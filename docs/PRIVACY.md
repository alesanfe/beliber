# Privacidad y datos

## Qué datos trata

| Dato | Dónde | Por qué | Sensible |
| --- | --- | --- | --- |
| `pid` (random local) | cliente + host (ladder) | clave anónima del ELO | pseudónimo |
| `tok` | cliente + host | credencial anti-suplantación | **secreto** |
| nick | sala (volátil) + `ratings.name` (display) | mostrar quién juega | elegido por el usuario |
| chat | solo en memoria de la sala | comunicación | no se persiste |
| saves/stats | `user://` local | continuidad local | solo en el PC del jugador |

## Principios aplicados

- **Minimización:** sin correo, sin cuentas, sin telemetría, sin
  analytics, sin IPs persistidas (solo viven en `peers` en RAM).
- **Sin tracking:** el host no loguea nicks ni mensajes — el
  heartbeat solo cuenta volúmenes.
- **Eliminación:** borrar `user://Beliber` elimina todo lo local; en
  el host, borrar la entrada del pid en `ratings`/`idtokens`.
- **Consentimiento:** ninguno necesario — no hay tratamiento de
  datos identificables más allá del nick autodeclarado en cada sala.
- **Retención:** `idtokens`/`ratings` persisten hasta borrado manual
  del operador (documentado en RUNBOOK).

## Transporte

`wss://` está soportado (env `BELIBER_TLS_*`); `ws://` plano es para
LAN/grupos de confianza — el token del ladder viaja en `create`/
`join`, así que **exponer el host a internet exige wss:// o un proxy
TLS** (ver SECURITY.md/THREAT_MODEL.md).
