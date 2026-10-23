package acceptance_tests

import (
	"fmt"
	"regexp"
	"strings"

	. "github.com/onsi/ginkgo/v2"
	. "github.com/onsi/gomega"
)

// Verifies that the SSL backend actually running on the VM matches the variant
// the release was assembled with (config.Variant, from the VARIANT env var).
//
// The signal is the running binary's `haproxy -vv`, which reports two dedicated
// lines describing the library loaded at runtime (verified against real output
// from AWS-LC 4.0.0 / OpenSSL 3.0.13):
//
//	variant      "Running on SSL library version : ..."   "SSL library FIPS mode : ..."
//	openssl      OpenSSL 3.0.13 30 Jan 2024               (line absent)
//	awslc        AWS-LC 4.0.0                             no
//	awslc-fips   AWS-LC FIPS 4.0.0                        yes
var (
	runningSSLLibRe = regexp.MustCompile(`Running on SSL library version\s*:\s*(.+)`)
	sslFIPSModeOnRe = regexp.MustCompile(`SSL library FIPS mode\s*:\s*yes`)
)

var _ = Describe("SSL variant", func() {
	It("Runs the HAProxy binary for the configured SSL variant", func() {
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    12000,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{}, map[string]interface{}{}, true)

		By("Reading the SSL library from the running HAProxy binary (haproxy -vv)")
		versionInfo := runningHAProxyVersionInfo(haproxyInfo)
		fmt.Fprintf(GinkgoWriter, "----- haproxy -vv (variant %q) -----\n%s\n", config.Variant, versionInfo)

		match := runningSSLLibRe.FindStringSubmatch(versionInfo)
		Expect(match).NotTo(BeNil(), "no 'Running on SSL library version' line in haproxy -vv:\n%s", versionInfo)
		runningSSL := strings.TrimSpace(match[1])

		isAWSLC := strings.Contains(runningSSL, "AWS-LC")
		fipsMode := sslFIPSModeOnRe.MatchString(versionInfo)

		switch {
		case strings.HasPrefix(config.Variant, "awslc-fips"):
			By("Expecting AWS-LC FIPS")
			Expect(isAWSLC).To(BeTrue(), "expected AWS-LC, running SSL library was %q", runningSSL)
			Expect(fipsMode).To(BeTrue(), "expected FIPS mode on; haproxy -vv was:\n%s", versionInfo)
		case strings.HasPrefix(config.Variant, "awslc"):
			By("Expecting AWS-LC (non-FIPS)")
			Expect(isAWSLC).To(BeTrue(), "expected AWS-LC, running SSL library was %q", runningSSL)
			Expect(fipsMode).To(BeFalse(), "expected FIPS mode off; haproxy -vv was:\n%s", versionInfo)
		default:
			// openssl (VARIANT unset/openssl); patches are an orthogonal axis and don't change the library.
			By("Expecting system OpenSSL")
			Expect(runningSSL).To(ContainSubstring("OpenSSL"), "expected OpenSSL, running SSL library was %q", runningSSL)
			Expect(isAWSLC).To(BeFalse(), "expected OpenSSL but found AWS-LC, running SSL library was %q", runningSSL)
			Expect(fipsMode).To(BeFalse(), "expected FIPS mode off; haproxy -vv was:\n%s", versionInfo)
		}
	})
})
