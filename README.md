# littlethings-build

Camada experimental de compatibilidade para executar, no Windows com DirectX 12, um dump **fornecido pelo próprio usuário** da versão Xbox Series S de GTA VI. Este repositório contém o código-fonte do VIctory e ajustes voltados à Radeon RX 6600 (RDNA 2, 8 GB). Não contém o jogo, shaders extraídos, caches, executáveis ou DLLs.

## Estado atual

O projeto compila em Release e chega a renderizar cenas, mas **ainda não é estável nem reproduz todos os gráficos corretamente**. Nos testes locais com RX 6600, houve `DXGI_ERROR_DEVICE_HUNG` e a cena 3D ficou em torno de 2–3 FPS. Um teste após a checagem de fence alcançou o timeout de 115 s sem remoção observada do device, mas isso não prova que o TDR foi eliminado. O pico medido de memória privada foi **18,8 GB**; a meta de 10–16 GB ainda não foi atingida. Não recomendamos tratar esta build como pronta para jogar.

## Ajustes desta árvore

- **VRAM:** limite de heaps DX12 vazios conforme o orçamento atual de `IDXGIAdapter3::QueryVideoMemoryInfo`; descarte de cópias de texturas ociosas sob pressão; o piso de texturas também respeita o orçamento nas placas de até 8 GB.
- **RAM e uploads:** teto de staging por frame reduzido para orçamento local de até 8 GB; pools de upload e limpeza de buffers ociosos já existentes no VIctory. São limites de admissão e retenção, não um teto rígido para toda a memória do processo.
- **Fences e recursos:** comandos e objetos usados pela GPU permanecem vivos até o término das submissões. Os waits síncronos confirmam o valor efetivo da fence e abortam o copy-back/reuso em caso de falha ou remoção do device.
- **Shaders:** saída de estágios com interpolações incompatíveis é separada em linhas válidas de DXIL; mesh shaders acima do limite de saída são recusados em vez de enviados ao driver.
- **PSOs e DXIL:** cache persistente de shaders e pipeline library, com trabalhadores para antecipar PSOs, já fazem parte do projeto. As otimizações desta árvore mantêm esse caminho.
- **Perfil RX 6600:** o script de execução usa submissão conservadora, desliga os caminhos de ray tracing/RTGI que ainda não foram validados e impõe timeout com logs locais.

Há limitações visuais conhecidas: alguns draws sem PSO válido são descartados, um mesh shader permanece sem tradução suportada e a iluminação pode sair escura. O script não altera os arquivos do dump.

## Requisitos

- Windows 10/11 de 64 bits e GPU com DirectX 12. Perfil testado: AMD Radeon RX 6600, 8 GB de VRAM.
- Rust 1.98.1 com alvo `x86_64-pc-windows-msvc` (fixado em `rust-toolchain.toml`).
- Visual Studio 2022 Build Tools com compilador MSVC e Windows 10/11 SDK. **O build é Cargo/Rust; não há projeto CMake nem solução Visual Studio nesta árvore.**
- Gaming Services e XGameRuntime disponíveis no sistema; Visual C++ Redistributable quando necessário.
- `dxcompiler.dll` e `dxil.dll` de x64 junto ao `victory.exe` final.
- Dump próprio, fora do repositório, contendo `game_scarlett_master.exe`. A posse e o uso dos arquivos do jogo são responsabilidade do usuário.

## Compilar em Release

No PowerShell, na raiz do repositório:

```powershell
rustup toolchain install 1.98.1 --profile minimal --target x86_64-pc-windows-msvc
cargo build --release --locked -p victory
```

O executável fica em `target\release\victory.exe`. Copie as DLLs x64 do Windows SDK para a mesma pasta (ajuste a versão do SDK se necessário):

```powershell
$sdk = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin" -Directory |
  Where-Object { (Test-Path (Join-Path $_.FullName 'x64\dxcompiler.dll')) -and (Test-Path (Join-Path $_.FullName 'x64\dxil.dll')) } |
  Sort-Object Name -Descending | Select-Object -First 1
if (-not $sdk) { throw 'DXC/DXIL x64 não encontrados no Windows SDK.' }
Copy-Item (Join-Path $sdk.FullName 'x64\dxcompiler.dll') .\target\release\
Copy-Item (Join-Path $sdk.FullName 'x64\dxil.dll') .\target\release\
```

## Executar com timeout

Use o diretório do seu dump **fora do checkout**. Exemplo para a instalação usada nos testes:

```powershell
.\scripts\run-rx6600.ps1 -GameDir 'C:\Users\Usuario\Downloads\ABDM\Compressed\GTA6xbox' -TimeoutSeconds 300
```

Também é possível usar `Play-VIctory.cmd "C:\caminho\do\dump"`. O script produz logs e um arquivo de resultado em `%LOCALAPPDATA%\VIctory\logs\rx6600`, usa o cache em `%LOCALAPPDATA%\VIctory\cache-rx6600` e encerra somente o processo iniciado quando chega ao timeout. Para iniciar diretamente, sem o perfil/timeout:

```powershell
.\target\release\victory.exe run 'C:\Users\Usuario\Downloads\ABDM\Compressed\GTA6xbox\game_scarlett_master.exe' --console series-s --execute
```

## Verificação e origem

`cargo test --release --locked -p victory-gpu --lib small_card_texture_floor_still_leaves_budget_for_targets` valida o novo limite de VRAM. Um teste Release anterior de `victory-shader` passou com 282 testes; a auditoria de DXIL recém-gerado validou 1.960 entradas. Isso não substitui testes de estabilidade em jogo.

Este é um fork de trabalho de [codec_d--cool_fox](https://git.gtahub.st/github/codec-d--cool_fox). A arquitetura está em `docs/architecture.md`, e a política que impede incluir material do jogo está em `docs/asset-policy.md`. Código sob [GPL-3.0-or-later](LICENSE); veja os avisos de terceiros no próprio código e na documentação.
