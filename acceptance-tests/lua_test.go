package acceptance_tests

import (
	"fmt"
	"net/http"
	"strings"
	"time"

	. "github.com/onsi/ginkgo"
	. "github.com/onsi/gomega"
)

var _ = FDescribe("Lua scripting", func() {
	It("Deploys haproxy with lua script", func() {
		opsfileLua := `---
# Enable Lua scripting
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/lua_scripts?/-
  value: "/var/vcap/packages/haproxy/lua_test.lua"
- type: replace
  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/frontend_config?
  value: |-
    acl lua_path path /lua_test
    http-request use-service lua.lua_test if lua_path`

		replyLuaContent := `
local function lua_test(applet)
    -- If client is POSTing request, receive body
    -- local request = applet:receive()

    local response = string.format([[<html>
    <body>Running %s</body>
</html>]], _VERSION)

    applet:set_status(200)
    applet:add_header("content-length", string.len(response))
    applet:add_header("content-type", "text/html")
    applet:add_header("lua-version", _VERSION)
    applet:start_response()
    applet:send(response)
end

core.register_service("lua_test", "http", lua_test)
		`

		haproxyBackendPort := 12000
		// Expect initial deployment to be failing due to lack of healthy backends
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileLua}, map[string]interface{}{}, false)

		// Verify that is in a failing state
		Expect(boshInstances(deploymentNameForTestNode())[0].ProcessState).To(Or(Equal("failing"), Equal("unresponsive agent")))

		// upload Lua script file
		uploadFile(haproxyInfo, strings.NewReader(replyLuaContent), "/var/vcap/packages/haproxy/lua_test.lua")

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		By("Waiting monit to report HAProxy is now healthy (the lua script was uploaded after start).")
		// Since the backend is now listening, HAProxy healthcheck should start returning healthy
		// and monit should in turn start reporting a healthy process
		// We will up to wait one minute for the status to stabilise
		Eventually(func() string {
			return boshInstances(deploymentNameForTestNode())[0].ProcessState
		}, time.Minute, time.Second).Should(Equal("running"))

		By("Sending a request to HAProxy with Lua endpoint")
		resp, err := http.Get(fmt.Sprintf("http://%s/lua_test", haproxyInfo.PublicIP))
		expectLuaServer200(resp, err)

		fmt.Printf("Server has Lua version %s", resp.Header["lua-version"])
	})
})
