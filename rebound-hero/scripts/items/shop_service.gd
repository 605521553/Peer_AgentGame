class_name ShopService
extends RefCounted

var model: CombatModel
var rng := RandomNumberGenerator.new()
var offers: Array = []
var refreshes := 0
var message := ""

func _init(combat: CombatModel) -> void:
	model = combat

func open() -> void:
	rng.seed = model.seed_value ^ (int(model.level_index + 1) * 7919)
	refreshes = 0
	message = ""
	generate()

func refresh_price() -> int:
	return int(model.db.rules.shop.refresh_base) + refreshes * int(model.db.rules.shop.refresh_increment)

func refresh() -> bool:
	if model.state != "SHOP" or model.player.gold < refresh_price():
		message = "金币不足，无法刷新"
		return false
	model.player.gold -= refresh_price()
	refreshes += 1
	generate()
	model.changed.emit()
	return true

func generate() -> void:
	offers.clear()
	var requirements: Array = model.db.rules.shop.required_types
	for i in range(int(model.db.rules.shop.slots)):
		var kind: String = requirements[i % requirements.size()]
		if kind == "random":
			var kinds: Array = model.db.rules.shop.random_types
			kind = str(kinds[rng.randi_range(0, kinds.size() - 1)])
		offers.append(_offer(kind, i))

func _quality() -> int:
	var rows: Array = model.db.rules.shop.quality_weights
	var weights: Array = rows[mini(model.level_index, rows.size() - 1)]
	var value := rng.randf() * 100.0
	for i in range(weights.size()):
		value -= float(weights[i])
		if value <= 0: return i
	return weights.size() - 1

func _offer(kind: String, slot: int) -> Dictionary:
	var db := model.db
	var quality := _quality()
	if kind == "heal":
		return {"type": kind, "id": "", "quality": 0, "price": int(db.rules.shop.heal.price), "sold": false, "name": db.rules.shop.heal.name, "description": db.rules.shop.heal.description, "visual": db.rules.shop.heal.visual}
	var catalog: Dictionary = db.weapons if kind == "weapon" else db.items
	var choices: Array = []
	var featured: Array = db.levels[model.level_index].get("shop_featured", [])
	if refreshes == 0:
		for feature in featured:
			if feature.type == kind and catalog.has(feature.id):
				var already_offered := false
				for offer in offers:
					if offer.type == kind and offer.id == feature.id: already_offered = true
				if not already_offered and (kind == "weapon" or int(model.collected.get(feature.id, 0)) < int(catalog[feature.id].max_stacks)): choices.append(feature.id)
	if choices.is_empty():
		for candidate_quality in range(quality, -1, -1):
			for id in catalog:
				if kind == "item":
					if int(catalog[id].quality) != candidate_quality or int(model.collected.get(id, 0)) >= int(catalog[id].max_stacks): continue
				var duplicate := false
				for other in offers:
					if other.type == kind and other.id == id: duplicate = true
				if not duplicate: choices.append(id)
			if not choices.is_empty(): break
	if choices.is_empty(): return _offer("heal", slot)
	var id: String = str(choices[rng.randi_range(0, choices.size() - 1)])
	var definition: Dictionary = catalog[id]
	if kind == "item": quality = int(definition.quality)
	var offer := {"type": kind, "id": id, "quality": quality, "price": roundi(float(definition.price) * float(db.rules.shop.quality_price[quality])), "sold": false, "name": definition.name, "description": definition.description, "visual": definition.visual}
	if kind == "weapon":
		offer.instance = model.make_weapon(id, quality, rng)
		offer.description = model.weapon_description(offer.instance)
	return offer

# Replacement selection happens before this call. No gold is debited while selecting.
func buy(index: int, replace_index: int = -1) -> bool:
	message = ""
	if model.state != "SHOP" or index < 0 or index >= offers.size(): return false
	var offer: Dictionary = offers[index]
	if offer.sold: message = "这件商品已经售出"; return false
	var available := int(model.player.gold)
	if offer.type == "weapon" and model.inventory.size() >= int(model.player.max_weapons):
		if replace_index < 0 or replace_index >= model.inventory.size(): message = "请选择要替换的武器"; return false
		available += sell_value(replace_index)
	if available < int(offer.price): message = "金币不足"; return false
	match offer.type:
		"heal":
			if model.player.hp >= model.player.max_hp: message = "生命已经全满"; return false
			model.player.hp = minf(model.player.max_hp, model.player.hp + float(model.db.rules.shop.heal.amount))
		"item":
			if int(model.collected.get(offer.id, 0)) >= int(model.db.items[offer.id].max_stacks): message = "该道具已达到叠加上限"; return false
			model.grant_item(offer.id)
		"weapon":
			if model.inventory.size() >= int(model.player.max_weapons):
				if replace_index < 0 or replace_index >= model.inventory.size(): message = "请选择要替换的武器"; return false
				model.player.gold += sell_value(replace_index)
				model.inventory[replace_index] = offer.instance.duplicate(true)
			else:
				model.inventory.append(offer.instance.duplicate(true))
	model.player.gold -= int(offer.price)
	offer.sold = true
	message = "已购买 " + str(offer.name)
	model.changed.emit()
	return true

func upgrade_price(index: int) -> int:
	return int(model.db.rules.shop.upgrade_base) + int(model.inventory[index].upgrade) * int(model.db.rules.shop.upgrade_growth)

func upgrade(index: int) -> bool:
	if model.state != "SHOP" or index < 0 or index >= model.inventory.size(): return false
	if int(model.inventory[index].upgrade) >= int(model.db.rules.shop.max_upgrade): message = "已达到强化上限"; return false
	var price := upgrade_price(index)
	if model.player.gold < price: message = "金币不足，无法强化"; return false
	model.player.gold -= price
	model.inventory[index].upgrade += 1
	message = "武器强化完成"
	model.changed.emit()
	return true

func sell_value(index: int) -> int:
	var weapon: Dictionary = model.inventory[index]
	return roundi(float(model.db.weapons[weapon.id].price) * float(model.db.rules.shop.quality_price[weapon.quality]) * float(model.db.rules.shop.sell_ratio))

func sell(index: int) -> bool:
	if model.state != "SHOP" or model.inventory.size() <= 1 or index < 0 or index >= model.inventory.size(): message = "至少保留一把武器"; return false
	model.player.gold += sell_value(index)
	model.inventory.remove_at(index)
	model.active_weapon = mini(model.active_weapon, model.inventory.size() - 1)
	message = "已出售武器"
	model.changed.emit()
	return true
