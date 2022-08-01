package acceptance_tests

import (
	"fmt"
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"net/http"
	"time"
)

var _ = Describe("Drain Test", func() {
	opsfileDrainTimeout := `---
# Enable health check
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/enable_health_check_http?
  value: true
# Enable draining
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/drain_enable?
  value: true
# Set grace period to 10s
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/drain_frontend_grace_time?
  value: 10
# Set drain period to 10s
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/drain_timeout?
  value: 10
`
	It("Honors grace and drain periods", func() {
		backendDeploymentName := "haproxy-backend"
		// For this test we will use a second HAProxy as pre-existing healthy 'backend'
		haproxyBackendPort := 12000
		backendHaproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        backendDeploymentName,
		}, []string{}, map[string]interface{}{}, true)
		defer deleteDeployment(backendDeploymentName)

		closeLocalServer, backendLocalPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(backendHaproxyInfo, haproxyBackendPort, backendLocalPort)
		defer closeTunnel()

		// Now deploy test HAProxy with 'haproxy-backend' configured as backend
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    80,
			haproxyBackendServers: []string{backendHaproxyInfo.PublicIP},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileDrainTimeout}, map[string]interface{}{}, true)

		// Verify that instance is in a running state
		Expect(boshInstances(deploymentNameForTestNode())[0].ProcessState).To(Equal("running"))

		By("The healthcheck health endpoint should report a 200 status code")
		expect200(http.Get(fmt.Sprintf("http://%s:8080/health", haproxyInfo.PublicIP)))

		By("Sending a request to HAProxy works")
		expectTestServer200(http.Get(fmt.Sprintf("http://%s", haproxyInfo.PublicIP)))

		By("Draining HAproxy should first shut down health check, listeners still working")
		drainHAProxy(haproxyInfo)
		_, err := http.Get(fmt.Sprintf("http://%s:8080/health", haproxyInfo.PublicIP))
		expectConnectionRefusedErr(err)
		expectTestServer200(http.Get(fmt.Sprintf("http://%s", haproxyInfo.PublicIP)))
		time.Sleep(10 * time.Second)

		By("After grace period has passed, draining should set in, disabling listeners")
		_, err = http.Get(fmt.Sprintf("http://%s:8080/health", haproxyInfo.PublicIP))
		expectConnectionRefusedErr(err)
		_, err = http.Get(fmt.Sprintf("http://%s", haproxyInfo.PublicIP))
		expectConnectionRefusedErr(err)
	})
})
