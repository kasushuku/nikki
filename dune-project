(lang dune 3.23)

(name app)

(generate_opam_files true)

(source
 (github kasushuku/nikki))

(authors "kasushuku")

(maintainers "kasushuku")

(package
 (name app)
 (synopsis "Kasushuku shared diary portal")
 (description
  "SSR diary portal served by Dream, progressively enhanced with htmx and Melange")
 (depends
  (ocaml
   (>= 5.1))
  (dune
   (>= 3.23))
  dream
  yojson)
 (tags
  (diary dream htmx)))

; See the complete stanza docs at https://dune.readthedocs.io/en/stable/reference/dune-project/index.html
