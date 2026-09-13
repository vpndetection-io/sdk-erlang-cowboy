%% The adapter against a REAL Cowboy server on a real socket, plus the shared
%% conformance corpus asserted end to end rather than against the core.
%%
%% What is NOT here is the condition matrix, fail-open and the selectors: those
%% are framework-independent and are asserted once for Erlang, in the
%% vpndetection package's own suite. Repeating them per adapter is how two
%% adapters end up disagreeing about which copy is right.
%%
%% A loopback client makes `cowboy_req:peer/1' a bogon, which is answered
%% locally without a request. Anything that needs a served answer therefore has
%% to arrive wearing a public address, through a selector.
-module(vpndetection_cowboy_tests).

-include_lib("eunit/include/eunit.hrl").

%% Cowboy calls init/2 on the handler MODULE, and both the app under test and
%% the stub API are handlers, so one callback serves both and the route's own
%% state says which.
-export([init/2]).

-define(PUBLIC_IP, <<"45.83.91.1">>).

%%% ---------------------------------------------------------------- the corpus

corpus_conditions_test_() ->
    {setup, fun start_apps/0, fun stop_apps/1,
     {inparallel,
      [{binary_to_list(Name), fun() -> assert_condition(Case) end}
       || #{<<"name">> := Name} = Case <- corpus(<<"conditions">>)]}}.

assert_condition(#{<<"condition">> := Condition, <<"expect">> := Expect, <<"why">> := Why} = Case) ->
    {Ip, Body} = fixture(Case),
    Api = api(Body),
    Warnings = collector(),
    App = app(#{
        base_url => base_url(Api),
        retries => 0,
        ip_selector => fun(_View) -> Ip end,
        block_condition => Condition,
        on_warn => sink(Warnings)
    }),

    {Status, _} = get(App, "/", []),

    Want = case maps:get(<<"blocked">>, Expect) of true -> 403; false -> 200 end,
    ?assertEqual({Want, Why}, {Status, Why}),
    Missing = maps:get(<<"missing">>, Expect, []),
    Reported = [W || W <- seen(Warnings), binary:match(W, <<"does not include">>) =/= nomatch],
    ?assertEqual({min(length(Missing), 1), Why}, {length(Reported), Why}),
    [?assertNotEqual({M, nomatch}, {M, binary:match(hd(Reported), M)}) || M <- Missing],
    stop(App),
    stop(Api).

%%% ------------------------------------------------- what only Cowboy can show

enriches_the_request_and_leaves_the_decision_to_the_handler_test_() ->
    {setup, fun start_apps/0, fun stop_apps/1, fun() ->
        Api = api(#{<<"is_vpn">> => true}),
        App = app(#{base_url => base_url(Api), ip_selector => fun(_) -> ?PUBLIC_IP end}),

        {200, Body} = get(App, "/", []),

        ?assertEqual(true, maps:get(<<"attached">>, Body)),
        ?assertEqual(true, maps:get(<<"is_vpn">>, Body)),
        ?assertEqual(?PUBLIC_IP, maps:get(<<"ip">>, Body)),
        ?assertEqual([?PUBLIC_IP], asked(Api)),
        stop(App),
        stop(Api)
    end}.

a_blocked_request_never_reaches_the_handler_test_() ->
    {setup, fun start_apps/0, fun stop_apps/1, fun() ->
        Api = api(#{<<"is_vpn">> => true}),
        App = app(#{base_url => base_url(Api), ip_selector => fun(_) -> ?PUBLIC_IP end,
                    block_condition => #{is_vpn => true}}),

        {Status, Body} = get(App, "/", []),

        ?assertEqual(403, Status),
        ?assertEqual(#{<<"error">> => <<"access denied">>}, Body),
        ?assertEqual(error, maps:find(<<"attached">>, Body)),
        stop(App),
        stop(Api)
    end}.

on_blocked_replaces_the_refusal_test_() ->
    {setup, fun start_apps/0, fun stop_apps/1, fun() ->
        Api = api(#{<<"is_vpn">> => true, <<"vpn">> => #{<<"provider">> => <<"nordvpn">>}}),
        App = app(#{
            base_url => base_url(Api),
            ip_selector => fun(_) -> ?PUBLIC_IP end,
            block_condition => #{is_vpn => true},
            on_blocked => fun(Req, Found) ->
                Provider = maps:get(provider, maps:get(vpn, maps:get(result, Found))),
                cowboy_req:reply(451, #{<<"content-type">> => <<"text/plain">>}, Provider, Req)
            end
        }),

        ?assertEqual({451, <<"nordvpn">>}, raw(App, "/", [])),
        stop(App),
        stop(Api)
    end}.

skip_leaves_the_request_untouched_test_() ->
    {setup, fun start_apps/0, fun stop_apps/1, fun() ->
        Api = api(#{<<"is_vpn">> => true}),
        App = app(#{
            base_url => base_url(Api),
            ip_selector => fun(_) -> ?PUBLIC_IP end,
            block_condition => #{is_vpn => true},
            skip => fun(Req) -> cowboy_req:path(Req) =:= <<"/healthz">> end
        }),

        {200, Body} = get(App, "/healthz", []),

        ?assertEqual(false, maps:get(<<"attached">>, Body)),
        ?assertEqual([], asked(Api)),
        stop(App),
        stop(Api)
    end}.

a_failing_lookup_lets_the_visitor_through_test_() ->
    {setup, fun start_apps/0, fun stop_apps/1, fun() ->
        Api = api(#{<<"error">> => <<"boom">>}, 500),
        App = app(#{base_url => base_url(Api), retries => 0,
                    ip_selector => fun(_) -> ?PUBLIC_IP end,
                    block_condition => #{is_vpn => true}}),

        {200, Body} = get(App, "/", []),

        ?assertEqual(<<"server_error">>, maps:get(<<"error">>, Body)),
        stop(App),
        stop(Api)
    end}.

%% The test that matters. Every other assertion here would pass whether or not
%% the selector is right, because a direct connection has nothing to confuse.
a_forged_x_forwarded_for_is_ignored_by_default_test_() ->
    {setup, fun start_apps/0, fun stop_apps/1, fun() ->
        Api = api(#{<<"is_vpn">> => true}),
        App = app(#{base_url => base_url(Api)}),

        {200, Body} = get(App, "/", [{"X-Forwarded-For", binary_to_list(?PUBLIC_IP)}]),

        ?assertEqual(<<"127.0.0.1">>, maps:get(<<"ip">>, Body)),
        ?assertEqual(true, maps:get(<<"is_bogon">>, Body)),
        ?assertEqual([], asked(Api)),
        stop(App),

        Trusting = app(#{base_url => base_url(Api),
                         ip_selector => vpndetection_selectors:xff(0)}),
        {200, Forwarded} = get(Trusting, "/", [{"X-Forwarded-For", binary_to_list(?PUBLIC_IP)}]),
        ?assertEqual(?PUBLIC_IP, maps:get(<<"ip">>, Forwarded)),
        ?assertEqual([?PUBLIC_IP], asked(Api)),
        stop(Trusting),
        stop(Api)
    end}.

a_header_selector_reads_the_edge_that_writes_it_test_() ->
    {setup, fun start_apps/0, fun stop_apps/1, fun() ->
        Api = api(#{<<"is_vpn">> => true}),
        App = app(#{base_url => base_url(Api),
                    ip_selector => vpndetection_selectors:header(<<"CF-Connecting-IP">>)}),

        get(App, "/", [{"CF-Connecting-IP", "45.83.91.9"}]),

        ?assertEqual([<<"45.83.91.9">>], asked(Api)),
        stop(App),
        stop(Api)
    end}.

depth_counts_trusted_hops_from_the_right_test_() ->
    {setup, fun start_apps/0, fun stop_apps/1, fun() ->
        Api = api(#{<<"is_vpn">> => true}),
        App = app(#{base_url => base_url(Api), ip_selector => vpndetection_selectors:xff(1)}),

        get(App, "/", [{"X-Forwarded-For", "45.83.91.1, 70.41.3.18, 150.172.238.178"}]),

        ?assertEqual([<<"150.172.238.178">>], asked(Api)),
        stop(App),
        stop(Api)
    end}.

%% Cowboy's peer is the socket peer with no trusted-proxy setting at all, so on
%% loopback the answer is computed locally and can never block. Local
%% development must not lock you out of your own app.
a_private_client_address_is_answered_locally_and_never_blocks_test_() ->
    {setup, fun start_apps/0, fun stop_apps/1, fun() ->
        Api = api(#{<<"is_vpn">> => true}),
        App = app(#{base_url => base_url(Api), block_condition => #{is_vpn => true}}),

        {Status, Body} = get(App, "/", []),

        ?assertEqual(200, Status),
        ?assertEqual(true, maps:get(<<"is_bogon">>, Body)),
        ?assertEqual([], asked(Api)),
        stop(App),
        stop(Api)
    end}.

a_condition_that_constrains_nothing_is_refused_when_the_core_is_built_test() ->
    ?assertMatch({error, {constrains_nothing, _, _}},
                 vpndetection_cowboy:core(#{block_condition => #{is_vpn => false}})).

%% Named in the chain but never configured: every request would otherwise crash
%% on a missing env key, which is the opposite of the fail-open this middleware
%% promises everywhere else.
an_unconfigured_middleware_lets_the_request_through_test_() ->
    {setup, fun start_apps/0, fun stop_apps/1, fun() ->
        App = listen(#{dispatch => dispatch()}),
        {200, Body} = get(App, "/", []),
        ?assertEqual(false, maps:get(<<"attached">>, Body)),
        stop(App)
    end}.

%%% ------------------------------------------------------------------- the app

%% A handler that reports back what the middleware attached.
init(Req, {api, Body, Status, Asked} = State) ->
    Address = iolist_to_binary(lists:join($/, cowboy_req:path_info(Req))),
    Asked ! {asked, Address},
    Answer = json:encode(Body#{<<"ip">> => Address}),
    {ok,
        cowboy_req:reply(Status, #{<<"content-type">> => <<"application/json">>}, Answer, Req),
        State};
init(Req, State) ->
    Found = vpndetection_cowboy:lookup(Req),
    Body = json:encode(#{
        <<"attached">> => Found =/= undefined,
        <<"ip">> => at(Found, ip),
        <<"is_vpn">> => flag(Found, is_vpn),
        <<"is_bogon">> => flag(Found, is_bogon),
        <<"error">> => error_kind(Found)
    }),
    {ok, cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, Body, Req), State}.

at(undefined, _Key) -> null;
at(Found, Key) -> null_for_undefined(maps:get(Key, Found, undefined)).

flag(undefined, _Key) -> null;
flag(#{result := undefined}, _Key) -> null;
flag(#{result := Result}, Key) -> null_for_undefined(maps:get(Key, Result, undefined)).

error_kind(undefined) -> null;
error_kind(#{error := undefined}) -> null;
error_kind(#{error := Error}) -> atom_to_binary(maps:get(kind, Error), utf8).

null_for_undefined(undefined) -> null;
null_for_undefined(Value) -> Value.

app(Options) ->
    {ok, Core} = vpndetection_cowboy:core(Options),
    listen(#{dispatch => dispatch(), vpndetection => Core}).

dispatch() ->
    cowboy_router:compile([{'_', [{"/[...]", ?MODULE, []}]}]).

listen(Env) ->
    Name = {app, make_ref()},
    {ok, _} = cowboy:start_clear(Name, [{port, 0}], #{
        env => Env,
        middlewares => [cowboy_router, vpndetection_cowboy, cowboy_handler]
    }),
    {Name, ranch:get_port(Name)}.

%%% ------------------------------------------------------------- the stub API

%% A stand-in API, served by Cowboy on a random port, that answers every lookup
%% from one body and records what it was asked about - so "never touched the
%% network" is asserted rather than assumed.
api(Body) ->
    api(Body, 200).

api(Body, Status) ->
    Asked = collector(),
    Name = {api, make_ref()},
    Dispatch = cowboy_router:compile([
        {'_', [{"/[...]", ?MODULE, {api, maps:without([<<"ip">>], Body), Status, Asked}}]}
    ]),
    {ok, _} = cowboy:start_clear(Name, [{port, 0}], #{env => #{dispatch => Dispatch}}),
    {Name, ranch:get_port(Name), Asked}.

base_url({_Name, Port, _Asked}) ->
    iolist_to_binary(["http://127.0.0.1:", integer_to_list(Port)]).

asked({_Name, _Port, Collector}) ->
    [A || {asked, A} <- seen(Collector)].

stop({Name, _Port}) -> ok = cowboy:stop_listener(Name);
stop({Name, _Port, _Asked}) -> ok = cowboy:stop_listener(Name).

%%% ------------------------------------------------------------------ helpers

start_apps() ->
    {ok, Started} = application:ensure_all_started([cowboy, inets, ssl]),
    Started.

stop_apps(_Started) ->
    ok.

get(App, Path, Headers) ->
    {Status, Body} = raw(App, Path, Headers),
    {Status, json:decode(Body)}.

raw({_Name, Port}, Path, Headers) ->
    Url = "http://127.0.0.1:" ++ integer_to_list(Port) ++ Path,
    {ok, {{_, Status, _}, _, Body}} =
        httpc:request(get, {Url, Headers}, [], [{body_format, binary}]),
    {Status, Body}.

%% eunit runs each test in its own process, so a plain collector process is
%% enough and needs no cleanup beyond the test's own lifetime.
collector() ->
    spawn(fun() -> collect([]) end).

collect(Seen) ->
    receive
        {seen, From} ->
            From ! {seen, Seen},
            collect(Seen);
        Message ->
            collect(Seen ++ [Message])
    end.

sink(Pid) ->
    fun(Message) -> Pid ! Message end.

seen(Pid) ->
    Pid ! {seen, self()},
    receive
        {seen, Messages} -> Messages
    after 5000 -> erlang:error(timeout)
    end.

fixture(#{<<"bogon">> := Ip}) ->
    %% Answered locally, so the stub is never asked and the synthesized shape is
    %% what gets pinned rather than a fixture's idea of it.
    {Ip, #{}};
fixture(#{<<"body">> := Body}) ->
    {maps:get(<<"ip">>, Body), Body}.

corpus(Section) ->
    {ok, Raw} = file:read_file(testdata_path()),
    maps:get(Section, maps:get(<<"middleware">>, json:decode(Raw))).

%% rebar3 runs from the project root, but a bare eunit run from anywhere else
%% would not, so fall back to walking up from the built application.
testdata_path() ->
    case filelib:is_regular("testdata/testdata.json") of
        true ->
            "testdata/testdata.json";
        false ->
            filename:join([code:lib_dir(vpndetection_cowboy), "..", "..", "..", "..",
                           "testdata", "testdata.json"])
    end.
