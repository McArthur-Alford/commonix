{ self, inputs, ... }:
rec {
  mkHosts =
    configurations:
    if configurations == [ ] then
      {
        homeConfigurations = { };
        nixosConfigurations = { };
      }
    else
      let
        head = builtins.head configurations;
        tail = builtins.tail configurations;
        combined = mkHosts tail;
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
            inherit systemSettings self;
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
    let
      head = builtins.head userSettings;
    in
    if userSettings == [ ] then
      { }
    else
      (
        {
          "${head.user}@${systemSettings.hostname}" = (
            mkHome {
              userSettings = head;
              inherit systemSettings;
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
      pkgs = import inputs.nixpkgs {
        config.allowUnfree = true;
        system = systemSettings.system;
      };
      extraSpecialArgs = {
        inherit userSettings inputs;
      };
      modules = userSettings.modules;
    };

  notNull = x: f: if x == null then [ ] else (f x);
  optionalFile = path: if builtins.pathExists "${self}/${path}" then [ "${self}/${path}" ] else [ ];
  requireFile =
    path:
    let
      file = (optionalFile path);
    in
    assert builtins.pathExists "${self}/${path}";
    file;

  loadAllSystems = builtins.concatMap (file: [
    (loadSystemSettings (import "${self}/settings/hosts/${file}"))
  ]) (builtins.attrNames (builtins.readDir "${self}/settings/hosts"));

  loadSystemSettings =
    {
      hostname, # system hostname
      system ? "x86_64-linux",
      kernel ? "latest",
      users ? [ ], # list of user names
    }:
    assert builtins.isString hostname;
    assert builtins.isList users;
    assert builtins.all (
      user:
      !(
        builtins.pathExists "${self}/hosts/${hostname}/users/${user}.nix"
        && builtins.pathExists "${self}/hosts/${hostname}/users/${user}"
      )
    ) users;
    let
      userSettings = builtins.map (
        user: loadUserSettings (import ("${self}/settings/users/${user}.nix"))
      ) users;
    in
    {
      inherit userSettings;
      systemSettings = rec {
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
          ++ (optionalFile "hosts/${hostname}/default.nix")

          # Config for ALL hosts for each supported user:
          ++ (builtins.concatMap (user: optionalFile "users/${user}/system/default.nix") users)

          # Universal modules that are always loaded
          ++ (optionalFile "modules/default.nix")

          # User specific configuration
          ++ (builtins.concatMap (
            userSettings:
            let
              user = userSettings.user;
            in
            # User config:
            optionalFile "hosts/${hostname}/users/${user}.nix"
            ++ optionalFile "hosts/${hostname}/users/${user}/default.nix"

            # User system config (ideally not necessary):
            ++ optionalFile "users/${user}/system/default.nix"

            # User specified desktop environment:
            ++ (notNull userSettings.gui.desktop (desktop: requireFile "modules/desktop/${desktop}.nix"))
            ++ (notNull userSettings.gui.protocol (protocol: requireFile "modules/protocol/${protocol}.nix"))
          ) userSettings)

          # The kernel
          ++ (requireFile "modules/kernel/${kernel}.nix");
      };
    };

  loadUserSettings =
    {
      user,
      gui ? {
        protocol = null; # wayland or x11
        desktop = null; # hyprland, sway, gnome, niri, etc
      },
      ...
    }:
    assert builtins.isString user;
    assert
      !(builtins.pathExists "${self}/users/${user}.nix" && builtins.pathExists "${self}/users/${user}");
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
