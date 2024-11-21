{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
          configs = lib.mkHosts (builtins.map (x: lib.mkHost x) lib.loadAllSystems);
        in
        {
          helpers = lib;

          homeConfigurations = configs.homeConfigurations;
          nixosConfigurations = configs.nixosConfigurations;
        };
    };
}
