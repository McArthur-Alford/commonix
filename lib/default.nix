{ inputs, self, ... }:
let
  helpers = import ./helpers.nix {
    inherit inputs self;
  };
in
{
  inherit (helpers)
    mkHome
    mkHost
    mkHosts
    forAllSystems
    getFile
    requireFile
    getDir
    loadSystemSettings
    loadUserSettings
    loadAllSystems
    ;
}
