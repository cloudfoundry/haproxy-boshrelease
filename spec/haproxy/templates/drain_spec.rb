# frozen_string_literal: true

require 'rspec'

describe 'bin/drain' do
  let(:template) { haproxy_job.template('bin/drain') }

  describe 'ha_proxy.drain_enable' do
    context 'when enabled' do
      it 'includes drain logic' do
        drain = template.render(
          {
            'ha_proxy' => {
              'drain_enable' => true
            }
          }
        )
        expect(drain).not_to include('drain is disabled')
      end

      context 'when health checks are enabled' do
        it 'includes drain and grace logic' do
          drain = template.render(
            {
              'ha_proxy' => {
                'drain_enable' => true,
                'enable_health_check_http' => true
              }
            }
          )
          expect(drain).not_to include('drain is disabled')
          expect(drain).to include('socat')
        end
      end

      context 'when a custom ha_proxy.drain_timeout is provided' do
        it 'overrides the default timeout' do
          drain = template.render(
            {
              'ha_proxy' => {
                'drain_enable' => true,
                'drain_timeout' => 123
              }
            }
          )
          expect(drain).not_to include('drain is disabled')
          expect(drain).to include('drain_timeout=123')
          expect(drain).not_to include('socat')
        end
      end
    end

    context 'when disabled' do
      it 'does not include drain logic' do
        drain = template.render(
          {
            'ha_proxy' => {
              'drain_enable' => false
            }
          }
        )
        expect(drain).to include('drain is disabled')
      end
    end
  end
end
