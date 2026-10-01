# Dependencias

Inventario completo — Beliber deliberadamente tiene una superficie de
suministro mínima.

## Runtime

| Dependencia | Versión | Uso |
|---|---|---|
| Godot Engine | 4.7.x (probado 4.7.2 stable) | Motor completo — la app no importa ninguna librería externa; solo `class_name` propios y API del engine. |
| Python `websockets` | ==13.1 (`server/requirements.txt`) | Solo `server/relay.py` y los tests WS. El host autoritativo (`host.gd`) NO la necesita — es Godot puro. |

Sin paquetes GDScript de terceros, sin addons, sin fuentes/audio assets
externos (la UI usa glifos Unicode de ajedrez sobre fuentes del sistema;
el sonido es sintetizado). Las imágenes en la raíz y `tools/` son
**documentación de diseño** (hojas escaneadas + recortes), no assets del
runtime.

## Toolchain / CI

| Herramienta | Uso |
|---|---|
| GitHub Actions + `actions/setup-python` | CI |
| `pip-audit` | Auditoría de `websockets` (no bloqueante) |
| `cyclonedx-bom` | SBOM de las deps Python como artefacto CI |
| `gitleaks` | Escaneo de secretos en el repo |
| Godot export templates 4.7.2 | Solo para el workflow de release |

## Reglas para añadir dependencias

1. Ninguna sin justificación — la superficie actual es deliberada.
2. Versiones pineadas, sin `latest`/rangos abiertos.
3. La dep debe existir ≥7 días publicada (evita supply-chain fresca).
4. Registrarla aquí y en el CI correspondiente.
