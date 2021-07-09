# frozen_string_literal: true

require 'rspec'

describe 'config/haproxy.config backend http-routers' do
  let(:haproxy_conf) do
    parse_haproxy_config(template.render({ 'ha_proxy' => properties }))
  end

  let(:properties) { {} }
  let(:backend_http_routers) { haproxy_conf['backend http-routers'] }

  it 'has the correct mode' do
    expect(backend_http_routers).to include('mode http')
  end

  it 'uses round-robin load balancing' do
    expect(backend_http_routers).to include('balance roundrobin')
  end

  context 'when ha_proxy.compress_types are provided' do
    let(:properties) { { 'compress_types' => 'text/html text/plain text/css' } }

    it 'configures the compression type and algorithm' do
      expect(backend_http_routers).to include('compression algo gzip')
      expect(backend_http_routers).to include('compression type text/html text/plain text/css')
    end
  end

  context 'when ha_proxy.backend_config is provided' do
    let(:properties) do
      {
        'backend_config' => 'custom backend config'
      }
    end

    it 'includes the config' do
      expect(backend_http_routers).to include('custom backend config')
    end
  end

  context 'when ha_proxy.custom_http_error_files is provided' do
    let(:properties) do
      {
        'custom_http_error_files' => {
          '503' => '<html><body><h1>503 Service Unavailable</h1></body></html>'
        }
      }
    end

    it 'includes the errorfiles' do
      expect(backend_http_routers).to include('errorfile 503 /var/vcap/jobs/haproxy/errorfiles/custom503.http')
    end
  end

  context 'when ha_proxy.backend_use_http_health is true' do
    let(:properties) do
      {
        'backend_use_http_health' => true,
        'backend_servers' => ['10.0.0.1', '10.0.0.2']
      }
    end

    it 'configures the healthcheck' do
      expect(backend_http_routers).to include('option httpchk GET /health')
    end

    it 'adds the healthcheck to the server config' do
      expect(backend_http_routers).to include('server node0 10.0.0.1:80 check inter 1000 port 8080')
      expect(backend_http_routers).to include('server node1 10.0.0.2:80 check inter 1000 port 8080')
    end

    context 'when backend_http_health_uri is provided' do
      let(:properties) do
        {
          'backend_use_http_health' => true,
          'backend_http_health_uri' => '1.2.3.5/health',
          'backend_servers' => ['10.0.0.1', '10.0.0.2']
        }
      end

      it 'configures the healthcheck' do
        expect(backend_http_routers).to include('option httpchk GET 1.2.3.5/health')
      end

      it 'adds the healthcheck to the server config' do
        expect(backend_http_routers).to include('server node0 10.0.0.1:80 check inter 1000 port 8080')
        expect(backend_http_routers).to include('server node1 10.0.0.2:80 check inter 1000 port 8080')
      end
    end

    context 'when backend_http_health_port is provided' do
      let(:properties) do
        {
          'backend_use_http_health' => true,
          'backend_http_health_port' => 8081,
          'backend_servers' => ['10.0.0.1', '10.0.0.2']
        }
      end

      it 'configures the healthcheck' do
        expect(backend_http_routers).to include('option httpchk GET /health')
      end

      it 'adds the healthcheck to the server config' do
        expect(backend_http_routers).to include('server node0 10.0.0.1:80 check inter 1000 port 8081')
        expect(backend_http_routers).to include('server node1 10.0.0.2:80 check inter 1000 port 8081')
      end
    end
  end

  context 'when backend servers are provided via ha_proxy.backend_servers' do
    let(:properties) do
      {
        'backend_servers' => ['10.0.0.1', '10.0.0.2']
      }
    end

    it 'configures the servers' do
      expect(backend_http_routers).to include('server node0 10.0.0.1:80 check inter 1000')
      expect(backend_http_routers).to include('server node1 10.0.0.2:80 check inter 1000')
    end
  end

  context 'when ha_proxy.backend_crt is provided' do
    let(:properties) do
      {
        'backend_servers' => ['10.0.0.1', '10.0.0.2'],
        'backend_crt' => 'backend_crt contents'
      }
    end

    it 'configures the server to use the provided certificate' do
      expect(backend_http_routers).to include('server node0 10.0.0.1:80 crt /var/vcap/jobs/haproxy/config/backend-crt.pem check inter 1000')
      expect(backend_http_routers).to include('server node1 10.0.0.2:80 crt /var/vcap/jobs/haproxy/config/backend-crt.pem check inter 1000')
    end
  end

  context 'when ha_proxy.backend_ssl is verify' do
    let(:properties) do
      {
        'backend_servers' => ['10.0.0.1', '10.0.0.2'],
        'backend_ssl' => 'verify'
      }
    end

    it 'configures the server to use ssl: verify' do
      expect(backend_http_routers).to include('server node0 10.0.0.1:80 check inter 1000  ssl verify required ca-file /var/vcap/jobs/haproxy/config/backend-ca-certs.pem')
      expect(backend_http_routers).to include('server node1 10.0.0.2:80 check inter 1000  ssl verify required ca-file /var/vcap/jobs/haproxy/config/backend-ca-certs.pem')
    end

    context 'when ha_proxy.backend_ssl_verifyhost is provided' do
      let(:properties) do
        {
          'backend_servers' => ['10.0.0.1', '10.0.0.2'],
          'backend_ssl' => 'verify',
          'backend_ssl_verifyhost' => 'backend.com'
        }
      end

      it 'configures the server to use ssl: verify with verifyhost for the provided host name' do
        expect(backend_http_routers).to include('server node0 10.0.0.1:80 check inter 1000  ssl verify required ca-file /var/vcap/jobs/haproxy/config/backend-ca-certs.pem verifyhost backend.com')
        expect(backend_http_routers).to include('server node1 10.0.0.2:80 check inter 1000  ssl verify required ca-file /var/vcap/jobs/haproxy/config/backend-ca-certs.pem verifyhost backend.com')
      end

      context 'when ha_proxy.backend_ssl is not verify' do
        let(:properties) do
          {
            'backend_servers' => ['10.0.0.1', '10.0.0.2'],
            'backend_ssl' => 'noverify',
            'backend_ssl_verifyhost' => 'backend.com'
          }
        end

        it 'aborts with a meaningful error message' do
          expect do
            backend_http_routers
          end.to raise_error /Conflicting configuration: backend_ssl must be 'verify' to use backend_ssl_verifyhost/
        end
      end
    end

    context 'when ha_proxy.enable_http2 is true' do
      let(:properties) do
        {
          'backend_servers' => ['10.0.0.1', '10.0.0.2'],
          'backend_ssl' => 'verify',
          'enable_http2' => true
        }
      end

      it 'enables h2 ALPN negotiation with backends' do
        expect(backend_http_routers).to include('server node0 10.0.0.1:80 check inter 1000  ssl verify required ca-file /var/vcap/jobs/haproxy/config/backend-ca-certs.pem alpn h2,http/1.1')
        expect(backend_http_routers).to include('server node1 10.0.0.2:80 check inter 1000  ssl verify required ca-file /var/vcap/jobs/haproxy/config/backend-ca-certs.pem alpn h2,http/1.1')
      end
    end
  end

  context 'when ha_proxy.backend_ssl is noverify' do
    let(:properties) do
      {
        'backend_servers' => ['10.0.0.1', '10.0.0.2'],
        'backend_ssl' => 'noverify'
      }
    end

    it 'configures the server to use ssl: verify none' do
      expect(backend_http_routers).to include('server node0 10.0.0.1:80 check inter 1000  ssl verify none')
      expect(backend_http_routers).to include('server node1 10.0.0.2:80 check inter 1000  ssl verify none')
    end

    context 'when ha_proxy.enable_http2 is true' do
      let(:properties) do
        {
          'backend_servers' => ['10.0.0.1', '10.0.0.2'],
          'backend_ssl' => 'noverify',
          'enable_http2' => true
        }
      end

      it 'enables h2 ALPN negotiation with backends' do
        expect(backend_http_routers).to include('server node0 10.0.0.1:80 check inter 1000  ssl verify none alpn h2,http/1.1')
        expect(backend_http_routers).to include('server node1 10.0.0.2:80 check inter 1000  ssl verify none alpn h2,http/1.1')
      end
    end
  end

  context 'when ha_proxy.backend_ssl is off' do
    let(:properties) do
      {
        'backend_servers' => ['10.0.0.1', '10.0.0.2'],
        'backend_ssl' => 'off'
      }
    end

    it 'configures the server to not use ssl' do
      expect(backend_http_routers).to include('server node0 10.0.0.1:80 check inter 1000')
      expect(backend_http_routers).to include('server node1 10.0.0.2:80 check inter 1000')
    end

    context 'when ha_proxy.enable_http2 is true' do
      let(:properties) do
        {
          'backend_servers' => ['10.0.0.1', '10.0.0.2'],
          'backend_ssl' => 'off',
          'enable_http2' => true
        }
      end

      it 'does not include ALPN configuration' do
        expect(backend_http_routers).to include('server node0 10.0.0.1:80 check inter 1000')
        expect(backend_http_routers).to include('server node1 10.0.0.2:80 check inter 1000')
      end
    end
  end

  context 'when ha_proxy.backend_port is provided' do
    let(:properties) do
      {
        'backend_servers' => ['10.0.0.1', '10.0.0.2'],
        'backend_port' => 7000
      }
    end

    it 'overrides the default port' do
      expect(backend_http_routers).to include('server node0 10.0.0.1:7000 check inter 1000')
      expect(backend_http_routers).to include('server node1 10.0.0.2:7000 check inter 1000')
    end
  end

  context 'when ha_proxy.resolvers are provided' do
    let(:properties) do
      {
        'resolvers' => [{ 'public' => '1.1.1.1' }],
        'backend_servers' => ['10.0.0.1', '10.0.0.2']
      }
    end

    it 'sets the resolver on the server configuration' do
      expect(backend_http_routers).to include('server node0 10.0.0.1:80 resolvers default check inter 1000')
      expect(backend_http_routers).to include('server node1 10.0.0.2:80 resolvers default check inter 1000')
    end
  end

  context 'when the backend configuration is provided via the http_backend link' do
    let(:http_backend_link) do
      Bosh::Template::Test::Link.new(
        name: 'http_backend',
        instances: [
          # will appear in same AZ
          Bosh::Template::Test::LinkInstance.new(address: 'backend.az1.internal', az: 'az1'),

          # will appear in another AZ
          Bosh::Template::Test::LinkInstance.new(address: 'backend.az2.internal', az: 'az2')
        ]
      )
    end

    let(:haproxy_conf) do
      parse_haproxy_config(template.render({ 'ha_proxy' => properties }, consumes: [http_backend_link]))
    end

    it 'correctly configures the servers' do
      expect(backend_http_routers).to include('server node0 backend.az1.internal:80 check inter 1000')
      expect(backend_http_routers).to include('server node1 backend.az2.internal:80 check inter 1000')
    end

    context 'when ha_proxy.backend_prefer_local_az is true' do
      let(:properties) do
        { 'backend_prefer_local_az' => true }
      end

      it 'configures servers in other azs as backup servers' do
        expect(backend_http_routers).to include('server node0 backend.az1.internal:80 check inter 1000')
        expect(backend_http_routers).to include('server node1 backend.az2.internal:80 check inter 1000   backup')
      end
    end
  end
end
