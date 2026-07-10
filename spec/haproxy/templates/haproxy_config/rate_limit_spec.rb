# frozen_string_literal: true

require 'rspec'

describe 'config/haproxy.config rate limiting' do
  let(:haproxy_conf) do
    parse_haproxy_config(template.render({ 'ha_proxy' => properties }))
  end

  let(:frontend_http) { haproxy_conf['frontend http-in'] }
  let(:frontend_https) { haproxy_conf['frontend https-in'] }

  let(:properties) { {} }

  let(:default_properties) do
    {
      'ssl_pem' => 'ssl pem contents' # required for https-in frontend
    }
  end

  context 'when ha_proxy.requests_rate_limit properties "window_size", "table_size" are provided' do
    let(:backend_req_rate) { haproxy_conf['backend st_http_req_rate'] }

    let(:request_limit_base_properties) do
      {
        'requests_rate_limit' => {
          'window_size' => '10s',
          'table_size' => '10m'
        }
      }
    end

    let(:temp_properties) do # temp_properties is required since we cannot deep_merge :properties in its own let/assignment block
      default_properties.deep_merge(request_limit_base_properties)
    end

    let(:properties) { temp_properties }

    it 'sets up stick-tables' do
      expect(backend_req_rate).to include('stick-table type ipv6 size 10m expire 10s store http_req_rate(10s)')
    end

    it 'tracks requests in stick tables' do
      expect(frontend_http).to include('http-request track-sc1 src table st_http_req_rate')
      expect(frontend_https).to include('http-request track-sc1 src table st_http_req_rate')
    end

    context 'when "requests" and "block" are also provided' do
      let(:properties) do
        temp_properties.deep_merge({ 'requests_rate_limit' => { 'requests' => '5', 'block' => 'true' } })
      end

      it 'adds http-request deny condition to http-in and https-in frontends' do
        expect(frontend_http).to include('http-request set-var-fmt(txn.block_reason) "blocked: requests rate limit reached" if { sc_http_req_rate(1) gt 5 }')
        expect(frontend_http).to include('http-request deny status 429 if { sc_http_req_rate(1) gt 5 }')
        expect(frontend_http).to include('http-request track-sc1 src table st_http_req_rate')
        expect(frontend_https).to include('http-request set-var-fmt(txn.block_reason) "blocked: requests rate limit reached" if { sc_http_req_rate(1) gt 5 }')
        expect(frontend_https).to include('http-request deny status 429 if { sc_http_req_rate(1) gt 5 }')
        expect(frontend_https).to include('http-request track-sc1 src table st_http_req_rate')
      end
    end
  end

  context 'when ha_proxy.connections_rate_limit "window_size" and "table_size" are NOT provided' do
    context 'when "connections" and "block" are set in manifest' do
      let(:properties) do
        default_properties.deep_merge({
          'connections_rate_limit' => { 'connections' => '5', 'block' => true }
        })
      end

      it 'does not set proc.connections_rate_limit_connections or proc.connections_rate_limit_block in global section' do
        expect(haproxy_conf['global']).not_to include('set-var proc.connections_rate_limit_connections')
        expect(haproxy_conf['global']).not_to include('set-var proc.connections_rate_limit_block')
      end
    end
  end

  context 'when ha_proxy.connections_rate_limit properties "window_size", "table_size" are provided' do
    let(:backend_conn_rate) { haproxy_conf['backend st_tcp_conn_rate'] }

    let(:connection_limit_base_properties) do
      {
        'connections_rate_limit' => {
          'window_size' => '10s',
          'table_size' => '10m'
        }
      }
    end

    let(:temp_properties) do # temp_properties is required since we cannot deep_merge :properties in its own let/assignment block
      default_properties.deep_merge(connection_limit_base_properties)
    end

    let(:properties) { temp_properties }

    it 'sets up stick-tables' do
      expect(backend_conn_rate).to include('stick-table type ipv6 size 10m expire 10s store conn_rate(10s)')
    end

    it 'tracks connections in stick tables' do
      expect(frontend_http).to include('tcp-request connection track-sc0 src table st_tcp_conn_rate')
      expect(frontend_https).to include('tcp-request connection track-sc0 src table st_tcp_conn_rate')
    end

    it 'always emits the reject rule (even without connections or block set in manifest)' do
      expect(frontend_http).to include('tcp-request connection reject if { var(proc.connections_rate_limit_block) -m bool } { var(proc.connections_rate_limit_connections) -m int gt 0 } { sc_conn_rate(0),sub(proc.connections_rate_limit_connections) gt 0 }')
      expect(frontend_https).to include('tcp-request connection reject if { var(proc.connections_rate_limit_block) -m bool } { var(proc.connections_rate_limit_connections) -m int gt 0 } { sc_conn_rate(0),sub(proc.connections_rate_limit_connections) gt 0 }')
    end

    it 'always sets proc.connections_rate_limit_block to false in global when block is not configured in manifest' do
      expect(haproxy_conf['global']).to include('set-var proc.connections_rate_limit_block bool(false)')
      expect(haproxy_conf['global']).not_to include('set-var proc.connections_rate_limit_connections')
    end

    it 'does not add the exclusion acl or negate the reject rule when exclude_cidrs is not set' do
      expect(frontend_http).not_to include('acl rate_limit_exclude src -f /var/vcap/jobs/haproxy/config/rate_limit_exclusion_cidrs.txt')
      expect(frontend_https).not_to include('acl rate_limit_exclude src -f /var/vcap/jobs/haproxy/config/rate_limit_exclusion_cidrs.txt')
      expect(frontend_http).to include('tcp-request connection reject if { var(proc.connections_rate_limit_block) -m bool } { var(proc.connections_rate_limit_connections) -m int gt 0 } { sc_conn_rate(0),sub(proc.connections_rate_limit_connections) gt 0 }')
      expect(frontend_https).to include('tcp-request connection reject if { var(proc.connections_rate_limit_block) -m bool } { var(proc.connections_rate_limit_connections) -m int gt 0 } { sc_conn_rate(0),sub(proc.connections_rate_limit_connections) gt 0 }')
    end

    context 'when connections_rate_limit.exclude_cidrs is provided' do
      let(:properties) do
        temp_properties.deep_merge({ 'connections_rate_limit' => { 'exclude_cidrs' => ['10.0.0.0/8', '192.168.0.0/16'] } })
      end

      it 'adds the exclusion acl to http-in and https-in frontends' do
        expect(frontend_http).to include('acl rate_limit_exclude src -f /var/vcap/jobs/haproxy/config/rate_limit_exclusion_cidrs.txt')
        expect(frontend_https).to include('acl rate_limit_exclude src -f /var/vcap/jobs/haproxy/config/rate_limit_exclusion_cidrs.txt')
      end

      it 'still tracks excluded sources in the stick-table' do
        expect(frontend_http).to include('tcp-request connection track-sc0 src table st_tcp_conn_rate')
        expect(frontend_https).to include('tcp-request connection track-sc0 src table st_tcp_conn_rate')
      end

      it 'negates the reject rule with the exclusion acl so excluded sources are never rejected' do
        expect(frontend_http).to include('tcp-request connection reject if { var(proc.connections_rate_limit_block) -m bool } { var(proc.connections_rate_limit_connections) -m int gt 0 } { sc_conn_rate(0),sub(proc.connections_rate_limit_connections) gt 0 } !rate_limit_exclude')
        expect(frontend_https).to include('tcp-request connection reject if { var(proc.connections_rate_limit_block) -m bool } { var(proc.connections_rate_limit_connections) -m int gt 0 } { sc_conn_rate(0),sub(proc.connections_rate_limit_connections) gt 0 } !rate_limit_exclude')
      end
    end

    context 'when proxy protocol used' do
      let(:properties) do
        temp_properties.deep_merge({ 'accept_proxy' => true })
      end

      it 'tracks connections in stick tables' do
        expect(frontend_http).to include('tcp-request session track-sc0 src table st_tcp_conn_rate')
        expect(frontend_https).to include('tcp-request session track-sc0 src table st_tcp_conn_rate')
      end
    end

    context 'when "connections" and "block" are also provided' do
      let(:properties) do
        temp_properties.deep_merge({ 'connections_rate_limit' => { 'connections' => '5', 'block' => 'true' } })
      end

      it 'adds tcp-request connection reject using process variables to http-in and https-in frontends' do
        expect(frontend_http).to include('tcp-request connection reject if { var(proc.connections_rate_limit_block) -m bool } { var(proc.connections_rate_limit_connections) -m int gt 0 } { sc_conn_rate(0),sub(proc.connections_rate_limit_connections) gt 0 }')
        expect(frontend_http).to include('tcp-request connection track-sc0 src table st_tcp_conn_rate')
        expect(frontend_https).to include('tcp-request connection reject if { var(proc.connections_rate_limit_block) -m bool } { var(proc.connections_rate_limit_connections) -m int gt 0 } { sc_conn_rate(0),sub(proc.connections_rate_limit_connections) gt 0 }')
        expect(frontend_https).to include('tcp-request connection track-sc0 src table st_tcp_conn_rate')
      end
    end

    context 'when "connections" is provided but "block" is false' do
      let(:properties) do
        temp_properties.deep_merge({ 'connections_rate_limit' => { 'connections' => '10', 'block' => false } })
      end

      it 'sets proc.connections_rate_limit_connections and proc.connections_rate_limit_block process variables in global section' do
        expect(haproxy_conf['global']).to include('set-var proc.connections_rate_limit_connections int(10)')
        expect(haproxy_conf['global']).to include('set-var proc.connections_rate_limit_block bool(false)')
      end

      it 'still emits reject rule (rejection controlled at runtime via proc.connections_rate_limit_block variable)' do
        expect(frontend_http).to include('tcp-request connection reject if { var(proc.connections_rate_limit_block) -m bool } { var(proc.connections_rate_limit_connections) -m int gt 0 } { sc_conn_rate(0),sub(proc.connections_rate_limit_connections) gt 0 }')
        expect(frontend_https).to include('tcp-request connection reject if { var(proc.connections_rate_limit_block) -m bool } { var(proc.connections_rate_limit_connections) -m int gt 0 } { sc_conn_rate(0),sub(proc.connections_rate_limit_connections) gt 0 }')
      end
    end

    context 'when only "block" is true but "connections" is not set in manifest' do
      let(:properties) do
        temp_properties.deep_merge({ 'connections_rate_limit' => { 'block' => true } })
      end

      it 'raises a validation error to prevent total lockout (every client with >= 1 connection would be blocked)' do
        expect { haproxy_conf }.to raise_error(/connections_rate_limit.connections must be set in the manifest as the initial threshold when block is true/)
      end
    end

    context 'when proxy protocol used and "connections" and "block" are also provided' do
      let(:properties) do
        temp_properties.deep_merge({ 'accept_proxy' => true, 'connections_rate_limit' => { 'connections' => '5', 'block' => true } })
      end

      it 'adds tcp-request session reject using process variables to http-in and https-in frontends' do
        expect(frontend_http).to include('tcp-request session reject if { var(proc.connections_rate_limit_block) -m bool } { var(proc.connections_rate_limit_connections) -m int gt 0 } { sc_conn_rate(0),sub(proc.connections_rate_limit_connections) gt 0 }')
        expect(frontend_http).to include('tcp-request session track-sc0 src table st_tcp_conn_rate')
        expect(frontend_https).to include('tcp-request session reject if { var(proc.connections_rate_limit_block) -m bool } { var(proc.connections_rate_limit_connections) -m int gt 0 } { sc_conn_rate(0),sub(proc.connections_rate_limit_connections) gt 0 }')
        expect(frontend_https).to include('tcp-request session track-sc0 src table st_tcp_conn_rate')
      end
    end
  end
end
