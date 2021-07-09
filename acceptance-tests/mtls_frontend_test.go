package acceptance_tests

import (
	"crypto/tls"
	"fmt"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

var _ = Describe("mTLS", func() {
	var haproxyInfo haproxyInfo
	var closeTunnel func()
	var closeLocalServer func()

	haproxyBackendPort := 12000
	opsfileMTLS := `---
# Configure CA and cert chain
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/crt_list?
  value:
  - snifilter:
    - a.haproxy.internal
    client_ca_file: ((client_a_ca.certificate))
    verify: optional
    ssl_pem:
      cert_chain: ((https_frontend.certificate))((https_frontend_ca.certificate))
      private_key: ((https_frontend.private_key))
  - snifilter:
    - b.haproxy.internal
    client_ca_file: ((client_b_ca.certificate))
    verify: required
    ssl_pem:
      cert_chain: ((https_frontend.certificate))((https_frontend_ca.certificate))
      private_key: ((https_frontend.private_key))
# Declare server certs
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
      common_name: a.haproxy.internal
      alternative_names:
      - a.haproxy.internal
      - b.haproxy.internal
# Declare client certs
- type: replace
  path: /variables?/-
  value:
    name: client_a_ca
    type: certificate
    options:
      is_ca: true
      common_name: bosh
- type: replace
  path: /variables?/-
  value:
    name: client_a
    type: certificate
    options:
      ca: client_a_ca
      common_name: a.haproxy.internal
      alternative_names: [a.haproxy.internal]
      extended_key_usage: [client_auth]
- type: replace
  path: /variables?/-
  value:
    name: client_b_ca
    type: certificate
    options:
      is_ca: true
      common_name: bosh
- type: replace
  path: /variables?/-
  value:
    name: client_b
    type: certificate
    options:
      ca: client_b_ca
      common_name: b.haproxy.internal
      alternative_names: [b.haproxy.internal]
      extended_key_usage: [client_auth]
`

	var creds struct {
		HTTPSFrontend struct {
			Certificate string `yaml:"certificate"`
			PrivateKey  string `yaml:"private_key"`
			CA          string `yaml:"ca"`
		} `yaml:"https_frontend"`
		ClientA struct {
			Certificate string `yaml:"certificate"`
			PrivateKey  string `yaml:"private_key"`
		} `yaml:"client_a"`
		ClientB struct {
			Certificate string `yaml:"certificate"`
			PrivateKey  string `yaml:"private_key"`
		} `yaml:"client_b"`
	}

	BeforeEach(func() {
		var varsStoreReader varsStoreReader
		haproxyInfo, varsStoreReader = deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        defaultDeploymentName,
		}, []string{opsfileMTLS}, map[string]interface{}{}, true)

		err := varsStoreReader(&creds)
		Expect(err).NotTo(HaveOccurred())

		var localPort int
		closeLocalServer, localPort = startDefaultTestServer()
		closeTunnel = setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
	})

	AfterEach(func() {
		if closeLocalServer != nil {
			defer closeLocalServer()
		}
		if closeTunnel != nil {
			defer closeTunnel()
		}
	})

	It("Correctly terminates mTLS requests", func() {
		clientCertA, err := tls.X509KeyPair([]byte(creds.ClientA.Certificate), []byte(creds.ClientA.PrivateKey))
		Expect(err).NotTo(HaveOccurred())

		addressMap := map[string]string{
			"a.haproxy.internal:443": fmt.Sprintf("%s:443", haproxyInfo.PublicIP),
			"b.haproxy.internal:443": fmt.Sprintf("%s:443", haproxyInfo.PublicIP),
		}

		httpClientA := buildHTTPClient([]string{creds.HTTPSFrontend.CA}, addressMap, []tls.Certificate{clientCertA}, "")

		clientCertB, err := tls.X509KeyPair([]byte(creds.ClientB.Certificate), []byte(creds.ClientB.PrivateKey))
		Expect(err).NotTo(HaveOccurred())

		httpClientB := buildHTTPClient([]string{creds.HTTPSFrontend.CA}, addressMap, []tls.Certificate{clientCertB}, "")

		httpClientNonMTLS := buildHTTPClient([]string{creds.HTTPSFrontend.CA}, addressMap, []tls.Certificate{}, "")

		By("Using client A cert with endpoint A works")
		expectTestServer200(httpClientA.Get("https://a.haproxy.internal"))

		By("Using client B cert with endpoint B works")
		expectTestServer200(httpClientB.Get("https://b.haproxy.internal"))

		By("Using client B cert with endpoint A is not allowed")
		_, err = httpClientB.Get("https://a.haproxy.internal")
		expectTLSUnknownCertificateAuthorityErr(err)

		By("Using client A cert with endpoint B is not allowed")
		_, err = httpClientA.Get("https://b.haproxy.internal")
		expectTLSUnknownCertificateAuthorityErr(err)

		By("Making a non-mTLS request to an endpoint with optional mTLS works")
		expectTestServer200(httpClientNonMTLS.Get("https://a.haproxy.internal"))

		By("Making a non-mTLS request to an endpoint with required mTLS fails")
		_, err = httpClientNonMTLS.Get("https://b.haproxy.internal")
		expectTLSHandshakeFailureErr(err)
	})
})
