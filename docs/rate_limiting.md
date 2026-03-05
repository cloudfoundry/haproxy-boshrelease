# Client IP based Rate Limiting
Rate limits in HAProxy are based on stick-tables. The concept of stick-tables is explained in [this blog article](https://www.haproxy.com/blog/introduction-to-haproxy-stick-tables/). It covers all relevant parts and gives a general idea on how one could rate limit based on certain attributes.

HAProxy-boshrelease can be configured to enforce these rate limits based on requests and connections per second per IP.

## Configuration Options
See also `jobs/haproxy/spec`:

There are two rate limit configuration groups:
- `connections_rate_limit` for connection based rate limiting on OSI layer 4/TCP
- `requests_rate_limit` for request based rate limiting on OSI layer 7/HTTP

Both groups contain the (roughly) same attributes :
- `requests` (for `requests_rate_limit`) and `connections` (for `connections_rate_limit`): the amount of requests/connections that are allowed within a time window (see `window_size`) before further incoming requests/connections are denied/blocked
- `window_size`: Window size for counting connections
- `table_size`: Size of the stick table in which the IPs and counters are stored.
- `block`: Whether or not to block connections. If `block` is disabled (or not provided), incoming requests/connections will still be tracked in the respective stick-tables, but will not be denied.

> **Note for `connections_rate_limit`:** The `block` flag and `connections` threshold are stored as HAProxy process-level variables (`proc.conn_rate_limit_enabled` and `proc.conn_rate_limit`). Their initial values are set from the BOSH manifest at startup, but they can be adjusted at runtime without reloading HAProxy by using `set-var` via the stats socket:

## Effects of Rate Limiting
Once a rate-limit is reached, haproxy-boshrelease will no longer proxy incoming request from the rate-limited client IP to a backend. Depending on the type of rate limiting, haproxy will respond with one of the following:

### Request based Rate Limiting
HAProxy responds the client with HTTP Status Code: `429: Too Many Requests`.

### Connection based Rate Limiting
The TCP connection will be rejected. This would for example show up as `Empty reply from server` for a `curl`-client.
This will not result in a log statement on HAProxy side, which can make tracing issues more difficult.

> Note:
> If both rate-limits are reached simultaneously (e.g. if they are configured identically and every incoming HTTP request uses a new TCP connection), connection based rate-limiting will come into effect first, resulting in a dropped TCP connection.


## Configuration Examples
> Note:
> The following example assume only a `http-in` frontend is configured, a `https-in` frontend would behave identically

### Count Incoming Requests Only (No blocking)
#### Configuration (`deployments/haproxy/config.yml`)
```yml
config:
    # [...]
    requests_rate_limit:
        window_size: 10s
        table_size: 1m
```

#### Resulting `haproxy.config`
```ini
backend st_http_req_rate
    stick-table type ipv6 size 1m expire 10s store http_req_rate(10s)
# [...]
frontend http-in
    http-request track-sc1 src table st_http_req_rate
```


### Request based Rate Limiting Fully Active
#### Configuration
```yml
config:
    # [...]
    requests_rate_limit:
        requests: 10
        window_size: 10s
        table_size: 1m
        block: true
```
#### Resulting `haproxy.config`
```ini
backend st_http_req_rate
    stick-table type ipv6 size 1m expire 10s store http_req_rate(10s)
# [...]
frontend http-in
    http-request track-sc1 src table st_http_req_rate
    http-request deny status 429 content-type "text/plain" string "429: Too Many Requests" if { sc_http_req_rate(1) gt <%= p("ha_proxy.requests_rate_limit.requests") %> }
```


### Both Types Active
#### Configuration
```yml
config:
    # [...]
    requests_rate_limit:
        requests: 10
        window_size: 10s
        table_size: 1m
        block: true
    connections_rate_limit:
        connections: 10
        window_size: 10s
        table_size: 1m
        block: true
```
#### Resulting `haproxy.config`
```ini
backend st_http_req_rate
    stick-table type ipv6 size 1m expire 10s store http_req_rate(10s)

backend st_tcp_conn_rate
    stick-table type ipv6 size 1m expire 10s store conn_rate(10s)
# [...]
frontend http-in
    # [...]
    http-request track-sc1 src table st_http_req_rate
    http-request deny status 429 content-type "text/plain" string "429: Too Many Requests" if { sc_http_req_rate(1) gt 10 }

    tcp-request content track-sc0 src table st_tcp_conn_rate
    tcp-request connection reject if { sc_conn_rate(0) gt 10}
```

## Querying current stick-table status
To give us more insights into what is going on inside HAProxy regarding its rate limits we can query the stats socket to get the raw table data:

```bash
$ echo "show table st_http_req_rate" | socat /var/vcap/sys/run/haproxy/stats.sock -
# table: st_http_req_rate, type: ip, size:10485760, used:1
0x56495f3dc3d0: key=172.18.0.1 use=0 exp=7618 http_req_rate(10000)=10
```

> Please note you will likely need 'sudo' permission to run socat.

## Runtime adjustment of connections_rate_limit via stats socket

The `connections_rate_limit.block` flag and `connections_rate_limit.connections` threshold are stored as HAProxy process-level variables and can be changed at runtime without a reload. This requires `ha_proxy.master_cli_enable: true` or `ha_proxy.stats_enable: true`.

The socket is located at `/var/vcap/sys/run/haproxy/stats.sock`. You will likely need `sudo` to access it.

### Inspect current variable values

```bash
sudo bash -c 'echo "show var proc.conn_rate_limit" | socat /var/vcap/sys/run/haproxy/stats.sock -'
# => proc.conn_rate_limit=10

sudo bash -c 'echo "show var proc.conn_rate_limit_enabled" | socat /var/vcap/sys/run/haproxy/stats.sock -'
# => proc.conn_rate_limit_enabled=1
```

### Enable or disable blocking at runtime

```bash
# Enable blocking (equivalent to setting block: true in the manifest)
sudo bash -c 'echo "set-var proc.conn_rate_limit_enabled bool(1)" | socat /var/vcap/sys/run/haproxy/stats.sock -'

# Disable blocking without reloading (equivalent to setting block: false in the manifest)
sudo bash -c 'echo "set-var proc.conn_rate_limit_enabled bool(0)" | socat /var/vcap/sys/run/haproxy/stats.sock -'
```

### Adjust the connections threshold at runtime

```bash
# Allow up to 20 connections per window (equivalent to setting connections: 20 in the manifest)
sudo bash -c 'echo "set-var proc.conn_rate_limit int(20)" | socat /var/vcap/sys/run/haproxy/stats.sock -'
```

### Combine enable + threshold change in one step

```bash
sudo bash -c 'printf "set-var proc.conn_rate_limit int(20)\nset-var proc.conn_rate_limit_enabled bool(1)\n" | socat /var/vcap/sys/run/haproxy/stats.sock -'
```

### Clear an IP from the stick table (unblock a specific client)

```bash
sudo bash -c 'echo "clear table st_tcp_conn_rate key 203.0.113.42" | socat /var/vcap/sys/run/haproxy/stats.sock -'
```

### Inspect current stick-table entries

```bash
sudo bash -c 'echo "show table st_tcp_conn_rate" | socat /var/vcap/sys/run/haproxy/stats.sock -'
# => # table: st_tcp_conn_rate, type: ipv6, size:100, used:2
# => 0x...: key=::ffff:203.0.113.42 use=0 exp=8123 conn_rate(10000)=5
```

> Note: Runtime changes are lost on HAProxy reload or restart. The values will be re-initialized from the BOSH manifest properties (`connections_rate_limit.connections` and `connections_rate_limit.block`) on next startup. The `tcp-request connection reject` rule is only present in the config when `connections_rate_limit.connections` is set; `connections_rate_limit.block` only controls the initial value of `proc.conn_rate_limit_enabled`.
