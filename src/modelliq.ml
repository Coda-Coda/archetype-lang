open Model
open Modelinfo
open Modelws
open Location
open Tools

open Why3
open Ptree

let empty_spec = {
    sp_pre = [];
    sp_post = [];
    sp_xpost = [];
    sp_reads = [];
    sp_writes = [];
    sp_alias = [];
    sp_variant = [];
    sp_checkrw = false;
    sp_diverge = false;
    sp_partial = false;
  }

let loc2loc (l : Location.t) : Loc.position =
  let fname  = l.loc_fname in
  let line   = (fst l.loc_start) in
  let startp = (snd l.loc_start) in
  let endp   = (snd l.loc_end)   in
  Loc.user_position fname line startp endp

let loc (a : 'a loced) : Loc.position =
  let l = Location.loc a in
  loc2loc l

let mk_expr e = { expr_desc = e; expr_loc = Loc.dummy_position }

let mk_ident s = { id_str = unloc s; id_ats = []; id_loc = loc s }

let mk_qid l =
  let rec aux l =
    match l with
      | [] -> assert false
      | [x] -> Qident(mk_ident x)
      | x::r -> Qdot(aux r,mk_ident x)
  in
  aux (List.rev l)

let rec mk_qualid (q : Model.liqualid) : Ptree.qualid =
  match q with
  | Qident i -> Qident (mk_ident i)
  | Qdot (a,i) -> Qdot (mk_qualid a, mk_ident i)

let mk_econst s =
  mk_expr
    (Econst
       Number.(ConstInt { ic_negative = false ;
                          ic_abs = int_literal_dec s }))

let str_to_eident (s : string list) = s
  |> List.map (fun x -> mkloc Location.dummy x)
  |> fun x -> Eident (mk_qid x)

let str_to_eidapp (s : string list) l = s
  |> List.map (fun x -> mkloc Location.dummy x)
  |> fun x -> Eidapp ((mk_qid x),l)

let mk_enum_vals = List.map (fun id -> loc id, mk_ident id, [])

let mk_evar x = mk_expr(Eident(mk_qid [x]))

let mk_enum_decl (enum : Modelws.enum) =
  Dtype [{
    td_loc = loc enum;
    td_ident = mk_ident (unloc enum).name;
    td_params = [];
    td_vis = Public;
    td_mut = false;
    td_inv = [];
    td_wit = [];
    td_def = TDalgebraic (mk_enum_vals (unloc enum).values);
  }]

let lident_to_typ s = PTtyapp (mk_qid [s],[])

let vtyp_to_str = function
  | VTbool               -> "bool"
  | VTint                -> "int"
  | VTuint               -> "nat"
  | VTdate               -> "timestamp"
  | VTduration           -> "nat"
  | VTstring             -> "string"
  | VTaddress            -> "key_hash"
  | VTcurrency (Tez,_)   -> "tez"
  | VTcurrency (Mutez,_) -> "tez"

let str_to_lident = mkloc Location.dummy

let str_to_ident s = { id_str = s; id_ats = []; id_loc = Loc.dummy_position }

let vtyp_to_mlwtyp vt = vt |> vtyp_to_str |> str_to_lident |> lident_to_typ

let rec field_storage_to_ptyp = function
  | Flocal lid -> lident_to_typ lid
  | Ftyp vt   -> vt |> vtyp_to_mlwtyp
  | Flist vt  ->
    let listid =  str_to_ident "list" in
    PTtyapp (Qident listid, [field_storage_to_ptyp vt])
  | Fset vt   ->
    let listid =  str_to_ident "set" in
    PTtyapp (Qident listid, [field_storage_to_ptyp vt])
  | Fmap (vt,fs) ->
    let mapid  = str_to_ident "map"  in
    PTtyapp (Qident mapid, [vtyp_to_mlwtyp vt; field_storage_to_ptyp fs])
  | Ftuple l     -> PTtuple (List.map field_storage_to_ptyp l)

let mk_storage_field (f : storage_field) : field = {
  f_loc     = loc2loc (f.loc);
  f_ident   = mk_ident f.name;
  f_pty     = field_storage_to_ptyp f.typ;
  f_mutable = false;
  f_ghost   = f.ghost;
}

let mk_storage_decl (storage : storage) =
  Dtype [{
    td_loc = Loc.dummy_position;
    td_ident = { id_str = "storage"; id_ats = []; id_loc = Loc.dummy_position } ;
    td_params = [];
    td_vis = Public;
    td_mut = false;
    td_inv = [];
    td_wit = [];
    td_def = TDrecord (List.map mk_storage_field storage.fields);
  }]

(* records generation *)

let remove_option (o : 'a option) : 'a =
  match o with
  | Some v -> v
  | None -> raise (Anomaly ("remove_option"))

let mk_value_field (d : record_field_type) : field = {
  f_loc     = loc2loc (d.loc);
  f_ident   = mk_ident d.name;
  f_pty     = field_storage_to_ptyp d.typ_;
  f_mutable = false;
  f_ghost   = false;
}

let mk_records (records : record list) =
  List.map (fun (x : record) ->
  Dtype [{
    td_loc = Loc.dummy_position;
    td_ident = { id_str = x.name |> unloc; id_ats = []; id_loc = loc x.name } ;
    td_params = [];
    td_vis = Public;
    td_mut = false;
    td_inv = [];
    td_wit = [];
    td_def = TDrecord (List.map mk_value_field x.values);
  }]) records

(* storage init generation *)
let mk_init_args info (fs : storage_field list) : (lident * storage_field_type) list =
  List.fold_left (fun acc (f : storage_field) ->
      match f.default with
      | None -> (* no default value : decide which one to pass as argument *)
        begin
          match f.typ with
          | Flocal id when (is_state info id) -> acc (* state has its own initial value *)
          | Flist _ -> acc
          | Fmap _ -> acc
          | _ -> acc @ [f.name, f.typ]
        end
      | _ -> acc
    ) [] fs

type empty_container =
  | Emptylist     of storage_field_type
  | EmptyMap      of storage_field_type * storage_field_type
  | EmptySet      of storage_field_type
  | EmptyCollMap  of storage_field_type * storage_field_type

type initval =
  | Ienum   of lident
  | Ival    of bval
  | Iemptyc of empty_container
  | Iinput  of lident

let mk_init_fields info args (fs : storage_field list) : (lident * initval) list =
  let retrieve_default_value (f : storage_field) =
    begin
      match f.typ with
      | Flocal id             -> Ienum (get_initial_state info id)
      | Ftyp vt               -> Ival (mkloc Location.dummy (mk_init_val vt))
      | Flist vt              -> Iemptyc (Emptylist vt)
      | Fmap (vtf, Flist vtt) -> Iemptyc (EmptyCollMap (Ftyp vtf, vtt))
      | Fmap (vtf, ftyp)      -> Iemptyc (EmptyMap (Ftyp vtf, ftyp))
      | _                     -> raise (Anomaly "retrieve_default_value")
    end in

  List.fold_left (fun acc (f : storage_field) ->
      match f.default with
      | Some bv -> acc @ [f.name, match unloc bv with
        | Plit l -> Ival l
        | _ -> (*raise (Anomaly "mk_init_fields_0")*)
          retrieve_default_value f (* TODO: handle all kind of default value for field *)
        ]
      | None ->
         let init =
           if List.mem_assoc f.name args
           then Iinput f.name
           else (* not an input, no default value : depends on type *)
             retrieve_default_value f
         in
         acc @ [f.name, init]
    ) [] fs

let bval_to_expr info = function
  | BVint      v ->
    mk_expr (str_to_eidapp ["toint"] [mk_econst (Big_int.string_of_big_int v)])
  | BVuint     v ->
    mk_expr (str_to_eidapp ["tonat"] [mk_econst (Big_int.string_of_big_int v)])
  | BVbool     v -> mk_expr (if v then Etrue else Efalse)
  | BVenum     v -> mk_expr (str_to_eident [v])
  | BVrational (n, d) -> raise (CannotConvert (n, d))
  | BVdate     v -> mk_expr (str_to_eident [get_dummy_for info v])
  | BVstring   _ -> raise (StringUnsupported)
  | BVcurrency (_,v) ->
    mk_expr (str_to_eidapp ["totez"] [mk_econst (Big_int.string_of_big_int v)])
  | BVaddress  v ->
    mk_expr (str_to_eidapp ["toaddress"] [mk_expr (str_to_eident [get_dummy_for info v])])
  | BVduration v -> mk_econst v

let vtyp_to_acronym = function
  | VTbool       -> "bol"
  | VTint        -> "int"
  | VTuint       -> "nat"
  | VTdate       -> "tim"
  | VTduration   -> "dur"
  | VTstring     -> "str"
  | VTaddress    -> "add"
  | VTcurrency _ -> "tez"

let mk_empty_list() = mk_expr (str_to_eident ["Nil"])

let empty_cont_to_expr = function
  | Emptylist    _         -> mk_empty_list()
  | EmptyMap     (_,_) ->
    mk_expr (str_to_eidapp ["empty_map"] [mk_expr (Etuple [])])
  | EmptySet     _         ->
    mk_expr (str_to_eidapp ["empty_set"] [mk_expr (Etuple [])])
  | EmptyCollMap (_,_) ->
    mk_expr (str_to_eidapp ["empty_map"] [mk_expr (Etuple [])])

let mk_init_body info (fields : (lident * initval) list) : expr =
  let fields = fields |> List.map (fun (id,init) ->
      mk_qid [id], match init with
        | Ienum id   -> mk_expr (Eident (mk_qid [id]))
        | Ival bv    -> bval_to_expr info (unloc bv)
        | Iemptyc ec -> empty_cont_to_expr ec
        | Iinput id  -> mk_evar id) in
  mk_expr (Erecord fields)

let mk_fun_decl id args body =
  let args = List.map (fun (id, st) ->
      let id = mk_ident id in
      let ty = field_storage_to_ptyp st in
      Loc.dummy_position, Some id, false, Some ty
    ) args in
  let f = Efun(args, None, Ity.MaskVisible, empty_spec, body) in
  Dlet(str_to_ident id, false, Expr.RKnone, mk_expr f)

let mk_init_storage info (s : storage) =
  let args = mk_init_args info s.fields in
  let fields = mk_init_fields info args s.fields in
  let body = mk_init_body info fields in
  mk_fun_decl "init" args body

let vt_to_mk = function
  | VTaddress -> "mkaddress"
  | VTstring  -> "mkstring"
  | VTdate    -> "mktimestamp"
  | _ -> raise (NotFound "vt_to_ml")

let mk_dummy_decl (name,(_,vt)) =
  let body = mk_expr (str_to_eidapp [vt_to_mk vt] [mk_expr (Etuple [])]) in
  let f = Efun ([], None, Ity.MaskVisible, empty_spec, body) in
  Dlet(str_to_ident name, false, Expr.RKnone, mk_expr f)

(* generate functions *)
let field_type_to_mlwtyp (t:storage_field_type) = t |> field_storage_to_ptyp

let is_var (p : Modelws.pterm) =
  match unloc p with
  | Pvar _ -> true
  | _ -> false

let dest_var (p : Modelws.pterm) : lident =
  match unloc p with
  | Pvar id -> id
  | _ -> raise (Anomaly "dest_var")

let is_dot (p : Modelws.pterm) =
  match unloc p with
  | Pdot _ -> true
  | _ -> false

let dest_dot (p : Modelws.pterm) =
  match unloc p with
  | Pdot (l,r) -> (l,r)
  | _ -> raise (Anomaly "dest_dot")

let is_lambda (p : Modelws.pterm) =
  match unloc p with
  | Plambda _ -> true
  | _ -> false

let dest_lambda (p : Modelws.pterm) =
  match unloc p with
  | Plambda (id,t,_,b) -> (id,t,b)
  | _ -> raise (Anomaly "dest_var")

let to_big_int (n : Big_int.big_int) : BigInt.t =
  let str = Big_int.string_of_big_int n in
  BigInt.of_string str

let op_infix  s = "infix " ^ s

let rec pterm_to_expr (p : Modelws.pterm) =  {
  expr_desc =
    begin
      match unloc p with
      | Plit lit ->
        (match unloc lit with
        | BVbool true -> Etrue
        | BVbool false -> Efalse
        | BVint n -> Econst (ConstInt (Number.int_const_of_big_int (to_big_int n)))
        | BVuint n -> Econst (ConstInt (Number.int_const_of_big_int (to_big_int n)))
        | _ -> raise (Anomaly ("pterm_to_expr: literal")))
      | Pnot e -> Enot (pterm_to_expr e)
      | Plogical (op, lhs, rhs) ->
        (match op with
         | And -> Eand (pterm_to_expr lhs, pterm_to_expr rhs)
         | Or -> Eor (pterm_to_expr lhs, pterm_to_expr rhs)
         | _ -> raise (Anomaly ("pterm_to_expr: logical")))
      | Pcomp (op, lhs, rhs) ->
        (let l = pterm_to_expr lhs in
         let r = pterm_to_expr rhs in
         Eidapp (Qident (
         (match op with
           | Equal -> "="
           | Nequal -> "<>"
           | Gt -> ">"
           | Ge -> ">="
           | Lt -> "<"
           | Le -> "<="
         ) |> op_infix |> dumloc |> mk_ident), [l; r]))
      | Parith (op, lhs, rhs) ->
        (let l = pterm_to_expr lhs in
         let r = pterm_to_expr rhs in
         Eidapp (Qident (
         (match op with
         | Plus -> "+"
         | Minus -> "-"
         | Mult -> "*"
         | Div -> "/"
         | Modulo -> "%"
         (*| _ -> raise (Anomaly ("pterm_to_expr: arith"))*)
         ) |> op_infix |> dumloc |> mk_ident), [l; r]))
      | Puarith (op, p) ->
        let e = pterm_to_expr p in
        Eidapp (Qident (
         (match op with
         | Uplus -> "+"
         | Uminus -> "-" ) |> op_infix |> dumloc |> mk_ident), [e])
      | Pif (cond, then_, else_) ->
        Eif (pterm_to_expr cond,
             pterm_to_expr then_,
             match else_ with
             | Some e ->  pterm_to_expr e
             | _ -> mk_unit())
      | Pvar id -> Eident (mk_qid [id])
      | Papp (f, l) when is_var f ->
        let fid =  dest_var f in
        let l = if List.length l = 0
          then [mk_unit ()]
          else List.map pterm_to_expr l in
        Eidapp (mk_qid [fid], l)
      | Papp (f, l) when is_dot f ->
        let (m,r) =  dest_dot f in
        if is_var m && is_var r
        then
          let mid = dest_var m in
          let rid = dest_var r in
        let l = if List.length l = 0
          then [mk_unit ()]
          else List.map pterm_to_expr l in
          Eidapp (mk_qid [mid;rid], l)
        else raise (Anomaly ("pterm_to_expr : "^(Modelws.show_pterm p)))
      | Plambda (i,t,s,b) -> mk_efun [] (loc p) i t s b
      | Pmatchwith (e, l) -> Ematch (pterm_to_expr e, List.map to_regbranch l, [])
      | Pletin (n,v,_,b) -> Elet (mk_ident n, false, Expr.RKnone, pterm_to_expr v, pterm_to_expr b)
      | Ptuple l -> Etuple (List.map pterm_to_expr l)
      | Pseq (lhs, rhs) -> Esequence (pterm_to_expr lhs, pterm_to_expr rhs)
      | Precord l -> Erecord (List.map (fun (i, e) -> (mk_qualid i, pterm_to_expr e)) l)
      | Pdot (x, y) ->
        (
          let to_qualid (x : (pterm * pterm)) : Ptree.qualid =
            let rec to_quald (z : pterm) : Ptree.qualid =
              match unloc z with
              | Pvar i -> Qident (mk_ident i)
              | Pdot (a, {pldesc = Pvar b; _}) -> Qdot(to_quald a, mk_ident b)
              | _ -> raise (Anomaly "to_quald: cannot convert to qualid ") in
            let x, y = x in
            match unloc y with
            | Pvar b -> Qdot (to_quald x, mk_ident b)
            | _ -> raise (Anomaly "to_qualid: cannot convert to qualid ") in
          Eident (to_qualid (x, y))
        )
      (* TODO : continue mapping *)
      | _ -> raise (Anomaly ("pterm_to_expr : "^(Modelws.show_pterm p)))
    end;
  expr_loc = loc p
}

and mk_efun args l i t s b =
  let t = map_option field_type_to_mlwtyp t in
  let args = args @ [l, Some (mk_ident i), false, t] in
  if is_lambda b
  then
    let (i,t,b) = dest_lambda b in
    mk_efun args (loc b) i t s b
  else
    let spec =
      if s
      then { empty_spec with
             sp_xpost = [ Loc.dummy_position, [ Qident (mk_ident (dumloc "Side")), None ] ];
           }
      else empty_spec in
    Efun (args, None, Ity.MaskVisible, spec, pterm_to_expr b)
and to_regbranch r : reg_branch =
  let pat, e = r in
  (mk_pattern pat, pterm_to_expr e)
and mk_pattern (p : Modelws.pattern) : Ptree.pattern =
  { pat_desc = (
      match unloc p with
        | Mwild -> Pwild
        | Mvar i -> Pvar (mk_ident i)
        | Mapp (q, l) -> Papp (mk_qualid q, List.map mk_pattern l)
        | Mrec l -> Prec (List.map (fun (q, p) -> (mk_qualid q, mk_pattern p)) l)
        | Mtuple l -> Ptuple (List.map mk_pattern l)
        | Mas (p, i, b) -> Pas (mk_pattern p, mk_ident i, b)
        | Mor (lhs, rhs) -> Por (mk_pattern lhs, mk_pattern rhs)
        | Mcast (p, t) -> Pcast (mk_pattern p, field_type_to_mlwtyp t)
        | Mscope (q, p) -> Pscope (mk_qualid q, mk_pattern p)
        | Mparen p -> Pparen (mk_pattern p)
        | Mghost p -> Pghost (mk_pattern p)
    );
    pat_loc = Loc.dummy_position;
}
and mk_qualid (q : lident Model.qualid) : Ptree.qualid =
  match q with
  | Qident i -> Qident (mk_ident i)
  | Qdot (q, i) -> Qdot (mk_qualid q, mk_ident i)

and mk_unit () = {
  expr_desc = Etuple [];
  expr_loc = Loc.dummy_position;
}

let rec mk_lambda (args : (storage_field_type,bval) gen_decl list) side body : Modelws.pterm =
  match args with
  | [a]   -> mkloc a.loc (Plambda (a.name, a.typ, side, body))
  | a::tl -> mkloc a.loc (Plambda (a.name, a.typ, side, mk_lambda tl side body))
  | []    -> body

let mk_empty_ops () =
  Dlet(str_to_ident "empty_ops", false, Expr.RKnone, mk_empty_list())

let mk_function_decl (f : function_ws) =
  (*print_endline ("fun : "^(unloc f.name)^" side : "^(string_of_bool f.side));*)
  let body = mk_lambda f.args f.side f.body in
  (*print_endline ("body : "^(show_pterm body));*)
  Dlet (mk_ident f.name, false, Expr.RKnone, pterm_to_expr body)

let mk_transaction (f : transaction_ws) =
  let action = match f.action with
    | None -> raise (Modelinfo.Anomaly "no action in transaction")
    | Some e -> e in
  let body = mk_lambda f.args f.side action in
  Dlet (mk_ident f.name, false, Expr.RKnone, pterm_to_expr body)

(* returns a list of definition *)
let modelws_to_modelliq (info : info) (m : model_with_storage) =
  Liq_printer.set_entries
    { !Liq_printer.entries with
      init = Some "init";
      entries = List.map (fun (x : transaction_ws) -> unloc (x.name)) m.transactions;
      inlines = List.map (fun (x : function_ws) -> unloc (x.name)) m.functions;
      dummies = List.map (fun (n,(v,_)) -> (n,v)) info.dummy_vars;
    };
  []
  (*  |> (fun x -> x @ [mk_empty_ops()])*)
  |> (fun x -> List.fold_left (fun acc d -> acc @ [mk_dummy_decl d]) x info.dummy_vars)
  |> (fun x -> List.fold_left (fun acc e -> acc @ [mk_enum_decl e]) x m.enums)
  |> (fun x -> x @ mk_records m.records)
  |> (fun x -> x @ [mk_storage_decl m.storage])
  |> (fun x -> x @ [mk_init_storage info m.storage])
  |> (fun x -> List.fold_left (fun acc f -> acc @ [mk_function_decl f]) x m.functions)
  |> (fun x -> List.fold_left (fun acc f -> acc @ [mk_transaction f]) x m.transactions);
