{pkgs}:

pkgs.stdenv.mkDerivation {
		name = "nix-user-chroot-patch";

		buildInputs = [ pkgs.gcc ];

		unpackPhase = "true";

		patch_source = "int grantpt(int fd) { return 0; }";


# Because the uid mapping doesn't work properly in a sandboxed environment (user namespace), 
# And old glibc's grantpt function which python's openpty() uses, doesn't work without correct uids, 
# We have to patch it. The source for the issue: https://github.com/apptainer/apptainer/issues/297
# P.S. The linux kernel doesn't allow proper uid mappings in unpriviliged user namespaces.
# We need to LD_PRELOAD this library whenever we want to do the pty stuff, e.g. alias python3 to do it.

		buildPhase = ''
			mkdir -p $out/lib
			echo $patch_source | gcc -shared -fPIC -o $out/lib/nix-user-chroot-patch.so -x c -
			'';

		installPhase = "true";

	}
