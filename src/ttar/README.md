ttar - Tiny Text Archives
=========================

> **Attribution:** `ttar` was written by **James Hunt** and is vendored into
> haproxy-boshrelease from [github.com/jhunt/ttar](https://github.com/jhunt/ttar)
> (previously a git submodule). It is licensed under the **MIT License,
> Copyright (c) 2017 James Hunt** — see the bundled [LICENSE](./LICENSE). The script
> itself is byte-identical to upstream `master`.

`ttar` is a small utility that reads specially crafted "text
archives" which contain the smashed together contents of other
files, at different paths.

Each file is preceded by a file header that looks like this:

```
========================================= [<mode>] <file>
```

At least three equal signs must be present.  More can be provided
if it makes the file easier to read.

The `<mode>` parameter is optional.  If present, the file will be
chmoded to that (octal) mode.

The `<file>` parameter is required, and must be an absolute path
starting with '/'.

But Why?
--------

Seriously. Why do this?

I needed to be able to use a single ERB template in a
[BOSH][bosh] release, but somehow generate an arbitrary number of
files based on configuration.  An oddly specific problem, that
demanded a small, oddly-specific program.

Example
-------

Here's a full example:

```
=================== /etc/named/10.in-addr.arpa
$TTL 1h
$ORIGIN 10.in-addr.arpa.
@ IN SOA foo.bl. hostmaster.foo.bl. (
           2015082504  ; serial
           15m         ; slaves should check back with us every 15min
           20          ; slaves should retry (on failure) after 20sec
           4h          ; slaves stop being authoritative after 4hr without updates
           1h          ; other NSes should cache our results for 1h
         )

        IN NS ns1.foo.bl.
        IN NS ns2.foo.bl.

11.0.0  IN PTR ns1.foo.bl.
12.0.0  IN PTR ns2.foo.bl.
42.0.0  IN PTR bar.foo.bl.
=================== /etc/named/foo.bl.db
$TTL 1h
$ORIGIN foo.bl.
@ IN SOA foo.bl. hostmaster.foo.bl. (
           2015082505  ; serial
           15m         ; slaves should check back with us every 15min
           20          ; slaves should retry (on failure) after 20sec
           4h          ; slaves stop being authoritative after 4hr without updates
           1h          ; other NSes should cache our results for 1h
         )

       IN NS ns1.foo.bl.
       IN NS ns2.foo.bl.

       IN A 10.0.0.42 ; bar
bar    IN A 10.0.0.42
```

[bosh]: https://bosh.io
