// ODÔMETRO · Edge Function: stripe-checkout
// Chamada pelo admin da empresa (frontend) para começar a assinatura de um plano.
// Cria (ou reaproveita) o Customer no Stripe e devolve a URL do Checkout.
//
// Secrets necessários (Project Settings → Edge Functions → Secrets):
//   STRIPE_SECRET_KEY, STRIPE_PRICE_BASICO, STRIPE_PRICE_PRO, STRIPE_PRICE_ILIMITADO, SITE_URL
// (SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY já existem sozinhos.)

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY")!;
const SITE_URL = Deno.env.get("SITE_URL") ?? "https://wonderful-maamoul-3fa924.netlify.app";
const PRECOS: Record<string, string | undefined> = {
  basico: Deno.env.get("STRIPE_PRICE_BASICO"),
  pro: Deno.env.get("STRIPE_PRICE_PRO"),
  ilimitado: Deno.env.get("STRIPE_PRICE_ILIMITADO"),
};

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

async function stripeApi(path: string, body: Record<string, string>) {
  const res = await fetch(`https://api.stripe.com/v1/${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams(body),
  });
  const json = await res.json();
  if (!res.ok) throw new Error(json?.error?.message || "Erro no Stripe");
  return json;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );
    const { data: userData, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userData?.user) throw new Error("Não autenticado.");

    const { plano } = await req.json();
    const priceId = PRECOS[plano];
    if (!priceId) throw new Error("Plano inválido ou preço não configurado no servidor.");

    const { data: perfil, error: perfilErr } = await supabase
      .from("perfis").select("papel, empresa_id").eq("id", userData.user.id).maybeSingle();
    if (perfilErr || !perfil) throw new Error("Perfil não encontrado.");
    if (perfil.papel !== "administrador") throw new Error("Só o administrador pode alterar a assinatura.");

    const { data: empresa, error: empresaErr } = await supabase
      .from("empresas").select("*").eq("id", perfil.empresa_id).maybeSingle();
    if (empresaErr || !empresa) throw new Error("Empresa não encontrada.");

    let customerId = empresa.stripe_customer_id as string | null;
    if (!customerId) {
      const customer = await stripeApi("customers", {
        name: empresa.nome,
        "metadata[empresa_id]": empresa.id,
      });
      customerId = customer.id;
      const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
      await admin.from("empresas").update({ stripe_customer_id: customerId }).eq("id", empresa.id);
    }

    const session = await stripeApi("checkout/sessions", {
      mode: "subscription",
      customer: customerId!,
      "line_items[0][price]": priceId,
      "line_items[0][quantity]": "1",
      success_url: `${SITE_URL}/?assinatura=sucesso`,
      cancel_url: `${SITE_URL}/?assinatura=cancelada`,
      client_reference_id: empresa.id,
      "metadata[empresa_id]": empresa.id,
      "metadata[plano]": plano,
      "subscription_data[metadata][empresa_id]": empresa.id,
      "subscription_data[metadata][plano]": plano,
    });

    return new Response(JSON.stringify({ url: session.url }), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 400,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
});
