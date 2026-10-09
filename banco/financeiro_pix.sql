-- ═══════════════════════════════════════════════════════════════════════
-- ODÔMETRO · FINANCEIRO: CHAVE PIX DA EMPRESA (pra gerar Pix copia-e-cola
-- no portal dos responsáveis). Rode depois de portal_responsaveis.sql.
-- ═══════════════════════════════════════════════════════════════════════

alter table empresas add column if not exists pix_chave text;
alter table empresas add column if not exists pix_nome_recebedor text;
alter table empresas add column if not exists pix_cidade text;

-- A policy de select de `empresas` só olhava minha_empresa() (via `perfis`), então um
-- responsável (que não tem linha em `perfis`) nunca conseguia nem ler os dados da própria
-- empresa (nome, chave pix etc.). Corrige incluindo empresa_do_responsavel() também.
-- E não existia NENHUMA policy de update em `empresas` — sem ela, o admin não consegue
-- salvar a chave pix (nem qualquer outro dado da empresa) pelo app.
drop policy if exists "empresas_select_propria" on empresas;
create policy "empresas_select_propria" on empresas for select using (
  id = minha_empresa() or id = empresa_do_responsavel()
);
drop policy if exists "empresas_update_admin" on empresas;
create policy "empresas_update_admin" on empresas for update using (
  id = minha_empresa() and eh_admin()
) with check (
  id = minha_empresa() and eh_admin()
);

-- ═══════════════════════════════ PRONTO ═════════════════════════════════
select 'financeiro_pix aplicado' as status;
