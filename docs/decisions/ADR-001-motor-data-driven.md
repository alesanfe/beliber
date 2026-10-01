# ADR-001: Motor data-driven — piezas definidas por casillas, no por código

## Contexto

Beliber tiene 7 facciones con ~30 piezas distintas, muchas con patrones
irregulares (saltos, multi-movimiento diagonal/ortogonal, ganchos,
empujar, atraer, atravesar, salto de Aquonte) y el juego incluye un
**editor de piezas** que debe poder reproducir/reprogramar cualquier
pieza oficial. Si cada pieza fuese código, el editor sería un lenguaje
de programación.

## Decisión

`pieces_data.gd` declara cada pieza como datos: un `cells` dict
`(x,y) → "j|m|c|a|i|t|J|"` (salta/mueve/captura/inmoviliza/atrae/
atraviesa/Jump=Aquonte), `slide` (propagación por rayos), `caps`,
flags (`no_leaders`, `consorte`…). El generador de movimientos
(`move_gen.gd`) recorre ese patrón una vez, para todas las piezas.
Los efectos raros son `cond`s y un `mv.second` para cadenas de 2 tramos
(Tritón, Humenex), no código por pieza.

## Alternativas

- Una clase/callback por pieza: expresivo pero no serializable → el
  editor de piezas no podría existir, y los overrides no podrían
  viajar por red como JSON.
- DSL/scripting custom: demasiada superficie para bugs y para
  validación (inputs arbitrarios en red).

## Consecuencias

+ Cualquier pieza es serializable a JSON (editor, overrides en red,
  exports BEL-FEN/BEL-ARMY).
+ Todas las piezas nuevas funcionan con el mismo motor ya testeado.
- Los patrones que no encajan en casillas estáticas (condicionales
  complejos) se resuelven como excepciones documentadas en move_gen —
  unas 4: Aquonte pivote, despliegue Humenex, enroque, Consorte.
