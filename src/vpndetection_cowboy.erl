%% @doc The official Cowboy middleware for the VPNDetection API.
%%
%% It classifies the visitor behind each request - VPN, residential proxy, Tor,
%% hosting, CDN, relay - and puts the answer on the request, where your handlers
%% can read it with {@link lookup/1}. Blocking is opt-in.
%%
%% Build the core once, at startup, and name this module in the middleware
%% chain:
%%
%% ```
%% {ok, Core} = vpndetection_cowboy:core(#{api_key => <<"...">>}),
%% Dispatch = cowboy_router:compile([{'_', [{"/", my_handler, []}]}]),
%% cowboy:start_clear(http, [{port, 8080}], #{
%%     env => #{dispatch => Dispatch, vpndetection => Core},
%%     middlewares => [cowboy_router, vpndetection_cowboy, cowboy_handler]
%% }).
%% '''
%%
%% AFTER `cowboy_router', so a `skip' can look at the matched route, and BEFORE
%% `cowboy_handler', so a blocked request never reaches one.
%%
%% The framework-agnostic half lives in `vpndetection_middleware'. Elixir's
%% `Plug.Cowboy' runs the same chain, so this works there through
%% `protocol_options'.
-module(vpndetection_cowboy).

-behaviour(cowboy_middleware).

-export([core/1, execute/2, lookup/1]).

-export_type([options/0]).

%% Everything `vpndetection_middleware:options()' takes, plus the two settings
%% that need Cowboy's own request type and so cannot live in the shared core.
-type options() :: #{
    %% Answers a request the condition matched, and must reply. Defaults to 403
    %% with a short JSON body. The handler never runs either way.
    on_blocked => fun((cowboy_req:req(), vpndetection_middleware:lookup()) -> cowboy_req:req()),
    %% Claims a request, so it is never classified - health checks, static
    %% assets, anything a chain-wide middleware would otherwise pay for.
    skip => fun((cowboy_req:req()) -> boolean()),
    _ => _
}.

%% Where the answer is stored on the request. `cowboy_router' adds `bindings'
%% and `path_info' to the same map, so this is the shape Cowboy already uses to
%% pass a middleware's findings down the chain.
-define(REQ_KEY, vpndetection).

%% @doc Build the core, refusing a condition that constrains nothing.
%%
%% Do this ONCE, at startup, and put the result in the protocol env: it owns the
%% HTTP client and the answer cache, and one per request would mean neither ever
%% helps.
-spec core(options()) -> {ok, map()} | {error, term()}.
core(Options) ->
    Shared = maps:without([on_blocked, skip], Options),
    case vpndetection_middleware:new(Shared) of
        {error, _} = Error ->
            Error;
        {ok, Core} ->
            {ok, #{
                core => Core,
                on_blocked => maps:get(on_blocked, Options, fun refuse/2),
                skip => maps:get(skip, Options, fun(_Req) -> false end)
            }}
    end.

%% @doc The Cowboy middleware callback. You do not call this yourself.
-spec execute(cowboy_req:req(), cowboy_middleware:env()) ->
    {ok, cowboy_req:req(), cowboy_middleware:env()} | {stop, cowboy_req:req()}.
execute(Req, Env) ->
    case maps:get(?REQ_KEY, Env, undefined) of
        undefined ->
            %% Named in the chain but never configured. Letting the request
            %% through is the same fail-open the rest of this middleware
            %% promises, and saying so once beats a crash per request.
            logger:warning(
                <<"vpndetection: no `vpndetection' key in the protocol env, so nothing was "
                    "classified; put the result of vpndetection_cowboy:core/1 there">>
            ),
            {ok, Req, Env};
        Configured ->
            classify(Configured, Req, Env)
    end.

%% @doc What the middleware found out about this visitor.
%%
%% `undefined' when the middleware did not run for this route, or when `skip'
%% claimed the request.
-spec lookup(cowboy_req:req()) -> vpndetection_middleware:lookup() | undefined.
lookup(Req) ->
    maps:get(?REQ_KEY, Req, undefined).

classify(#{core := Core, on_blocked := OnBlocked, skip := Skip}, Req, Env) ->
    case Skip(Req) of
        true ->
            {ok, Req, Env};
        false ->
            case vpndetection_middleware:evaluate(Core, view(Req)) of
                %% A condition naming a member the plan does not serve, with
                %% on_missing_field set to error. A failed LOOKUP never reaches
                %% here: it rides on the lookup's `error' key and the visitor is
                %% let through.
                {error, {missing_members, _Missing, Message}} ->
                    {stop, cowboy_req:reply(500, #{<<"content-type">> => <<"text/plain">>},
                                            Message, Req)};
                {ok, #{blocked := true} = Found} ->
                    {stop, OnBlocked(Req#{?REQ_KEY => Found}, Found)};
                {ok, Found} ->
                    {ok, Req#{?REQ_KEY => Found}, Env}
            end
    end.

%% Cowboy has NO trusted-proxy setting, so `peer' is the socket peer and nothing
%% else. Behind a proxy that is the proxy's own address, which is why the README
%% spends most of its length on the selector.
view(Req) ->
    #{
        header => fun(Name) -> cowboy_req:header(Name, Req, undefined) end,
        framework_ip => fun() ->
            {Address, _Port} = cowboy_req:peer(Req),
            list_to_binary(inet:ntoa(Address))
        end
    }.

refuse(Req, _Found) ->
    cowboy_req:reply(
        403, #{<<"content-type">> => <<"application/json">>},
        <<"{\"error\":\"access denied\"}">>, Req
    ).
