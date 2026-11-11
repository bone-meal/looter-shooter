# Purpose: European (single zero) roulette rules: wheel order, colours, bet keys, payouts. Pure; the caller supplies randomness.
# Dependencies: none.
extends RefCounted

# Pocket order around the wheel, clockwise from 0.
const WHEEL := [0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10, 5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26]
const REDS := [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36]


static func is_red(n: int) -> bool:
	return n in REDS


static func color_of(n: int) -> String:
	if n == 0:
		return "green"
	return "red" if is_red(n) else "black"


static func spin(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(0, 36)


# Bet keys: "straight:17", "split:17-20", "street:1" (row 1..12), "corner:17", "line:1" (rows r and r+1),
# "dozen:1..3", "column:1..3", "red", "black", "odd", "even", "low", "high".
static func numbers_of(key: String) -> Array[int]:
	var out: Array[int] = []
	var parts := key.split(":")
	var kind := parts[0]
	var arg := parts[1] if parts.size() > 1 else ""
	match kind:
		"straight":
			if arg.is_valid_int() and int(arg) >= 0 and int(arg) <= 36:
				out.append(int(arg))
		"split":
			var pair := arg.split("-")
			if pair.size() == 2 and pair[0].is_valid_int() and pair[1].is_valid_int():
				var a := int(pair[0])
				var b := int(pair[1])
				if a >= 1 and b <= 36 and a < b and (b - a == 3 or (b - a == 1 and floori(float(a - 1) / 3.0) == floori(float(b - 1) / 3.0))):
					out.append(a)
					out.append(b)
		"street":
			if arg.is_valid_int() and int(arg) >= 1 and int(arg) <= 12:
				var s := (int(arg) - 1) * 3
				out.append_array([s + 1, s + 2, s + 3])
		"corner":
			if arg.is_valid_int():
				var n := int(arg)  # the lowest number of the 2x2 block
				if n >= 1 and n <= 32 and n % 3 != 0:
					out.append_array([n, n + 1, n + 3, n + 4])
		"line":
			if arg.is_valid_int() and int(arg) >= 1 and int(arg) <= 11:
				var s2 := (int(arg) - 1) * 3
				for i in 6:
					out.append(s2 + 1 + i)
		"dozen":
			if arg.is_valid_int() and int(arg) >= 1 and int(arg) <= 3:
				for i in 12:
					out.append((int(arg) - 1) * 12 + 1 + i)
		"column":
			if arg.is_valid_int() and int(arg) >= 1 and int(arg) <= 3:
				for i in 12:
					out.append(int(arg) + i * 3)
		"red":
			for n in 37:
				if n != 0 and is_red(n):
					out.append(n)
		"black":
			for n in 37:
				if n != 0 and not is_red(n):
					out.append(n)
		"odd":
			for n in range(1, 37, 2):
				out.append(n)
		"even":
			for n in range(2, 37, 2):
				out.append(n)
		"low":
			for n in range(1, 19):
				out.append(n)
		"high":
			for n in range(19, 37):
				out.append(n)
	return out


static func is_valid(key: String) -> bool:
	return not numbers_of(key).is_empty()


# Coins won per coin staked (not counting the stake), from how many numbers the bet covers.
static func odds(key: String) -> int:
	var count := numbers_of(key).size()
	return 0 if count == 0 else floori(36.0 / float(count)) - 1  # 1 -> 35, 2 -> 17, 3 -> 11, 4 -> 8, 6 -> 5, 12 -> 2, 18 -> 1


# Coins handed back for one bet (stake + winnings), or 0 if it lost.
static func payout(key: String, amount: int, result: int) -> int:
	if amount <= 0 or not (result in numbers_of(key)):
		return 0
	return amount * (odds(key) + 1)


# bets: {key: amount}. Returns total coins handed back.
static func settle(bets: Dictionary, result: int) -> int:
	var total := 0
	for key: String in bets:
		total += payout(key, int(bets[key]), result)
	return total
