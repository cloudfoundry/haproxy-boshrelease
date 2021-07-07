package acceptance_tests

import (
	"fmt"
	"net/http"

	. "github.com/onsi/ginkgo"
)

var _ = Describe("TCP Frontend", func() {
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
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    12000,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        defaultDeploymentName,
		}, []string{opsfileTCP}, map[string]interface{}{
			"tcp_frontend_port": tcpFrontendPort,
			"tcp_backend_port":  tcpBackendPort,
		}, true)

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, tcpBackendPort, localPort)
		defer closeTunnel()

		By("Sending a request to the HAProxy TCP endpoint")
		expectTestServer200(http.Get(fmt.Sprintf("http://%s:%d", haproxyInfo.PublicIP, tcpFrontendPort)))
	})
})
