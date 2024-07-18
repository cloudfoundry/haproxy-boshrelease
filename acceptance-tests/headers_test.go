package acceptance_tests

import (
	"crypto/tls"
	"fmt"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	"net/http"
)

var _ = Describe("headers", func() {
	opsfileHeaders := `---
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/strip_headers?
  value: ["Custom-Header-To-Delete", "Custom-Header-To-Replace"]
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/headers?
  value: 
    Custom-Header-To-Add: my-custom-header
    Custom-Header-To-Replace: header-value
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

	// These headers will be forwarded, overwritten or deleted
	incomingRequestHeaders := map[string]string{
		"Custom-Header-To-Delete":  "custom-header",
		"custom-header-to-replace": "custom-header-2",
	}

	// These headers will be added
	additionalRequestHeaders := map[string]string{
		"Custom-Header-To-Add":     "my-custom-header",
		"Custom-Header-To-Replace": "header-value",
	}

	It("Check correct headers handling", func() {
		haproxyBackendPort := 12000
		var varsStoreReader varsStoreReader
		haproxyInfo, varsStoreReader := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileHeaders}, map[string]interface{}{}, true)

		err := varsStoreReader(&creds)
		Expect(err).NotTo(HaveOccurred())

		By("Starting a local http server to act as a backend")
		var localPort int
		closeLocalServer, localPort, err = startLocalHTTPServer(nil, func(w http.ResponseWriter, r *http.Request) {
			writeLog("Backend server handling incoming request")
			recordedHeaders = r.Header
			_, _ = w.Write([]byte("OK"))
		})
		Expect(err).NotTo(HaveOccurred())
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()
		client = buildHTTPClient(
			[]string{creds.HTTPSFrontend.CA},
			map[string]string{"haproxy.internal:443": fmt.Sprintf("%s:443", haproxyInfo.PublicIP)},
			[]tls.Certificate{}, "",
		)

		request, err = http.NewRequest("GET", "https://haproxy.internal:443", nil)
		Expect(err).NotTo(HaveOccurred())
		for key, value := range incomingRequestHeaders {
			request.Header.Set(key, value)
		}

		By("Gets successful request")
		resp, err := client.Do(request)
		expect200(resp, err)

		By("Correctly removes related headers")
		Expect(recordedHeaders).NotTo(HaveKey("Custom-Header-To-Delete"))

		By("Correctly adds related headers")
		Expect(recordedHeaders).To(HaveKey("Custom-Header-To-Add"))
		Expect(recordedHeaders["Custom-Header-To-Add"]).To(ContainElements(additionalRequestHeaders["Custom-Header-To-Add"]))

		By("Correctly replaces related headers")
		Expect(recordedHeaders["Custom-Header-To-Replace"]).NotTo(ContainElements(incomingRequestHeaders["custom-header-to-replace"]))
		Expect(recordedHeaders["Custom-Header-To-Replace"]).To(ContainElements(additionalRequestHeaders["Custom-Header-To-Replace"]))
	})
})
