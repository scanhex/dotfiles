{
  description = "Whisper Dictation - A lightweight dictation app using OpenAI API with global hotkey support";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
    crane.url = "github:ipetkov/crane";
  };

  outputs = { self, nixpkgs, flake-utils, crane }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          pyaudio
          requests
          numpy
          pyperclip
          pyxdg
          xlib
          evdev
        ] ++ pkgs.lib.optional (pkgs.stdenv.hostPlatform.system != "aarch64-darwin" && pkgs.stdenv.hostPlatform.system != "x86_64-darwin") ps.pynput);

        craneLib = crane.mkLib pkgs;

        commonArgs = {
          src = self;
          nativeBuildInputs = [ pkgs.iconv ] ++ pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.pkg-config pkgs.makeWrapper ];
          buildInputs = pkgs.lib.optionals pkgs.stdenv.isLinux [ pkgs.openssl pkgs.alsa-lib pkgs.udev pkgs.xorg.libX11 pkgs.xorg.libXi pkgs.xorg.libXtst pkgs.xdotool pkgs.wtype ];
        };

        deps = craneLib.buildDepsOnly (commonArgs // {
          cargoExtraArgs = pkgs.lib.optionalString pkgs.stdenv.isLinux "--features wayland";
        });

        rustApp = craneLib.buildPackage (commonArgs // {
          inherit deps;
          pname = "whisper";
          version = "0.1.0";
          cargoExtraArgs = pkgs.lib.optionalString pkgs.stdenv.isLinux "--features wayland";
          postInstall = ''
            if [ "${pkgs.stdenv.hostPlatform.system}" = "x86_64-linux" ] || \
                [ "${pkgs.stdenv.hostPlatform.system}" = "aarch64-linux" ]; then
              wrapProgram $out/bin/whisper \
              --prefix PATH : ${pkgs.wtype}/bin
            fi
          '';
        });
      in
      {
        packages.default = rustApp;

        packages.python = pkgs.stdenv.mkDerivation {
          pname = "whisper-dictation-python";
          version = "0.1.0";
          
          src = ./.;
          
          buildInputs = [ pythonEnv pkgs.wtype ];
          
          installPhase = ''
            mkdir -p $out/bin
            cp main.py $out/bin/whisper-dictation
            chmod +x $out/bin/whisper-dictation
            
            # Create wrapper to ensure PATH includes wtype
            mv $out/bin/whisper-dictation $out/bin/.whisper-dictation-unwrapped
            cat > $out/bin/whisper-dictation << EOF
            #!/bin/sh
            export PATH="${pkgs.lib.optionalString (system == "x86_64-linux" || system == "aarch64-linux") "${pkgs.wtype}/bin:"}$PATH"
            exec $out/bin/.whisper-dictation-unwrapped "\$@"
            EOF
            chmod +x $out/bin/whisper-dictation
          '';
        };
        
        devShells.default = pkgs.mkShell {
          buildInputs = [ pythonEnv ] ++ commonArgs.nativeBuildInputs ++ commonArgs.buildInputs;
        };
      }
    );
}

