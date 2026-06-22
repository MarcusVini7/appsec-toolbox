# Guia de uso

Este guia mostra, na prática, como usar cada script do `appsec-toolbox`.
Todos os exemplos usam apenas alvos seguros: `http://127.0.0.1:8000` (um
serviço local seu) e `https://example.com` (domínio reservado para
documentação/teste). Substitua por um alvo próprio ou explicitamente
autorizado antes de usar de verdade.

## Perfis: safe (padrão), normal, deep

A maioria dos scripts aceita um segundo argumento de perfil:

```bash
./scripts/web-check.sh http://127.0.0.1:8080            # = safe
./scripts/web-check.sh http://127.0.0.1:8080 safe
./scripts/web-check.sh http://127.0.0.1:8080 normal
./scripts/web-check.sh http://127.0.0.1:8080 deep
```

- **safe** (padrão): rate baixo, wordlist pequena, Nuclei rápido
  (`exposure,misconfig`), sem nikto, timeout curto.
- **normal**: wordlist média, Nuclei com tags `+cve`, nmap com `-sC`
  (scripts seguros padrão), inclui nikto.
- **deep**: pede confirmação explícita antes de rodar, wordlist maior,
  Nuclei sem filtro de tags (mais amplo), nmap varre todas as portas
  (1-65535). Ainda sem nenhuma ação destrutiva.

## 0. Validar o ambiente

```bash
./scripts/check-tools.sh
```

Rode isso primeiro. Se faltar uma ferramenta essencial, o script termina com
código de saída diferente de zero — instale o que estiver `MISSING` antes de
seguir.

## 1. Subir um alvo de teste local (opcional)

Se você não tem um alvo próprio à mão, use o laboratório local:

```bash
./scripts/start-local-lab.sh
# URL: http://127.0.0.1:8080
```

Para derrubar depois:

```bash
./scripts/stop-local-lab.sh
```

## 2. Auditoria web básica completa

```bash
./scripts/web-check.sh http://127.0.0.1:8080
```

O script:

1. Valida que o alvo começa com `http://` ou `https://`.
2. Cria `reports/<alvo>-<timestamp>/`.
3. Coleta headers HTTP, indícios passivos de WAF/CDN (heurística sobre os
   próprios headers, sem requisição extra), fingerprint (`whatweb`), `nmap`
   na porta do alvo, perfil de exposição (`nmap --top-ports 100`, ainda
   apenas observacional), enumeração de conteúdo (`gobuster` e `ffuf` com a
   wordlist `common.txt`) e Nuclei em modo rápido.
4. Gera `summary.md` com o que foi executado, os arquivos gerados e achados
   simples — inclusive porta(s) abertas no perfil de exposição e indícios de
   WAF/CDN — sempre terminando com o aviso de que tudo precisa de validação
   manual.

Ao final, abra `reports/<alvo>-<timestamp>/summary.md` para o resumo, e os
demais arquivos (`headers.txt`, `whatweb.txt`, `nmap.txt`,
`gobuster-common.txt`, `ffuf-common.json`, `nuclei.txt`) para o detalhe.

## 3. Reconhecimento dedicado

```bash
./scripts/recon-web.sh https://example.com
```

whatweb, httpx, curl com e sem redirecionamento, cookies, indícios de
WAF/CDN e um resumo simples de headers. Sem perfil — é sempre leve.

## 4. Auditoria de headers HTTP (OK/WARN/REVIEW)

```bash
./scripts/headers-audit.sh https://example.com
```

Classifica cada header relevante (incluindo COOP/CORP/COEP) e cada flag de
cookie como `OK`, `WARN` ou `REVIEW`, e gera `headers-audit.md`. (O script
mais simples `http-headers-check.sh`, da versão anterior do toolkit,
continua disponível para uma checagem rápida de presença/ausência.)

## 5. Verificar TLS/SSL com resumo

```bash
./scripts/tls-audit.sh https://example.com
```

Exige HTTPS. Roda `testssl` com timeout e gera `tls-summary.md` com
protocolos aceitos, dados do certificado e ciphers potencialmente fracos.

## 6. Descoberta de conteúdo por perfil

```bash
./scripts/discovery.sh https://example.com safe
./scripts/discovery.sh https://example.com normal
./scripts/discovery.sh https://example.com deep
```

gobuster + ffuf com wordlist e extensões conforme o perfil. Nunca usa
wordlist de senha nem tenta login.

## 7. Nuclei por perfil

```bash
./scripts/nuclei-safe.sh https://example.com safe
./scripts/nuclei-safe.sh https://example.com normal
./scripts/nuclei-safe.sh https://example.com deep
```

`-ni` sempre ativo (sem interactsh/OAST). Perfil `deep` pede confirmação.

## 8. Varredura de portas por perfil

```bash
./scripts/port-check.sh 127.0.0.1 safe
./scripts/port-check.sh 127.0.0.1 normal
./scripts/port-check.sh 127.0.0.1 deep   # pede confirmação (1-65535)
```

## 9. Consolidar um relatório existente

```bash
./scripts/report-summary.sh reports/<pasta-do-relatorio>
```

Gera/atualiza `summary.md` dentro da pasta com achados, possíveis falsos
positivos, recomendações defensivas e próximos passos.

## 10. Verificar dados sensíveis antes de compartilhar

```bash
./scripts/sanitize-reports.sh reports/<pasta-do-relatorio>
```

Procura tokens, JWT, cookies de sessão, csrftoken, `Authorization: Bearer`,
chaves privadas, e-mails, IPs internos e senhas óbvias. Gera
`sensitive-findings.txt` com alertas — não remove nada automaticamente.

## 11. Auditoria web completa (orquestrador)

```bash
./scripts/web-check.sh http://127.0.0.1:8080 safe
```

Ver [Perfis](#perfis-safe-padrão-normal-deep) acima. Roda headers, WAF/CDN,
whatweb, nmap (porta do alvo + perfil de exposição), gobuster/ffuf, nuclei
e (em `normal`/`deep`) nikto, e gera `metadata.txt` + `summary.md` completo.

## 12. Atalhos via Makefile

```bash
make check          # ./scripts/check-tools.sh
make lab-up          # ./scripts/start-local-lab.sh
make scan-local       # ./scripts/web-check.sh http://127.0.0.1:8080 safe
make headers-local     # ./scripts/headers-audit.sh http://127.0.0.1:8080
make tls-local          # ./scripts/tls-audit.sh (requer HTTPS — ver Makefile)
make lab-down            # ./scripts/stop-local-lab.sh
```

## Dica geral

Nenhum script aqui substitui análise humana. Trate toda saída como ponto de
partida para investigação manual — veja
[`docs/REPORTING.md`](REPORTING.md) para como interpretar os resultados.
