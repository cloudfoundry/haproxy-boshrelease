# Fixes
- `X-SSL-*` headers that could previously contain non-standard ASCII characters are now base64 encoded. These include `X-SSL-Client-Subject-CN`, `X-SSL-Client-Subject-DN`, `X-SSL-Client-Issuer-DN`. Client certificates may contain non ASCII characters and when these were added to the `X-SSL-*` headers it was breaking some backend server implementation that have strict checks for HTTP header RFC compliance. Note this is a breaking change.

