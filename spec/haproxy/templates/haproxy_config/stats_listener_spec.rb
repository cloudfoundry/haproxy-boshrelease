# frozen_string_literal: true

require 'rspec'

describe 'config/haproxy.config stats listener' do
  let(:haproxy_conf) do
    parse_haproxy_config(template.render({ 'ha_proxy' => properties }))
  end

  context 'when ha_proxy.stats_enable is true' do
    let(:default_properties) do
      {
        'syslog_server' => '/dev/log',
        'stats_enable' => true,
        'stats_user' => 'admin',
        'stats_password' => 'secret',
        'stats_uri' => 'foo'
      }
    end

    let(:properties) { default_properties }

    let(:stats_listener) { haproxy_conf['listen stats'] }

    it 'sets up a stats listener for each process' do
      expect(stats_listener).to include('bind *:9000')
      expect(stats_listener).to include('acl private src 0.0.0.0/32')
      expect(stats_listener).to include('http-request deny unless private')
      expect(stats_listener).to include('mode http')
      expect(stats_listener).to include('stats enable')
      expect(stats_listener).to include('stats hide-version')
      expect(stats_listener).to include('stats realm "Haproxy Statistics"')
      expect(stats_listener).to include('stats uri /foo')
      expect(stats_listener).to include('stats auth admin:secret')
    end

    context 'when ha_proxy.stats_promex_enable is true' do
      let(:properties) do
        default_properties.merge({ 'stats_promex_enable' => true, 'stats_promex_path' => '/foo' })
      end

      it 'sets up a prometheus exporter endpoint' do
        expect(stats_listener).to include('http-request use-service prometheus-exporter if { path /foo }')
      end
    end

    context 'when ha_proxy.trusted_stats_cidrs is set' do
      let(:properties) do
        default_properties.merge({ 'trusted_stats_cidrs' => '1.2.3.4/32' })
      end

      it 'has the correct acl' do
        expect(stats_listener).to include('acl private src 1.2.3.4/32')
      end
    end

    context 'when ha_proxy.stats_bind is set' do
      let(:properties) do
        default_properties.merge({ 'stats_bind' => '1.2.3.4:5000' })
      end

      it 'overrides the default bind address' do
        expect(stats_listener).to include('bind 1.2.3.4:5000')
      end
    end

    context 'when ha_proxy.stats_user is empty' do
      let(:properties) do
        default_properties.merge({ 'stats_user' => '' })
      end

      it 'removes stats auth' do
        expect(stats_listener).to include('stats enable')
        expect(stats_listener).not_to include(a_string_starting_with('stats auth'))
      end
    end

    context 'when there is no ha_proxy.stats_user key' do
      let(:properties) do
        default_properties.reject { |key| key == 'stats_user' }
      end

      it 'removes stats auth' do
        expect(stats_listener).to include('stats enable')
        expect(stats_listener).not_to include(a_string_starting_with('stats auth'))
      end
    end

  end
end
