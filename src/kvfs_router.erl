-module(kvfs_router).
-export([routes/0]).

routes() ->
    cowboy_router:compile([
        {'_', [
            {"/api/list/[...]", kvfs_http_handler, list_dir},
            {"/api/file/[...]", kvfs_http_handler, file_ops},
            {"/api/move", kvfs_http_handler, move_path},
            {"/api/copy", kvfs_http_handler, copy_path},
            {"/api/search/tag", kvfs_http_handler, search_tag},
            {"/api/quota/:owner", kvfs_http_handler, user_quota},
            {"/ws", kvfs_ws_handler, []},
            {"/static/[...]", cowboy_static, {priv_dir, kvfs, "static"}},
            {"/", cowboy_static, {priv_file, kvfs, "static/index.html"}}
        ]}
    ]).