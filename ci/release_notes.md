# Improvements

There is now a more flexible option for using ACLs to restrict access to
requests, using the `ha_proxy.http_request_deny_conditions` property:

```
 example:
   http_request_deny_conditions:
   - condition:
     - acl_name: block_host
       acl_rule: "hdr_beg(host) -i login"
     - acl_name: block_reset_password_url
       acl_rule: "path_beg,url_dec -m beg -i /reset_password"
 ```

 # Acknowledgements

 Thanks @stefanlay for providing this feature!
