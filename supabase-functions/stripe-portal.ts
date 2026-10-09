// ODÔMETRO · Edge Function: stripe-portal
// Chamada pelo admin da empresa para abrir o Portal de Cobrança do Stripe
// (trocar cartão, ver faturas, cancelar). Usa o mesmo segredo STRIPE_SECRET_KEY.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY")!;
const SITE_URL = Deno.env.get("SITE_URL") ?? "https://wonderful-maamoul-3fa924.netlify.app";

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

    const { data: perfil, error: perfilErr } = await supabase
      .from("perfis").select("papel, empresa_id").eq("id", userData.user.id).maybeSingle();
    if (perfilErr || !perfil) throw new Error("Perfil não encontrado.");
    if (perfil.papel !== "administrador") throw new Error("Só o administrador pode gerenciar a assinatura.");

    const { data: empresa, error: empresaErr } = await supabase
      .from("empresas").select("stripe_customer_id").eq("id", perfil.empresa_id).maybeSingle();
    if (empresaErr || !empresa?.stripe_customer_id) throw new Error("Esta empresa ainda não tem assinatura iniciada.");

    const session = await stripeApi("billing_portal/sessions", {
      customer: empresa.stripe_customer_id,
      return_url: `${SITE_URL}/`,
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
