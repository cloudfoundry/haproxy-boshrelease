package acceptance_tests

import (
	"bytes"
	"fmt"
	"net"
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

var _ = Describe("Master CLI", func() {
	It("Works when enabled", func() {
		opsfileMasterCLI := `---
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/master_cli_enable?
  value: true
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/master_cli_bind?
  value: '0.0.0.0:9001'
`
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    12000,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        defaultDeploymentName,
		}, []string{opsfileMasterCLI}, map[string]interface{}{}, true)

		By("The master CLI 'show proc' command works")
		output, err := haproxyCLICommand("show proc", fmt.Sprintf("%s:9001", haproxyInfo.PublicIP))
		Expect(err).NotTo(HaveOccurred())

		// Example expected output
		// #<PID>          <type>          <relative PID>  <reloads>       <uptime>        <version>
		// 15              master          0               0               0d00h11m09s     2.2.14-a07ac36
		// # workers
		// 17              worker          1               0               0d00h11m09s     2.2.14-a07ac36
		Expect(string(output)).To(MatchRegexp("[0-9]+[\\s]+master"))
		Expect(string(output)).To(MatchRegexp("[0-9]+[\\s]+worker"))
	})
})

func haproxyCLICommand(command string, addr string) (string, error) {
	conn, err := net.DialTimeout("tcp", addr, 5*time.Second)
	if err != nil {
		return "", err
	}
	defer conn.Close()

	// HAProxy master CLI does not close connection after writing response,
	// so we will close after one second
	if err := conn.SetDeadline(time.Now().Add(time.Second)); err != nil {
		return "", err
	}

	if _, err := conn.Write([]byte(fmt.Sprintf("%s\n", command))); err != nil {
		return "", err
	}

	var buffer bytes.Buffer
	if _, err := buffer.ReadFrom(conn); err != nil && !isTimeoutError(err) {
		return "", err
	}

	return buffer.String(), nil
}

func isTimeoutError(err error) bool {
	e, ok := err.(net.Error)
	return ok && e.Timeout()
}
