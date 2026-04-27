# Enabling Core Dumps for HAProxy

When debugging crashes or unexpected behavior in HAProxy, it can be useful to enable core dumps for post-mortem analysis.

## Required Changes

Enabling core dumps requires a few modifications to the BOSH release.

Depending on the BPM (BOSH Process Manager) version, BPM needs to be either configured or disabled:

### 1a. Disable BPM (BPM <= 1.4.29)

BPM <= 1.4.29 restricts the process environment in ways that prevent core dumps from being written. To work around this, the monit configuration must be changed to manage HAProxy directly via `haproxy_wrapper` instead of BPM:

- **Start program** in `jobs/haproxy/monit`: Change from `/var/vcap/jobs/bpm/bin/bpm start haproxy` to `/var/vcap/jobs/haproxy/bin/haproxy_wrapper`
- **Stop program** in `jobs/haproxy/monit`: Change from `/var/vcap/jobs/bpm/bin/bpm stop haproxy` to `/bin/bash -c 'kill $(cat /var/vcap/sys/run/haproxy/haproxy.pid)'`
- **PID file** in `jobs/haproxy/monit`: Change from `/var/vcap/sys/run/bpm/haproxy/haproxy.pid` to `/var/vcap/sys/run/haproxy/haproxy.pid`
- **PID file** in `jobs/haproxy/templates/drain.erb`: Change the `pidfile=` variable from `/var/vcap/sys/run/bpm/haproxy/haproxy.pid` to `/var/vcap/sys/run/haproxy/haproxy.pid`
- **PID file** in `jobs/haproxy/templates/reload.erb`: Change the `pidfile=` variable from `/var/vcap/sys/run/bpm/haproxy/haproxy.pid` to `/var/vcap/sys/run/haproxy/haproxy.pid`

### 1b. Set BPM core_file_size limit (BPM > 1.4.29)

BPM > 1.4.29 allows setting the core dump file size limit. In `jobs/haproxy/templates/bpm.yml`, add `core_file_size` to the existing `limits:` block (alongside `open_files`):

```yaml
    limits:
      open_files: <%= p("ha_proxy.max_open_files") %>
      core_file_size: 1073741824
```

### 2. Configure the HAProxy wrapper script

The following must be added to `haproxy_wrapper.erb` before HAProxy is started:

```bash
ulimit -c unlimited      # Allow unlimited core dump file size
ulimit -n 256000         # Ensure sufficient file descriptors
echo /var/vcap/data/haproxy/core.%e.%p.%t > /proc/sys/kernel/core_pattern
```

The core pattern places dumps in `/var/vcap/data/haproxy/` with the filename format `core.<executable>.<pid>.<timestamp>`.

### 3. Enable `set-dumpable` in HAProxy config

Add the `set-dumpable` directive to the `global` section in `haproxy.config.erb`. This is required because HAProxy drops privileges to the `vcap` user after startup, which by default causes the kernel to disable core dumps. `set-dumpable` calls `prctl(PR_SET_DUMPABLE, 1)` to re-enable them.

## Analyzing Core Dumps

Core dump files are written to `/var/vcap/data/haproxy/`.

To analyze a core dump, use `gdb` with the HAProxy binary and the core file:

```bash
gdb /var/vcap/packages/haproxy/bin/haproxy /var/vcap/data/haproxy/core.<executable>.<pid>.<timestamp>
```

Useful GDB commands once loaded:

```
bt              # Print backtrace of the crashing thread
bt full         # Print backtrace with local variables
info threads    # List all threads
thread <N>      # Switch to thread N
thread apply all bt   # Print backtraces for all threads
```

> **Note:** For meaningful stack traces, HAProxy should be compiled with debug symbols. To enable this, add `DEBUG_CFLAGS="-g"` to the `make` command in `packages/haproxy/packaging`. Without debug symbols, the backtrace will show only addresses without function names.