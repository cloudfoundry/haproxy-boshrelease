# frozen_string_literal: true

require 'rspec'

describe 'config/haproxy.config backend http-routers-ws-http1' do
  let(:haproxy_conf) do
    parse_haproxy_config(template.render({ 'ha_proxy' => properties }))
  end

  let(:properties) do
    { 'backend_servers' => ['10.0.0.1', '10.0.0.2'] }
  end

  let(:frontend_http) { haproxy_conf['frontend http-in'] }
  let(:frontend_https) { haproxy_conf['frontend https-in'] }
  let(:frontend_wss_in) { haproxy_conf['frontend wss-in'] }

  context 'when ha_proxy.disable_backend_http2_websockets is configured' do
    let(:properties) do
      super().merge({ 'disable_backend_http2_websockets' => true })
    end

    it 'receives websocket traffic from http-in' do
      expect(frontend_http).to include('use_backend http-routers-http1 if is_websocket')
    end

    context 'when https is enabled' do
      let(:properties) do
        super().merge({ 'ssl_pem' => 'ssl pem contents' })
      end

      it 'receives websocket traffic from https-in' do
        expect(frontend_http).to include('use_backend http-routers-http1 if is_websocket')
      end

      context 'when the port 4443 websocket frontend is enabled' do
        let(:properties) do
          super().merge({ 'enable_4443' => true })
        end

        it 'receives websocket traffic from wss-in' do
          expect(frontend_wss_in).to include('use_backend http-routers-http1 if is_websocket')
        end
      end
    end
  end
end
