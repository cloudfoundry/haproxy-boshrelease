# frozen_string_literal: true

require 'rspec'

describe 'config/haproxy.config backend http-routers-ws-http1' do
  let(:haproxy_conf) do
    parse_haproxy_config(template.render({ 'ha_proxy' => properties }))
  end

  let(:properties) do
    { 'backend_servers' => ['10.0.0.1', '10.0.0.2'] }
  end
  let(:backend_http_routers) { haproxy_conf['backend http-routers'] }
  let(:backend_http_routers_ws) { haproxy_conf['backend http-routers-ws-http1'] }
  let(:frontend_http) { haproxy_conf['frontend http-in'] }
  let(:frontend_https) { haproxy_conf['frontend https-in'] }
  let(:frontend_wss_in) { haproxy_conf['frontend wss-in'] }

  it 'does not exist by default' do
    expect(backend_http_routers_ws).to be_nil
  end

  context 'when ha_proxy.disable_backend_http2_websockets is configured' do
    let(:properties) do
      super().merge({ 'disable_backend_http2_websockets' => true })
    end

    it 'exists' do
      expect(backend_http_routers_ws).not_to be_nil
    end

    it 'is the same as the normal http-routers backend except for different server settings' do
      http_non_server_entries = backend_http_routers.reject { |l| l =~ /^server / }
      http_ws_non_server_entries = backend_http_routers_ws.reject { |l| l =~ /^server / }
      expect(http_non_server_entries).to eq(http_ws_non_server_entries)
    end

    it 'uses an upstream ALPN of HTTP/1.1 only' do
      server_entries = backend_http_routers_ws.select { |l| l =~ /^server / }
      expect(server_entries).to contain_exactly(
        'server node0 10.0.0.1:80 check inter 1000  alpn http/1.1',
        'server node1 10.0.0.2:80 check inter 1000  alpn http/1.1'
      )
    end

    it 'receives websocket traffic from http-in' do
      expect(frontend_http).to include('use_backend http-routers-ws-http1 if is_websocket')
    end

    context 'when https is enabled' do
      let(:properties) do
        super().merge({ 'ssl_pem' => 'ssl pem contents' })
      end

      it 'receives websocket traffic from https-in' do
        expect(frontend_http).to include('use_backend http-routers-ws-http1 if is_websocket')
      end

      context 'when the port 4443 websocket frontend is enabled' do
        let(:properties) do
          super().merge({ 'enable_4443' => true })
        end

        it 'receives websocket traffic from wss-in' do
          expect(frontend_wss_in).to include('use_backend http-routers-ws-http1 if is_websocket')
        end
      end
    end
  end
end
