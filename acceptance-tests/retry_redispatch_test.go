package acceptance_tests

import (
	"fmt"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	"net/http"
)

var _ = Describe("Retry and Redispatch Tests", func() {
	var haproxyInfo haproxyInfo
	var closeTunnel []func()
	var closeLocalServer []func()

	enableRedispatch := false
	haproxyBackendPort := 12000
	haproxyBackendHealthPort := 8080
	opsfileRetry := `---
# Configure Redispatch
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/enable_redispatch?
  value: ((enable_redispatch))
# Configure Retries
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/retries?
  value: 2
# Enable backend http health check
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/backend_use_http_health?
  value: true
`

	JustBeforeEach(func() {
		haproxyInfo, _ = deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1", "127.0.0.2"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileRetry}, map[string]interface{}{
			"enable_redispatch": enableRedispatch,
		}, true)

		setupTunnel := func(ip string, backendPort int) {
			closeLocalServerFunc, localPort := startDefaultTestServer(withIP(ip))
			closeTunnelFunc := setupTunnelFromHaproxyIPToTestServerIP(haproxyInfo, ip, backendPort, ip, localPort)

			closeTunnel = append(closeTunnel, closeTunnelFunc)
			closeLocalServer = append(closeLocalServer, closeLocalServerFunc)
		}

		setupTunnel("127.0.0.1", haproxyBackendPort)
		setupTunnel("127.0.0.1", haproxyBackendHealthPort)

		setupTunnel("127.0.0.2", haproxyBackendHealthPort) // this backend seems healthy but does not respond to traffic
	})

	AfterEach(func() {
		for _, closeLocalServerFunc := range closeLocalServer {
			closeLocalServerFunc()
		}
		for _, closeTunnelFunc := range closeTunnel {
			closeTunnelFunc()
		}
	})

	Context("When ha_proxy.enable_redispatch is false (default)", func() {
		BeforeEach(func() {
			enableRedispatch = false
		})

		It("Does not redispatch by default", func() {
			By("Sending a request to broken backend results in a 503")

			Eventually(func() int {
				resp, err := http.Get(fmt.Sprintf("http://%s", haproxyInfo.PublicIP))
				Expect(err).NotTo(HaveOccurred())
				return resp.StatusCode
			}).Should(Equal(http.StatusServiceUnavailable))
		})
	})
	Context("When ha_proxy.enable_redispatch is true", func() {
		BeforeEach(func() {
			enableRedispatch = true
		})

		It("Does redispatch to other backends", func() {
			By("Sending a request to broken backend results in a 200 due to redispatch to working backend")

			Consistently(func() int {
				resp, err := http.Get(fmt.Sprintf("http://%s", haproxyInfo.PublicIP))
				Expect(err).NotTo(HaveOccurred())
				return resp.StatusCode
			}).Should(Equal(http.StatusOK))
		})
	})
})
