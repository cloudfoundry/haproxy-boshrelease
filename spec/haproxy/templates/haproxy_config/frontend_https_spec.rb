# frozen_string_literal: true

require 'rspec'

describe 'config/haproxy.config HTTPS frontend' do
  let(:template) { haproxy_job.template('config/haproxy.config') }

  let(:haproxy_conf) do
    parse_haproxy_config(template.render({ 'ha_proxy' => properties }))
  end

  let(:frontend_https) { haproxy_conf['frontend https-in'] }
  let(:default_properties) do
    {
      'ssl_pem' => 'ssl pem contents'
    }
  end

  let(:properties) { default_properties }

  context 'when ha_proxy.drain_enable is true' do
    let(:properties) do
      default_properties.merge({ 'drain_enable' => true })
    end

    it 'has a default grace period of 0 milliseconds' do
      expect(frontend_https).to include('grace 0')
    end

    context('when ha_proxy.drain_frontend_grace_time is provided') do
      let(:properties) do
        default_properties.merge({ 'drain_enable' => true, 'drain_frontend_grace_time' => 12 })
      end

      it 'overrides the grace period' do
        expect(frontend_https).to include('grace 12000')
      end

      context 'when ha_proxy.drain_enable is false' do
        let(:properties) do
          default_properties.merge({ 'drain_enable' => false, 'drain_frontend_grace_time' => 12 })
        end

        it 'aborts with a meaningful error message' do
          expect do
            frontend_https
          end.to raise_error /Conflicting configuration: drain_enable must be true to use drain_frontend_grace_time/
        end
      end
    end
  end

  it 'binds to all interfaces by default' do
    expect(frontend_https).to include('bind :443  ssl crt /var/vcap/jobs/haproxy/config/ssl')
  end

  context 'when ha_proxy.binding_ip is provided' do
    let(:properties) do
      default_properties.merge({ 'binding_ip' => '1.2.3.4' })
    end

    it 'binds to the provided ip' do
      expect(frontend_https).to include('bind 1.2.3.4:443  ssl crt /var/vcap/jobs/haproxy/config/ssl')
    end

    context 'when ha_proxy.v4v6 is true and binding_ip is ::' do
      let(:properties) do
        default_properties.merge({ 'v4v6' => true, 'binding_ip' => '::' })
      end

      it 'enables ipv6' do
        expect(frontend_https).to include('bind :::443  ssl crt /var/vcap/jobs/haproxy/config/ssl  v4v6')
      end
    end

    context 'when ha_proxy.accept_proxy is true' do
      let(:properties) do
        default_properties.merge({ 'accept_proxy' => true })
      end

      it 'sets accept-proxy' do
        expect(frontend_https).to include('bind :443 accept-proxy ssl crt /var/vcap/jobs/haproxy/config/ssl')
      end
    end
  end

  context 'when mutual tls is enabled' do
    let(:properties) do
      default_properties.merge({ 'client_cert' => 'client_cert contents' })
    end

    it 'configures ssl to use the client ca' do
      expect(frontend_https).to include('bind :443  ssl crt /var/vcap/jobs/haproxy/config/ssl  ca-file /etc/ssl/certs/ca-certificates.crt verify optional')
    end

    context 'when ha_proxy.client_cert_ignore_err is true' do
      let(:properties) do
        default_properties.merge({ 'client_cert' => 'client_cert contents', 'client_cert_ignore_err' => true })
      end

      # FIXME: if client_cert_ignore_err is true but client_cert is not provided, then it should error

      it 'adds the crt-ignore-err flag' do
        expect(frontend_https).to include('bind :443  ssl crt /var/vcap/jobs/haproxy/config/ssl  ca-file /etc/ssl/certs/ca-certificates.crt verify optional crt-ignore-err true')
      end
    end

    context 'when ha_proxy.client_revocation_list is provided' do
      let(:properties) do
        default_properties.merge({ 'client_cert' => 'client_cert contents', 'client_revocation_list' => 'client_revocation_list contents' })
      end

      # FIXME: if client_revocation_list is provided but client_cert is not provided, then it should error

      it 'references the crl list' do
        expect(frontend_https).to include('bind :443  ssl crt /var/vcap/jobs/haproxy/config/ssl  ca-file /etc/ssl/certs/ca-certificates.crt verify optional crl-file /var/vcap/jobs/haproxy/config/client-revocation-list.pem')
      end
    end
  end

  context 'when ha_proxy.forwarded_client_cert is always_forward_only (the default)' do
    it 'deletes the X-Forwarded-Client-Cert header by default' do
      expect(frontend_https).to include('http-request del-header X-Forwarded-Client-Cert')
    end
  end

  context 'when ha_proxy.forwarded_client_cert is forward_only' do
    let(:properties) do
      default_properties.merge({ 'forwarded_client_cert' => 'forward_only' })
    end

    it 'deletes the X-Forwarded-Client-Cert header' do
      expect(frontend_https).to include('http-request del-header X-Forwarded-Client-Cert')
    end

    context 'when mutual TLS is enabled' do
      let(:properties) do
        default_properties.merge({
          'client_cert' => 'client_cert contents',
          'forwarded_client_cert' => 'forward_only'
        })
      end

      it 'only deletes the X-Forwarded-Client-Cert header when mTLS is not used' do
        expect(frontend_https).to include('http-request del-header X-Forwarded-Client-Cert if ! { ssl_c_used }')
      end
    end
  end

  context 'when ha_proxy.forwarded_client_cert is sanitize_set' do
    let(:properties) do
      default_properties.merge({ 'forwarded_client_cert' => 'sanitize_set' })
    end

    it 'deletes the X-Forwarded-Client-Cert header' do
      expect(frontend_https).to include('http-request del-header X-Forwarded-Client-Cert')
    end

    context 'when mutual TLS is enabled' do
      let(:properties) do
        default_properties.merge({
          'client_cert' => 'client_cert contents',
          'forwarded_client_cert' => 'sanitize_set'
        })
      end

      it 'sets X-Forwarded-Client-Cert to the client cert for mTLS connections ' do
        expect(frontend_https).to include('http-request del-header X-Forwarded-Client-Cert')
        expect(frontend_https).to include('http-request set-header X-Forwarded-Client-Cert %[ssl_c_der,base64] if { ssl_c_used }')
      end
    end
  end

  context 'when ha_proxy.forwarded_client_cert is forward_only_if_route_service' do
    let(:properties) do
      default_properties.merge({ 'forwarded_client_cert' => 'forward_only_if_route_service' })
    end

    it 'deletes the X-Forwarded-Client-Cert header for non-route service requests' do
      expect(frontend_https).to include('acl route_service_request hdr(X-Cf-Proxy-Signature) -m found')
      expect(frontend_https).to include('http-request del-header X-Forwarded-Client-Cert if !route_service_request')
      expect(frontend_https).to include('http-request set-header X-Forwarded-Client-Cert %[ssl_c_der,base64] if { ssl_c_used }')
    end
  end

  context 'when ha_proxy.hsts_enable is true' do
    let(:properties) do
      default_properties.merge({ 'hsts_enable' => true })
    end

    it 'sets the Strict-Transport-Security header' do
      expect(frontend_https).to include('http-response set-header Strict-Transport-Security max-age=31536000;')
    end

    context 'when ha_proxy.hsts_max_age is provided' do
      let(:properties) do
        default_properties.merge({ 'hsts_enable' => true, 'hsts_max_age' => 9999 })
      end

      it 'sets the Strict-Transport-Security header with the correct max-age' do
        expect(frontend_https).to include('http-response set-header Strict-Transport-Security max-age=9999;')
      end
    end

    context 'when ha_proxy.hsts_include_subdomains is true' do
      let(:properties) do
        default_properties.merge({ 'hsts_enable' => true, 'hsts_include_subdomains' => true })
      end

      it 'sets the includeSubDomains flag' do
        expect(frontend_https).to include('http-response set-header Strict-Transport-Security max-age=31536000;\ includeSubDomains;')
      end

      context 'when ha_proxy.hsts_enable is false' do
        let(:properties) do
          default_properties.merge({ 'hsts_enable' => false, 'hsts_include_subdomains' => true })
        end

        it 'aborts with a meaningful error message' do
          expect do
            frontend_https
          end.to raise_error /Conflicting configuration: hsts_enable must be true to use hsts_include_subdomains/
        end
      end
    end

    context 'when ha_proxy.hsts_preload is true' do
      let(:properties) do
        default_properties.merge({ 'hsts_enable' => true, 'hsts_preload' => true })
      end

      it 'sets the preload flag' do
        expect(frontend_https).to include('http-response set-header Strict-Transport-Security max-age=31536000;\ preload;')
      end

      context 'when ha_proxy.hsts_enable is false' do
        let(:properties) do
          default_properties.merge({ 'hsts_enable' => false, 'hsts_preload' => true })
        end

        it 'aborts with a meaningful error message' do
          expect do
            frontend_https
          end.to raise_error /Conflicting configuration: hsts_enable must be true to enable hsts_preload/
        end
      end
    end
  end

  it 'correct request capturing configuration' do
    expect(frontend_https).to include('capture request header Host len 256')
  end

  it 'has the correct default backend' do
    expect(frontend_https).to include('default_backend http-routers')
  end

  context 'when ha_proxy.http_request_deny_conditions are provided' do
    let(:properties) do
      default_properties.merge({
        'http_request_deny_conditions' => [{
          'condition' => [{
            'acl_name' => 'block_host',
            'acl_rule' => 'hdr_beg(host) -i login'
          }, {
            'acl_name' => 'whitelist_ips',
            'acl_rule' => 'src 5.22.5.11 5.22.5.12',
            'negate' => true
          }]
        }]
      })
    end

    it 'adds the correct acls and http-request deny rules' do
      expect(frontend_https).to include('acl block_host hdr_beg(host) -i login')
      expect(frontend_https).to include('acl whitelist_ips src 5.22.5.11 5.22.5.12')

      expect(frontend_https).to include('http-request deny if block_host !whitelist_ips')
    end
  end

  context 'when a custom ha_proxy.frontend_config is provided' do
    let(:properties) do
      default_properties.merge({ 'frontend_config' => 'custom config content' })
    end

    it 'includes the custom config' do
      expect(frontend_https).to include('custom config content')
    end
  end

  context 'when a ha_proxy.cidr_whitelist is provided' do
    let(:properties) do
      default_properties.merge({ 'cidr_whitelist' => ['172.168.4.1/32', '10.2.0.0/16'] })
    end

    it 'sets the correct acl and content accept rules' do
      expect(frontend_https).to include('acl whitelist src -f /var/vcap/jobs/haproxy/config/whitelist_cidrs.txt')
      expect(frontend_https).to include('tcp-request content accept if whitelist')
    end
  end

  context 'when a ha_proxy.cidr_blacklist is provided' do
    let(:properties) do
      default_properties.merge({ 'cidr_blacklist' => ['172.168.4.1/32', '10.2.0.0/16'] })
    end

    it 'sets the correct acl and content reject rules' do
      expect(frontend_https).to include('acl blacklist src -f /var/vcap/jobs/haproxy/config/blacklist_cidrs.txt')
      expect(frontend_https).to include('tcp-request content reject if blacklist')
    end
  end

  context 'when ha_proxy.block_all is provided' do
    let(:properties) do
      default_properties.merge({ 'block_all' => true })
    end

    it 'sets the correct content reject rules' do
      expect(frontend_https).to include('tcp-request content reject')
    end
  end

  context 'when ha_proxy.headers are provided' do
    let(:properties) do
      default_properties.merge({ 'headers' => ['X-Application-ID: my-custom-header', 'MyCustomHeader: 3'] })
    end

    it 'adds the request headers' do
      expect(frontend_https).to include('http-request add-header X-Application-ID:\ my-custom-header ""')
      expect(frontend_https).to include('http-request add-header MyCustomHeader:\ 3 ""')
    end
  end

  context 'when ha_proxy.rsp_headers are provided' do
    let(:properties) do
      default_properties.merge({ 'rsp_headers' => ['X-Application-ID: my-custom-header', 'MyCustomHeader: 3'] })
    end

    it 'adds the response headers' do
      expect(frontend_https).to include('http-response add-header X-Application-ID:\ my-custom-header ""')
      expect(frontend_https).to include('http-response add-header MyCustomHeader:\ 3 ""')
    end
  end

  context 'when ha_proxy.internal_only_domains are provided' do
    let(:properties) do
      default_properties.merge({ 'internal_only_domains' => ['bosh.internal'] })
    end

    it 'adds the correct acl and http-request deny rules' do
      expect(frontend_https).to include('acl private src -f /var/vcap/jobs/haproxy/config/trusted_domain_cidrs.txt')
      expect(frontend_https).to include('acl internal hdr(Host) -m sub bosh.internal')
      expect(frontend_https).to include('http-request deny if internal !private')
    end
  end

  context 'when ha_proxy.routed_backend_servers are provided' do
    let(:properties) do
      default_properties.merge({
        'routed_backend_servers' => {
          '/images' => {
            'port' => 12_000,
            'servers' => ['10.0.0.1']
          }
        }
      })
    end

    it 'grants access to the backend servers' do
      expect(frontend_https).to include('acl routed_backend_9c1bb7 path_beg /images')
      expect(frontend_https).to include('use_backend http-routed-backend-9c1bb7 if routed_backend_9c1bb7')
    end
  end

  it 'adds the X-Forwarded-Proto header' do
    expect(frontend_https).to include('acl xfp_exists hdr_cnt(X-Forwarded-Proto) gt 0')
    expect(frontend_https).to include('http-request add-header X-Forwarded-Proto "https" if ! xfp_exists')
  end

  context 'when ha_proxy.enable_http2 is true' do
    let(:properties) do
      default_properties.merge({ 'enable_http2' => true })
    end

    it 'enables alpn h2 negotiation' do
      expect(frontend_https).to include('bind :443  ssl crt /var/vcap/jobs/haproxy/config/ssl   alpn h2,http/1.1')
    end
  end

  context 'when no ssl options are provided' do
    let(:properties) { {} }

    it 'removes the https frontend' do
      expect(haproxy_conf).not_to have_key('frontend https-in')
    end
  end
end
