{ inputs, system, ... }:
let
  clangToolsDarwinOverlay = final: prev:
    if prev == null then
      { }
    else
      let
        queryDrivers = prev.lib.concatStringsSep "," [
          "/nix/store/*-clang-wrapper-*/bin/clang"
          "/nix/store/*-clang-wrapper-*/bin/clang++"
        ];

        wrapClangTools = clangTools:
          clangTools.overrideAttrs (old: {
            postInstall = (old.postInstall or "") + ''
              if [ -x "$out/bin/clangd" ]; then
                substituteInPlace "$out/bin/clangd" \
                  --replace-warn 'extendcpath=true' 'extendcpath=false' \
                  --replace-warn '$(basename $0)-unwrapped "$@"' '$(basename $0)-unwrapped --query-driver='"'"'${queryDrivers}'"'"' "$@"'
              fi
            '';
          });
      in
      if prev.stdenv.hostPlatform.isDarwin then
        {
          llvmPackages_21 = prev.llvmPackages_21.overrideScope (_: llvmPrev: {
            clang-tools = wrapClangTools llvmPrev.clang-tools;
          });
          clang-tools = final.llvmPackages_21.clang-tools;
        }
      else
        { };
in
[
#  (import "${inputs.nixpkgs}/pkgs/top-level/by-name-overlay.nix" ../pkgs/by-name)
  clangToolsDarwinOverlay
  (final: prev: {
    unstable = import inputs.nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
      overlays = [ clangToolsDarwinOverlay ];
    };
#      bash-completion = prev.bash-completion.overrideAttrs (old:
#          {
#          src = builtins.fetchurl {
#          url = "https://github.com/scop/bash-completion/releases/download/2.11/bash-completion-2.11.tar.xz";
#          sha256 = "1b0iz7da1sgifx1a5wdyx1kxbzys53v0kyk8nhxfipllmm5qka3k";
#          };
#          });
#      delta = prev.delta.overrideAttrs (old:
#          {
#          postInstall = "";
#          });
  })
]
