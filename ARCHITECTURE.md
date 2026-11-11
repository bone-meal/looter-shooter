# ARCHITECTURE (short map; keep current)

Engine: Godot 4.6, GDScript only. Renderer: Compatibility by default (HD 620 laptop, 2016 MacBook); Forward+ on machines that choose it in settings (GTX 1080). See diary/DECISIONS.md and diary/DECISIONS_REALISM.md.

| Folder | Purpose | May import |
|---|---|---|
| `core/` | Pure gameplay rules: damage, loot rolls, stats, save format. No Node, no rendering. | core/ only |
| `data/` | Weapons, parts, enemies, loot tables, tuning. JSON, referenced by string ID. | none |
| `game/` | Scenes and nodes: player, enemies, arena, HUD. Calls into core/. | core/, data/ |
| `net/` | Host-authoritative networking: intents in, host decides, fixed tick. | core/ |
| `tools/` | Dev scripts, e.g. data validator. | core/ |

Key files
- `game/main.gd` entry scene: owns settings + menus (`main_menu.gd`, `pause_menu.gd`, `settings_menu.gd`, shared `menu_widgets.gd`); Esc pauses.
- `game/game_session.gd` one play session: light, colosseum, player, wave director, HUD (debug readout when enabled in settings).
- `core/settings_state.gd` pure settings; `game/settings_io.gd` saves to user://settings.cfg and applies vsync/fullscreen/fps cap.
- View: yaw/pitch live on the player's head node, moved per rendered frame (physics interpolation is on in project.godot).
- `game/input_setup.gd` all input actions, defaults and rebinding ("key:87"/"mouse:1" strings saved in settings `bindings`).
- `game/controls_menu.gd` rebind screen opened from settings.
- `core/item_db.gd`, `core/inventory_state.gd`, `core/loot_roll.gd` pure item lookup, 36-slot inventory (9 hotbar) with cursor stack, loot rolling. Data: `data/items.json` (names + flavor text), `data/loot_tables.json`.
- `game/inventory_screen.gd` mouse inventory UI; `game/item_icons.gd` vector icons; `game/damage_numbers.gd` pooled floating damage numbers; `game/reward_area.gd` chest + return door shown after the arena is cleared.
- `game/explosives.gd` rocket + grenade pool with splash damage; `game/worm_model.gd` placeholder worm model.
- `core/armor_math.gd` (totals + damage after block/defense/resist), `core/status_state.gd` (burn/poison/chill). Armor items live in `data/items.json`; elements in `data/elements.json`.
- `game/cigarette_model.gd` lit cigarette + smoke; `game/crow_model.gd` giant crow; `game/club_island.gd` + `game/party_people.gd` neon club island and its animated people. Crow rules in `data/crow.json`.
- `game/island.gd` + `game/painting_art.gd` starting island (x=500): terrain that slopes into the sea (flat inside 12 m), ocean, palms, shore rocks, plants, and the paintings; F on a painting (interact) teleports.
- `game/colosseum.gd` oval arena build (swept wall, seat rows, column gallery, gate portals, cover pillars; one static body with trimesh collision); returns gate spawn points.
- `game/wave_director.gd` spawns enemies from `core/wave_state.gd`, owns `game/projectile_pool.gd` (48 pooled shots).
- `game/enemy.gd` one enemy node; decisions in `core/enemy_brain.gd`, hit points in `core/health_state.gd`.
- `game/weapon_models.gd` held-weapon models by weapon ID (flat-color primitives); weapon slots (keys 1-2) come from `slots` in `data/weapons.json`.
- `core/viewmodel_motion.gd` pure aim/recoil/reload animation state; `game/player.gd` applies it each rendered frame (per-weapon "view" tuning in `data/weapons.json`); `game/scope_overlay.gd` draws the sniper scope.
- `game/player_hud.gd` Payday-2-style HUD (health ring, weapon slots/icons/ammo pips, reload bar, wave + boss bar, damage flash); `game/enemy_bars.gd` health bars above enemy heads.
- `game/character_models.gd` blocky player and skeleton (sword / archer) models; `game/blood_effects.gd` pooled blood bursts; arrows come from `game/projectile_pool.gd`.
- `game/debug_overlay.gd` graphical debug HUD (frame graph, colored meters, icons), toggled in settings.
- Data: `data/enemies.json`, `data/waves.json`, `data/player.json`, `data/weapons.json`.
- Physics layers: 1 = world + player, 2 = enemies. Enemy shots only hit layer 1.
- `game/target.gd` is unused (replaced by enemies); safe to delete.

Rules
- Rendering code never lives in core/.
- Saves store IDs, rolled values and a version number.
- Clients send intents only; the host validates damage, loot rolls and pickups.

Run data validator:
`godot --headless --script tools/validate_data.gd`

## Online (milestone 5, part 1)
- addons/tube: third-party WebRTC session addon (MIT), trimmed to the runtime scripts. Needs the webrtc-native GDExtension (webrtc/ folder) on desktop.
- game/net_session.gd (node "Net" under Main): host/join by session ID, host-side profile check, roster, position sync (clients send only their own position), remote-player ghosts. Gameplay is not synced yet.
- game/lobby_menu.gd: host/join/start UI. data/net.json: app id, trackers, STUN, max players, send rate.
- core/join_check.gd: pure host check of a joiner's name/items/equipment. core/profile_sign.gd: HMAC. game/profile_io.gd: signed user://profile.sav.
- Co-op layer (children of the "Net" node): game/net_boss.gd (shared boss: host simulates, others show a puppet and send damage intents), game/net_spirits.gd (other players' regular enemies shown as see-through spirits), game/net_pvp.gd (player-vs-player hits validated by the host), game/remote_player.gd (other player's body + hit box on physics layer 8).
- Name loadouts (easter egg): data/player.json "name_loadouts", applied by game_session._apply_name_loadout().

## Host migration
- `game/net_session.gd` `_migrate()`: when the host drops mid-game, remaining peers sorted by id are candidates. Candidate N hosts a session with an ID derived from (old ID, N); the others rejoin it (3 s wait, 2 tries). Dead candidate is skipped; all fail -> back to lobby.
- `net_boss.adopt_as_host()` turns the new host's boss puppet into the real boss. `addons/tube/tube_client.gd` has a studio patch `forced_session_id`.
- Host does not cap or rate-limit boss/PvP hit claims (director decision).

## Appearance (customization)
- data/appearance.json, outfits.json (100), expressions.json (50) -> core/appearance_db.gd (pure; `sanitize` turns any input into a valid look) <- game/appearance_data.gd (cached loader).
- game/body_builder.gd `build(look)` -> Node3D "Character" > Torso (Head, ArmL, ArmR), LegL, LegR; helpers: face_builder, hair_builder, outfit_tops, outfit_gear, body_parts, body_ctx.
- Used by player.gd (`set_appearance`), remote_player.gd, lifeguard.gd, customize_menu.gd. Saved in profile `look`; synced via net_session `looks` + `send_look`.
- game/lifeguard.gd: fishing NPC on the spawn island; F near her opens game/customize_menu.gd via game_session.gd (`look_changed` signal -> main.gd -> net.send_look).

## Emotes
- game/dance_poses.gd: 8 pure pose functions (model, id, time). game/emote_wheel.gd: wheel UI. player.gd handles H (wheel, orbit camera, start/stop); emote id rides the state RPCs; remote_player.gd plays it.

## Graphics and lighting presets
- data/graphics.json: "graphics" presets (potato..ultimate: render_scale, msaa, fxaa, mesh_detail, view_distance) and "shaders" presets (off..ultimate: toon, outline, rim, sky, glow, fog, saturation, contrast, warmth, sun_energy, ambient, shadows).
- core/settings_state.gd stores the chosen IDs; game/settings_menu.gd has the two dropdowns.
- game/render_style.gd (child of game_session): applies viewport/environment/sun and restyles every StandardMaterial3D (toon, rim, shared outline next_pass) and PrimitiveMesh segment count on preset change; new nodes are styled via SceneTree.node_added. Unshaded, transparent and glowing materials are left alone.
- game/body_motion.gd: walk/idle/hold-weapon poses for player and remote player models. tools/render_shots.tscn renders each preset to tools/shots/*.png for checking.

## Casino (decisions: diary/DECISIONS_CASINO.md)
- core/ (pure, no rendering): wallet.gd (coins), slot_math.gd, blackjack_rules.gd, roulette_rules.gd, pachinko_sim.gd (deterministic 2D ball sim; peg lattice lookup, pooled arrays). Data: data/slots.json, casino.json, pachinko.json. Check scenes: tools/casino_check, tools/pachinko_check (logs next to them).
- game/casino_room.gd: annex east of the club (x 12..23, z -7..6 from the club centre, door in the south wall). Built from club_island.build(), returns {pachinko, slots, blackjack, roulette, crew, bj_dealer, rt_dealer}.
- game/pachinko_wall.gd: the back wall. Draws sim state (MultiMesh pegs and balls, pocket trays, sweeping aim marker, chase lights, launch console). Signal ball_landed(pocket, coins, name). game_session spends coins, calls launch(), adds winnings.
- Coins + progressive jackpot pot live in the signed profile ("extra": coins, jackpot) via game/profile_io.gd; game_session holds the Wallet; HUD shows coins near the club (player_hud.coins).
- tools/casino_shot.tscn renders the annex to tools/shots/.
- TODO: slot machines, blackjack and roulette tables, dealers, staff outfits.
- game/slot_machine.gd (3D cabinet + 3 spinning drums, symbol_art.gd draws the atlas), slot_screen.gd (bet/spin overlay). game/blackjack_table.gd + blackjack_screen.gd, roulette_table.gd (wheel, ball, layout) + roulette_screen.gd. game/casino_games.gd runs both table flows (spend, deal, dealer steps, pay) and is owned by game_session. game/staff_crew.gd = original clothed bunny-girl staff and dealers (outfits.json casino_* outfits).
- tools/casino_flow_check.tscn plays 8 blackjack rounds and 2 roulette spins through casino_games and checks wallet arithmetic (log next to it, ~60 s).

## Gun loot (decisions: diary/DECISIONS_LOOT.md)
- core/ (pure): gun_db.gd (data lookup), gun_gen.gd (generate, pick_tier with luck, validate = host-side anti-tamper), gun_stats.gd (final_stats shaped like a weapons.json entry + crit_chance/recoil/ads_fov/buffs/combos, display_name), gun_combos.gd (part COMBINATIONS: `combos` and maker-`matched` rules in gun_parts.json give extra mods, buffs and a name; derived from the parts each time, never saved or sent). A gun is IDs + rolled qualities + version only. Data: data/gun_loot.json (stats, 8 tiers, buffs), gun_parts.json (bodies + slots, part variants with `model` ids), manufacturers.json. Checks: tools/gun_gen_check.tscn, tools/gun_combo_check.tscn (every part set per body gives different stats).
- game/chip_stack.gd: chips + amount label on the casino tables.
- Wired (pass 1): inventory slots hold a rolled gun ({"id":"gun","count":1,"gun":{...}}, one slot per gun; saves as [id,count,gun], version 3; load drops any gun GunGen.validate rejects). game/player.gd builds the WeaponState of the gun's body from GunStats.final_stats (crit, free_shot, leech, burn, slow, shock/explosive via Explosives.blast, ammo on kill). game/tier_style.gd = tier colours incl. animated rainbow/pony. Inventory tooltip compares with the held gun; HUD shows tier-coloured name. Arena chest gives 2 guns (first guaranteed >= purple, data/gun_loot.json `chest`).
- Pass 2: core/drop_rules.gd (pure: drop chance, wave luck, boss/elite floors, elite affix + stats; data/drops.json). game/wave_director.gd emits `killed(where, id, elite, wave)` and spawns elites (enemy.elite = affix name, Label3D tag). game/loot_field.gd = world drops (beam, model, name tag, tier_sound.gd chime; cap + despawn). game/gun_vendor.gd = 3 casino crate kiosks (data/gun_loot.json `vendor`); game_session handles F pickup/buy (interact key is F; Q/E are the gun skills).
- Pony skin: game/pony_skin.gd (animated shader on pony gun models, world drop + held gun); tier json `skin`/`tag`.
- NOT built yet: part models/animations, pony uniques, drop/vendor sync online (each machine rolls its own loot).

## Gun skills (Q/E) (decisions: diary/DECISIONS_SKILLS.md, list: DESIGN_GUN_SKILLS.md)
- Data: data/skills.json (skill defs with [worst,best] numbers and cooldown); tier keys skills/skill_quality/skill_cd in data/gun_loot.json; passive buffs live in the same buffs list.
- core/skill_state.gd (pure): value, cooldown, describe, roll, check, per-gun cooldown tracker. core/gun_db.gd takes skills as the 5th constructor argument; core/gun_gen.gd (gun version 2) rolls + validates `skills`.
- game/skill_effects.gd (child of game_session; source = wave_director, explosives, numbers, follow = player): cast(db, entry, base_damage, feet, eye, forward, aim). Pooled visuals, caps: 2 wells, 4 drones, 16 bolts, 4 rings. Enemy hooks (game/enemy.gd): apply_freeze, apply_vulnerable, push.
- game/player.gd: use_skill(index) on skill_1/skill_2 (input_setup.gd), cooldown getters for game/player_hud.gd, on_enemy_killed (called from game_session._on_enemy_killed), _damage_mult, Glass Cannon health cap.
- Check: tools/skill_check.tscn (stand-in enemies, log + renders in tools/shots/skill_*.png).

## Character life (jiggle, NPC personality, idle)
- core/jiggle_spring.gd (pure spring) + game/body_jiggle.gd (driver attached by BodyBuilder.build; moves bust/glute balls tagged meta "soft") + data/jiggle.json.
- game/npc_chatter.gd + data/npcs.json: name plate, greeting/idle speech bubbles (uses NpcChatter.player_name, set by game_session), head follows camera. Attach via StaffCrew.add(..., npc_id) or NpcChatter.new().setup(model, id).
- game/body_motion.gd idle: weight shift, glances, blink (face_builder groups eyes under Face/Eyes), ~13 s right-arm fidget; used by player, remote players, staff.
- Scope recoil: weapons.json view `scope_kick`, player.gd `_kick_view`/`_update_view_kick`.
- Checks: tools/jiggle_check, tools/npc_check.

## Progression and player card (key P)
- core/progress_state.gd (pure): XP/level, stat points, trait slots, achievement counters + unlocks, card (callsign/emblem/title), from_dict sanitize, check() for host validation. Data: data/progression.json (curve, stats, traits, xp rewards), data/achievements.json (emblems, titles, achievements).
- game/card_screen.gd (tabs Card/Stats/Traits/Achievements) + game/player_card.gd (banner) + game/emblem_art.gd (emblem shapes). Wiring in game_session: `_progress`, `_award(kind, counters)`, `_apply_progress()` (player.set_progress_bonuses + NPC callsign), saved in profile extra["progress"], HUD level/xp bar. Luck: `_luck_mult()` into drops/chest/crates (DropRules.roll_drops luck_mult).
- Checks: tools/progress_check (rules), tools/card_shot (render).

## Omaha open world (decisions: diary/DECISIONS_OMAHA.md)
- Data pipeline (dev-time): tools/omaha_fetch.gd/.tscn (run on a machine with internet; Overpass -> data/omaha/raw/, DEV ONLY, keep out of exports) -> tools/omaha_bake.py (Python; projects, simplifies, chunks) -> data/omaha/map.json + data/omaha/chunks/r_RX_RZ.json. Origin Old Market, x east / z south, metres/5. Map data (c) OpenStreetMap contributors, ODbL.
- core/omaha_geo.gd: pure lat/lon projection, point-in-polygon, rect test, district lookup. Data: data/omaha/districts.json (districts, tiers, enemy mixes, boss lairs), data/omaha/enemies.json (stats + spawn tuning), drops in data/drops.json.
- game/omaha_world.gd: streams 192 m chunks (radius 3) around the player at world offset x=+10000; per chunk one flat vertex-colour mesh (parks, water, rail, roads) + one building mesh (window texture) + box colliders; one big ground plane. `blocked(xz)` for spawn checks.
- game/omaha_spawner.gd: district-based groups near the player, despawn far away, 5 boss lairs with respawn timer. Uses game/wave_director.gd `spawn_custom` / `despawn` so bars, skills, explosives and loot keep working.
- game/game_session.gd: second painting on the island (game/island.gd `build_painting`, game/painting_art.gd `omaha_texture`), `_enter_omaha` / `_leave_omaha`, dusty fog while inside, exit painting at the Old Market spawn.
- tools/omaha_check.tscn: unit tests + data validation + renders tools/shots/omaha_a..c.png.

## Realistic look (decisions: diary/DECISIONS_REALISM.md)
- data/graphics.json: lighting preset "realistic" + a "realistic" block per graphics tier (texture size, map count, shadows, SSAO, prop density, water, LOD, and "forward" extras used only on Forward+). game/render_style.gd applies it.
- Two looks share one world: every builder asks for named surfaces and registers look-only pieces, so switching preset flips flat colours <-> PBR textures in place (no rebuild).
  - game/surface_library.gd + data/surfaces.json: surface id -> CC0 texture set, tile, tint; one shared material per surface.
  - game/ground_blend.gd (island ground: sand + grass + wet shore), game/water_surface.gd (ocean), game/look_props.gd (pieces that exist in one look only, scatter density by tier).
  - game/model_library.gd (meshes out of CC0 glTF files), game/palm_builder.gd (code-built palm), game/sweep_mesh.gd (profile swept around an ellipse or circle).
- Assets: assets/cc0/ (textures, hdris, models from Poly Haven, CC0; list in assets/cc0/CREDITS.md). Download more with tools/cc0_fetch.tscn + tools/cc0_jobs.json (run on a machine with internet, then let the editor import).
- Renderer choice: settings `renderer`; game/renderer_switch.gd relaunches the game once at start on Forward+ when chosen. project.godot stays on Compatibility.
- Check: tools/realism_shot.tscn renders the island and colosseum per tier (and again on Forward+) into tools/shots/real_*.jpg with draw calls, triangles and frame time in tools/realism_shot*.log.
- Rigged characters (2026-11-10, players only so far; NPCs still use game/body_builder.gd):
  - data/characters.json: bodies, outfits, hairstyles, skin reference, clip names for motion, anchors. game/rigged_body.gd `build(appearance)` -> Node3D (null when the packs are missing; callers then fall back to BodyBuilder); `animate(move, holding)`, `emote(id)`, `head_anchor()`, `hand_anchor()`, `third_person_hold()`.
  - core/appearance_db.gd validates the look keys `rig_outfit` / `rig_hair` against data/characters.json. game/body_motion.gd and game/dance_poses.gd hand rigged bodies to their own clips. game/player.gd, game/remote_player.gd and game/customize_menu.gd build rigged bodies first.
  - tools/pack_fetch.tscn (unpack the Quaternius zips), tools/anim_bake.tscn (retarget clips -> assets/anim/<skeleton>.res), tools/character_shot.tscn (pictures + draw calls in tools/shots/character_*.jpg, tools/character_shot*.log).
- Modelled assets (2026-11-10, originals made with Blender's Python module; the scripts are developer tools, the game only loads the files):
  - tools/blender/kit.py (shapes, lofted organic parts, per-part colours, generated PBR textures, glTF export) used by weapons.py (8 guns with Barrel / Mag nodes and Mount<Slot> markers), weapon_parts.py (12 part models), creatures.py (skeletons, clockwork bear, crow), wasteland.py (the ten Omaha enemies from one humanoid builder + SPEC table). Output: assets/models/weapons/, weapons/parts/, creatures/.
  - game/weapon_models.gd loads a gun model by weapon ID (old code-built gun = fallback and source of hold position). game/gun_parts_view.gd `apply(model, gun, db)` shows a rolled gun's parts on it (barrel scale, part models on the mounts, maker colours, sight height) from the part `view` entries in data/gun_parts.json; used by game/player.gd and game/loot_field.gd.
  - game/character_models.gd loads creature models and puts the enemy's own tintable material on their main surfaces (`skeleton`, `clockwork_bear`, `wastelander`); game/enemy.gd picks by the enemy's `model` id (data/enemies.json, data/omaha/enemies.json). game/crow_model.gd loads the crow.
  - Checks: tools/weapon_shot.tscn (`-- --parts` fits full part sets), tools/creature_shot.tscn (all creatures + real Omaha enemy nodes), tools/import_assets.tscn (headless import after copying asset files), tools/game_boot_check.tscn (runs the real game per renderer).

## Chat, admin commands, pony uniques (decisions: diary/DECISIONS_FANTASY.md)
- Chat: game/chat_box.gd (HUD lines + input; Enter = chat, / = command), game/net_chat.gd (net child "Chat": host relays lines, runs world commands for players it has /op'd). core/chat_command.gd parses; data/commands.json is the command table (name, usage, help, scope self | world | host).
- game/admin_commands.gd `run(text, near)` does the work through the session (`local_player`, `director`, `progress`, `wallet`, `travel`, `fantasy`). Off unless SettingsState.dev_commands (on in debug builds).
- Unique guns: data/gun_uniques.json (fixed body, maker, parts, buffs, skills + a bonus to every stat). core/gun_gen.gd `unique(db, id)` builds one, `validate` rebuilds and compares (an edited unique is refused); a gun carries `"unique": id`.

## Fantasy world "Aurelind" (third painting; decisions, gaps and tried-and-failed: diary/DECISIONS_FANTASY.md)
- Pure rules (core/, no rendering): fantasy_terrain.gd (height with lakes cut in, colour, region weights, mood, roads, `water_at` fresh/salt/lava, `trodden`), fantasy_layout.gd (WHERE everything stands: houses and props of every place, roadside sites, trees, gather nodes, fishing spots on real water; also `walk` / `blocked` / `push_out` so creatures go around all of it without physics), spell_book.gd, skill_levels.gd, fantasy_bag.gd, quest_log.gd, text_book.gd (reads the writers' files), fantasy_data.gd (`load_all()`: every rule file + every text, merged; lists missing texts).
- Data (data/fantasy/): world.json (regions, places, lakes, roads, people), layouts.json (what a town / village / camp / tribe camp is made of), props.json (model footprints, written by the Blender scripts), spells.json (+ `look` per substance), skilling.json, gear.json, quests.json, enemies.json (+ `walks`, `debris`, boss `moves`, `tribes`), sounds.json. NO text in these: all names and lines are in data/fantasy/writing/*.txt (`[kind id]` sections, `key: text` lines, `#` notes saying WHO speaks / WHAT is named).
- game/fantasy_world.gd is the hub (lives at x = 20000): loads through fantasy_data, builds everything below, keeps the player's own look and lays each region's haze / sun colour / sky tint over it, gives xp / items / rewards, saves (bag, skills, quests, found places).
  - Land: fantasy_land.gd (threaded chunks + collision, far mesh, sea, lake water) with fantasy_ground.gd (one shader: two region grounds + rock on slopes + trodden yard / road) -> fantasy_scatter.gd (trees, grass tufts, gather nodes from the layout) -> fantasy_places.gd (places and sites as one MultiMesh per model + box colliders, stations, quest people, ordinary folk).
  - Looks: fantasy_models.gd maps a model's material NAME (plaster, timber, thatch, fur, scale ...) to a surface `fx_<kind>` (data/surfaces.json, grey grain texture x model colour); models store calmed, screen-encoded colours (tools/blender/fantasy_kit.py `real`), the land uses the same sum (`FantasyGround.toned`).
  - Play: staff_caster.gd -> spell_book -> spell_effects.gd (forms, hits) + spell_motes.gd (the flying bits that tell substances apart, pooled MultiMeshes); fantasy_work.gd (talk, stations, gathering, fishing by kind of water).
  - Creatures: ordinary game/enemy.gd nodes with `walker` set (hub.walk_world -> layout.walk), spawned by fantasy_spawner.gd (roaming packs, bosses, the two desert tribes fighting on their battlefield); boss_moves.gd runs each boss's special attacks from data (warning marks, then the strike).
  - Indoors: core/fantasy_interiors.gd (pure: which building is what inside, door spots, furniture, loot rolls; data/fantasy/interiors.json) + game/fantasy_rooms.gd. The main story's WALK-IN houses (models open_house_<scheme>, open_farmhouse with "walls" in props.json) are furnished in the open world by the layout and their people stand inside; every other building is entered at its door into a room built on the spot far from the map (hub-local +4000 m south, 300 m up), windows painted with the land outside; containers give loot by table and refill (per player, saved as "looted").
  - Cost: fantasy_places.gd folds each place's buildings into ONE mesh (a few per frame), small props cast no shadows and are drawn only within the tier's small_m; graphics tiers (data/graphics.json "fantasy") also set motion (0-3: what still animates) and bits (share of spell particles).
  - On screen: fantasy_style.gd (the shared look: ink panels, gold line, book font, element signs) used by fantasy_hud.gd, element_box.gd, fantasy_map.gd (key M; chart painted once on a worker thread) and the window fantasy_panel.gd (frame, icon tabs, mouse, scrolling, shared helpers `cell` / `item_cell` / `card_*` / `signs`) whose pages are one file each: panel_skills.gd, panel_bag.gd, panel_quests.gd (also talking), panel_spells.gd, panel_station.gd (recipes as pictures). Everything is icons first: an item's `icon` + `color` in data/fantasy/gear.json, a skill's `icon` and `stations` in skilling.json. Sound: fantasy_sounds.gd (pooled players, region ambience) with files from tools/make_fantasy_sounds.py.
- Online: game/net_fantasy.gd (net child "Fantasy"): host runs creatures, tribes, boss moves (`_move` replays them on clients) and the party quest log; clients show puppets and send hits / events as intents.
- Models: tools/blender/fantasy_kit.py (shared), fantasy_props.py, fantasy_life.py (buildings, tools, camps), fantasy_creatures.py; textures: tools/make_grain.py. Checks: tools/fantasy_check.tscn (data + writing), fantasy_creature_shot.tscn, spell_look_shot.tscn, boss_moves_shot.tscn, game_boot_check.tscn with tools/boot_cmd.txt. After changing models: unpack_inbox clears their cached imports (a changed .bin alone is NOT re-imported).

## Icons (whole game)
- tools/make_icons.py draws the icon sheet (assets/ui/icons_tint.png = the part that takes a colour + dark outline, icons_ink.png = fixed colours) and data/icons.json (shape -> cell). game/icon_art.gd `IconArt.draw(canvas, shape, rect, colour, alpha)` draws one. Users: the fantasy window and HUD, game/item_icons.gd (armour = the icon of its slot in the item's `color` from data/items.json; guns keep their drawn shapes), game/inventory_screen.gd (empty equipment slots show the faint icon of what goes there).
- Tier names: game/tier_style.gd `draw_name` writes a tier's `tag` in its own `tag_font` (data/gun_loot.json; pony = "*PONY*" in assets/fonts/Chewy-Regular.ttf, bold and slanted), used by the HUD, the inventory tooltip and world drops.
