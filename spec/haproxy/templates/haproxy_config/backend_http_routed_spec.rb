# frozen_string_literal: true

require 'rspec'

describe 'config/haproxy.config backend http-routed-backend-X' do
  let(:haproxy_conf) do
    parse_haproxy_config(template.render({ 'ha_proxy' => properties }))
  end

  let(:default_properties) do
    {
      'routed_backend_servers' => {
        '/images' => {
          'servers' => ['10.0.0.2', '10.0.0.3'],
          'port' => '443'
        },
        '/auth' => {
          'servers' => ['10.0.0.8', '10.0.0.9'],
          'port' => '8080'
        }
      }
    }
  end

  let(:properties) { default_properties }

  let(:backend_images) { haproxy_conf['backend http-routed-backend-9c1bb7'] }
  let(:backend_auth) { haproxy_conf['backend http-routed-backend-7d2f30'] }

  it 'has the correct mode' do
    expect(backend_images).to include('mode http')
    expect(backend_auth).to include('mode http')
  end

  it 'uses round-robin load balancing' do
    expect(backend_images).to include('balance roundrobin')
    expect(backend_auth).to include('balance roundrobin')
  end

  context 'when ha_proxy.compress_types are provided' do
    let(:properties) do
      default_properties.deep_merge({ 'compress_types' => 'text/html text/plain text/css' })
    end

    it 'configures the compression type and algorithm' do
      expect(backend_images).to include('compression algo gzip')
      expect(backend_images).to include('compression type text/html text/plain text/css')

      expect(backend_auth).to include('compression algo gzip')
      expect(backend_auth).to include('compression type text/html text/plain text/css')
    end
  end

  it 'configures the backend servers' do
    expect(backend_images).to include('server node0 10.0.0.2:443 check inter 1000')
    expect(backend_images).to include('server node1 10.0.0.3:443 check inter 1000')
    expect(backend_auth).to include('server node0 10.0.0.8:8080 check inter 1000')
    expect(backend_auth).to include('server node1 10.0.0.9:8080 check inter 1000')
  end

  context 'when ha_proxy.resolvers are provided' do
    let(:properties) do
      default_properties.deep_merge({ 'resolvers' => [{ 'public' => '1.1.1.1' }] })
    end

    it 'sets the resolver on the server configuration' do
      expect(backend_images).to include('server node0 10.0.0.2:443 resolvers default check inter 1000')
      expect(backend_images).to include('server node1 10.0.0.3:443 resolvers default check inter 1000')
      expect(backend_auth).to include('server node0 10.0.0.8:8080 resolvers default check inter 1000')
      expect(backend_auth).to include('server node1 10.0.0.9:8080 resolvers default check inter 1000')
    end
  end

  context 'when backend_use_http_health is true' do
    let(:properties) do
      default_properties.deep_merge({
        'routed_backend_servers' => {
          '/images' => {
            'backend_use_http_health' => true
          }
        }
      })
    end

    it 'configures the healthcheck' do
      expect(backend_images).to include('option httpchk GET /health')
    end

    it 'uses the backend port for the healthcheck' do
      expect(backend_images).to include('server node0 10.0.0.2:443 check inter 1000 port 443')
      expect(backend_images).to include('server node1 10.0.0.3:443 check inter 1000 port 443')
    end

    context 'when backend_http_health_port is provided' do
      let(:properties) do
        default_properties.deep_merge({
          'routed_backend_servers' => {
            '/images' => {
              'backend_use_http_health' => true,
              'backend_http_health_port' => 9999
            }
          }
        })
      end

      it 'configures the correct check port on the servers' do
        expect(backend_images).to include('server node0 10.0.0.2:443 check inter 1000 port 9999')
        expect(backend_images).to include('server node1 10.0.0.3:443 check inter 1000 port 9999')
      end
    end

    context 'when backend_http_health_uri is provided' do
      let(:properties) do
        default_properties.deep_merge({
          'routed_backend_servers' => {
            '/images' => {
              'backend_use_http_health' => true,
              'backend_http_health_uri' => '/alive'
            }
          }
        })
      end

      it 'overrides the default health check uri' do
        expect(backend_images).to include('option httpchk GET /alive')
      end
    end
  end

  context 'when backend_ssl is verify' do
    let(:properties) do
      default_properties.deep_merge({
        'routed_backend_servers' => {
          '/images' => {
            'backend_ssl' => 'verify'
          }
        }
      })
    end

    it 'configures the server to use ssl: verify' do
      expect(backend_images).to include('server node0 10.0.0.2:443 check inter 1000  ssl verify required ca-file /var/vcap/jobs/haproxy/config/backend-ca-certs.pem')
      expect(backend_images).to include('server node1 10.0.0.3:443 check inter 1000  ssl verify required ca-file /var/vcap/jobs/haproxy/config/backend-ca-certs.pem')
    end

    context 'when ha_proxy.enable_http2 is true and ha_proxy.enable_http2_backend is default' do
      let(:properties) do
        default_properties.deep_merge({
          'routed_backend_servers' => {
            '/images' => {
              'backend_ssl' => 'verify'
            }
          },
          'enable_http2' => true
        })
      end

      it 'enables h2 ALPN negotiation with routed backends' do
        expect(backend_images).to include('server node0 10.0.0.2:443 check inter 1000  ssl verify required ca-file /var/vcap/jobs/haproxy/config/backend-ca-certs.pem alpn h2,http/1.1')
        expect(backend_images).to include('server node1 10.0.0.3:443 check inter 1000  ssl verify required ca-file /var/vcap/jobs/haproxy/config/backend-ca-certs.pem alpn h2,http/1.1')
      end
    end

    context 'when ha_proxy.enable_http2_backend is true' do
      let(:properties) do
        default_properties.deep_merge({
          'routed_backend_servers' => {
            '/images' => {
              'backend_ssl' => 'verify'
            }
          },
          'enable_http2_backend' => true
        })
      end

      it 'enables h2 ALPN negotiation with routed backends' do
        expect(backend_images).to include('server node0 10.0.0.2:443 check inter 1000  ssl verify required ca-file /var/vcap/jobs/haproxy/config/backend-ca-certs.pem alpn h2,http/1.1')
        expect(backend_images).to include('server node1 10.0.0.3:443 check inter 1000  ssl verify required ca-file /var/vcap/jobs/haproxy/config/backend-ca-certs.pem alpn h2,http/1.1')
      end
    end

    context 'when ha_proxy.enable_http2_backend is false' do
      let(:properties) do
        default_properties.deep_merge({
          'routed_backend_servers' => {
            '/images' => {
              'backend_ssl' => 'verify'
            }
          },
          'enable_http2_backend' => false
        })
      end

      it 'does not enable h2 ALPN negotiation with routed backends' do
        expect(backend_images).to include('server node0 10.0.0.2:443 check inter 1000  ssl verify required ca-file /var/vcap/jobs/haproxy/config/backend-ca-certs.pem')
        expect(backend_images).to include('server node1 10.0.0.3:443 check inter 1000  ssl verify required ca-file /var/vcap/jobs/haproxy/config/backend-ca-certs.pem')
      end
    end

    context 'when ha_proxy.backend_verifyhost is provided' do
      let(:properties) do
        default_properties.deep_merge({
          'routed_backend_servers' => {
            '/images' => {
              'backend_ssl' => 'verify',
              'backend_verifyhost' => 'backend.com'
            }
          }
        })
      end

      it 'configures the server to use ssl: verify with verifyhost for the provided host name' do
        expect(backend_images).to include('server node0 10.0.0.2:443 check inter 1000  ssl verify required ca-file /var/vcap/jobs/haproxy/config/backend-ca-certs.pem verifyhost backend.com')
        expect(backend_images).to include('server node1 10.0.0.3:443 check inter 1000  ssl verify required ca-file /var/vcap/jobs/haproxy/config/backend-ca-certs.pem verifyhost backend.com')
      end

      context 'when backend_ssl is not verify' do
        let(:properties) do
          default_properties.deep_merge({
            'routed_backend_servers' => {
              '/images' => {
                'backend_ssl' => 'noverify',
                'backend_verifyhost' => 'backend.com'
              }
            }
          })
        end

        it 'aborts with a meaningful error message' do
          expect do
            backend_images
          end.to raise_error /Conflicting configuration: backend_ssl must be 'verify' to use backend_verifyhost in routed_backend_servers/
        end
      end
    end
  end

  context 'when ha_proxy.backend_ssl is noverify' do
    let(:properties) do
      default_properties.deep_merge({
        'routed_backend_servers' => {
          '/images' => {
            'backend_ssl' => 'noverify'
          }
        }
      })
    end

    it 'configures the server to use ssl: verify none' do
      expect(backend_images).to include('server node0 10.0.0.2:443 check inter 1000  ssl verify none')
      expect(backend_images).to include('server node1 10.0.0.3:443 check inter 1000  ssl verify none')
    end

    context 'when ha_proxy.enable_http2 is true' do
      let(:properties) do
        default_properties.deep_merge({
          'routed_backend_servers' => {
            '/images' => {
              'backend_ssl' => 'noverify'
            }
          },
          'enable_http2' => true
        })
      end

      it 'enables h2 ALPN negotiation with routed backends' do
        expect(backend_images).to include('server node0 10.0.0.2:443 check inter 1000  ssl verify none alpn h2,http/1.1')
        expect(backend_images).to include('server node1 10.0.0.3:443 check inter 1000  ssl verify none alpn h2,http/1.1')
      end
    end
  end

  context 'when ha_proxy.backend_ssl is off' do
    let(:properties) do
      default_properties.deep_merge({
        'routed_backend_servers' => {
          '/images' => {
            'backend_ssl' => 'off'
          }
        }
      })
    end

    it 'configures the server to not use ssl' do
      expect(backend_images).to include('server node0 10.0.0.2:443 check inter 1000')
      expect(backend_images).to include('server node1 10.0.0.3:443 check inter 1000')
    end

    context 'when ha_proxy.enable_http2 is true' do
      let(:properties) do
        default_properties.deep_merge({
          'routed_backend_servers' => {
            '/images' => {
              'backend_ssl' => 'off'
            }
          },
          'enable_http2' => true
        })
      end

      it 'does not include ALPN configuration' do
        expect(backend_images).to include('server node0 10.0.0.2:443 check inter 1000')
        expect(backend_images).to include('server node1 10.0.0.3:443 check inter 1000')
      end
    end
  end

  context 'when ha_proxy.routed_backend_servers is not provided' do
    let(:haproxy_conf) do
      parse_haproxy_config(template.render({}))
    end

    it 'is not included' do
      expect(haproxy_conf).not_to have_key(/backend http-routed-backend/)
    end
  end
end
