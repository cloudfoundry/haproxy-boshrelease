package acceptance_tests

import (
	"fmt"
	"net/http"
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
		_, err = http.Get(fmt.Sprintf("http://%s:8080/health", haproxyInfo.PublicIP))
		expectConnectionRefusedErr(err)
		_, err = http.Get(fmt.Sprintf("http://%s", haproxyInfo.PublicIP))
		expectConnectionRefusedErr(err)
	})

	// drain with an inexisting Process
	It("Honors grace and drain periods with stale PID", func() {
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
})
