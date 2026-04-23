# Enabling Core Dumps for HAProxy

When debugging crashes or unexpected behavior in HAProxy, it can be useful to enable core dumps for post-mortem analysis.

## Required Changes

Enabling core dumps requires the following modifications to the BOSH release:

### 1. Disable BPM

BPM (BOSH Process Manager) restricts the process environment in ways that prevent core dumps from being written. To work around this, the monit configuration must be changed to manage HAProxy directly via `haproxy_wrapper` instead of BPM:

- **Start program**: `/var/vcap/jobs/haproxy/bin/haproxy_wrapper` (instead of `/var/vcap/jobs/bpm/bin/bpm start haproxy`)
- **Stop program**: `kill $(cat /var/vcap/sys/run/haproxy/haproxy.pid)` (instead of `bpm stop`)
- **PID file**: `/var/vcap/sys/run/haproxy/haproxy.pid` (instead of `/var/vcap/sys/run/bpm/haproxy/haproxy.pid`)

The PID file path must also be updated in `drain.erb` and `reload.erb` to match.

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