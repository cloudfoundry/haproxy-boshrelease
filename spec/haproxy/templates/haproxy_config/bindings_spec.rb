# frozen_string_literal: true

require 'rspec'

describe 'config/haproxy.config explicit bindings' do
  let(:properties) { { 'bindings' => bindings } }
  let(:rendered_config) { template.render({ 'ha_proxy' => properties }, consumes:) }
  let(:haproxy_conf) { parse_haproxy_config(rendered_config) }
  let(:bindings) { [{ 'address' => '0.0.0.0' }] }
  let(:consumes) { [] }

  def render_with(bindings, additional_properties = {})
    template.render({ 'ha_proxy' => additional_properties.merge('bindings' => bindings) })
  end

  it 'renders an IPv4-only binding without a family mode' do
    expect(haproxy_conf['frontend http-in']).to include('bind 0.0.0.0:80')
  end

  it 'renders an IPv6 wildcard v6only binding' do
    config = parse_haproxy_config(render_with([{ 'address' => '::', 'ipv6_mode' => 'v6only' }]))

    expect(config['frontend http-in']).to include('bind [::]:80 v6only')
  end

  it 'renders an IPv6 wildcard v4v6 binding' do
    config = parse_haproxy_config(render_with([{ 'address' => '::', 'ipv6_mode' => 'v4v6' }]))

    expect(config['frontend http-in']).to include('bind [::]:80 v4v6')
  end

  it 'renders a specific IPv6 binding without a family mode' do
    config = parse_haproxy_config(render_with([{ 'address' => 'fd00::12' }]))

    expect(config['frontend http-in']).to include('bind [fd00::12]:80')
  end

  it 'preserves input order for separate IPv4 and IPv6 sockets' do
    config = render_with([{ 'address' => '::', 'ipv6_mode' => 'v6only' },
                          { 'address' => '0.0.0.0' }])

    expect(config.index('bind [::]:80 v6only')).to be < config.index('bind 0.0.0.0:80')
  end

  context 'with generated listeners and listener-specific options' do
    let(:bindings) do
      [{ 'address' => '0.0.0.0' }, { 'address' => '::', 'ipv6_mode' => 'v6only' }]
    end
    let(:properties) do
      {
        'bindings' => bindings,
        'ssl_pem' => 'ssl pem contents',
        'enable_4443' => true,
        'enable_http2' => true,
        'accept_proxy' => true,
        'enable_health_check_http' => true,
        'enable_additional_health_check_proxy' => true,
        'stats_enable' => true,
        'stats_bind' => '*:9000',
        'tcp' => [{
          'name' => 'redis',
          'port' => 6379,
          'backend_servers' => ['10.0.0.1'],
          'ssl' => true,
          'health_check_http' => 9095
        }]
      }
    end
    let(:consumes) do
      [Bosh::Template::Test::Link.new(
        name: 'tcp_router',
        instances: [Bosh::Template::Test::LinkInstance.new(address: 'tcp.cf.com')]
      )]
    end

    it 'applies every binding and listener-specific options without changing stats' do
      expect(haproxy_conf['listen health_check_http_url']).to include('bind 0.0.0.0:8080', 'bind [::]:8080 v6only')
      expect(haproxy_conf['listen health_check_http_url_proxy_protocol']).to include('bind 0.0.0.0:8081 accept-proxy', 'bind [::]:8081 v6only accept-proxy')
      expect(haproxy_conf['frontend http-in']).to include('bind 0.0.0.0:80 accept-proxy', 'bind [::]:80 v6only accept-proxy')
      https_binds = haproxy_conf['frontend https-in'].join("\n")
      expect(https_binds).to include('bind 0.0.0.0:443 accept-proxy ssl', 'bind [::]:443 v6only accept-proxy ssl', 'alpn h2,http/1.1')
      wss_binds = haproxy_conf['frontend wss-in'].join("\n")
      expect(wss_binds).to include('bind 0.0.0.0:4443 accept-proxy ssl', 'bind [::]:4443 v6only accept-proxy ssl')
      expect(haproxy_conf['frontend cf_tcp_routing']).to include('bind 0.0.0.0:1024-1123', 'bind [::]:1024-1123 v6only')
      tcp_binds = haproxy_conf['frontend tcp-frontend_redis'].join("\n")
      expect(tcp_binds).to include('bind 0.0.0.0:6379 accept-proxy ssl', 'bind [::]:6379 v6only accept-proxy ssl')
      expect(haproxy_conf['listen health_check_http_tcp-redis']).to include('bind 0.0.0.0:9095', 'bind [::]:9095 v6only')
      expect(haproxy_conf['listen health_check_http_tcp-redis_proxy_protocol']).to include('bind 0.0.0.0:9096 accept-proxy', 'bind [::]:9096 v6only accept-proxy')
      expect(haproxy_conf['listen stats']).to include('bind *:9000')
    end
  end

  {
    'an empty array' => [],
    'a non-array' => { 'address' => '0.0.0.0' },
    'a non-map entry' => ['0.0.0.0'],
    'an entry without address' => [{ 'ipv6_mode' => 'v6only' }],
    'an entry with an unknown key' => [{ 'address' => '0.0.0.0', 'unexpected' => true }],
    'an empty address' => [{ 'address' => '' }],
    'a hostname' => [{ 'address' => 'localhost' }],
    'a CIDR' => [{ 'address' => '10.0.0.0/8' }],
    'an address with a port' => [{ 'address' => '1.2.3.4:80' }],
    'a bracketed address' => [{ 'address' => '[::]' }],
    'an IPv6 zone ID' => [{ 'address' => 'fe80::1%eth0' }],
    'an IPv4-mapped IPv6 address' => [{ 'address' => '::ffff:192.0.2.1' }]
  }.each do |description, invalid_bindings|
    it "rejects #{description}" do
      expect { render_with(invalid_bindings) }.to raise_error(/ha_proxy\.bindings/)
    end
  end

  it 'rejects ipv6_mode on IPv4' do
    expect { render_with([{ 'address' => '0.0.0.0', 'ipv6_mode' => 'v6only' }]) }.to raise_error(/IPv4 addresses cannot specify ipv6_mode/)
  end

  it 'requires an allowed ipv6_mode on the IPv6 wildcard' do
    expect { render_with([{ 'address' => '::' }]) }.to raise_error(/requires ipv6_mode/)
    expect { render_with([{ 'address' => '::', 'ipv6_mode' => 'invalid' }]) }.to raise_error(/requires ipv6_mode/)
  end

  it 'rejects ipv6_mode on specific IPv6' do
    expect { render_with([{ 'address' => 'fd00::12', 'ipv6_mode' => 'v6only' }]) }.to raise_error(/specific IPv6 addresses cannot specify ipv6_mode/)
  end

  it 'rejects normalized duplicates' do
    expect do
      render_with([{ 'address' => 'fd00::12' }, { 'address' => 'fd00:0:0:0:0:0:0:12' }])
    end.to raise_error(/duplicate address/)
  end

  it 'rejects IPv4 and IPv6 wildcard overlap with specific addresses' do
    expect do
      render_with([{ 'address' => '0.0.0.0' }, { 'address' => '192.0.2.10' }])
    end.to raise_error(/IPv4 wildcard/)
    expect do
      render_with([{ 'address' => '::', 'ipv6_mode' => 'v6only' }, { 'address' => 'fd00::12' }])
    end.to raise_error(/IPv6 wildcard/)
  end

  it 'rejects a v4v6 IPv6 wildcard alongside IPv4' do
    expect do
      render_with([{ 'address' => '::', 'ipv6_mode' => 'v4v6' }, { 'address' => '0.0.0.0' }])
    end.to raise_error(/v4v6 cannot be combined with an IPv4 binding/)
  end

  it 'rejects non-empty legacy binding settings' do
    expect do
      render_with([{ 'address' => '0.0.0.0' }], 'binding_ip' => '192.0.2.10')
    end.to raise_error(/non-empty ha_proxy\.binding_ip/)
    expect do
      render_with([{ 'address' => '::', 'ipv6_mode' => 'v4v6' }], 'v4v6' => true)
    end.to raise_error(/ha_proxy\.bindings cannot be combined with ha_proxy\.v4v6/)
  end

  it 'does not evaluate bindings when raw_config is used' do
    expect(template.render({ 'ha_proxy' => {
      'raw_config' => 'global',
      'bindings' => []
    } })).to eq("global\n")
  end
end
