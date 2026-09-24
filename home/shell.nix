# zsh as the interactive shell, with a starship prompt.
{ config, ... }:

{
  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh"; # keep ~ free of .zshrc and friends
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    history = {
      path = "${config.xdg.stateHome}/zsh/history";
      size = 50000;
      save = 50000;
      ignoreDups = true;
      ignoreSpace = true; # a leading space keeps a command out of history
      share = true;
    };
  };

  # The prompt's symbols render with the AdwaitaMono Nerd Font foot uses.
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };
}
