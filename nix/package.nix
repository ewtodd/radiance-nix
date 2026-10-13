# Radiance, built the way its Dockerfile builds it: the host code with the stdenv C++ compiler, the
# device kernels with the TheRock SDK clang (wrapped for NixOS headers by therock-sdk-nix), ffmpeg
# for image/video/audio parts. Kernels are compiled for the R9700 (gfx1201); libr4d is RDNA4-only.
{
  lib,
  stdenv,
  cmake,
  ninja,
  patchelf,
  pkg-config,
  ffmpeg-headless,
  curl,
  jq,
  makeWrapper,
  src,
  srcRev,
  rocmSdk,
  rocmSdkCc,
  gpuTargets,
}:

stdenv.mkDerivation {
  pname = "radiance";
  version = "1.4.0-${srcRev}";
  inherit src;

  nativeBuildInputs = [
    cmake
    ninja
    patchelf
    pkg-config
    makeWrapper
  ];

  buildInputs = [ ffmpeg-headless ];

  cmakeFlags = [
    (lib.cmakeFeature "CMAKE_BUILD_TYPE" "Release")
    (lib.cmakeFeature "RAD_WITH_HIP" "ON")
    (lib.cmakeFeature "RAD_WITH_FFMPEG" "ON")
    (lib.cmakeFeature "RAD_GPU_TARGETS" (lib.concatStringsSep ";" gpuTargets))
    # find_program()/find_library() look only in /opt/rocm; the ROCm root (headers) is derived from
    # hipcc's location.
    (lib.cmakeFeature "RAD_HIPCC" "${rocmSdk}/bin/hipcc")
    (lib.cmakeFeature "RAD_HIP_RUNTIME" "${rocmSdk}/lib/libamdhip64.so")
    (lib.cmakeFeature "RAD_HSA_RUNTIME" "${rocmSdk}/lib/libhsa-runtime64.so")
    (lib.cmakeFeature "CMAKE_HIP_COMPILER" "${rocmSdkCc}/bin/clang++")
    (lib.cmakeFeature "CMAKE_HIP_COMPILER_ROCM_ROOT" "${rocmSdk}")
    (lib.cmakeFeature "CMAKE_HIP_FLAGS" "--rocm-path=${rocmSdk}")
    (lib.cmakeBool "RAD_BUILD_TESTS" false)
  ];

  env = {
    ROCM_PATH = "${rocmSdk}";
    HIP_PATH = "${rocmSdk}";
    HIP_DEVICE_LIB_PATH = "${rocmSdk}/lib/llvm/amdgcn/bitcode";
  };

  postInstall = ''
    mkdir -p $out/share/radiance/recipes
    cp $src/data/recipes/*.recipe $out/share/radiance/recipes/
  '';

  # Device code is linked by the SDK clang, not nix's ld wrapper: add the SDK (HIP runtime, comgr)
  # and ffmpeg to the runpath of every ELF we install (the server, the tools and the plugins).
  postFixup = ''
    find $out -type f \( -perm -0100 -o -name '*.so' -o -name '*.so.*' \) | while read -r f; do
      if head -c4 "$f" | grep -q ELF; then
        patchelf --add-rpath ${
          lib.makeLibraryPath [
            rocmSdk
            ffmpeg-headless
          ]
        }:$out/lib "$f"
      fi
    done
    # hfget.sh (--model <hf repo>) shells out to curl and jq.
    for f in $out/libexec/radiance/*.sh; do
      [ -e "$f" ] && wrapProgram "$f" --prefix PATH : ${
        lib.makeBinPath [
          curl
          jq
        ]
      }
    done
  '';

  passthru = {
    inherit rocmSdk rocmSdkCc gpuTargets;
  };

  meta = {
    description = "Radiance LLM inference server for AMD RDNA4 (ROCm ${rocmSdk.version or "10.1"})";
    homepage = "https://codeberg.org/StillDeadcode/radiance";
    platforms = [ "x86_64-linux" ];
    license = lib.licenses.asl20;
    mainProgram = "radiance";
  };
}
