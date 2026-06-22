# OPSEC — segurança operacional do toolkit

Foco defensivo: como evitar que o próprio trabalho de auditoria vire um
incidente de vazamento de dados.

## Não vazar dados de cliente

Relatórios podem conter headers internos, caminhos descobertos, fingerprints
de tecnologia, certificados, e ocasionalmente segredos capturados por
acidente (tokens em headers, cookies de sessão). Trate tudo em `reports/`
como confidencial por padrão.

## Não commitar reports

`reports/*` é ignorado pelo Git (exceto `.gitkeep`). Antes de cada commit:

```bash
git status --ignored -sb
git ls-files
```

Se algo dentro de `reports/` aparecer em `git ls-files`, pare e remova do
versionamento antes de continuar.

## Não salvar secrets

Nunca adicione ao repositório `.env`, chaves privadas (`.key`, `.pem`,
`.crt`, `.p12`), dumps (`.sql`, `.dump`), backups (`.bak`, `.old`) ou
qualquer arquivo de configuração com credenciais reais. Use
`config/*.env.example` como referência e mantenha o `.env` real (se você
criar um) fora do controle de versão — o `.gitignore` já bloqueia isso.

## Separar targets reais de exemplos

`targets/example-targets.txt` deve conter apenas exemplos genéricos
(`http://127.0.0.1:8000`, `https://example.com`). Listas reais de alvos
autorizados vão em arquivos adicionais dentro de `targets/` (ex.:
`targets/cliente-x.txt`), que já são ignorados pelo Git automaticamente.

## Usar rate limit

Todo scan deste toolkit já vem com rate-limit e timeout por padrão (perfil
`safe`). Não desative isso nem aumente agressivamente os limites contra
ambiente de terceiros, mesmo com autorização — combine limites com o
responsável pelo ambiente antes de qualquer ajuste, especialmente em
produção.

## Registrar autorização

Mantenha, fora do repositório (ou em um local com controle de acesso
adequado, nunca commitado), o registro de quem autorizou o teste, qual o
escopo e qual o período. Isso protege tanto você quanto o cliente.

## Manter logs organizados

Cada execução cria sua própria pasta em `reports/<alvo>-<perfil>-<timestamp>/`,
com `metadata.txt` registrando alvo, perfil, data/hora e comandos executados.
Use `scripts/report-summary.sh` para consolidar, e
`scripts/sanitize-reports.sh` para varrer por dados sensíveis antes de
compartilhar qualquer coisa para fora do ambiente de trabalho.

## Resumo rápido

Antes de enviar qualquer relatório para fora: `sanitize-reports.sh` rodado,
`git status --ignored` conferido, e autorização documentada. Se faltar
qualquer um dos três, não envie ainda.
