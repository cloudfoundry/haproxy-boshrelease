package acceptance_tests

import (
	"fmt"
	"math/rand"
	"net/http"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("max_rewrite and buffer_size_bytes", func() {
	It("Allows HTTP requests as large as buffer_size_bytes - max_rewrite", func() {
		opsfileBufferSize := `---
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/max_rewrite?
  value: 4096
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/buffer_size_bytes?
  value: 71000
`
		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileBufferSize}, map[string]interface{}{}, true)

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		By("Sending a request to HAProxy with a 64kb header is allowed")
		// buffer_size_bytes is 71000 and max_rewrite is 4096.
		// buffer_size_bytes - max_rewrite = 71000 - 4096 = 66904
		// remaining buffer for the request which should leave plenty
		// of room for a request with a single 64kb header

		req, err := http.NewRequest("GET", fmt.Sprintf("http://%s", haproxyInfo.PublicIP), nil)
		Expect(err).NotTo(HaveOccurred())

		// ensure total header size (key+value) is 64kb
		req.Header.Set("X-Custom", string(randBytes(64*1024-len("X-Custom: "))))

		expectTestServer200(http.DefaultClient.Do(req))

		By("Sending a request to HAProxy with a 72kb header is not allowed")
		req, err = http.NewRequest("GET", fmt.Sprintf("http://%s", haproxyInfo.PublicIP), nil)
		Expect(err).NotTo(HaveOccurred())

		// ensure total header size (key+value) is 72k
		req.Header.Set("X-Custom", string(randBytes(72*1024-len("X-Custom: "))))

		expect431(http.DefaultClient.Do(req))
	})
})

var letters = []byte("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

func randBytes(n int) []byte {
	b := make([]byte, n)
	for i := range b {
		b[i] = letters[rand.Intn(len(letters))]
	}
	return b
}
