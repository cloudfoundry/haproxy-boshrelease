package acceptance_tests

import (
	"fmt"
	"net/http"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/gbytes"
)

var _ = Describe("TCP Frontend", func() {
	AfterEach(func() {
		deleteDeployment()
	})

	It("Correctly proxies TCP requests", func() {
		opsfileTCP := `---
# Configure TCP Backend
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/tcp?/-
  value:
    backend_port: ((tcp_backend_port))
    port: ((tcp_frontend_port))
    backend_servers:
    - 127.0.0.1
    name: test
`
		tcpFrontendPort := 13000
		tcpBackendPort := 13001
		haproxyInfo, _ := deployHAProxy(12000, []string{opsfileTCP}, map[string]interface{}{
			"tcp_frontend_port": tcpFrontendPort,
			"tcp_backend_port":  tcpBackendPort,
		})

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, tcpBackendPort, localPort)
		defer closeTunnel()

		By("Sending a request to the HAProxy TCP endpoint")
		resp, err := http.Get(fmt.Sprintf("http://%s:%d", haproxyInfo.PublicIP, tcpFrontendPort))
		Expect(err).NotTo(HaveOccurred())
		Expect(resp.StatusCode).To(Equal(http.StatusOK))
		Eventually(gbytes.BufferReader(resp.Body)).Should(gbytes.Say("Hello cloud foundry"))
	})
})
