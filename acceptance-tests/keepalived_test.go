package acceptance_tests

import (
	"fmt"
	"net/http"

	. "github.com/onsi/ginkgo/v2"
)

var _ = Describe("keepalived", func() {
	It("Deploys haproxy with keepalived", func() {
		opsfileKeepalived := `---
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=keepalived?/release?
  value: haproxy
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=keepalived?/properties/keepalived/vip?
  value: 10.245.0.99
`
		keepalivedVIP := "10.245.0.99"
		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileKeepalived}, map[string]interface{}{}, true)
		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		By("Sending a request to HAProxy via keepalived virtual IP")
		expectTestServer200(http.Get(fmt.Sprintf("http://%s", keepalivedVIP)))
	})
})
