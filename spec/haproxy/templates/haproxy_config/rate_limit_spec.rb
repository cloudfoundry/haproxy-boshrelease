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
      expect(backend_req_rate).to include('stick-table type ip size 10m expire 10s store http_req_rate(10s)')
    end

    it 'tracks requests in stick tables' do
      expect(frontend_http).to include('tcp-request content track-sc1 src table st_http_req_rate')
      expect(frontend_https).to include('tcp-request content track-sc1 src table st_http_req_rate')
    end

    context 'when "requests" and "block" are also provided' do
      let(:properties) do
        temp_properties.deep_merge({ 'requests_rate_limit' => { 'requests' => '5', 'block' => 'true' } })
      end

      it 'adds http-request deny condition to http-in and https-in frontends' do
        expect(frontend_http).to include('http-request deny status 429 if { sc_http_req_rate(1) gt 5 }')
        expect(frontend_http).to include('tcp-request content track-sc1 src table st_http_req_rate')
        expect(frontend_https).to include('http-request deny status 429 if { sc_http_req_rate(1) gt 5 }')
        expect(frontend_https).to include('tcp-request content track-sc1 src table st_http_req_rate')
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
      expect(backend_conn_rate).to include('stick-table type ip size 10m expire 10s store conn_rate(10s)')
    end

    it 'tracks connections in stick tables' do
      expect(frontend_http).to include('tcp-request connection track-sc0 src table st_tcp_conn_rate')
      expect(frontend_https).to include('tcp-request connection track-sc0 src table st_tcp_conn_rate')
    end

    context 'when "connections" and "block" are also provided' do
      let(:properties) do
        temp_properties.deep_merge({ 'connections_rate_limit' => { 'connections' => '5', 'block' => 'true' } })
      end

      it 'adds http-request deny condition to http-in and https-in frontends' do
        expect(frontend_http).to include('tcp-request connection reject if { sc_conn_rate(0) gt 5 }')
        expect(frontend_http).to include('tcp-request connection track-sc0 src table st_tcp_conn_rate')
        expect(frontend_https).to include('tcp-request connection reject if { sc_conn_rate(0) gt 5 }')
        expect(frontend_https).to include('tcp-request connection track-sc0 src table st_tcp_conn_rate')
      end
    end
  end
end
