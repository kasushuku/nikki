# 共同日記ポータル アーキテクチャ

## 1. 目的

個人ポータルと身内向けブログを兼ねた共同日記サイトを構築する。

- 日記は各自がローカルでMarkdownとして執筆し、GitHubへpushする。
- 初回表示と基本機能はSSRで成立させる。
- 通常の操作ではページ全体の再読み込みを避ける。
- 軽い部分更新にはhtmx、検索など状態や計算量の大きい機能にはMelangeを使う。
- option: 将来、複数人の日記をagentで整形・要約できるようにする。

## 2. 現時点の決定

| 領域 | 採用方針 |
| --- | --- |
| HTTPサーバー | OCaml Dream |
| レンダリング | DreamによるSSR |
| 部分更新 | htmx |
| 高機能UI | Melangeでブラウザ向けJavaScriptを生成 |
| 共通データ型 | Native/Melangeで共有できるOCamlモジュール |
| コンテンツ | Markdown・画像をGitで管理 |
| Dune project root | repository root（`app/` ではない。§5参照） |
| デプロイ | Vercel Functions のコンテナイメージ |

## 3. 責務の境界

### Client

#### Views / htmx

`web/views/` と `web/assets/` に配置する。

- 完全なHTMLページ
- htmxへ返すHTML fragment
- `hx-get`、`hx-post`、`hx-target`、`hx-swap`、`hx-push-url` などの属性
- CSSとhtmx本体
- option: 共通のcss class schemeを規定してボタンでcss libraryをinteractiveに変えられるとよい

#### UI

`app/ui/` に配置し、Melangeでブラウザ向けにビルドする。

- 検索UI
- 検索indexの読み込みとランキング
- Web Worker
- 複雑な入力状態
- htmxによるDOM差し替え後の再初期化

全面的なSPAにはせず、機能単位でマウントする。常駐する小さな `shell.ml` が `htmx:load` を監視し、`data-component` を持つ要素を初期化する。

```html
<div
  data-component="search"
  data-index-url="/assets/generated/search-index.json">
</div>
```

### Server

#### Server / dream

`app/server/` に配置する。

- Dreamの起動とルーティング
- 認証・認可
- Gitから取り込まれたコンテンツの読み込み
- Markdownのパース
- SSR用データの準備
- HTMLまたはJSONレスポンスの選択
- privateな記事を対象にした検索
- privateな記事の添付画像の配信（§10）
- 将来のagent実行制御

#### Shared schema

`app/shared/` に配置する。

- `Author`
- `Entry`
- `Visibility`
- `Search_document`
- `Search_result`
- JSON codec

この階層はDream、Lwt、DOM、Node.jsなどに依存させない。NativeとMelangeの双方からコンパイルできるOCamlに限定する。ただしJSON codecは「純粋OCaml」だけでは両対応にならない。§5.3を参照。

## 4. Repository構成

アプリケーションとコンテンツを別repositoryにする。

### nikki

```text
nikki/
├── dune-project               # Dune projectのroot（repo root）
├── app.opam                   # duneが生成
├── dune                       # 走査範囲の制御（dirs / data_only_dirs）
├── app/
│   ├── server/
│   │   ├── dune
│   │   ├── main.ml
│   │   ├── routes.ml
│   │   ├── content.ml
│   │   ├── search.ml
│   │   └── agent.ml
│   ├── ui/
│   │   ├── dune
│   │   ├── shell.ml
│   │   ├── search.ml
│   │   └── search_worker.ml
│   └── shared/
│       ├── dune
│       ├── author.ml
│       ├── entry.ml
│       ├── visibility.ml
│       └── search.ml
├── web/
│   ├── views/
│   │   ├── pages/
│   │   └── fragments/
│   └── assets/
│       ├── app.css
│       ├── vendor/htmx.min.js
│       └── generated/         # Melange出力。Git管理外
├── vendor/                    # opamで解決せず取り込んだ第三者ライブラリ
│   └── search/                # ocaml-search（§9）
├── content/                   # nikki-contentへのGit submodule
├── Dockerfile.vercel          # この名前でVercelが自動検出する（§11.1）
├── vercel.json
├── package.json               # vercel CLIをlocalに置くためだけのもの
└── README.md
```

### nikki-content

```text
nikki-content/
├── authors/
│   ├── zukimo/
│   │   ├── profile.md
│   │   └── avatar.webp
│   └── miya/
│       ├── profile.md
│       └── avatar.webp
├── diaries/
│   └── zukimo/
│       └── 20260811/
│           ├── index.md
│           └── breakfast.png
└── summaries/
    └── 20260811.md
```

記事は「1記事1ディレクトリ」とする。記事をファイル1枚（`zukimo/20260811.md`）にすると、Markdown中の `./breakfast.png` が著者ディレクトリ直下に解決され、日付をまたいで画像名が衝突する。ディレクトリを切れば相対パスが記事内で閉じる。

`nikki/content` から `nikki-content` の特定commitをsubmoduleとして参照する。これにより、本番デプロイが使用した記事の版を再現できる。

## 5. Build構成

### 5.1 Dune projectのroot

`dune-project` はrepository rootに置く。`app/` の内部で完結させることはできない。

duneには2つの制約がある。

1. ruleの `target` は、そのruleを書いたディレクトリの中にしか置けない。`../../web/assets/generated/search-index.json` のようなパスは `does not denote a file in the current directory` で拒否される。
2. project rootの外はファイルツリーの走査対象にならない。root外に置いた `dune` ファイルはエラーも出さずに黙って無視される。

したがってrootを `app/` にすると、

- §9の検索index生成（`web/assets/generated/` への出力）ができない。Melangeの `melange.emit` も出力先がproject内に限られる。
- `web/views/` のDreamテンプレート（`.eml`）を `dream_eml` で前処理するdune ruleが読まれない。

`web/` をdune projectの中に入れる必要があるため、rootをrepo rootへ上げる。

### 5.2 ビルド成果物の置き場所

duneは原則としてソースツリーへ書き戻さない。`web/assets/generated/search-index.json` やMelangeの出力は、ソースの `web/assets/generated/` ではなく `_build/default/web/assets/generated/` に出る。

したがって次のどちらかを選ぶ。

- サーバーの静的配信を `_build` 側の出力ディレクトリに向ける。
- ruleに `(mode promote)` を付けてソースツリーへコピーバックする。

Dockerfileでも、Melangeを導入した時点で静的アセットをビルドコンテキストの `web/` ではなく build stage の `_build/default/web/assets` から取る必要がある。

### 5.3 shared schemaの両対応

型定義は純粋OCamlで両対応にできるが、JSON codecはそのままでは成立しない。Yojsonはnative専用で、`[@@deriving yojson]` はMelangeで動かない。

方針を次のいずれかに決める。

- `melange-json` と `melange-json-native` を併用し、両側で同じ `[@@deriving json]` を通す。（推奨）
- `JSON` signatureに対するfunctorとして書き、native/Melangeそれぞれにadapterを置く。

dune側では、shared libraryに `(modes :standard melange)` が要る。

### 5.4 走査範囲

rootがrepo rootになったため、duneは `content/` や `docs/` まで走査して `_build` へコピーしようとする。`content/` には写真が入るので、rootの `dune` で制御する。

```dune
(data_only_dirs content)
(dirs :standard \ docs node_modules)
```

`data_only_dirs` にすると、duneはdune fileを探さずデータとしてだけ扱う。将来のビルド時index生成で依存に取れる。

`node_modules/` はvercel CLIをglobalに入れずlocalへ置いた結果できるもので、252MBある。`:standard` はdot始まり・underscore始まり以外のすべてのディレクトリを拾うため、除外しないとduneがこれを走査する。

### 5.5 Melangeのversion

MelangeとDreamを同一opam switchで満たせるOCaml versionを固定する。現在の検証環境はOCaml 5.3 / dream 1.0.0~alpha8。Melange導入時にここを再確認する。

## 6. Markdown形式

日記はfront matter付きMarkdownとする。

```markdown
---
id: zukimo-2026-08-11
author: zukimo
date: 2026-08-11T08:30:00+09:00
visibility: family
tags:
  - morning
  - food
---

# 朝の日記

今日は少し早く起きた。

![朝食](./breakfast.png)
```

- 画像は記事ディレクトリ（`diaries/:author/:date/`）に置き、Markdownでは相対パスを使う。
- 相対パスはサーバー側で `/media/:author/:date/:file` に書き換える。生の `content/` を静的配信してはならない（§10.2）。
- 日付はJSTで扱う。front matterはoffset付きで書き、表示時にJSTへ正規化する。

## 7. URL設計

SSRとhtmxはURLを設計の中心に置く。以下は提案であり、実装時に確定する。

| path | 内容 | 認可 |
| --- | --- | --- |
| `/` | 最新の日記一覧 | visibilityで絞り込み |
| `/d/:author/:date` | 記事のpermalink | 記事のvisibility |
| `/a/:author` | 著者ページ | 公開 |
| `/t/:tag` | タグ一覧 | visibilityで絞り込み |
| `/search?q=` | 検索結果 | §9 |
| `/media/:author/:date/:file` | 記事の添付画像 | 記事のvisibility |
| `/assets/**` | CSS・htmx・検索index | 公開 |
| `/healthz` | 死活監視 | 公開 |

`/d/`、`/a/`、`/t/`、`/search` は同一URLで完全ページとfragmentの両方を返す（§8）。

ページネーションの方式（page番号かcursorか）は未決定。

## 8. SSR・htmx・Melangeの連携

### 初回表示

Dreamが完全なHTMLをサーバーサイドでレンダリング。JavaScriptが無効でも記事閲覧と基本検索が成立する形を目標にする。

### ページ遷移

ナビゲーションはhtmxで差し替え、必要に応じてhistoryも更新する。

- 通常リクエストには完全なページを返す。
- `HX-Request` を持つリクエストには `<main>` 相当のfragmentを返す。
- キャッシュが両者を混同しないよう、レスポンスに `Vary: HX-Request, Cookie` を設定する。`Cookie` を含めないと、edge cacheに認証済みの内容と未認証の内容が混ざる。
- URLは `hx-push-url` または `HX-Push-Url` で更新する。

同一のcanonical URLから完全ページとfragmentを返す方式を基本とし、HTML断片専用endpointは再利用性が高い部品に限定する。

### 認証切れの扱い

htmxリクエストに対して401で302を返すと、ログインページがそのまま `<main>` へ差し込まれる。htmxリクエストと判定した場合は `HX-Redirect` ヘッダを返し、ブラウザ側でページ遷移させる。

### CSRF

Dreamの `Dream.csrf_tag` はform前提。htmxのPOSTでtokenをどう載せるか（hidden inputか `hx-headers` か）を最初に規約として決め、全fragmentで揃える。

### Melange機能の再マウント

htmxがDOMを差し替えると、Melangeの対象要素も新しくなる。`app/ui/shell.ml` が `htmx:load` を購読し、対象要素を探索して機能をマウントする。

htmxとMelangeを直接依存させず、接続面を次に限定する。

- `data-*` 属性
- DOM event
- HTTP/JSON
- shared schema

## 9. 検索

検索はSSRを基準にし、Melangeで強化する。

### 公開コンテンツ

1. ビルド時に検索index生成処理を実行する。
2. Markdownから検索documentを生成する。
3. `web/assets/generated/search-index.json` を出力する（実体の置き場所は§5.2）。
4. Melangeがindexを読み込み、ブラウザ内で検索・ランキングする。
5. 必要になればWeb Workerへ移す。

### 非公開コンテンツ

非公開記事の全文indexをブラウザへ配布しない。Dreamの認証付き検索endpointへqueryを送り、閲覧権限で絞り込んだ結果だけを返す。

### SSR fallback

`GET /search?q=...` はサーバー検索結果をSSRする。Melangeが利用できる場合は、画面遷移なしのインクリメンタル検索へ切り替える。

### サーバー側の実装（決定済み）

インメモリの転置index + TF-IDF。ライブラリは [ocaml-search](https://github.com/patricoferris/ocaml-search) を `vendor/search/` へ取り込んで使う（`vendor/README.md`）。opamで解決せずvendorしたのは、依存がduneだけでCライブラリを引かず、イメージサイズに響かないため。SQLite FTS5も候補だったが、libsqlite3を足すコストに見合わないと判断した。

- indexは `app/bin/main.ml` の起動時に一度だけ組む。§11.3の通りcontentはビルド時にイメージへ焼き込まれ、プロセスの生存中に変化しないため、再構築の仕組みは要らない。
- tokenは**文字unigram + bigram**（`app/lib/search.ml`）。日本語は空白で語に切れないので、ライブラリ既定の空白splitでは本文が丸ごと1 tokenになる。形態素解析は入れていない。
- 絞り込みは全token一致（AND）、並び順はライブラリのTF-IDF。
- `abst` / `body` はHTMLを含むので、indexに入れる前にタグを落とす。

実測（合成コーパス、1記事あたり本文1550字）。

| 記事数 | index構築 | 1 query |
| --- | --- | --- |
| 50 | 0.06s | 1.2ms |
| 200 | 0.31s | 7.8ms |
| 500 | 0.76s | 25.3ms |

index構築時間はcold startにそのまま乗る。§11.1の通りほぼ全アクセスがcold startになるので、記事数が数百を超えたらビルド時にindexを作って焼き込む方式へ移す判断が要る。

ブラウザ側（Melange）のindex形式は未決定。`vendor/search` はdune以外に依存しないが `(modes melange)` 付きでは公開されていないため、そのままではMelangeから使えない。

## 10. 認証と可視性

認証方式は§8のキャッシュ戦略、§9の検索、§10.2の画像配信のすべてに影響する。他の設計より先に決める。

### 10.1 認証方式（未決定）

候補。

- Dreamのsession cookie + 共有パスワード。実装が最も軽い。
- GitHub OAuth。執筆者がGitHubアカウントを持つ前提と一致する。
- リバースプロキシ層での認証。ただしVercel Functionsのコンテナは Secure Compute と Static IP に非対応のため、ネットワーク層での絞り込みは使えない。

### 10.2 privateな添付画像

`content/` を素の静的配信（`Dream.static "content"`）に載せてはならない。`visibility: family` の記事の画像がURL直打ちで取得できてしまう。

- 添付画像は `/media/:author/:date/:file` で受け、記事本文と同じ認可を通す。
- privateな応答には `Cache-Control: private, no-store` を付ける。

## 11. デプロイと同期

### 11.1 Vercel Functionsのコンテナ

Vercelの「コンテナ」は常駐コンテナではなくVercel Functionsとして動く。以下の制約が設計に効く。

| 事項 | 内容 |
| --- | --- |
| Dockerfileの検出 | root の `Dockerfile.vercel` / `Containerfile.vercel` を自動検出し、全traffic をコンテナへ流すrewriteを自動で足す。`vercel.json` に `services` を書く必要はない |
| Framework Preset | 検出結果は `Container`。`vercel.json` に `"framework": null` を書くとこれが打ち消され、静的デプロイになって全pathが404になる（実際に踏んだ） |
| listen port | 既定は80。`PORT` 環境変数で上書きする。イメージの `ENV PORT` も有効（8080で動作確認済み） |
| architecture | linux/amd64 |
| scale to zero | 無通信5分（previewは30秒）で停止する |
| 停止signal | SIGTERM + 30秒の猶予。Dreamが標準で扱うのはSIGINTのみなので、SIGTERMハンドラを明示的に入れる |
| イメージ制限 | 圧縮レイヤ1つあたり500MB、総サイズ15GB |
| Preview の保護 | Deployment Protectionが既定で有効。素のcurlは302になる。確認には `vercel curl` を使うとbypass tokenを自動生成してくれる |
| promote | `vercel promote` はpreviewのイメージを流用せず、本番デプロイを作り直してビルドし直す。previewで検証してからpromoteしても、もう一度ビルド時間がかかる |
| 非対応 | Secure Compute、Static IP |

`vercel.json` はコンテナ運用では実質空でよい。書くとしても `framework` や `outputDirectory` のようなビルド関連のキーは触らない。

低トラフィックの身内向けサイトでは、事実上ほとんどのアクセスがcold startになる。起動時間はイメージのpullが支配するため、イメージサイズを小さく保つことが体感速度に直結する。

§11.3の通りcontentはイメージへ焼き込むため、写真が増えるとレイヤの500MB制限に近づく。上限に当たる前に、画像だけを別の静的配信へ切り出す判断が要る。

### 11.2 Branchの役割

| Repository | Branch / PR | 用途 |
| --- | --- | --- |
| `nikki` | `main` | 本番アプリ |
| `nikki` | PR | アプリのPreview Deployment |
| `nikki-content` | `main` | 公開可能な記事 |
| `nikki-content` | PR | 下書き、校正、記事preview |

### 11.3 コンテンツの取り込み

runtimeでGitHub APIから毎回Markdownを取得する方式は採用しない。ビルド時に特定commitのcontentをコンテナへ取り込み、リクエスト処理を外部GitHub APIへ依存させない。

この方針の代償として、記事を1本追加するたびにイメージの再ビルドと再デプロイが発生する。Vercelのビルドマシン（2 core / 8GB）での実測は、キャッシュなしでイメージビルド **391秒**、デプロイ全体で **約7分**。opam依存の解決が大半を占めるので、依存を変えない限り2回目以降はレイヤキャッシュが効く見込み。投稿ごとに7分待つ運用が許容できるかは、この数字を見て判断する。

`nikki-content` をprivate repositoryにする場合、Vercelのgit integrationがsubmoduleを解決できない可能性がある。tokenを使ってビルド時に別途fetchする必要があるかを、最初のデプロイで確認する。

### 11.4 運用手順

1. `nikki-content` に記事をmergeする。
2. `nikki` でsubmodule参照を新しいcommitへ更新する。
3. Preview Deploymentで確認する。
4. `nikki/main` へmergeして本番へ反映する。

最初はsubmodule更新を手動で行う。投稿頻度が増えたら、`nikki-content/main` の更新を契機に `nikki` へsubmodule更新PRを作るGitHub Actionsを追加する。

### 11.5 観測

Vercelはコンテナの `stdout` / `stderr` をruntime logsとして拾う。ログはリクエストに紐づかず、そのインスタンスの全in-flightリクエストへ配信される点に注意する。

## 12. Optional. Agentによる要約

将来、複数人の日記を混ぜたdaily summaryを生成する。

推奨する流れはrequest時の即時生成ではなく、content更新後の非同期処理である。

1. 対象期間のMarkdownを収集する。
2. visibilityと閲覧対象を確認する。
3. agentへ構造化された入力を渡す。
4. summaryをMarkdownとして生成する。
5. `nikki-content/summaries/` へのPRを作る。
6. 人間が確認してmergeする。

これにより、生成結果をGitで監査・修正・再生成できる。プロンプト、provider、モデル、入力commit SHAも生成メタデータとして残す。

Codex App Serverが候補だが具体的なprovider構成は未決定とする。アプリケーション側ではprovider interfaceを用意し、特定providerへの依存をadapter内に限定する。

scale to zeroするFunctionの中でagentを実行するのは向かない。§11.1の通り無通信で停止するため、agent実行はGitHub Actions側に置くことを前提とする。

## 13. 現在の実装状況

疎通確認までを済ませた段階。

- `dune-project` をrepo rootへ移動済み。走査範囲を root の `dune` で制御。
- `app/bin/main.ml` に最小のDreamサーバー。`$PORT` 読み取り、`0.0.0.0` bind、`/`・`/healthz`・`/assets/**`、`HX-Request` による完全ページ/fragmentの出し分けと `Vary`、SIGTERMハンドラ。
- `Dockerfile.vercel` はmulti-stage（build: `ocaml/opam:debian-12-ocaml-5.3` / runtime: `debian:12-slim`）。イメージ152MB。
- Vercel本番で稼働中（`https://nikki-jade.vercel.app`）。`/`・`/healthz`・`/assets/app.css`・`HX-Request` fragment・404のすべてが期待通り。`Vary: HX-Request` もedgeを通過して保持される。
- vercel CLIはglobalに入れず、`package.json` のdevDependencyとして持つ。

- サーバー側の全文検索。`vendor/search` + `app/lib/search.ml` + `GET /search`。htmxで `#article-list` を差し替える。Dockerイメージ上で疎通確認済み。

未着手。

- `app/server/`、`app/shared/`、`app/ui/` への分割
- Markdownのパースとcontentの読み込み
- Melangeの導入
- 認証
- ブラウザ側（Melange）の検索
- 非公開記事を除外する検索（§9・認証に依存）

## 14. 未決定事項

先に決めるほど他への影響が小さくなる順。

1. 認証方式（§10.1）。§8のキャッシュ、§9の検索、§10.2の画像配信がこれに依存する。
2. shared schemaのJSON codec方針（§5.3）。
3. `nikki-content` をprivateにした場合のsubmodule解決方法（§11.3）。
4. ブラウザ側（Melange）の検索index形式（§9）。サーバー側は決定済み。
5. URL設計の確定とページネーション方式（§7）。
6. ビルド成果物をpromoteするかどうか（§5.2）。
7. Dreamとagent processの分離方法（§12）。
8. content更新からPreview Deploymentまでの自動化（§11.4）。
9. RSS/Atom feed、404/500ページの扱い。

## 15. 参考資料

- [</> htmx](https://htmx.org/)
- [OCaml Dream](https://camlworks.github.io/dream/)
- [OCaml Melange](https://melange.re/v7.0.1/)
- [Vercel Container Registry](https://vercel.com/docs/container-registry)
- [Vercel Functions / Container Images](https://vercel.com/docs/functions/container-images)
- [dune / dune-project](https://dune.readthedocs.io/en/stable/reference/dune-project/index.html)
