# Tools Inventory

**Author: Nima Shafie**

Complete inventory of default tool manifests in `airgap-devkit-tools`.
All tools target air-gapped environments — no internet access required at install time.

> **Prebuilt available?** — If yes, no compiler or build tools required at install time.

---

## Toolchains

| Tool | Version | Platform | Prebuilt? | Location |
|------|---------|----------|-----------|----------|
| **Clang / LLVM (source build)** | 22.1.3 | Windows + Linux | Yes | `toolchains/clang/source-build/` |
| **LLVM Style Formatter** | 22.1.3 | Windows + Linux | Yes | `toolchains/clang/style-formatter/` |
| **GCC + MinGW-w64** | 15.2.0 + 13.0.0 UCRT | Windows | Yes | `toolchains/gcc/windows/` |
| **GCC Native (RHEL 8)** | 15 | RHEL 8 | Yes | `toolchains/gcc/linux/native/` |
| **GCC Cross (x86_64-bionic)** | 15 | Linux | Yes | `toolchains/gcc/linux/cross/` |

---

## Build Tools

| Tool | Version | Platform | Prebuilt? | Location |
|------|---------|----------|-----------|----------|
| **CMake** | 4.3.1 | Windows + Linux | Yes | `build-tools/cmake/` |
| **lcov** | 2.4 | Linux / RHEL 8 | Yes (vendored tarball) | `build-tools/lcov/` |

---

## Languages

| Tool | Version | Platform | Prebuilt? | Location |
|------|---------|----------|-----------|----------|
| **Python** | 3.14.4 | Windows + Linux | Yes | `languages/python/` |
| **.NET SDK** | 10.0.201 | Windows + Linux | Yes | `languages/dotnet/` |

---

## Frameworks

| Tool | Version | Platform | Prebuilt? | Location |
|------|---------|----------|-----------|----------|
| **gRPC** | 1.80.0 | Windows | Yes (.zip, 4 parts) | `frameworks/grpc/` |

---

## Developer Tools

| Tool | Version | Platform | Prebuilt? | Location |
|------|---------|----------|-----------|----------|
| **7-Zip** | 26.00 | Windows + Linux | Yes | `dev-tools/7zip/` |
| **Servy** | 7.9 | Windows | Yes (single file ~80 MB) | `dev-tools/servy/` |
| **Conan** | 2.27.1 | Windows + Linux | Yes (self-contained) | `dev-tools/conan/` |
| **VS Code Extensions** | Various | Windows + Linux | Yes (.vsix) | `dev-tools/vscode-extensions/` |
| **SQLite CLI** | 3.53.0 (Win/Linux) / 3.26.0 RPM (RHEL 8) | Windows + Linux | Yes | `dev-tools/sqlite/` |
| **MATLAB Verification** | N/A | Windows + Linux | — (checks existing install) | `dev-tools/matlab/` |
| **git-bundle Transfer Tool** | N/A | Windows + Linux | — (Python scripts) | `dev-tools/git-bundle/` |

---

## Platform Support Matrix

| Tool | Windows 11 | RHEL 8 | Notes |
|------|-----------|--------|-------|
| Clang / LLVM | Yes | Yes | Prebuilt for both |
| LLVM Style Formatter | Yes | Yes | Git pre-commit hook |
| GCC + MinGW-w64 | Yes | — | Windows native toolchain |
| GCC Native | — | Yes | RHEL 8 RPMs |
| GCC Cross | — | Yes | Linux hosts only |
| CMake 4.3.1 | Yes | Yes | Prebuilt for both |
| lcov 2.4 | — | Yes | Linux / RHEL 8 only |
| Python 3.14.4 | Yes | Yes | Different packages per platform |
| .NET SDK 10.0.201 | Yes | Yes | Portable, no installer |
| gRPC 1.80.0 | Yes | — | Windows MSVC build only |
| 7-Zip 26.00 | Yes | Yes | Admin + user install |
| Servy 7.9 | Yes | — | Windows only, graceful no-op on Linux |
| Conan 2.27.1 | Yes | Yes | Self-contained, no Python required |
| VS Code Extensions | Yes | Yes | Per-platform .vsix files |
| SQLite CLI | Yes (3.53.0) | Yes (3.26.0 RPM) | RHEL 8 uses system RPM |
| MATLAB Verification | Yes | Yes | Checks existing install only |
| git-bundle Tool | Yes | Yes | Pure Python, no deps |
