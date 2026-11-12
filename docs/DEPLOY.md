# Publicar o app web (PWA) e instalar no celular

Guia da Fase 1: o app roda no navegador e pode ser instalado na tela inicial do iPhone ou do Android. Nesta fase, **os dados ficam no próprio aparelho**; a sincronização entre aparelhos é a Fase 2.

## 1. Gerar o site (no computador)

Primeira vez, na pasta do projeto:

```
flutter create . --platforms=web
```

Isso cria a pasta `web/`. Em seguida, **copie por cima** os arquivos desta entrega para `web/`, substituindo os gerados: `index.html`, `manifest.json`, `favicon.png`, `_headers` e a pasta `icons/` inteira.

Se o `flutter create` recriar o arquivo `test\widget_test.dart`, apague-o de novo (ele não combina com o nosso app).

Depois:

```
flutter pub get
flutter test
flutter run -d chrome        # testar no próprio computador (opcional)
flutter build web --release --no-web-resources-cdn
```

O `--no-web-resources-cdn` inclui no site os arquivos gráficos do Flutter (CanvasKit), em vez de baixá-los de outro servidor a cada abertura. Fica um site maior, mas carrega de um endereço só e funciona melhor offline.

O site pronto fica em `build/web`.

## 2. Publicar no Cloudflare Pages (grátis)

1. Crie uma conta gratuita em cloudflare.com.
2. No painel, abra **Workers & Pages**, escolha **Create** e depois **Pages**, e a opção de **upload direto** ("Upload assets"). Os nomes dos menus mudam de vez em quando, então use o que mais se parecer.
3. Dê um nome ao projeto (por exemplo, `adaptive-routine`).
4. Envie a pasta `build/web` (arraste a pasta ou o conteúdo dela) e clique em **Deploy**.
5. O endereço será parecido com `https://adaptive-routine.pages.dev`. Se o nome já existir, a Cloudflare acrescenta um sufixo.

**Para atualizar depois:** gere de novo com `flutter build web --release` e envie a nova versão no mesmo projeto (opção de criar um novo deployment).

Alternativa pela linha de comando (precisa de Node.js): `npx wrangler pages deploy build/web --project-name adaptive-routine`, depois de `npx wrangler login`.

## 3. Instalar no iPhone

1. No iPhone, abra o endereço no **Safari**. Não use o navegador embutido de outros apps (Instagram, WhatsApp etc.), porque a opção de instalar pode não aparecer.
2. Toque no botão **Compartilhar** (o quadrado com a seta para cima).
3. Escolha **Adicionar à Tela de Início**, deixe o nome "Rotina" e toque em **Adicionar**.
4. Abra o app pelo **ícone da tela inicial**. Ele abre em tela cheia, sem a barra do Safari.

**Use sempre o app pelo ícone.** O Safari e o app instalado guardam dados separados: o que você digitar numa aba do Safari não aparece no app instalado.

No **Android**, no Chrome: menu ⋮ e depois "Instalar app" (ou "Adicionar à tela inicial").

## 4. Atualizar uma versão já instalada

Depois de publicar uma versão nova, feche o app por completo (no iPhone, deslize para cima no alternador de apps) e abra de novo. Às vezes é preciso abrir duas vezes até a versão nova aparecer.

## 5. O que saber

- **Os dados ficam no aparelho.** Apagar o ícone da tela inicial apaga a agenda daquele app. A sincronização (Fase 2) resolve isso.
- **O endereço do site é público:** quem tiver o link consegue abrir o app, mas só vê uma agenda vazia dela mesma, porque nenhum dado sai do aparelho nesta fase.
- **Ainda não há** notificações nem voz no app web.
- **Desempenho no iPhone:** o Flutter web tem um teto de velocidade no Safari (veja a seção 6).
- **Tela branca ou erro ao abrir:** feche e reabra; se persistir, no iPhone vá em Ajustes, Safari, Avançado, Dados de Sites, apague o do seu endereço e instale de novo. Se continuar, me mande um print.

## 6. Desempenho no iPhone

O app web ficou **fluido no iPhone** depois das otimizações (menos redesenho no calendário, sem sombra e sem fade-in, tela de carregamento). Um teste de limitar a resolução de desenho (`?dpr=2`, `?dpr=1.5`) não mudou muito o resultado e foi retirado.

Se algum dia voltar a travar, o app tem um **medidor de quadros**: digite `desempenho` no chat para ligar (canto superior esquerdo) e de novo para desligar. Ele mostra, a cada segundo, quantos quadros foram desenhados, a duração média, a pior e quantos passaram de 16,7 ms (o limite para 60 quadros por segundo). Com a tela parada, aparece "sem quadros", e isso é normal.

Depois de publicar uma versão nova, abra o endereço **duas vezes** para o Safari trocar para ela.
