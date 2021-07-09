# frozen_string_literal: true

require 'rspec'

describe 'config/haproxy.config custom TCP backends' do
  let(:haproxy_conf) do
    parse_haproxy_config(template.render({ 'ha_proxy' => properties }, consumes: [backend_tcp_link]))
  end

  let(:backend_tcp_link) do
    Bosh::Template::Test::Link.new(
      name: 'tcp_backend',
      instances: [
        # will appear in same AZ
        Bosh::Template::Test::LinkInstance.new(address: 'postgres.az1.com', name: 'postgres', az: 'az1'),

        # will appear in another AZ
        Bosh::Template::Test::LinkInstance.new(address: 'postgres.az2.com', name: 'postgres', az: 'az2')
      ]
    )
  end

  let(:backend_tcp_redis) { haproxy_conf['backend tcp-redis'] }
  let(:backend_tcp_mysql) { haproxy_conf['backend tcp-mysql'] }
  let(:backend_tcp_postgres_via_link) { haproxy_conf['backend tcp-postgres'] }

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
    expect(backend_tcp_redis).to include('mode tcp')
    expect(backend_tcp_mysql).to include('mode tcp')
    expect(backend_tcp_postgres_via_link).to include('mode tcp')
  end

  context 'when backend_port is provided' do
    let(:properties) do
      {
        'tcp_link_port' => 5432,
        'tcp' => [{
          'name' => 'redis',
          'port' => 6379,
          'backend_port' => 6380,
          'backend_servers' => ['10.0.0.1', '10.0.0.2'],
          'balance' => 'leastconn'
        }, {
          'name' => 'mysql',
          'port' => 3306,
          'backend_port' => 3307,
          'backend_servers' => ['11.0.0.1', '11.0.0.2'],
          'balance' => 'leastconn'
        }]
      }
    end

    it 'configures the backend servers with the correct backend port' do
      expect(backend_tcp_redis).to include('server node0 10.0.0.1:6380 check port 6380 inter 1000')
      expect(backend_tcp_redis).to include('server node1 10.0.0.2:6380 check port 6380 inter 1000')

      expect(backend_tcp_mysql).to include('server node0 11.0.0.1:3307 check port 3307 inter 1000')
      expect(backend_tcp_mysql).to include('server node1 11.0.0.2:3307 check port 3307 inter 1000')
    end
  end

  context 'when balance is provided (not available via link)' do
    let(:properties) do
      {
        'tcp_link_port' => 5432,
        'tcp' => [{
          'name' => 'redis',
          'port' => 6379,
          'backend_servers' => ['10.0.0.1', '10.0.0.2'],
          'balance' => 'leastconn'
        }, {
          'name' => 'mysql',
          'port' => 3306,
          'backend_servers' => ['11.0.0.1', '11.0.0.2'],
          'balance' => 'leastconn'
        }]
      }
    end

    it 'uses the specified balancing algorithm' do
      expect(backend_tcp_redis).to include('balance leastconn')
      expect(backend_tcp_mysql).to include('balance leastconn')
    end
  end

  it 'configures the backend servers' do
    expect(backend_tcp_redis).to include('server node0 10.0.0.1:6379 check port 6379 inter 1000')
    expect(backend_tcp_redis).to include('server node1 10.0.0.2:6379 check port 6379 inter 1000')

    expect(backend_tcp_mysql).to include('server node0 11.0.0.1:3306 check port 3306 inter 1000')
    expect(backend_tcp_mysql).to include('server node1 11.0.0.2:3306 check port 3306 inter 1000')

    expect(backend_tcp_postgres_via_link).to include('server node0 postgres.az1.com:5432 check port 5432 inter 1000')
    expect(backend_tcp_postgres_via_link).to include('server node1 postgres.az2.com:5432 check port 5432 inter 1000  backup')
  end

  context 'when a server is included in backend_servers_local' do
    let(:properties) do
      {
        'tcp_link_port' => 5432,
        'tcp' => [{
          'name' => 'redis',
          'port' => 6379,
          'backend_servers' => ['10.0.0.1', '10.0.0.2'],
          'backend_servers_local' => ['10.0.0.1']
        }]
      }
    end

    it 'configures non-local servers as "backups"' do
      expect(backend_tcp_redis).to include('server node0 10.0.0.1:6379 check port 6379 inter 1000')
      expect(backend_tcp_redis).to include('server node1 10.0.0.2:6379 check port 6379 inter 1000  backup')
    end
  end

  context 'when ha_proxy.tcp_link_check_port is provided' do
    let(:properties) { default_properties.merge({ 'tcp_link_check_port' => 9000 }) }

    it 'overrides the health check port' do
      expect(backend_tcp_redis).to include('server node0 10.0.0.1:6379 check port 9000 inter 1000')
      expect(backend_tcp_redis).to include('server node1 10.0.0.2:6379 check port 9000 inter 1000')

      expect(backend_tcp_mysql).to include('server node0 11.0.0.1:3306 check port 9000 inter 1000')
      expect(backend_tcp_mysql).to include('server node1 11.0.0.2:3306 check port 9000 inter 1000')

      expect(backend_tcp_postgres_via_link).to include('server node0 postgres.az1.com:5432 check port 9000 inter 1000')
      expect(backend_tcp_postgres_via_link).to include('server node1 postgres.az2.com:5432 check port 9000 inter 1000  backup')
    end
  end

  context 'when ha_proxy.resolvers are provided' do
    let(:properties) do
      default_properties.merge({ 'resolvers' => [{ 'public' => '1.1.1.1' }] })
    end

    it 'sets the resolver on the server configuration' do
      expect(backend_tcp_redis).to include('server node0 10.0.0.1:6379 resolvers default check port 6379 inter 1000')
      expect(backend_tcp_redis).to include('server node1 10.0.0.2:6379 resolvers default check port 6379 inter 1000')

      expect(backend_tcp_mysql).to include('server node0 11.0.0.1:3306 resolvers default check port 3306 inter 1000')
      expect(backend_tcp_mysql).to include('server node1 11.0.0.2:3306 resolvers default check port 3306 inter 1000')

      expect(backend_tcp_postgres_via_link).to include('server node0 postgres.az1.com:5432 resolvers default check port 5432 inter 1000')
      expect(backend_tcp_postgres_via_link).to include('server node1 postgres.az2.com:5432 resolvers default check port 5432 inter 1000  backup')
    end
  end

  context 'when backend_ssl is verify' do
    let(:properties) do
      {
        'tcp_link_port' => 5432,
        'tcp' => [{
          'name' => 'redis',
          'port' => 6379,
          'backend_servers' => ['10.0.0.1', '10.0.0.2'],
          'backend_ssl' => 'verify'
        }]
      }
    end

    it 'configures the server to use ssl: verify' do
      expect(backend_tcp_redis).to include('server node0 10.0.0.1:6379 check port 6379 inter 1000 ssl verify required ca-file /var/vcap/jobs/haproxy/config/backend-ca-certs.pem')
      expect(backend_tcp_redis).to include('server node1 10.0.0.2:6379 check port 6379 inter 1000 ssl verify required ca-file /var/vcap/jobs/haproxy/config/backend-ca-certs.pem')
    end

    context 'when ha_proxy.backend_ssl_verifyhost is provided' do
      let(:properties) do
        {
          'tcp_link_port' => 5432,
          'tcp' => [{
            'name' => 'redis',
            'port' => 6379,
            'backend_servers' => ['10.0.0.1', '10.0.0.2'],
            'backend_ssl' => 'verify',
            'backend_verifyhost' => 'backend.com'
          }]
        }
      end

      it 'configures the server to use ssl: verify with verifyhost for the provided host name' do
        expect(backend_tcp_redis).to include('server node0 10.0.0.1:6379 check port 6379 inter 1000 ssl verify required ca-file /var/vcap/jobs/haproxy/config/backend-ca-certs.pem verifyhost backend.com')
        expect(backend_tcp_redis).to include('server node1 10.0.0.2:6379 check port 6379 inter 1000 ssl verify required ca-file /var/vcap/jobs/haproxy/config/backend-ca-certs.pem verifyhost backend.com')
      end

      context 'when ha_proxy.backend_ssl is not verify' do
        let(:properties) do
          {
            'tcp_link_port' => 5432,
            'tcp' => [{
              'name' => 'redis',
              'port' => 6379,
              'backend_servers' => ['10.0.0.1', '10.0.0.2'],
              'backend_ssl' => 'noverify',
              'backend_verifyhost' => 'backend.com'
            }]
          }
        end

        it 'aborts with a meaningful error message' do
          expect do
            backend_tcp_redis
          end.to raise_error /Conflicting configuration: backend_ssl must be 'verify' to use backend_verifyhost in tcp backend configuration/
        end
      end
    end
  end

  context 'when ha_proxy.backend_ssl is noverify' do
    let(:properties) do
      {
        'tcp_link_port' => 5432,
        'tcp' => [{
          'name' => 'redis',
          'port' => 6379,
          'backend_servers' => ['10.0.0.1', '10.0.0.2'],
          'backend_ssl' => 'noverify'
        }]
      }
    end

    it 'configures the server to use ssl: verify none' do
      expect(backend_tcp_redis).to include('server node0 10.0.0.1:6379 check port 6379 inter 1000 ssl verify none')
      expect(backend_tcp_redis).to include('server node1 10.0.0.2:6379 check port 6379 inter 1000 ssl verify none')
    end
  end

  context 'when ha_proxy.tcp is not provided' do
    let(:haproxy_conf) do
      parse_haproxy_config(template.render({}))
    end

    it 'is not included' do
      expect(haproxy_conf).not_to have_key(/backend tcp/)
    end
  end
end
