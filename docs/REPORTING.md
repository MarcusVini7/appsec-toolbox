# Como interpretar os relatórios

Os scripts deste projeto produzem saída automatizada (headers, fingerprint,
enumeração de conteúdo, varredura de porta pontual, resultados de Nuclei e
testssl). Esta saída é um **ponto de partida**, não um veredito. Este
documento explica como ler esses relatórios com critério.

## 1. Finding vs. falso positivo

- **Finding (achado)**: uma observação que, após validação manual, se
  confirma como uma condição real e relevante para a segurança do alvo
  (ex.: um header de segurança realmente ausente em produção, um caminho
  sensível realmente acessível, uma versão de software realmente vulnerável
  e confirmada).
- **Falso positivo**: uma detecção automática que não reflete um problema
  real. É comum em ferramentas baseadas em assinatura/template (Nuclei,
  Nikto) e em heurísticas (ex.: ausência de um header pode ser intencional e
  mitigada de outra forma, como em uma CDN na frente da aplicação).
- Regra prática: nenhuma linha de saída de `nuclei.txt`, `gobuster-common.txt`,
  `whatweb.txt` ou `testssl.txt` deve ser citada em um relatório final sem
  antes ter sido confirmada manualmente (reproduzida, inspecionada, ou
  contextualizada).

## 2. Validação manual é sempre necessária

Todo `summary.md` gerado por `web-check.sh` (e os demais scripts) termina com
um aviso de que os resultados precisam de validação manual. Isso é
proposital: este toolkit prioriza recall (não deixar passar sinais) sobre
precisão automática. Antes de reportar algo:

1. Reproduza a observação manualmente (ex.: confira o header com `curl -sI`
   de novo, abra o caminho encontrado pelo gobuster no navegador).
2. Confirme a versão/configuração real do serviço, quando relevante.
3. Avalie o impacto no contexto da aplicação — não apenas a presença da
   condição.

## 3. Severidade é contextual

- As severidades reportadas por ferramentas como o Nuclei (`low`, `medium`,
  `high`, `critical`) refletem uma classificação genérica do template, não o
  impacto real no seu contexto.
- Um header ausente pode ser irrelevante em uma API interna sem dados
  sensíveis e crítico em um login público. Avalie sempre: exposição
  (quem acessa o alvo), dado em risco, e mitigação existente em outra camada
  (ex.: WAF, CDN, segmentação de rede).
- Ao registrar um achado em um relatório final, ajuste a severidade ao
  contexto real, e documente o raciocínio — não copie a severidade da
  ferramenta sem revisão.

## 4. Como registrar evidência sem vazar segredo

- Inclua apenas o necessário para comprovar o achado (ex.: a linha de header
  relevante, o trecho da resposta), não a captura completa quando ela
  contiver dados sensíveis adicionais (tokens de sessão, cookies de outros
  usuários, dados pessoais).
- Redija/oculte valores sensíveis em prints e trechos de log antes de
  compartilhar (ex.: substitua o valor de um token por `[REDACTED]`).
- Nunca cole tokens, senhas ou chaves reais em relatórios, tickets ou
  mensagens — nem mesmo "temporariamente para mostrar o problema". Descreva
  o problema e, se for indispensável demonstrar, use um valor de exemplo.
- Mantenha os relatórios brutos (pasta em `reports/`) fora do controle de
  versão e em um local de acesso restrito — eles não são versionados neste
  repositório (veja [`docs/SAFETY.md`](SAFETY.md)).
- Ao compartilhar um relatório final com o cliente/responsável, prefira um
  documento resumido e revisado em vez dos arquivos brutos das ferramentas.

## 5. Ferramentas de apoio

- `scripts/report-summary.sh reports/<pasta>` consolida uma pasta de
  relatório em um `summary.md` com achados, possíveis falsos positivos,
  recomendações defensivas e próximos passos.
- `scripts/sanitize-reports.sh reports/<pasta>` varre a pasta por padrões
  sensíveis (tokens, JWT, cookies de sessão, chaves privadas, e-mails, IPs
  internos) e gera `sensitive-findings.txt`. Rode isso **antes** de
  compartilhar qualquer relatório para fora do ambiente de trabalho — ele
  só alerta, não remove nada automaticamente.
