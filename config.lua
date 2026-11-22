Config = {}

-- opx_core metadata keys holding each need (an integer 0..max). opx_hud reads the same keys (its Config.needs).
Config.keys = { hunger = 'hunger', thirst = 'thirst' }

-- Value of a full need (opx_core Config.defaultMetadata gives new characters 100).
Config.max = 100

-- Seconds between two decay steps.
Config.tickSeconds = 60

-- Points lost per decay step (about 3 h for hunger and 2 h 15 for thirst from full, with tickSeconds = 60).
Config.decay = { hunger = 0.55, thirst = 0.75 }

-- One notification when a need goes down to (or under) one of these values.
Config.warnAt = { 25, 10 }

-- A need at zero hurts: `damage` health points every `intervalSeconds`. lethal = false stops at `minHealth`.
Config.starve = { intervalSeconds = 30, damage = 5, lethal = true, minHealth = 10 }

-- After a revive or a hospital respawn (opx:medical:up), both needs are raised to at least this value.
Config.afterRevive = 30

-- true: needs do not go down while the character is down or dead (no damage while down in any case).
Config.pauseWhenDown = true

-- Food and drink: opx_needs owns these items. Each key is an item id ([a-z0-9_], never change it once players
-- own the item). At start (and whenever the inventory provider starts) every entry is registered on the inventory
-- provider with RegisterItem (label, description, weightG, usable = true) then RegisterUsable.
-- label / description: a string or { en = ..., fr = ... }. weightG: grams of one item.
-- hunger / thirst: points added. seconds: length of the action. animation: open77_animations profile
-- (false = none). still = true: the character cannot move meanwhile (needed by the stationary "workspot"
-- profiles such as takeout). Add an entry here to add a new food or drink.
Config.consumables = {
	water = {
		label = { en = 'Water', fr = 'Eau' },
		description = { en = 'A bottle of water.', fr = "Une bouteille d'eau." },
		weightG = 500, thirst = 30, seconds = 4, animation = 'bottle_walk',
	},
	soda = {
		label = { en = 'Soda', fr = 'Soda' },
		description = { en = 'A can of fizzy soda, too sweet.', fr = 'Une canette de soda pétillant, trop sucré.' },
		weightG = 350, thirst = 20, seconds = 4, animation = 'drink_walk',
	},
	coffee = {
		label = { en = 'Coffee', fr = 'Café' },
		description = { en = 'Synthetic coffee in a paper cup.', fr = 'Café synthétique dans un gobelet en carton.' },
		weightG = 300, thirst = 15, seconds = 4, animation = 'drink_walk',
	},
	bread = {
		label = { en = 'Bread', fr = 'Pain' },
		description = { en = 'Synth bread, still soft.', fr = 'Pain synthétique, encore moelleux.' },
		weightG = 250, hunger = 30, seconds = 5, animation = 'takeout', still = true,
	},
	sandwich = {
		label = { en = 'Sandwich', fr = 'Sandwich' },
		description = { en = 'A vending machine sandwich, scop inside.', fr = 'Un sandwich de distributeur, garni de scop.' },
		weightG = 300, hunger = 40, seconds = 5, animation = 'takeout', still = true,
	},
	noodles = {
		label = { en = 'Noodles', fr = 'Nouilles' },
		description = { en = 'A hot box of noodles from a street stall.', fr = "Une boîte de nouilles chaudes d'un stand de rue." },
		weightG = 450, hunger = 55, thirst = 5, seconds = 7, animation = 'takeout', still = true,
	},
}

-- Staff command: setneed <playerId|me> <hunger|thirst> <0-max>. Restricted (ACL right `command.setneed`).
-- false = no command.
Config.commands = { setneed = 'setneed' }

-- Minimum milliseconds between two requests of one player (anything faster is ignored).
Config.rateLimitMs = 500

-- Update check at start: compares this version with the one published on GitHub and prints a line in the
-- server console when an update is out. Needs outbound HTTP in server.jsonc ("http": "enabled": true, with
-- "raw.githubusercontent.com" in "allowedHosts"). false = no request.
Config.versionCheck = true
