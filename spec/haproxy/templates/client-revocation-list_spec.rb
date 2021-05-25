# frozen_string_literal: true

require 'rspec'

describe 'config/client-revocation-list.pem' do
  let(:template) { haproxy_job.template('config/client-revocation-list.pem') }

  describe 'ha_proxy.client_revocation_list' do
    it 'has the correct contents' do
      expect(template.render({
        'ha_proxy' => {
          'client_revocation_list' => 'foobarbaz'
        }
      })).to eq("\nfoobarbaz\n\n")
    end

    context 'when ha_proxy.client_revocation_list is not provided' do
      it 'is empty' do
        expect(template.render({})).to be_a_blank_string
      end
    end
  end
end
