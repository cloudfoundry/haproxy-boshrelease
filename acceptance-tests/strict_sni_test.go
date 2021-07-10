package acceptance_tests

import (
	"context"
	"crypto/tls"
	"fmt"
	"net/http"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

var _ = Describe("Strict SNI", func() {
	opsfile := `---
# Strict SNI
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/strict_sni?
  value: ((strict_sni))
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
			Certificate string `yaml:"certificate" json:"certificate"`
			PrivateKey  string `yaml:"private_key" json:"private_key"`
			CA          string `yaml:"ca" json:"ca"`
		} `yaml:"https_frontend" json:"https_frontend"`
		HTTPSFrontendCA struct {
			Certificate string `yaml:"certificate" json:"certificate"`
			PrivateKey  string `yaml:"private_key" json:"private_key"`
		} `yaml:"https_frontend_ca" json:"https_frontend_ca"`
	}
	var closeLocalServer func()
	var closeSSHTunnel context.CancelFunc
	var httpClient *http.Client
	var httpClientNoSNI *http.Client
	var httpClientWrongSNI *http.Client
	var strictSNI bool

	AfterEach(func() {
		if closeLocalServer != nil {
			defer closeLocalServer()
		}

		if closeSSHTunnel != nil {
			defer closeSSHTunnel()
		}
	})

	JustBeforeEach(func() {
		haproxyBackendPort := 12000
		haproxyInfo, varsStoreReader := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        defaultDeploymentName,
		}, []string{opsfile}, map[string]interface{}{
			"cert_common_name": "haproxy.internal",
			"cert_sans":        []string{"haproxy.internal"},
			"strict_sni":       strictSNI,
		}, true)

		var localPort int
		closeLocalServer, localPort = startDefaultTestServer()
		closeSSHTunnel = setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)

		err := varsStoreReader(&creds)
		Expect(err).NotTo(HaveOccurred())

		addressMap := map[string]string{
			"haproxy.internal:443": fmt.Sprintf("%s:443", haproxyInfo.PublicIP),
		}

		httpClient = buildHTTPClient([]string{creds.HTTPSFrontend.CA}, addressMap, []tls.Certificate{}, "")
		httpClientNoSNI = buildHTTPClient([]string{creds.HTTPSFrontend.CA}, addressMap, []tls.Certificate{}, "1.2.3.4")
		httpClientWrongSNI = buildHTTPClient([]string{creds.HTTPSFrontend.CA}, addressMap, []tls.Certificate{}, "spoof.internal")
	})

	Context("When strict_sni is false", func() {
		BeforeEach(func() {
			strictSNI = false
		})

		It("Ignores the SNI", func() {
			By("Sending a request to HAProxy with the correct SNI is allowed")
			expectTestServer200(httpClient.Get("https://haproxy.internal"))

			By("Sending a request to HAProxy with no SNI is allowed")
			expectTestServer200(httpClientNoSNI.Get("https://haproxy.internal"))

			By("Sending a request to HAProxy with an incorrect SNI is allowed")
			expectTestServer200(httpClientWrongSNI.Get("https://haproxy.internal"))
		})
	})

	Context("When strict_sni is true", func() {
		BeforeEach(func() {
			strictSNI = true
		})

		It("Validates the SNI", func() {
			By("Sending a request to HAProxy with the correct SNI is allowed")
			expectTestServer200(httpClient.Get("https://haproxy.internal"))

			By("Sending a request to HAProxy with no SNI is forbidden")
			_, err := httpClientNoSNI.Get("https://haproxy.internal")
			expectTLSUnrecognizedNameErr(err)

			By("Sending a request to HAProxy with an incorrect SNI is forbidden")
			_, err = httpClientWrongSNI.Get("https://haproxy.internal")
			expectTLSHandshakeFailureErr(err)
		})
	})
})
