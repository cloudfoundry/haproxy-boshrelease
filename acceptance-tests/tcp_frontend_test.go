package acceptance_tests

import (
	"context"
	"fmt"
	"net/http"
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/gbytes"
)

var _ = Describe("TCP Frontend", func() {
	AfterEach(func() {
		deleteDeployment()
	})

	It("Correctly proxies TCP requests", func() {
		opsfileTCP := `---
# Configure TCP Backend
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/tcp?/-
  value:
    backend_port: ((tcp_backend_port))
    port: ((tcp_frontend_port))
    backend_servers:
    - 127.0.0.1
    name: test
`
		tcpFrontendPort := 13000
		tcpBackendPort := 13001
		haproxyInfo, _ := deployHAProxy(12000, []string{opsfileTCP}, map[string]interface{}{
			"tcp_frontend_port": tcpFrontendPort,
			"tcp_backend_port":  tcpBackendPort,
		})

		dumpHAProxyConfig(haproxyInfo)

		//---------------------------------------------------------------------------------
		By("Starting a local http server")
		closeLocalServer, localPort, err := startLocalHTTPServer(func(w http.ResponseWriter, r *http.Request) {
			fmt.Fprintln(w, "Hello cloud foundry")
		})
		defer closeLocalServer()
		Expect(err).NotTo(HaveOccurred())

		By(fmt.Sprintf("Creating a reverse SSH tunnel from HAProxy TCP backend (port %d) to local HTTP server (port %d)", tcpBackendPort, localPort))
		ctx, cancelFunc := context.WithCancel(context.Background())
		defer cancelFunc()
		err = startReverseSSHPortForwarder(haproxyInfo.SSHUser, haproxyInfo.PublicIP, haproxyInfo.SSHPrivateKey, tcpBackendPort, localPort, ctx)
		Expect(err).NotTo(HaveOccurred())

		By("Waiting a few seconds so that HAProxy can detect the backend server is listening")
		// HAProxy backend health check interval is 1 second so this should be plenty
		time.Sleep(5 * time.Second)

		By("Sending a request to the HAProxy TCP endpoint")
		resp, err := http.Get(fmt.Sprintf("http://%s:%d", haproxyInfo.PublicIP, tcpFrontendPort))
		Expect(err).NotTo(HaveOccurred())
		Expect(resp.StatusCode).To(Equal(http.StatusOK))
		Eventually(gbytes.BufferReader(resp.Body)).Should(gbytes.Say("Hello cloud foundry"))
	})
})
