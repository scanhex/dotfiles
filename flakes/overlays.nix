{self, ...}:
{
    flake.overlays.default = (final: prev: 
      { 
      bash-completion = prev.bash-completion.overrideAttrs (old:  
          {
            src = builtins.fetchurl {
              url = "https://github.com/scop/bash-completion/releases/download/2.11/bash-completion-2.11.tar.xz";
              sha256 = "1b0iz7da1sgifx1a5wdyx1kxbzys53v0kyk8nhxfipllmm5qka3k";
            };
          });
      delta = prev.delta.overrideAttrs (old: 
        {
          postInstall = "";
        });
      });
}
