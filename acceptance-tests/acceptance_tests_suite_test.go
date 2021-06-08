package acceptance_tests

import (
	"context"
	"fmt"
	"net/http"
	"testing"
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

func TestAcceptanceTests(t *testing.T) {
	RegisterFailHandler(Fail)
	RunSpecs(t, "AcceptanceTests Suite")
}

var _ = BeforeSuite(func() {
	var err error
	config, err = loadConfig()
	Expect(err).NotTo(HaveOccurred())
})

var _ = AfterSuite(func() {
})

// Starts a simple test server that returns 200 OK
func startDefaultTestServer() (func(), int) {
	By("Starting a local http server to act as a backend")
	closeLocalServer, localPort, err := startLocalHTTPServer(func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "Hello cloud foundry")
	})
	Expect(err).NotTo(HaveOccurred())
	return closeLocalServer, localPort
}

// Sets up SSH tunnel from HAProxy VM to test server
func setupTunnelFromHaproxyToTestServer(haproxyInfo haproxyInfo, haproxyBackendPort, localPort int) func() {
	By(fmt.Sprintf("Creating a reverse SSH tunnel from HAProxy backend (port %d) to local HTTP server (port %d)", haproxyBackendPort, localPort))
	ctx, cancelFunc := context.WithCancel(context.Background())
	err := startReverseSSHPortForwarder(haproxyInfo.SSHUser, haproxyInfo.PublicIP, haproxyInfo.SSHPrivateKey, haproxyBackendPort, localPort, ctx)
	Expect(err).NotTo(HaveOccurred())

	By("Waiting a few seconds so that HAProxy can detect the backend server is listening")
	// HAProxy backend health check interval is 1 second
	// So we wait five seconds here to ensure that HAProxy
	// has time to verify that the backend is now up
	time.Sleep(5 * time.Second)

	return cancelFunc
}

// Sets up SSH tunnel from local machine to HAProxy
func setupTunnelFromLocalMachineToHAProxy(haproxyInfo haproxyInfo, localPort, haproxyPort int) func() {
	By(fmt.Sprintf("Creating a SSH tunnel from localmachine (port %d) to HAProxy (port %d)", localPort, haproxyPort))
	ctx, cancelFunc := context.WithCancel(context.Background())
	err := startSSHPortForwarder(haproxyInfo.SSHUser, haproxyInfo.PublicIP, haproxyInfo.SSHPrivateKey, localPort, haproxyPort, ctx)
	Expect(err).NotTo(HaveOccurred())

	return cancelFunc
}
