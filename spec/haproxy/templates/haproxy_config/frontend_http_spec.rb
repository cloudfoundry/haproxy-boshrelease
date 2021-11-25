# frozen_string_literal: true

require 'rspec'

describe 'config/haproxy.config HTTP frontend' do
  let(:haproxy_conf) do
    parse_haproxy_config(template.render({ 'ha_proxy' => properties }))
  end

  let(:frontend_http) { haproxy_conf['frontend http-in'] }
  let(:properties) { {} }

  context 'when ha_proxy.drain_enable is true' do
    let(:properties) do
      { 'drain_enable' => true }
    end

    it 'has a default grace period of 0 milliseconds' do
      expect(frontend_http).to include('grace 0')
    end

    context('when ha_proxy.drain_frontend_grace_time is provided') do
      let(:properties) do
        { 'drain_enable' => true, 'drain_frontend_grace_time' => 12 }
      end

      it 'overrides the grace period' do
        expect(frontend_http).to include('grace 12000')
      end

      context 'when ha_proxy.drain_enable is false' do
        let(:properties) do
          { 'drain_enable' => false, 'drain_frontend_grace_time' => 12 }
        end

        it 'aborts with a meaningful error message' do
          expect do
            frontend_http
          end.to raise_error /Conflicting configuration: drain_enable must be true to use drain_frontend_grace_time/
        end
      end
    end
  end

  it 'binds to all interfaces by default' do
    expect(frontend_http).to include('bind :80')
  end

  context 'when ha_proxy.binding_ip is provided' do
    let(:properties) do
      { 'binding_ip' => '1.2.3.4' }
    end

    it 'binds to the provided ip' do
      expect(frontend_http).to include('bind 1.2.3.4:80')
    end

    context 'when ha_proxy.v4v6 is true and binding_ip is ::' do
      let(:properties) do
        { 'v4v6' => true, 'binding_ip' => '::' }
      end

      it 'enables ipv6' do
        expect(frontend_http).to include('bind :::80  v4v6')
      end
    end

    context 'when ha_proxy.accept_proxy is true' do
      let(:properties) do
        { 'accept_proxy' => true }
      end

      it 'sets accept-proxy' do
        expect(frontend_http).to include('bind :80 accept-proxy')
      end
    end
  end

  context 'when a custom ha_proxy.frontend_config is provided' do
    let(:properties) do
      { 'frontend_config' => 'custom config content' }
    end

    it 'includes the custom config' do
      expect(frontend_http).to include('custom config content')
    end
  end

  context 'when a ha_proxy.cidr_whitelist is provided' do
    let(:properties) do
      { 'cidr_whitelist' => ['172.168.4.1/32', '10.2.0.0/16'] }
    end

    it 'sets the correct acl and content accept rules' do
      expect(frontend_http).to include('acl whitelist src -f /var/vcap/jobs/haproxy/config/whitelist_cidrs.txt')
      expect(frontend_http).to include('tcp-request content accept if whitelist')
    end
  end

  context 'when a ha_proxy.cidr_blacklist is provided' do
    let(:properties) do
      { 'cidr_blacklist' => ['172.168.4.1/32', '10.2.0.0/16'] }
    end

    it 'sets the correct acl and content reject rules' do
      expect(frontend_http).to include('acl blacklist src -f /var/vcap/jobs/haproxy/config/blacklist_cidrs.txt')
      expect(frontend_http).to include('tcp-request content reject if blacklist')
    end
  end

  context 'when ha_proxy.block_all is provided' do
    let(:properties) do
      { 'block_all' => true }
    end

    it 'sets the correct content reject rules' do
      expect(frontend_http).to include('tcp-request content reject')
    end
  end

  it 'correct request capturing configuration' do
    expect(frontend_http).to include('capture request header Host len 256')
  end

  context 'when HTTP1 backend servers are available' do
    it 'has the uses the HTTP1 backend default backend' do
      expect(frontend_http).to include('default_backend http-routers-http1')
    end
  end

  context 'when only HTTP1 and HTTP2 backend servers are available' do
    let(:properties) do
      {
        'disable_backend_http2_websockets' => true,
        'enable_http2' => true,
        'backend_ssl' => 'verify'
      }
    end

    it 'uses the HTTP2 backend default backend' do
      expect(frontend_http).to include('default_backend http-routers-http2')
    end
  end

  context 'when only HTTP2 backend servers are available' do
    let(:properties) do
      {
        'disable_backend_http2_websockets' => false,
        'enable_http2' => true,
        'backend_match_http_protocol' => false,
        'backend_ssl' => 'verify'
      }
    end

    it 'uses the HTTP2 backend default backend' do
      expect(frontend_http).to include('default_backend http-routers-http2')
    end
  end

  context 'when ha_proxy.http_request_deny_conditions are provided' do
    let(:properties) do
      {
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
      }
    end

    it 'adds the correct acls and http-request deny rules' do
      expect(frontend_http).to include('acl block_host hdr_beg(host) -i login')
      expect(frontend_http).to include('acl whitelist_ips src 5.22.5.11 5.22.5.12')

      expect(frontend_http).to include('http-request deny if block_host !whitelist_ips')
    end
  end

  context 'when ha_proxy.headers are provided' do
    let(:properties) do
      { 'headers' => ['X-Application-ID: my-custom-header', 'MyCustomHeader: 3'] }
    end

    it 'adds the request headers' do
      expect(frontend_http).to include('http-request add-header X-Application-ID:\ my-custom-header ""')
      expect(frontend_http).to include('http-request add-header MyCustomHeader:\ 3 ""')
    end
  end

  context 'when ha_proxy.rsp_headers are provided' do
    let(:properties) do
      { 'rsp_headers' => ['X-Application-ID: my-custom-header', 'MyCustomHeader: 3'] }
    end

    it 'adds the response headers' do
      expect(frontend_http).to include('http-response add-header X-Application-ID:\ my-custom-header ""')
      expect(frontend_http).to include('http-response add-header MyCustomHeader:\ 3 ""')
    end
  end

  context 'when ha_proxy.internal_only_domains are provided' do
    let(:properties) do
      { 'internal_only_domains' => ['bosh.internal'] }
    end

    it 'adds the correct acl and http-request deny rules' do
      expect(frontend_http).to include('acl private src -f /var/vcap/jobs/haproxy/config/trusted_domain_cidrs.txt')
      expect(frontend_http).to include('acl internal hdr(Host) -m sub bosh.internal')
      expect(frontend_http).to include('http-request deny if internal !private')
    end
  end

  context 'when ha_proxy.routed_backend_servers are provided' do
    let(:properties) do
      {
        'routed_backend_servers' => {
          '/images' => {
            'port' => 12_000,
            'servers' => ['10.0.0.1']
          }
        }
      }
    end

    it 'grants access to the backend servers' do
      expect(frontend_http).to include('acl routed_backend_9c1bb7 path_beg /images')
      expect(frontend_http).to include('use_backend http-routed-backend-9c1bb7 if routed_backend_9c1bb7')
    end

    context 'when a routed_backend_server contains additional_acls' do
      let(:properties) do
        super().deep_merge({
          'routed_backend_servers' => {
            '/images' => {
              'additional_acls' => ['method GET', 'path_end /foo']
            }
          }
        })
      end

      it 'includes additional acls' do
        expect(frontend_http).to include('acl routed_backend_9c1bb7_0 method GET')
        expect(frontend_http).to include('acl routed_backend_9c1bb7_1 path_end /foo')
        expect(frontend_http).to include('use_backend http-routed-backend-9c1bb7 if routed_backend_9c1bb7 routed_backend_9c1bb7_0 routed_backend_9c1bb7_1')
      end
    end
  end

  it 'adds the X-Forwarded-Proto header' do
    expect(frontend_http).to include('acl xfp_exists hdr_cnt(X-Forwarded-Proto) gt 0')
    expect(frontend_http).to include('http-request add-header X-Forwarded-Proto "http" if ! xfp_exists')
  end

  context 'when ha_proxy.https_redirect_all is true' do
    let(:properties) do
      { 'https_redirect_all' => true }
    end

    it 'adds the redirect rule' do
      expect(frontend_http).to include('redirect scheme https code 301 if !{ ssl_fc }')
    end
  end

  context 'when ha_proxy.https_redirect_all is false (the default)' do
    let(:properties) do
      { 'https_redirect_all' => false }
    end

    it 'only redirects domains specified in the redirect map' do
      expect(frontend_http).to include('acl ssl_redirect hdr(host),lower,map_end(/var/vcap/jobs/haproxy/config/ssl_redirect.map,false) -m str true')
      expect(frontend_http).to include('redirect scheme https code 301 if ssl_redirect')
    end
  end

  context 'when ha_proxy.disable_http is true' do
    let(:properties) do
      { 'disable_http' => true }
    end

    it 'removes the http frontend' do
      expect(haproxy_conf).not_to have_key('frontend http-in')
    end
  end
end
