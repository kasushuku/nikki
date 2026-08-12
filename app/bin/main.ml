(* Docker/Vercel向けの疎通確認用の最小SSRサーバー。
   ルーティングは app/server/routes.ml へ移す前提の暫定実装。 *)

let port =
  match Option.bind (Sys.getenv_opt "PORT") int_of_string_opt with
  | Some p -> p
  | None -> 8080

(* Dreamが処理するのはSIGINTのみ。Vercelはscale-in時にSIGTERM+30秒の猶予を
   送るため、明示的に終了させないと毎回SIGKILLまで待たされる。 *)
let () = Sys.set_signal Sys.sigterm (Sys.Signal_handle (fun _ -> exit 0))
let articles = App.Entry.load_dir "content/articles"

(* 検索indexは起動時に一度だけ組む。contentはビルド時にイメージへ焼き込まれ、
   プロセスの生存中は変化しない。 *)
let search_index = App.Search.build articles

let () =
  let open Dream in
  run ~interface:"0.0.0.0" ~port
  @@ logger
  @@ router
       [
         get "/" (fun _ ->
             html (App.Views.Index.render ~author:"zkm" ~article_count:"999"));
         get "/all_posts.html" (fun _ ->
             html (App.Views.All_posts.render articles));
         get "/home_window.html" (fun _ ->
             html (App.Views.Home_window.render articles));
         get "/about.html" (fun _ -> html (App.Views.About.render ()));
         get "/articles/:id" (fun request ->
             let id = Filename.remove_extension (Dream.param request "id") in
             match App.Entry.find articles id with
             | Some a -> html (App.Views.Article.render a)
             | None -> empty `Not_Found);
         (* htmxが #article-list へ差し込むfragmentを返す。
            q が空なら全件なので、クリアも同じendpointで足りる。 *)
         get "/search" (fun request ->
             let q = Dream.query request "q" |> Option.value ~default:"" in
             let hits =
               if String.trim q = "" then articles
               else App.Search.query search_index q
             in
             html (App.Views.Search_results.render ~q hits));
         get "/healthz" (fun _ -> respond "ok");
         get "/assets/**" (static "web/assets");
       ]
