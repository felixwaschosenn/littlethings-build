# littlethings-build

An experimental compatibility layer for running a **user-provided** Xbox Series S dump of GTA VI on Windows with DirectX 12. This repository contains the VIctory source code and tweaks targeting the Radeon RX 6600 (RDNA 2, 8 GB). It is based on the build by **cgbj** and is a working fork of [codec_d--cool_fox](https://git.gtahub.st/github/codec-d--cool_fox).

This repository does not distribute the game itself, game executables, extracted shader caches, or game DLLs. Any game files used for testing must remain outside the repository and be supplied by the user.

## Current status

The project builds in Release mode and can render scenes, but **it is not stable and does not render all graphics correctly yet**. In local tests on an RX 6600, `DXGI_ERROR_DEVICE_HUNG` occurred and the 3D scene ran at around 2–3 FPS. A test after the fence check reached the 115-second timeout without an observed device removal, but this does not prove that TDR has been eliminated.

Measured peak private memory was **18.8 GB**; the 10–16 GB target has not yet been reached. This build should not be considered playable or ready for regular gameplay.

## Changes in this tree

- **VRAM:** limits empty DX12 heaps according to the current budget reported by `IDXGIAdapter3::QueryVideoMemoryInfo`; discards idle texture copies under memory pressure; and makes the texture floor respect the budget on GPUs with up to 8 GB of VRAM.
- **RAM and uploads:** lowers the per-frame staging cap for a local budget of up to 8 GB. VIctory's existing upload pools and idle-buffer cleanup are retained. These are admission and retention limits, not a hard cap on total process memory.
- **Fences and resources:** keeps GPU-used commands and objects alive until submissions complete. Synchronous waits confirm the effective fence value and abort copy-back or reuse if a failure or device removal occurs.
- **Shaders:** splits stage outputs with incompatible interpolations into valid DXIL lines; mesh shaders exceeding the output limit are rejected instead of being passed to the driver.
- **PSOs and DXIL:** the project already includes a persistent shader cache and pipeline library, with worker threads to pre-warm PSOs. Changes in this tree preserve that path.
- **RX 6600 profile:** the launch script uses conservative submission, disables unvalidated ray-tracing/RTGI paths, and enforces a timeout while writing local logs.

Known visual limitations remain: some draws without a valid PSO are discarded, one mesh shader still lacks a supported translation, and lighting may appear too dark. The script does not modify the dump files.

## Requirements

- 64-bit Windows 10/11 and a DirectX 12-capable GPU. Tested profile: AMD Radeon RX 6600 with 8 GB of VRAM.
- Rust 1.98.1 with the `x86_64-pc-windows-msvc` target (pinned in `rust-toolchain.toml`).
- Visual Studio 2022 Build Tools with the MSVC compiler and Windows 10/11 SDK. **This project builds with Cargo/Rust; there is no CMake project or Visual Studio solution in this tree.**
- Gaming Services and XGameRuntime available on the system; the Visual C++ Redistributable may also be required.
- The x64 versions of `dxcompiler.dll` and `dxil.dll` alongside the final `victory.exe`.
- Your own dump, stored outside the repository, containing `game_scarlett_master.exe`. The user is responsible for the ownership and use of their game files.

## Build (Release)

Open PowerShell in the repository root:

```powershell
rustup toolchain install 1.98.1 --profile minimal --target x86_64-pc-windows-msvc
cargo build --release --locked -p victory
```

The executable is created at `target\\release\\victory.exe`. Copy the x64 DLLs from the Windows SDK into the same directory (adjust the SDK version if needed):

```powershell
$sdk = Get-ChildItem "${env:ProgramFiles(x86)}\\Windows Kits\\10\\bin" -Directory |
  Where-Object { (Test-Path (Join-Path $_.FullName 'x64\\dxcompiler.dll')) -and (Test-Path (Join-Path $_.FullName 'x64\\dxil.dll')) } |
  Sort-Object Name -Descending | Select-Object -First 1
if (-not $sdk) { throw 'x64 DXC/DXIL not found in the Windows SDK.' }
Copy-Item (Join-Path $sdk.FullName 'x64\\dxcompiler.dll') .\\target\\release\\
Copy-Item (Join-Path $sdk.FullName 'x64\\dxil.dll') .\\target\\release\\
```

## Run with a timeout

Keep your dump directory **outside the repository checkout**. Example:

```powershell
.\\scripts\\run-rx6600.ps1 -GameDir 'C:\\path\\to\\your\\dump' -TimeoutSeconds 300
```

You can also use:

```powershell
.\\Play-VIctory.cmd "C:\\path\\to\\your\\dump"
```

The script writes logs and a result file to `%LOCALAPPDATA%\\VIctory\\logs\\rx6600`, uses the cache at `%LOCALAPPDATA%\\VIctory\\cache-rx6600`, and terminates only the process it launched when the timeout is reached.

To launch directly, without the profile or timeout:

```powershell
.\\target\\release\\victory.exe run 'C:\\path\\to\\your\\dump\\game_scarlett_master.exe' --console series-s --execute
```

## Verification and provenance

The following command tests the updated VRAM limit:

```powershell
cargo test --release --locked -p victory-gpu --lib small_card_texture_floor_still_leaves_budget_for_targets
```

An earlier Release test of `victory-shader` passed 282 tests; an audit of newly generated DXIL validated 1,960 entries. These results do not replace in-game stability testing.

The architecture is documented in `docs/architecture.md`, and the asset policy is described in `docs/asset-policy.md`. See [LICENSE](LICENSE) for the project's GPL-3.0-or-later license and the third-party notices in the source code and documentation.

This project is independent and is not affiliated with or endorsed by Rockstar Games, Take-Two Interactive, or Microsoft. All trademarks belong to their respective owners.
