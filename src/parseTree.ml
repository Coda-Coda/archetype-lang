(* -------------------------------------------------------------------- *)
open Ident
open Location

(* -------------------------------------------------------------------- *)
type lident = ident loced
[@@deriving yojson]

let pp_lident fmt i = Format.fprintf fmt "%s" (unloc i)

(* -------------------------------------------------------------------- *)
type container =
  | Collection
  | Queue
  | Stack
  | Set
  | Partition
[@@deriving yojson, show {with_path = false}]

type type_r =
  | Tref of lident
  | Tcontainer of type_t * container
  | Tvset of lident * type_t
  | Tapp of type_t * type_t
  | Ttuple of type_t list
[@@deriving yojson, show {with_path = false}]

and type_t = type_r loced
[@@deriving yojson, show {with_path = false}]

(* -------------------------------------------------------------------- *)
type logical_operator =
  | And
  | Or
  | Imply
  | Equiv
[@@deriving yojson, show {with_path = false}]

type comparison_operator =
  | Equal
  | Nequal
  | Gt
  | Ge
  | Lt
  | Le
[@@deriving yojson, show {with_path = false}]

type arithmetic_operator =
  | Plus
  | Minus
  | Mult
  | Div
  | Modulo
[@@deriving yojson, show {with_path = false}]

type unary_operator =
  | Uplus
  | Uminus
  | Not
[@@deriving yojson, show {with_path = false}]

type assignment_operator =
  | ValueAssign
  | SimpleAssign
  | PlusAssign
  | MinusAssign
  | MultAssign
  | DivAssign
  | AndAssign
  | OrAssign
[@@deriving yojson, show {with_path = false}]

type quantifier =
  | Forall
  | Exists
[@@deriving yojson, show {with_path = false}]

type operator = [
  | `Logical of logical_operator
  | `Cmp     of comparison_operator
  | `Arith   of arithmetic_operator
  | `Unary   of unary_operator
]
[@@deriving yojson, show {with_path = false}]

type qualid =
  | Qident of lident
  | Qdot of qualid * lident
[@@deriving yojson, show {with_path = false}]

type name = lident option * lident
[@@deriving yojson, show {with_path = false}]

type pattern_unloc =
  | Pwild
  | Pref of lident
[@@deriving yojson, show {with_path = false}]

type pattern = pattern_unloc loced
[@@deriving yojson, show {with_path = false}]

type expr_r =
  | Eterm         of name
  | Eop           of operator
  | Eliteral      of literal
  | Earray        of expr list
  | Erecord       of record_item list
  | Etuple        of expr list
  | Edot          of expr * lident
  | Eapp          of expr * expr list
  | Etransfer     of expr * bool * qualid option
  | Eassign       of assignment_operator * expr * expr
  | Eif           of expr * expr * expr option
  | Ebreak
  | Efor          of lident * expr * expr
  | Eassert       of expr
  | Eseq          of expr * expr
  | Efun          of lident_typ list * expr
  | Eletin        of lident_typ * expr * expr * expr option
  | Ematchwith    of expr * (pattern list * expr) list
  | Equantifier   of quantifier * lident_typ * expr
  | Elabel        of lident * expr
[@@deriving yojson, show {with_path = false}]

and literal =
  | Lnumber   of Core.big_int
  | Lrational of Core.big_int * Core.big_int
  | Ltz       of Core.big_int
  | Laddress  of string
  | Lstring   of string
  | Lbool     of bool
  | Lduration of string
  | Ldate     of string
[@@deriving yojson, show {with_path = false}]

and record_item = (assignment_operator * lident) option * expr

and expr = expr_r loced
[@@deriving yojson, show {with_path = false}]

and lident_typ = lident * type_t option * extension list option
[@@deriving yojson, show {with_path = false}]

and label_exprs = (lident option * expr) list

(* -------------------------------------------------------------------- *)
and extension_r =
 | Eextension of lident * expr list option (** extension *)
[@@deriving yojson, show {with_path = false}]

and extension = extension_r loced
[@@deriving yojson, show {with_path = false}]

and exts = extension list option
[@@deriving yojson, show {with_path = false}]

(* -------------------------------------------------------------------- *)
type field_r =
  | Ffield of lident * type_t * expr option * extension list option   (** field *)
[@@deriving yojson, show {with_path = false}]

and field = field_r loced
[@@deriving yojson, show {with_path = false}]


type transition_r = (lident * expr option * expr option) list
[@@deriving yojson, show {with_path = false}]

type args = lident_typ list
[@@deriving yojson, show {with_path = false}]

type verification_item_unloc =
  | Vpredicate of lident * args * expr
  | Vdefinition of lident * type_t * lident * expr
  | Vaxiom of lident * expr
  | Vtheorem of lident * expr
  | Vvariable of lident * type_t * expr option
  | Vinvariant of lident * expr
  | Veffect of expr
  | Vspecification of label_exprs
[@@deriving yojson, show {with_path = false}]

type verification_item = verification_item_unloc loced
[@@deriving yojson, show {with_path = false}]

type verification_unloc = verification_item list * exts
[@@deriving yojson, show {with_path = false}]

type verification = verification_unloc loced
[@@deriving yojson, show {with_path = false}]

type s_function = {
  name  : lident;
  args  : args;
  ret_t : type_t option;
  verif : verification option;
  body  : expr;
}
[@@deriving yojson, show {with_path = false}]

type action_properties = {
  calledby   : (expr * extension list option) option;
  condition  : (label_exprs * extension list option) option;
  functions  : s_function list;
  verif      : verification option;
}
[@@deriving yojson, show {with_path = false}]

(* -------------------------------------------------------------------- *)
type declaration_r =
  | Darchetype     of lident * exts
  | Dvariable      of lident * type_t * expr option * value_option list option * bool * exts
  | Denum          of lident * lident list * exts
  | Dstates        of lident option * (lident * state_option list option) list option * exts
  | Dasset         of lident * field list option * asset_option list option * asset_post_option list * asset_operation option * exts
  | Dobject        of lident * expr * exts
  | Dkey           of lident * expr * exts
  | Daction        of lident * args * action_properties * (expr * exts) option * exts
  | Dtransition    of lident * args * (lident * lident) option * expr * action_properties * transition_r * exts
  | Dcontract      of lident * signature list * expr option * exts
  | Dextension     of lident * expr list option
  | Dnamespace     of lident * declaration list
  | Dfunction      of s_function
  | Dverification  of verification
[@@deriving yojson, show {with_path = false}]

and value_option =
  | VOfrom of qualid
  | VOto of qualid
[@@deriving yojson, show {with_path = false}]

and asset_option =
  | AOasrole
  | AOidentifiedby of lident
  | AOsortedby of lident
[@@deriving yojson, show {with_path = false}]

and asset_post_option =
  | APOstates of lident
  | APOconstraints of expr
  | APOinit of expr
[@@deriving yojson, show {with_path = false}]

and state_option =
  | SOinitial
  | SOspecification of label_exprs
[@@deriving yojson, show {with_path = false}]

and signature =
  | Ssignature of lident * type_t list
[@@deriving yojson, show {with_path = false}]

and declaration = declaration_r loced
[@@deriving yojson, show {with_path = false}]

and asset_operation_enum =
  | AOadd
  | AOremove
  | AOupdate
[@@deriving yojson, show {with_path = false}]

and asset_operation =
  | AssetOperation of asset_operation_enum list * expr list option
[@@deriving yojson, show {with_path = false}]

(* -------------------------------------------------------------------- *)
type archetype_unloc =
  | Marchetype of declaration list
  | Mextension of lident * declaration list * declaration list
[@@deriving yojson, show {with_path = false}]

and archetype = archetype_unloc loced
[@@deriving yojson, show {with_path = false}]
