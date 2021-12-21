package acceptance_tests

import (
	"crypto/tls"
	"fmt"
	"net/http"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

var _ = Describe("Backend match HTTP protocol", func() {
	var haproxyInfo haproxyInfo
	var closeTunnel func()
	var closeLocalServer func()
	var http1Client *http.Client
	var http2Client *http.Client

	haproxyBackendPort := 12000
	opsfileHTTPS := `---
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/backend_ssl?
  value: verify
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/backend_ca_file?
  value: ((https_backend.ca))
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/backend_match_http_protocol?
  value: true
# Configure CA and cert chain
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/crt_list?/-
  value:
    snifilter:
    - haproxy.internal
    ssl_pem:
      cert_chain: ((https_frontend.certificate))((default_ca.certificate))
      private_key: ((https_frontend.private_key))
    alpn: ['h2', 'http/1.1']
# Declare certs
- type: replace
  path: /variables?/-
  value:
    name: default_ca
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
      ca: default_ca
      common_name: haproxy.internal
      alternative_names: [haproxy.internal]
- type: replace
  path: /variables?/-
  value:
    name: https_backend
    type: certificate
    options:
      ca: default_ca
      common_name: 127.0.0.1
      alternative_names: [127.0.0.1]
`

	var creds struct {
		HTTPSFrontend struct {
			Certificate string `yaml:"certificate"`
			PrivateKey  string `yaml:"private_key"`
			CA          string `yaml:"ca"`
		} `yaml:"https_frontend"`
		HTTPSBackend struct {
			Certificate string `yaml:"certificate"`
			PrivateKey  string `yaml:"private_key"`
			CA          string `yaml:"ca"`
		} `yaml:"https_backend"`
	}

	JustBeforeEach(func() {
		var varsStoreReader varsStoreReader
		haproxyInfo, varsStoreReader = deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileHTTPS}, map[string]interface{}{}, true)

		err := varsStoreReader(&creds)
		Expect(err).NotTo(HaveOccurred())

		// Build backend server that supports HTTP2 and HTTP1.1
		backendTLSCert, err := tls.X509KeyPair([]byte(creds.HTTPSBackend.Certificate), []byte(creds.HTTPSBackend.PrivateKey))
		Expect(err).NotTo(HaveOccurred())

		backendTLSConfig := &tls.Config{
			Certificates: []tls.Certificate{backendTLSCert},
			MinVersion:   tls.VersionTLS12,
			MaxVersion:   tls.VersionTLS12,
			NextProtos:   []string{"h2", "http/1.1"},
		}

		var localPort int
		closeLocalServer, localPort, err = startLocalHTTPServer(backendTLSConfig, func(w http.ResponseWriter, r *http.Request) {
			writeLog("Backend server handling incoming request")
			protocolHeaderValue := "none"
			if r.TLS != nil {
				protocolHeaderValue = r.TLS.NegotiatedProtocol
			}
			w.Header().Add("X-BACKEND-ALPN-PROTOCOL", protocolHeaderValue)
			w.Header().Add("X-BACKEND-PROTO", r.Proto)
			_, _ = w.Write([]byte("OK"))
		})
		Expect(err).NotTo(HaveOccurred())
		closeTunnel = setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)

		addresses := map[string]string{
			"haproxy.internal:443": fmt.Sprintf("%s:443", haproxyInfo.PublicIP),
		}

		http1Client = buildHTTPClient([]string{creds.HTTPSFrontend.CA}, addresses, []tls.Certificate{}, "")
		http2Client = buildHTTP2Client([]string{creds.HTTPSFrontend.CA}, addresses, []tls.Certificate{})
	})

	Context("When backend_match_http_protocol is true", func() {
		It("uses the same backend protocol as was used for the frontend connection", func() {
			resp, err := http1Client.Get("https://haproxy.internal:443")
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(200))

			// Frontend request HTTP1.1
			Expect(resp.Proto).To(Equal("HTTP/1.1"))
			Expect(resp.TLS.NegotiatedProtocol).To(Equal(""))

			// Backend request HTTP1.1
			Expect(resp.Header.Get("X-BACKEND-PROTO")).To((Equal("HTTP/1.1")))
			Expect(resp.Header.Get("X-BACKEND-ALPN-PROTOCOL")).To((Equal("http/1.1")))

			resp, err = http2Client.Get("https://haproxy.internal:443")
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(200))

			// Frontend request HTTP2
			Expect(resp.Proto).To(Equal("HTTP/2.0"))
			Expect(resp.TLS.NegotiatedProtocol).To(Equal("h2"))

			// Backend request HTTP2
			Expect(resp.Header.Get("X-BACKEND-PROTO")).To((Equal("HTTP/2.0")))
			Expect(resp.Header.Get("X-BACKEND-ALPN-PROTOCOL")).To(Equal("h2"))
		})
	})

	AfterEach(func() {
		if closeLocalServer != nil {
			defer closeLocalServer()
		}
		if closeTunnel != nil {
			defer closeTunnel()
		}
	})
})
