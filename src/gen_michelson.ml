open Ident
open Location
open Tools

module M = Model
module T = Michelson

exception Anomaly of string

type error_desc =
  | UnsupportedTerm of string
  | TODO
[@@deriving show {with_path = false}]

let emit_error (desc : error_desc) =
  let str = Format.asprintf "%a@." pp_error_desc desc in
  raise (Anomaly str)

type env = {
  function_p: (ident * (ident * T.type_) list) option
}

let mk_env ?function_p _ =
  { function_p }

let to_ir (model : M.model) : T.ir =

  let to_one_gen init f l =
    match List.rev l with
    | [] -> init
    | i::q -> List.fold_right (fun x accu -> f x accu) q i
  in

  let to_one_type (l : T.type_ list) : T.type_ = to_one_gen (T.mk_type T.Tunit) (fun x accu -> (T.mk_type (T.Tpair (x, accu)))) l in

  let to_one_data (l : T.data list) : T.data = to_one_gen (T.Dunit) (fun x accu -> (T.Dpair (x, accu))) l in

  let rec to_type ?annotation (t : M.type_) : T.type_ =
    let node =
      match t with
      | Tasset _   -> assert false
      | Tenum _    -> assert false
      | Tstate     -> assert false
      | Tbuiltin b -> begin
          match b with
          | Bunit      -> T.Tunit
          | Bbool      -> T.Tbool
          | Bint       -> T.Tint
          | Brational  -> assert false
          | Bdate      -> T.Ttimestamp
          | Bduration  -> T.Tint
          | Btimestamp -> T.Ttimestamp
          | Bstring    -> T.Tstring
          | Baddress   -> T.Taddress
          | Brole      -> T.Taddress
          | Bcurrency  -> T.Tmutez
          | Bsignature -> T.Tsignature
          | Bkey       -> T.Tkey
          | Bkeyhash   -> T.Tkey_hash
          | Bbytes     -> T.Tbytes
          | Bnat       -> T.Tnat
          | Bchainid   -> T.Tchain_id
        end
      | Tcontainer _ -> assert false
      | Tlist t      -> T.Tlist (to_type t)
      | Toption t    -> T.Toption (to_type t)
      | Ttuple lt    -> to_one_type (List.map to_type lt) |> fun x -> x.node
      | Tset t -> T.Tset (to_type t)
      | Tmap (b, k, v) -> if b then T.Tbig_map (to_type k, to_type v) else T.Tmap (to_type k, to_type v)
      | Trecord _id -> begin
          (* TODO *)
          assert false
        end
      | Tunit -> T.Tunit
      | Toperation -> T.Toperation
      | Tentrysig t -> T.Tcontract (to_type t)
      | Tstorage -> assert false
      | Tprog  _ -> assert false
      | Tvset  _ -> assert false
      | Ttrace _ -> assert false
    in
    T.mk_type ?annotation node
  in

  let rec to_data (mt : M.mterm) : T.data =
    match mt.node with
    | Munit             -> T.Dunit
    | Mbool      v      -> (if v then T.Dtrue else T.Dfalse)
    | Mint       n      -> T.Dint n
    | Mnat       n      -> T.Dint n
    | Mstring    s      -> T.Dstring s
    | Mcurrency  (v, _) -> T.Dint v
    | Maddress   v      -> T.Dstring v
    | Mdate      v      -> T.Dint (Core.date_to_timestamp v)
    | Mduration  n      -> T.Dint (Core.duration_to_timestamp n)
    | Mtimestamp v      -> T.Dint v
    | Mbytes     b      -> T.Dbytes b
    | Mnone             -> T.Dnone
    | Msome      v      -> T.Dsome (to_data v)
    | Mtuple     l      -> to_one_data (List.map to_data l)
    | Mlitset    l      -> T.Dlist (List.map to_data l)
    | Mlitlist   l      -> T.Dlist (List.map to_data l)
    | Mlitmap    l      -> T.Dplist (List.map (fun (x, y) -> to_data x, to_data y) l)
    | Muminus    v      -> to_data v |> (function | T.Dint n -> T.Dint (Big_int.mult_int_big_int (-1) n) | _ -> assert false )
    (* | Mlitrecord l -> to_data v *)
    | Mnattoint v
    | Mnattorat v
    | Minttorat v
    | Mcast (_, _, v) -> to_data v
    | _ -> Format.printf "%a@." M.pp_mterm mt; assert false

  in

  let l = List.map (
      fun (si : M.storage_item) ->
        to_type ~annotation:(unloc si.id) si.typ, to_data si.default)
      model.storage
  in

  let remove_annot (t : T.type_) = {t with annotation = None} in

  let storage_type, storage_data =
    match l with
    | []  -> T.mk_type Tunit, T.Dunit
    | [t, d] -> remove_annot t, d
    | _   -> let lt, ld = List.split l in to_one_type lt, to_one_data ld
  in

  let rec mterm_to_intruction env (mtt : M.mterm) : T.instruction =
    let f = mterm_to_intruction env in
    let ft = to_type in
    match mtt.node with

    (* lambda *)

    | Mletin ([id], v, _, b, _)    -> T.IletIn (unloc id, f v, f b)
    | Mletin _                     -> assert false
    | Mdeclvar (_ids, _t, _v)      -> assert false
    | Mapp (_e, _args)             -> assert false

    (* assign *)

    | Massign (_op, _, Avar id, v)                 -> T.Iassign (unloc id, Local, f v)
    | Massign (_op, _, Avarstore id, v)            -> T.Iassign (unloc id, Storage, f v)
    | Massign (_op, _, Aasset (_an, _fn, _k), _v)  -> assert false
    | Massign (_op, _, Arecord (_rn, _fn, _r), _v) -> assert false
    | Massign (_op, _, Astate, _x)                 -> assert false
    | Massign (_op, _, Aassetstate (_an, _k), _v)  -> assert false
    | Massign (_op, _, Aoperations, _v)            -> assert false

    (* control *)

    | Mif (c, t, Some e)         -> T.Iif (f c, f t, f e)
    | Mif (c, t, None)           -> T.Iif (f c, f t, T.Iseq [])
    | Mmatchwith (_e, _l)        -> assert false
    | Mfor (_id, _col, _body, _) -> assert false
    | Miter (_i, _a, _b, _c, _)  -> assert false
    | Mwhile (_c, _b, _)         -> assert false
    | Mseq is                    -> T.Iseq (List.map f is)
    | Mreturn _x                 -> assert false
    | Mlabel _                   -> assert false
    | Mmark  _                   -> assert false


    (* effect *)

    | Mfail ft          -> begin
        let x =
          match ft with
          | Invalid v            -> f v
          | InvalidCaller        -> T.istring "InvalidCaller"
          | InvalidCondition lbl -> T.istring ("InvalidCondition" ^ (match lbl with | Some lbl -> ": " ^ lbl | _ -> ""))
          | NoTransfer           -> T.istring "NoTransfer"
          | AssignNat            -> T.istring "AssignNat"
          | InvalidState         -> T.istring "InvalidState"
        in
        T.Ifail x
      end
    | Mtransfer (_v, _k) -> assert false

    (* entrypoint *)

    | Mentrypoint (_, _a, _s) -> assert false
    | Mself _id               -> assert false


    (* operation *)

    | Moperations               -> assert false
    | Mmkoperation (_v, _d, _a) -> assert false


    (* literals *)

    | Mint  v            -> T.Iconst (T.mk_type Tint, Dint v)
    | Mnat  v            -> T.Iconst (T.mk_type Tnat, Dint v)
    | Mbool v            -> T.Iconst (T.mk_type Tbool, if v then Dtrue else Dfalse)
    | Menum _v           -> assert false
    | Mrational (_n, _d) -> assert false
    | Mstring v          -> T.Iconst (T.mk_type Tstring, Dstring v)
    | Mcurrency (v, Utz) -> T.Iconst (T.mk_type Tmutez, Dint v)
    | Mcurrency _        -> assert false
    | Maddress _v        -> assert false
    | Mdate _v           -> assert false
    | Mduration _v       -> assert false
    | Mtimestamp _v      -> assert false
    | Mbytes v           -> T.Iconst (T.mk_type Tbytes, Dbytes v)
    | Munit              -> T.Iconst (T.mk_type Tunit, Dunit)

    (* control expression *)

    | Mexprif (_c, _t, _e)     -> assert false
    | Mexprmatchwith (_e, _l)  -> assert false


    (* composite type constructors *)

    | Mnone    -> assert false
    | Msome _v -> assert false

    | Mtuple     l -> begin
        match List.rev l with
        | []  -> T.iunit
        | [e] -> f e
        | e::t -> List.fold_left (fun accu x -> T.Ibinop (Bpair, f x, accu)) (f e) t
      end
    | Masset     _l -> assert false
    | Massets    _l -> assert false
    | Mlitset    _l -> assert false
    | Mlitlist   _l -> assert false
    | Mlitmap    l -> begin
        match mtt.type_ with
        | M.Tmap (true, k, v)  (* TODO: big map *)
        | M.Tmap (false, k, v) -> T.Imap (ft k, ft v, List.map (fun (x, y) -> f x, f y) l)
        | _ -> assert false
      end
    | Mlitrecord _l -> assert false

    (* access *)

    | Mdot (_e, _i)         -> assert false
    | Mdotassetfield _      -> emit_error (UnsupportedTerm ("dotassetfield"))
    | Mdotcontract (_e, _i) -> assert false
    | Maccestuple (_e, _i)  -> assert false

    (* comparison operators *)

    | Mequal (_, l, r)  -> T.Ibinop (Beq, f l, f r)
    | Mnequal (_, l, r) -> T.Ibinop (Bneq, f l, f r)
    | Mgt (l, r)        -> T.Ibinop (Bgt, f l, f r)
    | Mge (l, r)        -> T.Ibinop (Bge, f l, f r)
    | Mlt (l, r)        -> T.Ibinop (Blt, f l, f r)
    | Mle (l, r)        -> T.Ibinop (Ble, f l, f r)
    | Mmulticomp _      -> emit_error (UnsupportedTerm ("multicomp"))


    (* arithmetic operators *)

    | Mand (l, r)      -> T.Ibinop (Band, f l, f r)
    | Mor (l, r)       -> T.Ibinop (Bor, f l, f r)
    | Mnot e           -> T.Iunop  (Unot, f e)
    | Mplus (l, r)     -> T.Ibinop (Badd, f l, f r)
    | Mminus (l, r)    -> T.Ibinop (Bsub, f l, f r)
    | Mmult (l, r)     -> T.Ibinop (Bmul, f l, f r)
    | Mdivrat _        -> emit_error (UnsupportedTerm ("divrat"))
    | Mdiveuc (_l, _r) -> assert false
    | Mmodulo (_l, _r) -> assert false
    | Muplus _e        -> assert false
    | Muminus e        -> T.Iunop  (Uneg, f e)

    (* asset api effect *)

    | Maddasset (_an, _i)               -> assert false
    | Maddfield (_an, _fn, _c, _i)      -> assert false
    | Mremoveasset (_an, _i)            -> assert false
    | Mremoveall (_an, _fn, _a)         -> assert false
    | Mremovefield (_an, _fn, _c, _i)   -> assert false
    | Mremoveif (_an, _c, _la, _lb, _a) -> assert false
    | Mclear (_an, _v)                  -> assert false
    | Mset (_c, _l, _k, _v)             -> assert false
    | Mupdate (_an, _k, _l)             -> assert false
    | Maddupdate _                      -> emit_error (UnsupportedTerm ("addupdate"))


    (* asset api expression *)

    | Mget (_an, _c, _k)              -> assert false
    | Mselect (_an, _c, _la, _lb, _a) -> assert false
    | Msort (_an, _c, _l)             -> assert false
    | Mcontains (_an, _c, _i)         -> assert false
    | Mnth (_an, _c, _i)              -> assert false
    | Mcount (_an, _c)                -> assert false
    | Msum (_an, _c, _p)              -> assert false
    | Mhead (_an, _c, _i)             -> assert false
    | Mtail (_an, _c, _i)             -> assert false


    (* utils *)

    | Mcast (_src, _dst, _v) -> assert false
    | Mtupleaccess (x, n)    -> Tools.foldi (fun x -> T.Iunop (Ucdr, x)) (f x) (Big_int.int_of_big_int n)

    (* set api expression *)

    | Msetadd (_, c, a)        -> T.Iterop (Tupdate, f c, f a, T.itrue)
    | Msetremove (_, c, a)     -> T.Iterop (Tupdate, f c, f a, T.ifalse)
    | Msetcontains (_, c, k)   -> T.Ibinop (Bmem, f c, f k)
    | Msetlength (_, c)        -> T.Iunop  (Usize, f c)


    (* list api expression *)

    | Mlistprepend (_t, i, l)    -> T.Ibinop (Bcons, f l, f i)
    | Mlistcontains (_t, _c, _a) -> assert false
    | Mlistlength (_, l)         -> T.Iunop (Usize, f l)
    | Mlistnth (_t, _c, _a)      -> assert false


    (* map api expression *)

    | Mmapput (_, _, c, k, v)     -> T.Iterop (Tupdate, f c, T.isome (f v), f k)
    | Mmapremove (_, tv, c, k)    -> T.Iterop (Tupdate, f c, T.inone (ft tv), f k)
    | Mmapget (_, _, _c, _k)      -> assert false
    | Mmapgetopt (_, _, c, k)     -> T.Ibinop (Bget, f c, f k)
    | Mmapcontains (_, _, c, k)   -> T.Ibinop (Bmem, f c, f k)
    | Mmaplength (_, _, c)        -> T.Iunop (Usize, f c)


    (* builtin functions *)

    | Mmax (_l, _r)      -> assert false
    | Mmin (_l, _r)      -> assert false
    | Mabs x             -> T.Iunop (Uabs, f x)
    | Mconcat (x, y)     -> T.Ibinop (Bconcat, f x, f y)
    | Mslice (x, s, e)   -> T.Iterop (Tslice, f x, f s, f e)
    | Mlength x          -> T.Iunop (Usize, f x)
    | Misnone _x         -> assert false
    | Missome _x         -> assert false
    | Moptget _x         -> assert false
    | Mfloor _x          -> assert false
    | Mceil _x           -> assert false
    | Mtostring (_t, _x) -> assert false
    | Mpack x            -> T.Iunop (Upack,  f x)
    | Munpack (t, x)     -> T.Iunop (Uunpack (ft t),  f x)

    (* crypto functions *)

    | Mblake2b x                -> T.Iunop  (Ublake2b,  f x)
    | Msha256  x                -> T.Iunop  (Usha256,   f x)
    | Msha512  x                -> T.Iunop  (Usha512,   f x)
    | Mhashkey x                -> T.Iunop  (Uhash_key, f x)
    | Mchecksignature (k, s, x) -> T.Iterop (Tcheck_signature, f k, f s, f x)


    (* constants *)

    | Mnow           -> T.Izop Znow
    | Mtransferred   -> T.Izop Zamount
    | Mcaller        -> T.Izop Zsender
    | Mbalance       -> T.Izop Zbalance
    | Msource        -> T.Izop Zsource
    | Mselfaddress   -> T.Izop Zself_address
    | Mchainid       -> T.Izop Zchain_id


    (* variable *)

    | Mvar (_an, Vassetstate _k) -> assert false
    | Mvar (v, Vstorevar)        -> T.Ivar (unloc v)
    | Mvar (_v, Vstorecol)       -> assert false
    | Mvar (_v, Venumval)        -> assert false
    | Mvar (_v, Vdefinition)     -> assert false
    | Mvar (v, Vlocal)           -> T.Ivar (unloc v)
    | Mvar (v, Vparam)           -> T.Ivar (unloc v)
    | Mvar (_v, Vfield)          -> assert false
    | Mvar (_, Vthe)             -> assert false
    | Mvar (_, Vstate)           -> assert false

    (* rational *)

    | Mrateq (_l, _r)         -> assert false
    | Mratcmp (_op, _l, _r)   -> assert false
    | Mratarith (_op, _l, _r) -> assert false
    | Mratuminus _v           -> assert false
    | Mrattez (_c, _t)        -> assert false
    | Mdivtez (_c, _t)        -> assert false
    | Mnattoint e             -> T.Iunop (Uint, f e)
    | Mnattorat _e            -> assert false
    | Minttorat _e            -> assert false
    | Mratdur (_c, _t)        -> assert false


    (* functional *)

    | Mfold _ -> emit_error (UnsupportedTerm ("fold"))


    (* imperative *)

    | Mbreak -> emit_error (UnsupportedTerm ("break"))


    (* quantifiers *)

    | Mforall _ -> emit_error (UnsupportedTerm ("forall"))
    | Mexists _ -> emit_error (UnsupportedTerm ("exists"))


    (* formula operators *)

    | Mimply _ -> emit_error (UnsupportedTerm ("imply"))
    | Mequiv _ -> emit_error (UnsupportedTerm ("equiv"))


    (* formula asset collection *)

    | Msetbefore    _ -> emit_error (UnsupportedTerm ("setbefore"))
    | Msetat        _ -> emit_error (UnsupportedTerm ("setat"))
    | Msetunmoved   _ -> emit_error (UnsupportedTerm ("setunmoved"))
    | Msetadded     _ -> emit_error (UnsupportedTerm ("setadded"))
    | Msetremoved   _ -> emit_error (UnsupportedTerm ("setremoved"))
    | Msetiterated  _ -> emit_error (UnsupportedTerm ("setiterated"))
    | Msettoiterate _ -> emit_error (UnsupportedTerm ("settoiterate"))


    (* formula asset collection methods *)

    | Mempty     _ -> emit_error (UnsupportedTerm ("empty"))
    | Msingleton _ -> emit_error (UnsupportedTerm ("singleton"))
    | Msubsetof  _ -> emit_error (UnsupportedTerm ("subsetof"))
    | Misempty   _ -> emit_error (UnsupportedTerm ("isempty"))
    | Munion     _ -> emit_error (UnsupportedTerm ("union"))
    | Minter     _ -> emit_error (UnsupportedTerm ("inter"))
    | Mdiff      _ -> emit_error (UnsupportedTerm ("diff"))
  in

  let env = mk_env () in

  let entries =
    let for_fs env (fs : M.function_struct) : T.entry =
      let name = unloc fs.name in
      let args = List.map (fun (id, t, _) -> unloc id, to_type t) fs.args in
      let env = {env with function_p = Some (name, args)} in
      let body = mterm_to_intruction env fs.body in
      T.mk_entry name args body
    in

    List.fold_right (fun (x : M.function__) accu -> match x.node with | Entry fs -> (for_fs env fs)::accu | _ -> accu ) model.functions []
  in

  T.mk_ir (storage_type, storage_data) entries

let to_michelson (ir : T.ir) : T.michelson =
  let storage = ir.storage |> fst in
  let parameter = T.mk_type T.Tunit in
  let default = T.SEQ [T.CDR; T.NIL (T.mk_type Toperation); T.PAIR ] in

  let rec instruction_to_code (i : T.instruction) : T.code =
    let f = instruction_to_code in
    match i with
    | Iseq l               -> T.SEQ (List.map f l)
    | IletIn (_id, v, b)   -> T.SEQ [f v; f b]      (* TODO *)
    | Ivar _id             -> T.SEQ [] (* TODO *)
    | Icall (_id, _args)   -> assert false
    | Iassign (_id, _, v)  -> f v
    | Izop op -> begin
        match op with
        | Znow               -> T.NOW
        | Zamount            -> T.AMOUNT
        | Zbalance           -> T.BALANCE
        | Zsource            -> T.SOURCE
        | Zsender            -> T.SENDER
        | Zaddress           -> T.ADDRESS
        | Zchain_id          -> T.CHAIN_ID
        | Zself_address      -> T.SEQ [T.SELF; T.ADDRESS]
        | Znone t            -> T.NONE t
      end
    | Iunop (op, e) -> begin
        let op =
          match op with
          | Ucar      -> T.CAR
          | Ucdr      -> T.CDR
          | Uneg      -> T.NEG
          | Uint      -> T.INT
          | Unot      -> T.NOT
          | Uabs      -> T.ABS
          | Uisnat    -> T.ISNAT
          | Usome     -> T.SOME
          | Usize     -> T.SIZE
          | Upack     -> T.PACK
          | Uunpack t -> T.UNPACK t
          | Ublake2b  -> T.BLAKE2B
          | Usha256   -> T.SHA256
          | Usha512   -> T.SHA512
          | Uhash_key -> T.HASH_KEY
        in
        let e = f e in
        T.SEQ [e; op]
      end
    | Ibinop (op, lhs, rhs) -> begin
        let op =
          match op with
          | Badd       -> T.ADD
          | Bsub       -> T.SUB
          | Bmul       -> T.MUL
          | Bediv      -> T.EDIV
          | Blsl       -> T.LSL
          | Blsr       -> T.LSR
          | Bor        -> T.OR
          | Band       -> T.AND
          | Bxor       -> T.XOR
          | Bcompare   -> T.COMPARE
          | Beq        -> T.EQ
          | Bneq       -> T.NEQ
          | Blt        -> T.LT
          | Bgt        -> T.GT
          | Ble        -> T.LE
          | Bge        -> T.GE
          | Bget       -> T.GET
          | Bmem       -> T.MEM
          | Bconcat    -> T.CONCAT
          | Bcons      -> T.CONS
          | Bpair      -> T.PAIR
        in
        let rhs = f rhs in
        let lhs = f lhs in
        T.SEQ [rhs; lhs; op]
      end
    | Iterop (op, a1, a2, a3) -> begin
        let op =
          match op with
          | Tcheck_signature -> T.CHECK_SIGNATURE
          | Tslice           -> T.SLICE
          | Tupdate          -> T.UPDATE
        in
        let a1 = f a1 in
        let a2 = f a2 in
        let a3 = f a3 in
        T.SEQ [a1; a2; a3; op]
      end
    | Iconst (t, e) -> T.PUSH (t, e)
    | Iif (_c, _t, _e) -> assert false
    | Ifail e       -> begin
        let e = f e in
        T.SEQ [e; T.FAILWITH]
      end
    | Iset (t, l) -> begin
        T.SEQ ([T.EMPTY_SET t] @ List.map (fun x -> T.SEQ [T.ctrue; f x; T.UPDATE ] ) l)
      end
    | Ilist (t, _l) -> begin
        T.NIL t
      end
    | Imap (k, v, l) -> begin
        T.SEQ ([T.EMPTY_MAP (k, v)] @ List.map (fun (x, y) -> T.SEQ [f y; T.SOME; f x; T.UPDATE ] ) l)
      end
  in

  let convert (i : T.instruction) : T.code =
    let code = instruction_to_code i in
    let code = T.SEQ [T.DROP 0; code; T.NIL (T.mk_type Toperation); T.PAIR ] in
    T.flat code
  in

  let code =
    match ir.entries with
    | [e] -> convert e.body
    | _ -> default
  in

  T.mk_michelson storage parameter code