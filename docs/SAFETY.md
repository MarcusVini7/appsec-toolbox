# Segurança operacional e limites de uso

Este documento define os limites obrigatórios de uso do `appsec-toolbox`.
Eles existem para manter o projeto como uma ferramenta de **validação
controlada e auditoria autorizada** — nunca como ferramenta ofensiva.

## 1. Autorização explícita é obrigatória

- Use os scripts apenas em ambientes que você possui, ou em ambientes para
  os quais você tem autorização explícita e por escrito do responsável.
- "Por escrito" significa um documento, e-mail ou contrato que comprove o
  escopo e o período autorizados — não uma combinação verbal.
- Nunca teste sistemas de terceiros sem essa permissão, mesmo que o sistema
  pareça mal configurado, exposto publicamente, ou "óbvio de testar". Estar
  acessível na internet não é autorização.
- Se você não tem certeza se está autorizado para um alvo específico, não
  rode os scripts contra ele.

## 2. Rate limiting e timeouts são obrigatórios

- Todo scan deve ter limite de tempo (`timeout`) e, quando aplicável, limite
  de taxa de requisições (`rate-limit`/`-rate`).
- Os valores padrão dos scripts já são conservadores
  (ex.: Nuclei rápido = rate-limit 30, timeout total 60s; Nuclei completo =
  rate-limit 10). Não aumente agressivamente esses valores contra sistemas
  que não sejam seus, mesmo com autorização — combine limites com o
  responsável pelo ambiente antes de qualquer ajuste.
- Nunca remova os limites de tempo dos scripts para "rodar até terminar"
  contra um alvo de terceiros.

## 3. Nada de brute force real ou exploração ativa

O que este projeto explicitamente **NÃO faz**, mesmo com autorização e mesmo
em perfil `deep`:

- Não altera dados da aplicação/alvo.
- Não derruba serviço (sem DoS, sem flood, sem ataque de exaustão).
- Não faz bypass real de autenticação/controle de acesso.
- Não persiste acesso (sem implantes, sem webshells, sem backdoor, sem C2).
- Não rouba ou tenta extrair credenciais reais.
- Não executa payload malicioso.
- Não faz brute force de login/senha (nenhum script usa wordlist de senha).
- Não faz evasão de detecção/WAF.

Os scripts deste projeto fazem reconhecimento e enumeração básica (headers,
fingerprint, descoberta de conteúdo com wordlists públicas de caminhos —
nunca de senha —, varredura de portas, checagem de configuração TLS,
templates de detecção do Nuclei com `-ni` para evitar OAST/interactsh).
Isso vale para todos os perfis (`safe`, `normal`, `deep`) — perfil mais
intenso significa mais cobertura/profundidade de detecção, não mais
agressividade ofensiva.

Não adicione a este projeto módulos de força bruta de credenciais,
exploração ativa, payloads destrutivos, bypass de WAF/autenticação,
técnicas de evasão de detecção, ou qualquer mecanismo de persistência. Se
uma tarefa exigir esse tipo de ação, ela está fora do escopo deste toolkit
e deve ser conduzida — se autorizada — com ferramentas e processo
apropriados, fora deste repositório.

## 4. Não testar terceiros sem permissão

- Isso vale também para subdomínios, IPs vizinhos, CDNs e infraestrutura
  compartilhada que apareçam incidentalmente durante um teste. Autorização
  para um domínio não é autorização para tudo que está na mesma rede.
- Em dúvida sobre o escopo, pare e confirme com o responsável antes de
  continuar.

## 5. Não commitar dados sensíveis

Nunca adicione ao repositório:

- Relatórios reais (qualquer coisa dentro de `reports/`, exceto `.gitkeep`).
- Listas de alvos reais (qualquer coisa dentro de `targets/`, exceto
  `.gitkeep` e `targets/example-targets.txt`).
- Arquivos `.env`, chaves privadas, certificados (`.key`, `.pem`, `.crt`,
  `.p12`), tokens de API, dumps de banco (`.sql`, `.dump`) ou backups
  (`.bak`, `.old`, arquivos compactados).
- Capturas de tráfego (`tcpdump`/`tshark`) contendo dados de produção ou de
  terceiros.

O `.gitignore` do projeto já bloqueia essas categorias por padrão. Antes de
qualquer commit, confira com:

```bash
git status --ignored -sb
git ls-files
```

Se algo sensível aparecer rastreado (`git ls-files`), remova-o do
versionamento antes de fazer push.

## 6. Perfil de exposição e indicações de WAF/CDN ainda são passivos

O `web-check.sh` inclui duas etapas adicionais voltadas a avaliar exposição de
rede e proteção de borda (úteis para discutir risco de LGPD com o cliente:
"existe firewall/WAF na frente disso?"):

- **Perfil de exposição** (`nmap --top-ports 100`): apenas identifica quais
  serviços estão acessíveis nas 100 portas mais comuns. Não tenta autenticar,
  explorar ou interagir com nenhum serviço encontrado além da detecção de
  versão padrão do nmap.
- **Indícios de WAF/CDN**: análise heurística que olha apenas os headers HTTP
  já coletados, sem enviar nenhuma requisição adicional ou payload. Não
  confirma presença/ausência de proteção com certeza — é um indicador, não um
  veredito.

Estes recursos **não** abrem a porta para exploração ativa: a regra 1 deste
documento continua valendo integralmente. Identificar que uma porta está
aberta ou que nenhum WAF foi detectado não autoriza tentar explorar o que foi
encontrado — isso continua exigindo escopo, ferramenta e processo separados
(fora deste toolkit), com autorização específica para esse tipo de teste.

## 7. Verifique antes de compartilhar relatórios

Relatórios podem conter detalhes do alvo, headers internos, ou caminhos
descobertos. Trate-os como confidenciais e compartilhe apenas com quem
precisa deles — normalmente o próprio responsável pelo ambiente testado.
