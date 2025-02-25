{self, inputs, ...}:
{
  perSystem = { lib, system, ... }:
    let
      overlays = import ../overlays { inherit inputs system; };
      pkgs = import self.inputs.nixpkgs {
        inherit system overlays;
        config.allowUnfree = true;
      };
    in
    {
      _module.args.pkgs = pkgs;

      packages = lib.filterAttrs (_: value: value ? type && value.type == "derivation") (
        builtins.mapAttrs (name: _: pkgs.${name}) (lib.composeManyExtensions overlays null null)
      );
    };
}
