# frozen_string_literal: true

require 'rspec'

describe 'config/expect_proxy_cidrs.txt' do
  let(:template) { haproxy_job.template('config/expect_proxy_cidrs.txt') }

  context 'when ha_proxy.expect_proxy_cidrs' do
    context 'when a list of cidrs is provided' do
      it 'has the correct contents' do
        expect(template.render({
          'ha_proxy' => {
            'expect_proxy_cidrs' => ['10.5.6.7/27',
                                     '2001:db8::/32']
          }
        })).to eq(<<~EXPECTED)
          # generated from expect_proxy_cidrs.txt.erb

          # BEGIN expect_proxy_cidrs
          10.5.6.7/27
          2001:db8::/32
          # END expect_proxy_cidrs
        EXPECTED
      end
    end
  end

  context 'when ha_proxy.expect_proxy_cidrs is not provided' do
    it 'is empty' do
      expect(template.render({})).to be_a_blank_string
    end
  end
end
