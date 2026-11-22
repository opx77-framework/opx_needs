---@meta

-- opx_needs server exports and events. Not loaded by the manifest (LuaLS annotations only).
-- A replacement needs resource keeps these names and shapes. The values themselves are opx_core character
-- metadata (Config.keys: `hunger`, `thirst`, integers 0..Config.max), so the HUD and any other resource can
-- read them with opx_core GetMetadata without opx_needs.
-- GetNeeds / SetNeed / AddNeed are SYNCHRONOUS (exports.opx_needs:Name(...) or Open77.exports.callSync).
-- UseConsumable WAITS (the player's timed action): only the inventory calls it, asynchronously.

---@alias OpxNeedKey 'hunger'|'thirst'

---@class OpxNeeds
---@field hunger integer 0..Config.max
---@field thirst integer 0..Config.max

---@alias OpxNeedsError
---| 'invalid_player' source is not a player id
---| 'invalid_key' key is not 'hunger' or 'thirst'
---| 'invalid_value' value / delta is not a finite number
---| 'not_loaded' no character loaded (or opx_core does not answer)

---@class OpxNeedsExports
local opx_needs = {}

--- SYNC. Both needs of a loaded character (the integers the HUD shows), or nil.
---@param source integer
---@return OpxNeeds|nil
function opx_needs.GetNeeds(source) end

--- SYNC. Sets one need, clamped to 0..Config.max; writes the metadata when the shown value changes.
--- Crossing a Config.warnAt value downward notifies the player; reaching 0 raises opx:needs:starving.
---@param source integer
---@param key OpxNeedKey
---@param value number
---@return boolean ok
---@return OpxNeedsError|nil reason
function opx_needs.SetNeed(source, key, value) end

--- SYNC. Adds delta (negative lowers) to one need, clamped. Returns the new shown value.
---@param source integer
---@param key OpxNeedKey
---@param delta number
---@return integer|false value
---@return OpxNeedsError|nil reason
function opx_needs.AddNeed(source, key, delta) end

--- ASYNC (waits up to seconds + 5). The usable-item handler opx_needs registers on the inventory provider
--- (RegisterItem then RegisterUsable(item, 'UseConsumable')) for every key of Config.consumables. Runs the player's eat / drink
--- action and answers true (the inventory removes one item) only when it ran to the end; false otherwise.
---@param source integer
---@param item string
---@param instanceId? string
---@param meta? table
---@return boolean consume
function opx_needs.UseConsumable(source, item, instanceId, meta) end

-- Server host event (AddEventHandler), raised when a need reaches 0 (decay, SetNeed, AddNeed):
-- TriggerEvent('opx:needs:starving', source, key)
---@alias OpxNeedsStarvingEvent fun(source: integer, key: OpxNeedKey)

-- Listens to: opx:playerLoaded, opx:playerUnloaded, onPlayerDisconnected, opx:medical:up (needs raised to
-- Config.afterRevive), onResourceStart of the inventory provider (re-registers items and usables) and of opx_core.
-- Starving damage uses cause 'environment' (a starving death is a normal death), never while down.
-- Items owned: opx_needs owns the food and drink items (default water, soda, coffee, bread, sandwich, noodles).
-- It registers each key of Config.consumables on the inventory provider (exports.opx_core:GetProvider('inventory'))
-- with RegisterItem(item, { label, description, weightG, usable = true }) then RegisterUsable(item,
-- 'UseConsumable'), at its start and on onResourceStart of the provider. While opx_needs is stopped the items
-- stay in the inventory catalogue but have no use (nothing is eaten or drunk).
-- Internal net events (not a contract): server -> client opx_needs:consume (token, { item, seconds, animation,
-- still, kind }), opx_needs:notify; client -> server opx_needs:consumed (token, ok).
