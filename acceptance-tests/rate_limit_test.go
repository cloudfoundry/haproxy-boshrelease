package acceptance_tests

import (
	"fmt"
	"net/http"
	"strings"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Rate-Limiting", func() {
	It("Connections/Requests aren't blocked when block config isn't set", func() {
		rateLimit := 5
		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{
			requestsRateLimitOps(rateLimit, false),
			connectionsRateLimitOps(rateLimit, false, nil),
		}, map[string]interface{}{}, true)

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

		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{requestsRateLimitOps(requestLimit, true)}, map[string]interface{}{}, true)

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
		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{connectionsRateLimitOps(connLimit, true, nil)}, map[string]interface{}{}, true)

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

	It("Excluded CIDRs are never connection rate-limited", func() {
		connLimit := 5
		// exclude_cidrs covers all IPv4 sources so the test runner's egress IP is
		// guaranteed to match, proving the negated reject rule lets excluded sources through
		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{connectionsRateLimitOps(connLimit, true, []string{"0.0.0.0/0"})}, map[string]interface{}{}, true)

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		By("Sending more connections than the limit, expecting none to be blocked because the source is excluded")
		testRequestCount := connLimit * 3
		for i := 0; i < testRequestCount; i++ {
			rt := &http.Transport{
				DisableKeepAlives: true,
			}
			client := &http.Client{Transport: rt}
			resp, err := client.Get(fmt.Sprintf("http://%s/foo", haproxyInfo.PublicIP))
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
		}
	})

	It("Connection Based Limiting Works with Proxy Protocol enabled", func() {
		connLimit := 5
		opsfileAcceptProxy := `---
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/accept_proxy?
  value: true
`

		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{
			opsfileAcceptProxy,
			connectionsRateLimitOps(connLimit, true, nil),
		}, map[string]interface{}{}, true)

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
		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{
			requestsRateLimitOps(requestLimit, true),
			connectionsRateLimitOps(connLimit, true, nil),
		}, map[string]interface{}{}, true)

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
		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{connectionsRateLimitOps(connLimit, true, nil)}, map[string]interface{}{}, true)

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		By("Verifying proc.connections_rate_limit_connections is initialised from manifest value")
		output := runHAProxySocketCommand(haproxyInfo, "get var proc.connections_rate_limit_connections")
		Expect(output).To(ContainSubstring(fmt.Sprintf("%d", connLimit)))

		By("Verifying proc.connections_rate_limit_block is initialised as true from manifest block: true")
		output = runHAProxySocketCommand(haproxyInfo, "get var proc.connections_rate_limit_block")
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
		runHAProxySocketCommand(haproxyInfo, fmt.Sprintf("experimental-mode on; set var proc.connections_rate_limit_connections int(%d)", newLimit))

		By("Verifying the override is reflected via get var")
		output = runHAProxySocketCommand(haproxyInfo, "get var proc.connections_rate_limit_connections")
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
})

// requestsRateLimitOps builds an opsfile fragment configuring the requests_rate_limit properties.
func requestsRateLimitOps(requests int, block bool) string {
	return fmt.Sprintf(`---
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/requests_rate_limit?/requests
  value: %d
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/requests_rate_limit/window_size?
  value: 10s
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/requests_rate_limit/table_size?
  value: 1k
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/requests_rate_limit/block?
  value: %t
`, requests, block)
}

// connectionsRateLimitOps builds an opsfile fragment configuring the connections_rate_limit properties.
func connectionsRateLimitOps(connections int, block bool, excludeCIDRs []string) string {
	quotedCIDRs := make([]string, len(excludeCIDRs))
	for i, cidr := range excludeCIDRs {
		quotedCIDRs[i] = fmt.Sprintf("%q", cidr)
	}
	return fmt.Sprintf(`---
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/connections_rate_limit?/connections
  value: %d
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/connections_rate_limit/window_size?
  value: 10s
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/connections_rate_limit/table_size?
  value: 1k
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/connections_rate_limit/block?
  value: %t
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/connections_rate_limit/exclude_cidrs?
  value: [%s]
`, connections, block, strings.Join(quotedCIDRs, ", "))
}
