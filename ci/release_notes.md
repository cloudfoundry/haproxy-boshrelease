# Fixes
- Wait for the main HAProxy process in daemon mode. This fixes monit not restarting crashed HAproxy processes.
- Resolve the null bytes in log file after rotation. This fixes issue #284

# Acknowledgements

Thanks @peanball for the pid wait PR!
Thanks @mariash for the null byte fix!
