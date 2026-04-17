# airgap-devkit-tools

**Author: Nima Shafie**

Default tool manifests for the **airgap-devkit** ecosystem.
Every tool in this repo targets air-gapped environments — no internet access required at install time.

---

## What this repo is

`airgap-devkit-tools` holds the **official default set** of `devkit.json` manifests and
install scripts for all tools in the airgap-devkit ecosystem.

The airgap-devkit engine discovers tools by scanning for `devkit.json` files in the
directory tree. This repo is the authoritative source for the default tool set.

---

## How to use

Include this repo as a submodule at `tools/default/` inside your team image repo:

```bash
git submodule add https://github.com/NimaShafie/airgap-devkit-tools tools/default
```

The airgap-devkit engine will automatically discover all `devkit.json` files under
`tools/default/` and register them as installable tools.

---

## Adding your own tools

To add team-specific tools, fork or use **airgap-devkit-teams** instead of modifying
this repo. Team tools should live in a separate submodule at `tools/team/` so that
default tool updates can be pulled in cleanly without merge conflicts.

Do not send pull requests to this repo for tools that are specific to your organization.

---

## devkit.json schema reference

Each tool directory contains exactly one `devkit.json` with the following fields:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique slug used as the internal tool identifier (e.g. `"cmake"`). Must be stable — changing it breaks receipts. |
| `name` | string | Yes | Human-readable display name shown in the UI and CLI (e.g. `"CMake"`). |
| `version` | string | Yes | Tool version string (e.g. `"4.3.1"`). Use `"N/A"` for version-less tools. |
| `category` | string | Yes | One of: `"Toolchains"`, `"Build Tools"`, `"Languages"`, `"Frameworks"`, `"Developer Tools"`. |
| `platform` | string | Yes | One of: `"windows"`, `"linux"`, `"both"`. Controls which platforms the setup script is offered on. |
| `description` | string | Yes | One-sentence description shown in the UI. |
| `setup` | string | Yes | Repo-relative path to the install script (e.g. `"build-tools/cmake/setup.sh"`). |
| `receipt_name` | string | Yes | Basename used to locate `INSTALL_RECEIPT.txt` under the install prefix. Usually matches `id`. |
| `estimate` | string | Yes | Human-readable install time estimate shown before install (e.g. `"~30s"`). |
| `uses_prebuilt` | boolean | Yes | `true` if the tool installs from a prebuilt binary; `false` if it is scripts/source only. |
| `sort_order` | integer | Yes | Controls display order within a category. Lower numbers appear first. |
| `source` | string | Yes | Must be `"default"` for all tools in this repo. Team repos use `"team"`. |

### Example

```json
{
  "id": "cmake",
  "name": "CMake",
  "version": "4.3.1",
  "category": "Build Tools",
  "platform": "both",
  "description": "CMake 4.3.1 prebuilt for Windows x64 and Linux x86_64.",
  "setup": "build-tools/cmake/setup.sh",
  "receipt_name": "cmake",
  "estimate": "~30s",
  "uses_prebuilt": true,
  "sort_order": 20,
  "source": "default"
}
```

---

## Repository layout

```
airgap-devkit-tools/
  toolchains/
    clang/
      source-build/     devkit.json  (Clang / LLVM 22.1.3)
      style-formatter/  devkit.json  (LLVM Style Formatter)
    gcc/
      windows/          devkit.json  (GCC + MinGW-w64 15.2.0)
      linux/
        native/         devkit.json  (GCC Native, RHEL 8)
        cross/          devkit.json  (GCC Cross x86_64-bionic)
  build-tools/
    cmake/              devkit.json  (CMake 4.3.1)
    lcov/               devkit.json  (lcov 2.4)
  languages/
    python/             devkit.json  (Python 3.14.4)
    dotnet/             devkit.json  (.NET SDK 10.0.201)
  frameworks/
    grpc/               devkit.json  (gRPC 1.80.0)
  dev-tools/
    7zip/               devkit.json  (7-Zip 26.00)
    servy/              devkit.json  (Servy 7.9)
    conan/              devkit.json  (Conan 2.27.1)
    vscode-extensions/  devkit.json  (VS Code Extensions)
    sqlite/             devkit.json  (SQLite CLI)
    matlab/             devkit.json  (MATLAB Verification)
    git-bundle/         devkit.json  (git-bundle Transfer Tool)
```

See [TOOLS.md](TOOLS.md) for the full inventory table.

---

## License

Source-available. See [LICENSE](LICENSE) for terms.
Commercial use, redistribution, and SaaS hosting require prior written permission from the Author.
