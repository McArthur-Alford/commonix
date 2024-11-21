{ self, inputs, ... }:
rec {
  mkHosts =
    { configurations }:
    if configurations == [ ] then
      {
        homeConfigurations = { };
        nixosConfigurations = { };
      }
    else
      let
        head = builtins.head configurations;
        tail = builtins.tail configurations;
        combined = mkHosts { inherit tail; };
      in
      {
        homeConfigurations = head.homeConfigurations // combined.homeConfigurations;
        nixosConfigurations = head.nixosConfigurations // combined.nixosConfigurations;
      };

  mkHost =
    { userSettings, systemSettings }:
    {
      nixosConfigurations = {
        "${systemSettings.hostname}" = inputs.nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit systemSettings;
          };
          modules = systemSettings.modules;
        };
      };

      homeConfigurations = (
        mkHomes {
          inherit userSettings systemSettings;
        }
      );
    };

  mkHomes =
    {
      userSettings,
      systemSettings,
      userConfigurations ? { },
    }:
    if userSettings == [ ] then
      { }
    else
      (
        {
          "${userSettings.username}@${systemSettings.hostname}" = (
            mkHome {
              userSettings = builtins.head userSettings;
            }
          );
        }
        // (mkHomes {
          userSettings = builtins.tail userSettings;
          inherit systemSettings userConfigurations;
        })
      );

  mkHome =
    { userSettings, systemSettings }:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = inputs.nixpkgs.${systemSettings.system};
      extraSpecialArgs = {
        inherit userSettings inputs;
      };
      modules = userSettings.modules;
    };

  notNull = x: f: if x == null then [ ] else [ ];
  optionalFile = path: if builtins.pathExists "${self}/${path}" then [ "${self}/${path}" ] else [ ];
  requireFile =
    path:
    let
      file = (optionalFile path);
    in
    assert builtins.pathExists "${self}/${path}";
    file;

  loadSystemSettings =
    {
      hostname, # system hostname
      system ? "x86_64-linux",
      kernel ? "latest",
      users ? [ ], # list of user names
    }:
    assert builtins.isString hostname;
    assert builtins.isList users;
    rec {
      inherit
        hostname
        system
        kernel
        users
        ;
      modules =
        # Universal config
        (optionalFile "hosts/default.nix")

        # Host specific config
        ++ (optionalFile "hosts/${hostname}/configuration.nix")
        ++ (optionalFile "hosts/${hostname}/hardware-configuration.nix")

        # Config specific to THIS host for each supported user:
        ++ (builtins.concatMap (user: optionalFile "hosts/${hostname}/users/${user}.nix") users)
        ++ (builtins.concatMap (user: optionalFile "hosts/${hostname}/users/${user}/default.nix") users)

        # Config for ALL hosts for each supported user:
        ++ (builtins.concatMap (user: optionalFile "users/${user}/system/default.nix") users)

        # Universal modules that are always loaded
        ++ (optionalFile "modules/default.nix")

        # The desktop

        # The kernel
        ++ (requireFile "modules/kernel/${kernel}.nix");
    };

  loadUserSettings =
    {
      user,
      gui ? {
        protocol = null; # wayland or x11
        desktop = null; # hyprland, sway, gnome, niri, etc
      },
    }:
    assert builtins.isString user;
    {
      inherit user gui;
      modules =
        # The users universal config, either a directory or .home.nix file:
        (optionalFile "users/${user}/default.home.nix")
        ++ (optionalFile "users/${user}.home.nix")

        # The users host-specific config, if it exists:
        ++ (notNull gui.desktop (desktop: requireFile "modules/desktop/${desktop}.home.nix"))
        ++ (notNull gui.protocol (protocol: requireFile "modules/protocol/${protocol}.home.nix"));
    };

  forAllSystems = inputs.nixpkgs.lib.genAttrs [
    "aarch64-linux"
    "i686-linux"
    "x86_64-linux"
    "aarch64-darwin"
    "x86_64-darwin"
    "armv6l-linux"
    "armv7l-linux"
  ];
}
