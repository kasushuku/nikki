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
- Dockerfile
- README.md
- devbox.json
- vercel.json
```

## 開発

```sh
dune build
PORT=8080 dune exec app/bin/main.exe
```

## Docker

```sh
docker build -t nikki .
docker run --rm -p 8080:8080 nikki
```

