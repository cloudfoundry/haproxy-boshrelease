package acceptance_tests

import (
	"fmt"
	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
	proxyproto "github.com/pires/go-proxyproto"
	"net"
	"net/http"
	"time"
)

var _ = Describe("Proxy Protocol", func() {
	opsfileProxyProtocol := `---
# Enable Proxy Protocol
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/accept_proxy?
  value: true
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/enable_health_check_http?
  value: true
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/disable_health_check_proxy?
  value: false
`
	It("Correctly proxies Proxy Protocol requests", func() {
		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileProxyProtocol}, map[string]interface{}{}, false)

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		By("Waiting for monit to report that HAProxy is healthy")
		// Since the backend is now listening, HAProxy healthcheck should start returning healthy
		// and monit should in turn start reporting a healthy process
		// We will wait up to one minute for the status to stabilise
		Eventually(func() string {
			return boshInstances(deploymentNameForTestNode())[0].ProcessState
		}, time.Minute, time.Second).Should(Equal("running"))

		By("Sending a request with Proxy Protocol Header to HAProxy traffic port")
		err := performProxyProtocolRequest(haproxyInfo.PublicIP, 80, "/")
		Expect(err).NotTo(HaveOccurred())

		By("Sending a request without Proxy Protocol Header to HAProxy")
		_, err = http.Get(fmt.Sprintf("http://%s", haproxyInfo.PublicIP))
		expectConnectionResetErr(err)

		By("Sending a request with Proxy Protocol Header to HAProxy health check port")
		err = performProxyProtocolRequest(haproxyInfo.PublicIP, 8080, "/health")
		Expect(err).NotTo(HaveOccurred())

		By("Sending a request without Proxy Protocol Header to HAProxy health check port")
		_, err = http.Get(fmt.Sprintf("http://%s:8080/health", haproxyInfo.PublicIP))
		expectConnectionResetErr(err)

	})
})

var _ = Describe("Proxy Protocol with specified expect_proxy and accept_proxy=false", func() {
	opsfileProxyProtocol := `---
# Enable Proxy Protocol for specified CIDRs
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/accept_proxy?
  value: false
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/expect_proxy?
  value:
    - 127.0.0.1/8
    - ::1/128
`
	It("Correctly proxies Proxy Protocol requests", func() {
		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileProxyProtocol}, map[string]interface{}{}, false)

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		By("Waiting for monit to report that HAProxy is healthy")
		// Since the backend is now listening, HAProxy healthcheck should start returning healthy
		// and monit should in turn start reporting a healthy process
		// We will wait up to one minute for the status to stabilise
		Eventually(func() string {
			return boshInstances(deploymentNameForTestNode())[0].ProcessState
		}, time.Minute, time.Second).Should(Equal("running"))

		By("Sending a request with Proxy Protocol Header to HAProxy traffic port")
		err := performProxyProtocolRequest(haproxyInfo.PublicIP, 80, "/")
		Expect(err).NotTo(HaveOccurred())
	})
})


func performProxyProtocolRequest(ip string, port int, endpoint string) error {
	// Create a connection to the HAProxy instance
	conn, err := net.Dial("tcp", fmt.Sprintf("%s:%d", ip, port))
	if err != nil {
		return err
	}

	defer conn.Close()

	// Create proxy protocol header
	header := &proxyproto.Header{
		Version:           1,
		Command:           proxyproto.PROXY,
		TransportProtocol: proxyproto.TCPv4,
		SourceAddr: &net.TCPAddr{
			IP:   net.ParseIP("10.1.1.1"),
			Port: 1000,
		},
		DestinationAddr: &net.TCPAddr{
			IP:   net.ParseIP(ip),
			Port: port,
		},
	}

	// Write header to the connection
	_, err = header.WriteTo(conn)
	if err != nil {
		return err
	}

	// Send HTTP Request
	request := fmt.Sprintf("GET %s HTTP/1.1\r\n"+
		"Host: %s\r\n"+
		"Content-Length: 0\r\n"+
		"Content-Type: text/plain\r\n"+
		"\r\n", endpoint, ip)
	_, err = conn.Write([]byte(request))
	if err != nil {
		return err
	}

	// Read the response
	buf := make([]byte, 1024)
	_, err = conn.Read(buf)
	if err != nil {
		return err
	}

	// Get HTTP status code
	if string(buf[9:12]) != "200" {
		return fmt.Errorf("expected HTTP status code 200, got %s", string(buf))
	}
	return nil
}
