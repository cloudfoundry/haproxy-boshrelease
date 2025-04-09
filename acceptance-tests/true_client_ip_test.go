package acceptance_tests

import (
	"crypto/tls"
	"fmt"
	"net"
	"net/http"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

const TrueClientIpHeader string = "X-Cf-True-Client-Ip"
const MockClientIp string = "8.8.8.8"

var _ = Describe("True Client IP", func() {

	opsFileTrueClientIp := fmt.Sprintf(`---
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/true_client_ip_header?
  value: "%s"
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/forward_true_client_ip_header?
  value: ((forward_true_client_ip_header))
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
`, TrueClientIpHeader)

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
	var err error
	var deployVars map[string]interface{}

	JustBeforeEach(func() {
		haproxyBackendPort := 12000

		haproxyInfo, varsStoreReader := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsFileTrueClientIp}, deployVars, true)

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

	Context("forward_true_client_ip_header: forward_only_if_route_service", func() {
		BeforeEach(func() {
			deployVars = map[string]interface{}{
				"forward_true_client_ip_header": "forward_only_if_route_service",
			}
		})

		It("Correctly handles True Client IP when forward_only_if_route_service option is selected", func() {
			ipAddresses := getAllIpAddresses()

			By("Adding a header with the provided name and correct value for the True Client ip, if it doesn't exist in a request")
			performRequest(client, false, false)
			expectTrueClientHeader(recordedHeaders, ipAddresses) // Header is added

			By("Overwriting the True-Client-Ip header if it is already set AND the request is NOT a route-service")
			performRequest(client, false, true)
			expectTrueClientHeader(recordedHeaders, ipAddresses) // Header is overwritten

			By("NOT overwriting the True-Client-Ip header if it is already set AND the request is a route-service")
			performRequest(client, true, true)
			expectTrueClientHeader(recordedHeaders, []string{MockClientIp}) // Header is forwarded
		})
	})

	Context("forward_true_client_ip_header: always_forward", func() {
		BeforeEach(func() {
			deployVars = map[string]interface{}{
				"forward_true_client_ip_header": "always_forward",
			}
		})

		It("Correctly handles True Client IP when always_forward option is selected", func() {
			ipAddresses := getAllIpAddresses()

			By("Adding a header with the provided name and correct value for the true client ip, if it doesn't exist in the request")
			performRequest(client, false, false)
			expectTrueClientHeader(recordedHeaders, ipAddresses) // Header is added

			By("NOT overwriting the True-Client-Ip header if it is already set AND the request is not a route-service")
			performRequest(client, false, true)
			expectTrueClientHeader(recordedHeaders, []string{MockClientIp}) // Header is forwarded

			By("NOT overwriting the True-Client-Ip header if it is already set AND the request is a route-service")
			performRequest(client, true, true)
			expectTrueClientHeader(recordedHeaders, []string{MockClientIp}) // Header is forwarded
		})
	})

	Context("forward_true_client_ip_header: always_set", func() {
		BeforeEach(func() {
			deployVars = map[string]interface{}{
				"forward_true_client_ip_header": "always_set",
			}
		})

		It("Correctly handles True Client IP when always_set option is selected", func() {
			ipAddresses := getAllIpAddresses()

			By("Adding a header with the provided name and correct value for the true client ip, if it doesn't exist")
			performRequest(client, false, false)
			expectTrueClientHeader(recordedHeaders, ipAddresses) // Header is overwritten

			By("Overwriting the True-Client-Ip header if it is already set AND the request is NOT a route-service")
			performRequest(client, false, true)
			expectTrueClientHeader(recordedHeaders, ipAddresses) // Header is overwritten

			By("Overwriting the True-Client-Ip header if it is already set AND the request is a route-service")
			performRequest(client, true, true)
			expectTrueClientHeader(recordedHeaders, ipAddresses) // Header is overwritten
		})
	})
})

func expectTrueClientHeader(recordedHeaders http.Header, expected []string) {
	if len(expected) > 0 {
		Expect(recordedHeaders).To(HaveKey(TrueClientIpHeader))
		Expect(recordedHeaders[TrueClientIpHeader]).To(HaveLen(1))
		Expect(expected).To(ContainElement(recordedHeaders[TrueClientIpHeader][0]))
	} else {
		Expect(recordedHeaders).NotTo(HaveKey(TrueClientIpHeader))
	}
}

func performRequest(client *http.Client, isRouteService bool, hasTrueClientIp bool) {
	request, err := http.NewRequest("GET", "https://haproxy.internal:443", nil)
	Expect(err).NotTo(HaveOccurred())
	if isRouteService {
		request.Header.Set("X-Cf-Proxy-Signature", "abc123")
	}
	if hasTrueClientIp {
		request.Header.Set(TrueClientIpHeader, MockClientIp)
	}

	resp, err := client.Do(request)
	expect200(resp, err)
}

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
