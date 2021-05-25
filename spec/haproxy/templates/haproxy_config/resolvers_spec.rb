# frozen_string_literal: true

require 'rspec'
require 'haproxy-tools'

describe 'config/haproxy.config resolvers' do
  let(:template) { haproxy_job.template('config/haproxy.config') }

  let(:haproxy_conf) do
    parse_haproxy_config(template.render({ 'ha_proxy' => properties }))
  end

  context 'when ha_proxy.resolvers are provided' do
    let(:resolvers_default) { haproxy_conf['resolvers default'] }

    let(:default_properties) do
      {
        'resolvers' => [
          { 'public' => '1.1.1.1' },
          { 'private' => '10.1.1.1' }
        ]
      }
    end

    let(:properties) { default_properties }

    it 'configures a resolver' do
      expect(resolvers_default).to include('hold valid 10s')
      expect(resolvers_default).to include('timeout retry 1s')
      expect(resolvers_default).to include('resolve_retries 3')
      expect(resolvers_default).to include('nameserver public 1.1.1.1:53')
      expect(resolvers_default).to include('nameserver private 10.1.1.1:53')
    end

    context 'when ha_proxy.dns_hold is provided' do
      let(:properties) { default_properties.merge({ 'dns_hold' => '30s' }) }

      it 'overrides the dns hold for the resolver' do
        expect(resolvers_default).to include('hold valid 30s')
      end
    end

    context 'when ha_proxy.resolve_retry_timeout is provided' do
      let(:properties) { default_properties.merge({ 'resolve_retry_timeout' => '5s' }) }

      it 'overrides the resolve_retry_timeout for the resolver' do
        expect(resolvers_default).to include('timeout retry 5s')
      end
    end

    context 'when ha_proxy.resolve_retries is provided' do
      let(:properties) { default_properties.merge({ 'resolve_retries' => 10 }) }

      it 'overrides the resolve_retries for the resolver' do
        expect(resolvers_default).to include('resolve_retries 10')
      end
    end
  end
end
