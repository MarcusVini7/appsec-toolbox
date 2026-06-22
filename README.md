# appsec-toolbox

Toolkit pessoal de **Red Team / AppSec controlado** para testes de
segurança web **autorizados**. Cobre reconhecimento, fingerprinting,
enumeração de superfície exposta, checagens de headers/TLS/rotas/tecnologias
e detecção de más configurações conhecidas (via templates do Nuclei) — tudo
de forma controlada, auditável e sem ações destrutivas.

## Objetivo

Dar suporte prático a auditorias de segurança web autorizadas, com:

- Perfis de intensidade (`safe`, `normal`, `deep`) para equilibrar
  velocidade e cobertura.
- Relatórios organizados, com metadados e resumos legíveis.
- Validações automáticas (alvo explícito, formato de URL, ferramentas
  disponíveis) e modo seguro por padrão.
- Documentação operacional (metodologia, OPSEC, segurança, interpretação de
  relatórios).

## ⚠️ Aviso legal e ético

Use este projeto **somente**:

- em ambientes que você possui, ou
- em ambientes para os quais você tem autorização explícita e por escrito
  do responsável.

Testar sistemas de terceiros sem autorização pode configurar crime. Este
toolkit **não** faz exploração ativa que altere dados, derrube serviço,
faça bypass real de autenticação, persista acesso, roube credenciais ou
execute payload malicioso — em nenhum perfil, inclusive `deep`. Veja
[`docs/SAFETY.md`](docs/SAFETY.md) para a lista completa do que este
projeto explicitamente não faz.

## Instalação

Ferramentas esperadas no `PATH`:

```
nmap whatweb gobuster ffuf nuclei nikto testssl curl dig whois httpx subfinder
docker (+ docker compose)
```

Mais SecLists em `/usr/share/seclists` e templates do Nuclei em
`~/nuclei-templates` (opcional — o Nuclei também atualiza os próprios).

Rode `./scripts/check-tools.sh` (ou `make check`) para validar tudo de uma
vez — mostra `OK`/`MISSING`/`WARN` por ferramenta.

Após clonar:

```bash
chmod +x scripts/*.sh
```

## Quickstart

```bash
make lab-up                                    # sobe nginx local em :8080
make scan-local                                # web-check.sh em modo safe
make headers-local                             # auditoria de headers
make tls-local TLS_TARGET=https://example.com  # auditoria TLS (precisa HTTPS)
make lab-down                                   # derruba o laboratório
```

## Perfis: safe (padrão), normal, deep

```bash
./scripts/web-check.sh http://127.0.0.1:8080            # = safe
./scripts/web-check.sh http://127.0.0.1:8080 normal
./scripts/web-check.sh http://127.0.0.1:8080 deep        # pede confirmação
```

| Perfil | Wordlist | Nuclei | Nmap | Nikto |
|---|---|---|---|---|
| `safe` (padrão) | `common.txt` | `exposure,misconfig`, rate-limit 10, timeout 60s | `-sV --top-ports 100` | não |
| `normal` | `directory-list-2.3-small.txt` | `+cve`, timeout 180s | `-sV -sC --top-ports 1000` | sim |
| `deep` | `directory-list-2.3-medium.txt` | sem filtro de tags, timeout 600s, rate-limit 5 | `-sV -sC -p-` (1-65535) | sim |

`deep` sempre pede confirmação explícita antes de rodar. Nenhum perfil
inclui brute force, exploração ativa ou qualquer ação destrutiva — perfis
mais intensos significam mais *cobertura de detecção*, não mais
agressividade ofensiva.

## Estrutura

```
appsec-toolbox/
├── README.md
├── Makefile
├── .gitignore
├── config/
│   ├── profiles.env.example     # limites por perfil (rate, threads, tags)
│   └── wordlists.env.example    # caminhos de wordlist por perfil
├── docs/
│   ├── USAGE.md
│   ├── SAFETY.md
│   ├── REDTEAM-METHODOLOGY.md
│   ├── OPSEC.md
│   └── REPORTING.md
├── scripts/
│   ├── lib/common.sh        # helpers compartilhados + lógica de perfis
│   ├── check-tools.sh       # valida o ambiente
│   ├── web-check.sh         # auditoria web completa, por perfil
│   ├── recon-web.sh         # reconhecimento (whatweb/httpx/cookies/headers)
│   ├── headers-audit.sh     # headers OK/WARN/REVIEW + cookies
│   ├── http-headers-check.sh # checagem simples de presença/ausência (legado)
│   ├── tls-audit.sh         # testssl + resumo (protocolos/cert/ciphers)
│   ├── tls-check.sh         # wrapper testssl simples (legado)
│   ├── discovery.sh         # gobuster + ffuf por perfil
│   ├── nuclei-safe.sh       # nuclei por perfil (-ni sempre ativo)
│   ├── nuclei-quick.sh / nuclei-full.sh  # variantes anteriores (legado)
│   ├── port-check.sh        # nmap por perfil
│   ├── report-summary.sh    # consolida uma pasta de relatório
│   ├── sanitize-reports.sh  # alerta dados sensíveis em um relatório
│   ├── start-local-lab.sh / stop-local-lab.sh  # laboratório Docker local
├── reports/                  # saída dos scripts — NÃO versionada (exceto .gitkeep)
└── targets/                  # alvos de teste — NÃO versionada (exceto exemplos)
```

## Exemplos de uso

```bash
./scripts/web-check.sh http://127.0.0.1:8080 safe
./scripts/recon-web.sh https://example.com
./scripts/headers-audit.sh https://example.com
./scripts/tls-audit.sh https://example.com
./scripts/discovery.sh https://example.com normal
./scripts/nuclei-safe.sh https://example.com safe
./scripts/port-check.sh 127.0.0.1 safe
./scripts/report-summary.sh reports/<pasta-do-relatorio>
./scripts/sanitize-reports.sh reports/<pasta-do-relatorio>
```

Use sempre `http://127.0.0.1:8000` (serviço local seu) ou
`https://example.com` (domínio reservado pela IANA) para validar o toolkit
antes de apontar para um alvo real autorizado.

Detalhes completos de cada script: [`docs/USAGE.md`](docs/USAGE.md).

## Relatórios e dados sensíveis

Tudo em `reports/` é ignorado pelo Git (exceto `.gitkeep`). Cada execução
cria `reports/<alvo>-<perfil>-<timestamp>/`, com `metadata.txt` (alvo,
perfil, data/hora, comandos executados) e `summary.md`. Antes de compartilhar
qualquer relatório:

```bash
./scripts/sanitize-reports.sh reports/<pasta-do-relatorio>
```

Isso varre por tokens, JWT, cookies de sessão, chaves privadas, e-mails e
IPs internos, e gera `sensitive-findings.txt` (apenas alerta — não remove
nada automaticamente). Antes de qualquer commit, confirme também:

```bash
git status --ignored -sb
git ls-files
```

Nenhum arquivo dentro de `reports/` (exceto `.gitkeep`) ou `targets/`
(exceto `.gitkeep` e `targets/example-targets.txt`) deve aparecer em
`git ls-files`.

## Adicionando alvos de exemplo

Para listar alvos de teste localmente sem expor clientes reais, crie um
arquivo adicional dentro de `targets/` (ex.: `targets/meus-alvos.txt`) — ele
é ignorado automaticamente pelo `.gitignore`. Nunca edite
`targets/example-targets.txt` para incluir alvos reais.

## Configuração opcional

`config/profiles.env.example` e `config/wordlists.env.example` documentam
todas as variáveis de ambiente que os scripts aceitam para sobrescrever
limites/wordlists padrão. Copie para um `.env` local se quiser ajustar — o
`.gitignore` já bloqueia `.env`/`.env.*`.

## Laboratório local

```bash
./scripts/start-local-lab.sh    # nginx:alpine em http://127.0.0.1:8080
./scripts/web-check.sh http://127.0.0.1:8080 safe
./scripts/stop-local-lab.sh
```

## Documentação

- [`docs/USAGE.md`](docs/USAGE.md) — uso detalhado de cada script
- [`docs/SAFETY.md`](docs/SAFETY.md) — o que este projeto não faz, mesmo autorizado
- [`docs/REDTEAM-METHODOLOGY.md`](docs/REDTEAM-METHODOLOGY.md) — as 10 fases de uma auditoria
- [`docs/OPSEC.md`](docs/OPSEC.md) — segurança operacional do próprio trabalho
- [`docs/REPORTING.md`](docs/REPORTING.md) — como interpretar achados e evitar falso positivo

## Próximos passos

- Avaliar integração opcional de `httpx`/`subfinder` para descoberta de
  subdomínios antes do reconhecimento web (fase 2 da metodologia).
- Considerar template próprio de relatório final (export para PDF/Markdown
  consolidado) a partir de `report-summary.sh`.
- Revisar periodicamente os templates do Nuclei usados em `normal`/`deep`
  para manter a cobertura de CVEs atualizada (`nuclei -update-templates`).
