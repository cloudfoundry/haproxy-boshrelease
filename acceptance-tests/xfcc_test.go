package acceptance_tests

import (
	"context"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/pem"
	"fmt"
	"net/http"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

type Certificate struct {
	CertPEM       string
	PrivateKeyPEM string
	X509Cert      *x509.Certificate
	PrivateKey    *rsa.PrivateKey
	TLSCert       tls.Certificate
}

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

- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/crt_list?/-
  value:
    verify: required
    snifilter:
    - haproxy.client1.internal
    ssl_pem:
      cert_chain: ((https_frontend.certificate))((https_frontend_ca.certificate))
      private_key: ((https_frontend.private_key))
    client_ca_file: ((client_ca.certificate))

- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/crt_list?/-
  value:
    verify: required
    snifilter:
    - haproxy.client2.internal
    ssl_pem:
      cert_chain: ((https_frontend.certificate))((https_frontend.ca))
      private_key: ((https_frontend.private_key))
    client_ca_file: ((client_ca.certificate))

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
      alternative_names:
      - haproxy.internal
      - haproxy.client1.internal
      - haproxy.client2.internal

- type: replace
  path: /variables?/-
  value:
    name: client_ca
    type: certificate
    options:
      is_ca: true
      duration: 3650

- type: replace
  path: /variables?/-
  value:
    name: client_cert
    type: certificate
    options:
      common_name: valid-client-cert
      ca: client_ca
      extended_key_usage:
      - client_auth

- type: replace
  path: /variables?/-
  value:
    name: intermediate_ca
    type: certificate
    options:
      is_ca: true
      ca: client_ca

- type: replace
  path: /variables?/-
  value:
    name: client_with_intermediate_cert
    type: certificate
    options:
      common_name: valid-client-with-intermediate-cert
      ca: intermediate_ca
      extended_key_usage:
      - client_auth
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
		ClientWithIntermediateCert struct {
			Certificate string `yaml:"certificate"`
			PrivateKey  string `yaml:"private_key"`
			CA          string `yaml:"ca"`
		} `yaml:"client_with_intermediate_cert"`
		IntermediateCA struct {
			Certificate string `yaml:"certificate"`
			PrivateKey  string `yaml:"private_key"`
			CA          string `yaml:"ca"`
		} `yaml:"intermediate_ca"`
	}
	var haproxyInfo haproxyInfo
	var deployVars map[string]interface{}
	var mtlsClient1 *http.Client
	var mtlsClient2 *http.Client
	var nonMTLSClient *http.Client
	var recordedHeaders http.Header
	var nonMTLSRequest *http.Request
	var mtlsClient1Request *http.Request
	var mtlsClient2Request *http.Request
	var clientTLSCert tls.Certificate
	var clientX509Cert *x509.Certificate
	var clientTLSCertWithIntermediate tls.Certificate
	var clientX509CertWithIntermediate *x509.Certificate
	var intermediateX509Cert *x509.Certificate

	// These headers will be forwarded, overwritten or deleted
	// depending on the value of ha_proxy.forwarded_client_cert
	incomingRequestHeaders := map[string]string{
		"X-Forwarded-Client-Cert":  "my-client-cert",
		"X-Forwarded-Client-Chain": "my-client-chain",
		"X-SSL-Client-Subject-Dn":  "My App",
		"X-SSL-Client-Subject-Cn":  "app.mycert.com",
		"X-SSL-Client-Issuer-Dn":   "ACME inc, USA",
		"X-SSL-Client-Issuer-Cn":   "mycert.com",
		"X-SSL-Client-Notbefore":   "Wednesday",
		"X-SSL-Client-Notafter":    "Thursday",
		"X-SSL-Client-Cert":        "ABC",
		"X-SSL-Client-Verify":      "DEF",
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
		closeLocalServer, localPort, err = startLocalHTTPServer(nil, func(w http.ResponseWriter, r *http.Request) {
			fmt.Println("Backend server handling incoming request")
			recordedHeaders = r.Header
			_, _ = w.Write([]byte("OK"))
		})
		Expect(err).NotTo(HaveOccurred())

		closeSSHTunnel = setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)

		addressMap := map[string]string{
			"haproxy.internal:443":         fmt.Sprintf("%s:443", haproxyInfo.PublicIP),
			"haproxy.client1.internal:443": fmt.Sprintf("%s:443", haproxyInfo.PublicIP),
			"haproxy.client2.internal:443": fmt.Sprintf("%s:443", haproxyInfo.PublicIP),
		}

		clientTLSCert, err = tls.X509KeyPair([]byte(creds.ClientCert.Certificate), []byte(creds.ClientCert.PrivateKey))
		Expect(err).NotTo(HaveOccurred())
		clientX509Cert, err = pemToX509Cert([]byte(creds.ClientCert.Certificate))
		Expect(err).NotTo(HaveOccurred())

		// For the client to present a chain, we need to concatenate the client leaf and intermediate cert
		// when building the client tls.Certificate
		clientTLSCertWithIntermediate, err = tls.X509KeyPair(append([]byte(creds.ClientWithIntermediateCert.Certificate), []byte(creds.ClientWithIntermediateCert.CA)...), []byte(creds.ClientWithIntermediateCert.PrivateKey))
		Expect(err).NotTo(HaveOccurred())
		clientX509CertWithIntermediate, err = pemToX509Cert([]byte(creds.ClientWithIntermediateCert.Certificate))
		Expect(err).NotTo(HaveOccurred())
		intermediateX509Cert, err = pemToX509Cert([]byte(creds.ClientWithIntermediateCert.CA))
		Expect(err).NotTo(HaveOccurred())

		nonMTLSClient = buildHTTPClient([]string{creds.HTTPSFrontend.CA}, addressMap, []tls.Certificate{}, "")
		mtlsClient1 = buildHTTPClient([]string{creds.HTTPSFrontend.CA}, addressMap, []tls.Certificate{clientTLSCert}, "")
		mtlsClient2 = buildHTTPClient([]string{creds.HTTPSFrontend.CA}, addressMap, []tls.Certificate{clientTLSCertWithIntermediate}, "")

		nonMTLSRequest, err = http.NewRequest("GET", "https://haproxy.internal:443", nil)
		Expect(err).NotTo(HaveOccurred())

		mtlsClient1Request, err = http.NewRequest("GET", "https://haproxy.client1.internal:443", nil)
		Expect(err).NotTo(HaveOccurred())

		mtlsClient2Request, err = http.NewRequest("GET", "https://haproxy.client2.internal:443", nil)
		Expect(err).NotTo(HaveOccurred())

		for key, value := range incomingRequestHeaders {
			nonMTLSRequest.Header.Set(key, value)
			mtlsClient1Request.Header.Set(key, value)
			mtlsClient2Request.Header.Set(key, value)
		}
	})

	Describe("When forwarded_client_cert is sanitize_set", func() {
		BeforeEach(func() {
			deployVars = map[string]interface{}{
				"forwarded_client_cert": "sanitize_set",
			}
		})

		It("Correctly handles the X-Forwarded-Client-Cert and related mTLS headers", func() {
			By("Correctly removes mTLS headers from non-mTLS requests")
			resp, err := nonMTLSClient.Do(nonMTLSRequest)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			for key := range incomingRequestHeaders {
				Expect(recordedHeaders).NotTo(HaveKey(key))
			}

			By("Correctly replaces mTLS headers in mTLS requests")
			resp, err = mtlsClient1.Do(mtlsClient1Request)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))

			checkXFCCHeadersMatchCert(clientX509Cert, nil, recordedHeaders)

			By("Correctly replaces mTLS headers in mTLS requests that use intermediate certificates")
			respClient2, err := mtlsClient2.Do(mtlsClient2Request)
			Expect(err).NotTo(HaveOccurred())
			Expect(respClient2.StatusCode).To(Equal(http.StatusOK))
			checkXFCCHeadersMatchCert(clientX509CertWithIntermediate, intermediateX509Cert, recordedHeaders)
		})
	})

	Describe("When forwarded_client_cert is always_forward_only", func() {
		BeforeEach(func() {
			deployVars = map[string]interface{}{
				"forwarded_client_cert": "always_forward_only",
			}
		})

		It("Correctly handles the X-Forwarded-Client-Cert and related mTLS headers", func() {
			By("Correctly forwards mTLS headers from non-mTLS requests")
			resp, err := nonMTLSClient.Do(nonMTLSRequest)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			for key, value := range incomingRequestHeaders {
				Expect(recordedHeaders.Get(key)).To(Equal(value))
			}

			By("Correctly forwards mTLS headers from mTLS requests")
			resp, err = mtlsClient1.Do(mtlsClient1Request)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))

			for key, value := range incomingRequestHeaders {
				Expect(recordedHeaders.Get(key)).To(Equal(value))
			}
		})
	})

	Describe("When forwarded_client_cert is forward_only", func() {
		BeforeEach(func() {
			deployVars = map[string]interface{}{
				"forwarded_client_cert": "forward_only",
			}
		})

		It("Correctly handles the X-Forwarded-Client-Cert and related mTLS headers", func() {
			By("Correctly removes mTLS headers from non-mTLS requests")
			resp, err := nonMTLSClient.Do(nonMTLSRequest)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			for key := range incomingRequestHeaders {
				Expect(recordedHeaders).NotTo(HaveKey(key))
			}

			By("Correctly forwards mTLS headers from mTLS requests")
			resp, err = mtlsClient1.Do(mtlsClient1Request)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))

			for key, value := range incomingRequestHeaders {
				Expect(recordedHeaders.Get(key)).To(Equal(value))
			}
		})
	})

	Describe("When forwarded_client_cert is forward_only_if_route_service", func() {
		BeforeEach(func() {
			deployVars = map[string]interface{}{
				"forwarded_client_cert": "forward_only_if_route_service",
			}
		})

		It("Correctly handles the X-Forwarded-Client-Cert and related mTLS headers", func() {
			By("Correctly removes mTLS headers from non-mTLS requests")
			resp, err := nonMTLSClient.Do(nonMTLSRequest)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			for key := range incomingRequestHeaders {
				Expect(recordedHeaders).NotTo(HaveKey(key))
			}

			By("Correctly forwards mTLS header from non-mTLS requests where X-Cf-Proxy-Signature is present")
			nonMTLSRequest.Header.Set("X-Cf-Proxy-Signature", "abc123")
			resp, err = nonMTLSClient.Do(nonMTLSRequest)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))
			Expect(recordedHeaders.Get("X-Cf-Proxy-Signature")).To(Equal("abc123"))
			for key, value := range incomingRequestHeaders {
				Expect(recordedHeaders.Get(key)).To(Equal(value))
			}

			By("Correctly replaces mTLS headers in mTLS requests")
			mtlsClient1Request.Header.Set("X-Cf-Proxy-Signature", "abc123")
			resp, err = mtlsClient1.Do(mtlsClient1Request)
			Expect(err).NotTo(HaveOccurred())
			Expect(resp.StatusCode).To(Equal(http.StatusOK))

			checkXFCCHeadersMatchCert(clientX509Cert, nil, recordedHeaders)

			// X-Cf-Proxy-Signature should be left intact
			Expect(recordedHeaders.Get("X-Cf-Proxy-Signature")).To(Equal("abc123"))

			By("Correctly replaces mTLS headers in mTLS requests that use intermediate certificates")
			respClient2, err := mtlsClient2.Do(mtlsClient2Request)
			Expect(err).NotTo(HaveOccurred())
			Expect(respClient2.StatusCode).To(Equal(http.StatusOK))
			checkXFCCHeadersMatchCert(clientX509CertWithIntermediate, intermediateX509Cert, recordedHeaders)
		})
	})
})

func checkXFCCHeadersMatchCert(expectedCert *x509.Certificate, expectedIntermediateCert *x509.Certificate, headers http.Header) {
	actualCert, err := x509.ParseCertificate([]byte(base64Decode(headers.Get("X-Forwarded-Client-Cert"))))
	Expect(err).NotTo(HaveOccurred())

	Expect(*actualCert).To(Equal(*expectedCert))

	if expectedIntermediateCert != nil {
		actualIntermediateCert, err := x509.ParseCertificate([]byte(base64Decode(headers.Get("X-Forwarded-Client-Chain"))))
		Expect(err).NotTo(HaveOccurred())

		Expect(*actualIntermediateCert).To(Equal(*expectedIntermediateCert))
	}

	Expect(base64Decode(headers.Get("X-SSL-Client-Subject-Dn"))).To(Equal(
		fmt.Sprintf("/C=%s/O=%s/CN=%s", expectedCert.Subject.Country[0], expectedCert.Subject.Organization[0], expectedCert.Subject.CommonName)))
	Expect(base64Decode(headers.Get("X-SSL-Client-Subject-CN"))).To(Equal(expectedCert.Subject.CommonName))
	Expect(base64Decode(headers.Get("X-SSL-Client-Issuer-Dn"))).To(Equal(
		fmt.Sprintf("/C=%s/O=%s", expectedCert.Issuer.Country[0], expectedCert.Issuer.Organization[0])))
	Expect(headers.Get("X-SSL-Client-Notbefore")).To(Equal(expectedCert.NotBefore.UTC().Format("060102150405Z"))) //YYMMDDhhmmss[Z]
	Expect(headers.Get("X-SSL-Client-Notafter")).To(Equal(expectedCert.NotAfter.UTC().Format("060102150405Z")))   //YYMMDDhhmmss[Z]

	Expect(headers.Get("X-SSL-Client")).To(Equal("1"))
	Expect(headers.Get("X-SSL-Client-Verify")).To(Equal("0"))
}

func base64Decode(input string) string {
	output, err := base64.StdEncoding.DecodeString(input)
	Expect(err).NotTo(HaveOccurred())
	return string(output)
}

func pemToX509Cert(pemBytes []byte) (*x509.Certificate, error) {
	block, _ := pem.Decode(pemBytes)
	return x509.ParseCertificate(block.Bytes)
}
