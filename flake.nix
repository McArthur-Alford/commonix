{
  inputs = { };

  outputs =
    { ... }:
    {
      generateOutputs =
        {
          self,
          inputs,
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
