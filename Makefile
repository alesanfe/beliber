# Makefile — Beliber
# Juego Godot 4 (game/) + relay/host de red en Python (server/).
# Requiere: godot en PATH (o GODOT=<ruta>), python, bash.
# Uso: make help

GODOT ?= godot
PY    ?= python

.DEFAULT_GOAL := help
.PHONY: help setup-server \
        run \
        test test-engine test-playthrough test-ui test-e2e test-net test-server test-load \
        relay host \
        shots export-windows export-web \
        test-all lint release clean

# ============================================================
#  HELP / SETUP
# ============================================================

help: ## Muestra esta ayuda
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | sort | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

setup-server: ## Instala las deps Python del relay/tests (websockets)
	pip install -r server/requirements.txt

# ============================================================
#  JUEGO
# ============================================================

run: ## Abre el juego (igual que F5 en el editor)
	$(GODOT) --path game

# ============================================================
#  TESTS (headless)
# ============================================================

test: test-engine test-playthrough test-ui test-e2e test-server ## Batería completa local

test-engine: ## Motor + regresiones
	$(GODOT) --headless --path game -s res://tests/run_tests.gd

test-playthrough: ## Partidas bot-vs-bot
	$(GODOT) --headless --path game -s res://tests/playthrough.gd

test-ui: ## Smoke de UI
	$(GODOT) --headless --path game -s res://tests/_smoke.gd

test-e2e: ## Partida por clicks (E2E)
	$(GODOT) --headless --path game -s res://tests/e2e.gd

test-net: ## E2E de red: 2 clientes a través del relay (requiere relay)
	$(GODOT) --headless --path game -s res://tests/e2e_net.gd

test-server: ## Tests Python del servidor (relay + host + ladder)
	$(PY) server/test_relay.py && $(PY) server/test_host.py && $(PY) server/test_ladder.py

test-load: ## Test de carga del relay
	$(PY) server/test_load.py

test-all: ## Batería canónica completa (tools/test_all.sh)
	bash tools/test_all.sh

lint: ## gdlint sobre src/server/tests (opcional en test_all.sh)
	gdlint game/src game/server game/tests

# ============================================================
#  RED
# ============================================================

relay: ## Levanta el relay no-autoritativo en :7778
	$(PY) server/relay.py

host: ## Levanta un host autoritativo Godot — uso: make host PORT=7779
	$(GODOT) --headless --path game -s res://server/host.gd -- $(or $(PORT),7779)

# ============================================================
#  ASSETS / RELEASE
# ============================================================

shots: ## Capturas de UI — uso: make shots SHOTS="nombre1 nombre2"
	$(GODOT) --path game -s res://tools/screenshots.gd -- $(SHOTS)

export-windows: ## Exporta el preset "Windows Desktop" a builds/windows/
	$(GODOT) --headless --path game --export-release "Windows Desktop" builds/windows/beliber.exe

export-web: ## Exporta el preset "Web" a builds/web/
	$(GODOT) --headless --path game --export-release "Web" builds/web/index.html

release: ## Empaqueta la release — uso: make release VER=x.y.z
	pwsh tools/release.ps1 $(VER)

clean: ## Borra caches y salidas de trabajo (mantiene builds/)
	find . -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null || true
	rm -rf tools/_shots/*
