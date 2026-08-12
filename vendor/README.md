# vendor/

opamで解決せず、ソースをこのrepositoryへ取り込んだ第三者ライブラリを置く。

root の `dune` で `(vendored_dirs vendor)` を指定しているため、duneはここを
「vendorされたコード」として扱う。具体的には、このプロジェクトの `flags` や
warnings-as-error を適用せず、上流のコードをそのままビルドする。

## search

| 項目 | 内容 |
| --- | --- |
| 上流 | <https://github.com/patricoferris/ocaml-search> |
| 取り込んだcommit | `e903edd0bb61ef93c51ee152efdfc5e18268b114` (2023-01-11) |
| opam版 | `search.0.1.1` |
| License | MIT（`search/LICENSE` を同梱） |
| 依存 | なし（duneのみ。Cライブラリを引かない） |

インメモリの転置index + TF-IDF。`app/lib/search.ml` から使う。

取り込んだのは `src/` の6ファイルと `LICENSE` のみ。上流の `dune-project`、
`search.opam`、`test/` は入れていない。`dune` はopamパッケージとして配らない
ぶんだけ書き換えてあり、**OCamlソースは1文字も変更していない**。

### 既知の癖

`Tfidf.Mono.search` は、query を tokenise した結果の **先頭tokenだけ**で候補
文書を選ぶ。2つ目以降のtokenは絞り込みに寄与せず、TF-IDFのスコア計算にのみ
効く（`tfidf.ml` の `search` で、絞り込み用の `documents` が
`UidMap.empty` に束縛されたまま更新されないため）。

結果として先頭tokenがindexに無いと、後続のtokenが全てヒットしても検索結果は
空になる。`app/lib/search.ml` はこれを前提に、tokenごとに検索して結果を
統合する形で呼び出している。

### 更新手順

```sh
git clone --depth 1 https://github.com/patricoferris/ocaml-search /tmp/ocaml-search
cp /tmp/ocaml-search/src/*.ml /tmp/ocaml-search/src/*.mli vendor/search/
cp /tmp/ocaml-search/LICENSE vendor/search/
# vendor/search/dune は上書きしない
```

上流は2023年1月から更新されていない。
