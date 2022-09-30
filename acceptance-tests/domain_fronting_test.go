package acceptance_tests

import (
	"bytes"
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Domain fronting", func() {
	opsfile := `---
# Disable domain fronting
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/disable_domain_fronting?
  value: ((disable_domain_fronting))
# Configure CA and cert chain
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/crt_list?/-
  value:
    snifilter:
    - haproxy.internal
    ssl_pem:
      cert_chain: ((https_frontend.certificate))((https_frontend_ca.certificate))
      private_key: ((https_frontend.private_key))
    client_ca_file: ((client_cert.ca))
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
- type: replace
  path: /variables?/-
  value:
    name: client_ca
    type: certificate
    options:
      is_ca: true
      common_name: bosh
- type: replace
  path: /variables?/-
  value:
    name: client_cert
    type: certificate
    options:
      ca: client_ca
      common_name: client
      alternative_names: [client]
      extended_key_usage: [client_auth]
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
		Client struct {
			Certificate string `yaml:"certificate" json:"certificate"`
			PrivateKey  string `yaml:"private_key" json:"private_key"`
			CA          string `yaml:"ca" json:"ca"`
		} `yaml:"client_cert" json:"client_cert"`
		ClientCA struct {
			Certificate string `yaml:"certificate" json:"certificate"`
			PrivateKey  string `yaml:"private_key" json:"private_key"`
		} `yaml:"client_ca" json:"client_ca"`
	}
	var disableDomainFronting interface{}
	var haproxyInfo haproxyInfo
	var closeLocalServer func()
	var closeSSHTunnel context.CancelFunc
	var clientCert tls.Certificate
	var mtlsClient *http.Client
	var nonMTLSClient *http.Client
	var mtlsClientNoSNI *http.Client
	var nonMTLSClientNoSNI *http.Client
	var tlsConfig *tls.Config
	haproxyBackendPort := 12000

	JustBeforeEach(func() {
		var varsStoreReader varsStoreReader
		haproxyInfo, varsStoreReader = deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfile}, map[string]interface{}{
			"disable_domain_fronting": disableDomainFronting,
			"cert_common_name":        "haproxy.internal",
			"cert_sans":               []string{"haproxy.internal"},
		}, true)

		err := varsStoreReader(&creds)
		Expect(err).NotTo(HaveOccurred())

		var localPort int
		closeLocalServer, localPort = startDefaultTestServer()
		closeSSHTunnel = setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)

		clientCert, err = tls.X509KeyPair([]byte(creds.Client.Certificate), []byte(creds.Client.PrivateKey))
		Expect(err).NotTo(HaveOccurred())

		addressMap := map[string]string{
			"haproxy.internal:443": fmt.Sprintf("%s:443", haproxyInfo.PublicIP),
		}

		nonMTLSClient = buildHTTPClient([]string{creds.HTTPSFrontend.CA}, addressMap, []tls.Certificate{}, "")
		mtlsClient = buildHTTPClient([]string{creds.HTTPSFrontend.CA}, addressMap, []tls.Certificate{clientCert}, "")
		nonMTLSClientNoSNI = buildHTTPClient([]string{creds.HTTPSFrontend.CA}, addressMap, []tls.Certificate{}, "1.2.3.4")
		mtlsClientNoSNI = buildHTTPClient([]string{creds.HTTPSFrontend.CA}, addressMap, []tls.Certificate{clientCert}, "1.2.3.4")
		tlsConfig = buildTLSConfig([]string{creds.HTTPSFrontend.CA}, []tls.Certificate{clientCert}, "haproxy.internal")
	})

	AfterEach(func() {
		if closeLocalServer != nil {
			defer closeLocalServer()
		}

		if closeSSHTunnel != nil {
			defer closeSSHTunnel()
		}
	})

	Context("When disable domain fronting is false", func() {
		BeforeEach(func() {
			disableDomainFronting = false
		})

		It("Allows domain fronting", func() {
			By("Sending a request to HAProxy with a mismatched SNI and Host header it returns a 200")
			req := buildRequest("https://haproxy.internal", "spoof.internal")
			expect200(nonMTLSClient.Do(req))
			expect200(mtlsClient.Do(req))

			By("Sending a request to HAProxy with no Host header returns a 400")
			expect400BadRequestNoHostHeader(haproxyInfo.PublicIP, tlsConfig)

			By("Sending a request to HAProxy with a matching Host header it returns a 200 as normal")
			req = buildRequest("https://haproxy.internal", "haproxy.internal")
			expect200(nonMTLSClient.Do(req))
			expect200(mtlsClient.Do(req))

			By("Sending a request to HAProxy with a matching Host header including the optional port it returns a 200 as normal")
			req = buildRequest("https://haproxy.internal", "haproxy.internal:443")
			expect200(nonMTLSClient.Do(req))
			expect200(mtlsClient.Do(req))

			By("Sending a request to HAProxy with no SNI it returns a 200, regardless of host header")
			// Although we are using a 'spoofed' host header here, HAProxy
			// should not care as there is no SNI in the request
			req = buildRequest("https://haproxy.internal", "spoof.internal")
			expect200(nonMTLSClientNoSNI.Do(req))
			expect200(mtlsClientNoSNI.Do(req))
		})
	})

	Context("When disable domain fronting is true", func() {
		BeforeEach(func() {
			disableDomainFronting = true
		})

		It("Disables domain fronting", func() {
			By("Sending a request to HAProxy with a mismatched SNI and Host header it returns a 421")
			req := buildRequest("https://haproxy.internal", "spoof.internal")
			expect421(nonMTLSClient.Do(req))
			expect421(mtlsClient.Do(req))

			By("Sending a request to HAProxy with no Host header returns a 400")
			expect400BadRequestNoHostHeader(haproxyInfo.PublicIP, tlsConfig)

			By("Sending a request to HAProxy with a matching SNI and Host header it returns a 200 as normal")
			req = buildRequest("https://haproxy.internal", "haproxy.internal")
			expect200(nonMTLSClient.Do(req))
			expect200(mtlsClient.Do(req))

			By("Sending a request to HAProxy with a case-mismatched SNI and Host header it returns a 200 as normal")
			req = buildRequest("https://haproxy.internal", "haproxy.internal")
			// overwrite host field directly to skip canonicalization
			req.Host = "HAPROXY.internal"
			expect200(nonMTLSClient.Do(req))
			expect200(mtlsClient.Do(req))

			By("Sending a request to HAProxy with a matching SNI and Host header including the optional port it returns a 200 as normal")
			req = buildRequest("https://haproxy.internal", "haproxy.internal:443")
			expect200(nonMTLSClient.Do(req))
			expect200(mtlsClient.Do(req))

			By("Sending a request to HAProxy with no SNI it returns a 200, regardless of host header")
			// Although we are using a 'spoofed' host header here, HAProxy
			// should not care as there is no SNI in the request
			req = buildRequest("https://haproxy.internal", "spoof.internal")
			expect200(nonMTLSClientNoSNI.Do(req))
			expect200(mtlsClientNoSNI.Do(req))
		})
	})

	Context("When disable domain fronting is mtls_only", func() {
		BeforeEach(func() {
			disableDomainFronting = "mtls_only"
		})

		It("Disables domain fronting for MTLS requests only", func() {
			By("Sending a request to HAProxy with a mismatched SNI and Host header it returns a 421 only for mTLS requests")
			req := buildRequest("https://haproxy.internal", "spoof.internal")
			expect200(nonMTLSClient.Do(req))
			expect421(mtlsClient.Do(req))

			By("Sending a request to HAProxy with no Host header returns a 400")
			expect400BadRequestNoHostHeader(haproxyInfo.PublicIP, tlsConfig)

			By("Sending a request to HAProxy with a matching SNI and Host header it returns a 200 as normal")
			req = buildRequest("https://haproxy.internal", "haproxy.internal")
			expect200(nonMTLSClient.Do(req))
			expect200(mtlsClient.Do(req))

			By("Sending a request to HAProxy with a case-mismatched SNI and Host header it returns a 200 as normal")
			req = buildRequest("https://haproxy.internal", "haproxy.internal")
			// overwrite host field directly to skip canonicalization
			req.Host = "HAPROXY.internal"
			expect200(nonMTLSClient.Do(req))
			expect200(mtlsClient.Do(req))

			By("Sending a request to HAProxy with a matching SNI and Host header including the optional port it returns a 200 as normal")
			req = buildRequest("https://haproxy.internal", "haproxy.internal:443")
			expect200(nonMTLSClient.Do(req))
			expect200(mtlsClient.Do(req))

			By("Sending a request to HAProxy with no SNI it returns a 200, regardless of host header")
			// Although we are using a 'spoofed' host header here, HAProxy
			// should not care as there is no SNI in the request
			req = buildRequest("https://haproxy.internal", "spoof.internal")
			expect200(nonMTLSClientNoSNI.Do(req))
			expect200(mtlsClientNoSNI.Do(req))
		})
	})
})

func buildRequest(address string, hostHeader string) *http.Request {
	req, err := http.NewRequest("GET", address, nil)
	Expect(err).NotTo(HaveOccurred())
	req.Host = hostHeader
	return req
}

func expect400BadRequestNoHostHeader(haproxyIP string, tlsConfig *tls.Config) {
	addr := fmt.Sprintf("%s:443", haproxyIP)
	conn, err := tls.Dial("tcp", addr, tlsConfig)
	Expect(err).ToNot(HaveOccurred())
	defer conn.Close()

	// Send an malformed HTTP request with a missing host header
	_, err = conn.Write([]byte(strings.Join([]string{
		"GET / HTTP/1.1",
		"Content-Length: 0",
		"Content-Type: text/plain",
		"\r\n",
	}, "\r\n")))
	Expect(err).ToNot(HaveOccurred())

	err = conn.SetDeadline(time.Now().Add(time.Second))
	Expect(err).ToNot(HaveOccurred())

	buffer := bytes.NewBuffer([]byte{})
	io.Copy(buffer, conn)

	Expect(buffer.String()).To(ContainSubstring("HTTP/1.1 400"))
	Expect(buffer.String()).To(ContainSubstring("Bad Request: missing required Host header"))
}
