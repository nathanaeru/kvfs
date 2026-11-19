%%%-------------------------------------------------------------------
%% @doc kvfs public API
%% @end
%%%-------------------------------------------------------------------

-module(kvfs_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    ok = kvfs_projection:prepare(),
    {ok, _} = khepri:start(),
    ok = kvfs_projection:init(),

    Dispatch = kvfs_router:routes(),
    {ok, _} = cowboy:start_clear(
        kvfs_http_listener,
        [{port, 8080}],
        #{env => #{dispatch => Dispatch}}
    ),
    io:format("~n==================================================~n"),
    io:format("  KVFS Server running on http://localhost:8080~n"),
    io:format("==================================================~n~n"),
    kvfs_sup:start_link().

stop(_State) ->
    cowboy:stop_listener(kvfs_http_listener),
    ok.

%% internal functions
