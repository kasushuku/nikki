# にっき.かすしゅく.みんな

## ディレクトリ構成

```
- dune-project: Dune projectのroot（repo root。docs/diary-architecture.md §5参照）
- dune: duneの走査範囲の制御
- app.opam: duneが生成
- app/: backend Dream; web-ui Melange
- web/: webpage view htmx
- content/: source articles @submodule
- docs/
- Dockerfile.vercel: この名前でVercelが自動検出する
- README.md
- devbox.json
- vercel.json
- package.json: vercel CLIをlocalに置くためだけのもの
```

## 開発

```sh
dune build
PORT=8080 dune exec app/bin/main.exe
```

## Docker

```sh
docker build -f Dockerfile.vercel -t nikki .
docker run --rm -p 8080:8080 nikki
```

## デプロイ

vercel CLIはglobalに入れず、pnpmでlocalに置いている。

```sh
pnpm deploy        # preview
pnpm deploy:prod   # production
```

previewはDeployment Protectionで保護されるため、確認には `vercel curl` を使う。

```sh
pnpm exec vercel curl <preview-url>/healthz
```

