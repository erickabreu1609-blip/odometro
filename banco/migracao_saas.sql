-- ═══════════════════════════════════════════════════════════════════════
-- ODÔMETRO · MIGRAÇÃO PARA SAAS (multi-empresa) — rode no projeto que você
-- já tem. Transforma o sistema de "uma empresa só" para "várias empresas
-- isoladas", preservando todos os dados que já existem (eles viram a
-- primeira empresa automaticamente).
-- ═══════════════════════════════════════════════════════════════════════

-- ─────────────────────────── 1. TABELA DE EMPRESAS ─────────────────────────
create table if not exists empresas (
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

-- ─────────────────────────── 2. EMPRESA PADRÃO (seus dados atuais) ────────
-- Cria uma empresa para representar o que já existe e guarda o id numa
-- tabela temporária só para esta sessão de migração.
create temporary table _migracao_empresa_padrao as
  with nova as (
    insert into empresas (nome, codigo, status_assinatura)
    values ('Minha Empresa', 'padrao' || substr(md5(random()::text), 1, 4), 'ativa')
    returning id
  )
  select id from nova;

-- ─────────────────────────── 3. ADICIONAR empresa_id ÀS TABELAS ───────────
alter table perfis        add column if not exists empresa_id uuid references empresas(id) on delete cascade;
alter table motoristas    add column if not exists empresa_id uuid references empresas(id) on delete cascade;
alter table convites      add column if not exists empresa_id uuid references empresas(id) on delete cascade;
alter table veiculos      add column if not exists empresa_id uuid references empresas(id) on delete cascade;
alter table kms           add column if not exists empresa_id uuid references empresas(id) on delete cascade;
alter table apontamentos  add column if not exists empresa_id uuid references empresas(id) on delete cascade;
alter table rotas         add column if not exists empresa_id uuid references empresas(id) on delete cascade;
alter table alunos        add column if not exists empresa_id uuid references empresas(id) on delete cascade;
alter table lancamentos   add column if not exists empresa_id uuid references empresas(id) on delete cascade;
alter table pagamentos    add column if not exists empresa_id uuid references empresas(id) on delete cascade;
alter table regras        add column if not exists empresa_id uuid references empresas(id) on delete cascade;

-- ─────────────────────────── 4. PREENCHER COM A EMPRESA PADRÃO ────────────
update perfis       set empresa_id = (select id from _migracao_empresa_padrao) where empresa_id is null;
update motoristas   set empresa_id = (select id from _migracao_empresa_padrao) where empresa_id is null;
update convites     set empresa_id = (select id from _migracao_empresa_padrao) where empresa_id is null;
update veiculos     set empresa_id = (select id from _migracao_empresa_padrao) where empresa_id is null;
update kms           set empresa_id = (select id from _migracao_empresa_padrao) where empresa_id is null;
update apontamentos set empresa_id = (select id from _migracao_empresa_padrao) where empresa_id is null;
update rotas         set empresa_id = (select id from _migracao_empresa_padrao) where empresa_id is null;
update alunos        set empresa_id = (select id from _migracao_empresa_padrao) where empresa_id is null;
update lancamentos   set empresa_id = (select id from _migracao_empresa_padrao) where empresa_id is null;
update pagamentos    set empresa_id = (select id from _migracao_empresa_padrao) where empresa_id is null;
update regras        set empresa_id = (select id from _migracao_empresa_padrao) where empresa_id is null;

-- ─────────────────────────── 5. TORNAR OBRIGATÓRIO ─────────────────────────
alter table perfis        alter column empresa_id set not null;
alter table motoristas    alter column empresa_id set not null;
alter table convites      alter column empresa_id set not null;
alter table veiculos      alter column empresa_id set not null;
alter table kms           alter column empresa_id set not null;
alter table apontamentos  alter column empresa_id set not null;
alter table rotas         alter column empresa_id set not null;
alter table alunos        alter column empresa_id set not null;
alter table lancamentos   alter column empresa_id set not null;
alter table pagamentos    alter column empresa_id set not null;
alter table regras        alter column empresa_id set not null;

-- ─────────────────────────── 6. AJUSTAR UNICIDADE (por empresa, não global) ─
-- Placa e matrícula deixam de ser únicas no sistema inteiro e passam a ser
-- únicas só dentro de cada empresa (duas empresas podem ter, cada uma, um
-- veículo de placa parecida usada em teste, por exemplo).
do $$
declare c record;
begin
  for c in select conname from pg_constraint where conrelid='veiculos'::regclass and contype='u'
    and conkey = (select array_agg(attnum) from pg_attribute where attrelid='veiculos'::regclass and attname='placa')
  loop execute format('alter table veiculos drop constraint %I', c.conname); end loop;
end $$;
alter table veiculos add constraint veiculos_empresa_placa_unica unique (empresa_id, placa);

do $$
declare c record;
begin
  for c in select conname from pg_constraint where conrelid='motoristas'::regclass and contype='u'
    and conkey = (select array_agg(attnum) from pg_attribute where attrelid='motoristas'::regclass and attname='matricula')
  loop execute format('alter table motoristas drop constraint %I', c.conname); end loop;
end $$;
alter table motoristas add constraint motoristas_empresa_matricula_unica unique (empresa_id, matricula);

drop table _migracao_empresa_padrao;

-- ─────────────────────────── 7. FUNÇÕES AUXILIARES (atualizadas) ──────────
create or replace function minha_empresa()
returns uuid
language sql stable security definer set search_path = public as $$
  select empresa_id from perfis where id = auth.uid();
$$;

create or replace function assinatura_ativa()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select status_assinatura in ('ativa','atrasada')
        or (status_assinatura = 'trial' and trial_termina_em > now())
    from empresas where id = minha_empresa()
  ), false);
$$;

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

drop trigger if exists empresa_motoristas    on motoristas;
drop trigger if exists empresa_veiculos      on veiculos;
drop trigger if exists empresa_kms           on kms;
drop trigger if exists empresa_apontamentos  on apontamentos;
drop trigger if exists empresa_rotas         on rotas;
drop trigger if exists empresa_alunos        on alunos;
drop trigger if exists empresa_lancamentos   on lancamentos;
drop trigger if exists empresa_pagamentos    on pagamentos;
drop trigger if exists empresa_regras        on regras;
drop trigger if exists empresa_convites      on convites;

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

-- ─────────────────────────── 8. ONBOARDING ATUALIZADO ──────────────────────
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

-- ─────────────────────────── 9. RLS: TROCA COMPLETA DAS POLÍTICAS ─────────
alter table empresas enable row level security;
drop policy if exists "empresas_select_propria" on empresas;
create policy "empresas_select_propria" on empresas for select using (id = minha_empresa());

drop policy if exists "perfis_select_autenticados" on perfis;
drop policy if exists "perfis_update_gestores" on perfis;
drop policy if exists "perfis_delete_admin" on perfis;
create policy "perfis_select_mesma_empresa" on perfis for select using (auth.uid() is not null and empresa_id = minha_empresa());
create policy "perfis_update_gestores" on perfis for update using (
  empresa_id = minha_empresa() and (eh_admin() or (papel_atual() = 'coordenador' and papel = 'funcionario'))
) with check (
  empresa_id = minha_empresa() and (eh_admin() or (papel_atual() = 'coordenador' and papel = 'funcionario'))
);
create policy "perfis_delete_admin" on perfis for delete using (empresa_id = minha_empresa() and eh_admin());

drop policy if exists "motoristas_select_autenticados" on motoristas;
drop policy if exists "motoristas_insert_gestores" on motoristas;
drop policy if exists "motoristas_update_gestores" on motoristas;
drop policy if exists "motoristas_delete_admin" on motoristas;
create policy "motoristas_select_mesma_empresa" on motoristas for select using (auth.uid() is not null and empresa_id = minha_empresa());
create policy "motoristas_insert_gestores" on motoristas for insert with check (empresa_id = minha_empresa() and eh_gestor());
create policy "motoristas_update_gestores" on motoristas for update using (empresa_id = minha_empresa() and eh_gestor()) with check (empresa_id = minha_empresa() and eh_gestor());
create policy "motoristas_delete_admin" on motoristas for delete using (empresa_id = minha_empresa() and eh_admin());

drop policy if exists "convites_select_gestores" on convites;
drop policy if exists "convites_insert_regra" on convites;
drop policy if exists "convites_delete_gestores" on convites;
create policy "convites_select_gestores" on convites for select using (empresa_id = minha_empresa() and (eh_admin() or (papel_atual()='coordenador' and papel='funcionario')));
create policy "convites_insert_regra" on convites for insert with check (empresa_id = minha_empresa() and (eh_admin() or (papel_atual()='coordenador' and papel='funcionario')));
create policy "convites_delete_gestores" on convites for delete using (empresa_id = minha_empresa() and (eh_admin() or (papel_atual()='coordenador' and papel='funcionario')));

drop policy if exists "veiculos_select_autenticados" on veiculos;
drop policy if exists "veiculos_insert_gestores" on veiculos;
drop policy if exists "veiculos_update_gestores" on veiculos;
drop policy if exists "veiculos_delete_admin" on veiculos;
create policy "veiculos_select_mesma_empresa" on veiculos for select using (auth.uid() is not null and empresa_id = minha_empresa());
create policy "veiculos_insert_gestores" on veiculos for insert with check (empresa_id = minha_empresa() and eh_gestor());
create policy "veiculos_update_gestores" on veiculos for update using (empresa_id = minha_empresa() and eh_gestor()) with check (empresa_id = minha_empresa() and eh_gestor());
create policy "veiculos_delete_admin" on veiculos for delete using (empresa_id = minha_empresa() and eh_admin());

drop policy if exists "kms_select_autenticados" on kms;
drop policy if exists "kms_insert_gestores" on kms;
drop policy if exists "kms_update_gestores" on kms;
drop policy if exists "kms_delete_gestores" on kms;
create policy "kms_select_mesma_empresa" on kms for select using (auth.uid() is not null and empresa_id = minha_empresa());
create policy "kms_insert_gestores" on kms for insert with check (empresa_id = minha_empresa() and eh_gestor());
create policy "kms_update_gestores" on kms for update using (empresa_id = minha_empresa() and eh_gestor()) with check (empresa_id = minha_empresa() and eh_gestor());
create policy "kms_delete_gestores" on kms for delete using (empresa_id = minha_empresa() and eh_gestor());

drop policy if exists "apontamentos_select" on apontamentos;
drop policy if exists "apontamentos_insert" on apontamentos;
drop policy if exists "apontamentos_update" on apontamentos;
drop policy if exists "apontamentos_delete" on apontamentos;
create policy "apontamentos_select" on apontamentos for select using (empresa_id = minha_empresa() and (eh_gestor() or motorista_id = motorista_atual()));
create policy "apontamentos_insert" on apontamentos for insert with check (empresa_id = minha_empresa() and (eh_gestor() or motorista_id = motorista_atual()));
create policy "apontamentos_update" on apontamentos for update using (empresa_id = minha_empresa() and (eh_gestor() or motorista_id = motorista_atual())) with check (empresa_id = minha_empresa() and (eh_gestor() or motorista_id = motorista_atual()));
create policy "apontamentos_delete" on apontamentos for delete using (empresa_id = minha_empresa() and eh_gestor());

drop policy if exists "rotas_select_autenticados" on rotas;
drop policy if exists "rotas_insert_gestores" on rotas;
drop policy if exists "rotas_update_gestores" on rotas;
drop policy if exists "rotas_delete_admin" on rotas;
create policy "rotas_select_mesma_empresa" on rotas for select using (auth.uid() is not null and empresa_id = minha_empresa());
create policy "rotas_insert_gestores" on rotas for insert with check (empresa_id = minha_empresa() and eh_gestor());
create policy "rotas_update_gestores" on rotas for update using (empresa_id = minha_empresa() and eh_gestor()) with check (empresa_id = minha_empresa() and eh_gestor());
create policy "rotas_delete_admin" on rotas for delete using (empresa_id = minha_empresa() and eh_admin());

drop policy if exists "alunos_select_gestores" on alunos;
drop policy if exists "alunos_insert_gestores" on alunos;
drop policy if exists "alunos_update_gestores" on alunos;
drop policy if exists "alunos_delete_admin" on alunos;
create policy "alunos_select_gestores" on alunos for select using (empresa_id = minha_empresa() and eh_gestor());
create policy "alunos_insert_gestores" on alunos for insert with check (empresa_id = minha_empresa() and eh_gestor());
create policy "alunos_update_gestores" on alunos for update using (empresa_id = minha_empresa() and eh_gestor()) with check (empresa_id = minha_empresa() and eh_gestor());
create policy "alunos_delete_admin" on alunos for delete using (empresa_id = minha_empresa() and eh_admin());

drop policy if exists "lancamentos_select_gestores" on lancamentos;
drop policy if exists "lancamentos_insert_gestores" on lancamentos;
drop policy if exists "lancamentos_update_gestores" on lancamentos;
drop policy if exists "lancamentos_delete_admin" on lancamentos;
create policy "lancamentos_select_gestores" on lancamentos for select using (empresa_id = minha_empresa() and eh_gestor());
create policy "lancamentos_insert_gestores" on lancamentos for insert with check (empresa_id = minha_empresa() and eh_gestor());
create policy "lancamentos_update_gestores" on lancamentos for update using (empresa_id = minha_empresa() and eh_gestor()) with check (empresa_id = minha_empresa() and eh_gestor());
create policy "lancamentos_delete_admin" on lancamentos for delete using (empresa_id = minha_empresa() and eh_admin());

drop policy if exists "pagamentos_select_gestores" on pagamentos;
drop policy if exists "pagamentos_insert_gestores" on pagamentos;
drop policy if exists "pagamentos_update_gestores" on pagamentos;
drop policy if exists "pagamentos_delete_admin" on pagamentos;
create policy "pagamentos_select_gestores" on pagamentos for select using (empresa_id = minha_empresa() and eh_gestor());
create policy "pagamentos_insert_gestores" on pagamentos for insert with check (empresa_id = minha_empresa() and eh_gestor());
create policy "pagamentos_update_gestores" on pagamentos for update using (empresa_id = minha_empresa() and eh_gestor()) with check (empresa_id = minha_empresa() and eh_gestor());
create policy "pagamentos_delete_admin" on pagamentos for delete using (empresa_id = minha_empresa() and eh_admin());

drop policy if exists "regras_select_gestores" on regras;
drop policy if exists "regras_insert_gestores" on regras;
drop policy if exists "regras_delete_gestores" on regras;
create policy "regras_select_gestores" on regras for select using (empresa_id = minha_empresa() and eh_gestor());
create policy "regras_insert_gestores" on regras for insert with check (empresa_id = minha_empresa() and eh_gestor());
create policy "regras_delete_gestores" on regras for delete using (empresa_id = minha_empresa() and eh_gestor());

-- ─────────────────────────── 10. STORAGE (comprovantes) ───────────────────
drop policy if exists "anexos_select_gestores" on storage.objects;
drop policy if exists "anexos_insert_gestores" on storage.objects;
drop policy if exists "anexos_delete_gestores" on storage.objects;
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
-- Confira o código gerado para a sua empresa (para uso do motorista no login):
select id, nome, codigo from empresas;
