# frozen_string_literal: true

require 'rspec'

describe 'config/proxies_cidrs.txt' do
  let(:template) { haproxy_job.template('config/proxies_cidrs.txt') }

  describe 'ha_proxy.proxies_cidrs' do
    context 'when a space-separated list of cidrs is provided' do
      it 'has the correct contents' do
        expect(template.render({
          'ha_proxy' => {
            'proxies_cidrs' => '10.0.1.32/27
                                2001:db8::/32
          }
        })).to eq(<<~EXPECTED)
          # generated from proxies_cidrs.txt.erb

          # BEGIN proxies cidrs
            10.0.1.32/27
            2001:db8::/32
          # END proxies cidrs

        EXPECTED
      end
    end

    context 'when a newline-separated, gzipped, base64-encoded list of cidrs is provided' do
      it 'has the correct contents' do
        expect(template.render({
          'ha_proxy' => {
            'proxies_cidrs' => gzip_and_b64_encode("10.0.1.32/27\n2001:db8::/32")
          }
        })).to eq(<<~EXPECTED)
          # generated from proxies_cidrs.txt.erb

          # BEGIN proxies cidrs
          10.0.1.32/27
          2001:db8::/32
          # END proxies cidrs

        EXPECTED
      end
    end

    context 'when ha_proxy.proxies_cidrs is not provided' do
      it 'is empty' do
        expect(template.render({})).to be_a_blank_string
      end
    end
  end
end
