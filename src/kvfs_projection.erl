-module(kvfs_projection).

-include_lib("khepri/include/khepri.hrl").

-export([
    prepare/0,
    init/0,
    search_by_tag/1,
    get_user_quota/1,
    list_tag_index/0
]).

prepare() ->
    ensure_table(kvfs_tag_index, [bag, public, named_table, {read_concurrency, true}]),
    ensure_table(kvfs_user_quota, [set, public, named_table, {read_concurrency, true}]),
    ok.

init() ->
    ok = prepare(),

    PathPattern = [kvfs, ?KHEPRI_WILDCARD_STAR, ?KHEPRI_WILDCARD_STAR_STAR],

    %% Buat Projection Resource (tanpa opsi protection)
    TagProjection = khepri_projection:new(
        tag_indexer,
        fun handle_tag_projection/4
    ),

    QuotaProjection = khepri_projection:new(
        quota_indexer,
        fun handle_quota_projection/4
    ),

    %% Daftarkan proyeksi ke Khepri
    ok = register_projection(PathPattern, TagProjection),
    ok = register_projection(PathPattern, QuotaProjection),
    ok.

ensure_table(Name, Options) ->
    case ets:whereis(Name) of
        undefined ->
            _ = ets:new(Name, Options),
            ok;
        _Tid ->
            ok
    end.

register_projection(PathPattern, Projection) ->
    Name = khepri_projection:name(Projection),
    case khepri:register_projection(PathPattern, Projection) of
        ok ->
            ok;
        {error, {khepri, projection_already_exists, #{name := Name}}} ->
            ok;
        {error, _Reason} = Error ->
            Error
    end.

%% --- API Publik ---

search_by_tag(Tag) ->
    case ets:lookup(kvfs_tag_index, Tag) of
        [] ->
            [];
        Entries ->
            [Path || {_Tag, Path} <- Entries]
    end.

get_user_quota(Owner) ->
    case ets:lookup(kvfs_user_quota, Owner) of
        [{Owner, TotalSize, FileCount}] ->
            {ok, #{owner => Owner, total_bytes => TotalSize, file_count => FileCount}};
        [] ->
            {ok, #{owner => Owner, total_bytes => 0, file_count => 0}}
    end.

list_tag_index() ->
    ets:tab2list(kvfs_tag_index).

%% --- Extended Projection Callbacks (Tids, Path, OldProps, NewProps) ---

handle_tag_projection(_Tids, Path, _OldProps, #{data := #{type := file, tags := Tags}}) ->
    update_tag_index(Path, Tags);
handle_tag_projection(_Tids, Path, #{data := #{type := file}}, _NewProps) ->
    ets:match_delete(kvfs_tag_index, {'_', Path});
handle_tag_projection(_Tids, _Path, _OldProps, _NewProps) ->
    ok.

update_tag_index(Path, Tags) when is_list(Tags) ->
    ets:match_delete(kvfs_tag_index, {'_', Path}),
    lists:foreach(
        fun(Tag) ->
            ets:insert(kvfs_tag_index, {Tag, Path})
        end,
        Tags
    ).

handle_quota_projection(_Tids, [kvfs, Owner | _Rest], OldProps, NewProps) ->
    update_quota(Owner, OldProps, NewProps);
handle_quota_projection(_Tids, _Path, _OldProps, _NewProps) ->
    ok.

update_quota(Owner, OldProps, NewProps) ->
    {OldSize, OldCount} = file_contribution(OldProps),
    {NewSize, NewCount} = file_contribution(NewProps),
    case ets:lookup(kvfs_user_quota, Owner) of
        [{Owner, CurrentSize, CurrentCount}] ->
            ets:insert(kvfs_user_quota, {
                Owner,
                CurrentSize - OldSize + NewSize,
                CurrentCount - OldCount + NewCount
            });
        [] ->
            ets:insert(kvfs_user_quota, {Owner, NewSize, NewCount})
    end.

file_contribution(#{data := #{type := file, size := Size}}) ->
    {Size, 1};
file_contribution(_Props) ->
    {0, 0}.