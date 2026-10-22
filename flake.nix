{
  description = "radiance-nix: the Radiance C++/HIP LLM inference server (codeberg.org/StillDeadcode/radiance) for the R9700 (gfx1201), built against TheRock ROCm SDK";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    therock-sdk = {
      url = "github:ewtodd/therock-sdk-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    radiance-src = {
      url = "https://codeberg.org/StillDeadcode/radiance/archive/123c4396842625ae79a14e6e598890c0044a8b91.tar.gz";
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
        }:
        let
          rocmSdk = therock-sdk.lib.${system}.mkRocmSdk {
            inherit pkgs;
            family = "gfx120X-all";
          };
          rocmSdkCc = therock-sdk.lib.${system}.mkRocmSdkCc { inherit pkgs rocmSdk; };
        in
        pkgs.callPackage ./nix/package.nix {
          inherit rocmSdk rocmSdkCc gpuTargets;
          src = radiance-src;
          srcRev = "123c4396842625ae79a14e6e598890c0044a8b91";
        };

      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };
      radiance = mkRadiance { inherit pkgs; };
    in
    {
      lib.${system} = { inherit mkRadiance; };

      packages.${system} = {
        default = radiance;
        inherit radiance;
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
