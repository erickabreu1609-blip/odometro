# Odômetro no GitHub — tudo pelo navegador

A pasta está organizada assim:

```
docs/                 ← o SITE (index.html, convites, mapas, privacidade). É isto que vai para o ar.
app-mobile/           ← o app de celular (Expo)
banco/                ← arquivos .sql já aplicados no Supabase (histórico)
supabase-functions/   ← funções do Stripe (cópia de referência)
```

O site fica na pasta `docs` porque o GitHub Pages publica direto dela, sem nenhuma configuração
extra.

---

## 1. Criar o repositório (uma vez só)

1. Entre em **github.com** (crie a conta se ainda não tiver).
2. Clique no **+** no canto superior direito → **New repository**.
3. Repository name: **`odometro`**
4. Marque **Public** (o GitHub Pages grátis só funciona com repositório público — o código não
   tem senhas nem chaves secretas, eu conferi).
5. **Não** marque "Add a README". Clique em **Create repository**.

## 2. Enviar o site

1. Na página do repositório recém-criado, clique no link **"uploading an existing file"**.
2. Abra a pasta `C:\Users\erick\OneDrive\SaaS Odômetro` no Explorador de Arquivos.
3. **Arraste** para a área do navegador (arrastar mantém as pastas; o botão "choose your
   files" não aceita pastas):
   - a pasta **`docs`**
   - a pasta **`banco`**
   - a pasta **`supabase-functions`**
   - os arquivos **`.md`** (LEIA-ME, COMO-PUBLICAR…) e o **`.gitignore`**
4. **Não arraste**: os `.zip`, `_extracted.js`, `_gc.js`.
5. Espere carregar e clique em **Commit changes**.

## 3. Ligar o GitHub Pages

1. No repositório: **Settings** → menu da esquerda **Pages**.
2. Em "Build and deployment": **Source: Deploy from a branch**.
3. Branch: **main** e pasta **/docs** → **Save**.
4. Em 1–2 minutos aparece no topo: *"Your site is live at…"*. O endereço será:
   **`https://SEU-USUARIO.github.io/odometro/`**

## 4. Enviar o app (opcional, para guardar o código)

Repita o passo 2 arrastando só a pasta **`app-mobile`** (são 96 arquivos — o GitHub aceita até
100 por envio). Se um dia aparecer uma pasta `node_modules` dentro dela, **não** envie essa
pasta (é gigante e se recria com `npm install`), nem o arquivo `google-services.json`.

Opcional: arraste também a pasta **`.github`** — ela faz o GitHub rodar os 64 testes do app a
cada mudança e avisar por e-mail se algo quebrar. Se o Windows não mostrar essa pasta, ative
"Itens ocultos" no menu Exibir do Explorador.

## 5. Trocar o endereço antigo do Netlify pelo novo (obrigatório)

Troque `SEU-USUARIO` pelo seu usuário do GitHub:

1. **Supabase → Project Settings → Edge Functions → Secrets** → `SITE_URL` =
   `https://SEU-USUARIO.github.io/odometro`
   (é o endereço dos e-mails de convite, do convite de administrador e da volta do Stripe).
2. **Supabase → Authentication → URL Configuration**:
   - Site URL: `https://SEU-USUARIO.github.io/odometro/`
   - Redirect URLs: adicione `https://SEU-USUARIO.github.io/odometro/**`
3. **App**: `app-mobile/src/lib/config.ts` — troque `SEU-USUARIO`.
4. **Privacidade**: `docs/privacidade.html` — troque `contato@seudominio.com.br` pelo seu e-mail.

Me diga seu usuário do GitHub que eu faço o item 3 e o ajuste no texto; os itens 1 e 2 são no
painel do Supabase (eu te guio).

## 6. Quando eu mudar algum arquivo do site

1. No GitHub, entre na pasta **`docs`** do repositório.
2. **Add file → Upload files** → arraste o(s) arquivo(s) que eu disser que mudaram (por exemplo
   `index.html`). Arquivo com o mesmo nome é substituído.
3. **Commit changes**. Em 1–2 minutos o site atualiza.

Sempre vou te dizer exatamente quais arquivos mudaram e em qual pasta.
