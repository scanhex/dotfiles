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
          nativeBuildInputs = [ pkgs.iconv ]; # any extra native libs you need
        };

        deps = craneLib.buildDepsOnly commonArgs;

        rustApp = craneLib.buildPackage (commonArgs // {
          inherit deps;
          pname = "whisper";
          version = "0.1.0";
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
          buildInputs = [ pythonEnv ];
        };
      }
    );
}

