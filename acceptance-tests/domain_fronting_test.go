package acceptance_tests

import (
	"crypto/tls"
	"fmt"
	"net/http"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/gbytes"
)

var _ = Describe("Domain fronting", func() {
	opsfile := `---
# Disable domain fronting
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/disable_domain_fronting?
  value: true
# Configure CA and cert chain
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/crt_list?/-
  value:
    snifilter:
    - haproxy.internal
    ssl_pem:
      cert_chain: ((https_frontend.certificate))((https_frontend_ca.certificate))
      private_key: ((https_frontend.private_key))
# Declare certs
- type: replace
  path: /variables?/-
  value:
    name: https_frontend_ca
    type: certificate
    options:
      is_ca: true
      common_name: bosh
- type: replace
  path: /variables?/-
  value:
    name: https_frontend
    type: certificate
    options:
      ca: https_frontend_ca
      common_name: haproxy.internal
      alternative_names: [haproxy.internal]
`

	var creds struct {
		HTTPSFrontend struct {
			Certificate string `yaml:"certificate"`
			PrivateKey  string `yaml:"private_key"`
			CA          string `yaml:"ca"`
		} `yaml:"https_frontend"`
	}

	It("Disables domain fronting", func() {
		haproxyBackendPort := 12000
		haproxyInfo, varsStoreReader := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        defaultDeploymentName,
		}, []string{opsfile}, map[string]interface{}{}, true)

		err := varsStoreReader(&creds)
		Expect(err).NotTo(HaveOccurred())

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		httpClient := buildHTTPClient(
			[]string{creds.HTTPSFrontend.CA},
			map[string]string{
				"haproxy.internal:443": fmt.Sprintf("%s:443", haproxyInfo.PublicIP),
			},
			[]tls.Certificate{},
		)

		By("Sending a request to HAProxy with a mismatched SNI and Host header it returns a 421")
		req, err := http.NewRequest("GET", "https://haproxy.internal", nil)
		Expect(err).NotTo(HaveOccurred())
		req.Host = "spoof.internal"

		resp, err := httpClient.Do(req)
		Expect(err).NotTo(HaveOccurred())
		Expect(resp.StatusCode).To(Equal(http.StatusMisdirectedRequest))

		By("Sending a request to HAProxy without a spoofed Host header it returns a 200 as normal")
		resp, err = httpClient.Get("https://haproxy.internal")
		Expect(err).NotTo(HaveOccurred())
		Expect(resp.StatusCode).To(Equal(http.StatusOK))
		Eventually(gbytes.BufferReader(resp.Body)).Should(gbytes.Say("Hello cloud foundry"))
	})
})
