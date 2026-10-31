# gRPC Starter / Test Project

A complete, minimal gRPC project you can **copy anywhere and make your own**. It
defines its own service ([`proto/echo.proto`](proto/echo.proto)), builds a
[server](src/echo_server.cc) and a [client](src/echo_client.cc), and links against
the **prebuilt gRPC package** — no building of gRPC required.

---

## "What files / libraries do I actually need?"

**Short answer: the extracted prebuilt package folder — nothing else.**

You do **not** hand-pick individual `.lib` files. gRPC is ~200 static libraries with a
web of dependencies; CMake wires them all up for you when you link the `gRPC::grpc++`
target. So all you need is:

| You need | Where it comes from | You reference it via |
|---|---|---|
| Headers (`grpcpp/…`, `google/protobuf/…`, `absl/…`) | package `include/` | `find_package(gRPC CONFIG)` |
| Static libs (grpc, protobuf, absl, boringssl, …) | package `lib/` | `target_link_libraries(... gRPC::grpc++)` |
| CMake config that links them all | package `lib/cmake/…` | `find_package(...)` (automatic) |
| Code generators | package `bin/protoc.exe`, `bin/grpc_cpp_plugin.exe` | CMake custom command / by hand |

The only two things your build needs to know are:

1. **`CMAKE_PREFIX_PATH`** = the package folder (so `find_package` finds it), and
2. **`CMAKE_TOOLCHAIN_FILE`** = `grpc-toolchain.cmake` in that folder (so your app links
   the same static `/MT` runtime the libraries use).

Running the package's `activate.ps1` sets `GRPC_ROOT` to the package folder; the presets
below read `$env{GRPC_ROOT}` so you never hard-code a path.

---

## Compiler compatibility (read this first)

On Windows the prebuilt static libraries are **ABI-locked** to the MSVC toolset they were
built with. Pick the package that matches your compiler (each ships in Release and Debug):

| Your IDE / compiler | Toolset | Use this package |
|---|---|---|
| Visual Studio 2019 (16.x) | v142 | `grpc-1.83.0-msvc142-<config>` |
| Visual Studio 2022 (17.x) | v143 | `grpc-1.83.0-msvc143-<config>` |
| Visual Studio 2026 | v145 | `grpc-1.83.0-msvc145-<config>` |
| VS 2026 building in v143 mode | v143 | `grpc-1.83.0-msvc143-<config>` |
| RHEL 8, 9 or 10 (gcc-toolset, x86_64) | — | `grpc-1.83.0-linux` |

> **Not supported:** Visual Studio 2017 (v141), MinGW/gcc on Windows, Clang. The static
> libs will not link against those ABIs. If you need one of them, a maintainer must produce
> a matching package with `scripts/build-grpc.ps1` (Windows) or `scripts/build-grpc.sh` (Linux).

---

## One-time setup

1. Install the matching package with the devkit (no admin needed). It extracts to a
   per-package prefix such as `%LOCALAPPDATA%\airgap-cpp-devkit\grpc-1.83.0-msvc143-release`
   on Windows, or `~/.local/share/airgap-cpp-devkit/grpc-1.83.0-linux` on Linux:
   ```bash
   bash tools/frameworks/grpc/setup.sh --toolset v143 --config release   # Windows
   bash tools/frameworks/grpc/setup.sh --platform linux                  # RHEL/Rocky 8/9/10
   ```
2. Activate it in your terminal — this sets `GRPC_ROOT` and puts `protoc` on PATH:
   ```powershell
   # Windows
   . "$env:LOCALAPPDATA\airgap-cpp-devkit\grpc-1.83.0-msvc143-release\activate.ps1"
   ```
   ```bash
   # Linux
   source ~/.local/share/airgap-cpp-devkit/grpc-1.83.0-linux/activate.sh
   ```
   Keep this variable available to whichever IDE you launch (launch the IDE from the same
   terminal, or set `GRPC_ROOT` as a user environment variable once).

---

## Build & run — pick your IDE

### Command line (any)
```powershell
cmake --preset vs2026-v143
cmake --build --preset vs2026-v143-release
.\build\vs2026-v143\Release\echo_server.exe   # in one terminal
.\build\vs2026-v143\Release\echo_client.exe   # in another
```

### VS Code
1. Install the **CMake Tools** and **C/C++** extensions.
2. `File > Open Folder…` on this `example-project` folder.
3. CMake Tools auto-detects [`CMakePresets.json`](CMakePresets.json). In the status bar
   pick the **Configure Preset** (`VS 2026 - v143 toolset`), then click **Build**.
   (`.vscode/settings.json` here already turns presets on.)
4. Use the Run/Debug targets `echo_server` / `echo_client`, or run the built exes from a
   terminal as above.

### Visual Studio 2022 / 2026
Two equivalent ways:

- **Open Folder (uses the presets):** `File > Open > Folder…` on this folder. VS reads
  `CMakePresets.json` natively — pick `vs2022-v143` (VS 2022) or `vs2026-v143` / `vs2026-v145`
  (VS 2026) from the configuration dropdown, then Build. Set `echo_server`/`echo_client` as
  the startup item to run.
- **Generate a .sln (classic):**
  ```powershell
  cmake -S . -B build -G "Visual Studio 17 2022" -A x64 `
        -DCMAKE_TOOLCHAIN_FILE="$env:GRPC_ROOT\grpc-toolchain.cmake" `
        -DCMAKE_PREFIX_PATH="$env:GRPC_ROOT"
  ```
  (Use `-G "Visual Studio 18 2026"` on VS 2026.) Then open `build\grpc_example_project.sln`.

---

## Generating C++ from your `.proto` by hand
CMake does this automatically, but if you want to run it yourself:
```powershell
protoc -I proto --cpp_out=gen --grpc_out=gen `
  --plugin=protoc-gen-grpc="$env:GRPC_ROOT\bin\grpc_cpp_plugin.exe" proto\echo.proto
```

## Make it yours
1. Edit [`proto/echo.proto`](proto/echo.proto) — rename the package/service/messages.
2. Update [`src/echo_server.cc`](src/echo_server.cc) / [`src/echo_client.cc`](src/echo_client.cc).
3. Rebuild. That's the whole loop.

## Troubleshooting
- **`LNK2038 ... RuntimeLibrary mismatch` / `__imp_*` unresolved** → your app compiled `/MD`
  but the package is `/MT`. Make sure you passed `CMAKE_TOOLCHAIN_FILE=…\grpc-toolchain.cmake`
  (the presets do this).
- **`Could not find a package configuration file provided by "gRPC"`** → `GRPC_ROOT` isn't
  set / `CMAKE_PREFIX_PATH` doesn't point at the extracted package. Re-run `activate.ps1`.
- **`protoc` not found** → run `activate.ps1` (adds the package `bin\` to PATH).
