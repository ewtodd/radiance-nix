{
  description = "radiance-nix: the Radiance C++/HIP LLM inference server (codeberg.org/StillDeadcode/radiance) for the R9700 (gfx1201), built against TheRock ROCm SDK";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    therock-sdk = {
      url = "github:ewtodd/therock-sdk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    radiance-src = {
      url = "https://codeberg.org/StillDeadcode/radiance/archive/19d4e8fe0e18071b9b6300f15fc4ccf38dc4fa3d.tar.gz";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      therock-sdk,
      radiance-src,
    }:
    let
      system = "x86_64-linux";
      # Callers (the NixOS host) pass their own pkgs through `lib.mkRadiance` so there is one nixpkgs;
      # the standalone instance below allows the unfree AMD SDK.
      mkRadiance =
        {
          pkgs,
          gpuTargets ? [ "gfx1201" ],
          # Patches applied to the upstream source (-p1), e.g. [ patches.checkpointSpill ].
          patches ? [ ],
        }:
        let
          rocmSdk = therock-sdk.lib.${system}.mkRocmSdk {
            inherit pkgs;
            family = "gfx120X-all";
          };
          rocmSdkCc = therock-sdk.lib.${system}.mkRocmSdkCc { inherit pkgs rocmSdk; };
        in
        pkgs.callPackage ./nix/package.nix {
          inherit rocmSdk rocmSdkCc gpuTargets patches;
          src = radiance-src;
          srcRev = "19d4e8fe0e18071b9b6300f15fc4ccf38dc4fa3d";
          version = "1.17.0";
        };

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      # Out-of-tree patches, to pass to mkRadiance.
      patches = {
        # A disk tier for the checkpoint slots (--checkpoint-dir DIR --disk-checkpoints N); off
        # unless both flags are given. See patches/checkpoint-spill.patch.
        checkpointSpill = ./patches/checkpoint-spill.patch;
      };
      radiance = mkRadiance { inherit pkgs; };
      radiance-spill = mkRadiance {
        inherit pkgs;
        patches = [ patches.checkpointSpill ];
      };
    in
    {
      lib.${system} = { inherit mkRadiance patches; };

      packages.${system} = {
        default = radiance;
        inherit radiance radiance-spill;
      };

      devShells.${system}.default = pkgs.mkShell {
        inputsFrom = [ radiance ];
        shellHook = ''
          export ROCM_PATH=${radiance.passthru.rocmSdk}
          export LD_LIBRARY_PATH=${radiance.passthru.rocmSdk}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
          export PATH=${radiance}/bin:${radiance.passthru.rocmSdk}/bin:$PATH
        '';
      };

      formatter.${system} = pkgs.nixfmt;
    };
}
