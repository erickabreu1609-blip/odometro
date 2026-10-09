-- ═══════════════════════════════════════════════════════════════════════
-- ODÔMETRO · CONFIRMAÇÃO AUTOMÁTICA DE PAGAMENTO POR COMPROVANTE PIX
-- Rode depois de financeiro_pix.sql.
-- ═══════════════════════════════════════════════════════════════════════

alter table pagamentos add column if not exists comprovante_path text;
alter table pagamentos add column if not exists origem_baixa text default 'manual' check (origem_baixa in ('manual','pix_auto'));

-- ═══════════════════════════════ PRONTO ═════════════════════════════════
select 'confirmacao_pix aplicado' as status;
