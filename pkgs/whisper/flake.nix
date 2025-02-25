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
        ] ++ (if pkgs.stdenv.isLinux then [
          ps.python-xlib
        ] else []));
        
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "whisper-dictation";
          version = "0.1.0";
          
          src = ./.;
          
          buildInputs = [ pythonEnv ] ++ (if pkgs.stdenv.isLinux then [
            pkgs.xdotool
          ] else []);
          
          installPhase = ''
            mkdir -p $out/bin
            cp whisper_dictation.py $out/bin/whisper-dictation
            chmod +x $out/bin/whisper-dictation
          '';
        };
        
        devShells.default = pkgs.mkShell {
          buildInputs = [ pythonEnv ] ++ (if pkgs.stdenv.isLinux then [
            pkgs.xdotool
          ] else []);
        };
      }
    );
}