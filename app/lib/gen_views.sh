set -e
tmp=$(mktemp -d); trap "rm -rf $tmp" EXIT

modname() { basename "$1" .html | sed "s/^./\U&/"; }

files=""
for f in "$@"; do case "$f" in *.html) files="$files $f" ;; esac; done

all_mods=""
for f in $files; do all_mods="$all_mods $(modname "$f")"; done

emit() {
  f=$1; M=$(modname "$f"); b=$(basename "$f" .html)
  sig=$(head -1 "$f" | sed -n "s/^[[:space:]]*<!--[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*-->[[:space:]]*$/\1/p")
  if [ -z "$sig" ]; then echo "gen_views.sh: $f に署名コメントがありません" >&2; exit 1; fi
  { echo "let $sig ="; tail -n +2 "$f"; } > "$tmp/$b.eml.html"
  echo "module $M = struct"
  dream_eml "$tmp/$b.eml.html" --stdout | sed "s|$tmp/$b.eml.html|$f|g"
  echo "end"; echo
}

echo "(* 生成物。編集しない。参照関係から定義順を決めている。 *)"
emitted=" "
remaining="$files"
while [ -n "$(echo $remaining)" ]; do
  progress=0; next=""
  for f in $remaining; do
    me=$(modname "$f"); ok=1
    for d in $(grep -oE "[A-Z][A-Za-z0-9_]*\." "$f" | tr -d "." | sort -u); do
      case " $all_mods " in *" $d "*) ;; *) continue ;; esac
      [ "$d" = "$me" ] && continue
      case "$emitted" in *" $d "*) ;; *) ok=0 ;; esac
    done
    if [ "$ok" = 1 ]; then emit "$f"; emitted="$emitted$me "; progress=1
    else next="$next $f"; fi
  done
  if [ "$progress" = 0 ]; then echo "gen_views.sh: 循環参照: $next" >&2; exit 1; fi
  remaining="$next"
done
