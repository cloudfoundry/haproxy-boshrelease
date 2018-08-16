# New Features

- Added a property to allow lua scripts to be easily loaded into the HA proxy config
  via `ha_proxy.lua_scripts`. This is a list of full paths to the lua script on disk.
  You'll want to provide those with some other boshrelease.

- Added a property for providing arbitrary frontend config to haproxy via `ha_proxy.frontend_config`.
  This applies to all of the haproxy frontends.

- Added a property for providing arbitrary global config to haproxy via `ha_proxy.global_config`.

# Acknowledgements

Thanks @teancom for helping out with the feature.
