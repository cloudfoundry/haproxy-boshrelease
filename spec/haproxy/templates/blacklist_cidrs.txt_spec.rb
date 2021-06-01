# frozen_string_literal: true

require 'rspec'

describe 'config/blacklist_cidrs.txt' do
  let(:template) { haproxy_job.template('config/blacklist_cidrs.txt') }

  context 'when ha_proxy.cidr_blacklist is provided' do
    context 'when an array of cidrs is provided' do
      it 'has the correct contents' do
        expect(template.render({
          'ha_proxy' => {
            'cidr_blacklist' => [
              '10.0.0.0/8',
              '192.168.2.0/24'
            ]
          }
        })).to eq(<<~EXPECTED)
          # generated from blacklist_cidrs.txt.erb

          # BEGIN blacklist cidrs
          # detected cidrs provided as array in cleartext format
          10.0.0.0/8
          192.168.2.0/24

          # END blacklist cidrs

        EXPECTED
      end
    end

    context 'when a base64-encoded, gzipped config is provided' do
      it 'has the correct contents' do
        expect(template.render({
          'ha_proxy' => {
            'cidr_blacklist' => gzip_and_b64_encode(<<~INPUT)
              10.0.0.0/8
              192.168.2.0/24
            INPUT
          }
        })).to eq(<<~EXPECTED)
          # generated from blacklist_cidrs.txt.erb

          # BEGIN blacklist cidrs
          10.0.0.0/8
          192.168.2.0/24

          # END blacklist cidrs

        EXPECTED
      end
    end
  end

  context 'when ha_proxy.cidr_blacklist is not provided' do
    it 'is empty' do
      expect(template.render({})).to be_a_blank_string
    end
  end
end
