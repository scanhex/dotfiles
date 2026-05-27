{ inputs, system, ... }:
let
  clangToolsDarwinOverlay = final: prev:
    if prev == null then
      { }
    else
      let
        clang = prev.llvmPackages_22.clang;
        queryDrivers = prev.lib.concatStringsSep "," [
          (prev.lib.getExe clang)
          (prev.lib.getExe' clang "clang++")
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
          clang-tools = wrapClangTools prev.llvmPackages_22.clang-tools;
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
    };

    openldap = prev.openldap.overrideAttrs (_: {
      doCheck = false;
    });
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
