# frozen_string_literal: true

require 'rspec'

describe 'bin/pre-start' do
  let(:template) { haproxy_job.template('bin/pre-start') }

  describe 'ha_proxy.pre_start_script' do
    context 'when not provided by default' do
      it 'does not include script lines' do
        pre_start = template.render(
          {
            'ha_proxy' => {}
          }
        )
        expect(pre_start).not_to include('# ha_proxy.pre_start_script {{{')
        expect(pre_start).not_to include('pre-start-script-line')
      end
    end

    context 'when provided' do
      it 'includes script lines' do
        pre_start = template.render(
          {
            'ha_proxy' => {
              'pre_start_script' => "pre-start-script-line1\npre-start-script-line2"
            }
          }
        )
        expect(pre_start).to include('# ha_proxy.pre_start_script {{{')
        expect(pre_start).to include('pre-start-script-line1')
        expect(pre_start).to include('pre-start-script-line2')
      end
    end
  end
end
