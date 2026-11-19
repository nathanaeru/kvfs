-module(kvfs_ws_handler).
-behaviour(cowboy_websocket).

-export([init/2, websocket_init/1, websocket_handle/2, websocket_info/2, broadcast/1]).

init(Req, State) ->
    {cowboy_websocket, Req, State}.

websocket_init(State) ->
    catch pg:start(pg),
    pg:join(pg, kvfs_ws_clients, self()),
    {ok, State}.

websocket_handle({text, <<"ping">>}, State) ->
    {reply, {text, <<"pong">>}, State};
websocket_handle(_Frame, State) ->
    {ok, State}.

websocket_info({broadcast, JsonMessage}, State) ->
    {reply, {text, JsonMessage}, State};
websocket_info(_Info, State) ->
    {ok, State}.

broadcast(DataMap) ->
    Json = jsx:encode(DataMap),
    Pids = pg:get_members(pg, kvfs_ws_clients),
    lists:foreach(fun(Pid) -> Pid ! {broadcast, Json} end, Pids).