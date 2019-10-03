# New Features

- The `hatop` utility has been added to haproxy-boshrelease to assist in haproxy troubleshooting
  http://feurix.org/projects/hatop/ Kudos to @jhunt and the [Genesis Community](https://github.com/genesis-community) for making this possible!
- @Scoobed added support for specifying additional filesystem paths to make available to the HAProxy
  process via BPM's [unrestricted volumes list](https://github.com/cloudfoundry/bpm-release/blob/master/docs/config.md#unsafe-schema). 
  This is particularly helpful when integrating LUA scripts from other BOSH releases. The 
  `ha_proxy.additional_unrestricted_volumes` will allow this, and uses the same syntax as BPM.

# Acknowledgements

Thanks @jhunt and @Scoobed!
