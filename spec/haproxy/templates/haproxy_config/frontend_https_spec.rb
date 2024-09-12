# frozen_string_literal: true

require 'rspec'

describe 'config/haproxy.config HTTPS frontend' do
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

    context 'when ha_proxy.expect_proxy is not empty/nil and ha_proxy.accept_proxy is false' do
      let(:properties) do
        default_properties.merge({ 'accept_proxy' => false,
                                   'expect_proxy' => ['127.0.0.1/8'] })
      end

      it 'sets expect-proxy of tcp connection to the file proxies_cidrs.txt contents' do
        expect(frontend_https).to include('tcp-request connection expect-proxy layer4 if { src -f /var/vcap/jobs/haproxy/config/expect_proxy_cidrs.txt }')
      end
    end

    context 'when ha_proxy.accept_proxy is true and ha_proxy.expect_proxy is not empty/nil' do
        let(:properties) do
          default_properties.merge({ 'accept_proxy' => true,
                                     'expect_proxy' => ['127.0.0.1/8'] })
        end

        it 'aborts with a meaningful error message' do
          expect do
            frontend_https
          end.to raise_error(/Conflicting configuration: accept_proxy and expect_proxy are mutually exclusive/)
        end
    end
  end

  context 'when ha_proxy.disable_domain_fronting is true' do
    let(:properties) do
      default_properties.merge({ 'disable_domain_fronting' => true })
    end

    it 'disables domain fronting by checking SNI against the Host header' do
      expect(frontend_https).to include('http-request set-var(txn.host) hdr(host),host_only')
      expect(frontend_https).to include('acl ssl_sni_http_host_match ssl_fc_sni,lower,strcmp(txn.host) eq 0')
      expect(frontend_https).to include('http-request deny deny_status 421 if { ssl_fc_has_sni } !ssl_sni_http_host_match')
    end
  end

  context 'when ha_proxy.disable_domain_fronting is mtls_only' do
    let(:properties) do
      default_properties.merge({ 'disable_domain_fronting' => 'mtls_only' })
    end

    it 'disables domain fronting by checking SNI against the Host header for mtls connections only' do
      expect(frontend_https).to include('http-request set-var(txn.host) hdr(host),host_only')
      expect(frontend_https).to include('acl ssl_sni_http_host_match ssl_fc_sni,lower,strcmp(txn.host) eq 0')
      expect(frontend_https).to include('http-request deny deny_status 421 if { ssl_fc_has_sni } { ssl_c_used } !ssl_sni_http_host_match')
    end
  end

  context 'when ha_proxy.disable_domain_fronting is false (the default)' do
    it 'allows domain fronting' do
      expect(frontend_https).not_to include(/http-request deny deny_status 421/)
    end
  end

  context 'when ha_proxy.disable_domain_fronting is an invalid value' do
    let(:properties) do
      default_properties.merge({ 'disable_domain_fronting' => 'foobar' })
    end

    it 'aborts with a meaningful error message' do
      expect do
        frontend_https
      end.to raise_error(/Unknown 'disable_domain_fronting' option: foobar. Known options: true, false or 'mtls_only'/)
    end
  end

  context 'when mutual tls is disabled' do
    let(:properties) do
      default_properties.merge({ 'client_cert' => false })
    end

    it 'does not add mTLS headers' do
      expect(frontend_https).not_to include(/http-request set-header X-Forwarded-Client-Cert/)
      expect(frontend_https).not_to include(/http-request set-header X-SSL-Client/)
    end
  end

  context 'when mutual tls is enabled' do
    let(:properties) do
      default_properties.merge({ 'client_cert' => true })
    end

    it 'configures ssl to use the client ca' do
      expect(frontend_https).to include('bind :443  ssl crt /var/vcap/jobs/haproxy/config/ssl  ca-file /etc/ssl/certs/ca-certificates.crt verify optional')
    end

    context 'when ha_proxy.client_cert_ignore_err is all' do
      let(:properties) do
        default_properties.merge({ 'client_cert' => true, 'client_cert_ignore_err' => 'all' })
      end

      it 'adds the crt-ignore-err and ca-ignore-err flags' do
        expect(frontend_https).to include('bind :443  ssl crt /var/vcap/jobs/haproxy/config/ssl  ca-file /etc/ssl/certs/ca-certificates.crt verify optional crt-ignore-err all ca-ignore-err all')
      end

      context 'when client_cert is not enabled' do
        let(:properties) do
          default_properties.merge({ 'client_cert_ignore_err' => 'all' })
        end

        it 'aborts with a meaningful error message' do
          expect do
            frontend_https
          end.to raise_error(/Conflicting configuration: must enable client_cert to use client_cert_ignore_err/)
        end
      end
    end

    context 'when ha_proxy.client_revocation_list is provided' do
      let(:properties) do
        default_properties.merge({ 'client_cert' => true, 'client_revocation_list' => 'client_revocation_list contents' })
      end

      it 'references the crl list' do
        expect(frontend_https).to include('bind :443  ssl crt /var/vcap/jobs/haproxy/config/ssl  ca-file /etc/ssl/certs/ca-certificates.crt verify optional crl-file /var/vcap/jobs/haproxy/config/client-revocation-list.pem')
      end

      context 'when client_cert is not enabled' do
        let(:properties) do
          default_properties.merge({ 'client_revocation_list' => 'client_revocation_list contents' })
        end

        it 'aborts with a meaningful error message' do
          expect do
            frontend_https
          end.to raise_error(/Conflicting configuration: must enable client_cert to use client_revocation_list/)
        end
      end
    end
  end

  describe 'ha_proxy.forwarded_client_cert' do
    context 'when ha_proxy.forwarded_client_cert is always_forward_only' do
      let(:properties) do
        default_properties.merge({ 'forwarded_client_cert' => 'always_forward_only' })
      end

      it 'does not delete mTLS headers' do
        expect(frontend_https).not_to include(/http-request del-header X-Forwarded-Client-Cert/)
        expect(frontend_https).not_to include(/http-request del-header X-SSL-Client/)
      end

      it 'does not add mTLS headers' do
        expect(frontend_https).not_to include(/http-request set-header X-Fowarded-Client-Cert/)
        expect(frontend_https).not_to include(/http-request set-header X-SSL-Client/)
      end
    end

    context 'when ha_proxy.forwarded_client_cert is forward_only' do
      let(:properties) do
        default_properties.merge({ 'forwarded_client_cert' => 'forward_only' })
      end

      it 'deletes mTLS headers' do
        expect(frontend_https).to include('http-request del-header X-Forwarded-Client-Cert')
        expect(frontend_https).to include('http-request del-header X-SSL-Client')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-Session-ID')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-Verify')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-Subject-DN')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-Subject-CN')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-Issuer-DN')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-NotBefore')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-NotAfter')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-Root-CA-DN')
      end

      it 'does not add mTLS headers' do
        expect(frontend_https).not_to include(/http-request set-header X-Fowarded-Client-Cert/)
        expect(frontend_https).not_to include(/http-request set-header X-SSL-Client/)
      end

      context 'when mutual TLS is enabled' do
        let(:properties) do
          default_properties.merge({
            'client_cert' => true,
            'forwarded_client_cert' => 'forward_only'
          })
        end

        it 'deletes mTLS headers when mTLS is not used' do
          expect(frontend_https).to include('http-request del-header X-Forwarded-Client-Cert if ! { ssl_c_used }')
          expect(frontend_https).to include('http-request del-header X-SSL-Client            if ! { ssl_c_used }')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-Session-ID if ! { ssl_c_used }')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-Verify     if ! { ssl_c_used }')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-Subject-DN if ! { ssl_c_used }')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-Subject-CN if ! { ssl_c_used }')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-Issuer-DN  if ! { ssl_c_used }')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-NotBefore  if ! { ssl_c_used }')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-NotAfter   if ! { ssl_c_used }')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-Root-CA-DN if ! { ssl_c_used }')
        end

        it 'does not add mTLS headers' do
          expect(frontend_https).not_to include(/http-request set-header X-Fowarded-Client-Cert/)
          expect(frontend_https).not_to include(/http-request set-header X-SSL-Client/)
        end
      end
    end

    context 'when ha_proxy.forwarded_client_cert is sanitize_set (the default)' do
      it 'always deletes mTLS headers' do
        expect(frontend_https).to include('http-request del-header X-Forwarded-Client-Cert')
        expect(frontend_https).to include('http-request del-header X-SSL-Client')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-Session-ID')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-Verify')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-Subject-DN')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-Subject-CN')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-Issuer-DN')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-NotBefore')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-NotAfter')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-Root-CA-DN')
      end

      it 'does not add mTLS headers' do
        expect(frontend_https).not_to include(/http-request set-header X-Fowarded-Client-Cert/)
        expect(frontend_https).not_to include(/http-request set-header X-SSL-Client/)
      end

      context 'when mutual TLS is enabled' do
        let(:properties) do
          default_properties.merge({ 'client_cert' => true })
        end

        it 'always deletes mTLS headers' do
          expect(frontend_https).to include('http-request del-header X-Forwarded-Client-Cert')
          expect(frontend_https).to include('http-request del-header X-SSL-Client')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-Session-ID')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-Verify')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-Subject-DN')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-Subject-CN')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-Issuer-DN')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-NotBefore')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-NotAfter')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-Root-CA-DN')
        end

        it 'writes mTLS headers when mTLS is used' do
          expect(frontend_https).to include('http-request set-header X-Forwarded-Client-Cert %[ssl_c_der,base64]          if { ssl_c_used }')
          expect(frontend_https).to include('http-request set-header X-SSL-Client            %[ssl_c_used]                if { ssl_c_used }')
          expect(frontend_https).to include('http-request set-header X-SSL-Client-Session-ID %[ssl_fc_session_id,hex]     if { ssl_c_used }')
          expect(frontend_https).to include('http-request set-header X-SSL-Client-Verify     %[ssl_c_verify]              if { ssl_c_used }')
          expect(frontend_https).to include('http-request set-header X-SSL-Client-NotBefore  %{+Q}[ssl_c_notbefore]       if { ssl_c_used }')
          expect(frontend_https).to include('http-request set-header X-SSL-Client-NotAfter   %{+Q}[ssl_c_notafter]        if { ssl_c_used }')
          expect(frontend_https).to include('http-request set-header X-SSL-Client-Subject-DN %{+Q}[ssl_c_s_dn,base64]     if { ssl_c_used }')
          expect(frontend_https).to include('http-request set-header X-SSL-Client-Subject-CN %{+Q}[ssl_c_s_dn(cn),base64] if { ssl_c_used }')
          expect(frontend_https).to include('http-request set-header X-SSL-Client-Issuer-DN  %{+Q}[ssl_c_i_dn,base64]     if { ssl_c_used }')
          expect(frontend_https).to include('http-request set-header X-SSL-Client-Root-CA-DN %{+Q}[ssl_c_r_dn,base64]     if { ssl_c_used }')
        end

        context 'when ha_proxy.legacy_xfcc_header_mapping is true' do
          let(:properties) do
            default_properties.merge({ 'client_cert' => true, 'legacy_xfcc_header_mapping' => true })
          end

          it 'writes mTLS headers without base64 encoding when mTLS is used' do
            expect(frontend_https).to include('http-request set-header X-SSL-Client-Subject-DN %{+Q}[ssl_c_s_dn]            if { ssl_c_used }')
            expect(frontend_https).to include('http-request set-header X-SSL-Client-Subject-CN %{+Q}[ssl_c_s_dn(cn)]        if { ssl_c_used }')
            expect(frontend_https).to include('http-request set-header X-SSL-Client-Issuer-DN  %{+Q}[ssl_c_i_dn]            if { ssl_c_used }')
            expect(frontend_https).to include('http-request set-header X-SSL-Client-Root-CA-DN %{+Q}[ssl_c_r_dn]            if { ssl_c_used }')
          end
        end
      end
    end

    context 'when ha_proxy.forwarded_client_cert is forward_only_if_route_service' do
      let(:properties) do
        default_properties.merge({ 'forwarded_client_cert' => 'forward_only_if_route_service' })
      end

      it 'deletes mTLS headers for non-route service requests (for mTLS and non-mTLS)' do
        expect(frontend_https).to include('acl route_service_request hdr(X-Cf-Proxy-Signature) -m found')
        expect(frontend_https).to include('http-request del-header X-Forwarded-Client-Cert if !route_service_request')
        expect(frontend_https).to include('http-request del-header X-SSL-Client            if !route_service_request')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-Session-ID if !route_service_request')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-Verify     if !route_service_request')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-Subject-DN if !route_service_request')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-Subject-CN if !route_service_request')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-Issuer-DN  if !route_service_request')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-NotBefore  if !route_service_request')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-NotAfter   if !route_service_request')
        expect(frontend_https).to include('http-request del-header X-SSL-Client-Root-CA-DN if !route_service_request')
      end

      it 'does not add mTLS headers' do
        expect(frontend_https).not_to include(/http-request set-header X-Fowarded-Client-Cert/)
        expect(frontend_https).not_to include(/http-request set-header X-SSL-Client/)
      end

      context 'when mutual TLS is enabled' do
        let(:properties) do
          default_properties.merge({
            'client_cert' => true,
            'forwarded_client_cert' => 'forward_only_if_route_service'
          })
        end

        it 'deletes mTLS headers for non-route service requests (for mTLS and non-mTLS)' do
          expect(frontend_https).to include('acl route_service_request hdr(X-Cf-Proxy-Signature) -m found')
          expect(frontend_https).to include('http-request del-header X-Forwarded-Client-Cert if !route_service_request')
          expect(frontend_https).to include('http-request del-header X-SSL-Client            if !route_service_request')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-Session-ID if !route_service_request')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-Verify     if !route_service_request')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-Subject-DN if !route_service_request')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-Subject-CN if !route_service_request')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-Issuer-DN  if !route_service_request')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-NotBefore  if !route_service_request')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-NotAfter   if !route_service_request')
          expect(frontend_https).to include('http-request del-header X-SSL-Client-Root-CA-DN if !route_service_request')
        end

        it 'overwrites mTLS headers when mTLS is used' do
          expect(frontend_https).to include('http-request set-header X-Forwarded-Client-Cert %[ssl_c_der,base64]          if { ssl_c_used }')
          expect(frontend_https).to include('http-request set-header X-SSL-Client            %[ssl_c_used]                if { ssl_c_used }')
          expect(frontend_https).to include('http-request set-header X-SSL-Client-Session-ID %[ssl_fc_session_id,hex]     if { ssl_c_used }')
          expect(frontend_https).to include('http-request set-header X-SSL-Client-Verify     %[ssl_c_verify]              if { ssl_c_used }')
          expect(frontend_https).to include('http-request set-header X-SSL-Client-NotBefore  %{+Q}[ssl_c_notbefore]       if { ssl_c_used }')
          expect(frontend_https).to include('http-request set-header X-SSL-Client-NotAfter   %{+Q}[ssl_c_notafter]        if { ssl_c_used }')
          expect(frontend_https).to include('http-request set-header X-SSL-Client-Subject-DN %{+Q}[ssl_c_s_dn,base64]     if { ssl_c_used }')
          expect(frontend_https).to include('http-request set-header X-SSL-Client-Subject-CN %{+Q}[ssl_c_s_dn(cn),base64] if { ssl_c_used }')
          expect(frontend_https).to include('http-request set-header X-SSL-Client-Issuer-DN  %{+Q}[ssl_c_i_dn,base64]     if { ssl_c_used }')
          expect(frontend_https).to include('http-request set-header X-SSL-Client-Root-CA-DN %{+Q}[ssl_c_r_dn,base64]     if { ssl_c_used }')
        end

        context 'when ha_proxy.legacy_xfcc_header_mapping is true' do
          let(:properties) do
            default_properties.merge({
              'client_cert' => true,
              'forwarded_client_cert' => 'forward_only_if_route_service',
              'legacy_xfcc_header_mapping' => true
            })
          end

          it 'overwrites mTLS headers without base64-encoding when mTLS is used' do
            expect(frontend_https).to include('http-request set-header X-SSL-Client-Subject-DN %{+Q}[ssl_c_s_dn]            if { ssl_c_used }')
            expect(frontend_https).to include('http-request set-header X-SSL-Client-Subject-CN %{+Q}[ssl_c_s_dn(cn)]        if { ssl_c_used }')
            expect(frontend_https).to include('http-request set-header X-SSL-Client-Issuer-DN  %{+Q}[ssl_c_i_dn]            if { ssl_c_used }')
            expect(frontend_https).to include('http-request set-header X-SSL-Client-Root-CA-DN %{+Q}[ssl_c_r_dn]            if { ssl_c_used }')
          end
        end
      end
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
          end.to raise_error(/Conflicting configuration: hsts_enable must be true to use hsts_include_subdomains/)
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
          end.to raise_error(/Conflicting configuration: hsts_enable must be true to enable hsts_preload/)
        end
      end
    end
  end

  it 'correct request capturing configuration' do
    expect(frontend_https).to include('capture request header Host len 256')
  end

  context 'when only HTTP1 backend servers are available' do
    it 'has the uses the HTTP1 backend default backend' do
      expect(frontend_https).to include('default_backend http-routers-http1')
    end
  end

  context 'when HTTP1 and HTTP2 backend servers are available' do
    let(:properties) do
      default_properties.merge({
        'disable_backend_http2_websockets' => true,
        'enable_http2' => true,
        'backend_ssl' => 'verify'
      })
    end

    it 'uses the HTTP2 backend default backend' do
      expect(frontend_https).to include('default_backend http-routers-http2')
    end
  end

  context 'when only HTTP2 backend servers are available' do
    let(:properties) do
      default_properties.merge({
        'disable_backend_http2_websockets' => false,
        'enable_http2' => true,
        'backend_match_http_protocol' => false,
        'backend_ssl' => 'verify'
      })
    end

    it 'uses the HTTP2 backend default backend' do
      expect(frontend_https).to include('default_backend http-routers-http2')
    end
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

  context 'when ha_proxy.strip_headers are provided' do
    let(:properties) do
      default_properties.merge({ 'strip_headers' => %w[MyHeader MySecondHeader] })
    end

    it 'deletes the headers' do
      expect(frontend_https).to include('http-request del-header MyHeader')
      expect(frontend_https).to include('http-request del-header MySecondHeader')
    end
  end

  context 'when ha_proxy.strip_headers and ha_proxy.headers are provided' do
    let(:properties) do
      default_properties.merge({
        'strip_headers' => %w[MyHeader MySecondHeader],
        'headers' => ['MyHeader: my-custom-header']
      })
    end

    it 'contains the headers' do
      expect(frontend_https).to include('http-request del-header MyHeader')
      expect(frontend_https).to include('http-request del-header MySecondHeader')
      expect(frontend_https).to include('http-request add-header MyHeader:\ my-custom-header ""')
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
      expect(frontend_https).to include('acl routed_backend_9c1bb7_0 path_beg /images')
      expect(frontend_https).to include('use_backend http-routed-backend-9c1bb7 if routed_backend_9c1bb7_0')
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
        expect(frontend_https).to include('acl routed_backend_9c1bb7_1 method GET')
        expect(frontend_https).to include('acl routed_backend_9c1bb7_2 path_end /foo')
        expect(frontend_https).to include('use_backend http-routed-backend-9c1bb7 if routed_backend_9c1bb7_0 routed_backend_9c1bb7_1 routed_backend_9c1bb7_2')
      end
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

  context 'when backend_match_http_protocol is true' do
    let(:properties) do
      default_properties.merge({
        'backend_match_http_protocol' => true,
        'backend_ssl' => 'verify'
      })
    end

    it 'enables config to match the protocol' do
      expect(frontend_https).to include('acl is_http2 ssl_fc_alpn,lower,strcmp(proc.h2_alpn_tag) eq 0')
      expect(frontend_https).to include('use_backend http-routers-http1 if ! is_http2')
      expect(frontend_https).to include('use_backend http-routers-http2 if is_http2')
    end

    context('when backend_ssl is off') do
      let(:properties) do
        default_properties.merge({
          'backend_match_http_protocol' => true,
          'backend_ssl' => 'off'
        })
      end

      it 'does not override the default backend' do
        expect(frontend_https).not_to include(/use_backend/)
      end
    end
  end

  context 'when no ssl options are provided' do
    let(:properties) { {} }

    it 'removes the https frontend' do
      expect(haproxy_conf).not_to have_key('frontend https-in')
    end
  end
end
