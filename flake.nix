{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { nixpkgs, ... }@inputs:
    {
      generateOutputs =
        {
          self,
          ...
        }:
        let
          inherit (self) outputs;
          lib = import ./lib {
            inherit inputs self;
          };
        in
        {
          lib = lib;
          nixosConfigurations = {
            thaumaturge = lib.mkHost {
              hostname = "thaumaturge";
              username = "mcarthur";
              system = "x86_64-linux";
              desktop = "alucard-niri";
            };
          };
        };
    };
}
