# Installing Archtype via Nix (instead of opam)
## Directly via fetchFromGitHub
### `nix-shell`

Create `archetype-shell.nix` (or add to your own .nix file if appropriate):
```
with import <nixpkgs> {};

let archetypeSrc = ( pkgs.fetchFromGitHub {
    owner  = "Coda-Coda";
    repo   = "archetype-lang";
    rev    = "b3b41d6da3581e915f4aecf4f9395e0d105b4dfa";
    sha256 = "0y7mx9d031177wj053rhny1bpm8rxnjzg03zz6821ws4hz2qgrx0"; } );
in
stdenv.mkDerivation {

  name = "archetype-env";

  buildInputs =
    [
        (import "${archetypeSrc}")
    ]
    ;

}
```
Then run `nix-shell archetype-shell.nix`

### `nix-env` and `nix-build`

Create `archetype.nix` (or add to your own .nix file if appropriate):
```
with import <nixpkgs> {};

let archetypeSrc = ( pkgs.fetchFromGitHub {
    owner  = "Coda-Coda";
    repo   = "archetype-lang";
    rev    = "b3b41d6da3581e915f4aecf4f9395e0d105b4dfa";
    sha256 = "0y7mx9d031177wj053rhny1bpm8rxnjzg03zz6821ws4hz2qgrx0"; } );
in
[
    (import "${archetypeSrc}")
]
```
Then run `nix-env -i -f archetype.nix` or `nix-build archetype.nix`

## By downloading
```
git clone https://github.com/Coda-Coda/archetype-lang.git
cd archetype-lang
nix-shell # or nix-build or nix-env -if default.nix
```

## Updating dependencies

> Note: after making any updates, if using fetchFromGitHub, the `rev` and `sha256` hashes need to be updated. `rev` is the commit hash, and `sha256` can be found by running: `nix-prefetch-url --unpack https://github.com/Coda-Coda/archetype-lang/archive/NEW-COMMIT-HASH.tar.gz`

You can run the following to regenerate opam2nix.nix after changes to any of archetype's dependencies:
`nix-shell -A resolve helper.nix`

Note: opam2nix does not work well with some more recent versions of digestif. The relevant fix was made in commit `ca406363dd109740e0f917f525edec694c88235d`. (Note that some more recent versions than 0.7.4 may work but have not been tested. 0.7.2 and 0.7.3 seem to allow archetype to build successfully). See also [the issue in opam2nix](https://github.com/timbertson/opam2nix/issues/37).