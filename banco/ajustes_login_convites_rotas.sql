-- ═══════════════════════════════════════════════════════════════════════
-- ODÔMETRO · AJUSTES: administrador com aceite automático, login por
-- telefone e registro de início/fim de rota do motorista.
-- Rode depois de migracao_saas.sql, stripe_billing.sql e
-- portal_responsaveis.sql (usa eh_admin(), eh_gestor(), minha_empresa(),
-- motorista_atual(), preencher_empresa_id() já criados antes).
-- ═══════════════════════════════════════════════════════════════════════

-- ─────────────────────── 1. ADMINISTRADOR: ACEITE AUTOMÁTICO ────────────
-- Coluna que marca se a pessoa já escolheu a própria senha. Todo mundo que
-- passa pelo fluxo normal (convite por e-mail ou matrícula) já cria a senha
-- no ato, então nasce com true. Só o administrador criado pelo fluxo rápido
-- (edge function convidar-admin) nasce com false, e a tela pede a senha
-- assim que ele entra pela primeira vez.
alter table perfis add column if not exists senha_definida boolean not null default true;

create or replace function marcar_senha_definida()
returns void
language sql security definer set search_path = public as $$
  update perfis set senha_definida = true where id = auth.uid();
$$;
grant execute on function marcar_senha_definida() to authenticated;

-- ─────────────────────── 2. LOGIN POR E-MAIL OU TELEFONE ────────────────
-- Função pública (chamada antes do login, por isso "to anon") que recebe o
-- que a pessoa digitou e devolve o e-mail de login correspondente, se achar
-- um cadastro (administrador/coordenador/funcionário/motorista em `perfis`,
-- motorista em `motoristas`, ou responsável em `responsaveis`) com aquele
-- telefone. Não expõe mais nada além do e-mail — a senha continua sendo
-- validada normalmente pelo Supabase Auth depois.
create or replace function buscar_email_login(p_identificador text)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_digits text;
  v_email text;
begin
  if p_identificador is null or btrim(p_identificador) = '' then
    return null;
  end if;

  if p_identificador ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return lower(btrim(p_identificador));
  end if;

  v_digits := regexp_replace(p_identificador, '\D', '', 'g');
  if length(v_digits) < 8 then
    return null;
  end if;

  select au.email into v_email
    from perfis p join auth.users au on au.id = p.id
    where regexp_replace(coalesce(p.telefone, ''), '\D', '', 'g') = v_digits
    limit 1;
  if v_email is not null then return v_email; end if;

  select au.email into v_email
    from motoristas m join auth.users au on au.id = m.perfil_id
    where regexp_replace(coalesce(m.telefone, ''), '\D', '', 'g') = v_digits
    limit 1;
  if v_email is not null then return v_email; end if;

  select email_login into v_email from responsaveis
    where regexp_replace(coalesce(telefone, ''), '\D', '', 'g') = v_digits
    limit 1;

  return v_email;
end;
$$;
grant execute on function buscar_email_login(text) to anon, authenticated;

-- ─────────────────────── 3. INÍCIO/FIM DE ROTA DO MOTORISTA ─────────────
create table if not exists viagens (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  motorista_id uuid not null references motoristas(id) on delete cascade,
  veiculo_id uuid references veiculos(id) on delete set null,
  rota_id uuid references rotas(id) on delete set null,
  status text not null default 'em_andamento' check (status in ('em_andamento','finalizada')),
  iniciado_em timestamptz not null default now(),
  iniciado_lat double precision,
  iniciado_lng double precision,
  finalizado_em timestamptz,
  finalizado_lat double precision,
  finalizado_lng double precision,
  criado_em timestamptz not null default now()
);

drop trigger if exists empresa_viagens on viagens;
create trigger empresa_viagens before insert on viagens for each row execute function preencher_empresa_id();

alter table viagens enable row level security;
drop policy if exists "viagens_select" on viagens;
drop policy if exists "viagens_insert" on viagens;
drop policy if exists "viagens_update" on viagens;
create policy "viagens_select" on viagens for select using (
  (empresa_id = minha_empresa() and eh_gestor()) or motorista_id = motorista_atual()
);
create policy "viagens_insert" on viagens for insert with check (
  motorista_id = motorista_atual() and assinatura_ativa()
);
create policy "viagens_update" on viagens for update using (
  motorista_id = motorista_atual()
) with check (
  motorista_id = motorista_atual()
);

alter publication supabase_realtime add table viagens;

-- ═══════════════════════════════ PRONTO ═════════════════════════════════
select 'ajustes_login_convites_rotas aplicado' as status;
