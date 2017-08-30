# Bug Fixes

- Resolved an issue where certs specified using the new `cert_chain`
  and `private_key` would result in an invalid cert file, if a newline
  wasn't provided in the `cert_chain` value. Leading + trailing whitespace
  are now removed, and the newline is added for you.


# Acknowledgements

Thanks @ryanmoran for the fix!
