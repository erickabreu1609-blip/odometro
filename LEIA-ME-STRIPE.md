# ODÔMETRO — cobrança via Stripe

## O que eu já fiz (não precisa mexer)

- **Banco de dados**: rodei `stripe_billing.sql` no seu Supabase. Isso ligou o bloqueio de verdade por assinatura (trial vencido/pagamento atrasado passam a travar o acesso no banco, não só na tela) e criou 3 planos: **Básico** (equipe/frota), **Pro** (+ financeiro) e **Ilimitado** (+ transporte escolar). Sua empresa já está em "ilimitado/ativa" para não travar seus testes.
- **3 Edge Functions publicadas** no seu projeto Supabase (`lkelzwpeopwnqubnflkt`):
  - `stripe-checkout` — cria a sessão de pagamento quando o admin escolhe um plano.
  - `stripe-portal` — abre o portal do Stripe (trocar cartão, ver faturas, cancelar).
  - `stripe-webhook` — recebe os avisos do Stripe e atualiza o status da empresa automaticamente.
- **`index.html`**: tela de "assinatura pendente", aviso de trial acabando e botão "Assinatura" no menu já estão no ar.

Falta só a configuração do lado do Stripe — são só cliques, nenhuma linha de código.

## Passo 1 — Criar a conta

Crie em [dashboard.stripe.com/register](https://dashboard.stripe.com/register). Fique em **modo Teste** (chave no canto superior direito, "Test mode") até terminarmos de testar tudo — só depois ativamos modo produção.

## Passo 2 — Criar os 3 produtos e preços

Em **Product catalog → Add product**, crie três produtos, cada um com um preço **recorrente mensal em BRL**:

| Produto | Preço sugerido |
|---|---|
| Odômetro — Básico | R$ 79,00/mês |
| Odômetro — Pro | R$ 149,00/mês |
| Odômetro — Ilimitado | R$ 249,00/mês |

(Valores fáceis de trocar depois no próprio Stripe, sem mexer em código.)

Depois de criar cada um, copie o **Price ID** dele (começa com `price_...`, fica na página do produto).

## Passo 3 — Criar o webhook

Em **Developers → Webhooks → Add endpoint**:

- **URL**: `https://lkelzwpeopwnqubnflkt.supabase.co/functions/v1/stripe-webhook`
- **Eventos**: `checkout.session.completed`, `customer.subscription.created`, `customer.subscription.updated`, `customer.subscription.deleted`, `invoice.payment_failed`

Depois de criar, copie o **Signing secret** (`whsec_...`).

## Passo 4 — Copiar a chave secreta

Em **Developers → API keys**, copie a **Secret key** (`sk_test_...` em modo teste).

## Passo 5 — Configurar no Supabase

No painel do Supabase do projeto: **Project Settings → Edge Functions → Secrets**, adicione:

| Nome | Valor |
|---|---|
| `STRIPE_SECRET_KEY` | a secret key do Passo 4 |
| `STRIPE_WEBHOOK_SECRET` | o signing secret do Passo 3 |
| `STRIPE_PRICE_BASICO` | price ID do plano Básico |
| `STRIPE_PRICE_PRO` | price ID do plano Pro |
| `STRIPE_PRICE_ILIMITADO` | price ID do plano Ilimitado |
| `SITE_URL` | `https://SEU-USUARIO.github.io/odometro` |

Esses valores ficam só no Supabase — nunca precisam passar por mim nem pelo site.

## Passo 6 — Testar

Ainda em modo Teste, crie uma empresa nova no site e clique em "Assinar" num plano. No checkout do Stripe, use o cartão de teste `4242 4242 4242 4242`, validade e CVC quaisquer. Confira se o status da empresa vira "ativa" e se o módulo do plano escolhido aparece no menu.

Quando tudo funcionar em modo teste, é só trocar `STRIPE_SECRET_KEY` e `STRIPE_WEBHOOK_SECRET` pelas versões de produção (`sk_live_...` / webhook criado em modo produção) e criar os mesmos 3 produtos lá.

## Me avise quando…

Terminar os passos 1 a 5. Eu confiro se está tudo certo e testo o fluxo de ponta a ponta com você (ou, se preferir, você pode conectar o conector do Stripe aqui na conversa depois de criar a conta, e eu crio os produtos e o webhook direto por lá — só os passos 4 e 5 continuam manuais, porque as chaves não passam por mim).
