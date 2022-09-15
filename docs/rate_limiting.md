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
    stick-table type ip size 1m expire 10s store http_req_rate(10s)
# [...]
frontend http-in
    tcp-request content track-sc1 src table st_http_req_rate
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
    stick-table type ip size 1m expire 10s store http_req_rate(10s)
# [...]
frontend http-in
    tcp-request content track-sc1 src table st_http_req_rate
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
    stick-table type ip size 1m expire 10s store http_req_rate(10s)

backend st_tcp_conn_rate
    stick-table type ip size 1m expire 10s store conn_rate(10s)
# [...]
frontend http-in
    # [...]
    tcp-request content track-sc1 src table st_http_req_rate
    http-request deny status 429 content-type "text/plain" string "429: Too Many Requests" if { sc_http_req_rate(1) gt 10 }

    tcp-request content track-sc0 src table st_tcp_conn_rate
    tcp-request connection reject if { sc_conn_rate(0) gt 10}
```

## Querying current stick-table status
To give us more insights into what is going on inside HAProxy with regards to its rate limits we can query the stats socket to get the raw table data:

```bash
$ echo "show table st_http_req_rate" | socat /var/vcap/sys/run/haproxy/stats.sock -
# table: st_http_req_rate, type: ip, size:10485760, used:1
0x56495f3dc3d0: key=172.18.0.1 use=0 exp=7618 http_req_rate(10000)=10
```

> Please note you will likely need 'sudo' permission to run socat.
