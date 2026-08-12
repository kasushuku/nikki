(* 記事の全文検索。vendor/search（ocaml-search）のインメモリTF-IDF indexを使う。

   indexは起動時にメモリ上へ組み立てる。§11.3の通りcontentはビルド時に
   イメージへ焼き込まれ、プロセスの生存中に増減しないため、これで足りる。 *)

(* --- tokenise -------------------------------------------------------------

   ocaml-search の既定tokeniserは空白splitなので、日本語の本文が丸ごと
   1 tokenになって検索できない。文字n-gramに差し替える。 *)

(* UTF-8を1 code pointずつに切る。OCaml 4.14以降の String.get_utf_8_uchar で
   足りるので uutf は要らない。不正なUTF-8でも utf_decode_length が1以上を
   返すので停止する。 *)
let utf8_chars s =
  let n = String.length s in
  let rec go i acc =
    if i >= n then List.rev acc
    else
      let len = Uchar.utf_decode_length (String.get_utf_8_uchar s i) in
      go (i + len) (String.sub s i len :: acc)
  in
  go 0 []

let is_separator c =
  match c with
  | " " | "\t" | "\n" | "\r" | "\u{3000}" -> true
  | _ -> false

(* 空白で区切った範囲の中だけでunigramとbigramを作る。区切りをまたぐbigramは
   作らない。unigramも入れるのは、1文字のqueryを空振りさせないため。
   indexは文字数のおよそ2倍のtokenを持つ。

   bigramを先に置くのは query 側の都合。M.search は渡された文字列を
   もう一度この関数に通し、その **先頭token** だけで候補を絞る。unigramが
   先頭に来ると、bigram "co" での検索が実質 unigram "c" での検索になり、
   c/o/d/e を含むだけの記事が "code" にヒットしてしまう。 *)
let ngrams run =
  let rec bigrams = function
    | a :: (b :: _ as rest) -> (a ^ b) :: bigrams rest
    | _ -> []
  in
  bigrams run @ run

let tokeniser s =
  let rec split acc cur = function
    | [] -> List.rev (List.rev cur :: acc)
    | c :: rest ->
        if is_separator c then split (List.rev cur :: acc) [] rest
        else split acc (c :: cur) rest
  in
  utf8_chars s |> split [] [] |> List.concat_map ngrams

(* --- index ---------------------------------------------------------------- *)

(* abst / body にはHTMLが直接入っている。タグ名や属性がヒットしないよう落とす。 *)
let strip_tags s =
  let b = Buffer.create (String.length s) in
  let rec go i inside =
    if i >= String.length s then Buffer.contents b
    else
      match s.[i] with
      | '<' -> go (i + 1) true
      (* タグを閉じたら空白を置く。前後の文字でbigramを作らないため。 *)
      | '>' ->
          if inside then Buffer.add_char b ' ';
          go (i + 1) false
      | c ->
          if not inside then Buffer.add_char b c;
          go (i + 1) inside
  in
  go 0 false

module M =
  Tfidf_search.Tfidf.Mono
    (Tfidf_search.Uids.String)
    (struct
      type t = Entry.t
    end)

module Ids = Set.Make (String)

type t = M.t

let build (articles : Entry.t list) =
  (* 既定のstrategyは前方一致展開（"abc" → "a"; "ab"; "abc"）。これはbyte単位の
     String.sub なので、マルチバイト文字に当てると壊れたUTF-8がindexへ入る。
     n-gramを自前で作っている以上不要でもあるので、恒等にする。 *)
  let idx = M.empty ~strategy:(fun t -> [ t ]) ~tokeniser () in
  M.add_indexes idx
    [
      (fun (a : Entry.t) -> a.title);
      (fun (a : Entry.t) -> strip_tags a.abst);
      (fun (a : Entry.t) -> strip_tags a.body);
      (fun (a : Entry.t) -> a.category);
      (fun (a : Entry.t) -> a.author);
    ];
  List.iter (fun (a : Entry.t) -> M.add_document idx a.id a) articles;
  idx

(* --- query ---------------------------------------------------------------- *)

let take n l =
  let rec go n acc = function
    | x :: rest when n > 0 -> go (n - 1) (x :: acc) rest
    | _ -> List.rev acc
  in
  go n [] l

(* M.search は query の先頭tokenだけで候補を絞り、2つ目以降はTF-IDFの
   スコアにしか効かない（vendor/README.md「既知の癖」）。そのままだと
   先頭の2文字がindexに無いだけで結果が空になる。
   絞り込みは token ごとの検索の積で自前に行い、並び順はライブラリの
   TF-IDFに任せる。全token一致の集合は先頭token一致の集合の部分集合なので、
   M.search idx q の結果を filter すれば順位を保ったまま取り出せる。 *)
let query ?(limit = 50) idx q =
  let q = String.lowercase_ascii (String.trim q) in
  match tokeniser q with
  | [] | [ "" ] -> []
  | first :: rest ->
      let ids token =
        M.search idx token
        |> List.map (fun (a : Entry.t) -> a.id)
        |> Ids.of_list
      in
      let matched =
        List.fold_left (fun acc t -> Ids.inter acc (ids t)) (ids first) rest
      in
      if Ids.is_empty matched then []
      else
        M.search idx q
        |> List.filter (fun (a : Entry.t) -> Ids.mem a.id matched)
        |> take limit
