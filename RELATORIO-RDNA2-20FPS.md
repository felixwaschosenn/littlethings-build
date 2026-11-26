# Relatório Técnico — Overhaul RDNA 2 / RX 6600 (`rdna2-20fps-overhaul`)

## 1. Resumo Executivo

Este relatório documenta a auditoria completa e as otimizações estruturais aplicadas na camada de compatibilidade DirectX 12 (`VIctory`) na branch `rdna2-20fps-overhaul`, visando estabilidade sem crashes/TDR e desempenho alvo de ~20 FPS na **AMD Radeon RX 6600 (RDNA 2, 8 GB VRAM)** executando o dump Xbox Series S (`game_scarlett_master.exe`).

---

## 2. Correções no Pipeline de Shaders, DXIL e PSOs

### 2.1 Auditoria Completa do Tradutor (`victory translate`)
Executado `victory.exe translate` contra `shaders.rpf` (`--jobs 8`):
- **Containers encontrados:** 26.503 (614 duplicados ignorados)
- **Vertex & Pixel Shaders:** **14.247 / 14.247** emitidos (100%)
- **Compute Shaders:** **2.677 / 2.682** emitidos (99,8%) — 5 falhas por descritor lido apenas como dados (`CS_TraceShadowRays_Quarter_*`)
- **Mesh Shaders:** **8.694 / 8.765** emitidos (99,2%) — 71 falhas por excederem o limite de 32 KiB de saída do host (`MS_VS_PedTransform_Decals_*`)

### 2.2 Validação Pré-PSO e Fallback Seguro (`crates/victory-gpu/src/pipeline/host.rs`)
- **Validação de Bytecode DXIL (`validate_dxil`):** verifica tamanho mínimo (`>= 32` bytes) e assinatura `DXBC` antes de submeter ao driver D3D12, evitando que blobs corrompidos ou nulos cheguem ao driver Adrenalin.
- **Orçamento de Root Signature (`root_signature_dwords`):** valida o limite de 64 DWORDs do D3D12 (constantes = `N` DWORDs, root CBV/SRV/UAV = 2 DWORDs, descriptor tables = 1 DWORD) antes de `CreateRootSignature`.
- **Sanitização de Estado Gráfico (`sanitize_graphics_state`):** limita `NumRenderTargets <= 8`, garante `SampleDesc.Count >= 1` e desabilita `DepthEnable`/`StencilEnable`/`depth_bounds` quando `DSVFormat == DXGI_FORMAT_UNKNOWN`, evitando rejeições ou hangs no driver desktop AMD.
- **Fallback Pixel Shader (`ps_6_6` via `dxcompiler.dll`):** adicionado `fallback_pixel_dxil(rt_count)` (controlado por `VICTORY_FALLBACK_SHADERS`, ativo por padrão). Quando um Pixel Shader falha na tradução ou na criação do PSO gráfico/mesh, o pipeline tenta compilar um `ps_6_6` pass-through seguro (`void main() {}` para passes depth-only ou saída `(0,0,0,1)` para `1..=8` RTs) e registra o hash problemático no log, preservando geometria/profundidade em vez de descartar o draw inteiro.

---

## 3. Paralelismo de CPU e Redução de Overhead DX12

### 3.1 Batching de `ResourceBarrier` (`crates/victory-gpu/src/list.rs`, `crates/victory-gpu/src/draw.rs`)
- Adicionados `queue_state_barrier` e `flush_barriers` em `list.rs`, e `readable_batched` em `draw.rs`.
- As transições de estados de render targets, depth-stencil e tabelas de descritores (SRVs/UAVs) por draw/dispatch agora são acumuladas em lote e submetidas em uma única chamada `ID3D12GraphicsCommandList::ResourceBarrier`, reduzindo chamadas COM por frame.

### 3.2 Reativação do Pipeline Paralelo/Assíncrono (`scripts/run-rx6600.ps1`)
O perfil conservador anterior desabilitava todas as otimizações de concorrência (`=0`), serializando CPU e GPU:
- `VICTORY_THIN=1` (8 worker threads traduzindo command lists em paralelo)
- `VICTORY_ASYNC_SUBMIT=1` (thread dedicada para preparo/submissão de frames)
- `VICTORY_LATE_WAIT=3` + `VICTORY_RELAY=2` (sobreposição CPU-GPU e landing assíncrono de voos)
- `VICTORY_RELAY_COPY=1` (readbacks via fila separada)
- `VICTORY_UPLOAD_AHEAD=1` (uploads de texturas via `D3D12_COMMAND_LIST_TYPE_COPY`)
- `VICTORY_JOIN_PARTS=4` (agrupamento de até 4 partes por submissão)

---

## 4. Estabilidade e Orçamento de 8 GB VRAM / 10–16 GB RAM

- **Pool de Blocos VRAM (`crates/victory-gpu/src/pool.rs`):**
  - `ahead()` (`VICTORY_RIPE_BLOCKS`): reduzido automaticamente de `12` (768 MiB) para **`3` blocos (192 MiB)** em GPUs com orçamento `<= 8 GiB`, liberando ~576 MiB imediatos de VRAM.
  - `spares()`: zera blocos vazios retidos quando o uso atinge **80%** do orçamento DXGI em placas `<= 8 GiB` (antes era 85%).
- **Política de Evicção LRU (`crates/victory-gpu/src/host.rs`):**
  - Em placas `<= 8 GiB`, `vram_keep` passa a disparar evicção de texturas ociosas acima de **78%** (alvejando 72%) e evicção agressiva acima de **88%** (alvejando 70%), mantendo o pico abaixo do limite físico da RX 6600.
- **Orçamento de RAM (`crates/victory-gpu/src/residency.rs`):**
  - Em hosts com RAM limitada (`<= 32 GiB`), `prefetch_limit` passa a limitar uploads especulativos a **32 MiB/frame** quando o staging ativo atinge **768 MiB** (antes 64 MiB/frame a partir de 1 GiB).

---

## 5. Resultados Observados (Antes vs. Depois)

| Métrica | Baseline (`run-rx6600.ps1` inicial, 75s) | Build Final (`rdna2-20fps-overhaul`, 120s) |
|---|---|---|
| **Estabilidade / TDR** | Timeout 75s (`ExitCode=124`), 0 crashes | Timeout 120s (`ExitCode=124`), **0 crashes, 0 TDR, 0 WARN/ERROR** |
| **Pipeline Paralelo** | Desligado (`THIN=0`, `ASYNC_SUBMIT=0`, `RELAY=0`) | **Ativo** (`THIN=1` 8 threads, `ASYNC_SUBMIT=1`, `LATE_WAIT=3`, `RELAY=2`, `UPLOAD_AHEAD=1`) |
| **VRAM em Uso (DXGI Local)** | 97 MB / 7379 MB (menu) | 353 MB / 7379 MB (menu) |
| **FPS / Frametime (Menu/Load)** | 30.0 FPS / 33.3 ms (11 draws/frame) | 30.0 FPS / 33.3 ms (0.1 ms CPU prep, 0.0 ms GPU wait, 11 draws/frame) |
| **Testes Unitários Alvo (`victory-gpu`)** | — | `residency::tests` + `pool::tests` (7/7) + `textures_are_kept_while_the_card_has_room` (1/1): **PASS** |
| **Testes Unitários (`victory-shader`)** | 282 passed, 0 failed, 4 ignored | Sem regressões |

> **Nota sobre medição em cena 3D:** Durante os testes automatizados com timeout em modo *headless/hidden*, o jogo permanece no menu inicial (`11 draws/frame`, `30.0 FPS`) aguardando interação para entrar no Modo História. A validação do alvo de **~20 FPS em cena 3D aberta** e do pico de **10–16 GB de RAM** em gameplay contínuo requer executar o comando abaixo interativamente e entrar no jogo.

---

## 6. Como Executar e Publicar no GitHub

### Executar a Build Release Final
```powershell
.\scripts\run-rx6600.ps1 -GameDir 'C:\Users\Usuario\Downloads\ABDM\Compressed\GTA6xbox' -TimeoutSeconds 300
```
Ou diretamente:
```powershell
.\target\release\victory.exe run 'C:\Users\Usuario\Downloads\ABDM\Compressed\GTA6xbox\game_scarlett_master.exe' --console series-s --execute
```

### Publicar a Branch no GitHub
```powershell
git push -u origin rdna2-20fps-overhaul
```
