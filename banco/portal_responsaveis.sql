-- ═══════════════════════════════════════════════════════════════════════
-- ODÔMETRO · PORTAL DOS RESPONSÁVEIS — rode depois de migracao_saas.sql e
-- stripe_billing.sql. Cria o papel "responsável" (pai/mãe/guardião), com
-- acesso só ao(s) próprio(s) filho(s) — nunca aos dados de outras famílias
-- nem aos dados internos da empresa (motoristas, financeiro etc).
--
-- Também cria a tabela de localização ao vivo dos veículos (pro
-- rastreamento) e prepara as colunas de Stripe Connect (próxima etapa).
-- ═══════════════════════════════════════════════════════════════════════

-- ─────────────────────────── 1. RESPONSÁVEIS ────────────────────────────
create table if not exists responsaveis (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  nome text not null,
  telefone text,
  email_contato text,
  email_login text not null,
  matricula text not null,
  perfil_id uuid unique references auth.users(id) on delete set null,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  unique (empresa_id, matricula),
  unique (email_login)
);

alter table alunos add column if not exists responsavel_id uuid references responsaveis(id) on delete set null;

create or replace function responsavel_atual()
returns uuid
language sql stable security definer set search_path = public as $$
  select id from responsaveis where perfil_id = auth.uid();
$$;

create or replace function empresa_do_responsavel()
returns uuid
language sql stable security definer set search_path = public as $$
  select empresa_id from responsaveis where perfil_id = auth.uid();
$$;

drop trigger if exists empresa_responsaveis on responsaveis;
create trigger empresa_responsaveis before insert on responsaveis for each row execute function preencher_empresa_id();

alter table responsaveis enable row level security;
drop policy if exists "responsaveis_select" on responsaveis;
drop policy if exists "responsaveis_insert_gestores" on responsaveis;
drop policy if exists "responsaveis_update" on responsaveis;
drop policy if exists "responsaveis_delete_admin" on responsaveis;
create policy "responsaveis_select" on responsaveis for select using (
  (empresa_id = minha_empresa() and eh_gestor()) or perfil_id = auth.uid()
);
create policy "responsaveis_insert_gestores" on responsaveis for insert with check (
  empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa() and meu_plano() = 'ilimitado'
);
create policy "responsaveis_update" on responsaveis for update using (
  (empresa_id = minha_empresa() and eh_gestor()) or perfil_id = auth.uid()
) with check (
  (empresa_id = minha_empresa() and eh_gestor()) or perfil_id = auth.uid()
);
create policy "responsaveis_delete_admin" on responsaveis for delete using (empresa_id = minha_empresa() and eh_admin());

-- ─────────────────────────── 2. ONBOARDING: RECONHECER RESPONSÁVEL ─────
-- Estende o gatilho de novo usuário: se o e-mail não bate com nenhum
-- convite de equipe/motorista, tenta achar um responsável esperando.
create or replace function lidar_novo_usuario()
returns trigger
language plpgsql security definer set search_path = public as $$
declare c convites%rowtype; r_id uuid;
begin
  select * into c from convites where email = new.email and usado = false limit 1;
  if found then
    insert into perfis (id, empresa_id, nome_completo, papel, cargo, salario, telefone, motorista_id)
    values (new.id, c.empresa_id, c.nome_completo, c.papel, c.cargo, c.salario, c.telefone, c.motorista_id);
    update convites set usado = true where id = c.id;
    if c.motorista_id is not null then
      update motoristas set perfil_id = new.id where id = c.motorista_id;
    end if;
    return new;
  end if;

  select id into r_id from responsaveis where email_login = new.email and perfil_id is null limit 1;
  if r_id is not null then
    update responsaveis set perfil_id = new.id where id = r_id;
  end if;
  return new;
end;
$$;

-- ─────────────────────────── 3. ALUNOS: só o(s) próprio(s) filho(s) ────
drop policy if exists "alunos_select_gestores" on alunos;
create policy "alunos_select_gestores" on alunos for select using (
  (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa() and meu_plano() = 'ilimitado')
  or (responsavel_id = responsavel_atual())
);

-- ─────────────────────────── 4. PAGAMENTOS: só do(s) próprio(s) filho(s) ─
drop policy if exists "pagamentos_select_gestores" on pagamentos;
create policy "pagamentos_select_gestores" on pagamentos for select using (
  (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa() and meu_plano() = 'ilimitado')
  or (aluno_id in (select id from alunos where responsavel_id = responsavel_atual()))
);

-- ─────────────────────────── 5. ROTAS: só a do(s) próprio(s) filho(s) ──
drop policy if exists "rotas_select_mesma_empresa" on rotas;
create policy "rotas_select_mesma_empresa" on rotas for select using (
  (auth.uid() is not null and empresa_id = minha_empresa() and assinatura_ativa() and meu_plano() = 'ilimitado')
  or (id in (select rota_id from alunos where responsavel_id = responsavel_atual()))
);

-- ─────────────────────────── 6. VEÍCULOS: só o da rota do(s) filho(s) ──
drop policy if exists "veiculos_select_mesma_empresa" on veiculos;
create policy "veiculos_select_mesma_empresa" on veiculos for select using (
  (auth.uid() is not null and empresa_id = minha_empresa() and assinatura_ativa())
  or (id in (select veiculo_id from rotas where id in (select rota_id from alunos where responsavel_id = responsavel_atual())))
);

-- ─────────────────────────── 7. LOCALIZAÇÃO AO VIVO ─────────────────────
create table if not exists localizacoes_veiculo (
  veiculo_id uuid primary key references veiculos(id) on delete cascade,
  empresa_id uuid not null references empresas(id) on delete cascade,
  motorista_id uuid references motoristas(id) on delete set null,
  rota_id uuid references rotas(id) on delete set null,
  lat double precision not null,
  lng double precision not null,
  precisao numeric,
  compartilhando boolean not null default true,
  atualizado_em timestamptz not null default now()
);

drop trigger if exists empresa_localizacoes on localizacoes_veiculo;
create trigger empresa_localizacoes before insert on localizacoes_veiculo for each row execute function preencher_empresa_id();

alter table localizacoes_veiculo enable row level security;
drop policy if exists "localizacoes_select" on localizacoes_veiculo;
drop policy if exists "localizacoes_insert" on localizacoes_veiculo;
drop policy if exists "localizacoes_update" on localizacoes_veiculo;
drop policy if exists "localizacoes_delete" on localizacoes_veiculo;
create policy "localizacoes_select" on localizacoes_veiculo for select using (
  (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa())
  or (motorista_id = motorista_atual())
  or (compartilhando and veiculo_id in (select veiculo_id from rotas where id in (select rota_id from alunos where responsavel_id = responsavel_atual())))
);
create policy "localizacoes_insert" on localizacoes_veiculo for insert with check (
  motorista_id = motorista_atual() and assinatura_ativa()
);
create policy "localizacoes_update" on localizacoes_veiculo for update using (
  motorista_id = motorista_atual()
) with check (
  motorista_id = motorista_atual()
);
create policy "localizacoes_delete" on localizacoes_veiculo for delete using (motorista_id = motorista_atual());

alter publication supabase_realtime add table localizacoes_veiculo;

-- ─────────────────────────── 8. STRIPE CONNECT (preparação) ────────────
alter table empresas add column if not exists stripe_connect_account_id text unique;
alter table empresas add column if not exists stripe_connect_ativo boolean not null default false;

-- ═══════════════════════════════ PRONTO ═════════════════════════════════
select 'portal_responsaveis aplicado' as status;
