// ODÔMETRO · Edge Function: stripe-webhook
// Recebe eventos do Stripe direto (sem passar pelo login de ninguém) e
// mantém a tabela `empresas` (status_assinatura, plano, ids do Stripe)
// em sincronia. Esta função tem que ser criada com "verificar JWT" DESLIGADO,
// porque quem chama é o Stripe, não um usuário logado — a segurança aqui
// vem da assinatura HMAC do próprio Stripe (STRIPE_WEBHOOK_SECRET).

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const STRIPE_WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET")!;
const PRECO_PARA_PLANO: Record<string, string> = {};
if (Deno.env.get("STRIPE_PRICE_BASICO")) PRECO_PARA_PLANO[Deno.env.get("STRIPE_PRICE_BASICO")!] = "basico";
if (Deno.env.get("STRIPE_PRICE_PRO")) PRECO_PARA_PLANO[Deno.env.get("STRIPE_PRICE_PRO")!] = "pro";
if (Deno.env.get("STRIPE_PRICE_ILIMITADO")) PRECO_PARA_PLANO[Deno.env.get("STRIPE_PRICE_ILIMITADO")!] = "ilimitado";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

async function verificarAssinatura(payload: string, header: string, secret: string): Promise<boolean> {
  const partes = Object.fromEntries(
    header.split(",").map((p) => p.split("=")) as [string, string][]
  );
  const timestamp = partes["t"];
  const assinaturaEsperada = partes["v1"];
  if (!timestamp || !assinaturaEsperada) return false;
  const dadosAssinados = `${timestamp}.${payload}`;
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  );
  const buf = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(dadosAssinados));
  const calculada = Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
  if (calculada.length !== assinaturaEsperada.length) return false;
  let diff = 0;
  for (let i = 0; i < calculada.length; i++) diff |= calculada.charCodeAt(i) ^ assinaturaEsperada.charCodeAt(i);
  return diff === 0;
}

function statusDoStripe(status: string): string {
  if (status === "active" || status === "trialing") return "ativa";
  if (status === "past_due" || status === "unpaid" || status === "incomplete") return "atrasada";
  return "cancelada"; // canceled, incomplete_expired
}

Deno.serve(async (req) => {
  const payload = await req.text();
  const assinaturaHeader = req.headers.get("stripe-signature") ?? "";
  const valido = await verificarAssinatura(payload, assinaturaHeader, STRIPE_WEBHOOK_SECRET);
  if (!valido) return new Response("Assinatura inválida.", { status: 400 });

  const evento = JSON.parse(payload);

  try {
    switch (evento.type) {
      case "checkout.session.completed": {
        const sessao = evento.data.object;
        const empresaId = sessao.metadata?.empresa_id || sessao.client_reference_id;
        if (empresaId && sessao.subscription) {
          await admin.from("empresas").update({
            stripe_customer_id: sessao.customer,
            stripe_subscription_id: sessao.subscription,
            status_assinatura: "ativa",
            ...(sessao.metadata?.plano ? { plano: sessao.metadata.plano } : {}),
            assinatura_atualizada_em: new Date().toISOString(),
          }).eq("id", empresaId);
        }
        break;
      }
      case "customer.subscription.updated":
      case "customer.subscription.created": {
        const sub = evento.data.object;
        const empresaId = sub.metadata?.empresa_id;
        const priceId = sub.items?.data?.[0]?.price?.id;
        const plano = priceId ? PRECO_PARA_PLANO[priceId] : undefined;
        const filtro = empresaId ? { id: empresaId } : { stripe_subscription_id: sub.id };
        await admin.from("empresas").update({
          status_assinatura: statusDoStripe(sub.status),
          stripe_subscription_id: sub.id,
          ...(plano ? { plano } : {}),
          assinatura_atualizada_em: new Date().toISOString(),
        }).match(filtro);
        break;
      }
      case "customer.subscription.deleted": {
        const sub = evento.data.object;
        const empresaId = sub.metadata?.empresa_id;
        const filtro = empresaId ? { id: empresaId } : { stripe_subscription_id: sub.id };
        await admin.from("empresas").update({
          status_assinatura: "cancelada",
          assinatura_atualizada_em: new Date().toISOString(),
        }).match(filtro);
        break;
      }
      case "invoice.payment_failed": {
        const fatura = evento.data.object;
        if (fatura.subscription) {
          await admin.from("empresas").update({
            status_assinatura: "atrasada",
            assinatura_atualizada_em: new Date().toISOString(),
          }).eq("stripe_subscription_id", fatura.subscription);
        }
        break;
      }
    }
  } catch (e) {
    console.error("Erro processando webhook:", e);
    return new Response("Erro interno", { status: 500 });
  }

  return new Response(JSON.stringify({ received: true }), { headers: { "Content-Type": "application/json" } });
});
