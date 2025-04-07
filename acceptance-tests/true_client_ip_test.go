package acceptance_tests

import (
	"crypto/tls"
	"fmt"
	"net"
	"net/http"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("True Client IP - forward_only_if_route_service", func() {
	opsfileHeaders := `---
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/true_client_ip_header?
  value: "X-CF-True-Client-IP"
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/forward_true_client_ip_header?
  value: "forward_only_if_route_service"
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

	It("Adds a header with the provided name and correct value for the true client ip, if it doesn't exist", func() {
		ipAddresses := getAllIpAddresses()
		request, err = http.NewRequest("GET", "https://haproxy.internal:443", nil)
		Expect(err).NotTo(HaveOccurred())

		By("Correctly sets the True-Client-Ip Header")
		resp, err := client.Do(request)
		expect200(resp, err)
		headerKey := "X-Cf-True-Client-Ip"
		Expect(recordedHeaders).To(HaveKey(headerKey))
		Expect(recordedHeaders[headerKey]).To(HaveLen(1))
		Expect(ipAddresses).To(ContainElement(recordedHeaders[headerKey][0]))
	})

	It("Overwrites the True-Client-Ip header if it is already set AND the request is not a route-service", func() {
		ipAddresses := getAllIpAddresses()
		request, err = http.NewRequest("GET", "https://haproxy.internal:443", nil)
		request.Header.Set("X-Cf-True-Client-Ip", "8.8.8.8")
		Expect(err).NotTo(HaveOccurred())

		By("Overwrites the existing True-Client-Ip Header")
		resp, err := client.Do(request)
		expect200(resp, err)
		headerKey := "X-Cf-True-Client-Ip"
		Expect(recordedHeaders).To(HaveKey(headerKey))
		Expect(recordedHeaders[headerKey]).To(HaveLen(1))
		Expect(ipAddresses).To(ContainElement(recordedHeaders[headerKey][0]))
	})

	It("Does not overwrite the True-Client-Ip header if it is already set AND the request is a route-service", func() {
		request, err = http.NewRequest("GET", "https://haproxy.internal:443", nil)
		// Mock a route-service request via the X-Cf-Proxy-Signature header
		request.Header.Set("X-Cf-Proxy-Signature", "abc123")
		request.Header.Set("X-Cf-True-Client-Ip", "8.8.8.8")
		Expect(err).NotTo(HaveOccurred())

		By("Correctly preserves the pre-existing True-Client-Ip Header")
		resp, err := client.Do(request)
		expect200(resp, err)
		headerKey := "X-Cf-True-Client-Ip"
		Expect(recordedHeaders).To(HaveKey(headerKey))
		Expect(recordedHeaders[headerKey]).To(HaveLen(1))
		Expect(recordedHeaders[headerKey][0]).To(Equal("8.8.8.8"))
	})
})

var _ = Describe("True Client IP - always_forward", func() {
	opsfileHeaders := `---
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/true_client_ip_header?
  value: "X-CF-True-Client-IP"
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/forward_true_client_ip_header?
  value: "always_forward"
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

	It("Adds a header with the provided name and correct value for the true client ip, if it doesn't exist", func() {
		ipAddresses := getAllIpAddresses()
		request, err = http.NewRequest("GET", "https://haproxy.internal:443", nil)
		Expect(err).NotTo(HaveOccurred())

		By("Correctly sets the True-Client-Ip Header")
		resp, err := client.Do(request)
		expect200(resp, err)
		headerKey := "X-Cf-True-Client-Ip"
		Expect(recordedHeaders).To(HaveKey(headerKey))
		Expect(recordedHeaders[headerKey]).To(HaveLen(1))
		Expect(ipAddresses).To(ContainElement(recordedHeaders[headerKey][0]))
	})

	It("Does not overwrite the True-Client-Ip header if it is already set AND the request is not a route-service", func() {
		request, err = http.NewRequest("GET", "https://haproxy.internal:443", nil)
		request.Header.Set("X-Cf-True-Client-Ip", "8.8.8.8")
		Expect(err).NotTo(HaveOccurred())

		By("Correctly preserves the pre-existing True-Client-Ip Header")
		resp, err := client.Do(request)
		expect200(resp, err)
		headerKey := "X-Cf-True-Client-Ip"
		Expect(recordedHeaders).To(HaveKey(headerKey))
		Expect(recordedHeaders[headerKey]).To(HaveLen(1))
		Expect(recordedHeaders[headerKey][0]).To(Equal("8.8.8.8"))
	})

	It("Does not overwrite the True-Client-Ip header if it is already set AND the request is a route-service", func() {
		request, err = http.NewRequest("GET", "https://haproxy.internal:443", nil)
		// Mock a route-service request via the X-Cf-Proxy-Signature header
		request.Header.Set("X-Cf-Proxy-Signature", "abc123")
		request.Header.Set("X-Cf-True-Client-Ip", "8.8.8.8")
		Expect(err).NotTo(HaveOccurred())

		By("Correctly preserves the pre-existing True-Client-Ip Header")
		resp, err := client.Do(request)
		expect200(resp, err)
		headerKey := "X-Cf-True-Client-Ip"
		Expect(recordedHeaders).To(HaveKey(headerKey))
		Expect(recordedHeaders[headerKey]).To(HaveLen(1))
		Expect(recordedHeaders[headerKey][0]).To(Equal("8.8.8.8"))
	})
})

var _ = Describe("True Client IP - always_set", func() {
	opsfileHeaders := `---
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/true_client_ip_header?
  value: "X-CF-True-Client-IP"
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/forward_true_client_ip_header?
  value: "always_set"
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

	It("Adds a header with the provided name and correct value for the true client ip, if it doesn't exist", func() {
		ipAddresses := getAllIpAddresses()
		request, err = http.NewRequest("GET", "https://haproxy.internal:443", nil)
		Expect(err).NotTo(HaveOccurred())

		By("Correctly sets the True-Client-Ip Header")
		resp, err := client.Do(request)
		expect200(resp, err)
		headerKey := "X-Cf-True-Client-Ip"
		Expect(recordedHeaders).To(HaveKey(headerKey))
		Expect(recordedHeaders[headerKey]).To(HaveLen(1))
		Expect(ipAddresses).To(ContainElement(recordedHeaders[headerKey][0]))
	})

	It("Overwrites the True-Client-Ip header if it is already set AND the request is not a route-service", func() {
		ipAddresses := getAllIpAddresses()
		request, err = http.NewRequest("GET", "https://haproxy.internal:443", nil)
		request.Header.Set("X-Cf-True-Client-Ip", "8.8.8.8")
		Expect(err).NotTo(HaveOccurred())

		By("Correctly preserves the pre-existing True-Client-Ip Header")
		resp, err := client.Do(request)
		expect200(resp, err)
		headerKey := "X-Cf-True-Client-Ip"
		Expect(recordedHeaders).To(HaveKey(headerKey))
		Expect(recordedHeaders[headerKey]).To(HaveLen(1))
		Expect(ipAddresses).To(ContainElement(recordedHeaders[headerKey][0]))
	})

	It("Overwrites the True-Client-Ip header if it is already set AND the request is a route-service", func() {
		ipAddresses := getAllIpAddresses()
		request, err = http.NewRequest("GET", "https://haproxy.internal:443", nil)
		// Mock a route-service request via the X-Cf-Proxy-Signature header
		request.Header.Set("X-Cf-Proxy-Signature", "abc123")
		request.Header.Set("X-Cf-True-Client-Ip", "8.8.8.8")
		Expect(err).NotTo(HaveOccurred())

		By("Correctly preserves the pre-existing True-Client-Ip Header")
		resp, err := client.Do(request)
		expect200(resp, err)
		headerKey := "X-Cf-True-Client-Ip"
		Expect(recordedHeaders).To(HaveKey(headerKey))
		Expect(recordedHeaders[headerKey]).To(HaveLen(1))
		Expect(ipAddresses).To(ContainElement(recordedHeaders[headerKey][0]))
	})
})

func getAllIpAddresses() (ips []string) {
	ifaces, err := net.Interfaces()
	if err != nil {
		fmt.Printf("Cannot get interface: %s", err)
		return
	}

	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 {
			continue
		}
		if iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			fmt.Printf("Cannot get addresses for interface %s: %s", iface.Name, err)
			continue
		}
		for _, addr := range addrs {
			var ip net.IP
			switch v := addr.(type) {
			case *net.IPNet:
				ip = v.IP
			case *net.IPAddr:
				ip = v.IP
			default:
				continue
			}
			if ip == nil || ip.IsLoopback() {
				continue
			}

			ips = append(ips, ip.String())
		}
	}
	return ips
}
