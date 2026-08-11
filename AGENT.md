# AGENT.md

このrepositoryでエージェント（Claude Code等）が作業するときの規約。

## 役割分担

**コードの理解と実装は人間が行う。エージェントはそのアシストに徹する。**

### やってよいこと

- 質問への回答、設計の検討、コードの読解と説明
- バグ修正のコード変更
- `docs/` と `README.md` の更新
- ローカルでの検証コマンド実行（`dune build`、`docker build`、`curl` など）

### 事前に許可を取ること

- **git commit** — 作成前に必ず提案し、許可を得てから行う。実装の進捗上コミットを分割すべき箇所では、提案 → 許可 → コミット の順を守る。
- **外部に影響する操作** — `vercel deploy` / `vercel promote`、`git push`、PRの作成など。

### やらないこと

- 機能の本格的な追加実装。新機能は人間が書く。
- 依頼されていないリファクタリングや設計変更。

## コードの出し方

実装のアシストで示すコードは、**会話内のスニペットまで**とする。ファイルへ直接書き込むのは、バグ修正と `docs/`・`README.md` の更新に限る。

「書いて」と明示された場合はその限りではない。

## 報告の仕方

- 検証したことと、していないことを区別する。ローカルで実行して確認したなら、そのコマンドと結果を示す。していないなら「未検証」と明記する。
- 推測を事実として書かない。

## プロジェクト

共同日記ポータル。個人ポータルと身内向けブログを兼ねる。

**設計の正は [`docs/diary-architecture.md`](docs/diary-architecture.md)。** 実装より先にこちらを読む。記事本体は別repository `nikki-content` を `content/` にsubmoduleとして持つ。

構成は Dream (OCaml) によるSSR + htmxによる部分更新 + Melangeによる高機能UI。デプロイ先は Vercel Functions のコンテナイメージ。

### コマンド

```sh
dune build
PORT=8080 dune exec app/bin/main.exe

docker build -f Dockerfile.vercel -t nikki .
docker run --rm -p 8080:8080 nikki

pnpm exec vercel curl <url>    # previewはDeployment Protectionで保護される
```

### 踏み抜きやすい点

一度踏んで直したもの。理由は括弧内の節に書いてある。

- dune projectのrootは **repo root**。`app/` ではない。root外はdune fileごと黙って無視される（§5.1）
- root の `dune` で `node_modules` と `docs` を走査対象から外している。`:standard` はdot始まり以外を全部拾うため（§5.4）
- Dockerfileの名前は **`Dockerfile.vercel`**。この名前でないとVercelが検出しない（§11.1）
- `vercel.json` に `framework` などビルド関連キーを書かない。Container presetが打ち消され、全pathが404になる（§11.1）
- `app/bin/main.ml` のSIGTERMハンドラはVercelのscale-in対策。消すと停止のたびに30秒待たされる（§11.1）
- Melange導入時、ビルド成果物はソースの `web/assets/generated/` ではなく `_build/default/` 側に出る（§5.2）

### branch運用

`main` がdefault branchで `origin` (github.com/kasushuku/nikki) がある。作業は `setup/*` などのbranchを切り、PR経由で `main` へ入れる。
