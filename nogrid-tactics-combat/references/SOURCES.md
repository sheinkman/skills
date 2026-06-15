# Sources

Attribution for the material distilled into this skill. **No verbatim transcript text or copied code** is reproduced anywhere in the skill — every technique is re-expressed in our own words and adapted from grid/tile designs to the no-grid model. Captions were pulled with `yt-dlp` (auto-subs); several non-English-origin tutorials had heavily auto-translated captions, so reconstructed specifics are approximate and flagged in the skill where they drive a design choice.

## Tactics RPG in Unity (grid-based series)

Playlist: https://www.youtube.com/playlist?list=PL0GUZtUkX6t4JrdjOoAF2ayH-ksVtgpqy
The primary combat source. Grid- and MonoBehaviour-coupled throughout; we took its turn-flow, command, damage, and elevation *ideas* and rebuilt them in continuous space with the resolution-vs-presentation boundary on top. Episodes 06, 08, 09, 32, 33 had no usable English captions and were not ingested.

- **Ep 1 — Grid foundation:** pure `Node` data vs `Grid` scene component; obstacle-baked walkability → translated to NavMesh baking.
- **Ep 2 — Click placement:** mouse-ray world picking; Character(logic)/GridObject(spatial) split.
- **Ep 3 — Optimization + elevation:** downward-raycast height sampling — reused directly for continuous elevation.
- **Ep 4 correction:** width/length array-ordering bugfix (grid-only artifact).
- **Ep 4 — A\* pathfinding:** clean pure `FindPath`-returns-data; replaced by `NavMesh.CalculatePath`.
- **Ep 6 — Animator Controller:** the canonical resolution-vs-presentation cautionary tale (animator-param lag).
- **Ep 8 — Map highlight:** highlight as a consumer of a precomputed reachable set; object pooling.
- **Ep 8.5 — Highlight over terrain:** URP depth-override draw (prefer Unity 6 Decal Projectors).
- **Ep 9 — Selection:** centralized raycast selection; marker-component opt-in; "model is only visual".
- **Ep 10 — Movement range:** budget-limited Dijkstra flood-fill → NavMesh path-length budget in meters; difficult terrain → area costs.
- **Ep 11 — Attacking:** attack range as a set + AoE-around-center; flags attack-resolved-through-animation.
- **Ep 12 — Mouse input refactor + marker:** single source-of-truth pointer input; clean compute-vs-present boundary.
- **Ep 13 — Command pattern (move):** CommandInput→Command→Manager dispatch shape; flags execute-is-the-animation.
- **Ep 14 — Command pattern (attack):** polymorphic dispatch, distance/team/bounds candidate filter; flags turn-flow-gated-on-animation; line-of-sight gap.
- **Ep 15 — Issuing/executing commands:** select→command-menu→issue-to-receiver seam.
- **Ep 16 — Character turn:** two-flag (`canMove`/`canAct`) action economy.
- **Ep 17 — Rounds and game menu:** singleton round manager, self-registering units, `NextRound` refresh.
- **Ep 18 — Turns:** faction alternation; player-interactive vs AI-auto routing seam.
- **Ep 19 — Attacking function:** HP/MP stat wrappers, AoE-in-radius; the heaviest damage-in-animation entanglement to invert.
- **Ep 20 — Input fixes + spawner:** menu-vs-world input arbitration; probabilistic encounter spawner.
- **Ep 21 — RPG system expanded:** accuracy/dodge/crit/armor/resistance + min-damage floor — the pure damage model to emulate.
- **Ep 22 — Victory conditions:** defeat-all-enemies, any-alive check; flags victory-checked-on-animation-completion.
- **Ep 23 — Elevation + status panel:** per-edge climb gate `abs(ΔE) > climb` → translated to grade-limited path segments.
- **Ep 24 — RPG system:** derived stats via single-source getters; flags per-frame HP-bar polling.
- **Ep 25 — Leveling up:** separate `Level` holder; rate-based attribute growth.
- **Ep 26 — Status panel:** per-field setter components; render vs visibility-policy split.
- **Ep 27 — Refactoring scene setup:** additive Combat-Essential + Combat-Stage scenes; `StageManager` service-locator.
- **Ep 28 — World↔Battle transition:** scene round trip; turn-ownership input gating; flags fused victory/panel/scene-load.
- **Ep 31 — ScriptableObjects as data containers:** SO as scene-decoupling channel; the must-clear-on-teardown footgun.

## Combat standalones

Individual videos provided as standalone watch URLs in the task. Caption-only downloads don't preserve video IDs in filenames, so titles are authoritative; the one confirmed ID mapping is noted.

- **I made XCOM in 25 HOURS! — Code Monkey** (https://www.youtube.com/watch?v=ezlkGhFBrmg): the Action-interface + on-complete-callback + per-action valid-targets architecture, AP economy, cover/hit-% and overwatch concepts. Grid implementation not used.
- **Grid Combat System! (Turn-Based, XCOM) — Code Monkey:** grid turn/move-validation/attack-range mechanics; the baseline translated to NavMesh budgets and world-space checks.
- **How to make a tactics game in only two weeks (Godot):** the Action→Effect→ActionResolver data-driven model and the target-selection-method concept; cited as the cautionary example for keeping damage resolution out of the attack animation.

## Inventory System series (items, equipment, save/load)

Playlist: https://www.youtube.com/playlist?list=PL-hj540P5Q1hLK7NS5fTSNYoNJpPWSL24
Adjacent material. Contributed the definition(SO)-vs-runtime-instance split, the data→UI change-event boundary, stacking/splitting math, multiple-holders-per-entity, select-then-use, and the JSON + stable-GUID save architecture. The shop/merchant economy (Parts 12–16) is out of scope; only its price-math-out-of-UI habit and the staged-mutation-before-commit (≈ action preview) pattern carried over.

- **Parts 0–7 — backend, UI, stacking, chests, backpack:** three-layer holder/container/slot model; `OnSlotChanged` data→UI event; headroom/half-split stack math; generic dynamic display; multiple holders with priority pickup.
- **Save Game System + Parts 8–10 — persistence:** `JsonUtility` + `[Serializable]` DTOs in `persistentDataPath`; `{stableId, amount}` item serialization; `ItemDatabase` SO assigning stable IDs; nested save graph; static save/load event broker; `UniqueId` GUID identity; `SerializableDictionary` workaround.
- **Part 11 — dropping items:** drop/pickup prefab flow; unique-ID integrity fix.
- **Parts 12–16 — shop system:** SO-config vs runtime-state split (reinforces the pattern); `GetModifiedPrice` keeps math out of UI; `GetAllItemsHeld` aggregation; staged cart → action-preview analog. Otherwise out of scope.
- **Part 17 — hotbar selection and use:** selected-index tracking and consume/equip on activate → select-then-use combat action loop.

## Environment / level-art videos (attributed, not folded in as combat technique)

These teach terrain, environment art, isometric assets, asset generation, and URP rendering — not combat systems. They are recorded here for completeness; the only transferable nuggets are terrain elevation as a surface combat sits on, NavMesh baking over terrain, height sampling, and camera/post-processing framing.

Playlist (environments): https://www.youtube.com/playlist?list=PLsg5Z44PDzwTF9Bo0aDU7PeV_6Djz86dm

- **Using Terrain Tools to Create 3D Landscapes; How to Make Beautiful Terrain (URP); How to build beautiful landscapes; Creating a Low-Poly Lagoon; Converting a Project to URP:** terrain/landscape/rendering tutorials — no combat technique folded in.
- **How I Learned Procedural Generation:** procedural mesh + Perlin height — referenced only for height-sampling/NavMesh-baking context.
- **Build a beautiful 3D open world in 5 minutes (Unity 6); Quick Tips for Beautiful Terrain (Synty):** terrain sculpting + asset import + URP post-fx — referenced only for terrain-surface/camera context.
- **How to Create Isometric 2D Game Assets; Using AI to Generate Game Assets For Free:** art/asset generation — no combat technique folded in.
