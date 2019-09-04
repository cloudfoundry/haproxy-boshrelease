# Fixes

- BPM now whitelists the filepath used for HAProxy's logging device, rather
  than hardcoding /dev/log. If you use a custom logging socket, this tells BPM
  to allow HAProxy to access the root filesystem for it.

# Acknowledgments

Thanks go to @h0nlg for the PR!
