# frozen_string_literal: true

require 'rspec'

describe 'config/haproxy.config ha_proxy.raw_blocks' do
  let(:haproxy_conf) do
    parse_haproxy_config(template.render({ 'ha_proxy' => properties }))
  end

  context 'when multiline configurations are provided for some raw blocks' do
    let(:properties) do
      {
        'raw_blocks' => {
          'some' => {
            'raw-block-1' => "line 1\nline 2\nline 3",
            'raw-block-2' => "\n\nline 1\nline 2\nline 3\n\n",
            'raw-block-3' => ['line 1', 'line 2', 'line 3']
          }
        }
      }
    end

    it 'formats the configuration as expected' do
      expected_block_content = ['line 1', 'line 2', 'line 3']
      expect(haproxy_conf['some raw-block-1']).to eq(expected_block_content)
      expect(haproxy_conf['some raw-block-2']).to eq(expected_block_content)
      expect(haproxy_conf['some raw-block-3']).to eq(expected_block_content)
    end
  end

  context 'when there are many types of raw blocks' do
    let(:properties) do
      {
        'raw_blocks' => {
          'unknown' => {
            'raw-test-1' => 'test',
            'raw-test-2' => 'test'
          },
          'mailers' => { 'raw-test' => 'test' },
          'peers' => { 'raw-test' => 'test' },
          'resolvers' => { 'raw-test' => 'test' },
          'backend' => { 'raw-test' => 'test' },
          'frontend' => { 'raw-test' => 'test' },
          'listen' => { 'raw-test' => 'test' },
          'defaults' => { '# raw-test' => 'test' },
          'global' => { '# raw-test' => 'test' }
        }
      }
    end

    it 'arranges them all in the correct order' do
      raw_keys = haproxy_conf.keys.select { |key| key.include?('raw-test') }
      expect(raw_keys).to eq(['global # raw-test', 'defaults # raw-test',
                              'listen raw-test', 'frontend raw-test', 'backend raw-test',
                              'resolvers raw-test', 'peers raw-test', 'mailers raw-test',
                              'unknown raw-test-1', 'unknown raw-test-2'])
    end
  end
end
