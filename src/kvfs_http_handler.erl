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
            OwnerBin = binary_to_existing_atom_or_bin(Owner),
            RestBins = [binary_to_existing_atom_or_bin(P) || P <- Rest],
            case kvfs_vfs:list_dir(OwnerBin, RestBins) of
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
    OwnerBin = binary_to_existing_atom_or_bin(Owner),
    RestBins = [binary_to_existing_atom_or_bin(P) || P <- Rest],
    case kvfs_vfs:read_path(OwnerBin, RestBins) of
        {ok, Payload} ->
            reply_json(200, #{status => ok, data => Payload}, Req0);
        {error, not_found} ->
            reply_json(404, #{status => error, reason => <<"not_found">>}, Req0);
        {error, Reason} ->
            reply_json(500, #{status => error, reason => format_reason(Reason)}, Req0)
    end;

handle_action(file_ops, <<"POST">>, [Owner | Rest], Req0) ->
    OwnerBin = binary_to_existing_atom_or_bin(Owner),
    RestBins = [binary_to_existing_atom_or_bin(P) || P <- Rest],
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    Params = jsx:decode(Body, [return_maps]),
    NodeType = maps:get(<<"type">>, Params, <<"file">>),
    
    Res = case NodeType of
        <<"directory">> ->
            kvfs_vfs:create_directory(OwnerBin, RestBins);
        _ ->
            Content = maps:get(<<"content">>, Params, <<"">>),
            Tags = maps:get(<<"tags">>, Params, []),
            MimeType = maps:get(<<"mime_type">>, Params, <<"text/plain">>),
            kvfs_vfs:create_file(OwnerBin, RestBins, Content, Tags, MimeType)
    end,
    case Res of
        ok ->
            kvfs_ws_handler:broadcast(#{event => <<"tree_updated">>, owner => OwnerBin}),
            reply_json(200, #{status => ok}, Req1);
        {error, Reason} ->
            reply_json(400, #{status => error, reason => format_reason(Reason)}, Req1)
    end;

handle_action(file_ops, <<"DELETE">>, [Owner | Rest], Req0) ->
    OwnerBin = binary_to_existing_atom_or_bin(Owner),
    RestBins = [binary_to_existing_atom_or_bin(P) || P <- Rest],
    case kvfs_vfs:delete_path(OwnerBin, RestBins) of
        ok ->
            kvfs_ws_handler:broadcast(#{event => <<"tree_updated">>, owner => OwnerBin}),
            reply_json(200, #{status => ok}, Req0);
        {error, Reason} ->
            reply_json(400, #{status => error, reason => format_reason(Reason)}, Req0)
    end;

handle_action(move_path, <<"POST">>, _, Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    #{<<"owner">> := Owner, <<"src">> := Src, <<"dst">> := Dst} = jsx:decode(Body, [return_maps]),
    case kvfs_vfs:move_path(binary_to_existing_atom_or_bin(Owner), Src, Dst) of
        ok ->
            kvfs_ws_handler:broadcast(#{event => <<"tree_updated">>, owner => Owner}),
            reply_json(200, #{status => ok}, Req1);
        {error, Reason} ->
            reply_json(400, #{status => error, reason => format_reason(Reason)}, Req1)
    end;

handle_action(copy_path, <<"POST">>, _, Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    #{<<"owner">> := Owner, <<"src">> := Src, <<"dst">> := Dst} = jsx:decode(Body, [return_maps]),
    case kvfs_vfs:copy_path(binary_to_existing_atom_or_bin(Owner), Src, Dst) of
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
    OwnerBin = binary_to_existing_atom_or_bin(Owner),
    {ok, Quota} = kvfs_projection:get_user_quota(OwnerBin),
    reply_json(200, #{status => ok, quota => Quota}, Req0);

handle_action(_, _, _, Req0) ->
    reply_json(405, #{status => error, reason => <<"method_not_allowed">>}, Req0).

reply_json(Code, Map, Req) ->
    Body = jsx:encode(Map),
    Req1 = cowboy_req:reply(Code, #{<<"content-type">> => <<"application/json">>}, Body, Req),
    {ok, Req1, list_dir}.

format_entry(Name, Payload) ->
    Payload#{name => Name}.

format_khepri_path([kvfs, Owner | Rest]) ->
    #{owner => Owner, path => Rest}.

binary_to_existing_atom_or_bin(Bin) when is_binary(Bin) ->
    try binary_to_existing_atom(Bin, utf8)
    catch error:badarg -> Bin
    end;
binary_to_existing_atom_or_bin(Val) -> Val.

format_reason(Reason) when is_binary(Reason) -> Reason;
format_reason(Reason) -> list_to_binary(io_lib:format("~p", [Reason])).