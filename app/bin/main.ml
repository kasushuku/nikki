(* Docker/Vercel向けの疎通確認用の最小SSRサーバー。
   ルーティングは app/server/routes.ml へ移す前提の暫定実装。 *)

let port =
  match Option.bind (Sys.getenv_opt "PORT") int_of_string_opt with
  | Some p -> p
  | None -> 8080

let layout ~title body =
  Printf.sprintf
    {|<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>%s</title>
<link rel="stylesheet" href="/assets/app.css">
</head>
<body>
<header><a href="/">にっき.かすしゅく.みんな</a></header>
<main id="main">%s</main>
</body>
</html>|}
    title body

(* 同一canonical URLから完全ページとfragmentを返す。
   キャッシュが両者を混同しないよう Vary を必ず付ける。 *)
let page request ~title body =
  let headers = [ ("Vary", "HX-Request") ] in
  match Dream.header request "HX-Request" with
  | Some "true" -> Dream.html ~headers body
  | _ -> Dream.html ~headers (layout ~title body)

let index =
  {|<h1>にっき</h1>
<p>Dreamコンテナの疎通確認用ページ。content/ の取り込みは未実装。</p>|}

(* Dreamが処理するのはSIGINTのみ。Vercelはscale-in時にSIGTERM+30秒の猶予を
   送るため、明示的に終了させないと毎回SIGKILLまで待たされる。 *)
let () = Sys.set_signal Sys.sigterm (Sys.Signal_handle (fun _ -> exit 0))

let () =
  Dream.run ~interface:"0.0.0.0" ~port
  @@ Dream.logger
  @@ Dream.router
       [
         Dream.get "/" (fun request -> page request ~title:"にっき" index);
         Dream.get "/healthz" (fun _ -> Dream.respond "ok");
         Dream.get "/assets/**" (Dream.static "web/assets");
       ]
