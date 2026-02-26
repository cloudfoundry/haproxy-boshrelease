# frozen_string_literal: true

require 'rspec'

describe 'config/blocklist_cidrs_tcp.txt' do
  let(:template) { haproxy_job.template('config/blocklist_cidrs_tcp.txt') }

  context 'when ha_proxy.cidr_blocklist_tcp is provided' do
    context 'when an array of cidrs is provided' do
      it 'has the correct contents' do
        expect(template.render({
          'ha_proxy' => {
            'cidr_blocklist_tcp' => [
              '10.0.0.0/8',
              '192.168.2.0/24'
            ]
          }
        })).to eq(<<~EXPECTED)
          # generated from blocklist_cidrs_tcp.txt.erb

          # This list contains CIDRs that are blocked immediately after TCP connection setup.
          10.0.0.0/8
          192.168.2.0/24

        EXPECTED
      end
    end

    context 'when a base64-encoded, gzipped config is provided' do
      it 'has the correct contents' do
        expect(template.render({
          'ha_proxy' => {
            'cidr_blocklist_tcp' => gzip_and_b64_encode(<<~INPUT)
              10.0.0.0/8
              192.168.2.0/24
            INPUT
          }
        })).to eq(<<~EXPECTED)
          # generated from blocklist_cidrs_tcp.txt.erb

          # This list contains CIDRs that are blocked immediately after TCP connection setup.
          10.0.0.0/8
          192.168.2.0/24

        EXPECTED
      end
    end
  end

  context 'when ha_proxy.cidr_blocklist_tcp is not provided' do
    it 'contains only the default comment' do
      expect(template.render({})).to eq(<<~EXPECTED)
        # generated from blocklist_cidrs_tcp.txt.erb

        # This list contains CIDRs that are blocked immediately after TCP connection setup.

      EXPECTED
    end
  end

  context 'when ha_proxy.cidr_blocklist_tcp is an empty array' do
    it 'contains only the default comment' do
      expect(template.render({
        'ha_proxy' => {
          'cidr_blocklist_tcp' => []
        }
      })).to eq(<<~EXPECTED)
        # generated from blocklist_cidrs_tcp.txt.erb

        # This list contains CIDRs that are blocked immediately after TCP connection setup.

      EXPECTED
    end
  end
end



