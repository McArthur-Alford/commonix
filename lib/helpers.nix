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
    let
      nixosConfigurations = {
        "${systemSettings.hostname}" = inputs.nixpkgs.lib.nixosSystem {
          specialArgs = {
            inherit systemSettings self inputs;
          };
          modules = systemSettings.modules;
        };
      };
    in
    {
      inherit nixosConfigurations;

      homeConfigurations = (
        mkHomes {
          inherit userSettings systemSettings;
          nixosConfigurations = nixosConfigurations."${systemSettings.hostname}";
        }
      );
    };

  mkHomes =
    {
      userSettings,
      systemSettings,
      nixosConfigurations,
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
              inherit systemSettings nixosConfigurations;
            }
          );
        }
        // (mkHomes {
          userSettings = builtins.tail userSettings;
          inherit systemSettings userConfigurations nixosConfigurations;
        })
      );

  mkHome =
    {
      userSettings,
      systemSettings,
      nixosConfigurations,
    }:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        config.allowUnfree = true;
        system = systemSettings.system;
      };
      extraSpecialArgs = {
        inherit
          userSettings
          systemSettings
          self
          inputs
          ;
        osConfig = nixosConfigurations.config;
      };
      modules =
        userSettings.modules
        ++ (optionalFile "users/${userSettings.user}/${systemSettings.hostname}/default.home.nix");
    };

  notNull = x: f: if x == null then [ ] else (f x);
  optionalFile = path: if builtins.pathExists "${self}/${path}" then [ "${self}/${path}" ] else [ ];
  requireFile =
    path:
    let
      file = (optionalFile path);
    in
    assert
      builtins.pathExists "${self}/${path}"
      || builtins.throw "The file '${path}' does not exist at '${self}'";
    file;

  loadAllSystems = builtins.concatMap (file: [
    (loadSystemSettings (import "${self}/settings/hosts/${file}"))
  ]) (builtins.attrNames (builtins.readDir "${self}/settings/hosts"));

  loadSystemSettings =
    {
      hostname, # system hostname
      stateVersion, # system state version
      system ? "x86_64-linux",
      kernel ? "latest",
      users ? [ ], # list of user names
      trustedUsers ? [ ], # trusted users
      nixPath ? "/etc/nixos",
      misc,
      ...
    }:
    assert builtins.isString hostname || builtins.throw "Hostname is not a string: ${hostname}";
    assert builtins.isList users || builtins.throw "Users is not a list: ${users}";
    assert
      builtins.all (
        user:
        !(
          builtins.pathExists "${self}/hosts/${hostname}/users/${user}.nix"
          && builtins.pathExists "${self}/hosts/${hostname}/users/${user}"
        )
        # TODO: I dont really no what this one is lol
      ) users
      || builtins.throw "Cannot find user configs?";
    let
      userSettings = builtins.map (
        user: loadUserSettings (import ("${self}/settings/users/${user}.nix") // { inherit hostname; })
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
          stateVersion
          trustedUsers
          nixPath
          misc
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
            ++ (notNull userSettings.gui.${userSettings.hostname}.desktop (
              desktop: requireFile "modules/desktop/${desktop}.nix"
            ))
            ++ (notNull userSettings.gui.${userSettings.hostname}.protocol (
              protocol: requireFile "modules/protocol/${protocol}.nix"
            ))
            ++ (notNull userSettings.gui.${userSettings.hostname}.desktop (
              desktop: requireFile "modules/desktop/default.nix"
            ))
          ) userSettings)

          # The kernel
          ++ (requireFile "modules/kernel/${kernel}.nix");
      };
    };

  loadUserSettings =
    {
      user,
      gui ? {
        default = {
          desktop = null; # hyprland, sway, gnome, niri, etc
          protocol = null; # wayland or x11
        };
      },
      theme,
      hostname,
      ...
    }:
    assert builtins.isString user || builtins.throw "User: ${user} is not a string";
    assert
      !(
        builtins.pathExists "${self}/users/${user}.home.nix" && builtins.pathExists "${self}/users/${user}"
      )
      || builtins.throw "User configs for ${user} not found";
    let
      hostnameOrDefault = if gui ? hostname then hostname else "default";
    in
    {
      inherit
        user
        gui
        theme
        ;
      hostname = hostnameOrDefault;
      modules =
        # The users universal config, either a directory or .home.nix file:
        (optionalFile "users/${user}/default.home.nix")
        ++ (optionalFile "users/${user}.home.nix")
        ++ (optionalFile "users/default.home.nix")

        # The users host-specific config, if it exists:
        ++ (notNull gui.${hostnameOrDefault}.desktop (
          desktop: requireFile "modules/desktop/${desktop}.home.nix"
        ))
        ++ (notNull gui.${hostnameOrDefault}.protocol (
          protocol: requireFile "modules/protocol/${protocol}.home.nix"
        ))

        ++ (notNull theme (theme: requireFile "modules/programs/stylix.home.nix"));
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
