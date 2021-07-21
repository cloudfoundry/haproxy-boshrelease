# New Features
- Allow disabling TLSv1.2 [details](https://github.com/cloudfoundry-incubator/haproxy-boshrelease/blob/ae5307068719795e7a57a244c2edd0ef15fb59a8/jobs/haproxy/spec#L233)
- Allow disabling TLSv1.3 [details](https://github.com/cloudfoundry-incubator/haproxy-boshrelease/blob/ae5307068719795e7a57a244c2edd0ef15fb59a8/jobs/haproxy/spec#L236)
- New property `lua_scripts_per_thread` that defines list of LUA scripts that HA Proxy should load per thread. Existing `lua_scripts` property remains unchanged [details](https://github.com/cloudfoundry-incubator/haproxy-boshrelease/blob/a525668ffe91d12287c9f1845199802c0cedbc34/jobs/haproxy/spec#L523)

# Upgrades
| Dependency | Old     | New     |
|------------|---------|---------|
| HAproxy    | 2.2.14  | 2.4.2   |
| Lua        | 5.4.1   | 5.4.3   |
| PCRE       | 10.34   | 10.37   |
| Socat      | 1.7.3.4 | 1.7.4.1 |
| keepalived | 1.2.24  | 2.2.2   |
| Stemcell   | xenial  | bionic  |

# Acknowledgements

Thanks @dtimm, @peterellisjones and @domdom82 for the PR / fixes!