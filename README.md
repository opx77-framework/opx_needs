# opx_needs

Hunger and thirst. Both go down over time, hurt the character when empty, and eating or drinking an item plays a short timed action with an animation. opx_needs owns the food and drink items (water, soda, coffee, bread, sandwich, noodles) and registers them on the inventory.

## Install
- Needs: `opx_core`. Load after `opx_core`, `opx_inventory`, `opx_progress` (and `opx_medical` if used). Load `open77_animations` for the animations.
- No database: the values are opx_core character metadata (`hunger`, `thirst`, 0..100).
- ACL: grant staff `command.setneed`.
- Without the inventory provider nothing can be eaten. While opx_needs is stopped the items stay in inventories but cannot be used.

## In game
- Use a food or drink item from the inventory: eat or drink it (cancelling the bar consumes nothing).
- `/setneed <playerId|me> <hunger|thirst> <0-100>`: staff, ACL `command.setneed`.

## Config
`config.lua`: `decay`, `starve` (damage, `lethal`), `consumables` (one entry per food or drink item: label en/fr, description, weightG, points, seconds, animation; add an entry to add an item), `afterRevive`. Everything else is commented in the file.

## For developers
- `GetNeeds(source)` → `{ hunger, thirst }` or nil
- `SetNeed(source, key, value)` → `true` | `false, reason`
- `AddNeed(source, key, delta)` → new value | `false, reason`
- Events: `opx:needs:starving (source, key)`.
- Items: each `Config.consumables` key is registered with the inventory's `RegisterItem` then `RegisterUsable(item, 'UseConsumable')`, at start and when the inventory provider starts.
- A replacement keeps these exports, the event and the metadata keys, and registers the same item ids. Full contract: `types.lua`.
