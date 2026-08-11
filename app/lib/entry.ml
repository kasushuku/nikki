type t = {
  id : string;
  title : string;
  author : string;
  date : string;
  category : string;
  abst : string;
  body : string;
}

let of_json ~id j =
  let open Yojson.Safe.Util in
  let s k = j |> member k |> to_string in
  {
    id;
    title = s "title";
    author = s "author";
    date = s "date";
    category = s "category";
    abst = s "abst";
    body = s "body";
  }

let load_file path =
  Yojson.Safe.from_file path
      |> Yojson.Safe.Util.to_assoc
      |> List.map (fun (id, j) -> of_json ~id j)

let load_dir dir =
  if not (Sys.file_exists dir) then []
  else
  Sys.readdir dir |> Array.to_list
  |> List.filter (fun f -> Filename.check_suffix f ".json")
  |> List.sort (fun a b -> compare b a)
  |> List.concat_map (fun f -> load_file (Filename.concat dir f))
  |> List.sort (fun a b -> compare b.date a.date)


let find articles id = List.find_opt (fun a -> a.id = id) articles
