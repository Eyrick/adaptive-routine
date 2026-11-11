# Sincronização entre aparelhos (Supabase)

Com a sincronização ligada, o computador, o iPhone e o Android mostram a **mesma agenda**. Cada aparelho guarda a sua cópia (o app continua funcionando sem internet) e troca com a nuvem quando há conexão.

## 1. Criar o projeto no Supabase (uma vez)

1. Entre em supabase.com e faça login (e-mail ou GitHub).
2. **New project**: nome `adaptive-routine`, escolha uma senha do banco (guarde, mas não vamos usá-la no app), região **South America (São Paulo)** se aparecer, plano **Free**. Espere uns 2 minutos até ficar pronto.
3. **SQL Editor > New query**: abra o arquivo `supabase/schema.sql` deste repositório, cole o conteúdo e clique em **Run**. Isso cria a tabela da agenda e as regras de segurança: cada conta só vê e altera a própria linha.
4. **Authentication**: em *Sign In / Providers* (o nome do menu varia), confira que **Email** está ativado e **desligue "Confirm email"**. Assim o cadastro entra direto, sem esperar e-mail.
5. **Project Settings > API** (ou "API Keys"): copie o **Project URL** e a chave **anon / public**. **Nunca use a `service_role`**: ela dá acesso total e não pode ir para o app.

## 2. Configurar o app

1. Copie `env.example.json` para `env.json` e preencha com o seu endereço e a chave anon.
2. Acrescente `env.json` ao `.gitignore`, para não subir para o GitHub. (A chave anon foi feita para ser pública e a segurança vem das regras do passo 3 acima, mas manter fora do repositório é mais organizado.)

## 3. Rodar e compilar com a configuração

```
flutter pub get
flutter run -d windows --dart-define-from-file=env.json
flutter build web --release --no-web-resources-cdn --dart-define-from-file=env.json
flutter build apk --release --dart-define-from-file=env.json
```

Sem o `--dart-define-from-file`, o app funciona normalmente, só **sem** o ícone de nuvem.

## 4. Usar

1. **No computador primeiro:** toque no ícone de nuvem (na barra do calendário), em **Criar conta**, e use e-mail e senha. A agenda deste aparelho sobe para a nuvem.
2. **No iPhone (e no Android):** publique de novo o app web (ou instale o APK novo), toque no ícone de nuvem e use **Entrar** com o mesmo e-mail e senha. A agenda aparece.
3. Se o aparelho já tinha dados próprios (por exemplo, testes antigos), aparece um **conflito**. No iPhone, escolha **"Usar a da nuvem"**.

O ícone mostra a situação: nuvem com check (sincronizado), setas (sincronizando), nuvem riscada (sem conta ou sem conexão), triângulo (conflito).

## 5. Como funciona

- A nuvem guarda **uma única agenda por conta**, com número de versão.
- O app envia a mudança uns 2 segundos depois de você parar de mexer, confere a nuvem a cada 30 segundos e ao voltar para o app, e adota o que veio de outro aparelho.
- Só envia se a nuvem ainda estiver na versão que este aparelho conhece. Se alguém mudou no meio, ele confere de novo antes de sobrescrever.
- **Conflito:** só acontece quando a agenda mudou **nos dois lugares** desde a última sincronização. O app pergunta qual manter. Para evitar, deixe o app sincronizar antes de editar em outro aparelho.
- O que vem da nuvem **zera o histórico do "desfazer"** daquele aparelho.

## 6. Cuidados

- **Segurança:** a proteção é feita pelas regras de acesso por linha (`schema.sql`). Não desligue a segurança por linha na tabela.
- **Só você usa?** Depois de criar a sua conta (e a de quem mais for usar), desligue *"Allow new users to sign up"* em *Authentication*, para estranhos não criarem contas no seu projeto.
- **Plano grátis:** o Supabase pode **pausar o projeto por inatividade**. Os dados não são apagados. Se o app parar de sincronizar, abra o painel do Supabase e retome o projeto.
- **Privacidade:** a agenda fica guardada nos servidores do Supabase. Se isso incomodar, use o app sem o `env.json` (só local).
- **Esta versão sincroniza a agenda inteira**, e não item por item. Para um uso por vez (uma pessoa, dois ou três aparelhos), é suficiente e mais seguro. Edição simultânea nos dois aparelhos sempre vira conflito.

## 7. Problemas comuns

| Sintoma | O que fazer |
|---|---|
| "Invalid API key" ou erro ao entrar | Confira o `env.json` (a URL termina em `.supabase.co`, e a chave é a **anon**) e recompile. |
| `permission denied for table user_state` (código 42501) | A tabela não foi liberada para quem está logado. Rode o `schema.sql` atualizado no SQL Editor, ou só esta linha: `grant select, insert, update, delete on table public.user_state to authenticated;` |
| Erro de permissão por linha (RLS) | Rode o `schema.sql` de novo no SQL Editor (as regras de segurança por linha não foram criadas). O arquivo pode ser repetido sem problema. |
| "Conta criada. Confirme o e-mail" | Desligue **Confirm email** (passo 1.4) ou confirme pelo link no e-mail. |
| Fica em "Sem conexão" | Confira a internet e se o projeto não foi pausado no painel. |
