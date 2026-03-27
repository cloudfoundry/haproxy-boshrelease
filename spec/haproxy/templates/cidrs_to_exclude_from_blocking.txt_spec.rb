# frozen_string_literal: true

require 'rspec'

describe 'config/cidrs_to_exclude_from_blocking.txt' do
  let(:template) { haproxy_job.template('config/cidrs_to_exclude_from_blocking.txt') }

  context 'when ha_proxy.connections_rate_limit.cidrs_to_exclude is provided' do
    context 'when an array of cidrs is provided' do
      it 'has the correct contents' do
        expect(template.render({
           'ha_proxy' => {
             'connections_rate_limit' => {
               'window_size' => '10s',
               'table_size' => '10m',
               'cidrs_to_exclude' => ['10.0.0.0/8', '3.22.12.3/32']
             }
           }
        })).to eq(<<~EXPECTED)
          # generated from cidrs_to_exclude_from_blocking.txt.erb

          # BEGIN cidrs to exclude from tcp rejection because of connection rate limiting
          # detected cidrs provided as array in cleartext format
          10.0.0.0/8
          3.22.12.3/32

          # END cidrs to exclude from tcp rejection because of connection rate limiting

        EXPECTED
      end
    end

    context 'when a base64-encoded, gzipped config is provided' do
      it 'has the correct contents' do
        expect(template.render({
          'ha_proxy' => {
            'connections_rate_limit' => {
              'cidrs_to_exclude' => gzip_and_b64_encode(<<~INPUT)
              10.0.0.0/8
              3.22.12.3/32
            INPUT
              }
            }
          })).to eq(<<~EXPECTED)
          # generated from cidrs_to_exclude_from_blocking.txt.erb

          # BEGIN cidrs to exclude from tcp rejection because of connection rate limiting
          10.0.0.0/8
          3.22.12.3/32

          # END cidrs to exclude from tcp rejection because of connection rate limiting

        EXPECTED
      end
    end
  end

  context 'when ha_proxy.connections_rate_limit.cidrs_to_exclude is not provided' do
    it 'is empty' do
      expect(template.render({})).to be_a_blank_string
    end
  end
end
