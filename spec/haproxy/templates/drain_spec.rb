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
          logfile=/var/vcap/sys/log/haproxy/drain.log

          mkdir -p "$(dirname ${logfile})"

          if [[ ! -f ${pidfile} ]]; then
            echo "$(date): pidfile does not exist" >> ${logfile}
            echo 0
            exit 0
          fi

          pid="$(cat ${pidfile})"

          haproxy_pids=$(pgrep -P $pid -l | grep 'haproxy$' | awk '{print $1}')

          for haproxy_pid in $haproxy_pids; do
            kill -USR1 "${haproxy_pid}"
            echo "$(date): triggering drain for process ${haproxy_pid}" >> ${logfile}
          done

          echo 30
        EXPECTED
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
          logfile=/var/vcap/sys/log/haproxy/drain.log

          echo "drain is disabled" >> ${logfile}
          echo 0
          exit 0
        EXPECTED
      end
    end
  end
end
