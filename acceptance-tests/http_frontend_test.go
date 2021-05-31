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

var _ = Describe("HTTP Frontend", func() {
	AfterEach(func() {
		deleteDeployment()
	})

	It("Correctly proxies HTTP requests", func() {
		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(haproxyBackendPort, []string{}, map[string]interface{}{})

		dumpHAProxyConfig(haproxyInfo)

		By("Starting a local http server")
		closeLocalServer, localPort, err := startLocalHTTPServer(func(w http.ResponseWriter, r *http.Request) {
			fmt.Fprintln(w, "Hello cloud foundry")
		})
		defer closeLocalServer()
		Expect(err).NotTo(HaveOccurred())

		By(fmt.Sprintf("Creating a reverse SSH tunnel from HAProxy backend (port %d) to local HTTP server (port %d)", haproxyBackendPort, localPort))
		ctx, cancelFunc := context.WithCancel(context.Background())
		defer cancelFunc()
		err = startReverseSSHPortForwarder(haproxyInfo.SSHUser, haproxyInfo.PublicIP, haproxyInfo.SSHPrivateKey, haproxyBackendPort, localPort, ctx)
		Expect(err).NotTo(HaveOccurred())

		By("Waiting a few seconds so that HAProxy can detect the backend server is listening")
		// HAProxy backend health check interval is 1 second so this should be plenty
		time.Sleep(5 * time.Second)

		By("Sending a request to HAProxy")
		resp, err := http.Get(fmt.Sprintf("http://%s", haproxyInfo.PublicIP))
		Expect(err).NotTo(HaveOccurred())
		Expect(resp.StatusCode).To(Equal(http.StatusOK))
		Eventually(gbytes.BufferReader(resp.Body)).Should(gbytes.Say("Hello cloud foundry"))
	})
})
