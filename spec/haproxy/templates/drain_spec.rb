# frozen_string_literal: true

require 'rspec'

describe 'bin/drain' do
  let(:template) { haproxy_job.template('bin/drain') }

  let(:backend_tcp_link) do
    Bosh::Template::Test::Link.new(
      name: 'tcp_backend',
      instances: [Bosh::Template::Test::LinkInstance.new(address: 'postgres.backend.com', name: 'postgres')]
    )
  end

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

        context 'when tcp backends are defined' do
          it 'includes drain and grace logic' do
            drain = template.render(
              {
                'ha_proxy' => {
                  'drain_enable' => true,
                  'tcp' => [{
                    'name' => 'redis',
                    'port' => 6379,
                    'backend_servers' => ['10.0.0.1', '10.0.0.2'],
                    'health_check_http' => 2223
                  }]
                }
              }
            )
            expect(drain).not_to include('drain is disabled')
            expect(drain).to include('socat')
            expect(drain).to include('disable frontend health_check_http_tcp-redis')
          end
        end

        context 'when tcp backends consumed via link' do
          it 'includes drain and grace logic' do
            drain = template.render(
              {
                'ha_proxy' => {
                  'drain_enable' => true,
                  'tcp_link_port' => 5432
                }
              }, consumes: [backend_tcp_link]
            )
            expect(drain).not_to include('drain is disabled')
            expect(drain).to include('socat')
            expect(drain).to include('disable frontend health_check_http_tcp-postgres')
          end
        end

        context 'when PROXY CIDRs are provided' do
          it 'includes the PROXY frontend in drain logic' do
            drain = template.render(
              {
                'ha_proxy' => {
                  'drain_enable' => true,
                  'enable_health_check_http' => true,
                  'expect_proxy_cidrs' => ['10.0.0.0/8']
                }
              }
            )
            expect(drain).not_to include('drain is disabled')
            expect(drain).to include('socat')
            expect(drain).to include('disable frontend health_check_http_url_proxy_protocol')
          end
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
