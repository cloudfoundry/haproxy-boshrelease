# frozen_string_literal: true

require 'rspec'
require 'bosh/template/test'
require 'json'
require 'yaml'

describe 'config/bpm.yml' do
  let(:template) { haproxy_job.template('config/bpm.yml') }

  it 'has the correct contents' do
    bpm_yaml = template.render({
      'ha_proxy' => {
        'max_open_files' => 123
      }
    })

    expect(bpm_yaml).to eq(<<~EXPECTED)
      processes:
        - name: haproxy
          executable: /var/vcap/jobs/haproxy/bin/haproxy_wrapper
          additional_volumes:
            - path: /var/vcap/jobs/haproxy/config/cidrs
              writable: true
            - path: /var/vcap/jobs/haproxy/config/ssl
              writable: true
            - path: /var/vcap/sys/run/haproxy
              writable: true

          unsafe:
            unrestricted_volumes: []

          limits:
            open_files: 123
          capabilities:
            - NET_BIND_SERVICE
    EXPECTED
  end

  context 'when ha_proxy.syslog_server with a path is provided' do
    it 'grants BPM access to the syslog server path' do
      bpm_yaml = template.render({
        'ha_proxy' => {
          'max_open_files' => 123,
          'syslog_server' => '/syslog/server'
        }
      })

      expect(bpm_yaml).to eq(<<~EXPECTED)
        processes:
          - name: haproxy
            executable: /var/vcap/jobs/haproxy/bin/haproxy_wrapper
            additional_volumes:
              - path: /var/vcap/jobs/haproxy/config/cidrs
                writable: true
              - path: /var/vcap/jobs/haproxy/config/ssl
                writable: true
              - path: /var/vcap/sys/run/haproxy
                writable: true

            unsafe:
              unrestricted_volumes: [{"path":"/syslog/server"}]

            limits:
              open_files: 123
            capabilities:
              - NET_BIND_SERVICE
      EXPECTED
    end
  end

  context 'when ha_proxy.additional_unrestricted_volumes are provided' do
    it 'grants BPM access to the volumes' do
      bpm_yaml = template.render({
        'ha_proxy' => {
          'max_open_files' => 123,
          'additional_unrestricted_volumes' => [
            # See following for format
            # https://github.com/cloudfoundry/bpm-release/blob/master/docs/config.md
            {
              'path' => '/my-volume',
              'writeable' => false
            },
            {
              'path' => '/my-volume',
              'mount_only' => true
            }
          ]
        }
      })

      expect(bpm_yaml).to eq(<<~EXPECTED)
        processes:
          - name: haproxy
            executable: /var/vcap/jobs/haproxy/bin/haproxy_wrapper
            additional_volumes:
              - path: /var/vcap/jobs/haproxy/config/cidrs
                writable: true
              - path: /var/vcap/jobs/haproxy/config/ssl
                writable: true
              - path: /var/vcap/sys/run/haproxy
                writable: true

            unsafe:
              unrestricted_volumes: [{"path":"/my-volume","writeable":false},{"path":"/my-volume","mount_only":true}]

            limits:
              open_files: 123
            capabilities:
              - NET_BIND_SERVICE
      EXPECTED
    end
  end
end
