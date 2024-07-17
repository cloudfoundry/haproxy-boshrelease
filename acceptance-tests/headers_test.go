package acceptance_tests

import (
	"context"
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
  value: ["CustomHeaderToDelete", "CustomHeaderToReplace"]

- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/headers?
  value: 
    X-Application-ID: my-custom-header
    CustomHeaderToReplace: header-value
`
	var closeLocalServer func()
	var closeSSHTunnel context.CancelFunc
	var creds struct {
		HTTPSFrontend struct {
			Certificate string `yaml:"certificate"`
			PrivateKey  string `yaml:"private_key"`
			CA          string `yaml:"ca"`
		} `yaml:"https_frontend"`
	}
	var haproxyInfo haproxyInfo
	var deployVars map[string]interface{}
	var nonMTLSClient *http.Client
	var recordedHeaders http.Header
	var request *http.Request

	// These headers will be forwarded, overwritten or deleted
	incomingRequestHeaders := map[string]string{
		"CustomHeaderToDelete":  "custom-header",
		"CustomHeaderToReplace": "custom-header-2",
	}
	// These headers will be added
	additionalRequestHeaders := map[string]string{
		"X-Application-ID":      "my-custom-header",
		"CustomHeaderToReplace": "header-value",
	}

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
		var varsStoreReader varsStoreReader

		var err error

		haproxyInfo, varsStoreReader = deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileHeaders}, deployVars, true)

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

		closeSSHTunnel = setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)

		nonMTLSClient = buildHTTPClient(
			[]string{creds.HTTPSFrontend.CA},
			map[string]string{"haproxy.internal:443": fmt.Sprintf("%s:443", haproxyInfo.PublicIP)},
			[]tls.Certificate{}, "",
		)

		request, err = http.NewRequest("GET", "https://haproxy.internal:443", nil)
		Expect(err).NotTo(HaveOccurred())
		for key, value := range incomingRequestHeaders {
			request.Header.Set(key, value)
		}
	})

	Describe("When strip_headers are set", func() {
		It("Correctly removes the related strip headers", func() {
			resp, err := nonMTLSClient.Do(request)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			for key := range incomingRequestHeaders {
				Expect(recordedHeaders).NotTo(HaveKey(key))
			}
		})
	})
	Describe("When custom headers are set", func() {
		It("Correctly adds related headers", func() {
			resp, err := nonMTLSClient.Do(request)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			for key := range additionalRequestHeaders {
				Expect(recordedHeaders).To(HaveKey(key))
			}
		})
		It("Correctly replace header", func() {
			resp, err := nonMTLSClient.Do(request)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			for key := range additionalRequestHeaders {
				Expect(recordedHeaders).To(HaveKeyWithValue(key, additionalRequestHeaders[key]))
			}
		})
	})
})
