# License and third-party notices

## Project source

The project's source code is distributed under the **GNU General Public License, version 3 or (at your option) any later version** (SPDX identifier: `GPL-3.0-or-later`). See [LICENSE](LICENSE) for the complete license text. This matches the license declared in the workspace's `Cargo.toml`.

This repository is a working fork of [codec_d--cool_fox](https://git.gtahub.st/github/codec-d--cool_fox), based on the build by **cgbj**. Keep applicable upstream copyright and license notices intact when modifying or redistributing files.

## Separate asset exception

`crates/victory-formats/src/bcpack-tables.bin` is identified in [docs/asset-policy.md](docs/asset-policy.md) as a special exception and is expressly stated there to be outside the repository's license. **Do not assume that the GPL notice for the source code grants rights to this file.** Its provenance and applicable permission must be assessed separately before redistributing it.

## Third-party dependencies

Third-party crates retain their own copyright and license terms; the project's GPL declaration does not replace those terms. The dependency versions are pinned in [Cargo.lock](Cargo.lock). The workspace manifest specifically notes that `zlib-rs` is under the Zlib license and `opus-pure` is under BSD-3-Clause.

This notice is not a complete inventory of every direct and transitive dependency license, and it does not replace the license files or notices distributed by those projects. Consult each crate's published license and notices when preparing a binary distribution.
