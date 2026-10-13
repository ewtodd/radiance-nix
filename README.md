# radiance-nix

Nix packaging for **[Radiance](https://codeberg.org/StillDeadcode/radiance)**, the LLM inference server for
AMD GPUs written by **Deadcode ([StillDeadcode](https://codeberg.org/StillDeadcode))**.

## Credit

Radiance is entirely StillDeadcode's work, together with the contributors named in its
`NOTICE` file. It includes:

- the engine, in C++ and HIP;
- the RDNA4 kernel library (`libr4d`);
- the quantisers and the `.rad` model format;
- the plugin system;
- the speculative decoders;
- an HTTP API that speaks OpenAI's, Anthropic's and llama-server's dialects.

The prebuilt `.rad` models are on [StillDeadcode's Hugging Face page](https://huggingface.co/StillDeadcode).

This repository adds only a nix derivation. If Radiance is useful to you,
[go give StillDeadcode money and support its development on Patreon](https://patreon.com/StillDeadCode). Send bugs in the engine upstream;
send problems with this packaging here.

Radiance is licensed under the Apache License 2.0.

## What this builds

Upstream ships Radiance as a container. This flake builds it from source, with no container,
against [TheRock](https://github.com/ROCm/TheRock) ROCm 10.1 SDK (via
[therock-sdk-nix](https://github.com/ewtodd/therock-sdk-nix)). It targets the R9700 (`gfx1201`) by default.

- **Host code:** built with the stdenv C++ compiler.
- **Device kernels:** built with the SDK's clang, wrapped for NixOS headers.
- **ffmpeg:** included for image, video and audio inputs.
- **Upstream build flags:** Radiance's CMake looks for ROCm only under `/opt/rocm`, so the build passes
  `RAD_HIPCC`, `RAD_HIP_RUNTIME` and `RAD_HSA_RUNTIME` explicitly.
- **Runtime libraries:** every installed binary and plugin gets the SDK and ffmpeg added to its runpath.
- **`hfget.sh`:** the script behind `--model <hf repo>` is wrapped with `curl` and `jq`.

Installed:

- `bin/radiance`: the server.
- `bin/rad-convert`, `rad-info`, `rad-kbench`, `rad-schemas`, `rad-tokcheck`, `rad-tune`: upstream's tools.
- `share/radiance/recipes/`: upstream's quantisation recipes.
- `libexec/radiance/hfget.sh`

## Use

```sh
nix build                    # result/bin/radiance
nix run . -- --model /models/qwen3.8-27b-fp8.rad --tp 2 --port 8100
nix develop                  # radiance, the SDK and ROCM_PATH on the shell
```

The AMD SDK is unfree. The standalone packages allow it; a caller passing its own `pkgs` must allow it too.

### Binary cache

The builds this flake's lock produces, Radiance and the TheRock SDK included, are served from
`https://cache.ethanwtodd.com`. With the cache configured, `nix build` downloads them instead of compiling
the kernels:

```nix
nix.settings = {
  extra-substituters = [ "https://cache.ethanwtodd.com" ];
  extra-trusted-public-keys = [ "e-desktop:35K0AY3HcDOSHVQ/lklmbvmrXjIspM/LYf7yek5lyVA=" ];
};
```

For a one-off build as a trusted user:

```sh
nix build --extra-substituters https://cache.ethanwtodd.com \
  --extra-trusted-public-keys e-desktop:35K0AY3HcDOSHVQ/lklmbvmrXjIspM/LYf7yek5lyVA=
```

A caller whose nixpkgs differs from this lock (through `inputs.nixpkgs.follows`) gets different store paths
and builds locally.

As a flake input, with your own nixpkgs and, optionally, a TheRock pin shared with another engine:

```nix
inputs.radiance-nix = {
  url = "git+ssh://git@github.com/ewtodd/radiance-nix";
  inputs.nixpkgs.follows = "nixpkgs";
  # inputs.therock-sdk.follows = "unholy/therock-sdk";
};

# then:
radiance = inputs.radiance-nix.lib.x86_64-linux.mkRadiance {
  inherit pkgs;
  # gpuTargets = [ "gfx1200" "gfx1201" ];   # libr4d is RDNA4-only
};
```

The NixOS service that runs it lives in the host configuration, not here.

## Updating Radiance

1. Point the `radiance-src` input in `flake.nix` at the new upstream commit's archive.
2. Set `srcRev` to the new short rev.
3. If upstream released, bump `version` in `nix/package.nix`.
4. Run `nix flake lock` and `nix build`.

If the build breaks, check upstream's `Dockerfile` and `CMakeLists.txt` for new options or dependencies.
