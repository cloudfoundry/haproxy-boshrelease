# rubocop: disable LineLength
# rubocop: disable BlockLength
require 'rspec'
require 'bosh/template/test'
require 'yaml'
require 'json'
require 'haproxy-tools'
require 'pry'
require 'tempfile'

describe 'haproxy' do
  let(:release_path) { File.join(File.dirname(__FILE__), '..') }
  let(:release) { Bosh::Template::Test::ReleaseDir.new(release_path) }
  let(:job) { release.job('haproxy') }

  let(:default_manifest_properties) do
    {
      'ha_proxy' => {
        'threads' => 1,
        'nbproc' => 1,
        'nbthread' => 1,
        'syslog_server' => 'stdout',
        'log_level' => 'info',
        'buffer_size_bytes' => '16384',
        'internal_only_domains' => [],
        'trusted_domain_cidrs' => '0.0.0.0/32',
        'strict_sni' => false,
        'ssl_pem' => nil,
        'crt_list' => nil,
        'reload_hard_stop_after' => '5m',
        'reload_max_instances' => 4,
        'enable_health_check_http' => false,
        'health_check_port' => '8080',
        'disable_http' => false,
        'enable_4443' => false,
        'https_redirect_domains' => [],
        'https_redirect_all' => false,
        'ssl_ciphers' => 'ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES256-SHA:ECDHE-ECDSA-DES-CBC3-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:DES-CBC3-SHA:!DSS',
        'hsts_enable' => false,
        'hsts_max_age' => '31536000',
        'hsts_include_subdomains' => false,
        'hsts_preload' => false,
        'default_dh_param' => 2048,
        'disable_tls_tickets' => false,
        'disable_tls_10' => false,
        'disable_tls_11' => false,
        'connect_timeout' => 5,
        'client_timeout' => 30,
        'server_timeout' => 30,
        'websocket_timeout' => 3600,
        'keepalive_timeout' => 6,
        'request_timeout' => 5,
        'queue_timeout' => 30,
        'stats_enable' => false,
        'stats_bind' => '*:9000',
        'stats_uri' => 'haproxy_stats',
        'trusted_stats_cidrs' => '0.0.0.0/32',
        'backend_servers' => [],
        'backend_ssl' => 'off',
        'backend_port' => '80',
        'compress_types' => '',
        'routed_backend_servers' => {},
        'client_cert' => false,
        'forwarded_client_cert' => 'sanitize_set',
        'tcp' => [],
        'dns_hold' => '10s',
        'resolve_retry_timeout' => '1s',
        'resolve_retries' => 3,
        'accept_proxy' => false,
        'disable_tcp_accept_proxy' => false,
        'binding_ip' => '',
        'v4v6' => false,
        'cidr_blacklist' => '~',
        'cidr_whitelist' => '~',
        'block_all' => false,
        'tcp_routing' => {
          'port_range' => '1024-1123'
        },
        'lua_scripts' => [],
        'backend_use_http_health' => false,
        'backend_http_health_uri' => '/health',
        'backend_http_health_port' => 8080,
        'max_open_files' => '256000',
        'max_connections' => '64000',
        'drain_enable' => false,
        'drain_timeout' => 30,
        'drain_frontend_grace_time' => 0,
        'backend_prefer_local_az' => false
      }
    }
  end

def dumpConfig(src, dst)
  file = File.open(src)
  file_content = file.read
  File.open(dst, "w") { |f| f.write file_content }
  file.close()
end

  describe 'config/haproxy.config' do
    let(:template) { job.template('config/haproxy.config') }
    let(:config_file) { Tempfile.new(['config', '.cfg']) }
    let(:manifest_properties) { default_manifest_properties }

    before :each do
      rendered_template = template.render(manifest_properties)
      config_file.write(rendered_template)
      config_file.rewind
    end

    after do
      config_file.close
      config_file.unlink
    end

    describe 'when given a valid set of properties' do
      it 'renders a valid haproxy template' do
        expect{HAProxy::Config.parse_file(config_file.path)}.to_not raise_error
      end
    end

    describe 'when custom_http_error_files are provided' do
      let(:manifest_properties) do
        default_manifest_properties['ha_proxy']['custom_http_error_files'] = {
            "503" => "content of errorfile 503",
            "403" => "content of errorfile 403"
        }
        default_manifest_properties
      end

      it 'set all errorfiles with theirs error status and location' do
        rendered_hash = HAProxy::Config.parse_file(config_file.path)
        expect(rendered_hash.backend('http-routers').config['errorfile 503']).to eq("/var/vcap/jobs/haproxy/errorfiles/custom503.http")
        expect(rendered_hash.backend('http-routers').config['errorfile 403']).to eq("/var/vcap/jobs/haproxy/errorfiles/custom403.http")
      end
    end

    describe 'when a tcp backend is provided' do
      tcp_backend = {
        "name" => "wss",
        "port" => 4443,
        "backend_servers" => ["10.20.10.10", "10.20.10.11"],
        "balance" => "roundrobin",
        "backend_port" => 80,
        "ssl" => true,
        "backend_ssl" => "verify",
        "backend_verifyhost" => "example.com",
        "health_check_http" => 4444
      }

      describe 'when not using tcp_link_check_port' do
        let(:manifest_properties) do
          default_manifest_properties['ha_proxy']['tcp'] = [ tcp_backend ]
          default_manifest_properties
        end

        it 'uses the backend port for health checks' do
          rendered_hash = HAProxy::Config.parse_file(config_file.path)
          expect(rendered_hash.backend('tcp-wss').servers['node0'].attributes['port']).to eq("80")
        end
      end

      describe 'when using tcp_link_check_port' do
        let(:manifest_properties) do
          default_manifest_properties['ha_proxy']['tcp'] = [ tcp_backend ]
          default_manifest_properties['ha_proxy']['tcp_link_check_port'] = 1234

          default_manifest_properties
        end
        it 'uses the tcp_link_check_port port for health checks instead' do
          rendered_hash = HAProxy::Config.parse_file(config_file.path)
          expect(rendered_hash.backend('tcp-wss').servers['node0'].attributes['port']).to eq("1234")
        end
      end
    end
  end
end
