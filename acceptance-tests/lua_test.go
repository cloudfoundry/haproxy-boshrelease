package acceptance_tests

import (
	"net/http"
	"strings"

	. "github.com/onsi/ginkgo"
)

// TODO:
// - load lua script that modifies default response somehow
// inject `lua-load /reply.lua` under global in haproxy.config
// haproxy.config frontend section
// http-request lua.rp
// http-request use-service lua.reply

// do http.Get(), parse response

var _ = Describe("Lua scripting", func() {
	It("Deploys haproxy with lua script", func() {
		opsfileLua := `---
		# Enable Lua scripting
		- type: replace
			path:  /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/lua_scripts?
			value: /var/vcap/packages/haproxy/reply.lua
		- type: replace
		  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/frontend_config?
		  value: |-
			http-request lua.rp
			http-request use-service lua.reply
			`

		replyLuaTargetPath := "/var/vcap/packages/haproxy/reply.lua"
		replyLuaContent := `core.register_service("reply", "http", function(applet)
			local response = "Got these headers: \n"
			for k, v in pairs(applet.headers) do
			response = response .. k .. " = " .. v[0] .. "\n"
			end

			applet:set_status(200)
			applet:add_header("content-length", string.len(response))
			applet:add_header("content-type", "text/plain")
			applet:start_response()
			applet:send(response)
		end)`

		haproxyBackendPort := 12000
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileLua}, map[string]interface{}{}, true)

		// upload Lua script file
		uploadFile(haproxyInfo, strings.NewReader(replyLuaContent), replyLuaTargetPath)

		closeLocalServer, localPort := startDefaultTestServer()
		defer closeLocalServer()

		closeTunnel := setupTunnelFromHaproxyToTestServer(haproxyInfo, haproxyBackendPort, localPort)
		defer closeTunnel()

		By("Sending a request to HAProxy ") // TODO:
		expectTestServer200(http.Get("http://127.0.0.1:12000"))
	})
})
