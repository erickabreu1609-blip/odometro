-- ═══════════════════════════════════════════════════════════════════════
-- ODÔMETRO · Schema do banco (Supabase / PostgreSQL) — versão SaaS (multi-empresa)
-- Execute este arquivo inteiro em: Supabase → SQL Editor → New query → Run
-- Use este arquivo apenas para um projeto NOVO, começando do zero.
-- Se você já tem um projeto rodando, use migracao_saas.sql em vez deste.
-- ═══════════════════════════════════════════════════════════════════════

create extension if not exists pgcrypto;

-- ─────────────────────────── 1. EMPRESAS (cada cliente do SaaS) ───────────
-- "codigo" é um identificador curto e digitável (ex.: "VANSJOAO"), usado
-- pelo motorista para montar o próprio login junto da matrícula, já que
-- ele não usa e-mail real. Os campos de Stripe ficam prontos aqui desde
-- já, mesmo que a cobrança automática só seja ligada numa etapa seguinte.
create table empresas (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  codigo text not null unique,
  criado_em timestamptz not null default now(),
  trial_termina_em timestamptz default (now() + interval '14 days'),
  status_assinatura text not null default 'trial' check (status_assinatura in ('trial','ativa','atrasada','cancelada')),
  plano text default 'padrao',
  stripe_customer_id text unique,
  stripe_subscription_id text unique
);

-- ─────────────────────────── 2. PAPÉIS DE ACESSO ─────────────────────────
create type papel_usuario as enum ('administrador','coordenador','funcionario');

-- ─────────────────────────── 3. MOTORISTAS ────────────────────────────────
create table motoristas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  nome text not null,
  telefone text,
  cnh text,
  validade_cnh date,
  curso_escolar boolean not null default false,
  matricula text,                                          -- único DENTRO da empresa (ver constraint abaixo)
  perfil_id uuid unique references auth.users(id) on delete set null,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  unique (empresa_id, matricula)
);

-- ─────────────────────────── 4. PERFIS (todo usuário autenticado) ────────
create table perfis (
  id uuid primary key references auth.users(id) on delete cascade,
  empresa_id uuid not null references empresas(id) on delete cascade,
  nome_completo text not null,
  papel papel_usuario not null default 'funcionario',
  cargo text,
  salario numeric(10,2),
  telefone text,
  motorista_id uuid unique references motoristas(id) on delete set null,
  ativo boolean not null default true,
  criado_em timestamptz not null default now()
);

-- ─────────────────────────── 5. CONVITES (onboarding sem chave sensível) ─
create table convites (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  email text not null unique,
  nome_completo text not null,
  papel papel_usuario not null,
  cargo text,
  salario numeric(10,2),
  telefone text,
  motorista_id uuid references motoristas(id) on delete set null,
  usado boolean not null default false,
  criado_por uuid references auth.users(id),
  criado_em timestamptz not null default now()
);

-- ─────────────────────────── 6. VEÍCULOS ──────────────────────────────────
create table veiculos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  placa text not null,
  modelo text,
  ano int,
  capacidade int,
  km_atual numeric(10,1) default 0,
  consumo_medio numeric(6,2),
  motorista_id uuid references motoristas(id) on delete set null,
  parcela numeric(10,2) default 0,
  km_troca_oleo numeric(10,1), interv_oleo numeric(10,1) default 10000,
  km_troca_pneus numeric(10,1), interv_pneus numeric(10,1) default 50000,
  km_troca_freio numeric(10,1), interv_freio numeric(10,1) default 25000,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  unique (empresa_id, placa)
);

-- ─────────────────────────── 7. QUILOMETRAGEM ─────────────────────────────
create table kms (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  veiculo_id uuid not null references veiculos(id) on delete cascade,
  data date not null,
  turno text check (turno in ('manhã','tarde','noite')),
  km numeric(10,1) not null,
  observacao text,
  registrado_por uuid references auth.users(id),
  criado_em timestamptz not null default now()
);
create index idx_kms_veiculo_data on kms(veiculo_id, data);
create index idx_kms_empresa on kms(empresa_id);

-- ─────────────────────────── 8. APONTAMENTO DE HORAS ──────────────────────
create table apontamentos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  motorista_id uuid not null references motoristas(id) on delete cascade,
  data date not null,
  turno text not null default 'manhã' check (turno in ('manhã','tarde','noite','extra')),
  entrada timestamptz,
  saida timestamptz,
  origem text not null default 'manual' check (origem in ('ponto','manual')),
  editado boolean not null default false,
  observacao text,
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create index idx_apontamentos_motorista_data on apontamentos(motorista_id, data);

-- ─────────────────────────── 9. ROTAS ──────────────────────────────────────
create table rotas (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  nome text not null,
  turno text not null default 'manhã' check (turno in ('manhã','tarde','noite')),
  veiculo_id uuid references veiculos(id) on delete set null,
  km_dia numeric(10,1) default 0,
  dias_mes int default 22,
  dist_media numeric(10,1),
  bairros text,
  criado_em timestamptz not null default now()
);

-- ─────────────────────────── 10. ALUNOS ────────────────────────────────────
create table alunos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  nome text not null,
  escola text,
  responsavel text,
  telefone text,
  rota_id uuid references rotas(id) on delete set null,
  turno text check (turno in ('manhã','tarde','noite')),
  mensalidade numeric(10,2) default 0,
  dia_vencimento int default 10,
  distancia_km numeric(10,1),
  data_matricula date,
  endereco text,
  ativo boolean not null default true,
  criado_em timestamptz not null default now()
);
create index idx_alunos_rota on alunos(rota_id);

-- ─────────────────────────── 11. LANÇAMENTOS FINANCEIROS ──────────────────
create table lancamentos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  tipo text not null check (tipo in ('receita','despesa')),
  data date not null,
  descricao text not null,
  categoria text not null,
  valor numeric(10,2) not null,
  veiculo_id uuid references veiculos(id) on delete set null,
  rota_id uuid references rotas(id) on delete set null,
  natureza text check (natureza in ('fixo','variavel')),
  litros numeric(10,2) default 0,
  anexo_path text,
  origem text default 'manual',
  hash text,
  fitid text,
  pagamento_id uuid,
  criado_por uuid references auth.users(id),
  criado_em timestamptz not null default now()
);
create index idx_lancamentos_data on lancamentos(data);
create index idx_lancamentos_veiculo on lancamentos(veiculo_id);
create index idx_lancamentos_hash on lancamentos(hash);
create index idx_lancamentos_empresa on lancamentos(empresa_id);

-- ─────────────────────────── 12. MENSALIDADES (PARCELAS) ──────────────────
create table pagamentos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  aluno_id uuid not null references alunos(id) on delete cascade,
  competencia text not null,
  valor numeric(10,2) not null,
  vencimento date not null,
  status text not null default 'aberto' check (status in ('aberto','pago')),
  data_pagamento date,
  criado_em timestamptz not null default now()
);
create index idx_pagamentos_aluno on pagamentos(aluno_id);
create index idx_pagamentos_competencia on pagamentos(competencia);

-- ─────────────────────────── 13. REGRAS DE CATEGORIZAÇÃO APRENDIDAS ───────
create table regras (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  termos text[] not null,
  tipo text not null check (tipo in ('receita','despesa')),
  categoria text not null,
  criado_em timestamptz not null default now()
);

-- ═══════════════════════════ FUNÇÕES AUXILIARES ═══════════════════════════
create or replace function minha_empresa()
returns uuid
language sql stable security definer set search_path = public as $$
  select empresa_id from perfis where id = auth.uid();
$$;

create or replace function papel_atual()
returns papel_usuario
language sql stable security definer set search_path = public as $$
  select papel from perfis where id = auth.uid();
$$;

create or replace function motorista_atual()
returns uuid
language sql stable security definer set search_path = public as $$
  select motorista_id from perfis where id = auth.uid();
$$;

create or replace function eh_gestor()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(papel_atual() in ('administrador','coordenador'), false);
$$;

create or replace function eh_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(papel_atual() = 'administrador', false);
$$;

-- Pronta para a etapa do Stripe: hoje não é usada em nenhuma política, mas
-- já permite gatear funcionalidades por assinatura quando ligarmos isso.
create or replace function assinatura_ativa()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select status_assinatura in ('ativa','atrasada')
        or (status_assinatura = 'trial' and trial_termina_em > now())
    from empresas where id = minha_empresa()
  ), false);
$$;

-- ═══════════════ PREENCHIMENTO AUTOMÁTICO DE empresa_id ═══════════════════
-- Evita ter que alterar cada tela que já existe: todo INSERT novo recebe a
-- empresa da pessoa logada automaticamente, sem o front-end precisar saber
-- disso. NÃO se aplica à tabela "perfis" (ver observação na função de
-- onboarding abaixo — geraria referência circular).
create or replace function preencher_empresa_id()
returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.empresa_id is null then
    new.empresa_id := minha_empresa();
  end if;
  if new.empresa_id is null then
    raise exception 'Não foi possível determinar a empresa deste registro.';
  end if;
  return new;
end;
$$;

create trigger empresa_motoristas    before insert on motoristas    for each row execute function preencher_empresa_id();
create trigger empresa_veiculos      before insert on veiculos      for each row execute function preencher_empresa_id();
create trigger empresa_kms           before insert on kms           for each row execute function preencher_empresa_id();
create trigger empresa_apontamentos  before insert on apontamentos  for each row execute function preencher_empresa_id();
create trigger empresa_rotas         before insert on rotas         for each row execute function preencher_empresa_id();
create trigger empresa_alunos        before insert on alunos        for each row execute function preencher_empresa_id();
create trigger empresa_lancamentos   before insert on lancamentos   for each row execute function preencher_empresa_id();
create trigger empresa_pagamentos    before insert on pagamentos    for each row execute function preencher_empresa_id();
create trigger empresa_regras        before insert on regras        for each row execute function preencher_empresa_id();
create trigger empresa_convites      before insert on convites      for each row execute function preencher_empresa_id();

-- ═══════════════════════ GATILHO DE ONBOARDING ════════════════════════════
-- Continua servindo para QUEM JÁ TEM convite (equipe existente convidando
-- alguém, ou motorista fazendo "criar minha senha"). Quem está criando uma
-- EMPRESA NOVA não passa por aqui — usa criar_empresa_e_admin() abaixo.
create or replace function lidar_novo_usuario()
returns trigger
language plpgsql security definer set search_path = public as $$
declare c convites%rowtype;
begin
  select * into c from convites where email = new.email and usado = false limit 1;
  if found then
    insert into perfis (id, empresa_id, nome_completo, papel, cargo, salario, telefone, motorista_id)
    values (new.id, c.empresa_id, c.nome_completo, c.papel, c.cargo, c.salario, c.telefone, c.motorista_id);
    update convites set usado = true where id = c.id;
    if c.motorista_id is not null then
      update motoristas set perfil_id = new.id where id = c.motorista_id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists ao_criar_usuario on auth.users;
create trigger ao_criar_usuario
  after insert on auth.users
  for each row execute function lidar_novo_usuario();

-- ═══════════════ CRIAR EMPRESA NOVA (self-signup do primeiro admin) ═══════
-- Chamada pelo front-end logo depois de supabase.auth.signUp(), só no
-- fluxo "Criar minha empresa" (não no fluxo de convite/matrícula).
create or replace function criar_empresa_e_admin(p_nome_empresa text, p_nome_pessoa text, p_codigo text)
returns empresas
language plpgsql security definer set search_path = public as $$
declare v_empresa empresas%rowtype;
begin
  if exists (select 1 from perfis where id = auth.uid()) then
    raise exception 'Esta conta já está vinculada a uma empresa.';
  end if;
  insert into empresas (nome, codigo) values (p_nome_empresa, lower(p_codigo))
    returning * into v_empresa;
  insert into perfis (id, empresa_id, nome_completo, papel)
    values (auth.uid(), v_empresa.id, p_nome_pessoa, 'administrador');
  return v_empresa;
end;
$$;

-- Mantém atualizado_em em dia nos apontamentos e força editado=true
-- sempre que entrada/saída mudam depois de criado.
create or replace function marcar_apontamento_editado()
returns trigger language plpgsql as $$
begin
  new.atualizado_em := now();
  if (old.entrada is distinct from new.entrada) or (old.saida is distinct from new.saida) then
    new.editado := true;
  end if;
  return new;
end;
$$;
create trigger antes_atualizar_apontamento
  before update on apontamentos
  for each row execute function marcar_apontamento_editado();

-- ═══════════════════════ BATER PONTO (RPC) ════════════════════════════════
create or replace function bater_ponto(p_turno text)
returns apontamentos
language plpgsql security definer set search_path = public as $$
declare
  v_motorista uuid := motorista_atual();
  v_registro apontamentos%rowtype;
begin
  if v_motorista is null then
    raise exception 'Esta conta não está vinculada a um motorista.';
  end if;
  select * into v_registro from apontamentos
    where motorista_id = v_motorista and data = current_date and turno = p_turno
    order by criado_em desc limit 1;
  if found and v_registro.saida is null then
    update apontamentos set saida = now()
      where id = v_registro.id returning * into v_registro;
  else
    insert into apontamentos (motorista_id, data, turno, entrada, origem)
      values (v_motorista, current_date, p_turno, now(), 'ponto')
      returning * into v_registro;
  end if;
  return v_registro;
end;
$$;

-- ═══════════════════════════════ RLS ═══════════════════════════════════════
-- Toda política agora exige "empresa_id = minha_empresa()" ALÉM da regra de
-- papel — isso é o que garante que uma empresa nunca veja dado de outra.
alter table empresas      enable row level security;
alter table perfis        enable row level security;
alter table motoristas    enable row level security;
alter table convites      enable row level security;
alter table veiculos      enable row level security;
alter table kms           enable row level security;
alter table apontamentos  enable row level security;
alter table rotas         enable row level security;
alter table alunos        enable row level security;
alter table lancamentos   enable row level security;
alter table pagamentos    enable row level security;
alter table regras        enable row level security;

-- EMPRESAS: só a própria empresa é visível; ninguém edita direto (isso
-- acontece via RPC/webhook do Stripe, com privilégio elevado).
create policy "empresas_select_propria" on empresas for select using (id = minha_empresa());

-- PERFIS
create policy "perfis_select_mesma_empresa" on perfis for select using (
  auth.uid() is not null and empresa_id = minha_empresa()
);
create policy "perfis_update_gestores" on perfis for update using (
  empresa_id = minha_empresa() and (eh_admin() or (papel_atual() = 'coordenador' and papel = 'funcionario'))
) with check (
  empresa_id = minha_empresa() and (eh_admin() or (papel_atual() = 'coordenador' and papel = 'funcionario'))
);
create policy "perfis_delete_admin" on perfis for delete using (
  empresa_id = minha_empresa() and eh_admin()
);

-- MOTORISTAS
create policy "motoristas_select_mesma_empresa" on motoristas for select using (
  auth.uid() is not null and empresa_id = minha_empresa()
);
create policy "motoristas_insert_gestores" on motoristas for insert with check (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "motoristas_update_gestores" on motoristas for update using (
  empresa_id = minha_empresa() and eh_gestor()
) with check (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "motoristas_delete_admin" on motoristas for delete using (
  empresa_id = minha_empresa() and eh_admin()
);

-- CONVITES
create policy "convites_select_gestores" on convites for select using (
  empresa_id = minha_empresa() and (eh_admin() or (papel_atual() = 'coordenador' and papel = 'funcionario'))
);
create policy "convites_insert_regra" on convites for insert with check (
  empresa_id = minha_empresa() and (eh_admin() or (papel_atual() = 'coordenador' and papel = 'funcionario'))
);
create policy "convites_delete_gestores" on convites for delete using (
  empresa_id = minha_empresa() and (eh_admin() or (papel_atual() = 'coordenador' and papel = 'funcionario'))
);

-- VEÍCULOS
create policy "veiculos_select_mesma_empresa" on veiculos for select using (
  auth.uid() is not null and empresa_id = minha_empresa()
);
create policy "veiculos_insert_gestores" on veiculos for insert with check (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "veiculos_update_gestores" on veiculos for update using (
  empresa_id = minha_empresa() and eh_gestor()
) with check (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "veiculos_delete_admin" on veiculos for delete using (
  empresa_id = minha_empresa() and eh_admin()
);

-- KM
create policy "kms_select_mesma_empresa" on kms for select using (
  auth.uid() is not null and empresa_id = minha_empresa()
);
create policy "kms_insert_gestores" on kms for insert with check (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "kms_update_gestores" on kms for update using (
  empresa_id = minha_empresa() and eh_gestor()
) with check (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "kms_delete_gestores" on kms for delete using (
  empresa_id = minha_empresa() and eh_gestor()
);

-- APONTAMENTOS
create policy "apontamentos_select" on apontamentos for select using (
  empresa_id = minha_empresa() and (eh_gestor() or motorista_id = motorista_atual())
);
create policy "apontamentos_insert" on apontamentos for insert with check (
  empresa_id = minha_empresa() and (eh_gestor() or motorista_id = motorista_atual())
);
create policy "apontamentos_update" on apontamentos for update using (
  empresa_id = minha_empresa() and (eh_gestor() or motorista_id = motorista_atual())
) with check (
  empresa_id = minha_empresa() and (eh_gestor() or motorista_id = motorista_atual())
);
create policy "apontamentos_delete" on apontamentos for delete using (
  empresa_id = minha_empresa() and eh_gestor()
);

-- ROTAS
create policy "rotas_select_mesma_empresa" on rotas for select using (
  auth.uid() is not null and empresa_id = minha_empresa()
);
create policy "rotas_insert_gestores" on rotas for insert with check (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "rotas_update_gestores" on rotas for update using (
  empresa_id = minha_empresa() and eh_gestor()
) with check (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "rotas_delete_admin" on rotas for delete using (
  empresa_id = minha_empresa() and eh_admin()
);

-- ALUNOS (só gestores, como antes — agora também isolado por empresa)
create policy "alunos_select_gestores" on alunos for select using (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "alunos_insert_gestores" on alunos for insert with check (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "alunos_update_gestores" on alunos for update using (
  empresa_id = minha_empresa() and eh_gestor()
) with check (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "alunos_delete_admin" on alunos for delete using (
  empresa_id = minha_empresa() and eh_admin()
);

-- LANÇAMENTOS FINANCEIROS
create policy "lancamentos_select_gestores" on lancamentos for select using (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "lancamentos_insert_gestores" on lancamentos for insert with check (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "lancamentos_update_gestores" on lancamentos for update using (
  empresa_id = minha_empresa() and eh_gestor()
) with check (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "lancamentos_delete_admin" on lancamentos for delete using (
  empresa_id = minha_empresa() and eh_admin()
);

-- PAGAMENTOS (mensalidades)
create policy "pagamentos_select_gestores" on pagamentos for select using (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "pagamentos_insert_gestores" on pagamentos for insert with check (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "pagamentos_update_gestores" on pagamentos for update using (
  empresa_id = minha_empresa() and eh_gestor()
) with check (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "pagamentos_delete_admin" on pagamentos for delete using (
  empresa_id = minha_empresa() and eh_admin()
);

-- REGRAS
create policy "regras_select_gestores" on regras for select using (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "regras_insert_gestores" on regras for insert with check (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "regras_delete_gestores" on regras for delete using (
  empresa_id = minha_empresa() and eh_gestor()
);

-- ═══════════════ ARMAZENAMENTO DE COMPROVANTES (Supabase Storage) ═════════
-- Caminho do arquivo agora começa com o id da empresa (ex.: "8f2a.../user/arquivo.png"),
-- e a política usa isso para isolar quem pode ver o quê.
insert into storage.buckets (id, name, public)
values ('anexos', 'anexos', false)
on conflict (id) do nothing;

create policy "anexos_select_gestores" on storage.objects for select using (
  bucket_id = 'anexos' and eh_gestor() and (storage.foldername(name))[1] = minha_empresa()::text
);
create policy "anexos_insert_gestores" on storage.objects for insert with check (
  bucket_id = 'anexos' and eh_gestor() and (storage.foldername(name))[1] = minha_empresa()::text
);
create policy "anexos_delete_gestores" on storage.objects for delete using (
  bucket_id = 'anexos' and eh_gestor() and (storage.foldername(name))[1] = minha_empresa()::text
);

-- ═══════════════════════════════ PRONTO ════════════════════════════════════
-- Não existe mais "bootstrap manual do primeiro admin" — toda empresa nova
-- (inclusive a primeira) se cria sozinha pela tela "Criar minha empresa" do
-- site, que chama supabase.auth.signUp() e depois criar_empresa_e_admin().
