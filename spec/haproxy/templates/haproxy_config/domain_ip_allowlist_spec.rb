# frozen_string_literal: true

require 'rspec'

describe 'config/haproxy.config domain-IP allowlist' do
  let(:haproxy_conf) do
    parse_haproxy_config(template.render({ 'ha_proxy' => properties }))
  end

  let(:frontend_http) { haproxy_conf['frontend http-in'] }
  let(:frontend_https) { haproxy_conf['frontend https-in'] }
  let(:frontend_wss) { haproxy_conf['frontend wss-in'] }

  let(:default_properties) do
    {
      'ssl_pem' => 'ssl pem contents', # required for https-in and wss-in frontends
      'enable_4443' => true            # required for wss-in frontend
    }
  end

  let(:properties) { default_properties }

  context 'when ha_proxy.enable_domain_ip_allowlist is not set' do
    it 'does not include domain-IP allowlist rules in http-in' do
      expect(frontend_http).not_to include('set-var(req.ip_bin)')
      expect(frontend_http).not_to include('domain_ip_allowlist.acl')
      expect(frontend_http).not_to include('http-request deny status 403')
    end

    it 'does not include domain-IP allowlist rules in https-in' do
      expect(frontend_https).not_to include('set-var(req.ip_bin)')
      expect(frontend_https).not_to include('domain_ip_allowlist.acl')
    end

    it 'does not include domain-IP allowlist rules in wss-in' do
      expect(frontend_wss).not_to include('set-var(req.ip_bin)')
      expect(frontend_wss).not_to include('domain_ip_allowlist.acl')
    end
  end

  context 'when ha_proxy.enable_domain_ip_allowlist is true' do
    let(:properties) { default_properties.merge('enable_domain_ip_allowlist' => true) }

    it 'converts source IP to binary in http-in' do
      expect(frontend_http).to include('http-request set-var(req.ip_bin) src,base2')
    end

    it 'sets IP protocol version variable in http-in' do
      expect(frontend_http).to include('http-request set-var(req.ip_proto) str(4)')
      expect(frontend_http).to include('http-request set-var(req.ip_proto) str(6) if { var(req.ip_bin),length gt 32 }')
    end

    it 'extracts domain and parent domain from Host header in http-in' do
      expect(frontend_http).to include('http-request set-var(req.domain) hdr(host),host_only,lower')
      expect(frontend_http).to include('http-request set-var(req.parent_domain) var(req.domain),regsub(^[^\.]+,)')
    end

    it 'builds lookup keys for domain and parent domain in http-in' do
      expect(frontend_http).to include('http-request set-var-fmt(req.domain_key) %[var(req.domain)]|%[var(req.ip_proto)]|%[var(req.ip_bin)]')
      expect(frontend_http).to include('http-request set-var-fmt(req.parent_domain_key) %[var(req.parent_domain)]|%[var(req.ip_proto)]|%[var(req.ip_bin)]')
    end

    it 'defines ACLs against the allowlist file in http-in' do
      expect(frontend_http).to include('acl domain_ip_matched var(req.domain_key) -m beg -f opt@/var/vcap/jobs/haproxy/config/domain_ip_allowlist.acl')
      expect(frontend_http).to include('acl parent_domain_ip_matched var(req.parent_domain_key) -m beg -f opt@/var/vcap/jobs/haproxy/config/domain_ip_allowlist.acl')
    end

    it 'sets block_reason and denies with 403 when neither ACL matches in http-in' do
      expect(frontend_http).to include('http-request set-var-fmt(txn.block_reason) "blocked by domain-ip allowlist, key=%[var(req.domain_key)]" if !domain_ip_matched !parent_domain_ip_matched')
      expect(frontend_http).to include('http-request deny status 403 content-type text/plain string "blocked by domain-ip allowlist" if !domain_ip_matched !parent_domain_ip_matched')
    end

    it 'includes domain-IP allowlist rules in https-in' do
      expect(frontend_https).to include('http-request set-var(req.ip_bin) src,base2')
      expect(frontend_https).to include('acl domain_ip_matched var(req.domain_key) -m beg -f opt@/var/vcap/jobs/haproxy/config/domain_ip_allowlist.acl')
      expect(frontend_https).to include('acl parent_domain_ip_matched var(req.parent_domain_key) -m beg -f opt@/var/vcap/jobs/haproxy/config/domain_ip_allowlist.acl')
      expect(frontend_https).to include('http-request deny status 403 content-type text/plain string "blocked by domain-ip allowlist" if !domain_ip_matched !parent_domain_ip_matched')
    end

    it 'includes domain-IP allowlist rules in wss-in' do
      expect(frontend_wss).to include('http-request set-var(req.ip_bin) src,base2')
      expect(frontend_wss).to include('acl domain_ip_matched var(req.domain_key) -m beg -f opt@/var/vcap/jobs/haproxy/config/domain_ip_allowlist.acl')
      expect(frontend_wss).to include('acl parent_domain_ip_matched var(req.parent_domain_key) -m beg -f opt@/var/vcap/jobs/haproxy/config/domain_ip_allowlist.acl')
      expect(frontend_wss).to include('http-request deny status 403 content-type text/plain string "blocked by domain-ip allowlist" if !domain_ip_matched !parent_domain_ip_matched')
    end
  end
end
