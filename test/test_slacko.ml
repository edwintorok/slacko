open Lwt
open OUnit2

open Slounit
open Abbrtypes


let token =
  try Sys.getenv "SLACKO_TEST_TOKEN" with Not_found -> "xoxp-testtoken"

let badtoken = "badtoken"

(* If we have a non-default token, assume we want to talk to real slack. If
   not, use our local fake instead. *)
let base_url = match token with
  | "xoxp-testtoken" -> Some "http://127.0.0.1:7357/api/"
  | _ ->
    print_endline ("NOTE: Because an API token has been provided, " ^
                   "tests will run against the real slack API.");
    try
      (* We may want to talk to a proxy or a different fake slack. *)
      let base_url = Sys.getenv "SLACKO_TEST_BASE_URL" in
      print_endline @@ "NOTE: Overriding slack base URL to " ^ base_url;
      Some base_url;
    with Not_found -> None


let abbr_json abbr_of_yojson json =
  match abbr_of_yojson json with
  | Ok abbr -> abbr
  | Error err -> failwith @@ "Error parsing JSON: " ^ err

let get_success = function
  | `Success obj -> obj
  | _ -> assert_failure "Unexpected failure."


(* api_test *)

let test_api_test_nodata tctx =
  Slacko.api_test ?base_url () >|= get_success >|= fun json ->
  assert_equal ~printer:Yojson.Safe.to_string
    (`Assoc [])
    json

let test_api_test_foo tctx =
  Slacko.api_test ?base_url ~foo:"hello" () >|= get_success >|= fun json ->
  assert_equal ~printer:Yojson.Safe.to_string
    (`Assoc ["args", `Assoc ["foo", `String "hello"]])
    json

let test_api_test_err tctx =
  Slacko.api_test ?base_url ~error:"badthing" () >|= fun resp ->
  assert_equal (`Unhandled_error "badthing") resp

let test_api_test_err_foo tctx =
  Slacko.api_test ?base_url ~foo:"goodbye" ~error:"badthing" () >|= fun resp ->
  assert_equal (`Unhandled_error "badthing") resp

let api_test_tests = fake_slack_tests "api_test" [
  "test_nodata", test_api_test_nodata;
  "test_foo", test_api_test_foo;
  "test_err", test_api_test_err;
  "test_err_foo", test_api_test_err_foo;
]

(* auth_test *)

let test_auth_test_valid tctx =
  let session = Slacko.make_session ?base_url token in
  Slacko.auth_test session >|= get_success >|=
  abbr_authed_obj >|= fun authed ->
  assert_equal ~printer:show_abbr_authed_obj
    (abbr_json abbr_authed_obj_of_yojson Fake_slack.authed_json)
    authed

let test_auth_test_invalid tctx =
  let session = Slacko.make_session ?base_url badtoken in
  Slacko.auth_test session >|= fun resp ->
  assert_equal `Invalid_auth resp

let auth_test_tests = fake_slack_tests "test_auth" [
  "test_valid", test_auth_test_valid;
  "test_invalid", test_auth_test_invalid;
]

(* channels_archive  *)

let test_channels_archive_bad_auth tctx =
  skip_if true "TODO: Channel lookup swallows all sorts of things.";
  let session = Slacko.make_session ?base_url badtoken in
  let new_channel = Slacko.channel_of_string "#new_channel" in
  Slacko.channels_archive session new_channel >|= fun resp ->
  assert_equal `Invalid_auth resp

let test_channels_archive_existing tctx =
  let session = Slacko.make_session ?base_url token in
  let new_channel = Slacko.channel_of_string "#archivable_channel" in
  Slacko.channels_archive session new_channel >|= fun resp ->
  assert_equal `Success resp

let test_channels_archive_missing tctx =
  let session = Slacko.make_session ?base_url token in
  let missing_channel = Slacko.channel_of_string "#missing_channel" in
  Slacko.channels_archive session missing_channel >|= fun resp ->
  assert_equal `Channel_not_found resp

let test_channels_archive_archived tctx =
  let session = Slacko.make_session ?base_url token in
  let archived_channel = Slacko.channel_of_string "#archived_channel" in
  Slacko.channels_archive session archived_channel >|= fun resp ->
  assert_equal `Already_archived resp

let test_channels_archive_general tctx =
  let session = Slacko.make_session ?base_url token in
  let general = Slacko.channel_of_string "#general" in
  Slacko.channels_archive session general >|= fun resp ->
  assert_equal `Cant_archive_general resp

let channels_archive_tests = fake_slack_tests "channels_archive" [
  "test_bad_auth", test_channels_archive_bad_auth;
  "test_existing", test_channels_archive_existing;
  "test_missing", test_channels_archive_missing;
  "test_archived", test_channels_archive_archived;
  "test_general", test_channels_archive_general;
]

(* channels_create *)

let test_channels_create_bad_auth tctx =
  let session = Slacko.make_session ?base_url badtoken in
  Slacko.channels_create session "#new_channel" >|= fun resp ->
  assert_equal `Invalid_auth resp

let test_channels_create_new tctx =
  skip_if true "TODO: Fix parsing of last_read field.";
  let session = Slacko.make_session ?base_url token in
  Slacko.channels_create session "#new_channel" >|= get_success >|=
  abbr_channel_obj >|= fun channel ->
  assert_equal ~printer:show_abbr_channel_obj
    (abbr_json abbr_channel_obj_of_yojson Fake_slack.new_channel_json)
    channel

let test_channels_create_existing tctx =
  let session = Slacko.make_session ?base_url token in
  Slacko.channels_create session "#general" >|= fun resp ->
  assert_equal `Name_taken resp

let channels_create_tests = fake_slack_tests "channels_create" [
  "test_bad_auth", test_channels_create_bad_auth;
  "test_new", test_channels_create_new;
  "test_existing", test_channels_create_existing;
]

(* channels_list *)

let test_channels_list_bad_auth tctx =
  let session = Slacko.make_session ?base_url badtoken in
  Slacko.channels_list session >|= fun resp ->
  assert_equal `Invalid_auth resp

let test_channels_list tctx =
  let session = Slacko.make_session ?base_url token in
  Slacko.channels_list session >|= get_success >|=
  List.map abbr_channel_obj >|= fun channels ->
  assert_equal ~printer:show_abbr_channel_obj_list
    (abbr_json abbr_channel_obj_list_of_yojson Fake_slack.channels_json)
    channels

let channels_list_tests = fake_slack_tests "channels_list" [
  "test_bad_auth", test_channels_list_bad_auth;
  "test", test_channels_list;
]


let suite = "tests" >::: [
    api_test_tests;
    auth_test_tests;
    channels_archive_tests;
    channels_create_tests;
    channels_list_tests;
  ]


let () = run_test_tt_main suite
