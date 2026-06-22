.PHONY: check lab-up lab-down scan-local headers-local tls-local

check:
	bash scripts/check-tools.sh

lab-up:
	bash scripts/start-local-lab.sh

lab-down:
	bash scripts/stop-local-lab.sh

scan-local:
	bash scripts/web-check.sh http://127.0.0.1:8080 safe

headers-local:
	bash scripts/headers-audit.sh http://127.0.0.1:8080

# O laboratório local (nginx:alpine) não expõe HTTPS. Para testar TLS,
# defina TLS_TARGET com um alvo HTTPS próprio ou autorizado, ex.:
#   make tls-local TLS_TARGET=https://dominio-autorizado.com
TLS_TARGET ?= https://example.com

tls-local:
	bash scripts/tls-audit.sh $(TLS_TARGET)
