(* ocaml-jwt
 * https://github.com/besport/ocaml-jwt
 *
 * Copyright (C) Be Sport
 * Author Danny Willems
 *
 * This program is released under the LGPL version 2.1 or later (see the text
 * below) with the additional exemption that compiling, linking, and/or using
 * OpenSSL is allowed.
 *
 * As a special exception to the GNU Library General Public License, you
 * may also link, statically or dynamically, a "work that uses the Library"
 * with a publicly distributed version of the Library to produce an
 * executable file containing portions of the Library, and distribute
 * that executable file under terms of your choice, without any of the
 * additional requirements listed in clause 6 of the GNU Library General
 * Public License.  By "a publicly distributed version of the Library",
 * we mean either the unmodified Library, or a
 * modified version of the Library that is distributed under the
 * conditions defined in clause 3 of the GNU Library General Public
 * License.  This exception does not however invalidate any other reasons
 * why the executable file might be covered by the GNU Library General
 * Public License.
 *)

exception Bad_token
exception Bad_payload

(* ------------------------------- *)
(* ---------- Algorithm ---------- *)

(* IMPROVEME: add other algorithm *)
type algorithm = [ `RS256 | `ES256 | `HS256 | `HS512 ]

type private_key =
  [ `RS256 of Mirage_crypto_pk.Rsa.priv
  | `ES256 of Mirage_crypto_ec.P256.Dsa.priv
  | `HS256 of Cstruct.t (* the argument is the secret key *)
  | `HS512 of Cstruct.t (* the argument is the secret key *) ]

type public_key =
  [ `RS256 of Mirage_crypto_pk.Rsa.pub
  | `ES256 of Mirage_crypto_ec.P256.Dsa.pub ]

let algorithm_of_private_key (x : private_key) : algorithm =
  match x with
  | `RS256 _ -> `RS256
  | `ES256 _ -> `ES256
  | `HS256 _ -> `HS256
  | `HS512 _ -> `HS512

let algorithm_of_public_key (x : public_key) =
  match x with `RS256 _ -> `RS256 | `ES256 _ -> `ES256

let fn_of_algorithm : private_key -> string -> string = function
  | `RS256 key ->
      fun input_str ->
        Mirage_crypto_pk.Rsa.PKCS1.sign ~hash:`SHA256 ~key
          (`Message (Cstruct.of_string input_str))
        |> Cstruct.to_string
  | `ES256 key ->
      fun input_str ->
        let r, s =
          input_str |> Cstruct.of_string |> Mirage_crypto.Hash.SHA256.digest
          |> Mirage_crypto_ec.P256.Dsa.sign ~key
        in
        Cstruct.(concat [ r; s ] |> to_string)
  | `HS256 key ->
      fun input_str ->
        Mirage_crypto.Hash.SHA256.hmac ~key (Cstruct.of_string input_str)
        |> Cstruct.to_string
  | `HS512 key ->
      fun input_str ->
        Mirage_crypto.Hash.SHA512.hmac ~key (Cstruct.of_string input_str)
        |> Cstruct.to_string

let string_of_algorithm : algorithm -> string = function
  | `RS256 -> "RS256"
  | `ES256 -> "ES256"
  | `HS256 -> "HS256"
  | `HS512 -> "HS512"

let algorithm_of_string : string -> algorithm = function
  | "HS256" -> `HS256
  | "HS512" -> `HS512
  | "RS256" -> `RS256
  | "ES256" -> `ES256
  | _ -> failwith "Unknown algorithm"
(* ---------- Algorithm ---------- *)
(* ------------------------------- *)

(* ---------------------------- *)
(* ---------- Header ---------- *)

type header = {
  alg : algorithm;
  typ : string option; (* IMPROVEME: Need a sum type *)
  kid : string option;
}

let make_header ~alg ?(typ = Some "JWT") ?kid () = { alg; typ; kid }
let header_of_algorithm_and_typ alg typ = { alg; typ; kid = None }

(* ------- *)
(* getters *)

let algorithm_of_header h = h.alg
let typ_of_header h = h.typ
let kid_of_header h = h.kid

(* getters *)
(* ------- *)

let json_of_header header =
  `Assoc
    (("alg", `String (string_of_algorithm (algorithm_of_header header)))
    :: ((match typ_of_header header with
        | Some typ -> [ ("typ", `String typ) ]
        | None -> [])
       @
       match kid_of_header header with
       | Some kid -> [ ("kid", `String kid) ]
       | None -> []))

let string_of_header header =
  let json = json_of_header header in
  Yojson.Basic.to_string json

let header_of_json json =
  let alg = Yojson.Basic.Util.to_string (Yojson.Basic.Util.member "alg" json) in
  let typ =
    Yojson.Basic.Util.to_string_option (Yojson.Basic.Util.member "typ" json)
  in
  let kid =
    Yojson.Basic.Util.to_string_option (Yojson.Basic.Util.member "kid" json)
  in
  { alg = algorithm_of_string alg; typ; kid }

let header_of_string str = header_of_json (Yojson.Basic.from_string str)

(* ----------- Header ---------- *)
(* ----------------------------- *)

(* ---------------------------- *)
(* ----------- Claim ---------- *)

type claim = string

let claim c = c
let string_of_claim c = c

(* ------------- *)
(* Common claims *)

(* Issuer: identifies principal that issued the JWT *)
let iss = "iss"

(* Subject: identifies the subject of the JWT *)
let sub = "sub"

(* Audience: The "aud" (audience) claim identifies the recipients that the JWT
 * is intended for. Each principal intended to process the JWT MUST identify
 * itself with a value in the audience claim. If the principal processing the
 * claim does not identify itself with a value in the aud claim when this claim
 * is present, then the JWT MUST be rejected. *)
let aud = "aud"

(* Expiration time: The "exp" (expiration time) claim identifies the expiration
 * time on or after which the JWT MUST NOT be accepted for processing. *)
let exp = "exp"

(* Not before: Similarly, the not-before time claim identifies the time on which
 * the JWT will start to be accepted for processing. *)
let nbf = "nbf"

(* Issued at: The "iat" (issued at) claim identifies the time at which the JWT
 * was issued.
 *)
let iat = "iat"

(* JWT ID: case sensitive unique identifier of the token even among different
 * issuers.
 *)
let jti = "jti"

(* Token type *)
let typ = "typ"

(* Content type: This claim should always be JWT *)
let ctyp = "ctyp"

(* Message authentication code algorithm (alg) - The issuer can freely set an
 * algorithm to verify the signature on the token. However, some asymmetrical
 * algorithms pose security concerns.
 *)
let alg = "alg"

(* Common claims *)
(* ------------- *)

(* ------------------------- *)
(* Defined in OpenID Connect *)

(* Time when the End-User authentication occurred. Its value is a JSON number
 * representing the number of seconds from 1970-01-01T0:0:0Z as measured in UTC
 * until the date/time.
 *)
let auth_time = "auth_time"

(* String value used to associate a Client session with an ID Token, and to
 * mitigate replay attacks. The value is passed through unmodified from the
 * Authentication Request to the ID Token. If present in the ID Token, Clients
 * MUST verify that the nonce Claim Value is equal to the value of the nonce
 * parameter sent in the Authentication Request. If present in the
 * Authentication Request, Authorization Servers MUST include a nonce Claim in
 * the ID Token with the Claim Value being the nonce value sent in the
 * Authentication Request. Authorization Servers SHOULD perform no other
 * processing on nonce values used. The nonce value is a case sensitive string.
 *)
let nonce = "nonce"
let acr = "acr"
let amr = "amr"
let azp = "azp"

(* Defined in OpenID Connect *)
(* ------------------------- *)

(* ----------- Claim ---------- *)
(* ---------------------------- *)

(* ------------------------------ *)
(* ----------- Payload ---------- *)

(* The payload a list of claim. The first component is the claim identifier and
 * the second is the value.
 *)
type payload = (claim * string) list

let empty_payload = []
let add_claim claim value payload = (claim, value) :: payload

let find_claim claim payload =
  let _, value =
    List.find (fun (c, _v) -> string_of_claim c = string_of_claim claim) payload
  in
  value

let map f p = List.map f p

let payload_of_json json =
  List.map
    (fun x ->
      match x with
      | claim, `String value -> (claim, value)
      | claim, `Int value -> (claim, string_of_int value)
      | claim, value -> (claim, Yojson.Basic.to_string value))
    (Yojson.Basic.Util.to_assoc json)

let payload_of_string str = payload_of_json (Yojson.Basic.from_string str)

let json_of_payload payload =
  let members =
    map
      (fun (claim, value) ->
        match string_of_claim claim with
        | "exp" | "iat" -> (string_of_claim claim, `Int (int_of_string value))
        | _ -> (string_of_claim claim, `String value))
      payload
  in
  `Assoc members

let string_of_payload payload = Yojson.Basic.to_string (json_of_payload payload)

(* ----------- Payload ---------- *)
(* ------------------------------ *)

(* -------------------------------- *)
(* ----------- JWT type ----------- *)

type t = {
  header : header;
  payload : payload;
  signature : string;
  unsigned_token : string;
}

let b64_url_encode str =
  let r = Base64.encode ~pad:false ~alphabet:Base64.uri_safe_alphabet str in
  match r with
  | Ok s -> s
  | Error _ ->
      failwith
        (Printf.sprintf "Something wrong happened while encoding\n  %s" str)

let b64_url_decode str =
  let r = Base64.decode ~pad:false ~alphabet:Base64.uri_safe_alphabet str in
  match r with
  | Ok s -> s
  | Error _ ->
      failwith
        (Printf.sprintf "Something wrong happened while decoding\n  %s" str)

let unsigned_token_of_header_and_payload header payload =
  let b64_header = b64_url_encode (string_of_header header) in
  let b64_payload = b64_url_encode (string_of_payload payload) in
  b64_header ^ "." ^ b64_payload

let t_of_payload ?header priv_key payload =
  let alg = algorithm_of_private_key priv_key in
  let header = match header with Some x -> x | None -> make_header ~alg () in
  let algo = fn_of_algorithm priv_key in
  let unsigned_token = unsigned_token_of_header_and_payload header payload in
  let signature = algo unsigned_token in
  { header; payload; signature; unsigned_token }
(* ------- *)
(* getters *)

let header_of_t t = t.header
let payload_of_t t = t.payload
let signature_of_t t = t.signature
let unsigned_token_of_t t = t.unsigned_token
(* getters *)
(* ------- *)

let token_of_t t =
  let b64_header = b64_url_encode (string_of_header (header_of_t t)) in
  let b64_payload = b64_url_encode (string_of_payload (payload_of_t t)) in
  let b64_signature = b64_url_encode (signature_of_t t) in
  b64_header ^ "." ^ b64_payload ^ "." ^ b64_signature

let t_of_token token =
  try
    let token_splitted = Re.Str.split_delim (Re.Str.regexp_string ".") token in
    match token_splitted with
    | [ header_encoded; payload_encoded; signature_encoded ] ->
        let header = header_of_string (b64_url_decode header_encoded) in
        let payload = payload_of_string (b64_url_decode payload_encoded) in
        let signature = b64_url_decode signature_encoded in
        let unsigned_token = header_encoded ^ "." ^ payload_encoded in
        { header; payload; signature; unsigned_token }
    | _ -> raise Bad_token
  with _ -> raise Bad_token

(* ----------- JWT type ----------- *)
(* -------------------------------- *)

(* ---------------------------------- *)
(* ----------- Verification ---------- *)

let verify ~(pub_key : public_key) t =
  let rs256 key signature unsigned_token =
    let pkcs1_sig header body =
      let hlen = Cstruct.length header in
      if Cstruct.check_bounds body hlen then
        match Cstruct.split ~start:0 body hlen with
        | a, b when Cstruct.equal a header -> Some b
        | _ -> None
      else None
    in
    let asn1_sha256 =
      Cstruct.of_string
        "\x30\x31\x30\x0d\x06\x09\x60\x86\x48\x01\x65\x03\x04\x02\x01\x05\x00\x04\x20"
    in
    let sign = Cstruct.of_string signature in
    match Mirage_crypto_pk.Rsa.PKCS1.sig_decode ~key sign with
    | None -> false
    | Some asn1_sign -> (
        match pkcs1_sig asn1_sha256 asn1_sign with
        | None -> false
        | Some decripted_sign ->
            let token_hash =
              Mirage_crypto.Hash.SHA256.digest
              @@ Cstruct.of_string unsigned_token
            in
            Cstruct.equal decripted_sign token_hash)
  in
  let es256 key signature unsigned_token =
    let sign = Cstruct.of_string signature in
    let r = Cstruct.sub sign 0 32 in
    let s = Cstruct.sub sign 32 32 in
    unsigned_token |> Cstruct.of_string |> Mirage_crypto.Hash.SHA256.digest
    |> Mirage_crypto_ec.P256.Dsa.verify ~key (r, s)
  in
  let header = header_of_t t in
  let payload = payload_of_t t in
  let signature = signature_of_t t in
  let unsigned_token = unsigned_token_of_t t in
  if typ_of_header header <> Some "JWT" then Error "type of header is not JWT"
  else if
    match List.assoc "exp" payload with
    | exp -> int_of_string exp <= int_of_float @@ Unix.time ()
    | exception Not_found -> false
  then Error "already expired"
  else if algorithm_of_public_key pub_key <> algorithm_of_header header then
    Error "algorithm of header is wrong"
  else if
    not
      (match pub_key with
      | `RS256 pub_key -> rs256 pub_key signature unsigned_token
      | `ES256 pub_key -> es256 pub_key signature unsigned_token)
  then Error "verification of signature failed"
  else Ok ()

(* ----------- Verification ---------- *)
(* ---------------------------------- *)
