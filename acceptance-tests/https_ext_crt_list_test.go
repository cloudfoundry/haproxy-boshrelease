package acceptance_tests

import (
	"bytes"
	"crypto/tls"
	"fmt"
	"io"
	"net/http"
	"path/filepath"
	"strings"
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
	"github.com/onsi/gomega/gbytes"
	"github.com/onsi/gomega/gexec"
)

/*
	Tests support for external certificate lists. Test structure:

	1. Deploy HAProxy with internal certificate A
	2. Update external certificate list to add certificate B
	3. Verify that HTTPS requests using certificates A, B are working and C is not working
	4. Update external certificate list to remove B and add C
	5. Verify that HTTPS requests using certificates A, C are working and B is not working

*/

var _ = Describe("External Certificate Lists", func() {
	haproxyBackendPort := 12000

	It("Uses the correct certs", func() {
		opsfileSSLCertificate := `---
# Ensure HAProxy is in daemon mode (syslog server cannot be stdout)
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/syslog_server?
  value: "/var/vcap/sys/log/haproxy/syslog"
# Add CertA as a regular certificate
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/crt_list?/-
  value:
    snifilter:
    - cert_a.haproxy.internal
    ssl_pem:
      cert_chain: ((cert_a.certificate))((cert_a.ca))
      private_key: ((cert_a.private_key))

# Configure external certificate list
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/ext_crt_list?
  value: true
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/ext_crt_list_file?
  value: ((ext_crt_list_path))
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/ext_crt_list_policy?
  value: continue

# Generate CA and certificates
- type: replace
  path: /variables?/-
  value:
    name: common_ca
    type: certificate
    options:
      is_ca: true
      common_name: bosh
- type: replace
  path: /variables?/-
  value:
    name: cert_a
    type: certificate
    options:
      ca: common_ca
      common_name: cert_a.haproxy.internal
      alternative_names: [cert_a.haproxy.internal]
- type: replace
  path: /variables?/-
  value:
    name: cert_b
    type: certificate
    options:
      ca: common_ca
      common_name: cert_b.haproxy.internal
      alternative_names: [cert_b.haproxy.internal]
- type: replace
  path: /variables?/-
  value:
    name: cert_c
    type: certificate
    options:
      ca: common_ca
      common_name: cert_c.haproxy.internal
      alternative_names: [cert_c.haproxy.internal]
`

		extCrtListPath := "/var/vcap/jobs/haproxy/config/ssl/ext-crt-list"
		haproxyInfo, varsStoreReader := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        defaultDeploymentName,
		}, []string{opsfileSSLCertificate}, map[string]interface{}{
			"ext_crt_list_path": extCrtListPath,
		}, true)

		var creds struct {
			CertA struct {
				Certificate string `yaml:"certificate"`
				CA          string `yaml:"ca"`
				PrivateKey  string `yaml:"private_key"`
			} `yaml:"cert_a"`
			CertB struct {
				Certificate string `yaml:"certificate"`
				CA          string `yaml:"ca"`
				PrivateKey  string `yaml:"private_key"`
			} `yaml:"cert_b"`
			CertC struct {
				Certificate string `yaml:"certificate"`
				CA          string `yaml:"ca"`
				PrivateKey  string `yaml:"private_key"`
			} `yaml:"cert_c"`
		}
		err := varsStoreReader(&creds)
		Expect(err).NotTo(HaveOccurred())

		// Wait for HAProxy to accept TCP connections
		waitForHAProxyListening(haproxyInfo)

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		client := buildHTTPClient(
			[]string{creds.CertA.CA, creds.CertB.CA, creds.CertC.CA},
			map[string]string{
				"cert_a.haproxy.internal:443": fmt.Sprintf("%s:443", haproxyInfo.PublicIP),
				"cert_b.haproxy.internal:443": fmt.Sprintf("%s:443", haproxyInfo.PublicIP),
				"cert_c.haproxy.internal:443": fmt.Sprintf("%s:443", haproxyInfo.PublicIP),
			},
			[]tls.Certificate{}, "",
		)

		By("Sending a request to HAProxy using internal cert A works (default cert)")
		resp, err := client.Get("https://cert_a.haproxy.internal:443")
		Expect(err).NotTo(HaveOccurred())
		Expect(resp.StatusCode).To(Equal(http.StatusOK))
		Eventually(gbytes.BufferReader(resp.Body)).Should(gbytes.Say("Hello cloud foundry"))

		By("Sending a request to HAProxy using external cert B fails (external cert not yet added)")
		_, err = client.Get("https://cert_b.haproxy.internal:443")
		Expect(err).To(HaveOccurred())
		Expect(err.Error()).To(ContainSubstring("certificate is valid for cert_a.haproxy.internal, not cert_b.haproxy.internal"))

		By("Sending a request to HAProxy using external cert C fails (external cert not yet added)")
		_, err = client.Get("https://cert_c.haproxy.internal:443")
		Expect(err).To(HaveOccurred())
		Expect(err.Error()).To(ContainSubstring("certificate is valid for cert_a.haproxy.internal, not cert_c.haproxy.internal"))

		// external certs format is a concatenated file containing certificate PEM, CA PEM, private key PEM
		pemChainCertB := bytes.NewBufferString(strings.Join([]string{creds.CertB.Certificate, creds.CertB.CA, creds.CertB.PrivateKey}, "\n"))
		pemChainCertBPath := "/var/vcap/jobs/haproxy/config/ssl/cert_b.haproxy.internal.pem"
		pemChainCertC := bytes.NewBufferString(strings.Join([]string{creds.CertC.Certificate, creds.CertC.CA, creds.CertC.PrivateKey}, "\n"))
		pemChainCertCPath := "/var/vcap/jobs/haproxy/config/ssl/cert_c.haproxy.internal.pem"

		extCrtList := bytes.NewBufferString(fmt.Sprintf("%s cert_b.haproxy.internal\n", pemChainCertBPath))

		By("Uploading external certificates and external cert list to HAProxy")
		uploadFile(haproxyInfo, pemChainCertB, pemChainCertBPath)
		defer deleteRemoteFile(haproxyInfo, pemChainCertBPath)
		uploadFile(haproxyInfo, extCrtList, extCrtListPath)
		defer deleteRemoteFile(haproxyInfo, extCrtListPath)

		By("Reloading HAProxy")
		reloadHAProxy(haproxyInfo)

		By("Waiting for HAProxy to start listening (up to two minutes)")
		waitForHAProxyListening(haproxyInfo)

		By("Sending a request to HAProxy using internal cert A works (default cert)")
		resp, err = client.Get("https://cert_a.haproxy.internal:443")
		Expect(err).NotTo(HaveOccurred())
		Expect(resp.StatusCode).To(Equal(http.StatusOK))
		Eventually(gbytes.BufferReader(resp.Body)).Should(gbytes.Say("Hello cloud foundry"))

		By("Sending a request to HAProxy using external cert B works (external cert now added)")
		resp, err = client.Get("https://cert_b.haproxy.internal:443")
		Expect(err).NotTo(HaveOccurred())
		Expect(resp.StatusCode).To(Equal(http.StatusOK))
		Eventually(gbytes.BufferReader(resp.Body)).Should(gbytes.Say("Hello cloud foundry"))

		By("Sending a request to HAProxy using external cert C fails (external cert not yet added)")
		_, err = client.Get("https://cert_c.haproxy.internal:443")
		Expect(err).To(HaveOccurred())
		Expect(err.Error()).To(ContainSubstring("certificate is valid for cert_a.haproxy.internal, not cert_c.haproxy.internal"))

		By("Removing external cert B and adding externat cert C to external cert list")
		extCrtList = bytes.NewBufferString(fmt.Sprintf("%s cert_c.haproxy.internal\n", pemChainCertCPath))

		deleteRemoteFile(haproxyInfo, pemChainCertBPath)
		uploadFile(haproxyInfo, pemChainCertC, pemChainCertCPath)
		defer deleteRemoteFile(haproxyInfo, pemChainCertCPath)
		uploadFile(haproxyInfo, extCrtList, extCrtListPath)

		By("Reloading HAProxy")
		reloadHAProxy(haproxyInfo)

		By("Waiting for HAProxy to start listening (up to two minutes)")
		waitForHAProxyListening(haproxyInfo)

		By("Sending a request to HAProxy using internal cert A works (default cert)")
		resp, err = client.Get("https://cert_a.haproxy.internal:443")
		Expect(err).NotTo(HaveOccurred())
		Expect(resp.StatusCode).To(Equal(http.StatusOK))
		Eventually(gbytes.BufferReader(resp.Body)).Should(gbytes.Say("Hello cloud foundry"))

		By("Sending a request to HAProxy using external cert B fails (external cert that was removed)")
		_, err = client.Get("https://cert_b.haproxy.internal:443")
		Expect(err).To(HaveOccurred())
		Expect(err.Error()).To(ContainSubstring("certificate is valid for cert_a.haproxy.internal, not cert_b.haproxy.internal"))

		By("Sending a request to HAProxy using external cert C works (external cert that was added)")
		resp, err = client.Get("https://cert_c.haproxy.internal:443")
		Expect(err).NotTo(HaveOccurred())
		Expect(resp.StatusCode).To(Equal(http.StatusOK))
		Eventually(gbytes.BufferReader(resp.Body)).Should(gbytes.Say("Hello cloud foundry"))
	})

	Context("When ext_crt_list_policy is set to fail", func() {
		opfileExternalCertificatePolicyFail := `---
# Ensure HAProxy is in daemon mode (syslog server cannot be stdout)
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/syslog_server?
  value: "/var/vcap/sys/log/haproxy/syslog"

# Configure external certificate list properties
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/ext_crt_list?
  value: true
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/ext_crt_list_policy?
  value: fail
# crt_list or ssl_pem need to be non-nil for SSL to be enabled
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/crt_list?
  value: []
`

		Context("When the external certificate does not exist", func() {
			It("Fails the deployment", func() {
				deployHAProxy(baseManifestVars{
					haproxyBackendPort:    haproxyBackendPort,
					haproxyBackendServers: []string{"127.0.0.1"},
					deploymentName:        defaultDeploymentName,
				}, []string{opfileExternalCertificatePolicyFail}, map[string]interface{}{}, true)
			})
		})

		opsfileSSLCertVariable := `# Generate CA and certificates
- type: replace
  path: /variables?/-
  value:
    name: common_ca
    type: certificate
    options:
      is_ca: true
      common_name: bosh
- type: replace
  path: /variables?/-
  value:
    name: cert
    type: certificate
    options:
      ca: common_ca
      common_name: haproxy.internal
      alternative_names: [haproxy.internal]
`

		Context("When the external certificate does exist", func() {
			opsfileOSConfProvidedCertificate := `---
# Configure os-conf to install "external" cert in pre-start script
- type: replace
  path: /instance_groups/name=haproxy/jobs/-
  value:
    name: pre-start-script
    release: os-conf
    properties:
      script: |-
        #!/bin/bash
        mkdir -p /var/vcap/jobs/haproxy/config/ssl/ext

        # Write cert list to default external crt-list location
        echo '/var/vcap/jobs/haproxy/config/ssl/ext/os-conf-cert haproxy.internal' > /var/vcap/jobs/haproxy/config/ssl/ext/crt-list

        # Write cert chain
        echo '((cert.certificate))((cert.ca))((cert.private_key))' > /var/vcap/jobs/haproxy/config/ssl/ext/os-conf-cert

        # Ensure HAProxy can read certs
        chown -R vcap:vcap /var/vcap/jobs/haproxy/config/ssl/ext
`

			It("Succesfully loads and uses the certificate", func() {
				haproxyInfo, varsStoreReader := deployHAProxy(baseManifestVars{
					haproxyBackendPort:    haproxyBackendPort,
					haproxyBackendServers: []string{"127.0.0.1"},
					deploymentName:        defaultDeploymentName,
				}, []string{opfileExternalCertificatePolicyFail, opsfileOSConfProvidedCertificate, opsfileSSLCertVariable}, map[string]interface{}{}, true)

				// Ensure file written by os-conf is cleaned up for next test
				defer deleteRemoteFile(haproxyInfo, "/var/vcap/jobs/haproxy/config/ssl/ext")

				var creds struct {
					Cert struct {
						Certificate string `yaml:"certificate"`
						CA          string `yaml:"ca"`
						PrivateKey  string `yaml:"private_key"`
					} `yaml:"cert"`
				}
				err := varsStoreReader(&creds)
				Expect(err).NotTo(HaveOccurred())

				// Wait for HAProxy to accept TCP connections
				waitForHAProxyListening(haproxyInfo)

				closeLocalServer, localPort := startDefaultTestServer()
				defer closeLocalServer()

				closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
				defer closeTunnel()

				client := buildHTTPClient(
					[]string{creds.Cert.CA},
					map[string]string{"haproxy.internal:443": fmt.Sprintf("%s:443", haproxyInfo.PublicIP)},
					[]tls.Certificate{}, "",
				)

				By("Sending a request to HAProxy using the external cert")
				resp, err := client.Get("https://haproxy.internal:443")
				Expect(err).NotTo(HaveOccurred())
				Expect(resp.StatusCode).To(Equal(http.StatusOK))
				Eventually(gbytes.BufferReader(resp.Body)).Should(gbytes.Say("Hello cloud foundry"))
			})

			Context("When the external certificate is written after HAProxy is started", func() {
				It("Succesfully loads and uses the certificate", func() {
					// Ensure that HAProxy is already deployed
					haproxyInfo, varsStoreReader := deployHAProxy(baseManifestVars{
						haproxyBackendPort:    haproxyBackendPort,
						haproxyBackendServers: []string{"127.0.0.1"},
						deploymentName:        defaultDeploymentName,
					}, []string{opfileExternalCertificatePolicyFail, opsfileSSLCertVariable}, map[string]interface{}{}, true)

					var creds struct {
						Cert struct {
							Certificate string `yaml:"certificate"`
							CA          string `yaml:"ca"`
							PrivateKey  string `yaml:"private_key"`
						} `yaml:"cert"`
					}
					err := varsStoreReader(&creds)
					Expect(err).NotTo(HaveOccurred())

					// now redeploy using same vars
					baseManifestVars := baseManifestVars{
						haproxyBackendPort:    haproxyBackendPort,
						haproxyBackendServers: []string{"127.0.0.1"},
						deploymentName:        defaultDeploymentName,
					}
					// Override SSH key and certificate with existing values to avoid re-generating
					manifestVars := buildManifestVars(baseManifestVars, map[string]interface{}{
						"ssh_key": map[string]string{
							"private_key":            haproxyInfo.SSHPrivateKey,
							"public_key":             haproxyInfo.SSHPublicKey,
							"public_key_fingerprint": haproxyInfo.SSHPublicKeyFingerprint,
						},
						"cert": creds.Cert,
					})
					opsfiles := append(defaultOpsfiles, opfileExternalCertificatePolicyFail, opsfileSSLCertVariable)
					deployCmd, _ := deployBaseManifestCmd(defaultDeploymentName, opsfiles, manifestVars)
					// Recreate VM to ensure that HAProxy process is restarted
					deployCmd.Args = append(deployCmd.Args, "--recreate")
					buffer := gbytes.NewBuffer()
					session, err := gexec.Start(deployCmd, buffer, GinkgoWriter)
					Expect(err).NotTo(HaveOccurred())

					By("Waiting for monit to start HAProxy wrapper")
					Eventually(buffer, 10*time.Minute, time.Second).Should(gbytes.Say("Updating instance haproxy"))
					Eventually(buffer, 10*time.Minute, time.Second).Should(gbytes.Say("starting jobs: haproxy"))

					// wait 30 seconds to simulate delayed certificate update
					time.Sleep(30 * time.Second)

					// external certs format is a concatenated file containing certificate PEM, CA PEM, private key PEM
					extCertChain := bytes.NewBufferString(strings.Join([]string{creds.Cert.Certificate, creds.Cert.CA, creds.Cert.PrivateKey}, "\n"))
					extCertChainPath := "/var/vcap/jobs/haproxy/config/ssl/ext/cert.haproxy.internal.pem"
					extCrtList := bytes.NewBufferString(fmt.Sprintf("%s cert.haproxy.internal\n", extCertChainPath))
					extCrtListPath := "/var/vcap/jobs/haproxy/config/ssl/ext/crt-list"

					By("Uploading external certs while HAProxy wrapper is waiting")
					uploadFile(haproxyInfo, extCertChain, extCertChainPath)
					defer deleteRemoteFile(haproxyInfo, extCertChainPath)
					uploadFile(haproxyInfo, extCrtList, extCrtListPath)
					defer deleteRemoteFile(haproxyInfo, extCrtListPath)

					By("Waiting for second deploy to finish")
					Eventually(session, 10*time.Minute, time.Second).Should(gexec.Exit(0))

					// Wait for HAProxy to accept TCP connections
					waitForHAProxyListening(haproxyInfo)

					closeLocalServer, localPort := startDefaultTestServer()
					defer closeLocalServer()

					closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
					defer closeTunnel()

					client := buildHTTPClient(
						[]string{creds.Cert.CA},
						map[string]string{"haproxy.internal:443": fmt.Sprintf("%s:443", haproxyInfo.PublicIP)},
						[]tls.Certificate{}, "",
					)

					By("Sending a request to HAProxy using the external cert")
					resp, err := client.Get("https://haproxy.internal:443")
					Expect(err).NotTo(HaveOccurred())
					Expect(resp.StatusCode).To(Equal(http.StatusOK))
					Eventually(gbytes.BufferReader(resp.Body)).Should(gbytes.Say("Hello cloud foundry"))
				})
			})
		})
	})
})

func deleteRemoteFile(haproxyInfo haproxyInfo, remotePath string) {
	_, _, err := runOnRemote(haproxyInfo.SSHUser, haproxyInfo.PublicIP, haproxyInfo.SSHPrivateKey, fmt.Sprintf("sudo rm -rf %s", remotePath))
	Expect(err).NotTo(HaveOccurred())
}

func uploadFile(haproxyInfo haproxyInfo, contents io.Reader, remotePath string) {
	// Due to permissions issues with the SCP library
	// we need to upload to the tmp dir first, then copy to the intended directory
	// Finally chown to VCAP user to BOSH processes have permissions to read/write the file
	basename := filepath.Base(remotePath)
	tmpRemotePath := fmt.Sprintf("/tmp/%s", basename)

	err := copyFileToRemote(haproxyInfo.SSHUser, haproxyInfo.PublicIP, haproxyInfo.SSHPrivateKey, tmpRemotePath, contents, "0777")
	Expect(err).NotTo(HaveOccurred())

	_, _, err = runOnRemote(haproxyInfo.SSHUser, haproxyInfo.PublicIP, haproxyInfo.SSHPrivateKey, fmt.Sprintf("sudo mv %s %s", tmpRemotePath, remotePath))
	Expect(err).NotTo(HaveOccurred())

	_, _, err = runOnRemote(haproxyInfo.SSHUser, haproxyInfo.PublicIP, haproxyInfo.SSHPrivateKey, fmt.Sprintf("sudo chown vcap:vcap %s", remotePath))
	Expect(err).NotTo(HaveOccurred())
}
