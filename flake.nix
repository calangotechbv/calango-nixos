{
  description = "calango-nixos: the calango Hyprland desktop on NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }:
    let
      mkHost = { hostname, username ? "isutton", system ? "x86_64-linux", modules }:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit self username; };
          modules = [
            ./nixos/common.nix
            ./nixos/desktop.nix
            ./nixos/audio.nix
            ./nixos/apps.nix
            ./nixos/endpoint-verification.nix
            home-manager.nixosModules.home-manager
            {
              networking.hostName = hostname;
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                # A real file where home-manager wants a link (Hyprland's
                # generated hyprland.lua, a pre-NixOS ~/.config) is renamed
                # to <name>.hm-backup instead of failing the activation.
                backupFileExtension = "hm-backup";
                extraSpecialArgs = { inherit username hostname; };
                users.${username} = import ./home;
              };
            }
          ] ++ modules;
        };
    in
    {
      nixosConfigurations = {
        vm = mkHost {
          hostname = "vm";
          modules = [ ./hosts/vm ];
        };
      };

      # nix run .#vm boots the test host in QEMU.
      apps.x86_64-linux.vm = {
        type = "app";
        program = "${self.nixosConfigurations.vm.config.system.build.vm}/bin/run-vm-vm";
        meta.description = "Boot the vm test host in QEMU";
      };

      checks.x86_64-linux = import ./checks.nix {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        nixos = self.nixosConfigurations.vm;
        username = "isutton";
      };
    };
}
