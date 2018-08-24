# New Features
- Added support for HAProxy's experimental multi-threading logic.
  Previously, this boshrelease used `ha_proxy.threads` to set the `nbproc`
  value of HAProxy, causing a multi-threaded behavior by spawning multiple
  HAProxy processes. In v1.8.x, built-in multi-threading was enabled in an
  experimental mode. This can be enabled via `ha_proxy.nbthread`. Adding multi-
  threading works in-conjunction with multi-process HAProxy, or on its own.
  To reduce confusion, the `ha_proxy.threads` property has been **deprecated,**
  but still affects the number of processes run. In the future, `ha_proxy.nbproc`
  should be used. To enable the experimental multi-threading, use `ha_proxy.nbthread`.

  Note: One of the upsides to multi-thread vs multi-process is that the threads
  are able to share memory, resulting in the need for only one stats socket/listener.
  One of the downsides is that LUA scripts are globally single-threaded, so only one
  script will run at a time, ever. HAProxy can still service requests that don't involve
  calling LUA code, but multiple calls requiring LUA will be serialized. 

# Deprecation Warning!

- `ha_proxy.threads` is hereby deprecated, and will be removed in the next major
  version of the boshrelease. It previously referred to the number of HAProxy
  processes running, and was going to be confusing with the added thread support.
  Please use `ha_proxy.nbproc` instead. 

# Acknowledgments

Thanks @teancom for all the amazing work once again!
