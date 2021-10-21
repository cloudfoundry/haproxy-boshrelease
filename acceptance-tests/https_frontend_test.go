package acceptance_tests

import (
	"crypto/tls"
	"fmt"
	"net/http"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/gbytes"
)

var _ = Describe("HTTPS Frontend", func() {
	var haproxyInfo haproxyInfo
	var closeTunnel func()
	var closeLocalServer func()
	enableHTTP2 := false
	var http1Client *http.Client
	var http2Client *http.Client

	haproxyBackendPort := 12000
	opsfileHTTPS := `---
# Configure HTTP2
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/enable_http2?
  value: ((enable_http2))
# Configure CA and cert chain
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/crt_list?/-
  value:
    snifilter:
    - haproxy.internal
    ssl_pem:
      cert_chain: ((https_frontend.certificate))((https_frontend_ca.certificate))
      private_key: ((https_frontend.private_key))
# Configure CA and cert chain
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/crt_list?/-
  value:
    snifilter:
    - haproxy.h2.internal
    ssl_pem:
      cert_chain: ((https_frontend.certificate))((https_frontend_ca.certificate))
      private_key: ((https_frontend.private_key))
    alpn: ['h2']
# Configure CA and cert chain
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/crt_list?/-
  value:
    snifilter:
    - haproxy.http11.internal
    ssl_pem:
      cert_chain: ((https_frontend.certificate))((https_frontend_ca.certificate))
      private_key: ((https_frontend.private_key))
    alpn: ['http/1.1']
# Configure CA and cert chain
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/crt_list?/-
  value:
    snifilter:
    - haproxy.h2-http11.internal
    ssl_pem:
      cert_chain: ((https_frontend.certificate))((https_frontend_ca.certificate))
      private_key: ((https_frontend.private_key))
    alpn: ['h2', 'http/1.1']
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
      alternative_names: [haproxy.internal, haproxy.h2.internal, haproxy.http11.internal, haproxy.h2-http11.internal]
`

	var creds struct {
		HTTPSFrontend struct {
			Certificate string `yaml:"certificate"`
			PrivateKey  string `yaml:"private_key"`
			CA          string `yaml:"ca"`
		} `yaml:"https_frontend"`
	}

	JustBeforeEach(func() {
		var varsStoreReader varsStoreReader
		haproxyInfo, varsStoreReader = deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        defaultDeploymentName,
		}, []string{opsfileHTTPS}, map[string]interface{}{
			"enable_http2": enableHTTP2,
		}, true)

		err := varsStoreReader(&creds)
		Expect(err).NotTo(HaveOccurred())

		var localPort int
		closeLocalServer, localPort = startDefaultTestServer()
		closeTunnel = setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)

		addresses := map[string]string{
			"haproxy.internal:443":        fmt.Sprintf("%s:443", haproxyInfo.PublicIP),
			"haproxy.h2.internal:443":     fmt.Sprintf("%s:443", haproxyInfo.PublicIP),
			"haproxy.http11.internal:443": fmt.Sprintf("%s:443", haproxyInfo.PublicIP),
		}

		http1Client = buildHTTPClient([]string{creds.HTTPSFrontend.CA}, addresses, []tls.Certificate{}, "")
		http2Client = buildHTTP2Client([]string{creds.HTTPSFrontend.CA}, addresses, []tls.Certificate{})
	})

	AfterEach(func() {
		if closeLocalServer != nil {
			defer closeLocalServer()
		}
		if closeTunnel != nil {
			defer closeTunnel()
		}
	})

	It("Correctly proxies HTTPS requests with TLSv1.2 and 1.3", func() {
		By("Sending a request to HAProxy using HTTP 1.1 and TLSv1.2")

		http1Client.Transport.(*http.Transport).TLSClientConfig.MaxVersion = tls.VersionTLS12
		http1Client.Transport.(*http.Transport).TLSClientConfig.MinVersion = tls.VersionTLS12

		resp, err := http1Client.Get("https://haproxy.internal:443")
		Expect(err).NotTo(HaveOccurred())
		Expect(resp.ProtoMajor).To(Equal(1))

		Expect(resp.StatusCode).To(Equal(http.StatusOK))
		Eventually(gbytes.BufferReader(resp.Body)).Should(gbytes.Say("Hello cloud foundry"))

		By("Sending a request to HAProxy using HTTP 1.1 and TLSv1.3")

		http1Client.Transport.(*http.Transport).TLSClientConfig.MaxVersion = tls.VersionTLS13
		http1Client.Transport.(*http.Transport).TLSClientConfig.MinVersion = tls.VersionTLS13

		resp, err = http1Client.Get("https://haproxy.internal:443")
		Expect(err).NotTo(HaveOccurred())
		Expect(resp.ProtoMajor).To(Equal(1))

		Expect(resp.StatusCode).To(Equal(http.StatusOK))
		Eventually(gbytes.BufferReader(resp.Body)).Should(gbytes.Say("Hello cloud foundry"))
	})

	Context("When ha_proxy.enable_http2 is true", func() {
		BeforeEach(func() {
			enableHTTP2 = true
		})

		It("Allows clients to use HTTP2 as well as HTTP1.1", func() {
			By("Sending a request to HAProxy using HTTP 1.1")
			resp, err := http1Client.Get("https://haproxy.internal:443")
			Expect(err).NotTo(HaveOccurred())

			Expect(resp.ProtoMajor).To(Equal(1))

			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			Eventually(gbytes.BufferReader(resp.Body)).Should(gbytes.Say("Hello cloud foundry"))

			By("Sending a request to HAProxy using HTTP 2")
			resp, err = http2Client.Get("https://haproxy.internal:443")
			Expect(err).NotTo(HaveOccurred())

			Expect(resp.ProtoMajor).To(Equal(2))

			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			Eventually(gbytes.BufferReader(resp.Body)).Should(gbytes.Say("Hello cloud foundry"))
		})
	})

	Context("ALPN Configuration via CRT list", func() {
		BeforeEach(func() {
			// Do not enable HTTP globally, since we are adding it via crt-list entries
			enableHTTP2 = false
		})

		It("Negotiates the correct ALPN protocol", func() {
			// H2 endpoint should negotiate H2 if the client supports it
			alpnProto, err := connectTLSALPNNegotiatedProtocol([]string{"http/1.1", "h2"}, haproxyInfo.PublicIP, creds.HTTPSFrontend.CA, "haproxy.h2.internal")
			Expect(err).NotTo(HaveOccurred())
			Expect(alpnProto).To(Equal("h2"))

			// HTTP/1.1 endpoint should negotiate HTTP/1.1 if the client supports it
			alpnProto, err = connectTLSALPNNegotiatedProtocol([]string{"h2", "http/1.1"}, haproxyInfo.PublicIP, creds.HTTPSFrontend.CA, "haproxy.http11.internal")
			Expect(err).NotTo(HaveOccurred())
			Expect(alpnProto).To(Equal("http/1.1"))

			// H2+HTTP/1.1 endpoint should negotiate H2 if the client supports it
			alpnProto, err = connectTLSALPNNegotiatedProtocol([]string{"h2"}, haproxyInfo.PublicIP, creds.HTTPSFrontend.CA, "haproxy.h2-http11.internal")
			Expect(err).NotTo(HaveOccurred())
			Expect(alpnProto).To(Equal("h2"))

			// H2+HTTP/1.1 endpoint should negotiate HTTP/1.1 if the client supports it
			alpnProto, err = connectTLSALPNNegotiatedProtocol([]string{"http/1.1"}, haproxyInfo.PublicIP, creds.HTTPSFrontend.CA, "haproxy.h2-http11.internal")
			Expect(err).NotTo(HaveOccurred())
			Expect(alpnProto).To(Equal("http/1.1"))

			// H2 endpoint should not use ALPN if client does not support H2
			alpnProto, err = connectTLSALPNNegotiatedProtocol([]string{"http/1.1"}, haproxyInfo.PublicIP, creds.HTTPSFrontend.CA, "haproxy.h2.internal")
			Expect(err).NotTo(HaveOccurred())
			Expect(alpnProto).To(Equal(""))

			// HTTP/1.1 endpoint should not use ALPN if client does not support HTTP/1.1
			alpnProto, err = connectTLSALPNNegotiatedProtocol([]string{"h2"}, haproxyInfo.PublicIP, creds.HTTPSFrontend.CA, "haproxy.http11.internal")
			Expect(err).NotTo(HaveOccurred())
			Expect(alpnProto).To(Equal(""))
		})
	})
})
