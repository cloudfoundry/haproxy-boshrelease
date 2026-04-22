package acceptance_tests

import (
	"fmt"
	"net/http"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Socket Rate Limiting", func() {
	It("enforces socket rate limits as configured", func() {
		socketLimit := 3
		opsfileSocketRateLimit := fmt.Sprintf(`---
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/socket_rate_limit?/sockets
  value: %d
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/socket_rate_limit/window_size?
  value: 10s
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/socket_rate_limit/table_size?
  value: 100
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/socket_rate_limit/block?
  value: true
`, socketLimit)

		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileSocketRateLimit}, map[string]interface{}{}, true)

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		testRequestCount := int(float64(socketLimit) * 1.5)
		firstFailure := -1
		successfulRequestCount := 0
		for i := 0; i < testRequestCount; i++ {
			rt := &http.Transport{
				DisableKeepAlives: true,
			}
			client := &http.Client{Transport: rt}
			resp, err := client.Get(fmt.Sprintf("http://%s/foo", haproxyInfo.PublicIP))
			if err == nil {
				if resp.StatusCode == 200 {
					successfulRequestCount++
					continue
				}
			}
			if firstFailure == -1 {
				firstFailure = i
			}
		}

		By("The first socket should fail after we've sent the amount of requests specified in the Socket Rate Limit")
		Expect(firstFailure).To(Equal(socketLimit))
		By("The total amount of successful sockets per time window should equal the Socket Rate Limit")
		Expect(successfulRequestCount).To(Equal(socketLimit))
	})
})
