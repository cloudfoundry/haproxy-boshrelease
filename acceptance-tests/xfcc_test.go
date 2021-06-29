package acceptance_tests

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"fmt"
	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"net/http"
)

/*
	https://bosh.io/jobs/haproxy?source=github.com/cloudfoundry-community/haproxy-boshrelease#p%3dha_proxy.forwarded_client_cert
	forwarded_client_cert
		always_forward_only 					=> X-Forwarded-Client-Cert is always forwarded

		forward_only 									=> X-Forwarded-Client-Cert is removed for non-mTLS connections
																	=> X-Forwarded-Client-Cert is forwarded for mTLS connections

		sanitize_set 									=> X-Forwarded-Client-Cert is removed for non-mTLS connections
																	=> X-Forwarded-Client-Cert is overwritten for mTLS connections

		forward_only_if_route_service => X-Forwarded-Client-Cert is removed for non-mTLS connections when X-Cf-Proxy-Signature header is not present
																		 X-Forwarded-Client-Cert is forwarded for non-mTLS connections when X-Cf-Proxy-Signature header is present
																		 X-Forwarded-Client-Cert is overwritten for mTLS connections
*/
var _ = Describe("forwarded_client_cert", func() {
	opsfileForwardedClientCert := `---
# Configure X-Forwarded-Client-Cert handling
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/forwarded_client_cert?
  value: ((forwarded_client_cert))
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/client_cert?
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
    client_ca_file: ((client_cert_ca.certificate))

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

# Add MTLS cert
- type: replace
  path: /variables?/-
  value:
    name: client_cert_ca
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
      ca: client_cert_ca
      common_name: haproxy.client
      alternative_names: [haproxy.client]
      extended_key_usage: [client_auth]
`
	var closeLocalServer func()
	var closeSSHTunnel context.CancelFunc
	var creds struct {
		HTTPSFrontend struct {
			Certificate string `yaml:"certificate"`
			PrivateKey  string `yaml:"private_key"`
			CA          string `yaml:"ca"`
		} `yaml:"https_frontend"`
		ClientCert struct {
			Certificate string `yaml:"certificate"`
			PrivateKey  string `yaml:"private_key"`
			CA          string `yaml:"ca"`
		} `yaml:"client_cert"`
	}
	var clientCert tls.Certificate
	var haproxyInfo haproxyInfo
	var deployVars map[string]interface{}
	var mtlsClient *http.Client
	var nonMTLSClient *http.Client
	recordedXFCCHeader := "initial"
	var recordedHeaders http.Header
	additionalmTLSHeaders := []string{
		"X-Ssl-Client",
		"X-Ssl-Client-Session-Id",
		"X-Ssl-Client-Verify",
		"X-Ssl-Client-Subject-Dn",
		"X-Ssl-Client-Subject-Cn",
		"X-Ssl-Client-Issuer-Dn",
		"X-Ssl-Client-Notbefore",
		"X-Ssl-Client-Notafter",
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
		haproxyInfo, varsStoreReader = deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        defaultDeploymentName,
		}, []string{opsfileForwardedClientCert}, deployVars, true)

		err := varsStoreReader(&creds)
		Expect(err).NotTo(HaveOccurred())

		By("Starting a local http server to act as a backend")
		var localPort int
		recordedXFCCHeader = "unknown"
		closeLocalServer, localPort, err = startLocalHTTPServer(func(w http.ResponseWriter, r *http.Request) {
			fmt.Println("Backend server handling incoming request")
			recordedXFCCHeader = r.Header.Get("X-Forwarded-Client-Cert")
			recordedHeaders = r.Header
			_, _ = w.Write([]byte("OK"))
		})
		Expect(err).NotTo(HaveOccurred())

		closeSSHTunnel = setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)

		clientCert, err = tls.X509KeyPair([]byte(creds.ClientCert.Certificate), []byte(creds.ClientCert.PrivateKey))
		Expect(err).NotTo(HaveOccurred())

		nonMTLSClient = buildHTTPClient(
			[]string{creds.HTTPSFrontend.CA},
			map[string]string{"haproxy.internal:443": fmt.Sprintf("%s:443", haproxyInfo.PublicIP)},
			[]tls.Certificate{},
		)

		mtlsClient = buildHTTPClient(
			[]string{creds.HTTPSFrontend.CA},
			map[string]string{"haproxy.internal:443": fmt.Sprintf("%s:443", haproxyInfo.PublicIP)},
			[]tls.Certificate{clientCert},
		)
	})

	Describe("When forwarded_client_cert is sanitize_set", func() {
		BeforeEach(func() {
			deployVars = map[string]interface{}{
				"forwarded_client_cert": "sanitize_set",
			}
		})

		It("Correctly handles the X-Forwarded-Client-Cert header", func() {
			req, err := http.NewRequest("GET", "https://haproxy.internal:443", nil)
			Expect(err).NotTo(HaveOccurred())
			req.Header.Set("X-Forwarded-Client-Cert", "spoofed-client-cert")

			By("Correctly removes the X-Forwarded-Client-Cert header from non-mTLS requests")
			resp, err := nonMTLSClient.Do(req)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			Expect(recordedXFCCHeader).To(BeEmpty())

			By("Does not add mTLS-related additional headers to non-mTLS requests")
			for _, additionalHeader := range additionalmTLSHeaders {
				Expect(recordedHeaders).NotTo(HaveKey(additionalHeader))
			}

			By("Correctly replaces the X-Forwarded-Client-Cert in mTLS requests")
			resp, err = mtlsClient.Do(req)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))

			By("Verifying that the XFCC header passed to the backend server is the base-64 DER-encoded client certificate")
			Expect(recordedXFCCHeader).ToNot(BeEmpty())
			Expect(parseXFCCHeaderToPEM(recordedXFCCHeader)).To(Equal(creds.ClientCert.Certificate))

			By("Verifying that mTLS-related additional headers are added and match the client certificate")
			for _, additionalHeader := range additionalmTLSHeaders {
				Expect(recordedHeaders).To(HaveKey(additionalHeader))
			}
			checkXFCCHeaders(recordedXFCCHeader, recordedHeaders)
		})
	})

	Describe("When forwarded_client_cert is always_forward_only", func() {
		BeforeEach(func() {
			deployVars = map[string]interface{}{
				"forwarded_client_cert": "always_forward_only",
			}
		})

		It("Correctly handles the X-Forwarded-Client-Cert header", func() {
			req, err := http.NewRequest("GET", "https://haproxy.internal:443", nil)
			Expect(err).NotTo(HaveOccurred())
			req.Header.Set("X-Forwarded-Client-Cert", "my-client-cert")

			By("Correctly forwards the X-Forwarded-Client-Cert header from non-mTLS requests")
			resp, err := nonMTLSClient.Do(req)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			Expect(recordedXFCCHeader).To(Equal("my-client-cert"))

			By("Does not add mTLS-related additional headers to non-mTLS requests")
			for _, additionalHeader := range additionalmTLSHeaders {
				Expect(recordedHeaders).NotTo(HaveKey(additionalHeader))
			}

			By("Correctly forwards the X-Forwarded-Client-Cert header from mTLS requests")
			resp, err = mtlsClient.Do(req)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			Expect(recordedXFCCHeader).To(Equal("my-client-cert"))

			By("Verifying that mTLS-related additional headers are added")
			for _, additionalHeader := range additionalmTLSHeaders {
				Expect(recordedHeaders).To(HaveKey(additionalHeader))
			}
		})
	})

	Describe("When forwarded_client_cert is forward_only", func() {
		BeforeEach(func() {
			deployVars = map[string]interface{}{
				"forwarded_client_cert": "forward_only",
			}
		})

		It("Correctly handles the X-Forwarded-Client-Cert header", func() {
			req, err := http.NewRequest("GET", "https://haproxy.internal:443", nil)
			Expect(err).NotTo(HaveOccurred())
			req.Header.Set("X-Forwarded-Client-Cert", "my-client-cert")

			By("Correctly removes the X-Forwarded-Client-Cert header from non-mTLS requests")
			resp, err := nonMTLSClient.Do(req)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			Expect(recordedXFCCHeader).To(BeEmpty())

			By("Does not add mTLS-related additional headers to non-mTLS requests")
			for _, additionalHeader := range additionalmTLSHeaders {
				Expect(recordedHeaders).NotTo(HaveKey(additionalHeader))
			}

			By("Correctly forwards the X-Forwarded-Client-Cert header from mTLS requests")
			resp, err = mtlsClient.Do(req)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			Expect(recordedXFCCHeader).To(Equal("my-client-cert"))

			By("Verifying that mTLS-related additional headers are added")
			for _, additionalHeader := range additionalmTLSHeaders {
				Expect(recordedHeaders).To(HaveKey(additionalHeader))
			}
		})
	})

	Describe("When forwarded_client_cert is forward_only_if_route_service", func() {
		BeforeEach(func() {
			deployVars = map[string]interface{}{
				"forwarded_client_cert": "forward_only_if_route_service",
			}
		})

		It("Correctly handles the X-Forwarded-Client-Cert header", func() {
			req, err := http.NewRequest("GET", "https://haproxy.internal:443", nil)
			Expect(err).NotTo(HaveOccurred())
			req.Header.Set("X-Forwarded-Client-Cert", "spoofed-client-cert")

			By("Correctly removes the X-Forwarded-Client-Cert header from non-mTLS requests")
			resp, err := nonMTLSClient.Do(req)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			Expect(recordedXFCCHeader).To(BeEmpty())

			By("Does not add mTLS-related additional headers to non-mTLS requests")
			for _, additionalHeader := range additionalmTLSHeaders {
				Expect(recordedHeaders).NotTo(HaveKey(additionalHeader))
			}

			By("Correctly forwards the X-Forwarded-Client-Cert header from non-mTLS requests where X-Cf-Proxy-Signature is present")
			req.Header.Set("X-Forwarded-Client-Cert", "my-client-cert")
			req.Header.Set("X-Cf-Proxy-Signature", "abc123")
			resp, err = nonMTLSClient.Do(req)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			Expect(recordedXFCCHeader).To(Equal("my-client-cert"))
			Expect(req.Header.Get("X-Cf-Proxy-Signature")).To(Equal("abc123"))

			By("Does not add mTLS-related additional headers to non-mTLS requests where X-Cf-Proxy-Signature is present")
			for _, additionalHeader := range additionalmTLSHeaders {
				Expect(recordedHeaders).NotTo(HaveKey(additionalHeader))
			}

			By("Correctly replaces the X-Forwarded-Client-Cert in mTLS requests")
			resp, err = mtlsClient.Do(req)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))

			By("Verifying that the XFCC header passed to the backend server is the base-64 DER-encoded client certificate")
			Expect(recordedXFCCHeader).ToNot(BeEmpty())
			Expect(parseXFCCHeaderToPEM(recordedXFCCHeader)).To(Equal(creds.ClientCert.Certificate))
			Expect(req.Header.Get("X-Cf-Proxy-Signature")).To(Equal("abc123"))

			By("Verifying that mTLS-related additional headers are added and match the client certificate")
			for _, additionalHeader := range additionalmTLSHeaders {
				Expect(recordedHeaders).To(HaveKey(additionalHeader))
			}
			checkXFCCHeaders(recordedXFCCHeader, recordedHeaders)
		})
	})
})

func parseXFCCHeaderToPEM(header string) string {
	cert := parseXFCCHeaderToCert(header)

	var certPEM bytes.Buffer
	err := pem.Encode(&certPEM, &pem.Block{Type: "CERTIFICATE", Bytes: cert.Raw})
	Expect(err).NotTo(HaveOccurred())

	return certPEM.String()
}

func parseXFCCHeaderToCert(header string) *x509.Certificate {
	derEncodedCert, err := base64.StdEncoding.DecodeString(header)
	Expect(err).NotTo(HaveOccurred())

	cert, err := x509.ParseCertificate(derEncodedCert)
	Expect(err).NotTo(HaveOccurred())

	return cert
}

func checkXFCCHeaders(recordedXFCCHeader string, recordedHeaders http.Header) {
	cert := parseXFCCHeaderToCert(recordedXFCCHeader)
	Expect(recordedHeaders.Get("X-Ssl-Client")).To(Equal("1"))
	Expect(recordedHeaders.Get("X-Ssl-Client-Verify")).To(Equal("0"))
	Expect(recordedHeaders.Get("X-Ssl-Client-Subject-Dn")).To(ContainSubstring(cert.Subject.Country[0]))
	Expect(recordedHeaders.Get("X-Ssl-Client-Subject-Dn")).To(ContainSubstring(cert.Subject.Organization[0]))
	Expect(recordedHeaders.Get("X-Ssl-Client-Subject-Dn")).To(ContainSubstring(cert.Subject.CommonName))
	Expect(recordedHeaders.Get("X-Ssl-Client-Subject-Cn")).To(Equal(cert.Subject.CommonName))
	Expect(recordedHeaders.Get("X-Ssl-Client-Issuer-Dn")).To(ContainSubstring(cert.Issuer.Country[0]))
	Expect(recordedHeaders.Get("X-Ssl-Client-Issuer-Dn")).To(ContainSubstring(cert.Issuer.Organization[0]))
	Expect(recordedHeaders.Get("X-Ssl-Client-Issuer-Dn")).To(ContainSubstring(cert.Issuer.CommonName))
	notBeforeString := fmt.Sprintf("%02d%02d%02d%02d%02d%02dZ", cert.NotBefore.Year()-2000,
		cert.NotBefore.Month(), cert.NotBefore.Day(), cert.NotBefore.Hour(), cert.NotBefore.Minute(), cert.NotBefore.Second())
	Expect(recordedHeaders.Get("X-Ssl-Client-Notbefore")).To(Equal(notBeforeString))
	notAfterString := fmt.Sprintf("%02d%02d%02d%02d%02d%02dZ", cert.NotAfter.Year()-2000,
		cert.NotAfter.Month(), cert.NotAfter.Day(), cert.NotAfter.Hour(), cert.NotAfter.Minute(), cert.NotAfter.Second())
	Expect(recordedHeaders.Get("X-Ssl-Client-Notafter")).To(Equal(notAfterString))
}
