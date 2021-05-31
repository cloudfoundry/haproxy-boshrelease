# frozen_string_literal: true

require 'rspec'
require 'haproxy-tools'

describe 'config/haproxy.config stats listener' do
  let(:template) { haproxy_job.template('config/haproxy.config') }

  let(:haproxy_conf) do
    parse_haproxy_config(template.render({ 'ha_proxy' => properties }))
  end

  context 'when ha_proxy.stats_enable is true' do
    let(:default_properties) do
      {
        'nbproc' => 2,
        'syslog_server' => '/dev/log',
        'stats_enable' => true,
        'stats_user' => 'admin',
        'stats_password' => 'secret',
        'stats_uri' => 'foo'
      }
    end

    let(:properties) { default_properties }

    let(:stats_listener_proc1) { haproxy_conf['listen stats_1'] }
    let(:stats_listener_proc2) { haproxy_conf['listen stats_2'] }

    it 'sets up a stats listener for each process' do
      expect(stats_listener_proc1).to include('bind *:9000')
      expect(stats_listener_proc1).to include('bind-process 1')
      expect(stats_listener_proc1).to include('acl private src 0.0.0.0/32')
      expect(stats_listener_proc1).to include('http-request deny unless private')
      expect(stats_listener_proc1).to include('mode http')
      expect(stats_listener_proc1).to include('stats enable')
      expect(stats_listener_proc1).to include('stats hide-version')
      expect(stats_listener_proc1).to include('stats realm "Haproxy Statistics"')
      expect(stats_listener_proc1).to include('stats uri /foo')
      expect(stats_listener_proc1).to include('stats auth admin:secret')

      expect(stats_listener_proc2).to include('bind *:9001')
      expect(stats_listener_proc2).to include('bind-process 2')
      expect(stats_listener_proc2).to include('acl private src 0.0.0.0/32')
      expect(stats_listener_proc2).to include('http-request deny unless private')
      expect(stats_listener_proc2).to include('mode http')
      expect(stats_listener_proc2).to include('stats enable')
      expect(stats_listener_proc2).to include('stats hide-version')
      expect(stats_listener_proc2).to include('stats realm "Haproxy Statistics"')
      expect(stats_listener_proc2).to include('stats uri /foo')
      expect(stats_listener_proc2).to include('stats auth admin:secret')
    end

    context 'when ha_proxy.trusted_stats_cidrs is set' do
      let(:properties) do
        default_properties.merge({ 'trusted_stats_cidrs' => '1.2.3.4/32' })
      end

      it 'has the correct acl' do
        expect(stats_listener_proc1).to include('acl private src 1.2.3.4/32')
        expect(stats_listener_proc2).to include('acl private src 1.2.3.4/32')
      end
    end

    context 'when ha_proxy.stats_bind is set' do
      let(:properties) do
        default_properties.merge({ 'stats_bind' => '1.2.3.4:5000' })
      end

      it 'overrides the default bind address' do
        expect(stats_listener_proc1).to include('bind 1.2.3.4:5000')
        expect(stats_listener_proc2).to include('bind 1.2.3.4:5001')
      end
    end
  end
end
