package acceptance_tests

import (
	"fmt"
	"net/http"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

var _ = Describe("Rate-Limiting", func() {
	It("Request Based Limiting Works", func() {
		requestLimit := 5
		opsfileRequestRateLimit := fmt.Sprintf(`---
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/requests_rate_limit?/requests
  value: %d
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/requests_rate_limit/window_size?
  value: 10s
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/requests_rate_limit/table_size?
  value: 100
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/requests_rate_limit/block?
  value: true
`, requestLimit)

		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileRequestRateLimit}, map[string]interface{}{}, true)

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		testRequestCount := int(float64(requestLimit) * 1.5)
		firstFailure := -1
		successfulRequestCount := 0
		for i := 0; i < testRequestCount; i++ {
			resp, err := http.Get(fmt.Sprintf("http://%s/foo", haproxyInfo.PublicIP))
			Expect(err).NotTo(HaveOccurred())
			switch resp.StatusCode {
			case http.StatusOK:
				successfulRequestCount++
			case http.StatusTooManyRequests:
				if firstFailure == -1 {
					firstFailure = i
				}
			}
		}

		By("The first request should fail after we've sent the amount of requests specified in the Request Rate Limit")
		Expect(firstFailure).To(Equal(requestLimit))
		By("The total amount of successful requests per time window should equal the Request Rate Limit")
		Expect(successfulRequestCount).To(Equal(requestLimit))
	})

	It("Connection Based Limiting Works", func() { //TODO: remove focus
		connLimit := 5
		opsfileConnectionsRateLimit := fmt.Sprintf(`---
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/connections_rate_limit?/connections
  value: %d
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/connections_rate_limit/window_size?
  value: 100s
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/connections_rate_limit/table_size?
  value: 100
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/connections_rate_limit/block?
  value: true
`, connLimit)
		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileConnectionsRateLimit}, map[string]interface{}{}, true)

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		testRequestCount := int(float64(connLimit) * 1.5)
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

		By("The first connection should fail after we've sent the amount of requests specified in the Connection Rate Limit")
		Expect(firstFailure).To(Equal(connLimit))
		By("The total amount of successful connections per time window should equal the Connection Rate Limit")
		Expect(successfulRequestCount).To(Equal(connLimit))
	})

	It("Both types of rate limiting work in parallel", func() { //TODO: remove focus
		requestLimit := 5
		connLimit := 6  // needs to be higher than request limit for this test
		// connection based rate-limiting has priority over request based rate-limiting so we expect some sucesses, then one status 429 response, then no response at all
		opsfileConnectionsRateLimit := fmt.Sprintf(`---
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/requests_rate_limit?/requests
  value: %d
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/requests_rate_limit/window_size?
  value: 10s
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/requests_rate_limit/table_size?
  value: 100
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/requests_rate_limit/block?
  value: true
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/connections_rate_limit?/connections
  value: %d
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/connections_rate_limit/window_size?
  value: 100s
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/connections_rate_limit/table_size?
  value: 100
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/connections_rate_limit/block?
  value: true
`, requestLimit, connLimit)
		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileConnectionsRateLimit}, map[string]interface{}{}, true)

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		testRequestCount := int(float64(connLimit) * 1.5)
		By("Receiving successful responses until request limit is reached, then response status 429 until TCP connection limit is reached, then no response at all")
		for i := 0; i < testRequestCount; i++ {
			rt := &http.Transport{
				DisableKeepAlives: true,
			}
			client := &http.Client{Transport: rt}
			resp, err := client.Get(fmt.Sprintf("http://%s/foo", haproxyInfo.PublicIP))
			if i < requestLimit {
				// sucessful requests
				Expect(err).NotTo(HaveOccurred())
				Expect(resp.StatusCode).To(Equal(http.StatusOK))
			} else if i == requestLimit {
				// request limit reached --> 429 response
				Expect(err).NotTo(HaveOccurred())
				Expect(resp.StatusCode).To(Equal(http.StatusTooManyRequests))
			} else {
				// TCP connection limit reached --> no response
				Expect(err).To(HaveOccurred())
			}
		}
	})
})
