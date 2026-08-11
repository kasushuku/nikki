set -e
tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT
echo "(* 生成物。編集しない。元は web/views/*.html *)"
for f in "$@"; do
  case "$f" in *.html) ;; *) continue ;; esac
  m=$(basename "$f" .html)
  M=$(printf "%s" "$m" | sed "s/^./\U&/")

  # 1行目のHTMLコメントを関数の署名として使う。
  # ここを必須にしているのは行番号を合わせるため。コメント1行が
  # "let ... =" 1行に置き換わるので、エラー位置が元のhtmlとズレない。
  sig=$(head -1 "$f" | sed -n "s/^[[:space:]]*<!--[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*-->[[:space:]]*$/\1/p")
  if [ -z "$sig" ]; then
    echo "gen_views.sh: $f の1行目に署名コメントがありません。" >&2
    echo "  例: <!-- render ~author -->   引数が無いなら <!-- render () -->" >&2
    exit 1
  fi

  { echo "let $sig ="; tail -n +2 "$f"; } > "$tmp/$m.eml.html"
  echo "module $M = struct"
  # dream_emlが埋める行番号情報を、一時ファイルから元のhtmlへ書き戻す
  dream_eml "$tmp/$m.eml.html" --stdout | sed "s|$tmp/$m.eml.html|$f|g"
  echo "end"
  echo
done
