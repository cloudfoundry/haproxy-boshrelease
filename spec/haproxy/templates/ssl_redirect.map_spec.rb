# frozen_string_literal: true

require 'rspec'

describe 'config/ssl_redirect.map' do
  let(:template) { haproxy_job.template('config/ssl_redirect.map') }

  context 'when ha_proxy.https_redirect_domains is provided' do
    it 'has the correct contents' do
      expect(template.render({
        'ha_proxy' => {
          'https_redirect_domains' => [
            'google.com',
            'bing.com'
          ]
        }
      })).to eq(<<~EXPECTED)

        google.com	true

        bing.com	true

      EXPECTED
    end
  end

  context 'when ha_proxy.https_redirect_domains is not provided' do
    it 'is empty' do
      expect(template.render({})).to be_a_blank_string
    end
  end
end
