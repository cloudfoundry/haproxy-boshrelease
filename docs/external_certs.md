# Using HAProxy with additional External Certificates

By default, the HAproxy BOSH manifest contains all certificates to be used during runtime.
The way to pass the certificates can be either via the `ha_proxy.ssl_pem` property that sets one chain for
the hostname HAproxy is running on. Or they can be passed via the `ha_proxy.crt_list` property, which is essentially
a list of `ssl_pem` properties that allows to configure multiple entries for different hostnames using SNI.

## What are External Certificates and why are they needed?

If you are planning to use more than one certificate on your HAproxy you are most likely going to use the `ha_proxy.crt_list`
property. The main use-case for this property is to register different trust configurations for different hosts.
For example, if your HAproxy services both the secure.example.com and www.example.com hosts, they both might have different
requirements towards security. One could be using mTLS and a more secure certificate than the other or they could be using different CAs.

The problems start when you are using a very large `ha_proxy.crt_list` with dozens or even hundreds of entries while using BOSH to deploy them.
The way BOSH works is that all certificates will become part of the manifest during rendering and those certificates will then be extracted
from the manifest and onto the HAproxy disk during deployment. If the manifest becomes very large (> 20M) the time BOSH needs to render and deploy increases significantly. At the same time, providing your customers the capability to register custom domains and certificates tends to be a very dynamic process, i.e. you never know when a customer will register a domain and upload a certificate to deploy but you will want to deploy the new certificate as quickly as possible so the customer can use it right away. Using the given way, you'll end up deploying HAproxy all the time. The major downside of this is that every time you deploy HAproxy, there will be a brief moment where the old process exits and the new process has not yet started. This will drop all existing connections to HAproxy and any client connected at that moment will receive a disruption.

How can this dilemma be solved? External certificates to the rescue!

## How does it all work?

The HAproxy BOSH release provides an additional property `ha_proxy.ext_crt_list` that enables the use of a second source of certificates.
When used, HAproxy will expect an additional `crt-list` file to be present in a specific folder (by default: `/var/vcap/jobs/haproxy/config/ssl/ext`).
If the file exists its contents will be merged with the existing certificates from the manifest before HAproxy is started.
Since the list of certificates is now provided by two decoupled sources, those sources need to be synchronized in order to avoid starting HAproxy with an incomplete set of certificates. During startup, HAproxy will wait for the second `crt-list` file to appear. This allows an external service (e.g. another BOSH release) to generate the file and place it in the directory where it is expected.

At runtime, when a new certificate needs to be added, the external service can simply update the second `crt-list` file and trigger a [hitless reload](https://www.haproxy.com/blog/hitless-reloads-with-haproxy-howto/) of HAproxy using the `/var/vcap/jobs/haproxy/bin/reload` command. No connections will be dropped.

Depending on your configuration, HAproxy will refuse to start without external certificates or it will continue without them after a timeout.

## Configuring HAproxy to use External Certificates

The feature is controlled by these properties:
```
ha_proxy.ext_crt_list:
    A flag denoting the use of additional certificates from external sources.
    If set to true the contents of an external crt-list file located at `ha_proxy.ext_crt_list_file` are
    added to the crt-list described by the `ha_proxy.crt_list` property.
  default: false
ha_proxy.ext_crt_list_file:
    The location from which to load additional external certificates list
  default: "/var/vcap/jobs/haproxy/config/ssl/ext/crt-list"
ha_proxy.ext_crt_list_timeout:
    Timeout (in seconds) to wait for the external certificates list located at `ha_proxy.ext_crt_list_file` to appear during HAproxy startup
  default: 60
ha_proxy.ext_crt_list_policy:
    What to do if the external certificates list located at `ha_proxy.ext_crt_list_file` does not appear within the time
    denoted by `ha_proxy.ext_crt_list_timeout`. Set to either 'fail' (HAproxy will not start) or 'continue' (HAproxy will start without external certificates)
  default: "fail"
```
