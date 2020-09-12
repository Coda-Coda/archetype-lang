with import <nixpkgs> {};

stdenv.mkDerivation {

  name = "archetype-env";

  # src = ./.;

  buildInputs =
    [
       (import ./default.nix )
    ]
    ;

}