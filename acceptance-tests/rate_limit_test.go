package acceptance_tests

import (
	"fmt"
	"net/http"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Rate-Limiting", func() {
	It("Connections/Requests aren't blocked when block config isn't set", func() {
		rateLimit := 5
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
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/connections_rate_limit?/connections
  value: %d
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/connections_rate_limit/window_size?
  value: 100s
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/connections_rate_limit/table_size?
  value: 100
`, rateLimit, rateLimit)
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

		By("Sending requests to test app, expecting none to be blocked")
		testRequestCount := int(float64(rateLimit) * 1.5)
		for i := 0; i < testRequestCount; i++ {
			rt := &http.Transport{
				DisableKeepAlives: true,
			}
			client := &http.Client{Transport: rt}
			resp, err := client.Get(fmt.Sprintf("http://%s/foo", haproxyInfo.PublicIP))
			// sucessful requests
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
		}
	})

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

	It("Connection Based Limiting Works", func() {
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

	It("Connection Based Limiting Works with Proxy Protocol enabled", func() {
		connLimit := 5
		opsfileConnRateLimitWithProxyProtocol := fmt.Sprintf(`---
# Enable Proxy Protocol
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/accept_proxy?
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
`, connLimit)

		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileConnRateLimitWithProxyProtocol}, map[string]interface{}{}, true)

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		By("Sending requests via Proxy Protocol, each on a new TCP connection, expecting connection rate limiting to apply")
		testRequestCount := int(float64(connLimit) * 1.5)
		firstFailure := -1
		successfulRequestCount := 0
		for i := 0; i < testRequestCount; i++ {
			err := performProxyProtocolRequest(haproxyInfo.PublicIP, 80, "/foo")
			if err == nil {
				successfulRequestCount++
			} else {
				if firstFailure == -1 {
					firstFailure = i
				}
			}
		}

		By("The first connection should fail after we've sent the amount of connections specified in the Connection Rate Limit")
		Expect(firstFailure).To(Equal(connLimit))
		By("The total amount of successful connections per time window should equal the Connection Rate Limit")
		Expect(successfulRequestCount).To(Equal(connLimit))
	})

	It("Both types of rate limiting work in parallel", func() {
		requestLimit := 5
		connLimit := 6 // needs to be higher than request limit for this test
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

	It("Connection Based Limiting works via manifest and can be overridden at runtime via socket", func() {
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

		By("Verifying proc.conn_rate_limit is initialised from manifest value")
		output := runHAProxySocketCommand(haproxyInfo, "get var proc.conn_rate_limit")
		Expect(output).To(ContainSubstring(fmt.Sprintf("%d", connLimit)))

		By("Verifying proc.conn_rate_block is initialised as true from manifest block: true")
		output = runHAProxySocketCommand(haproxyInfo, "get var proc.conn_rate_block")
		Expect(output).To(ContainSubstring("1"))

		By("Verifying connections are blocked after exceeding the manifest-configured limit")
		testRequestCount := int(float64(connLimit) * 1.5)
		firstFailure := -1
		successfulRequestCount := 0
		for i := 0; i < testRequestCount; i++ {
			rt := &http.Transport{DisableKeepAlives: true}
			client := &http.Client{Transport: rt}
			resp, err := client.Get(fmt.Sprintf("http://%s/foo", haproxyInfo.PublicIP))
			if err == nil && resp.StatusCode == 200 {
				resp.Body.Close()
				successfulRequestCount++
				continue
			}
			if err == nil {
				resp.Body.Close()
			}
			if firstFailure == -1 {
				firstFailure = i
			}
		}
		Expect(firstFailure).To(Equal(connLimit))
		Expect(successfulRequestCount).To(Equal(connLimit))

		By("Clearing stick table before overriding limit")
		runHAProxySocketCommand(haproxyInfo, "clear table st_tcp_conn_rate")

		By("Overriding the limit at runtime via socket to a higher value")
		newLimit := connLimit * 3
		runHAProxySocketCommand(haproxyInfo, fmt.Sprintf("experimental-mode on; set var proc.conn_rate_limit int(%d)", newLimit))

		By("Verifying the override is reflected via get var")
		output = runHAProxySocketCommand(haproxyInfo, "get var proc.conn_rate_limit")
		Expect(output).To(ContainSubstring(fmt.Sprintf("%d", newLimit)))

		By("Verifying connections are allowed up to the new higher socket-configured limit")
		testRequestCount = int(float64(newLimit) * 1.5)
		firstFailure = -1
		successfulRequestCount = 0
		for i := 0; i < testRequestCount; i++ {
			rt := &http.Transport{DisableKeepAlives: true}
			client := &http.Client{Transport: rt}
			resp, err := client.Get(fmt.Sprintf("http://%s/foo", haproxyInfo.PublicIP))
			if err == nil && resp.StatusCode == 200 {
				resp.Body.Close()
				successfulRequestCount++
				continue
			}
			if err == nil {
				resp.Body.Close()
			}
			if firstFailure == -1 {
				firstFailure = i
			}
		}
		Expect(firstFailure).To(Equal(newLimit))
		Expect(successfulRequestCount).To(Equal(newLimit))
	})

	It("Connection Based Limiting can be enabled and disabled at runtime via socket with manifest block false", func() {
		connLimit := 5
		// block: false in manifest — blocking is enabled/disabled at runtime via socket
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
  value: false
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

		By("Verifying proc.conn_rate_block is initialised as false from manifest block: false")
		output := runHAProxySocketCommand(haproxyInfo, "get var proc.conn_rate_block")
		Expect(output).To(ContainSubstring("0"))

		By("Enabling blocking at runtime via socket")
		runHAProxySocketCommand(haproxyInfo, "experimental-mode on; set var proc.conn_rate_block bool(true)")

		By("Verifying proc.conn_rate_block is now true")
		output = runHAProxySocketCommand(haproxyInfo, "get var proc.conn_rate_block")
		Expect(output).To(ContainSubstring("1"))

		By("Verifying connections are blocked after exceeding the limit")
		testRequestCount := int(float64(connLimit) * 1.5)
		firstFailure := -1
		successfulRequestCount := 0
		for i := 0; i < testRequestCount; i++ {
			rt := &http.Transport{DisableKeepAlives: true}
			client := &http.Client{Transport: rt}
			resp, err := client.Get(fmt.Sprintf("http://%s/foo", haproxyInfo.PublicIP))
			if err == nil && resp.StatusCode == 200 {
				resp.Body.Close()
				successfulRequestCount++
				continue
			}
			if err == nil {
				resp.Body.Close()
			}
			if firstFailure == -1 {
				firstFailure = i
			}
		}
		Expect(firstFailure).To(Equal(connLimit))
		Expect(successfulRequestCount).To(Equal(connLimit))

		By("Disabling blocking at runtime via socket")
		runHAProxySocketCommand(haproxyInfo, "experimental-mode on; set var proc.conn_rate_block bool(false)")

		By("Verifying proc.conn_rate_block is now false")
		output = runHAProxySocketCommand(haproxyInfo, "get var proc.conn_rate_block")
		Expect(output).To(ContainSubstring("0"))

		By("Clearing stick table to reset counters")
		runHAProxySocketCommand(haproxyInfo, "clear table st_tcp_conn_rate")

		By("Verifying all connections are now allowed after disabling blocking via socket")
		for i := 0; i < testRequestCount; i++ {
			rt := &http.Transport{DisableKeepAlives: true}
			client := &http.Client{Transport: rt}
			resp, err := client.Get(fmt.Sprintf("http://%s/foo", haproxyInfo.PublicIP))
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			resp.Body.Close()
		}
	})

	It("Connection Based Limiting works when limit is set entirely via socket without manifest connections property", func() {
		connLimit := 5
		// Only table_size and window_size are set — no connections or block in manifest
		// proc.conn_rate_block defaults to false, proc.conn_rate_limit must be set via socket
		opsfileConnectionsRateLimit := `---
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/connections_rate_limit?/window_size
  value: 100s
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/connections_rate_limit/table_size?
  value: 100
`
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

		By("Setting conn_rate_limit and enabling blocking entirely via socket")
		runHAProxySocketCommand(haproxyInfo, fmt.Sprintf("experimental-mode on; set var proc.conn_rate_limit int(%d)", connLimit))
		runHAProxySocketCommand(haproxyInfo, "experimental-mode on; set var proc.conn_rate_block bool(true)")

		By("Verifying proc.conn_rate_limit is set correctly via socket")
		output := runHAProxySocketCommand(haproxyInfo, "get var proc.conn_rate_limit")
		Expect(output).To(ContainSubstring(fmt.Sprintf("%d", connLimit)))

		By("Verifying proc.conn_rate_block is set correctly via socket")
		output = runHAProxySocketCommand(haproxyInfo, "get var proc.conn_rate_block")
		Expect(output).To(ContainSubstring("1"))

		By("Verifying connections are blocked after exceeding the socket-configured limit")
		testRequestCount := int(float64(connLimit) * 1.5)
		firstFailure := -1
		successfulRequestCount := 0
		for i := 0; i < testRequestCount; i++ {
			rt := &http.Transport{DisableKeepAlives: true}
			client := &http.Client{Transport: rt}
			resp, err := client.Get(fmt.Sprintf("http://%s/foo", haproxyInfo.PublicIP))
			if err == nil && resp.StatusCode == 200 {
				resp.Body.Close()
				successfulRequestCount++
				continue
			}
			if err == nil {
				resp.Body.Close()
			}
			if firstFailure == -1 {
				firstFailure = i
			}
		}
		Expect(firstFailure).To(Equal(connLimit))
		Expect(successfulRequestCount).To(Equal(connLimit))
	})
})
