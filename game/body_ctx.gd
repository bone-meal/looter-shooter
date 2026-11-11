# Purpose: the measurements, colors and body-part nodes of one character being built; passed between the body, face, hair and outfit builders.
# Dependencies: none (plain data holder).
extends RefCounted

var female := false
var weight := 1.0
var bust := 0.0
var glutes := 0.0

# Sizes in meters (torso-local: y 0 is the hip line, chest ends near 0.52, the head pivot sits at 0.60).
var head_w := 0.25
var head_d := 0.23
var chest_w := 0.4
var waist_w := 0.34
var hip_w := 0.34
var depth := 0.22
var arm_t := 0.115
var leg_w := 0.15
var leg_x := 0.09

var skin: Material
var m1: Material  # outfit color 1 (main)
var m2: Material  # outfit color 2 (bottom / secondary)
var m3: Material  # outfit color 3 (accent)
var c1 := Color.WHITE
var c2 := Color.WHITE
var c3 := Color.WHITE
var hair_color := Color.BLACK

var torso: Node3D
var head: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var hide_hair := false


func slot(slot_name: String) -> Material:
	if slot_name == "m1":
		return m1
	if slot_name == "m2":
		return m2
	return m3
