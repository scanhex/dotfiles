{
  description = "Whisper Dictation - A lightweight dictation app using openai-whisper-cpp";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "whisper-dictation";
          version = "0.1.0";
          
          src = ./.;
          
          nativeBuildInputs = with pkgs; [
            pkg-config
          ];
          
          buildInputs = with pkgs; [
            portaudio
            openai-whisper-cpp
          ];
          
          buildPhase = ''
            cc -o whisper-dictation main.c recording.c -lportaudio -lwhisper -lm -pthread -O3
          '';
          
          installPhase = ''
            mkdir -p $out/bin
            cp whisper-dictation $out/bin/
          '';
        };
        
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            portaudio
            openai-whisper-cpp
            pkg-config
          ];
        };
      }
    );
}