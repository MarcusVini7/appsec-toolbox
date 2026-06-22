# Metodologia (Red Team controlado)

Este documento descreve as fases seguras de uma auditoria realizada com o
`appsec-toolbox`. O objetivo é estruturar o trabalho, não pular etapas — e
nenhuma fase aqui inclui exploração ativa, brute force de login, bypass
real, persistência ou qualquer ação destrutiva (ver `docs/SAFETY.md`).

## 1. Escopo e autorização

Antes de qualquer comando: confirme por escrito o que está dentro do escopo
(domínios, IPs, portas, ambientes), o período autorizado, e quem é o
responsável pela autorização. Registre isso fora do repositório (não
commitamos targets reais — ver `docs/OPSEC.md`). Sem isso, pare aqui.

## 2. Reconhecimento passivo/controlado

Levantamento inicial sem (ou com mínima) interação direta agressiva:
`whois`, `dig`, `subfinder` (enumeração de subdomínios via fontes públicas),
e `scripts/recon-web.sh` para uma primeira passada (headers, redirecionamentos,
cookies, fingerprint inicial). Perfil recomendado: `safe`.

## 3. Fingerprinting

Identificação de tecnologia, servidor, framework, CDN/WAF:
`whatweb`, `httpx`, e a heurística de WAF/CDN embutida (`analyze_edge_protection`,
usada por `recon-web.sh`, `web-check.sh` e `headers-audit.sh`).

## 4. Enumeração web

Descoberta de caminhos e arquivos comuns com `scripts/discovery.sh` (ou a
etapa equivalente do `web-check.sh`). Comece em `safe`, suba para `normal`/`deep`
apenas nos pontos que já mostraram sinal de interesse. Nunca com wordlist de
senha — isso está fora do escopo deste toolkit.

## 5. Análise de headers/cookies

`scripts/headers-audit.sh` classifica cada header relevante como `OK`,
`WARN` ou `REVIEW`, e avalia flags de cookies (`HttpOnly`, `Secure`,
`SameSite`). Nenhuma ausência é tratada como vulnerabilidade automática.

## 6. TLS

`scripts/tls-audit.sh` roda `testssl` com timeout e gera um resumo de
protocolos aceitos, certificado e ciphers potencialmente fracos. Sempre
exige HTTPS.

## 7. Detecção de exposição

`scripts/port-check.sh` (ou a etapa de "perfil de exposição" do
`web-check.sh`) identifica portas/serviços acessíveis. `scripts/nuclei-safe.sh`
roda templates de exposição/misconfiguração/CVE conhecidos, com `-ni` (sem
interactsh/OAST) e rate-limit conforme o perfil. Isso responde "o que está
exposto e parece desatualizado/mal configurado" — não "o que dá para
explorar".

## 8. Validação manual

Toda saída automatizada (Nuclei, Nikto, gobuster/ffuf, whatweb, heurística de
WAF/CDN) pode conter falsos positivos e falsos negativos. Nenhum achado vai
para o relatório final sem reprodução/confirmação manual — ver
`docs/REPORTING.md`.

## 9. Relatório

Use `scripts/report-summary.sh <pasta>` para consolidar uma pasta de
`reports/` em um `summary.md` com achados, possíveis falsos positivos,
recomendações defensivas e próximos passos. Rode
`scripts/sanitize-reports.sh <pasta>` antes de enviar qualquer relatório a
terceiros.

## 10. Correção/reteste

Compartilhe o relatório com o responsável pelo ambiente, com recomendação de
correção por achado. Depois da correção, reteste especificamente o que foi
corrigido (não é necessário repetir tudo) para confirmar a remediação.

## O que esta metodologia explicitamente não cobre

Engenharia social, phishing, físico, brute force de credenciais, exploração
ativa de vulnerabilidade encontrada, movimentação lateral, persistência,
exfiltração de dados real, ou qualquer simulação de adversário com ação
destrutiva. Esses tipos de teste exigem escopo, ferramental, contrato e
processo de autorização específicos — fora do que este toolkit foi desenhado
para fazer (ver `docs/SAFETY.md`).
