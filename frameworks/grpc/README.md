# gRPC (prebuilt) — airgap-cpp-devkit

**Version:** 1.81.1 · **Platform:** Windows x64 · **Prebuilt:** yes (per MSVC toolset)

A ready-to-consume, **relocatable** gRPC install prefix for C++ — no compilation,
no admin rights, no internet. Extract the package the devkit installs and build
your own gRPC app in minutes.

The prebuilt distribution is a maintainer build (release configuration),
vendored into this repo as split parts under
`prebuilt/frameworks/grpc/windows/1.81.1/`. To refresh it from an updated
maintainer build, use [`scripts/internal/import-grpc-prebuilt.sh`](../../../scripts/internal/import-grpc-prebuilt.sh).

## Pick the package that matches your Visual Studio

The static libraries are **ABI-locked** to the MSVC toolset they were built with,
so one package is shipped per Visual Studio version. Install the matching one:

| Toolset | Visual Studio | `--toolset` |
|---------|---------------|-------------|
| MSVC v142 | Visual Studio 2019 | `v142` |
| MSVC v143 | Visual Studio 2022 (default) | `v143` |
| MSVC v145 | Visual Studio 2026 | `v145` |

Not sure which you have? Run the environment check — it detects your installed
MSVC toolset(s) and CMake, then prints the exact package and configure command:

```powershell
powershell -File tools/frameworks/grpc/Check-Environment.ps1
```

## Install

**devkit-ui:** open the gRPC tool, choose your Visual Studio version from the
selector, and click Install.

**CLI:**
```bash
bash tools/frameworks/grpc/setup.sh --toolset v143     # VS 2022 (default)
bash tools/frameworks/grpc/setup.sh --toolset v145     # VS 2026
bash tools/frameworks/grpc/setup.sh --toolset v142     # VS 2019
```

Each toolset installs into its own sibling directory
(`<prefix>/grpc-1.81.1-msvc<NNN>`), so multiple toolsets can coexist. `protoc`
and `grpc_cpp_plugin` are added to the devkit `env.sh` PATH.

## What you get

Each package extracts to a self-contained CMake install prefix:

```
grpc-1.81.1-msvc143/
  bin/                protoc.exe, grpc_cpp_plugin.exe, ...
  include/            grpcpp/, grpc/, google/protobuf/, absl/, ...
  lib/                static .libs + lib/cmake/{grpc,protobuf,absl}, ...
  share/              root certs, etc.
  activate.ps1        # per-session env setup (GRPC_ROOT + PATH)
  grpc-toolchain.cmake  # forces /MT so your app matches the prebuilt libs
```

## Build your own app against it

From a Developer PowerShell:

```powershell
# 1. Activate the installed package for this session
. "<install-prefix>/grpc-1.81.1-msvc143/activate.ps1"

# 2. Configure your project with the shipped toolchain (so your app links the
#    same static /MT runtime as the prebuilt libs)
cmake -G "Visual Studio 17 2022" -A x64 `
      -DCMAKE_TOOLCHAIN_FILE="$env:GRPC_ROOT\grpc-toolchain.cmake" `
      -DCMAKE_PREFIX_PATH="$env:GRPC_ROOT" -B build
cmake --build build --config Release
```

In your `CMakeLists.txt`:

```cmake
find_package(Protobuf CONFIG REQUIRED)
find_package(gRPC CONFIG REQUIRED)
target_link_libraries(your_app PRIVATE gRPC::grpc++ protobuf::libprotobuf)
```

> **Runtime note:** the package is `/MT` (static CRT); your app must also compile
> `/MT` — the shipped `grpc-toolchain.cmake` handles that. Mixing `/MD` and `/MT`
> produces `LNK2038 RuntimeLibrary mismatch` errors.

## Copy-and-go starter

A complete starter project is vendored alongside this tool at
[`example-project/`](example-project/) — a minimal echo service with its own
`.proto`, cross-IDE `CMakePresets.json`, and a full walkthrough for VS Code /
Visual Studio 2022 / Visual Studio 2026. Copy it anywhere, activate the installed
package, and build:

```powershell
. "<install-prefix>/grpc-1.81.1-msvc143/activate.ps1"
cd tools/frameworks/grpc/example-project
cmake --preset vs2022-v143        # VS 2022; also vs2026-v143 / vs2026-v145
cmake --build --preset vs2022-v143-release
```

(Or just open the folder in VS Code / Visual Studio and pick a preset.)

Point new developers there.
