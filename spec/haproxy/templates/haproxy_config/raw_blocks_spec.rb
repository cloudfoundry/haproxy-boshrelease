# frozen_string_literal: true

require 'rspec'

describe 'config/haproxy.config ha_proxy.raw_blocks' do
  let(:haproxy_conf) do
    parse_haproxy_config(template.render({ 'ha_proxy' => properties }))
  end

  context 'when multiline configurations are provided for global, defaults and some raw blocks with ids' do
    let(:properties) do
      {
        'config_mode' => 'raw_blocks_only',
        'raw_blocks' => {
          'global' => "line 1\nline 2\nline 3",
          'defaults' => ['line 1', 'line 2', 'line 3'],
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
      expect(haproxy_conf['global']).to eq(expected_block_content)
      expect(haproxy_conf['defaults']).to eq(expected_block_content)
      expect(haproxy_conf['some raw-block-1']).to eq(expected_block_content)
      expect(haproxy_conf['some raw-block-2']).to eq(expected_block_content)
      expect(haproxy_conf['some raw-block-3']).to eq(expected_block_content)
    end
  end

  context 'when there are many types of raw blocks, ha_proxy.config_mode=raw_blocks_only' do
    let(:properties) do
      {
        'config_mode' => 'raw_blocks_only',
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
          'defaults' => 'test',
          'global' => 'test'
        }
      }
    end

    it 'return only raw blocks and arranges them in the correct order' do
      raw_keys = haproxy_conf.keys
      expect(raw_keys).to eq(['global', 'defaults',
                              'listen raw-test', 'frontend raw-test', 'backend raw-test',
                              'resolvers raw-test', 'peers raw-test', 'mailers raw-test',
                              'unknown raw-test-1', 'unknown raw-test-2'])
    end
  end

  context 'when there are many types of raw blocks, classic config mode' do
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
          'listen' => { 'raw-test' => 'test' }
        }
      }
    end

    it 'return static block and then raw blocks arranged in the correct order' do
      raw_keys = haproxy_conf.keys
      expect(raw_keys).to eq(['global', 'defaults', 'frontend http-in', 'backend http-routers-http1',
                              'listen raw-test', 'frontend raw-test', 'backend raw-test',
                              'resolvers raw-test', 'peers raw-test', 'mailers raw-test',
                              'unknown raw-test-1', 'unknown raw-test-2'])
    end
  end

end
