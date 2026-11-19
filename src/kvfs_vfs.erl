-module(kvfs_vfs).

-include_lib("khepri/include/khepri.hrl").

-export([
    create_directory/2,
    create_file/5,
    read_path/2,
    list_dir/2,
    delete_path/2,
    move_path/3,
    copy_path/3
]).

create_directory(Owner, PathComponents) ->
    KhepriPath = build_path(Owner, PathComponents),
    Now = erlang:system_time(second),
    Payload = #{
        type => directory,
        created_at => Now,
        updated_at => Now
    },
    khepri:put(KhepriPath, Payload).

create_file(Owner, PathComponents, Content, Tags, MimeType) ->
    KhepriPath = build_path(Owner, PathComponents),
    Now = erlang:system_time(second),
    Size = byte_size(Content),
    Payload = #{
        type => file,
        content => Content,
        size => Size,
        tags => Tags,
        mime_type => MimeType,
        created_at => Now,
        updated_at => Now
    },
    khepri:put(KhepriPath, Payload).

read_path(Owner, PathComponents) ->
    KhepriPath = build_path(Owner, PathComponents),
    case khepri:get(KhepriPath) of
        {ok, Payload} ->
            {ok, Payload};
        {error, {khepri, node_not_found, _Details}} ->
            {error, not_found};
        Error ->
            Error
    end.

list_dir(Owner, PathComponents) ->
    ChildPattern = #if_name_matches{regex = ".*"},
    KhepriPath = build_path(Owner, PathComponents) ++ [ChildPattern],
    case khepri:get_many(KhepriPath) of
        {ok, Entries} ->
            Formatted = maps:fold(
                fun(Path, Payload, Acc) ->
                    NodeName = lists:last(Path),
                    [{NodeName, Payload} | Acc]
                end,
                [],
                Entries
            ),
            {ok, Formatted};
        {error, {khepri, node_not_found, _Details}} ->
            {ok, []};
        Error ->
            Error
    end.

delete_path(Owner, PathComponents) ->
    KhepriPath = build_path(Owner, PathComponents),
    khepri:delete(KhepriPath).

move_path(Owner, SrcPathComponents, DstPathComponents) ->
    SrcKhepriPath = build_path(Owner, SrcPathComponents),
    DstKhepriPath = build_path(Owner, DstPathComponents),
    Now = erlang:system_time(second),
    khepri:transaction(fun() ->
        case khepri_tx:get(SrcKhepriPath) of
            {ok, SrcPayload} ->
                FinalDstPath = resolve_dst_path(DstKhepriPath, SrcPathComponents),
                UpdatedSrcPayload = SrcPayload#{updated_at => Now},
                
                ok = khepri_tx:put(FinalDstPath, UpdatedSrcPayload),
                move_children_tx(SrcKhepriPath, FinalDstPath),
                ok = khepri_tx:delete(SrcKhepriPath),
                ok;
            _ ->
                khepri_tx:abort(src_not_found)
        end
    end).

copy_path(Owner, SrcPathComponents, DstPathComponents) ->
    SrcKhepriPath = build_path(Owner, SrcPathComponents),
    DstKhepriPath = build_path(Owner, DstPathComponents),
    Now = erlang:system_time(second),
    khepri:transaction(fun() ->
        case khepri_tx:get(SrcKhepriPath) of
            {ok, SrcPayload} ->
                FinalDstPath = resolve_dst_path(DstKhepriPath, SrcPathComponents),
                UpdatedSrcPayload = SrcPayload#{created_at => Now, updated_at => Now},
                
                ok = khepri_tx:put(FinalDstPath, UpdatedSrcPayload),
                copy_children_tx(SrcKhepriPath, FinalDstPath, Now),
                ok;
            _ ->
                khepri_tx:abort(src_not_found)
        end
    end).

%% --- Private Helper Functions ---

build_path(Owner, PathComponents) when is_list(PathComponents) ->
    [kvfs, Owner | PathComponents];
build_path(Owner, Component) ->
    [kvfs, Owner, Component].

%% Resolusi path seperti perintah mv/cp di Unix
resolve_dst_path(DstKhepriPath, SrcPathComponents) ->
    case khepri_tx:get(DstKhepriPath) of
        {ok, #{type := directory}} ->
            Filename = lists:last(SrcPathComponents),
            DstKhepriPath ++ [Filename];
        _ ->
            DstKhepriPath
    end.

move_children_tx(SrcKhepriPath, FinalDstPath) ->
    ChildPattern = SrcKhepriPath ++ ['**'],
    case khepri_tx:get_many(ChildPattern) of
        {ok, ChildrenMap} ->
            maps:fold(
                fun(ChildPath, ChildPayload, ok) ->
                    RelativePath = ChildPath -- SrcKhepriPath,
                    NewChildPath = FinalDstPath ++ RelativePath,
                    ok = khepri_tx:put(NewChildPath, ChildPayload)
                end,
                ok,
                ChildrenMap
            );
        _ ->
            ok
    end.

copy_children_tx(SrcKhepriPath, FinalDstPath, Now) ->
    ChildPattern = SrcKhepriPath ++ ['**'],
    case khepri_tx:get_many(ChildPattern) of
        {ok, ChildrenMap} ->
            maps:fold(
                fun(ChildPath, ChildPayload, ok) ->
                    RelativePath = ChildPath -- SrcKhepriPath,
                    NewChildPath = FinalDstPath ++ RelativePath,
                    UpdatedChild = ChildPayload#{created_at => Now, updated_at => Now},
                    ok = khepri_tx:put(NewChildPath, UpdatedChild)
                end,
                ok,
                ChildrenMap
            );
        _ ->
            ok
    end.