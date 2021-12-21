# Fixes
- We reverted the X-Forwarded-Client-Chain feature released in https://github.com/cloudfoundry/haproxy-boshrelease/releases/tag/v11.9.1
  This increased the header size of some requests which caused backend servers for users to hit header limits
