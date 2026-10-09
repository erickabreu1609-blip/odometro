-- ═══════════════════════════════════════════════════════════════════════
-- ODÔMETRO · COBRANÇA (STRIPE) — rode no mesmo projeto Supabase, depois de
-- já ter rodado migracao_saas.sql. Isto faz duas coisas:
--
-- 1. Liga de verdade o bloqueio por assinatura: hoje toda empresa fica em
--    "trial" pra sempre sem nunca ser bloqueada. Depois disto, quando o
--    trial vencer (ou a assinatura ficar "atrasada"/"cancelada"), o banco
--    passa a recusar leitura/escrita nas tabelas operacionais — não é só
--    a tela que esconde, é o banco que nega.
-- 2. Cria os 3 planos (básico / pro / ilimitado) e restringe os módulos de
--    Financeiro (lançamentos, regras) ao plano pro+, e o módulo Escolar
--    (rotas, alunos, mensalidades) ao plano ilimitado.
--
-- Empresas e perfis continuam sempre legíveis (senão ninguém veria a tela
-- de "assinatura pendente" nem conseguiria pagar).
-- ═══════════════════════════════════════════════════════════════════════

-- ─────────────────────────── 1. PLANOS ──────────────────────────────────
alter table empresas alter column plano set default 'basico';
update empresas set plano = 'ilimitado' where plano is null or plano = 'padrao';
alter table empresas drop constraint if exists empresas_plano_valido;
alter table empresas add constraint empresas_plano_valido check (plano in ('basico','pro','ilimitado'));

-- Campos de controle de cobrança que as Edge Functions vão preencher.
alter table empresas add column if not exists stripe_price_id text;
alter table empresas add column if not exists assinatura_atualizada_em timestamptz;

create or replace function meu_plano()
returns text
language sql stable security definer set search_path = public as $$
  select plano from empresas where id = minha_empresa();
$$;

-- ─────────────────────────── 2. BLOQUEIO REAL POR ASSINATURA ───────────
-- "atrasada" deixa de contar como ativa: pagamento que falhou bloqueia,
-- como combinado (em vez de dar carência silenciosa).
create or replace function assinatura_ativa()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select status_assinatura = 'ativa'
        or (status_assinatura = 'trial' and trial_termina_em > now())
    from empresas where id = minha_empresa()
  ), false);
$$;

-- ─────────────────────────── 3. POLÍTICAS — MOTORISTAS ─────────────────
drop policy if exists "motoristas_select_mesma_empresa" on motoristas;
drop policy if exists "motoristas_insert_gestores" on motoristas;
drop policy if exists "motoristas_update_gestores" on motoristas;
create policy "motoristas_select_mesma_empresa" on motoristas for select using (auth.uid() is not null and empresa_id = minha_empresa() and assinatura_ativa());
create policy "motoristas_insert_gestores" on motoristas for insert with check (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa());
create policy "motoristas_update_gestores" on motoristas for update using (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa()) with check (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa());

-- ─────────────────────────── 4. POLÍTICAS — VEÍCULOS ────────────────────
drop policy if exists "veiculos_select_mesma_empresa" on veiculos;
drop policy if exists "veiculos_insert_gestores" on veiculos;
drop policy if exists "veiculos_update_gestores" on veiculos;
create policy "veiculos_select_mesma_empresa" on veiculos for select using (auth.uid() is not null and empresa_id = minha_empresa() and assinatura_ativa());
create policy "veiculos_insert_gestores" on veiculos for insert with check (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa());
create policy "veiculos_update_gestores" on veiculos for update using (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa()) with check (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa());

-- ─────────────────────────── 5. POLÍTICAS — KMS ─────────────────────────
drop policy if exists "kms_select_mesma_empresa" on kms;
drop policy if exists "kms_insert_gestores" on kms;
drop policy if exists "kms_update_gestores" on kms;
create policy "kms_select_mesma_empresa" on kms for select using (auth.uid() is not null and empresa_id = minha_empresa() and assinatura_ativa());
create policy "kms_insert_gestores" on kms for insert with check (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa());
create policy "kms_update_gestores" on kms for update using (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa()) with check (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa());

-- ─────────────────────────── 6. POLÍTICAS — APONTAMENTOS (ponto) ───────
drop policy if exists "apontamentos_select" on apontamentos;
drop policy if exists "apontamentos_insert" on apontamentos;
drop policy if exists "apontamentos_update" on apontamentos;
create policy "apontamentos_select" on apontamentos for select using (empresa_id = minha_empresa() and assinatura_ativa() and (eh_gestor() or motorista_id = motorista_atual()));
create policy "apontamentos_insert" on apontamentos for insert with check (empresa_id = minha_empresa() and assinatura_ativa() and (eh_gestor() or motorista_id = motorista_atual()));
create policy "apontamentos_update" on apontamentos for update using (empresa_id = minha_empresa() and assinatura_ativa() and (eh_gestor() or motorista_id = motorista_atual())) with check (empresa_id = minha_empresa() and assinatura_ativa() and (eh_gestor() or motorista_id = motorista_atual()));

-- bater_ponto() é SECURITY DEFINER e passa por cima do RLS acima — por
-- isso precisa checar a assinatura na mão.
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
  if not assinatura_ativa() then
    raise exception 'A assinatura da sua empresa não está ativa. Fale com o administrador.';
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

-- ─────────────────────────── 7. MÓDULO ESCOLAR (plano ilimitado) ───────
drop policy if exists "rotas_select_mesma_empresa" on rotas;
drop policy if exists "rotas_insert_gestores" on rotas;
drop policy if exists "rotas_update_gestores" on rotas;
create policy "rotas_select_mesma_empresa" on rotas for select using (auth.uid() is not null and empresa_id = minha_empresa() and assinatura_ativa() and meu_plano() = 'ilimitado');
create policy "rotas_insert_gestores" on rotas for insert with check (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa() and meu_plano() = 'ilimitado');
create policy "rotas_update_gestores" on rotas for update using (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa() and meu_plano() = 'ilimitado') with check (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa() and meu_plano() = 'ilimitado');

drop policy if exists "alunos_select_gestores" on alunos;
drop policy if exists "alunos_insert_gestores" on alunos;
drop policy if exists "alunos_update_gestores" on alunos;
create policy "alunos_select_gestores" on alunos for select using (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa() and meu_plano() = 'ilimitado');
create policy "alunos_insert_gestores" on alunos for insert with check (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa() and meu_plano() = 'ilimitado');
create policy "alunos_update_gestores" on alunos for update using (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa() and meu_plano() = 'ilimitado') with check (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa() and meu_plano() = 'ilimitado');

drop policy if exists "pagamentos_select_gestores" on pagamentos;
drop policy if exists "pagamentos_insert_gestores" on pagamentos;
drop policy if exists "pagamentos_update_gestores" on pagamentos;
create policy "pagamentos_select_gestores" on pagamentos for select using (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa() and meu_plano() = 'ilimitado');
create policy "pagamentos_insert_gestores" on pagamentos for insert with check (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa() and meu_plano() = 'ilimitado');
create policy "pagamentos_update_gestores" on pagamentos for update using (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa() and meu_plano() = 'ilimitado') with check (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa() and meu_plano() = 'ilimitado');

-- ─────────────────────────── 8. MÓDULO FINANCEIRO (plano pro+) ─────────
drop policy if exists "lancamentos_select_gestores" on lancamentos;
drop policy if exists "lancamentos_insert_gestores" on lancamentos;
drop policy if exists "lancamentos_update_gestores" on lancamentos;
create policy "lancamentos_select_gestores" on lancamentos for select using (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa() and meu_plano() in ('pro','ilimitado'));
create policy "lancamentos_insert_gestores" on lancamentos for insert with check (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa() and meu_plano() in ('pro','ilimitado'));
create policy "lancamentos_update_gestores" on lancamentos for update using (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa() and meu_plano() in ('pro','ilimitado')) with check (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa() and meu_plano() in ('pro','ilimitado'));

drop policy if exists "regras_select_gestores" on regras;
drop policy if exists "regras_insert_gestores" on regras;
create policy "regras_select_gestores" on regras for select using (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa() and meu_plano() in ('pro','ilimitado'));
create policy "regras_insert_gestores" on regras for insert with check (empresa_id = minha_empresa() and eh_gestor() and assinatura_ativa() and meu_plano() in ('pro','ilimitado'));

-- ─────────────────────────── 9. CONVITES seguem exigindo assinatura ────
drop policy if exists "convites_select_gestores" on convites;
drop policy if exists "convites_insert_regra" on convites;
create policy "convites_select_gestores" on convites for select using (empresa_id = minha_empresa() and assinatura_ativa() and (eh_admin() or (papel_atual()='coordenador' and papel='funcionario')));
create policy "convites_insert_regra" on convites for insert with check (empresa_id = minha_empresa() and assinatura_ativa() and (eh_admin() or (papel_atual()='coordenador' and papel='funcionario')));

-- ═══════════════════════════════ PRONTO ═════════════════════════════════
-- Confira o plano de cada empresa (a sua já foi promovida a "ilimitado"
-- para não travar seus próprios testes):
select id, nome, codigo, plano, status_assinatura, trial_termina_em from empresas;
