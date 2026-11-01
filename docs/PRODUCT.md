# PRODUCT.md — Adaptive Routine AI (Fluid Scheduler)

> Status: Fase 1 (Desktop + Android) · Versão do doc: 0.1

## 1. Validação da ideia (resumo do Tech Lead + PM)

**Veredito: ideia válida, com um ajuste de posicionamento.**

| Ponto | Avaliação |
|---|---|
| Dor real | Alta. Estudantes têm base rígida (aulas) + caos variável (provas, grupos, reuniões). Agendas atuais tratam tudo como bloco igual. |
| Diferencial | O **Duplo Calendário** separa o que é *imutável* do que é *negociável*. Isso é o que torna o remanejamento seguro e automatizável. |
| Risco principal | Confiança. Se a IA mover algo errado uma vez, o usuário abandona. Mitigação: **a IA propõe, o motor determinístico valida, o usuário confirma**. |
| Risco técnico | LLM não deve calcular horários. Ele só extrai intenção; conflitos e janelas livres são calculados por código local (testável, offline, instantâneo). |
| Ajuste | Posicionar como **"agenda que negocia com você"**, não "agenda com chatbot". O chat é a interface, o motor de conflitos é o produto. |

## 2. Proposta de valor

> *"Sua rotina fixa fica protegida. O imprevisto encontra o próprio lugar."*

### O Duplo Calendário

| | **Camada 1 — Base (Fixo)** | **Camada 2 — Dinâmica (Extras)** |
|---|---|---|
| Conteúdo | Aulas, trabalho, compromissos recorrentes | Estudos, tarefas, reuniões de última hora |
| Editável pela IA | **Nunca** (só o usuário edita) | **Sim**, com confirmação |
| Recorrência | Sim | Normalmente pontual |
| Papel no conflito | Barreira intransponível | Candidato a remanejamento |
| Visual | Sólido, discreto, ícone de cadeado | Cor de destaque, animado ao mover |

**Regra de ouro:** bloco Fixo nunca é movido pela IA. Se o novo evento colide com um Fixo, a IA oferece janelas alternativas para o *novo* evento.

## 3. Personas

### Marina, 20 — Universitária (persona primária)
- Engenharia, 6 aulas/semana, estágio meio período, grupo de estudo.
- **Dor:** "Todo fim de semana refaço minha agenda no papel porque algo mudou."
- **Quer:** falar "o professor marcou revisão amanhã 15h" e ver tudo se ajustar.

### Rafael, 27 — Concurseiro que trabalha
- Trabalho fixo 8–17h, estuda à noite, plano de estudo muda conforme simulados.
- **Dor:** estudo perdido vira culpa e não é reposto.
- **Quer:** que o estudo não cumprido seja realocado automaticamente na semana.

### Persona secundária (pós-MVP): Profissional freelancer com horários variáveis.

## 4. Jornada da Marina (cenário-âncora)

| Etapa | Ação | Emoção | Resposta do produto |
|---|---|---|---|
| 1. Onboarding | Importa/cria aulas e trabalho como **Base Fixa** (2 min) | Neutro | Grade semanal pronta, bloqueios com cadeado |
| 2. Planejamento | "Preciso estudar Física 3x essa semana, 1h30 cada" | Organizada | IA aloca 3 blocos na camada Dinâmica |
| 3. Imprevisto | "Reunião de última hora hoje às 17h" | Estressada | Detecta choque com *Estudo de Física* e propõe 3 janelas |
| 4. Decisão | Toca na janela "Amanhã 19:00" | Aliviada | Reunião entra às 17h, Física move, animação fluida |
| 5. Notificação | 16:45 — lembrete da reunião | Confiante | Push com ações *Ok / Adiar* |
| 6. Fim do dia | 21:00 — "Sua rotina de amanhã foi ajustada. Quer revisar?" | Controle | Abre resumo do dia seguinte |

## 5. Escopo

### MVP (Fase 1)
- Calendário semanal com 2 camadas e filtro por camada.
- Chat em texto (voz via speech-to-text do SO no marco M3).
- Motor de conflitos local com sugestão de 2–3 janelas.
- Armazenamento local-first (SQLite), funciona offline.
- Notificações locais (Windows, macOS, Linux, Android).
- Dark/Light mode.

### Fora do MVP
- iOS (Fase 2), sync multi-dispositivo em nuvem, integração Google/Outlook Calendar, colaboração, aprendizado de preferências.

## 6. Métricas de sucesso
- **Time-to-resolve** de um conflito: < 15 s (da frase ao calendário atualizado).
- ≥ 70% das sugestões de janela aceitas sem edição manual.
- Cold start < 1,5 s no desktop e < 2 s no Android médio.
- Retenção D7 ≥ 35% entre estudantes.

## 7. Riscos e mitigações
| Risco | Mitigação |
|---|---|
| Alucinação do LLM com datas | LLM só retorna JSON de intenção; datas resolvidas por parser/código; UI sempre mostra preview antes de confirmar |
| Custo/latência de LLM | Parser local simples para frases comuns; LLM só quando ambíguo |
| Privacidade da agenda | Local-first; ao LLM vai apenas o mínimo (intenção + janelas anônimas), nunca a agenda completa por padrão |
| Fadiga de notificação | Teto diário, agrupamento, horário de silêncio |
