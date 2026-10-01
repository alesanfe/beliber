# Análisis de competencia — Beliber

Investigación de juegos similares (ajedrez asimétrico / ejércitos distintos)
y lecciones aplicables al diseño y la implementación.

## Referentes directos

### 1. Chess with Different Armies (Ralph Betza, 1979)
El padre del género. 4 ejércitos "iguales en fuerza pero distintos en
propiedades": Fabulous FIDEs, Colorbound Clobberers, Nutty Knights,
Remarkable Rookies. Reyes y peones idénticos en todas las facciones.

**Lecciones para Beliber:**
- Betza mantuvo reyes y peones iguales en todas las facciones
  *deliberadamente*: facilita aprender el juego. Beliber va más lejos
  (todo es distinto) — compensar con el editor y los highlights de color.
- Regla de equilibrio de Betza: no hace falta que cada pieza valga igual,
  basta que el **ejército entero** se compense (±10% por pieza).
- Buypoint Chess (Betza): el sistema de "puntos" de las hojas de Beliber
  (1–8 por pieza) ya imita esto. Usar la suma de valores como indicador
  de equilibrio del ejército en la UI.

### 2. Chess 2 (Sirlin & Burns, 2014) — Steam/Ouya
6 ejércitos asimétricos + dos innovaciones clave:
- **Midline Invasion**: ganas si tu rey cruza el centro. Elimina las
  tablas y los finales "resueltos" de libro.
- **Duelos con piedras**: al capturar, el defensor puede apostar piedras
  para destruir al atacante. Añade lectura de rival y valor dinámico.

**Lecciones:**
- Condición de victoria alternativa = anti-tablas. Beliber usa captura de
  líder (ya es anti-draw), pero se puede añadir "invasión de línea" como
  opción de reglas.
- Los duelos de piedras son un mecanismo de mind-game sobre capturas;
  Beliber ya tiene efectos de respuesta (empujar/atraer/inmovilizar) que
  cubren ese espacio sin necesidad de meta-moneda.

### 3. Chess Evolved Online (CEO)
Ajedrez online con **army-building total**: minions en fila frontal,
champions atrás, presupuesto de ~80–100 puntos, máx. 8 copias de un
minion / 4 de un champion, 16 setups guardables.

**Lecciones (las más aplicables):**
- El **army builder con presupuesto de puntos** es el sueño del jugador de
  Beliber: las piezas ya tienen valores → permitir crear ejércitos propios
  dentro del editor.
- Mostrar en el setup **qué casillas están defendidas** (coverage map).
- "Move decay" para evitar stalls (la partida se pudre si nadie ataca).
- La sinergia del ejército pesa más que el valor individual (igual que
  dice Betza).

### 4. Asymmetric Chess (chessvariants.org)
3 razas: Humanos (lineal), Elfos (saltadores diagonales), Orcos
(saltadores ortogonales). Mismo tablero y misma disposición.

**Lección:** la identidad de facción se define por *estilo de movimiento*
(lineal vs salto vs diagonal). Beliber ya lo hace: Elfos atraviesan,
Kronturs empujan, Aquontes saltan sobre piezas, Mortifers roban, etc.

### 5. Otros
- **Maharajah and the Sepoys**: asimetría extrema (1 pieza vs ejército).
- **Board 8x8 Game Mix**: múltiples condiciones de victoria mezcladas.
- **Chu Shogi / Tenjiku Shogi**: precedente histórico de piezas que
  capturan saltando e inmovilizan (el "Burning Piece" y el "Lion" con
  movimiento doble = nuestro Tritón encadenado / doble apertura Humenex).
- **Interactive Diagram Piece Lab** (chessvariants.com): editor de piezas
  por notación Betza — nuestro editor visual es el equivalente.

## Piezas "parecidas" ya vistas en el folklore (fairy chess)

| Efecto Beliber | Equivalente fairy chess |
|---|---|
| Saltar (morado/cian) | Leapers: Knight (1,2), Camel (1,3), Giraffe (1,4), Zebra (2,3) |
| Deslizar | Riders: Rook, Bishop, Queen, Nightrider (caballo en línea) |
| Atravesar | "Screenless" movimiento estilo Leo/Pao (cañón chino) |
| Empujar | Push-me-pullyu, Ultima/Baroque chess (pincer, coordinator!) |
| Atraer | Coordinator de Ultima, imanes de Magnetic Chess |
| Al paso | Idéntico al ajedrez FIDE |
| Enroque | Idéntico FIDE (con chequeo de casillas atacadas) |
| Salto de Aquonte | Grasshopper / Cañón (Xiangqi/Korean cannon): salta sobre 1 pieza |
| Cadena (Tritón) | Lion de Chu Shogi (doble movimiento) |
| Robo de movimiento | Mimic/Copycat de variantes; "Diplomat" de Baroque |
| Inmovilizar | "Basilisk" / piezas paralizantes de fairy chess |
| Doble líder | Two Kings army de Chess 2 |

## Recomendaciones concretas para Beliber

1. **Contador de valor del ejército** en la selección de facción
   (suma de puntos) — transparencia de equilibrio.
2. **Coverage map** opcional: casillas atacadas/defendidas en color tenue.
3. **Army builder** (fase 2 del editor): presupuesto de puntos + límites
   8/4 como CEO → modo "ejército personalizado".
4. **Regla anti-stall**: si N turnos sin captura, opción de tablas o
   victoria por "material" (suma de valores restantes).
5. **Segunda condición de victoria** opcional estilo midline invasion
   (llevar líder a la última fila enemiga).
6. Notación de movimientos en el log ya existe — añadir export PGN-like
   para compartir partidas (los códigos de pack SKM del Sokoban mutante
   son buen precedente en este mismo workspace).

## Estado del diseño actual

Beliber ya supera a la competencia en expresividad del editor: la
competencia usa notación Betza textual; nosotros pintamos el mismo
diagrama de colores que define las piezas — ventaja clara de UX.

## Extraccion de funcionalidades (catalogo general de ajedrez)

De las plataformas y juegos listados, esto es lo que aplica a Beliber,
ordenado por prioridad y viabilidad en el proyecto actual (local, sin red).

### Ya implementado
- Log de movimientos (todas las plataformas)
- Mapa de cobertura (Chess Evolved Online)
- Valor de ejercito visible en HUD (valoracion de material, clasica)
- Invasion de linea ~ "King of the Hill" de Lichess
- Constructor de ejercito con presupuesto ~ CEO / army draft
- Dos despliegues por faccion ~ Chess960-lite (aleatoriedad controlada)
- Tablas por estancamiento ~ regla de 50 movimientos de FIDE
- Editor visual de piezas ~ chessvariants PieceLab

### Imprescindibles de un juego de tablero (pendientes, baratas)
1. **Deshacer jugada** (undo) — estandar en Lucas Chess, Chess Lv.100.
   El motor ya tiene BoardState copiable; basta guardar pila de estados.
2. **Resaltar ultimo movimiento** (from/to en amarillo tenue) — universal
   en Chess.com/Lichess.
3. **Indicador de "lider en peligro"** — equivalente al aviso de jaque:
   marcar al lider si esta siendo atacado.
4. **Reloj configurable** (rapido/blitz/bullet o por turno) — trivial:
   timer por jugador en TurnManager, timeout = victoria por tiempo.
5. **Rendirse / nueva partida** con confirmacion — ya existe Nueva partida;
   falta "Rendirse" explicito.
6. **Exportar partida** — notacion compacta (origen-destino + efecto) a
   fichero de texto, como el PGN; el log ya existe.

### Recomendables (coste medio)
7. **Bot/IA simple** — minimax con evaluacion de material+lider; DroidFish/
   Stockfish nivel 1 como inspiracion, no necesitamos motor externo.
8. **Replay de la partida** — recorrer el log (flechas atras/adelante).
9. **Sugerencia de jugada** — resaltar un movimiento "bueno" (eval de
   material post-jugada), estilo Aimchess/DecodeChess simplificado.
10. **Animacion de captura/movimiento** — transicion suave estilo Battle
    Chess lite (sin cinematica, solo slide+fade).
11. **Sonidos** — click de pieza, captura, victoria. Assets CC0 de kenney.nl.
12. **Resumen post-partida** — material capturado por bando, nº movimientos,
    tiempo (si hay reloj), estilo pantalla de resultados de Chess.com.

### Solo relevantes si se hace online (fase futura)
- Emparejamiento, ELO/clasificacion, torneos (Chess.com, ICC, FIDE Arena)
- Ajedrez por correspondencia (GameKnot, Red Hot Pawn)
- Espectadores, chat, clubs

### Irrelevantes o ya superados por el diseno de Beliber
- Bases de datos de aperturas (ChessBase): Beliber tiene despliegues
  por faccion, no "teoria de aperturas" trasladable.
- Repeticion espaciada/cursos (Chessable): es producto educativo, no juego.
- Variantes exoticas (5D, atomic, crazyhouse): Beliber ES la variante;
  el editor ya permite definir comportamientos equivalentes.
- Auto-battlers (Auto Chess, TFT): genero distinto.
- Chess960 aleatorio: el army builder + 2 equipos cubren la variabilidad.

### Conclusion
Lo que falta para que Beliber "se sienta" como un juego de ajedrez
profesional es barato y local: **deshacer, ultimo movimiento, peligro al
lider, reloj, rendirse, exportar partida, bot simple y animaciones**.
Todo eso cabe en el motor/UI actual sin tocar las reglas.

## Oleada 3 - herramientas de analisis y partida local

Implementado:
- Arrastrar y soltar piezas (drag&drop) ademas de clic-clic.
- Flechas de analisis y marcas de casilla con boton derecho
  (clic = ciclar color; arrastre = flecha; repetir = borrar).
- Premove contra la IA (programar jugada durante el turno rival).
- Zoom del tablero (slider 0.7x-1.4x).
- Velocidad de animacion configurable (lenta/normal/rapida/off).
- Entrada por teclado en notacion de coordenadas (e2e4).
- Indicador de amenazas: punto rojo en piezas propias atacadas.
- Personalidades de IA: equilibrada / agresiva / defensiva.
- Errores humanos simulados: blunders por nivel (25%/10%/0%).
- Handicap temporal: la IA juega con la mitad de tiempo.
- Editor de posiciones libre: colocar piezas de ambas facciones,
  elegir quien mueve primero, validacion de lideres, jugar desde ahi.
- Tiempos por jugada registrados (move_times) para estadisticas.
- Perft (conteo de movimientos) como test de regresion del motor.
- Auto-giro del tablero en hotseat; revancha con cambio de bandos.
- Replay navegable de la partida (snapshots por jugada).
- Temas de tablero (3 paletas).

Pendiente deliberado (requiere diseno/servidor):
- Online, torneos, ELO, antitrampas, espectadores, chat.
- 3D/VR, cosmeticos, campana narrativa, logros.
- Cursos/aperturas con repeticion espaciada (producto educativo).
- Tablebases, MultiPV, integracion UCI con Stockfish real.

## Oleada 4 - acabado de plataforma local

Implementado:
- Barra de evaluacion del motor propio en el HUD (Eval +N/-N/=).
- Modo ciego (oculta las piezas, memoria pura).
- Confirmacion de jugada: primer clic = vista previa verde,
  segundo clic = ejecutar.
- Ocultar coordenadas.
- Exportar el tablero a PNG (user://beliber_board.png).
- Mute de sonido.
- Ajustes persistentes (tema, zoom, animacion, amenazas, coords,
  ciego, confirmar, mute) en user://beliber.cfg.
- Estadisticas persistentes en user://beliber_stats.json:
  partidas totales, victorias por faccion, logros.
- Logros: primera victoria, cazador (5+ capturas), vencer a la
  IA nivel 3, cinco partidas, victoria en <15 movimientos.
- Tiempos por jugada registrados para futuras estadisticas.

Lo que deliberadamente NO se implementa (requiere servidor):
matchmaking, ELO/Glicko, torneos online, correspondencia,
espectadores, chat, antitrampas, cuentas, sincronizacion nube.

## Oleada 5 - online (ENet embebido)

Servidor dentro de la app: un jugador hace de host (Crear partida),
el otro se une por IP:puerto (Unirse). Funciona en LAN o con el
puerto abierto en internet.

- Host = J1, cliente = J2. El host configura la partida (facciones,
  equipo, reglas, reloj) y se la envia al cliente por RPC.
- Solo viajan las jugadas; el estado es determinista en ambos lados.
- El lado local solo puede mover en su turno (net_me); el analisis
  con boton derecho sigue funcionando siempre.
- Deshacer deshabilitado online (desincronizaria los clientes).
- Rendicion sincronizada mediante RPC.
- Desconexion del rival = victoria automatica.
- Sin cuentas ni matchmaking: es P2P directo, no un lobby.

Para hacerlo publico-internet serio harian falta: relay/STUN,
salas con codigo, reconexion con estado completo y un servidor
autoritativo que valide las jugadas.

## Oleada 6 - servidor relay WebSocket (salas + reconexion)

server/relay.py: relay Python (websockets) con salas por codigo.

- Sala = codigo de 4 chars; host = lado 0, join = lado 1.
- El host define la config (facciones, equipo, reglas, reloj) y el
  servidor se la entrega al cliente al unirse.
- Jugadas retransmitidas + archivadas en el servidor.
- Reconexion: cada lado tiene un token; rejoin devuelve el historial
  completo (resync) y el cliente lo reproduce localmente.
- Aviso rival offline/online; salas vacias expiran a las 4 h.
- Test: server/test_relay.py (12 checks, todos verdes).

Cliente (main.gd): campos Servidor/Codigo + botones Sala/Entrar.
Jugadas serializadas a JSON (Vector2i -> {x,y}). Si la conexion cae,
'Entrar' con el mismo codigo y vacio reenvia 'rejoin' con el token.

Limitaciones: el servidor reenvia sin validar reglas (la confianza
esta en los clientes); sin cuentas ni matchmaking — eso requeriria
auth y un backend de emparejamiento aparte.

## Oleada 7 - servidor autoritativo (arbitro Godot)

game/server/host.gd — el propio juego en headless actua como
servidor WebSocket y valida cada jugada con el motor real
(TurnManager + MoveGen). Ya no es un relay: es el arbitro.

    godot --headless --path game -s server/host.gd [puerto=7779]

- El cliente envia solo la intencion {"op":"play","from","to"}.
- El servidor resuelve la jugada legal (o la rechaza), la aplica al
  TurnManager de la sala y difunde la jugada completa a ambos.
- Un cliente modificado ya no puede colar jugadas ilegales.
- Rendicion y resultado tambien los decide el servidor.
- Reconexion con token + resync del historial resuelto.
- El cliente detecta el modo autoritativo por el saludo "hello"
  (el relay Python no lo envia) y no aplica la jugada localmente:
  espera el eco del servidor (defer_play).
- Mismo protocolo de salas que el relay; conviven ambos servidores.

Test: server/test_host.py — 8/8 checks verdes contra el arbitro real.

---

# Analisis competitivo profundo (ronda 2)

Beliber no compite solo con plataformas de ajedrez: su naturaleza
asimetrica (8 facciones con reglas distintas) lo pone frente a
juegos de ejercitos y tactica por turnos. Matriz actualizada.

## Chess Evolved Online (el mas cercano)

| Feature CEO | Beliber |
|---|---|
| 500+ piezas coleccionables | 8 facciones x ~6 piezas, editor de piezas |
| Ejercito: max 8 minions/4 champions, presupuesto 80→100 | ✓ Army builder con presupuesto |
| Army Profile: huecos defensivos, stats ataque/magia | Parcial: cobertura de ejercito |
| Test Area: probar ejercito contra IA o IA-vs-IA | ✓ IA e IA-vs-IA funcionan con ejércitos custom |
| Ranked ELO por rating, rangos (Novato→GM) | ✓ Ladder ELO en host autoritativo (pid local) |
| Desafios diarios PvE, escenarios | ✓ Desafío diario determinista + Puzzle Rush |
| Draft mode | ✓ Draft con presupuesto (draft.gd) |
| Unlocks por rating (progresion) | Logros locales basicos |
| Cero RNG en PvP | ✓ determinista puro |

**Brecha principal**: progresion/meta (coleccion, desafios diarios,
rangos) y el "Army Profile" con test contra IA.

## Root (asimetria referente)

| Feature Root | Beliber |
|---|---|
| Cada faccion con victoria propia | ✓ todas = eliminar lider (variante: linea media) |
| IAs "Clockwork" por faccion (comportamientos distintos) | ✓ arquetipo "auto" por facción (FACTION_STYLE) |
| Campana/tutorial interactivo por faccion | ✓ tutorial guiado + guía interactiva (guide.gd) |
| 58 logros Steam | 5 logros locales |
| Modo cooperativo vs IA | ✓ modo co-op (2 humanos alternan el bando J1) |
| Mapas variados | Tablero fijo 8x8 |

## Duelyst II (tactica por facciones)

| Feature | Beliber |
|---|---|
| 6 facciones con estilo claro (aggro, control, combo…) | ✓ 8 con estilos marcados |
| Nombre/identidad de estrategia por faccion | ✓ arquetipos en FACTION_STYLE + guía |
| Coleccion/progresion | ✓ XP por facción + niveles + logros |
| Animaciones de combate llamativas | Basico: squash, sonidos, confetti no hay |
| Ranked ladder | ✓ ladder ELO en host (grupo privado) |

## Prismata (modelo de producto)

| Feature | Beliber |
|---|---|
| Bots con ELO propio | 3 niveles sin rating medido |
| Puzzles generados | ✓ puzzles + rush + diario (puzzles.gd) |
| Emotes/chat | ✓ chat en UI online (ENet y WS) |
| Eventos/torneos | Falta |
| Blitz + "tiempo por turno" | Reloj de partida, no por-turno aparte |
| Zero pay-to-win | ✓ |

## lichess / chess.com (plataforma ajedrez)

Cubierto en ronda 1. Lo que ya esta: reloj+incremento, analisis
(flechas, amenazas, eval, cobertura), replay, premove, editor,
IA multinivel, tablas por repeticion/material/anti-stall, online
ENet+relay+arbitro, logros, estadisticas.

Falta relevante: tablebase, aperturas con nombre,
analisis post-partida por jugada (errores), correspondencia.
(Puzzle mode ya existe — puzzles.gd con rush y desafío diario.)

## Shotgun King / Pawnbarian / 5D Chess (variantes roguelike)

Estos venden la fantasía de "ajedrez pero roto": escopetas,
cartas de mazmorra, lineas temporales. Beliber podria tener un
**modo roguelike**: run con eleccion de faccion, modificadores entre
combates (ej. "tus guerreros empujan doble"), dificultad escalando.
Es la diferenciacion mas barata y con mas potencial viral.

## Prioridades derivadas del analisis

1. **IA-vs-IA / Test Area del constructor** (CEO lo tiene, es gratis
   de implementar con el bot actual).
2. **Arquetipo por faccion en la UI** (Root/Duelyst: saber de un
   vistazo como juega cada raza).
3. **Desafios diarios con seed** (Prismata/CEO: contenido eterno
   sin servidor; el generador de posiciones ya existe).
4. **Analisis post-partida por jugada** (lichess: errores,
   mejor jugada, precision) — con evaluate() ya disponible.
5. **Emotes/chat UI** (protocolo ya soporta chat).
6. **Modo roguelike/run** (diferenciador tipo Shotgun King).
7. **Tutorial guiado por faccion** (Root "walkthrough").
8. Matchmaking+ELO con cuentas → solo cuando haya backend serio.

## Oleada 8 - inspirado en competidores (implementado)

- IA vs IA (Test Area de CEO): el bot juega ambos lados; el humano
  es espectador. Sirve para evaluar ejercicios del constructor.
- Arquetipo por faccion (Duelyst/Root): el menu muestra el estilo de
  cada raza con su color (ej. "Combo corruptor", "Muro y martillo").
- Desafio diario (Prismata/CEO): combinacion determinista por fecha —
  facciones, equipo, regla de linea, reloj y nivel de IA siempre
  iguales para todo el mundo ese dia. Se guarda en stats.
- Analisis post-partida por jugada (lichess): se evalua cada
  posicion del replay y se reporta el mayor error de cada jugador.
- Chat online: LineEdit en el HUD; funciona por WebSocket y por ENet.
- Modo Run (Shotgun King): racha de combates contra la IA; cada
  victoria sube el nivel del rival y permite elegir una bendicion
  (rival con mas fallos / +60s / iniciativa). Mejor racha persistida.

## Oleada 9 - ladder, guia y puzzles (implementado)

- Ladder ELO en el arbitro autoritativo: nick en create/join,
  resultado registrado al ganar/rendirse/abandonar, persistido en
  user://beliber_ratings.json (K=32). Op "ladder" devuelve el top 20;
  el cliente muestra ELO de ambos tras la partida. Sin cuentas ni
  auth: los nicks son libres (suficiente para un grupo privado).
- Guia interactiva por faccion (guide.gd): ejercito desplegado,
  arquetipo, reglas especiales y lista de piezas; clic en cualquier
  pieza (de cualquier bando) muestra su patron real.
- Puzzles tacticos (puzzles.gd): posiciones generadas por juego
  aleatorio donde existe captura de lider en 1; el jugador debe
  encontrarla, fallar deshace. Contador de resueltos.
- Tests: puzzle detection (2 checks) + test_ladder.py (6 checks).

---

# Analisis de INTERFAZ frente a competidores (ronda 3)

## lichess / chess.com — la referencia en UI de ajedrez

| Elemento UI | Ellos | Beliber (estado) |
|---|---|---|
| Lista de jugadas | Tabla scrolleable, clic = saltar a la posicion | Cola de texto (ultimas 16) |
| Piezas capturadas | Bandeja de iconos + dif de material junto al nombre | Texto "Capturado J1: …" |
| Barra de eval | Barra vertical blanco/negro junto al tablero | Texto "Eval +N" |
| Reloj | Bloque grande sobre/bajo el tablero, rojo a <10s | Texto en el lateral |
| Hover | Casilla resaltada + tooltip de pieza | Nada |
| Move feedback | Glifo de clasificacion (!? ?!) en la notacion | Solo "x" y describe() |
| Zen mode | Ocultar todo menos el tablero | No |
| Sonidos | set por accion (move/capture/check/threat) | 3 beeps |
| Notacion | SAN clickeable | describe() propio |
| Colores de flechas | shift/ctrl/alt = verde/naranja/azul | Un color + marcas |
| Vista previa origen | La casilla origen se resalta al arrastrar | Solo la pieza fantasma |

## Chess Evolved Online — UI para piezas desconocidas (nuestro caso)

- Hover sobre unidad: tooltip con nombre, coste y descripcion de
  habilidades. CRITICO para nosotros: 8 facciones con piezas nuevas
  nadie conoce los patrones de memoria.
- Badge de estado sobre la pieza (inmovilizada, potenciada).
- Panel de ejercito con stats de ataque/defensa/magia.
- Colores de casilla del patron segun efecto — YA lo hacemos igual
  (esa idea era de sus diagramas).

## Duelyst II — feedback tactil

- Screen shake en impactos, sprites animados, mana/acciones claras,
  log descriptivo de cada accion.
- Resumen de carta grande al hover (equivalente a nuestro tooltip).

## Gaps priorizados por impacto visual

1. Tooltip de pieza al hover (nombre + valor + efectos) — CEO.
2. Barra de eval vertical junto al tablero — lichess.
3. Lista de jugadas clickeable que salta al replay — lichess.
4. Bandeja de capturadas con iconos — lichess/chess.com.
5. Reloj rojo/alerta a <10s — lichess.
6. Zen mode (ocultar panel) — lichess.
7. Casilla hover + origen del arrastre resaltado — lichess.
8. Clasificacion !/?/?! por jugada — chess.com.

## Oleada 10 - rediseño visual (implementado)

- Tema oscuro propio (theme.gd): StyleBoxFlat programatico para
  botones, paneles, campos, sliders, scrollbars y checkboxes con
  acento azul; fondo de ventana #14181f. Sin assets externos.
- Modal de fin de partida: overlay oscuro + panel con resultado en
  color de faccion, resumen, analisis y botones Revancha/Ver tablero.
- Piezas con relieve: sombra, disco oscuro + nucleo de faccion +
  arco de luz; arrastre con sombra amplificada.
- Marco del tablero con sombra; menu en dos filas de botones.
- Fix de corrupcion UTF-8 en main.gd (acentos restaurados).

## Oleada 11 - "game feel" UI nativo (implementado)

Tras evaluar los plugins recomendados (Godotwind, SmoothScroll,
ProperUI, Juicee, Kenney Theme, Lucide) se adopta el enfoque nativo —
los plugins de editor de terceros añaden superficie de supply chain y
los asset packs de pago son prematuros sin arte propio:

- juice.gd: pop_in (fade+scale con ease-out-back) para paneles,
  toast con slide+fade autodestructible, hover_pop y squash en
  botones. Equivalente a Godotwind/Juicee sin deps.
- smooth_scroll.gd: ScrollContainer con rueda animada hacia
  objetivo (inercia) — sustituye al plugin SmoothScroll.
- Panel de perfil: stats, % victorias, mejor racha Run y logros.
- Modal de fin de partida con entrada animada.

Pendiente de la lista (valor real pero costoso): iconos Lucide
embebidos, tema Glassmorphism, sonidos UI Kenney/Pixabay — todos
requieren assets externos licenciables, no decisiones de codigo.

## Oleada 12 - estructura de panel estilo chess.com/lichess

- Panel lateral reorganizado en TabContainer: Partida (turno, reloj,
  eval, info, lista de jugadas) / Opciones (toggles, zoom, herramientas)
  / Chat (hud_log + entrada online).
- Tarjeta del rival arriba del panel (faccion + bando, color propio).
- Confirmacion modal antes de rendirse (ConfirmationDialog).
- Variantes de tema UI: Oscuro / Claro / Alto contraste (selector en
  menu, persistido en beliber.cfg, aplica en caliente).
- Indicador de foco visible (anillo de acento) para navegacion Tab.
- Breakpoint compacto: <950 px apila el panel bajo el tablero.
- Aviso de amenaza con '!' (senal no cromatica).
- widgets.gd: componentes primary/secondary/danger/heading/screen.
- juice.gd: pop_in, toast, hover_pop, squash.
- smooth_scroll.gd: scroll con inercia.

## Oleada 13 - feedback de partida + modos (implementado)

- Bandeja de capturadas con glifos (captured_tray.gd): iconos de
  ajedrez ordenados por valor en el color de la faccion victima,
  con diferencial de material "+N" para el que va por delante.
- Reloj: alerta roja <10 s (ya existia) + aviso sonoro al cruzar
  el umbral (una vez por bando, solo si es el humano/local).
- Clasificacion de jugadas estilo chess.com en la lista: swing de
  evaluacion por snapshot -> "!" (delta>=+4), "?" (<=-3), "??" (<=-7),
  coloreado verde/rojo en cada entrada clickeable.
- IA con personalidad de faccion (Clockwork de Root): opcion
  "Auto (faccion)" en el selector de estilo; el bot adopta el
  arquetipo (aggro/defense/normal) de PiecesData.FACTION_STYLE.
  En IA-vs-IA cada bando usa el suyo.
- Tutorial guiado (walkthrough estilo Root): partida real vs IA
  nivel 1 con checklist de objetivos adaptada a la mecanica
  distintiva de la faccion elegida (enroque Humenex, atravesar
  Elfos, combo Consorte, empuje Enanos/Kronturs, salto Aquonte...).
- Modo Draft (CEO): picks alternos J1/J2 con presupuesto = valor del
  ejercito oficial; auto-despliegue (lideres atras, caras al centro,
  baratas delante); sin picks -> despliegue oficial. draft.gd.
- Modo co-op: 2 humanos alternan los movimientos del bando J1
  contra la IA ("Humano A/B mueve" en el HUD).

## Oleada 14 - online publico + feedback (implementado)

- Matchmaking automatico: op "queue"/"dequeue" en relay.py Y en el
  servidor autoritativo host.gd — cola FIFO, al haber 2 se crea sala
  y se fusionan preferencias (faccion propia + reglas comunes).
  Cliente: boton "Buscar" junto a Sala/Entrar.
- Pack de SFX sintetizado por tipo de jugada: captura (golpe grave),
  castillo/cadena (doble tono), push/attract/inmovilizar (barrido
  _sweep), click de seleccion en board_view. Todo via Juice.ui_sfx.
- Aperturas con nombre (lichess-style): hud_opening muestra
  "Apertura - Faccion: Pieza" segun la primera jugada de cada bando.
- Progresion por faccion: XP por partida (+10) y victoria (+30),
  nivel = xp/100, se ve en el menu (Dominio: faccion nvN) y mensaje
  de subida de nivel en el HUD.
- Puzzle Rush: modo contrarreloj 60 s en puzzles.gd — acierto
  auto-regenera, fallo resta 5 s, score final al agotarse.
- Iconos UI procedurales (Icons.draw_ui + IconGlyph + ui_tex):
  swords/gear/chat/trophy/flag/undo/hint/puzzle/book/bolt/back/clock
  aplicados a los botones del menu via apply_icons.
