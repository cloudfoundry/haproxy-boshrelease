package acceptance_tests

import (
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"time"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

var _ = Describe("Drain Test", func() {
	opsfileDrainTimeout := `---
# Enable health check
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/enable_health_check_http?
  value: true
# Enable draining
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/drain_enable?
  value: true
# Set grace period to 10s
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/drain_frontend_grace_time?
  value: 10
# Set drain period to 10s
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/drain_timeout?
  value: 10
# Increase idle timeout between requests
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/keepalive_timeout?
  value: 60
`
	It("Honors grace and drain periods", func() {
		haproxyBackendPort := 12000
		// Expect initial deployment to be failing due to lack of healthy backends
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileDrainTimeout}, map[string]interface{}{}, false)

		// Verify that is in a failing state
		Expect(boshInstances(deploymentNameForTestNode())[0].ProcessState).To(Or(Equal("failing"), Equal("unresponsive agent")))

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		By("Waiting monit to report HAProxy is now healthy (due to having a healthy backend instance)")
		// Since the backend is now listening, HAProxy healthcheck should start returning healthy
		// and monit should in turn start reporting a healthy process
		// We will up to wait one minute for the status to stabilise
		Eventually(func() string {
			return boshInstances(deploymentNameForTestNode())[0].ProcessState
		}, time.Minute, time.Second).Should(Equal("running"))

		By("The healthcheck health endpoint should report a 200 status code")
		expect200(http.Get(fmt.Sprintf("http://%s:8080/health", haproxyInfo.PublicIP)))

		By("Sending a request to HAProxy works")
		expectTestServer200(http.Get(fmt.Sprintf("http://%s", haproxyInfo.PublicIP)))

		By("Draining HAproxy should first shut down health check, listeners still working")
		drainHAProxy(haproxyInfo)

		_, err := http.Get(fmt.Sprintf("http://%s:8080/health", haproxyInfo.PublicIP))
		expectConnectionRefusedErr(err)
		expectTestServer200(http.Get(fmt.Sprintf("http://%s", haproxyInfo.PublicIP)))
		time.Sleep(10 * time.Second)

		By("After grace period has passed, draining should set in, disabling listeners")
		// We need a new client so there won't be any reusable connections
		httpClient := &http.Client{}
		_, err = httpClient.Get(fmt.Sprintf("http://%s:8080/health", haproxyInfo.PublicIP))
		expectConnectionRefusedErr(err)
		_, err = httpClient.Get(fmt.Sprintf("http://%s", haproxyInfo.PublicIP))
		expectConnectionRefusedErr(err)
	})

	// drain with a non-existent Process
	It("Stale PID should be ignored", func() {
		haproxyBackendPort := 12000
		// Expect initial deployment to be failing due to lack of healthy backends
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileDrainTimeout}, map[string]interface{}{}, false)

		// Verify that is in a failing state
		Expect(boshInstances(deploymentNameForTestNode())[0].ProcessState).To(Or(Equal("failing"), Equal("unresponsive agent")))

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		By("Waiting for monit to report HAProxy is now healthy (due to having a healthy backend instance)")
		// Since the backend is now listening, HAProxy healthcheck should start returning healthy
		// and monit should in turn start reporting a healthy process
		// We will up to wait one minute for the status to stabilise
		Eventually(func() string {
			return boshInstances(deploymentNameForTestNode())[0].ProcessState
		}, time.Minute, time.Second).Should(Equal("running"))

		By("The healthcheck health endpoint should report a 200 status code")
		expect200(http.Get(fmt.Sprintf("http://%s:8080/health", haproxyInfo.PublicIP)))

		By("Sending a request to HAProxy works")
		expectTestServer200(http.Get(fmt.Sprintf("http://%s", haproxyInfo.PublicIP)))

		// Set a fake PID of the parent process haproxy_wrapper
		_, _, err := runOnRemote(haproxyInfo.SSHUser, haproxyInfo.PublicIP, haproxyInfo.SSHPrivateKey, "sudo cat /var/vcap/sys/run/bpm/haproxy/haproxy.pid > /tmp/haproxy.pid")
		Expect(err).NotTo(HaveOccurred())
		_, _, err = runOnRemote(haproxyInfo.SSHUser, haproxyInfo.PublicIP, haproxyInfo.SSHPrivateKey, "echo 32761 | sudo tee /var/vcap/sys/run/bpm/haproxy/haproxy.pid")
		Expect(err).NotTo(HaveOccurred())

		By("Draining HAproxy, drain script should not fail and HAproxy should still be healthy")
		drainHAProxy(haproxyInfo)

		_, _, err = runOnRemote(haproxyInfo.SSHUser, haproxyInfo.PublicIP, haproxyInfo.SSHPrivateKey, "cat /tmp/haproxy.pid | sudo tee /var/vcap/sys/run/bpm/haproxy/haproxy.pid")
		Expect(err).NotTo(HaveOccurred())

		By("The healthcheck health endpoint should report a 200 status code")
		expect200(http.Get(fmt.Sprintf("http://%s:8080/health", haproxyInfo.PublicIP)))

		By("Sending a request to HAProxy works")
		expectTestServer200(http.Get(fmt.Sprintf("http://%s", haproxyInfo.PublicIP)))
	})

	It("Closes idle connections gracefully", func() {
		haproxyBackendPort := 12000
		// Expect initial deployment to be failing due to lack of healthy backends
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileDrainTimeout}, map[string]interface{}{}, false)

		// Verify that is in a failing state
		Expect(boshInstances(deploymentNameForTestNode())[0].ProcessState).To(Or(Equal("failing"), Equal("unresponsive agent")))

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		By("Waiting monit to report HAProxy is now healthy (due to having a healthy backend instance)")
		// Since the backend is now listening, HAProxy healthcheck should start returning healthy
		// and monit should in turn start reporting a healthy process
		// We will up to wait one minute for the status to stabilise
		Eventually(func() string {
			return boshInstances(deploymentNameForTestNode())[0].ProcessState
		}, time.Minute, time.Second).Should(Equal("running"))

		By("The healthcheck health endpoint should report a 200 status code")
		expect200(http.Get(fmt.Sprintf("http://%s:8080/health", haproxyInfo.PublicIP)))

		By("Sending request using keep-alive works")
		conn, err := net.Dial("tcp", fmt.Sprintf("%s:80", haproxyInfo.PublicIP))
		defer conn.Close()
		Expect(err).ToNot(HaveOccurred())

		sendHTTP := func(conn net.Conn) string {
			_, err := conn.Write([]byte(strings.Join([]string{
				"GET / HTTP/1.1",
				fmt.Sprintf("Host: %s", haproxyInfo.PublicIP),
				"Content-Length: 0",
				"Content-Type: text/plain",
				"\r\n",
			}, "\r\n")))

			Expect(err).ToNot(HaveOccurred())

			// Too lazy to properly parse headers? Just stop reading after a second!
			_ = conn.SetReadDeadline(time.Now().Add(time.Second))

			response, _ := io.ReadAll(conn)
			return string(response)
		}

		response := sendHTTP(conn)
		Expect(response).NotTo(ContainSubstring("connection: close"))

		drainHAProxy(haproxyInfo)
		time.Sleep(10 * time.Second)

		By("During draining, idle connections should be closed upon the next request")
		response = sendHTTP(conn)
		Expect(response).To(ContainSubstring("connection: close"))
	})

})
