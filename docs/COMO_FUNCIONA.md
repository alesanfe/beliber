# BELIBER — Cómo funciona el juego + Plan para Godot

> Documento de investigación basado en las 11 imágenes de referencia de la carpeta.
> Beliber es un juego de estrategia por turnos sobre tablero **8x8**, similar al
> ajedrez, pero **asimétrico**: cada jugador controla una facción con piezas,
> movimientos y reglas especiales diferentes.

---

## 1. Concepto general

- Tablero de **8x8 casillas** (como ajedrez).
- **2 jugadores**, cada uno elige una **facción** (hay 8 facciones).
- Cada facción tiene su propio ejército: tipos de pieza únicos, con patrones de
  movimiento propios y 1-2 configuraciones de despliegue inicial (**Eq1 / Eq2**).
- Cada pieza tiene un **valor numérico** (1-9) que se muestra en su diagrama;
  probablemente sirve como coste/puntos del ejército.
- Objetivo general: capturar la pieza líder del enemigo (equivalente al rey).
  Excepción: contra **Bestiarios** hay que derrotar a **ambos líderes**.

---

## 2. Sistema de movimientos (leyenda de colores)

El juego define los movimientos mediante **casillas coloreadas** en los diagramas.
Cada color es un *efecto de movimiento*:

### Efectos base

| Color | Efecto | Descripción |
| --- | --- | --- |
| Amarillo | **Mover** | Colocar la pieza en la casilla solo si está vacía. |
| Rojo | **Capturar** | Colocar la pieza en la casilla solo si hay una pieza enemiga; se captura. |
| — | **Saltar** | El movimiento ignora piezas que bloqueen el paso. |
| — | **Atravesar** | Al pasar por una casilla con pieza puedes capturar o mover a la casilla adyacente. Si la pieza atravesada era enemiga, queda **inmovilizada** (no puede moverse en el próximo turno enemigo). |
| Azul | **Empujar** | Colocar la pieza en la casilla solo si está ocupada; la pieza ocupante se desplaza a la casilla adyacente en la dirección del movimiento. Ignora y atropella (captura) todas las piezas enemigas en el camino. |
| Magenta | **Atraer** | La pieza que ocupaba la casilla es atraída a la casilla adyacente a tu pieza en la dirección correspondiente. Si era enemiga queda **inmovilizada** un turno. |

### Colores combinados

| Color | Significado |
| --- | --- |
| Naranja | "Mover" **o** "Capturar" |
| Cian | "Mover" saltando |
| Verde lima | "Capturar" saltando |
| Morado | "Capturar" saltando o "Mover" saltando |
| Oliva | "Mover" atravesando |
| Rojo oscuro | "Capturar" atravesando |
| Verde oscuro | "Capturar" atravesando o "Mover" atravesando |
| Azul grisáceo | "Mover" o "Empujar" |
| Morado-magenta | "Capturar" o "Empujar" |
| Azul oscuro | "Mover", "Capturar" o "Empujar" |

### Movimientos condicionados

| Color | Condición |
| --- | --- |
| Rosa | **Capturar al paso**: si el enemigo movió un peón en vertical en su último turno y quedó adyacente, mueves tu peón a esta casilla y lo capturas. |
| Verde claro | **Despliegue**: solo si el peón aún no ha movido (equivalente al avance doble del peón). |
| Verde oscuro | **Enroque**: si rey y torre no han movido, no hay casillas amenazadas entre posición inicial y final, y no hay piezas entre ellos. La torre queda adyacente al rey en el lado contrario. |
| Verde brillante | "Mover o Capturar" o "Enroque" |
| Marrón | **Salto de Aquonte** (mover saltando condicionado): si hay una casilla ocupada dentro del rango extendido por este efecto, a igual distancia, en la misma recta donde la pieza podría "Mover o Capturar"/"Mover" sin este efecto. |
| Granate | "Mover o Capturar" o "Salto de Aquonte" |

### Estado derivado

- **Inmovilizada**: la pieza no puede realizar ningún movimiento durante el
  próximo turno de su dueño (la sufren piezas enemigas atravesadas o atraídas).
  Como no puede capturar durante ese turno, tampoco "amenaza" casillas para
  el enroque ni para el indicador de piezas atacadas.

### Interpretaciones confirmadas sobre la leyenda

- **Salto de Aquonte**: la regla dice "si hay una casilla **ocupada**" sin
  distinguir bando → una pieza **enemiga también sirve de pivote**.
- **Empujar/Atraer no cuentan como "realizar un movimiento"**: la pieza
  desplazada conserva su estado de no-movida (sigue pudiendo desplegar o
  enrocar). La condición 'd'/'k' habla de que la pieza *realizara* un
  movimiento, no de que hubiera sido movida por otro.
- **Enroque de un paso**: imposible por construcción — el destino del rey
  sería la casilla inicial de la torre (ocupada), y la regla exige que las
  casillas iniciales/finales y las intermedias estén libres.
- **Anti-stall** (opción de la app, no del manual): el límite cuenta
  **turnos** sin captura; la doble apertura de Humenex consume 1, no 2.

---

## 3. Facciones

Cada facción tiene: una **pieza básica** (valor 1, tipo peón), una **pieza
poderosa** (valor alto, tipo reina), un **líder** (tipo rey), y 3+ **piezas
medias** (valores 2-6). Los tableros negros de cada hoja muestran el despliegue
inicial del ejército (con variantes **Eq1** y **Eq2** = dos dotaciones
alternativas).

### 3.1 Humenex

*Regla especial: los Humenex **siempre empiezan segundos**; en su primer
movimiento juegan **2 movimientos**.*

| Pieza | Valor | Movimiento (interpretación) |
| --- | --- | --- |
| **Peón** | 1 | Avanza 1 (amarillo); despliegue 2 casillas si no ha movido (verde claro); captura en diagonal frontal incl. al paso (rosa). |
| **Emperatriz** (X) | 8 | Desliza en todas las direcciones (naranja) — la "reina" clásica. |
| **Emperador** (Y) | — | 3 casillas frontales (naranja) + laterales M/C o enroque (lima) + enroque a lo largo de la fila (verde osc.). El rey. |
| **Espía** (A) | 3 | Desliza en diagonal (naranja) — "alfil". |
| **Caballero** (C) | 3 | Saltos en L (morado) — salta para mover o capturar. |
| **Torre** (T) | 5 | Desliza en ortogonal (naranja) — "torre". |

Despliegue: fila trasera `T C E Y X E C T`. Es la facción más parecida al ajedrez clásico.

### 3.2 Elfos

*Regla especial: los Elfos **siempre empiezan primeros**.*

| Pieza | Valor | Movimiento |
| --- | --- | --- |
| **Centinela** (C) | 1 | 1 casilla adyacente (naranja) — peón lento de corto alcance. |
| **Dama** (X) | 8 | Mover/capturar atravesando cerca (verde osc.) + mover atravesando lejos (oliva) + saltos de caballo (cian). Reina con atravesar. |
| **Monarca** (Y) | — | 1 casilla **mover/capturar atravesando** (verde oscuro). El rey. |
| **Hostigador** (H) | 3 | Diagonal: atravesar cerca (verde osc.) y capturar atravesando lejos (rojo osc.) + mover atravesando ortogonal (oliva). |
| **Explorador** (E) | 3 | Captura atravesando en diagonal desde distancia 2 (rojo osc.) + saltos de caballo (cian). |
| **Forestal** (F) | 5 | Desliza en ortogonal **atravesando** (oliva) — torre que atraviesa e inmoviliza. |

Identidad: mucha movilidad a través de piezas e inmovilización.

### 3.3 Mortifers

*Regla especial: la **Consorte** (reina) puede intercambiar su gama de
movimientos con la de una pieza tras capturarla.*

| Pieza | Valor | Movimiento |
| --- | --- | --- |
| **Carroñero** (K/C) | 1 | Casillas adyacentes (rojo + naranja). |
| **Consorte** (X) | 8 | Diagonal (rojo) + ortogonal (naranja) + saltos (morado). Roba movimientos al capturar. |
| **Tirano** (Y) | — | Adyacentes (rojo + naranja). El rey. |
| **Corruptor** (C) | 3 | Diagonal (rojo) + saltos (morado) + casillas (naranja). |
| **Merodeador** (M) | 3 | Captura diagonal (rojo) + mueve a casillas (amarillo). |
| **Incubo** (I) | 5 | Columna de captura (rojo) + salto (morado) + (naranja). |

Despliegue: `I C M X Y M C I` (Eq1) / `I C M Y X M C I` (Eq2).

### 3.4 Bestiarios

*Regla especial: para ganar hay que derrotar a **ambos líderes** (Líder y
Lideresa). Facción de enjambre con más tipos de pieza (9).*

| Pieza | Valor | Movimiento |
| --- | --- | --- |
| **Rahez** (H) | 1 | Avanza (amarillo) + captura laterales (rojo). |
| **Rapaz** (R) | 4 | Diagonal (naranja) + casillas (amarillo). |
| **Fugaz** (F) | 3 | Saltos largos (1,3) en morado. |
| **Edaz** (E) | 6 | Ortogonal hasta 4 + diagonal hasta 3 (naranja) — pieza pesada. |
| **Voraz** (V) | 3 | Diagonal de captura (rojo) + (naranja/rojo). |
| **Sagaz** (S) | 3 | Saltos (morado). |
| **Audaz** (A) | 5 | Bloque de saltos 2x2 (cian) + casillas cercanas (naranja). |
| **Lideresa** (X) | 6 / líder | Saltos cortos (morado). |
| **Líder** (Y) | 6 / líder | Saltos cortos (morado). |

Despliegue Eq1: `V X R E F S Y A` · Eq2: `A Y S F E R X V`.

### 3.5 Enanos

Facción orientada a **empujar**.

| Pieza | Valor | Movimiento |
| --- | --- | --- |
| **Vasallo** (S) | 1 | Mover/empujar frontal (teal) + captura saltando a los lados (morado). |
| **Sultana** (X) | 6 | Naranja + morado (mixto). |
| **Califa** (Y) | — | Adyacentes teal + morado. El rey. |
| **Verdugo** (V) | 4 | Atraer/empujar (magenta) + naranja + rojo. |
| **Raudo** (R) | 4 | Morado + amarillo + rojo. |
| **Zaguero** (Z) | 4 | Morado + azul oscuro (mover/capturar/empujar). |

Despliegue Eq1: `Z V R V X R Y Z` · Eq2: `Z Y R X V R V Z`.

### 3.6 Chlontos

| Pieza | Valor | Movimiento |
| --- | --- | --- |
| **Zángano** (Z) | 1 | Avanza (amarillo) + captura laterales/frontal (rojo). |
| **Matriarca** (X) | 6 | Diagonal (rojo) + saltos (morado). |
| **Gerarca** (Y) | — | Adyacentes (cian + naranja). El rey. |
| **Raptor** (R) | 4 | Diagonal de captura (rojo) + mover saltando (cian). |
| **Céfiro** (C) | 4 | Captura saltando (verde lima) + mover saltando (cian). |
| **Hoplita** (H) | 4 | Saltos (morado). |

Despliegue Eq1: `H C C R R X Y H` · Eq2: `H Y X R R C C H`.

### 3.7 Aquontes

Facción con el **Salto de Aquonte** (salto condicionado sobre piezas alineadas).

| Pieza | Valor | Movimiento |
| --- | --- | --- |
| **Alevín** (A) | 1 | Salto de Aquonte frontal (marrón) + amarillo + rojo. |
| **Anfitrite** (X) | 8 | Marrón + rojo + morado + naranja — reina versátil. |
| **Leviatán** (Y) | — | Diagonal Aquonte (marrón) + naranja. El rey. |
| **Mako** (M) | 2 | Marrón + rojo + morado + naranja (mezcla corta). |
| **Tritón** (T) | 4 | **Dos movimientos encadenados**: mov1 naranja en diagonal cercana, mov2 captura a distancia 2 (rojo) — uno, el otro o ambos. |
| **Carchar** (C) | 4 | Columna (marrón) + rojo + morado + naranja. |

Despliegue Eq1: `C M T T M X Y C` · Eq2: `C Y X M T T M C`.

### 3.8 Kronturs

Facción de **empuje** pesada.

| Pieza | Valor | Movimiento |
| --- | --- | --- |
| **Mole** (M) | 1 | Empuja frontal (azul) + captura laterales (rojo) — "peón ariete". |
| **Zarina** (X) | 6 | Saltos (morado) + azul oscuro (mover/capturar/empujar). |
| **Zar** (Y) | — | Empujar (azul) + azul oscuro. El rey. |
| **Ariete** (A) | 4 | Teal (mover/empujar) + morado. |
| **Dique** (D) | 4 | Teal + azul oscuro. |
| **Goliat** (G) | 4 | Saltos (morado). |

Despliegue Eq1: `X Y A A G D G D` · Eq2: `D G D G A A Y X`.

---

## 4. Reglas globales deducidas

1. Turnos alternos; el orden de salida depende de la facción
   (Elfos primero, Humenex segundo con doble movimiento inicial).
2. Capturar el líder enemigo = victoria (Bestiarios: los dos líderes).
3. Las piezas inmovilizadas pierden su siguiente movimiento.
4. Los valores de pieza probablemente equilibran los ejércitos
   (cada despliegue suma un total similar).
5. Cada facción ofrece **dos equipos (Eq1/Eq2)**: mismo conjunto de piezas,
   distinta composición/disposición.

> ⚠️ **Interpretaciones pendientes de confirmar:** si existe jaque/jaque mate
> o la partida acaba directamente por captura del líder.
>
> **Estado de la transcripción (auditoría visual celda a celda):**
> los patrones de movimiento de las 8 facciones y los tableros de
> despliegue Eq1/Eq2 están transcritos de las hojas (ver
> `game/src/core/pieces_data.gd`). Cada celda conserva su color/efecto
> literal. Glifos góticos resueltos por contexto: 'D' en Enanos = Raudo,
> 'M' en Chlontos = Zángano (ℨ), 'P' en tableros = básico de la facción,
> 'R' en Aquontes = Leviatán (𝔜), 'P' rojo en Bestiarios Eq2 = Rapaz (ℜ).
> Los números junto a los tableros (p. ej. "8 / (+1) / 4") parecen
> contar piezas por grupo de color; sin confirmar.

---

## 5. Plan de implementación en Godot

**Motor recomendado:** Godot 4.x, GDScript, 2D (Node2D/Control).
Es viable en 3D más adelante (los concept art son piezas escultóricas), pero el
núcleo del juego es un tablero lógico → **hacer primero 2D data-driven**.

### 5.1 Principio clave: todo es datos

El juego tiene ~50 tipos de pieza con movimientos combinables. **No hardcodear
piezas**: definir cada pieza como un `Resource` con una lista de *átomos de
movimiento*.

```gdscript
# move_atom.gd — un patrón atómico de movimiento
class_name MoveAtom extends Resource

enum Kind { STEP, RAY }            # salto a offset fijo / deslizamiento
enum Effect {                      # combinable con flags
    MOVE, CAPTURE, JUMP, ATRAVESAR, EMPUJAR, ATRAER
}
enum Condition {
    NONE, DEPLOY, EN_PASSANT, CASTLE, AQUONTE, CHAIN
}

@export var kind: Kind
@export var direction: Vector2i    # u offset para STEP
@export var range: int = 1         # alcance para RAY
@export_flags("MOVE","CAPTURE","JUMP","ATRAVESAR","EMPUJAR","ATRAER") var effects
@export var condition: Condition
@export var chained_to: MoveAtom   # para Tritón (movimiento en 2 pasos)
```

```gdscript
# piece_def.gd
class_name PieceDef extends Resource
@export var id: StringName          # "peon", "emperatriz"...
@export var faction: StringName     # "humenex"...
@export var display_name: String
@export var value: int
@export var is_leader: bool         # rey/líder → condición de victoria
@export var moves: Array[MoveAtom]
@export var sprite: Texture2D
```

### 5.2 Arquitectura (modelo / vista separados)

```text
┌─ MODELO (puro, testeable, sin nodos) ──────────────┐
│ BoardState      grid 8x8 de PieceState             │
│ PieceState      def, owner, has_moved, statuses    │
│                 (inmovilizada, moves_robados...)   │
│ MoveGenerator   state + pieza → Array[Move]        │
│ Move            origen, destino, capturas,         │
│                 empujones, inmovilizaciones        │
│ TurnManager     orden, reglas de facción, victoria │
└───────────────────────────────────────────────────┘
┌─ VISTA (nodos) ────────────────────────────────────┐
│ BoardView       dibuja grid, instancia PieceNode   │
│ PieceNode       sprite + animaciones               │
│ HighlightLayer  muestra movimientos legales        │
│                 (con el COLOR del efecto real)     │
│ HUD             turno, facción, capturadas         │
└───────────────────────────────────────────────────┘
```

**Sistema de efectos** — el corazón del motor:

- `MoveGenerator` itera los `MoveAtom` de la pieza y produce acciones.
- `Empujar` y `Atraer` generan movimientos *sobre casillas ocupadas* y mueven
  la pieza objetivo (a veces fuera del tablero = captura por atropello).
- `Atravesar`/`Atraer` aplican el status `inmovilizada` → `PieceState.flags`.
- Condiciones se evalúan con contexto: `has_moved`, `last_move` (al paso),
  derechos de enroque, ocupación alineada (Aquonte).

**Mecánicas especiales a encapsular:**

- `Tritón`: un `Move` puede ser `CompoundMove` (2 sub-movimientos encadenados).
- `Consorte`: al capturar, guarda copia de los `moves` de la víctima
  (o reemplaza su set) → estado mutable por pieza.
- `Bestiarios`: `is_leader` en 2 piezas; victoria = ambos capturados.
- `Humenex`/`Elfos`: reglas de orden en `TurnManager` + flag `first_turn`.

### 5.3 Estructura de proyecto sugerida

```text
beliber-godot/
├── project.godot
├── data/
│   ├── factions/          # .tres de facciones (ejércitos Eq1/Eq2)
│   └── pieces/            # .tres por tipo de pieza (~50)
├── src/
│   ├── core/              # BoardState, MoveGenerator, TurnManager,
│   │                      # red y servicios (RefCounted/Node)
│   ├── ui/                # BoardView, pantallas, Widgets, tema
│   └── main.gd            # entrypoint (único script por ruta)
├── scenes/
│   └── main.tscn
└── assets/                # sprites de piezas (del arte conceptual)
```

### 5.4 Roadmap por hitos

1. **M0 – Núcleo**: BoardState + MoveGenerator con MOVE/CAPTURE/JUMP +
   render 2D + selección/movimiento por clic. Playtest: Humenex vs Humenex.
2. **M1 – Efectos**: Atravesar, Empujar, Atraer, inmovilización,
   condicionados (al paso, despliegue, enroque, Aquonte, Tritón).
3. **M2 – Facciones**: las 8 facciones con datos Eq1/Eq2 + reglas especiales
   (Consorte, doble líder, orden de turno).
4. **M3 – UX**: pantalla de selección de facción/equipo, highlights coloreados
   por efecto, historial de movimientos, capturadas.
5. **M4 – Polish**: sprites finales del arte conceptual, animaciones,
   sonido. Opcional: IA simple (minimax con eval por `value`) y/o online.

### 5.5 Ventaja de este diseño

Al ser **data-driven**, equilibrar el juego = editar `.tres`, sin tocar código.
Además el mismo `MoveGenerator` sirve para: highlights, validación, IA y replay.

---

## 6. Dudas a resolver antes de programar

1. ¿Los patrones de los diagramas se **espejan** en las 4 direcciones o solo
   hacia adelante? (los diagramas muestran un solo cuadrante)
2. ¿Hay **jaque** (obligación de defender al líder) o gana quien captura?
3. ¿Qué significan los números del despliegue (`5 + 3 + 2 2 + 2`)? ¿Límite
   de puntos del ejército / coste por pieza?
4. ¿Eq1/Eq2 se elige antes de la partida o es secreto?
5. Regla exacta del **Salto de Aquonte** (la descripción es ambigua).
6. Caso Elfos vs Humenex: ¿Elfos mueve primero y Humenex hace doble turno?
