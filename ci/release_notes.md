# New Features
- `forwarded_client_cert` property now additionally controls a `X-Forwarded-Client-Chain` header. This contains the CA certificate chain sent by the client in binary DER format (Base64 encoded). Note that multiple DER-encoded certificates are concatenated before being base64-encoded.

# Acknowledgements

Thanks @peterellisjones
