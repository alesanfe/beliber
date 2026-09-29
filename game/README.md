# Beliber — Proyecto Godot

Prototipo jugable del ajedrez asimétrico **Beliber** (ver `../COMO_FUNCIONA.md`).

## Ejecutar

1. Instala **Godot 4.2+** (probado con 4.4.1): https://godotengine.org/download
2. Abre `project.godot` con el editor, o ejecuta:
   ```
   godot --path game
   ```

## Tests del motor

```
godot --headless --path game -s res://tests/run_tests.gd
```

23 tests cubren: despliegue, movimientos base, salto del caballo, doble
apertura Humenex, orden Elfos, empujar (Mole), atravesar+inmovilizar
(Forestal), robo de movimientos (Consorte) y victoria por líderes.

## Estructura

```
game/
├── project.godot
├── scenes/main.tscn        # escena raíz (un Control con src/main.gd)
├── src/
│   ├── fx.gd             # constantes de efectos + colores de la leyenda
│   ├── pieces_data.gd    # ⭐ TODAS las piezas y facciones como datos
│   ├── board_state.gd    # estado 8x8, despliegue, aplicar movimientos
│   ├── move_gen.gd       # generador de movimientos legales (todos los fx)
│   ├── turn_manager.gd   # turnos, reglas de facción, victoria
│   ├── board_view.gd     # tablero dibujado + input + highlights por color
│   └── main.gd           # menú de facciones + HUD
└── tests/run_tests.gd
```

## Cómo se define una pieza

Cada pieza es un **mapa de casillas** — literalmente el diagrama de la hoja
de referencia—: un diccionario `"dx,dy" -> código de color`. En
`pieces_data.gd`:

```gdscript
# Peón Humenex: avanza 1 (m), despliegue a 2 (d), captura diagonal/al paso (E)
_pc("P", "Peón", 1, _cells([
    [Vector2i(0, -1), "m"], [Vector2i(0, -2), "d"],
    [Vector2i(-1, -1), "E"], [Vector2i(1, -1), "E"],
]), {"sym": "lit"})
```

- Códigos = letras por cada color de la leyenda (`m` amarillo, `c` rojo,
  `o` naranja, `J` morado, `p` teal, `e` azul, `q` marrón… 19 en total,
  ver `PiecesData.CODE_NAMES`).
- `sym = "all"` expande el patrón a las 8 direcciones (lo normal);
  `sym = "lit"` aplica el patrón literal (solo girado para J2), para
  piezas direccionales como los básicos.
- Celdas contiguas alineadas = deslizamiento; celda aislada o no alineada
  = salto. Cada celda conserva su propio efecto.

## Editor de piezas

Menú → **Editor de piezas**. Permite:
- Elegir facción y pieza, pintar celdas con la paleta de la leyenda.
- Reubicar la pieza en el diagrama (clic con "Reubicar pieza").
- Editar nombre, valor, simetría, líder, robo de movimientos.
- **Vista previa real**: el motor calcula movimientos legales sobre un
  tablero de prueba con enemigos/aliados dummy.
- Guardar → `user://beliber_pieces.json` (sobreescribe al instante);
  "Restaurar" borra el override de esa pieza.

Los patrones por defecto son mi transcripción de los diagramas; el editor
sirve para corregirlos casilla a casilla sin tocar código.

## Estado / provisional

- ✅ Motor completo: mover, capturar, saltar, atravesar (+inmovilizar),
  empujar (arrolla enemigos), atraer, al paso, despliegue, enroque,
  Salto de Aquonte, cadena del Tritón, Consorte, doble líder Bestiarios,
  orden Humenex/Elfos, doble apertura.
- ✅ **Despliegues Eq1/Eq2 transcritos de las hojas** (formaciones
  dispersas de ~5 filas, no filas de ajedrez).
- ✅ Hotseat 2 jugadores con selección de facción y Eq1/Eq2/Personalizado.
- ✅ Highlights coloreados con la paleta oficial de la leyenda.
- ✅ Editor visual de piezas con persistencia JSON.
- ✅ **Funcionalidades de la competencia** (ver `../COMPETENCIA.md`):
  - Valor de ejército por facción en el menú (equilibrio estilo Betza).
  - Material vivo en el HUD.
  - Mapa de cobertura alternable (estilo Chess Evolved Online).
  - Invasión de línea opcional (Chess 2): líder en última fila gana.
  - Anti-estancamiento opcional: N turnos sin captura → material decide.
  - Constructor de ejército con presupuesto de puntos (CEO): se guarda
    como equipo "Personalizado".
- ⚠️ Algunos glifos góticos del manual son ambiguos; los despliegues se
  transcribieron letra a letra, pendiente verificación visual.
- 🔜 Arte, animaciones, sonido, IA.
