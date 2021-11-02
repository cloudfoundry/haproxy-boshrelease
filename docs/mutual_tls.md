[haproxy-boshrelease][1] has two different features related to Mutual TLS -
[authenticating itself][2] with a set of backend servers, and [passing through][3]
end-user client certificates to backend apps. Both features can be used
on their own, or in tandem, depending on the requirements of the infrastructure
deployed.

## Using HAProxy in front of Backends that require Mutual TLS

If HAProxy is placed in front of backend servers that require
Client SSL Certificates/Mutual TLS, you will want to ensure the
following property is set:

```
properties:
  haproxy:
    backend_crt: |
      ----- BEGIN CERTIFICATE -----
      YOUR CERT PEM HERE
      ----- END CERTIFICATE -----
      ----- BEGIN RSA PRIVATE KEY -----
      YOUR KEY HERE
      ----- END RSA PRIVATE KEY -----
```

If you wish to have HAProxy perform SSL verification on the backend
it's connecting to, add the following properties to the mix:

```
properties:
  haproxy:
    backend_ssl: verify
    backend_ca: |
      ----- BEGIN CERTIFICATE -----
      CA Certificate for validating backend certs
      ----- END CERTIFICATE -----
    backend_ssl_verifyhost: # Omit these if you only want to validate that the CA signed the backend
    - backend-host.com      # server's cert, and not check hostnames + certificate Subjects
```

## Configuring HAProxy to Pass Client Certificates to Apps

HAProxy can be configured to pass client certificates on to apps requiring them on the backend.
This does not enforce mutual TLS at the HAPrcxy level, nor does it enable it at the app level.
Instead, it allows for HAProxy to accept client certificates optionally, which are then passed to
backend apps via the `X-Forwarded-Client-Cert` HTTP Header. Apps must then be written to inspect that
header, and perform a manual certificate validation based on the value of the `X-Forwarded-Client-Cert`
header.

To enable the mutual TLS passthrough, add the following property to your manifest:

```
properties:
  haproxy:
    client_cert: true
```

The `haproxy.client_ca_file` can be optionally supplied for client cert validation, if custom CAs
were used to issue the client certs.

`ha_proxy.client_revocation_list` is an optional list of CRLs for HAProxy to use when validating
certs, to ensure client certs have not been revoked.

If HAProxy has trouble validating a client cert, it will refuse to serve the request, unless
that specific error has been ignored. This can be configured via `ha_proxy.client_cert_ignore_err`
An exhaustive list of these error codes can be found here][4]

[1]: https://github.com/cloudfoundry/haproxy-boshrelease
[2]: #using-haproxy-in-front-of-backends-that-require-mutual-tls
[3]: #configuring-haproxy-to-pass-client-certificates-to-apps
[4]: https://wiki.openssl.org/index.php/Manual:Verify(1)
