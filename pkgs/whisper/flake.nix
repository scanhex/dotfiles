{
  description = "Whisper Dictation - A lightweight dictation app using OpenAI API with global hotkey support";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          pyaudio
          pynput
          requests
          numpy
          pyperclip
          pyxdg
          xlib
          evdev
        ]);
        
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "whisper-dictation";
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
            export PATH="${pkgs.wtype}/bin:\$PATH"
            exec $out/bin/.whisper-dictation-unwrapped "\$@"
            EOF
            chmod +x $out/bin/whisper-dictation
          '';
        };
        
        devShells.default = pkgs.mkShell {
          buildInputs = [ pythonEnv pkgs.wtype ];
        };
      }
    );
}
