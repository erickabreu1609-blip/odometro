-- ═══════════════════════════════════════════════════════════════════════
-- ODÔMETRO · CONTRATO DE TRANSPORTE ESCOLAR (assinatura anual via gov.br)
-- Rode depois de confirmacao_pix.sql.
-- ═══════════════════════════════════════════════════════════════════════

-- ─────────────────────── 1. CPF DO RESPONSÁVEL (pro contrato) ──────────
alter table alunos add column if not exists cpf_responsavel text;

-- ─────────────────────── 2. DADOS DA EMPRESA (pro contrato) ────────────
alter table empresas add column if not exists cnpj text;
alter table empresas add column if not exists endereco text;

-- ─────────────────────── 3. CONTRATOS ───────────────────────────────────
create table if not exists contratos (
  id uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references empresas(id) on delete cascade,
  aluno_id uuid not null references alunos(id) on delete cascade,
  ano_letivo int not null,
  status text not null default 'pendente' check (status in ('pendente','assinado')),
  comprovante_path text,
  assinado_em timestamptz,
  criado_em timestamptz not null default now(),
  unique (aluno_id, ano_letivo)
);

drop trigger if exists empresa_contratos on contratos;
create trigger empresa_contratos before insert on contratos for each row execute function preencher_empresa_id();

alter table contratos enable row level security;
drop policy if exists "contratos_select" on contratos;
drop policy if exists "contratos_insert_gestores" on contratos;
drop policy if exists "contratos_update_gestores" on contratos;
drop policy if exists "contratos_delete_gestores" on contratos;
create policy "contratos_select" on contratos for select using (
  (empresa_id = minha_empresa() and eh_gestor())
  or (aluno_id in (select id from alunos where responsavel_id = responsavel_atual()))
);
create policy "contratos_insert_gestores" on contratos for insert with check (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "contratos_update_gestores" on contratos for update using (
  empresa_id = minha_empresa() and eh_gestor()
) with check (
  empresa_id = minha_empresa() and eh_gestor()
);
create policy "contratos_delete_gestores" on contratos for delete using (
  empresa_id = minha_empresa() and eh_gestor()
);
-- Sem policy de update/insert pra responsável de propósito: o upload do contrato assinado
-- passa pela Edge Function `enviar-contrato-assinado` (com service role), que confere a posse
-- e só então marca o contrato como assinado — o cliente nunca escreve direto nessa tabela.

-- ═══════════════════════════════ PRONTO ═════════════════════════════════
select 'contratos_transporte aplicado' as status;
