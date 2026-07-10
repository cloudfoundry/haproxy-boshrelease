# frozen_string_literal: true

require 'rspec'

describe 'config/rate_limit_exclusion_cidrs.txt' do
  let(:template) { haproxy_job.template('config/rate_limit_exclusion_cidrs.txt') }

  context 'when ha_proxy.connections_rate_limit.exclude_cidrs is provided' do
    context 'when an array of cidrs is provided' do
      it 'has the correct contents' do
        expect(template.render({
          'ha_proxy' => {
            'connections_rate_limit' => {
              'exclude_cidrs' => [
                '10.0.0.0/8',
                '192.168.2.0/24'
              ]
            }
          }
        })).to eq(<<~EXPECTED)
          # generated from rate_limit_exclusion_cidrs.txt.erb

          # BEGIN rate limit exclusion cidrs
          # detected cidrs provided as array in cleartext format
          10.0.0.0/8
          192.168.2.0/24

          # END rate limit exclusion cidrs

        EXPECTED
      end
    end

    context 'when a base64-encoded, gzipped config is provided' do
      it 'has the correct contents' do
        expect(template.render({
          'ha_proxy' => {
            'connections_rate_limit' => {
              'exclude_cidrs' => gzip_and_b64_encode(<<~INPUT)
                10.0.0.0/8
                192.168.2.0/24
              INPUT
            }
          }
        })).to eq(<<~EXPECTED)
          # generated from rate_limit_exclusion_cidrs.txt.erb

          # BEGIN rate limit exclusion cidrs
          10.0.0.0/8
          192.168.2.0/24

          # END rate limit exclusion cidrs

        EXPECTED
      end
    end
  end

  context 'when ha_proxy.connections_rate_limit.exclude_cidrs is not provided' do
    it 'is empty' do
      expect(template.render({})).to be_a_blank_string
    end
  end
end