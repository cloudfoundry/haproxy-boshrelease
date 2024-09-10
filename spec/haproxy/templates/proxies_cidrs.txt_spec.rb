# frozen_string_literal: true

require 'rspec'

describe 'config/proxies_cidrs.txt' do
  let(:template) { haproxy_job.template('config/proxies_cidrs.txt') }


  context 'when ha_proxy.expect_proxy is provided ' do
    context 'when an array of cidrs is provided' do
      it 'has the correct contents' do
        expect(template.render({
          'ha_proxy' => {
            'expect_proxy' => [
              '10.5.6.7/27',
              '2001:db8::/32'
            ]
          }
        })).to eq(<<~EXPECTED)
          # generated from proxies_cidrs.txt.erb

          # BEGIN proxies cidrs
          # detected cidrs provided as array in cleartext format
            10.5.6.7/27
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
