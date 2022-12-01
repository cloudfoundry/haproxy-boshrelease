# frozen_string_literal: true

require 'rspec'

describe 'config/haproxy.config healthcheck listeners' do
  let(:haproxy_conf) do
    parse_haproxy_config(template.render({ 'ha_proxy' => properties }))
  end

  context 'when ha_proxy.enable_health_check_http is true' do
    let(:healthcheck_listener) { haproxy_conf['listen health_check_http_url'] }

    let(:properties) do
      {
        'enable_health_check_http' => true
      }
    end

    it 'adds a health check listener for the http-routers-http1' do
      expect(healthcheck_listener).to include('bind :8080')
      expect(healthcheck_listener).to include('mode http')
      expect(healthcheck_listener).to include('option httpclose')
      expect(healthcheck_listener).to include('monitor-uri /health')
      expect(healthcheck_listener).to include('acl http-routers_down nbsrv(http-routers-http1) eq 0')
      expect(healthcheck_listener).to include('monitor fail if http-routers_down')
    end

    context 'when only http2 backend servers are available' do
      let(:properties) do
        {
          'enable_health_check_http' => true,
          'disable_backend_http2_websockets' => false,
          'enable_http2' => true,
          'backend_match_http_protocol' => false,
          'backend_ssl' => 'verify'
        }
      end

      it 'adds a health check listener for the http-routers-http2' do
        expect(healthcheck_listener).to include('bind :8080')
        expect(healthcheck_listener).to include('mode http')
        expect(healthcheck_listener).to include('option httpclose')
        expect(healthcheck_listener).to include('monitor-uri /health')
        expect(healthcheck_listener).to include('acl http-routers_down nbsrv(http-routers-http2) eq 0')
        expect(healthcheck_listener).to include('monitor fail if http-routers_down')
      end
    end

    context 'when health_check_port is not the default' do
      let(:properties) do
        {
          'enable_health_check_http' => true,
          'health_check_port' => 1234
        }
      end

      it 'sets the correct port' do
        expect(healthcheck_listener).to include('bind :1234')
      end
    end
  end
end
