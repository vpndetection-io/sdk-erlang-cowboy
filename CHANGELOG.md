# Changelog

What each release changed for you, newest first. Each line is a commit's summary, linked to its full description and diff. Releases before 2.0.4 are described by their release commits.

## 2.1.5 - 2026-10-26

### Fixes

- Require vpndetection 3.10.1: re-pinned to the 2026.10.25 spec ([`1748e18`](https://github.com/vpndetection-io/sdk-erlang-cowboy/commit/1748e18857fa159041cf49b87d0bfef9d0aa2102))

## 2.1.4 - 2026-10-24

### Fixes

- Require vpndetection 3.10.0: a stricter answer reader and oauth_register ([`53d9c70`](https://github.com/vpndetection-io/sdk-erlang-cowboy/commit/53d9c70bc471b906b98f8a4e2faa7fe49de2d87c))

## 2.1.3 - 2026-10-20

### Features

- Require vpndetection 3.9.0: lookup results carry location and asn ([`bd6ffa1`](https://github.com/vpndetection-io/sdk-erlang-cowboy/commit/bd6ffa126e9370b4fc397eb8eef6004624903f3d))

## 2.1.2 - 2026-10-19

### Fixes

- Require vpndetection 3.8.1: warn once when the result cache has stopped ([`1d4bb94`](https://github.com/vpndetection-io/sdk-erlang-cowboy/commit/1d4bb94d771dfc781de0e534d0162a4ffebc6936))

## 2.1.1 - 2026-10-19

### Fixes

- Require vpndetection 3.8.0: num_ports and num_proxies in the pubproxy detail ([`8aeb645`](https://github.com/vpndetection-io/sdk-erlang-cowboy/commit/8aeb6450aa8c5e05c9667832bfc9c6902472f030))

## 2.1.0 - 2026-10-18

### Features

- Read the PROXY protocol's source address from a trusted balancer ([`644f838`](https://github.com/vpndetection-io/sdk-erlang-cowboy/commit/644f838ba50299f8f18180c8288957e083998ae8))

### Fixes

- Require vpndetection 3.7.0: the PROXY selector and is_pubproxy ([`319e2aa`](https://github.com/vpndetection-io/sdk-erlang-cowboy/commit/319e2aad45ae2505cc7ea9baa531d2a9d0c6a9b4))

## 2.0.13 - 2026-10-17

### Fixes

- Require vpndetection 3.6.0: a nil key is no key, and the cache ends with its owner ([`67be02a`](https://github.com/vpndetection-io/sdk-erlang-cowboy/commit/67be02a309df94ce2af70272333b0b535f60344a))

## 2.0.12 - 2026-10-16

### Fixes

- Require vpndetection 3.5.3: the spec re-pinned to 2026.10.15 ([`6988621`](https://github.com/vpndetection-io/sdk-erlang-cowboy/commit/69886215aebf8e449749ee5b1e545a3d138171d7))

## 2.0.11 - 2026-10-14

### Fixes

- Require vpndetection 3.5.2: an unset key runs keyless, an unreadable 2xx is retried ([`e847230`](https://github.com/vpndetection-io/sdk-erlang-cowboy/commit/e847230da413bfc4caa5b5862a039ac2b972abc0))

## 2.0.10 - 2026-10-10

### Fixes

- Require vpndetection 3.5.1: the spec re-pinned to 2026.10.09 ([`9b0ba62`](https://github.com/vpndetection-io/sdk-erlang-cowboy/commit/9b0ba624e294ba6321a929dee3a4dc1b663d5bca))

## 2.0.9 - 2026-10-05

### Fixes

- Require vpndetection 3.5.0: a 503 reaches its retries at once on OTP 28.4+ ([`e690eb7`](https://github.com/vpndetection-io/sdk-erlang-cowboy/commit/e690eb7796a35fbf982686e67994f51d8a4c0d8b))

## 2.0.8 - 2026-10-04

### Fixes

- Require vpndetection 3.4.3, re-pinned to spec 2026.10.03 ([`80dd18b`](https://github.com/vpndetection-io/sdk-erlang-cowboy/commit/80dd18b4e517e471453cc4f634941bafddf586da))

## 2.0.7 - 2026-10-01

### Fixes

- Require vpndetection 3.4.2: concurrent requests from one visitor share one lookup ([`e5c67e3`](https://github.com/vpndetection-io/sdk-erlang-cowboy/commit/e5c67e3cb5298a092ab7898fab7af87c649b30a8))

## 2.0.6 - 2026-09-29

### Fixes

- Require vpndetection 3.4.1: IPv4-mapped visitors are looked up, not waved through ([`d6e5dca`](https://github.com/vpndetection-io/sdk-erlang-cowboy/commit/d6e5dca9c2b5079fae0198c927c4606454747ab5))

## 2.0.5 - 2026-09-27

### Features

- Require vpndetection 3.4.0: the metadata map carries client_id_metadata_document_supported ([`2d6db44`](https://github.com/vpndetection-io/sdk-erlang-cowboy/commit/2d6db4430114b93a3782b8637972ed4c495b4e6a))

## 2.0.4 - 2026-09-23

### Fixes

- Raise the vpndetection floor to 3.3.2 ([`205564d`](https://github.com/vpndetection-io/sdk-erlang-cowboy/commit/205564d3d6bdf999538d1bd9734b045557383caf))
