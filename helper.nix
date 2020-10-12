# standalone derivation, for nix-build, nix-shell, etc
{ pkgs ? import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/89281dd1dfed6839610f0ccad0c0e493606168fe.tar.gz") {}, opam2nix ? import ./opam2nix.nix }:
pkgs.callPackage ./nix { inherit opam2nix; }
