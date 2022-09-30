package acceptance_tests

import (
	"fmt"
	"net/http"

	. "github.com/onsi/ginkgo"
)

var _ = Describe("Bionic", func() {
	It("Correctly proxies HTTP requests when using the Bionic stemcell", func() {

		opsfileBionic := `---
# Configure Bionic stemcell
- type: replace
  path: /stemcells/alias=default/os
  value: ubuntu-bionic
`

		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileBionic}, map[string]interface{}{}, true)

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		By("Sending a request to HAProxy")
		expectTestServer200(http.Get(fmt.Sprintf("http://%s", haproxyInfo.PublicIP)))
	})
})
