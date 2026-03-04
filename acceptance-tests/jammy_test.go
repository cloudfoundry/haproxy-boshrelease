package acceptance_tests

import (
	"fmt"
	"net/http"

	. "github.com/onsi/ginkgo/v2"
)

var _ = Describe("Jammy", func() {
	It("Correctly proxies HTTP requests when using the Jammy stemcell", func() {

		opsfileJammy := `---
# Configure Jammy stemcell
- type: replace
  path: /stemcells/alias=default/os
  value: ubuntu-jammy
`

		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileJammy}, map[string]interface{}{}, true)

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		By("Sending a request to HAProxy")
		expectTestServer200(http.Get(fmt.Sprintf("http://%s", haproxyInfo.PublicIP)))
	})
})
