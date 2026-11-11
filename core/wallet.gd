# Purpose: the player's coin balance (virtual, free, only used in the casino). Pure rules: never goes negative.
# Dependencies: none.
extends RefCounted

var balance := 0


func _init(start: int = 0) -> void:
	balance = maxi(start, 0)


func can_afford(amount: int) -> bool:
	return amount >= 0 and amount <= balance


# Takes `amount` coins; returns false (and changes nothing) if there are not enough.
func spend(amount: int) -> bool:
	if not can_afford(amount):
		return false
	balance -= amount
	return true


func add(amount: int) -> void:
	if amount > 0:
		balance += amount
