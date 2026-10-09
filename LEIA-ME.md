# ODÔMETRO SAAS — guia da versão multi-empresa

Três arquivos:

- **`index.html`** — o site, agora com tela de "Criar minha empresa" e login por empresa.
- **`migracao_saas.sql`** — rode este no projeto Supabase **que você já tem**.
- **`schema.sql`** — schema completo, use só se for começar um projeto do zero.

## O que mudou na arquitetura

Cada empresa agora é isolada das outras (multi-tenant): toda tabela ganhou uma coluna `empresa_id`, e toda regra de permissão do banco passou a checar "é a mesma empresa?" além de "tem o papel certo?". Uma empresa nunca consegue ver ou mexer no dado de outra — isso é garantido no banco, não só na tela.

**O código da empresa.** Como o motorista não usa e-mail real para entrar (ele usa matrícula), e agora existem várias empresas no mesmo sistema, cada empresa ganhou um **código curto** (ex.: `vansjoao`) que o motorista digita junto da matrícula para entrar. Sem isso, duas empresas diferentes com um motorista de matrícula "M-001" colidiriam. Você escolhe esse código na hora de criar a empresa (pode editar a sugestão automática).

## Passo 1 — Rodar a migração

No **SQL Editor** do projeto Supabase que você já usa, abra uma query nova, cole **todo** o conteúdo de `migracao_saas.sql` e rode. Ele:

1. Cria a tabela de empresas.
2. Transforma tudo que já existe no seu banco na **primeira empresa** automaticamente (com um código gerado tipo `padrao4f2a` — você pode trocar depois, veja abaixo).
3. Reescreve todas as regras de permissão para incluir o isolamento por empresa.
4. No final, mostra o `id` e o `codigo` dessa empresa — guarde essa tela ou role para ver o resultado.

Se quiser trocar o código gerado automaticamente por um mais fácil de lembrar, rode depois:
```sql
update empresas set codigo = 'seucodigo' where nome = 'Minha Empresa';
```
(Só letras minúsculas e números, sem espaço.)

## Passo 2 — Publicar o novo `index.html`

Mesmo processo de sempre: cole sua `SUPABASE_URL` e `SUPABASE_ANON_KEY` no topo do arquivo, suba no Netlify por cima do site atual.

## ⚠️ Um ponto de atenção: comprovantes já anexados

O caminho de onde os comprovantes ficam guardados mudou (agora inclui o id da empresa, para isolar cada cliente). Anexos que já foram enviados **antes** desta migração podem parar de abrir. Se você já testou anexar alguma nota fiscal, verifique depois da migração — se não abrir, é só anexar de novo no lançamento.

## Como todo mundo entra agora

- **Administrador/coordenador/funcionário** — e-mail e senha, sem mudança.
- **Motorista** — matrícula **+ código da empresa** + senha (tanto no login quanto em "Criar minha senha"). O código aparece para o coordenador na hora de gerar o acesso do motorista (tela Motoristas → ícone de chave).
- **Empresa nova** — tela "Criar minha empresa" na tela de login: nome da empresa, código, seu nome, e-mail e senha. Você vira administrador automaticamente.

## O que ainda falta: cobrança (Stripe)

A tabela de empresas já tem os campos prontos (`status_assinatura`, `stripe_customer_id`, `stripe_subscription_id`, `trial_termina_em`), mas **nada cobra automaticamente ainda** — toda empresa nova entra em modo "trial" indefinidamente, sem bloqueio. Isso é proposital: cobrança de verdade exige uma peça técnica nova (funções de servidor do Supabase, porque a chave secreta do Stripe nunca pode ficar no site) e prefiro construir isso com calma numa próxima etapa, em vez de misturar com essa mudança de banco de dados. Me avise quando quiser seguir para essa parte.
