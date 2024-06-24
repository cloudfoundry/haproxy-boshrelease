# frozen_string_literal: true

require 'rspec'

describe 'config/haproxy.config custom TCP frontends' do
  let(:haproxy_conf) do
    parse_haproxy_config(template.render({ 'ha_proxy' => properties }, consumes: [backend_tcp_link]))
  end

  let(:backend_tcp_link) do
    Bosh::Template::Test::Link.new(
      name: 'tcp_backend',
      instances: [Bosh::Template::Test::LinkInstance.new(address: 'postgres.backend.com', name: 'postgres')]
    )
  end

  let(:frontend_tcp_redis) { haproxy_conf['frontend tcp-frontend_redis'] }
  let(:frontend_tcp_mysql) { haproxy_conf['frontend tcp-frontend_mysql'] }
  let(:frontend_tcp_postgres_via_link) { haproxy_conf['frontend tcp-frontend_postgres'] }

  let(:default_properties) do
    {
      'tcp_link_port' => 5432,
      'tcp' => [{
        'name' => 'redis',
        'port' => 6379,
        'backend_servers' => ['10.0.0.1', '10.0.0.2']
      }, {
        'name' => 'mysql',
        'port' => 3306,
        'backend_servers' => ['11.0.0.1', '11.0.0.2']
      }]
    }
  end

  let(:properties) { default_properties }

  it 'has the correct mode' do
    expect(frontend_tcp_redis).to include('mode tcp')
    expect(frontend_tcp_mysql).to include('mode tcp')
    expect(frontend_tcp_postgres_via_link).to include('mode tcp')
  end

  it 'has the correct default backend' do
    expect(frontend_tcp_redis).to include('default_backend tcp-redis')
    expect(frontend_tcp_mysql).to include('default_backend tcp-mysql')
    expect(frontend_tcp_postgres_via_link).to include('default_backend tcp-postgres')
  end

  it 'binds to all interfaces by default' do
    expect(frontend_tcp_redis).to include('bind :6379')
    expect(frontend_tcp_mysql).to include('bind :3306')
    expect(frontend_tcp_postgres_via_link).to include('bind :5432')
  end

  context 'when ha_proxy.binding_ip is provided' do
    let(:properties) do
      default_properties.merge({ 'binding_ip' => '1.2.3.4' })
    end

    it 'binds to the provided ip' do
      expect(frontend_tcp_redis).to include('bind 1.2.3.4:6379')
      expect(frontend_tcp_mysql).to include('bind 1.2.3.4:3306')
      expect(frontend_tcp_postgres_via_link).to include('bind 1.2.3.4:5432')
    end

    context 'when ha_proxy.v4v6 is true and binding_ip is ::' do
      let(:properties) do
        default_properties.merge({ 'v4v6' => true, 'binding_ip' => '::' })
      end

      it 'enables ipv6' do
        expect(frontend_tcp_redis).to include('bind :::6379  v4v6')
        expect(frontend_tcp_mysql).to include('bind :::3306  v4v6')
        expect(frontend_tcp_postgres_via_link).to include('bind :::5432  v4v6')
      end
    end
  end

  context 'when ssl is enabled on custom backends (not links)' do
    let(:default_properties) do
      {
        'tcp_link_port' => 5432,
        'tcp' => [{
          'name' => 'redis',
          'port' => 6379,
          'backend_servers' => ['10.0.0.1', '10.0.0.2'],
          'ssl' => true
        }, {
          'name' => 'mysql',
          'port' => 3306,
          'backend_servers' => ['11.0.0.1', '11.0.0.2'],
          'ssl' => false
        }]
      }
    end

    it 'adds the default ssl options' do
      expect(frontend_tcp_redis).to include('bind :6379  ssl')
      expect(frontend_tcp_mysql).to include('bind :3306  ')
    end

    context 'when ha_proxy.accept_proxy is true' do
      let(:properties) do
        default_properties.merge({ 'accept_proxy' => true })
      end

      it 'sets accept-proxy' do
        expect(frontend_tcp_redis).to include('bind :6379 accept-proxy ssl')
        expect(frontend_tcp_mysql).to include('bind :3306 accept-proxy ')
      end

      context 'when ha_proxy.disable_tcp_accept_proxy is true' do
        let(:properties) do
          default_properties.merge({ 'accept_proxy' => true, 'disable_tcp_accept_proxy' => true })
        end

        it 'does not set accept-proxy' do
          expect(frontend_tcp_redis).to include('bind :6379  ssl')
          expect(frontend_tcp_mysql).to include('bind :3306  ')
        end
      end
    end
  end

  context 'when ha_proxy.tcp is not provided' do
    let(:haproxy_conf) do
      parse_haproxy_config(template.render({}))
    end

    it 'is not included' do
      expect(haproxy_conf).not_to have_key(/frontend tcp/)
    end
  end
end
