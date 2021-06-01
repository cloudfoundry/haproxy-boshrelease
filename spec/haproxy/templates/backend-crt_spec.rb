# frozen_string_literal: true

require 'rspec'

describe 'config/backend-crt.pem' do
  let(:template) { haproxy_job.template('config/backend-crt.pem') }

  describe 'ha_proxy.backend_crt' do
    it 'has the correct contents' do
      expect(template.render({
        'ha_proxy' => {
          'backend_crt' => 'foobarbaz'
        }
      })).to eq("\nfoobarbaz\n\n")
    end

    context 'when ha_proxy.backend_crt is not provided' do
      it 'is empty' do
        expect(template.render({})).to be_a_blank_string
      end
    end
  end
end
