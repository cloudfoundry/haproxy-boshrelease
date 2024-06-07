# frozen_string_literal: true

require 'rspec'

describe 'HAProxy feature version spec' do
  let(:pre_start_template) { haproxy_job.template('bin/pre-start') }
  let(:haproxy_wrapper_template) { haproxy_job.template('bin/haproxy_wrapper') }

  describe 'ha_proxy.haproxy_feature_version' do
    some_feature_version = 'X.Y'
    context 'when is provided' do
      it 'pre_start template HAPROXY_FEATURE_VERSION variable is rendered' do
        pre_start = pre_start_template.render(
          {
            'ha_proxy' => {
              'haproxy_feature_version' => some_feature_version
            }
          }
        )
        expect(pre_start).to include("HAPROXY_FEATURE_VERSION='#{some_feature_version}'")
      end
    end

    it 'haproxy_wrapper template HAPROXY_FEATURE_VERSION variable is rendered' do
      some_feature_version = 'X.Y'
      haproxy_wrapper = haproxy_wrapper_template.render(
        {
          'ha_proxy' => {
            'haproxy_feature_version' => some_feature_version
          }
        }
      )
      expect(haproxy_wrapper).to include("HAPROXY_FEATURE_VERSION='#{some_feature_version}'")
    end
  end
end
