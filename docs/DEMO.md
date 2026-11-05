# Como gravar o GIF e os prints

Material de apoio para o autor. O README já tem o espaço para o GIF.

## Antes de gravar (estado limpo e repetível)

1. Feche o app.
2. Apague `schedule.json` e `routine.json`. O caminho aparece no terminal quando o app inicia (linhas "Agenda salva em..." e "Rotina fixa salva em...").
3. Abra o app, com a janela em cerca de **1000×700** (o chat aparece ao lado).
4. Digite `carregar exemplo`. Aparecem Cálculo II, Laboratório e um "Estudo de Física" hoje às 17h.

## Roteiro (10 a 15 segundos)

| Tempo | Ação |
|---|---|
| 0–3 s | Digitar `Tenho uma reunião de última hora hoje às 17h` |
| 3–6 s | O app avisa o choque. Digitar `sim` |
| 6–9 s | Digitar `amanhã 19h` (ou tocar numa das opções) |
| 9–12 s | O calendário reorganiza. Deixar parado um instante no resultado, em hoje e em amanhã (seta `›`) |

## Ferramentas (Windows)

- **ScreenToGif** (gratuito): grava a região da tela e exporta GIF. Use 10 a 15 quadros por segundo e largura de uns 900 px.
- Mantenha o arquivo abaixo de uns 5 a 8 MB para carregar rápido no GitHub.
- Prints: `Win + Shift + S`.

## Onde salvar

- `docs/media/demo.gif`: o GIF principal.
- `docs/media/dark.png` e `docs/media/light.png` (opcional): prints dos dois temas.

Depois, no `README.md`, descomente a linha da imagem no topo.
