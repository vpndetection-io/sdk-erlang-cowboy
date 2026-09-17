# [<img src="https://s3.vpndetection.io/vpndetection-public/brand/mark.svg" alt="VPNDetection" width="24"/>](https://vpndetection.io/) VPNDetection Cowboy Middleware

[![Hex.pm](https://img.shields.io/hexpm/v/vpndetection_cowboy.svg)](https://hex.pm/packages/vpndetection_cowboy)
[![HexDocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/vpndetection_cowboy)
[![license](https://img.shields.io/github/license/vpndetection-io/sdk-erlang-cowboy.svg)](LICENSE)

The official [Cowboy](https://github.com/ninenines/cowboy) middleware for the [VPNDetection](https://vpndetection.io) API.

It classifies the visitor behind each request — VPN, residential proxy, Tor, hosting, CDN, relay — and puts the answer on the request. Blocking is opt-in.

Elixir's `Plug.Cowboy` runs the same middleware chain, so this works there too through `protocol_options`.

## Getting Started

```erlang
{deps, [{vpndetection_cowboy, "~> 2.0"}]}.
```

Requires OTP 27 or newer, and Cowboy 2.13 or newer.

You need an API key. Create one in the [console](https://app.vpndetection.io); the free tier's allowance is counted per source address, and a server is a single source address, so a key is what makes this usable in production rather than optional.

Build the core once, at startup, and name this module in the chain:

```erlang
{ok, Core} = vpndetection_cowboy:core(#{api_key => os:getenv("VPNDETECTION_API_KEY")}),
Dispatch = cowboy_router:compile([{'_', [{"/", my_handler, []}]}]),
{ok, _} = cowboy:start_clear(http, [{port, 8080}], #{
    env => #{dispatch => Dispatch, vpndetection => Core},
    middlewares => [cowboy_router, vpndetection_cowboy, cowboy_handler]
}).
```

**After `cowboy_router`**, so a `skip` can look at the matched route, and **before `cowboy_handler`**, so a blocked request never reaches one.

The core owns the HTTP client and the answer cache, so build it once. One per request would mean neither ever helps.

Your handler reads what it found:

```erlang
init(Req, State) ->
    Body = case vpndetection_cowboy:lookup(Req) of
        #{result := #{is_vpn := true}} -> <<"Hello, VPN user">>;
        _ -> <<"Hello">>
    end,
    {ok, cowboy_req:reply(200, #{}, Body, Req), State}.
```

By default nothing is blocked. Every request carries a lookup and your own handlers decide what that means — which is usually what you want, because whether a VPN visitor is a problem depends entirely on what they are doing.

## Blocking

Set a `block_condition` and a matching request is answered with `403` and never reaches your handlers.

```erlang
vpndetection_cowboy:core(#{api_key => Key, block_condition => #{is_vpn => true}}).
```

A condition is written in the shape of a result, keyed by the same names the API uses, and only the members you name are considered. That lets it reach the evidence, not just the flags:

```erlang
%% one provider
#{is_vpn => true, vpn => #{provider => <<"nordvpn">>}}

%% a numeric threshold
#{resproxy => #{hits => #{gte => 5}}}

%% any of these
#{vpn => #{confidence => [<<"high">>, <<"medium">>]}}

%% a list is OR
[#{is_tor => true}, #{is_resproxy => true}]
```

Values are matched by equality, strings without regard to case. A list means any-of. A map of `gte`/`gt`/`lte`/`lt` bounds a number and combines into a range; every bound you give must hold. Members set to `false`, `null` or `undefined` are ignored, so a condition states the signals you act on; one that constrains nothing would match every request, and is refused when the core is built rather than silently blocking all your traffic.

Atom and binary keys both work, so a condition can come straight out of `json:decode/1` on your app's config file:

```erlang
{ok, Raw} = file:read_file("policy.json"),
vpndetection_cowboy:core(#{api_key => Key, block_condition => json:decode(Raw)}).
```

**Write strings as binaries.** An Erlang string is a list of codepoints, so `"nordvpn"` and an any-of of those numbers are the same term. A bare string is accepted anyway, but binaries have no such ambiguity and are what `json:decode/1` produces.

Replace the refusal with `on_blocked`, which must reply:

```erlang
on_blocked => fun(Req, _Found) ->
    cowboy_req:reply(403, #{}, <<"VPN not allowed">>, Req)
end
```

## Where the client address comes from

This is the setting that decides whether any of the above works, and it is the one thing only you can get right.

By default the middleware uses `cowboy_req:peer/1`. **Cowboy has no trusted-proxy setting**, so that is the socket peer and nothing else. If your app sits behind nginx, a load balancer, or a CDN, every visitor arrives wearing your proxy's address — which is a datacenter address, so a hosting rule would block all of them.

For an edge that writes the address into its own header, name the header:

```erlang
ip_selector => vpndetection_selectors:header(<<"CF-Connecting-IP">>)   % or True-Client-IP
```

`vpndetection_selectors:xff(0)` reads the left-most `X-Forwarded-For` entry. Be aware that the left-most entry is whatever the caller sent, because proxies append to that header — it is only trustworthy when an edge you control overwrites it. If you know how many proxies sit in front, count from the right instead: `xff(1)` is the address your nearest proxy saw.

Anything else, pass your own fun. It receives a view of the request and returns an address:

```erlang
ip_selector => fun(View) -> (maps:get(header, View))(<<"x-real-ip">>) end
```

If the address resolves to a private one, the middleware says so once through `on_warn`, which defaults to `logger:warning/1`. That is expected on localhost and is the signal to fix your configuration anywhere else.

## When a lookup fails

The request is let through, and the reason is on the lookup's `error` key. Our outage should not become yours, so a network failure, an exhausted quota or a rejected key all fail open.

```erlang
case vpndetection_cowboy:lookup(Req) of
    #{error := #{kind := Kind}} when Kind =/= undefined ->
        logger:warning("vpndetection unavailable: ~p", [Kind]);
    _ ->
        ok
end
```

Set `fail_closed => true` to block instead. Private addresses are answered locally and never fail, so this will not lock you out in development.

## Cost and latency

Answers are cached per core for an hour, so a returning visitor costs nothing, and private addresses never leave the process. A cache miss is one request to our API, bounded at 2500 ms by default and not retried — on a request path, failing open quickly beats holding a visitor while we try again. Both are adjustable, and so is the cache, through a client you build yourself and pass as `client`.

Skip what you do not care about:

```erlang
skip => fun(Req) -> cowboy_req:path(Req) =:= <<"/healthz">> end
```

If you already hold a `vpndetection` client, pass it as `client` and the middleware will share it rather than building a second cache.

Beyond a few million distinct visitors a day, stop calling the API per request: [download the dataset](https://vpndetection.io/databases) and look addresses up locally instead.

## Absent is not false

Only `ip` and `is_vpn` come back on every plan. A key your plan does not include is ABSENT from the result map, which means "not in your plan" rather than "checked, and no".

```erlang
maps:get(is_hosting, Result, false)        % when you only want the flag
maps:get(is_hosting, Result, undefined)    % when the difference matters
```

A `block_condition` naming a member your plan does not serve can never match, so the middleware warns once instead of failing silently. Set `on_missing_field => error` to make it an error, which this middleware answers with a `500`.

## Other Libraries

There are official VPNDetection client libraries available for many languages including PHP, Python, Go, Java, Ruby, and many popular frameworks such as Django, Rails, and Laravel. See our GitHub at https://github.com/vpndetection-io for more.

## About VPNDetection

VPN Detection API: Accurate anonymity detection identifying VPNs, residential proxies, hosting servers, Tor nodes, CDNs, relays and more.

[<img src="https://s3.vpndetection.io/vpndetection-public/brand/mark.svg" alt="VPNDetection" width="96"/>](https://vpndetection.io/)

## License

This project is licensed under the [MIT License](LICENSE).
