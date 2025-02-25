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
            curl
            openssl
            jansson
            libuiohook
          ] ++ (if pkgs.stdenv.isDarwin then [ 
            pkgs.darwin.apple_sdk.frameworks.Carbon 
            pkgs.darwin.apple_sdk.frameworks.AppKit
          ] else if pkgs.stdenv.isLinux then [
            xorg.libX11
            xorg.libXtst
            xorg.libXt
            xorg.libXi
            xorg.libxcb
            xorg.xcbutilwm
            xorg.xcbutilkeysyms
            xorg.xcbutil
            xorg.libXinerama
            libxkbcommon
            xdotool
          ] else if pkgs.stdenv.isWindows then [
            # Windows-specific dependencies would go here
          ] else []);
          
          buildPhase = ''
            echo "Building with libxkbcommon from: $(find ${libxkbcommon}/lib -name "*.so" | sort)"
            echo "Building with libX11 from: $(find ${xorg.libX11}/lib -name "*.so" | sort)"
            
            XCBINC="${xorg.libxcb}/include"
            X11INC="${xorg.libX11}/include"
            X11LIB="${xorg.libX11}/lib"
            XKBLIB="${libxkbcommon}/lib"
            
            $CC -v -o whisper-dictation main.c recording.c \
              -lportaudio -lcurl -lm -pthread -ljansson -luiohook \
              -I$XCBINC -I$X11INC -L$X11LIB -L$XKBLIB \
              ${if pkgs.stdenv.isLinux then "-lX11 -lXtst -lXt -lxcb -lX11-xcb -lXinerama -lxkbcommon -lxkbcommon-x11 -lxcb-util -lxcb-keysyms -lxcb-icccm -lxcb-ewmh -lxdo" else 
                if pkgs.stdenv.isDarwin then "-framework Carbon -framework AppKit" else 
                if pkgs.stdenv.isWindows then "-luser32" else ""} \
              -O3
          '';
          
          installPhase = ''
            mkdir -p $out/bin
            cp whisper-dictation $out/bin/
          '';
        };
        
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            portaudio
            curl
            openssl
            jansson
            libuiohook
            pkg-config
          ] ++ (if pkgs.stdenv.isDarwin then [ 
            pkgs.darwin.apple_sdk.frameworks.Carbon 
            pkgs.darwin.apple_sdk.frameworks.AppKit
          ] else if pkgs.stdenv.isLinux then [
            xorg.libX11
            xorg.libXtst
            xorg.libXt
            xorg.libXi
            xorg.libxcb
            xorg.xcbutilwm
            xorg.xcbutilkeysyms
            xorg.xcbutil
            xorg.libXinerama
            libxkbcommon
            xdotool
          ] else if pkgs.stdenv.isWindows then [
            # Windows-specific dependencies would go here
          ] else []);
        };
      }
    );
}
