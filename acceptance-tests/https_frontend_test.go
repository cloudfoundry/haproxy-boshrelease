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

var _ = Describe("HTTPS Frontend", func() {
	AfterEach(func() {
		deleteDeployment()
	})

	It("Correctly proxies HTTPS requests", func() {
		opsfileSSLCertificate := `---
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

		haproxyBackendPort := 12000
		haproxyInfo, varsStoreReader := deployHAProxy(haproxyBackendPort, []string{opsfileSSLCertificate}, map[string]interface{}{})

		dumpHAProxyConfig(haproxyInfo)

		var creds struct {
			HTTPSFrontend struct {
				Certificate string `yaml:"certificate"`
				PrivateKey  string `yaml:"private_key"`
				CA          string `yaml:"ca"`
			} `yaml:"https_frontend"`
		}

		err := varsStoreReader(&creds)
		Expect(err).NotTo(HaveOccurred())

		By("Starting a local http server to act as a backend")
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

		client := buildHTTPClient(
			[]string{creds.HTTPSFrontend.CA},
			map[string]string{"haproxy.internal:443": fmt.Sprintf("%s:443", haproxyInfo.PublicIP)},
		)

		By("Sending a request to HAProxy")
		resp, err := client.Get("https://haproxy.internal:443")
		Expect(err).NotTo(HaveOccurred())
		Expect(resp.StatusCode).To(Equal(http.StatusOK))
		Eventually(gbytes.BufferReader(resp.Body)).Should(gbytes.Say("Hello cloud foundry"))
	})
})
