-module(kvfs_http_handler).
-behaviour(cowboy_handler).

-export([init/2]).

init(Req0, Action) ->
    Method = cowboy_req:method(Req0),
    PathInfo = cowboy_req:path_info(Req0),
    handle_action(Action, Method, PathInfo, Req0).

handle_action(list_dir, <<"GET">>, PathInfo, Req0) ->
    case PathInfo of
        [Owner | Rest] ->
            case kvfs_vfs:list_dir(Owner, Rest) of
                {ok, Entries} ->
                    Formatted = [format_entry(Name, Payload) || {Name, Payload} <- Entries],
                    reply_json(200, #{status => ok, entries => Formatted}, Req0);
                {error, Reason} ->
                    reply_json(400, #{status => error, reason => format_reason(Reason)}, Req0)
            end;
        _ ->
            reply_json(400, #{status => error, reason => <<"owner_required">>}, Req0)
    end;

handle_action(file_ops, <<"GET">>, [Owner | Rest], Req0) ->
    case kvfs_vfs:read_path(Owner, Rest) of
        {ok, Payload} ->
            reply_json(200, #{status => ok, data => Payload}, Req0);
        {error, not_found} ->
            reply_json(404, #{status => error, reason => <<"not_found">>}, Req0);
        {error, Reason} ->
            reply_json(500, #{status => error, reason => format_reason(Reason)}, Req0)
    end;

handle_action(file_ops, <<"POST">>, [Owner | Rest], Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Params = try jsx:decode(Body, [return_maps]) catch _:_ -> #{} end,
    NodeType = maps:get(<<"type">>, Params, <<"file">>),
    
    Res = case NodeType of
        <<"directory">> ->
            kvfs_vfs:create_directory(Owner, Rest);
        _ ->
            Content = maps:get(<<"content">>, Params, <<"">>),
            Tags = maps:get(<<"tags">>, Params, []),
            MimeType = maps:get(<<"mime_type">>, Params, <<"text/plain">>),
            kvfs_vfs:create_file(Owner, Rest, Content, Tags, MimeType)
    end,
    case Res of
        ok ->
            kvfs_ws_handler:broadcast(#{event => <<"tree_updated">>, owner => Owner}),
            reply_json(200, #{status => ok}, Req1);
        {error, Reason} ->
            reply_json(400, #{status => error, reason => format_reason(Reason)}, Req1)
    end;

handle_action(file_ops, <<"DELETE">>, [Owner | Rest], Req0) ->
    case kvfs_vfs:delete_path(Owner, Rest) of
        ok ->
            kvfs_ws_handler:broadcast(#{event => <<"tree_updated">>, owner => Owner}),
            reply_json(200, #{status => ok}, Req0);
        {error, Reason} ->
            reply_json(400, #{status => error, reason => format_reason(Reason)}, Req0)
    end;

handle_action(move_path, <<"POST">>, _, Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Params = try jsx:decode(Body, [return_maps]) catch _:_ -> #{} end,
    Owner = maps:get(<<"owner">>, Params, <<"alice">>),
    Src = maps:get(<<"src">>, Params, []),
    Dst = maps:get(<<"dst">>, Params, []),
    case kvfs_vfs:move_path(Owner, Src, Dst) of
        ok ->
            kvfs_ws_handler:broadcast(#{event => <<"tree_updated">>, owner => Owner}),
            reply_json(200, #{status => ok}, Req1);
        {error, Reason} ->
            reply_json(400, #{status => error, reason => format_reason(Reason)}, Req1)
    end;

handle_action(copy_path, <<"POST">>, _, Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Params = try jsx:decode(Body, [return_maps]) catch _:_ -> #{} end,
    Owner = maps:get(<<"owner">>, Params, <<"alice">>),
    Src = maps:get(<<"src">>, Params, []),
    Dst = maps:get(<<"dst">>, Params, []),
    case kvfs_vfs:copy_path(Owner, Src, Dst) of
        ok ->
            kvfs_ws_handler:broadcast(#{event => <<"tree_updated">>, owner => Owner}),
            reply_json(200, #{status => ok}, Req1);
        {error, Reason} ->
            reply_json(400, #{status => error, reason => format_reason(Reason)}, Req1)
    end;

handle_action(search_tag, <<"GET">>, _, Req0) ->
    #{tag := Tag} = cowboy_req:match_qs([{tag, [], undefined}], Req0),
    case Tag of
        undefined ->
            reply_json(400, #{status => error, reason => <<"tag_parameter_required">>}, Req0);
        _ ->
            Results = kvfs_projection:search_by_tag(Tag),
            Formatted = [format_khepri_path(P) || P <- Results],
            reply_json(200, #{status => ok, tag => Tag, matches => Formatted}, Req0)
    end;

handle_action(user_quota, <<"GET">>, _, Req0) ->
    Owner = cowboy_req:binding(owner, Req0),
    {ok, Quota} = kvfs_projection:get_user_quota(Owner),
    reply_json(200, #{status => ok, quota => Quota}, Req0);

handle_action(_, _, _, Req0) ->
    reply_json(405, #{status => error, reason => <<"method_not_allowed">>}, Req0).

reply_json(Code, Map, Req) ->
    Body = jsx:encode(Map),
    Req1 = cowboy_req:reply(Code, #{<<"content-type">> => <<"application/json">>}, Body, Req),
    {ok, Req1, list_dir}.

%% Penanganan aman terhadap Payload non-map / undefined
format_entry(Name, Payload) when is_map(Payload) ->
    Payload#{name => Name};
format_entry(Name, _OtherPayload) ->
    #{
        name => Name,
        type => <<"directory">>,
        size => 0,
        tags => []
    }.

format_khepri_path([kvfs, Owner | Rest]) ->
    #{owner => Owner, path => Rest}.

format_reason(Reason) when is_binary(Reason) -> Reason;
format_reason(Reason) -> list_to_binary(io_lib:format("~p", [Reason])).