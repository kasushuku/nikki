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
| 共通データ型 | Native/Melangeで共有できる純粋なOCamlモジュール |
| コンテンツ | Markdown・画像をGitで管理 |
| デプロイ | Vercelのコンテナ環境 |

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
  data-index-url="/assets/search-index.json">
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
- 将来のagent実行制御

#### Shared schema

`app/shared/` に配置する。

- `Author`
- `Entry`
- `Visibility`
- `Search_document`
- `Search_result`
- JSON codec

この階層はDream、Lwt、DOM、Node.jsなどに依存させない。NativeとMelangeの双方からコンパイルできる純粋なOCamlに限定する。

## 4. Repository構成

アプリケーションとコンテンツを別repositoryにする。

### nikki

```text
nikki/
├── app/                       # Dune projectのルート
│   ├── dune-project
│   ├── app.opam
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
│   │   ├── dune
│   │   ├── author.ml
│   │   ├── entry.ml
│   │   ├── visibility.ml
│   │   └── search.ml
├── web/
│   ├── views/
│   │   ├── pages/
│   │   └── fragments/
│   └── assets/
│       ├── app.css
│       ├── vendor/htmx.min.js
│       └── generated/         # Melange出力。Git管理外
├── content/                   # nikki-contentへのGit submodule
├── Dockerfile
├── vercel.json
└── README.md
```

Dune projectは `app/` の内部で完結させる。

```sh
dune build --root app
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
│   └── alice/
│       └── 20260811.md
└── summaries/
    └── 20260811.md
```

`nikki/content` から `nikki-content` の特定commitをsubmoduleとして参照する。これにより、本番デプロイが使用した記事の版を再現できる。

## 5. Markdown形式

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

- 画像は記事ディレクトリに置き、Markdownでは相対パスを使う。
- (それぞれのrepoからfetchすることを考えるとここは柔軟にすべきか)


## 6. SSR・htmx・Melangeの連携

### 初回表示

Dreamが完全なHTMLをサーバーサイドでレンダリング。JavaScriptが無効でも記事閲覧と基本検索が成立する形を目標にする。

### ページ遷移

ナビゲーションはhtmxで差し替え、必要に応じてhistoryも更新する。

- 通常リクエストには完全なページを返す。
- `HX-Request` を持つリクエストには `<main>` 相当のfragmentを返す。
- キャッシュが両者を混同しないよう、レスポンスに `Vary: HX-Request` を設定する。
- URLは `hx-push-url` または `HX-Push-Url` で更新する。

同一のcanonical URLから完全ページとfragmentを返す方式を基本とし、HTML断片専用endpointは再利用性が高い部品に限定する。

### Melange機能の再マウント

htmxがDOMを差し替えると、Melangeの対象要素も新しくなる。`app/ui/shell.ml` が `htmx:load` を購読し、対象要素を探索して機能をマウントする。

htmxとMelangeを直接依存させず、接続面を次に限定する。

- `data-*` 属性
- DOM event
- HTTP/JSON
- shared schema

## 7. 検索

検索はSSRを基準にし、Melangeで強化する。

### 公開コンテンツ

1. ビルド時に検索index生成処理を実行する。
2. Markdownから検索documentを生成する。
3. `web/assets/generated/search-index.json` を出力する。
4. Melangeがindexを読み込み、ブラウザ内で検索・ランキングする。
5. 必要になればWeb Workerへ移す。

### 非公開コンテンツ

非公開記事の全文indexをブラウザへ配布しない。Dreamの認証付き検索endpointへqueryを送り、閲覧権限で絞り込んだ結果だけを返す。

### SSR fallback

`GET /search?q=...` はサーバー検索結果をSSRする。Melangeが利用できる場合は、画面遷移なしのインクリメンタル検索へ切り替える。

## 9. デプロイと同期

### Branchの役割

| Repository | Branch / PR | 用途 |
| --- | --- | --- |
| `nikki` | `main` | 本番アプリ |
| `nikki` | PR | アプリのPreview Deployment |
| `nikki-content` | `main` | 公開可能な記事 |
| `nikki-content` | PR | 下書き、校正、記事preview |

### 最初の運用

1. `nikki-content` に記事をmergeする。
2. `nikki` でsubmodule参照を新しいcommitへ更新する。
3. Preview Deploymentで確認する。
4. `nikki/main` へmergeして本番へ反映する。

最初はsubmodule更新を手動で行う。投稿頻度が増えたら、`nikki-content/main` の更新を契機に `nikki` へsubmodule更新PRを作るGitHub Actionsを追加する。

runtimeでGitHub APIから毎回Markdownを取得する方式は採用しない。ビルド時に特定commitのcontentをコンテナへ取り込み、リクエスト処理を外部GitHub APIへ依存させない。

## Optional. Agentによる要約

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

## 12. 保留事項

- 身内向け記事の認証方式。
- 公開検索indexの形式と検索アルゴリズム。
- Dreamとagent processの分離方法。
- content更新からPreview Deploymentまでの自動化。

## 13. 参考資料

- [</> htmx](https://htmx.org/)
- [OCaml Dream](https://camlworks.github.io/dream/)
- [OCaml Melange](https://melange.re/v7.0.1/)
- [Vercel Container Registry](https://vercel.com/docs/container-registry)
