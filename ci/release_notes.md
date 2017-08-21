# New Features

- `ssl_pem` now has additional support for supplying custom cert chains associated with each certificate.
  It can still be specified as a single block of text, and array of private keys. The newly supported format
  looks something like this:

  ```
  ssl_pem:
  - private_key: |
      -----BEGIN RSA PRIVATE KEY-----
      key here
      -----END RSA PRIVATE KEY-----
  - cert_chain: |
      -----BEGIN CERTIFICATE-----
      cert here
      -----END CERTIFICATE-----
      -----BEGIN CERTIFICATE-----
      cert here
      -----END CERTIFICATE-----
  ```

# Acknowledgements

Thanks @Nino-K and @flawedmatrix for the new feature!
