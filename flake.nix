# First draft of this flake include a large amount of cruft to be compatible
# with both pre and post Nix 2.6 APIs.
#
# The expected state is to support bundlers of the form:
# bundlers.<system>.<name> = drv: some-drv;

{
  description = "Example bundlers";

  inputs.nix-utils.url = "github:juliosueiras-nix/nix-utils";
  inputs.nix-bundle.url = "github:matthewbauer/nix-bundle";
  inputs.nix-appimage.url = "github:ralismark/nix-appimage";

  outputs = { self, nixpkgs, nix-appimage, nix-bundle, nix-utils }: let
      # System types to support.
      supportedSystems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; });

      # Backwards compatibility helper for pre Nix2.6 bundler API
      program = p: with builtins; with (protect p); "${outPath}/bin/${
        if p?meta && p.meta?mainProgram then
          meta.mainProgram
          else (parseDrvName (unsafeDiscardStringContext p.name)).name
      }";

      protect = drv: if drv?outPath then drv else throw "provided installable is not a derivation and not coercible to an outPath";
  in {
    defaultBundler = builtins.listToAttrs (map (system: {
        name = system;
        value = drv: self.bundlers.${system}.toArx (protect drv);
      }) supportedSystems)
      # Backwards compatibility helper for pre Nix2.6 bundler API
      // {__functor = s: nix-bundle.bundlers.nix-bundle;};

    bundlers = let n =
      (forAllSystems (system: {
        # Backwards compatibility helper for pre Nix2.6 bundler API
        toArx = drv: (nix-bundle.bundlers.nix-bundle ({
          program = if drv?program then drv.program else (program drv);
          inherit system;
        })) // (if drv?program then {} else {name=
          (builtins.parseDrvName drv.name).name;});

      toRPM = drv: nix-utils.bundlers.rpm {inherit system; program=program drv;};

      toDEB = drv: nix-utils.bundlers.deb {inherit system; program=program drv;};

      toDockerImage = {...}@drv:
        (nixpkgs.legacyPackages.${system}.dockerTools.buildLayeredImage {
          name = drv.name or drv.pname or "image";
          tag = "latest";
          contents = if drv?outPath then drv else throw "provided installable is not a derivation and not coercible to an outPath";
      });

      toBuildDerivation = drv:
        (import ./report/default.nix {
          drv = protect drv;
          pkgs = nixpkgsFor.${system};}).buildtimeDerivations;

      toReport = drv:
        (import ./report/default.nix {
          drv = protect drv;
          pkgs = nixpkgsFor.${system};}).runtimeReport;

      toAppImage = nix-appimage.bundlers.${system}.default;

      identity = drv: drv;
    }
    ));
    in with builtins;
    # Backwards compatibility helper for pre Nix2.6 bundler API
    listToAttrs (map
      (name: {
        inherit name;
        value = builtins.trace "The bundler API has been updated to require the form `bundlers.<system>.<name>`. The previous API will be deprecated in Nix 2.7. See `https://github.com/NixOS/nix/pull/5456/`"
        ({system,program}@drv: self.bundlers.${system}.${name}
          (drv // {
            name = baseNameOf drv.program;
            outPath = dirOf (dirOf drv.program);
          }));
        })
      (attrNames n.x86_64-linux))
      //
      n;
  };
}
