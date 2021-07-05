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
      common_name: ((cert_common_name))
      alternative_names: ((cert_sans))
`

	var creds struct {
		HTTPSFrontend struct {
			Certificate string `yaml:"certificate"`
			PrivateKey  string `yaml:"private_key"`
			CA          string `yaml:"ca"`
		} `yaml:"https_frontend"`
		HTTPSFrontendCA struct {
			Certificate string `yaml:"certificate"`
			PrivateKey  string `yaml:"private_key"`
		} `yaml:"https_frontend_ca"`
	}

	It("Disables domain fronting", func() {
		haproxyBackendPort := 12000
		haproxyInfo, varsStoreReader := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        defaultDeploymentName,
		}, []string{opsfile}, map[string]interface{}{
			"cert_common_name": "haproxy.internal",
			"cert_sans":        []string{"haproxy.internal"},
		}, true)

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

		By("Sending a request to HAProxy with a matching Host header it returns a 200 as normal")
		req, err = http.NewRequest("GET", "https://haproxy.internal", nil)
		Expect(err).NotTo(HaveOccurred())
		req.Host = "haproxy.internal"
		resp, err = httpClient.Do(req)
		Expect(err).NotTo(HaveOccurred())

		Expect(resp.StatusCode).To(Equal(http.StatusOK))
		Eventually(gbytes.BufferReader(resp.Body)).Should(gbytes.Say("Hello cloud foundry"))

		By("Sending a request to HAProxy with a matching Host header including the optional port it returns a 200 as normal")
		req, err = http.NewRequest("GET", "https://haproxy.internal", nil)
		Expect(err).NotTo(HaveOccurred())
		req.Host = "haproxy.internal:443"

		resp, err = httpClient.Do(req)
		Expect(err).NotTo(HaveOccurred())

		Expect(resp.StatusCode).To(Equal(http.StatusOK))
		Eventually(gbytes.BufferReader(resp.Body)).Should(gbytes.Say("Hello cloud foundry"))

		By("Sending a request to HAProxy with no SNI it returns a 200, regardless of host header")
		haproxyIP := haproxyInfo.PublicIP

		// Requests that use an IP rather than a hostname do not send an SNI.
		// However the IP of HAProxy is not known until deploy time.
		// After the first deploy, BOSH won't change the IP, so we will now
		// redeploy and update the cert to include the IP
		haproxyInfo, varsStoreReader = deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        defaultDeploymentName,
		}, []string{opsfile}, map[string]interface{}{
			// Update cert to include public IP
			"cert_common_name": haproxyIP,
			"cert_sans":        []string{haproxyIP, "haproxy.internal"},
			// Keep previous CA so we can re-use HTTP client
			"https_frontend_ca": map[string]string{
				"certificate": creds.HTTPSFrontendCA.Certificate,
				"private_key": creds.HTTPSFrontendCA.PrivateKey,
			},
		}, true)

		err = varsStoreReader(&creds)
		Expect(err).NotTo(HaveOccurred())

		// Confirm IP has not changed
		Expect(haproxyInfo.PublicIP).To(Equal(haproxyIP))

		req, err = http.NewRequest("GET", fmt.Sprintf("https://%s", haproxyIP), nil)
		Expect(err).NotTo(HaveOccurred())

		// Although we are using a 'spoofed' host header here, HAProxy
		// should not care as there is no SNI in the request
		req.Host = "spoof.internal"

		resp, err = httpClient.Do(req)
		Expect(err).NotTo(HaveOccurred())
		Expect(resp.StatusCode).To(Equal(http.StatusOK))
	})
})
