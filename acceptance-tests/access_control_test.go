package acceptance_tests

import (
	"errors"
	"fmt"
	"io"
	"net/http"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

/*
	Test strategy:
		* Use an SSH tunnel to make requests to HAProxy that appear to come from 127.0.0.1
		* Requests directly from test runner on Concourse appear to come from 10.0.0.0/8
		We can test whitelisting and blacklisting by using these CIDRs
*/
var _ = Describe("Access Control", func() {
	opsfileWhitelist := `---
# Enable CIDR whitelist
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/cidr_whitelist?
  value: ((cidr_whitelist))
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/block_all?
  value: true
`
	opsfileBlacklist := `---
# Enable CIDR blacklist
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/cidr_blacklist?
  value: ((cidr_blacklist))
`

	It("Allows IPs in whitelisted CIDRS", func() {
		haproxyBackendPort := 12000

		// Allow 127.0.0.1/32, but deny other connections
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    12000,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        defaultDeploymentName,
		}, []string{opsfileWhitelist}, map[string]interface{}{
			"cidr_whitelist": []string{"127.0.0.1/32"},
		}, true)

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeBackendTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeBackendTunnel()

		// Set up a tunnel so that requests to localhost:11000 appear to come from 127.0.0.1
		// on the HAProxy VM as this is now whitelisted
		closeFrontendTunnel := setupTunnelFromLocalMachineToHAProxy(haproxyInfo, 11000, 80)
		defer closeFrontendTunnel()

		By("Denying access from non-whitelisted CIDRs (request from test runner)")
		_, err := http.Get(fmt.Sprintf("http://%s", haproxyInfo.PublicIP))
		Expect(err).To(HaveOccurred())
		Expect(errors.Is(err, io.EOF)).To(BeTrue())

		By("Allowing access to whitelisted CIDRs (request from 127.0.0.1 on HAProxy VM)")
		resp, err := http.Get("http://127.0.0.1:11000")
		Expect(err).NotTo(HaveOccurred())
		Expect(resp.StatusCode).To(Equal(http.StatusOK))
	})

	It("Rejects IPs in blacklisted CIDRS", func() {
		haproxyBackendPort := 12000

		// Allow 127.0.0.1/32, but deny other connections
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    12000,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        defaultDeploymentName,
		}, []string{opsfileBlacklist}, map[string]interface{}{
			// traffic from test runner appears to come from this CIDR block
			"cidr_blacklist": []string{"10.0.0.0/8"},
		}, true)

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeBackendTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeBackendTunnel()

		// Set up a tunnel so that requests to localhost:11000 appear to come from 127.0.0.1
		// on the HAProxy VM as this is now blacklisted
		closeFrontendTunnel := setupTunnelFromLocalMachineToHAProxy(haproxyInfo, 11000, 80)
		defer closeFrontendTunnel()

		By("Denying access from blacklisted CIDRs (request from test runner)")
		_, err := http.Get(fmt.Sprintf("http://%s", haproxyInfo.PublicIP))
		Expect(err).To(HaveOccurred())
		Expect(errors.Is(err, io.EOF)).To(BeTrue())

		By("Allowing access to non-blacklisted CIDRs (request from 127.0.0.1 on HAProxy VM)")
		resp, err := http.Get("http://127.0.0.1:11000")
		Expect(err).NotTo(HaveOccurred())
		Expect(resp.StatusCode).To(Equal(http.StatusOK))
	})
})
