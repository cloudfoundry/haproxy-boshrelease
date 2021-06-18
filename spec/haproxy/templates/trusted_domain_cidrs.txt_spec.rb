# frozen_string_literal: true

require 'rspec'

describe 'config/trusted_domain_cidrs.txt' do
  let(:template) { haproxy_job.template('config/trusted_domain_cidrs.txt') }

  describe 'ha_proxy.trusted_domain_cidrs' do
    context 'when a space-separated list of cidrs is provided' do
      it 'has the correct contents' do
        expect(template.render({
          'ha_proxy' => {
            'trusted_domain_cidrs' => '10.0.0.0/8 192.168.2.0/24'
          }
        })).to eq(<<~EXPECTED)
          # generated from trusted_domain_cidrs.txt.erb

          # BEGIN trusted_domain cidrs
          10.0.0.0/8
          192.168.2.0/24

          # END trusted_domain cidrs

        EXPECTED
      end
    end

    context 'when a newline-separated, gzipped, base64-encoded list of cidrs is provided' do
      it 'has the correct contents' do
        expect(template.render({
          'ha_proxy' => {
            'trusted_domain_cidrs' => gzip_and_b64_encode("10.0.0.0/8\n192.168.2.0/24")
          }
        })).to eq(<<~EXPECTED)
          # generated from trusted_domain_cidrs.txt.erb

          # BEGIN trusted_domain cidrs
          10.0.0.0/8
          192.168.2.0/24
          # END trusted_domain cidrs

        EXPECTED
      end
    end

    context 'when ha_proxy.trusted_domain_cidrs is not provided' do
      it 'is empty' do
        expect(template.render({})).to be_a_blank_string
      end
    end
  end
end
