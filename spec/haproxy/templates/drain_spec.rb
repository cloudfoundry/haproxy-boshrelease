# frozen_string_literal: true

require 'rspec'

describe 'bin/drain' do
  let(:template) { haproxy_job.template('bin/drain') }

  describe 'ha_proxy.drain_enable' do
    context 'when enabled' do
      it 'includes drain logic' do
        expect(template.render({
          'ha_proxy' => {
            'drain_enable' => true
          }
        })).to eq(<<~EXPECTED)
          #!/bin/bash
          # vim: set ft=sh

          set -e

          pidfile=/var/vcap/sys/run/bpm/haproxy/haproxy.pid
          sockfile=/var/vcap/sys/run/haproxy/stats.sock
          logfile=/var/vcap/sys/log/haproxy/drain.log

          mkdir -p "$(dirname ${logfile})"

          if [[ ! -f ${pidfile} ]]; then
            echo "$(date): pidfile does not exist" >> ${logfile}
            echo 0
            exit 0
          fi

          pid="$(cat ${pidfile})"
          if ! ps -p ${pid} >/dev/null; then
            # In case haproxy_wrapper process is stale, pid_exists will be empty,
            # the drain job should not fail
            echo "$(date): There was no process for the recorded haproxy_wrapper PID (${pid})." >> ${logfile}
            echo 0
            exit 0
          fi

          haproxy_wrapper_pid=$(pgrep -P "$pid" haproxy_wrapper)
          haproxy_master_pid=$(pgrep -P "$haproxy_wrapper_pid" -x haproxy)


          kill -USR1 "${haproxy_master_pid}"
          echo "$(date): triggering drain for process ${haproxy_master_pid}" >> ${logfile}

          echo 30
        EXPECTED
      end

      context 'when health checks are enabled' do
        it 'includes drain and grace logic' do
          expect(template.render({
            'ha_proxy' => {
              'drain_enable' => true,
              'enable_health_check_http' => true
            }
          })).to eq(<<~EXPECTED)
            #!/bin/bash
            # vim: set ft=sh

            set -e

            pidfile=/var/vcap/sys/run/bpm/haproxy/haproxy.pid
            sockfile=/var/vcap/sys/run/haproxy/stats.sock
            logfile=/var/vcap/sys/log/haproxy/drain.log

            mkdir -p "$(dirname ${logfile})"

            if [[ ! -f ${pidfile} ]]; then
              echo "$(date): pidfile does not exist" >> ${logfile}
              echo 0
              exit 0
            fi

            pid="$(cat ${pidfile})"
            if ! ps -p ${pid} >/dev/null; then
              # In case haproxy_wrapper process is stale, pid_exists will be empty,
              # the drain job should not fail
              echo "$(date): There was no process for the recorded haproxy_wrapper PID (${pid})." >> ${logfile}
              echo 0
              exit 0
            fi

            haproxy_wrapper_pid=$(pgrep -P "$pid" haproxy_wrapper)
            haproxy_master_pid=$(pgrep -P "$haproxy_wrapper_pid" -x haproxy)

            echo "disable frontend health_check_http_url" | /usr/local/bin/socat stdio unix-connect:${sockfile}
            echo "$(date): triggering grace period for process ${haproxy_master_pid}" >> ${logfile}
            sleep 0
            kill -USR1 "${haproxy_master_pid}"
            echo "$(date): triggering drain for process ${haproxy_master_pid}" >> ${logfile}

            echo 30
          EXPECTED
        end
      end

      context 'when a custom ha_proxy.drain_timeout is provided' do
        it 'overrides the default timeout' do
          expect(template.render({
            'ha_proxy' => {
              'drain_enable' => true,
              'drain_timeout' => 123
            }
          }).split(/\n/).last).to eq('echo 123')
        end
      end
    end

    context 'when disabled' do
      it 'does not include drain logic' do
        expect(template.render({
          'ha_proxy' => {
            'drain_enable' => false
          }
        })).to eq(<<~EXPECTED)
          #!/bin/bash
          # vim: set ft=sh

          set -e

          pidfile=/var/vcap/sys/run/bpm/haproxy/haproxy.pid
          sockfile=/var/vcap/sys/run/haproxy/stats.sock
          logfile=/var/vcap/sys/log/haproxy/drain.log

          echo "drain is disabled" >> ${logfile}
          echo 0
          exit 0
        EXPECTED
      end
    end
  end
end
