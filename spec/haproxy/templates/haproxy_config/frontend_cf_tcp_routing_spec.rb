# frozen_string_literal: true

require 'rspec'
require 'tempfile'

describe 'config/haproxy.config frontend cf_tcp_routing' do
  let(:tcp_router_link) do
    Bosh::Template::Test::Link.new(
      name: 'tcp_router',
      instances: [Bosh::Template::Test::LinkInstance.new(address: 'tcp.cf.com')]
    )
  end

  let(:haproxy_conf) do
    parse_haproxy_config(template.render({ 'ha_proxy' => properties }, consumes: [tcp_router_link]))
  end

  let(:frontend_cf_tcp_routing) { haproxy_conf['frontend cf_tcp_routing'] }

  let(:properties) { {} }

  it 'has the correct mode' do
    expect(frontend_cf_tcp_routing).to include('mode tcp')
  end

  it 'uses default port range of 1024-1123' do
    expect(frontend_cf_tcp_routing).to include('bind :1024-1123')
  end

  context 'when ha_proxy.binding_ip is provided' do
    let(:properties) do
      {
        'binding_ip' => '1.2.3.4'
      }
    end

    it 'overrides the binding ip' do
      expect(frontend_cf_tcp_routing).to include('bind 1.2.3.4:1024-1123')
    end
  end

  context 'when ha_proxy.tcp_routing.port_range is provided' do
    let(:properties) do
      {
        'tcp_routing' => {
          'port_range' => '100-200'
        }
      }
    end

    it 'overrides the port range' do
      expect(frontend_cf_tcp_routing).to include('bind :100-200')
    end
  end

  it 'has the correct backend' do
    expect(frontend_cf_tcp_routing).to include('default_backend cf_tcp_routers')
  end

  context 'when no tcp_router link is provided' do
    let(:haproxy_conf) do
      parse_haproxy_config(template.render(properties))
    end

    it 'is not included' do
      expect(haproxy_conf).not_to have_key('frontend cf_tcp_routing')
    end
  end
end
