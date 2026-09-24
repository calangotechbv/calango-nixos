# What every host shares at the system level.
{ pkgs, username, ... }:

{
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "@wheel" ];
  };

  time.timeZone = "Europe/Amsterdam";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  networking.networkmanager.enable = true;

  # System side of zsh: /etc/zshenv, /etc/shells and completion for system
  # packages. The user's own zsh setup is home/shell.nix.
  programs.zsh.enable = true;

  users.users.${username} = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "input" ];
  };

  environment.systemPackages = with pkgs; [ git vim ];

  system.stateVersion = "26.05";
}
