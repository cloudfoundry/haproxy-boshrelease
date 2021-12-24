package acceptance_tests

import (
	"fmt"
	"net/http"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

var _ = Describe("Regex-based ACLs", func() {
	It("Works", func() {
		opsfileRegexACLs := `---
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/frontend_config?
  value: |-
    acl is_regex_match url,debug -i -m reg foo
    http-request deny deny_status 429 if is_regex_match
    http-request deny deny_status 401 if ! is_regex_match
`
		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileRegexACLs}, map[string]interface{}{}, true)

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		By("Positive regex matches are working in ACLs")
		// path /foo should match '-m reg foo' ACL
		resp, err := http.Get(fmt.Sprintf("http://%s/foo", haproxyInfo.PublicIP))
		Expect(err).NotTo(HaveOccurred())
		Expect(resp.StatusCode).To(Equal(429))

		// path /bar should NOT match '-m reg foo' ACL
		By("Negative regex matches are working in ACLs")
		resp, err = http.Get(fmt.Sprintf("http://%s/bar", haproxyInfo.PublicIP))
		Expect(err).NotTo(HaveOccurred())
		Expect(resp.StatusCode).To(Equal(401))
	})
})
