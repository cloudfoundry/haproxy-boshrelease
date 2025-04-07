package acceptance_tests

import (
	"crypto/tls"
	"fmt"
	"net/http"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Headers", func() {
	opsfileHeaders := `---
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/strip_headers?
  value: ["Custom-Header-To-Delete", "Custom-Header-To-Replace"]
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/headers?
  value: 
    Custom-Header-To-Add: add-value
    Custom-Header-To-Replace: replace-value
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
	var closeLocalServer func()
	var closeTunnel func()
	var creds struct {
		HTTPSFrontend struct {
			Certificate string `yaml:"certificate"`
			PrivateKey  string `yaml:"private_key"`
			CA          string `yaml:"ca"`
		} `yaml:"https_frontend"`
	}
	var client *http.Client
	var recordedHeaders http.Header
	var request *http.Request
	var err error

	BeforeEach(func() {
		haproxyBackendPort := 12000
		var varsStoreReader varsStoreReader
		haproxyInfo, varsStoreReader := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileHeaders}, map[string]interface{}{}, true)

		err = varsStoreReader(&creds)
		Expect(err).NotTo(HaveOccurred())

		By("Starting a local http server to act as a backend")
		var localPort int
		closeLocalServer, localPort, err = startLocalHTTPServer(nil, func(w http.ResponseWriter, r *http.Request) {
			writeLog("Backend server handling incoming request")
			recordedHeaders = r.Header
			_, _ = w.Write([]byte("OK"))
		})
		Expect(err).NotTo(HaveOccurred())

		closeTunnel = setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		client = buildHTTPClient(
			[]string{creds.HTTPSFrontend.CA},
			map[string]string{"haproxy.internal:443": fmt.Sprintf("%s:443", haproxyInfo.PublicIP)},
			[]tls.Certificate{}, "",
		)
	})

	AfterEach(func() {
		closeLocalServer()
		closeTunnel()
	})

	It("Adds, replaces and strips headers correctly", func() {
		request, err = http.NewRequest("GET", "https://haproxy.internal:443", nil)
		Expect(err).NotTo(HaveOccurred())

		// These headers are sent to HAProxy during the test
		headersToSend := map[string]string{
			"Custom-Header-To-Replace": "old-value",
			"Custom-Header-To-Delete":  "some-value",
		}

		for key, value := range headersToSend {
			request.Header.Set(key, value)
		}

		// These headers are expected to be removed by HAProxy,
		// as the header keys are defined in 'strip_headers' (see `opsfileHeaders`).
		headerKeysNotToExpect := []string{"Custom-Header-To-Delete"}

		// These headers are expected to be set by HAProxy,
		// as they are defined in 'headers' (see `opsfileHeaders`).
		headersWithKeysToExpect := map[string]string{
			"Custom-Header-To-Add":     "add-value",
			"Custom-Header-To-Replace": "replace-value",
		}

		// These headers are expected to be set by HAProxy with another value,
		// as they are defined in 'strip_headers' and `headers` (see `opsfileHeaders`).
		headersWithKeysNotToExpect := map[string]string{
			"Custom-Header-To-Replace": "old-value",
		}

		By("Gets successful request")
		resp, err := client.Do(request)
		expect200(resp, err)

		By("Correctly removes headers in 'strip_headers'")
		for headerKey := range headerKeysNotToExpect {
			Expect(recordedHeaders).NotTo(HaveKey(headerKey))
		}

		By("Correctly adds headers in 'headers'")
		for headerKey, headerValue := range headersWithKeysToExpect {
			Expect(recordedHeaders).To(HaveKey(headerKey))
			Expect(recordedHeaders[headerKey]).To(ContainElements(headerValue))
		}

		By("Correctly replaces the value in 'strip_headers' when 'headers' with same key is present")
		for headerKey, headerValue := range headersWithKeysNotToExpect {
			Expect(recordedHeaders).To(HaveKey(headerKey))
			Expect(recordedHeaders[headerKey]).NotTo(ContainElements(headerValue))
		}

	})

})
