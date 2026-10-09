# Odômetro — por que o e-mail de convite não está chegando (e o que já ajustei)

## O que eu já fiz agora

1. **Botão "Copiar link" nos convites.** Na aba **Equipe → Convites enviados**, cada convite pendente agora tem um ícone de link (🔗) ao lado de "Reenviar". Clicando, o link de aceite é copiado — dá para mandar por WhatsApp, SMS etc. mesmo que o e-mail automático ainda não esteja funcionando. Isso já resolve o problema na prática, hoje.
2. **Administrador agora tem aceite automático** (mais detalhes abaixo) — não depende mais do Resend, só do e-mail nativo do Supabase.

## Por que o e-mail automático (coordenador/funcionário/motorista) não está saindo

O convite por e-mail passa por uma Edge Function (`enviar-convite`) que usa o **Resend** para disparar a mensagem. Ela só funciona se três segredos estiverem configurados no Supabase (**Project Settings → Edge Functions → Secrets**):

| Nome | O que é |
|---|---|
| `RESEND_API_KEY` | Chave da API do Resend |
| `RESEND_FROM` | Remetente, ex.: `Odômetro Escolar <convites@seudominio.com>` |
| `SITE_URL` | `https://SEU-USUARIO.github.io/odometro` |

Se `RESEND_API_KEY` nunca foi configurada, a função falha silenciosamente do ponto de vista do usuário (o convite é criado, mas o toast de erro pode passar despercebido). E mesmo com a chave configurada, o Resend tem uma pegadinha comum: **enquanto você usa o remetente de teste (`onboarding@resend.dev`), só é possível enviar e-mails para o próprio e-mail que criou a conta Resend** — para qualquer outro destinatário, o envio é bloqueado até você verificar um domínio próprio.

## Como resolver de vez

1. Crie uma conta em [resend.com](https://resend.com) (grátis até 3.000 e-mails/mês).
2. Em **Domains**, adicione e verifique um domínio seu (ex.: `seudominio.com.br`) — são só registros DNS, o Resend guia o processo. Sem isso, o envio só funciona pro seu próprio e-mail de teste.
3. Em **API Keys**, copie a chave.
4. No Supabase, em **Project Settings → Edge Functions → Secrets**, defina `RESEND_API_KEY`, `RESEND_FROM` (algo como `Odômetro Escolar <convites@seudominio.com.br>`) e `SITE_URL`.
5. Teste convidando alguém — o e-mail deve chegar em segundos.

Enquanto isso não estiver pronto, use o botão **Copiar link** — funciona sem depender de nada disso.

## Bônus: também vale configurar SMTP próprio no Supabase Auth

O e-mail de "criar minha senha" (depois que a pessoa clica no link do convite) e o e-mail do administrador com aceite automático são enviados pelo **Supabase Auth**, não pelo Resend. O Supabase usa um serviço de e-mail próprio com limite baixo (poucos e-mails por hora) — para produção de verdade, o recomendado é configurar um SMTP próprio em **Project Settings → Auth → SMTP Settings**, e dá pra usar a mesma conta Resend de cima como servidor SMTP. Isso deixa a entrega de todos os e-mails do sistema mais confiável de uma vez só.

## Um passo manual necessário para o administrador com aceite automático

O link do e-mail de convite do Supabase só funciona se a URL do site estiver na lista de redirecionamentos permitidos. Confira em **Authentication → URL Configuration → Redirect URLs** no painel do Supabase se `https://SEU-USUARIO.github.io/odometro` (ou `https://SEU-USUARIO.github.io/odometro/*`) está cadastrado. Se não estiver, adicione — sem isso, a pessoa convidada recebe um erro ao clicar no link em vez de entrar automaticamente.

## O que mudou no administrador

Antes, adicionar um administrador passava pelo mesmo fluxo de convite por e-mail dos outros papéis. Agora:

- Ao cadastrar um **administrador** (Equipe → Convidar → papel "Administrador"), o acesso é criado e liberado **na hora**, sem token nem espera.
- A pessoa recebe o e-mail de convite nativo do Supabase; ao clicar no link, ela já entra logada.
- Na primeira vez que acessa, o sistema pede pra ela **criar a própria senha** antes de liberar o resto do app.
- Coordenador e funcionário continuam exatamente como antes (convite por token + e-mail via Resend, ou o link copiado manualmente).
