# Improvements
- `ha_proxy.http_request_deny_conditions`  now supports negations of ACLs thanks to @gdenn
   Simply add the `negate: true` field to your ACL to negate it.
- `ha_proxy.cidrs_in_file` has been added to allow users to specify a wide array of ACLs
  that apply to an ACL in the `ha_proxy.http_request_deny_conditions` ACL list, which
  would otherwise be too long for haproxy to start up properly. Take a look at [the example]
  for more details(https://github.com/cloudfoundry-incubator/haproxy-boshrelease/blob/master/jobs/haproxy/spec#L396-L406).
  Thanks @gdenn for this feature as well!

# Bug Fixes

- Resolved an issue where the haproxy stop script would fail if haproxy was already stopped.
  Thanks for the fix @domdom82!
