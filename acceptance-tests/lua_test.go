package acceptance_tests

import (
	"fmt"
	"net/http"
	"strings"

	. "github.com/onsi/ginkgo"
)

var _ = Describe("Lua scripting", func() {
	It("Deploys haproxy with lua script", func() {
		replyLuaTargetPath := "/var/vcap/packages/haproxy/lua_test.lua"
		opsfileLua := fmt.Sprintf(`---
		# Enable Lua scripting
		- type: replace
			path:  /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/lua_scripts?
			value: %s
		- type: replace
		  path: /instance_groups/name=haproxy/jobs/name=haproxy/properties/ha_proxy/frontend_config?
		  value: |-
			http-request use-service lua.lua_test if { path /lua_test }
			`, replyLuaTargetPath)

		replyLuaContent := `
local function lua_test(applet)
    -- If client is POSTing request, receive body
    -- local request = applet:receive()

    local response = string.format([[
        <html>
            <body>Running Lua %s</body>
        </html>
    ]], _VERSION)

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
		haproxyInfo, _ := deployHAProxy(baseManifestVars{
			haproxyBackendPort:    haproxyBackendPort,
			haproxyBackendServers: []string{"127.0.0.1"},
			deploymentName:        deploymentNameForTestNode(),
		}, []string{opsfileLua}, map[string]interface{}{}, true)

		// upload Lua script file
		uploadFile(haproxyInfo, strings.NewReader(replyLuaContent), replyLuaTargetPath)

		By("Sending a request to HAProxy with Lua endpoint")
		resp, err := http.Get(fmt.Sprintf("http://%s/lua_test", haproxyInfo.PublicIP))
		expectLuaServer200(resp, err)

		fmt.Printf("Server has Lua version %s", resp.Header["lua-version"])
	})
})
