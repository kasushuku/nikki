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

let () =
  Dream.run ~interface:"0.0.0.0" ~port
  @@ Dream.logger
  @@ Dream.router
       [
         Dream.get "/" (fun _ ->
             Dream.html
               (App.Views.Index.render ~author:"zkm" ~article_count:"999"));
         Dream.get "/all_posts.html" (fun _ ->
             Dream.html (App.Views.All_posts.render articles));
         Dream.get "/home_window.html" (fun _ ->
             Dream.html (App.Views.Home_window.render ()));
         Dream.get "/about.html" (fun _ ->
             Dream.html (App.Views.About.render ()));
         Dream.get "/articles/:id" (fun request ->
            let id = Filename.remove_extension (Dream.param request "id") in
             match App.Entry.find articles id with
             | Some a -> Dream.html (App.Views.Article.render a)
             | None -> Dream.empty `Not_Found);
         Dream.get "/healthz" (fun _ -> Dream.respond "ok");
         Dream.get "/assets/**" (Dream.static "web/assets");
       ]
