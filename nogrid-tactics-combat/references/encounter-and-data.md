# Encounter Setup, Data, and Saves

Everything around the combat loop: how a battle is assembled and torn down, how units/abilities/items are modeled as data, and how state is persisted. The unifying idea — borrowed wholesale from the inventory sources — is a **three-layer data model**: ScriptableObject *definitions* (shared, immutable) → plain-C# *runtime instances* (mutable per-encounter state) → thin MonoBehaviour *holders/views* that present them.

## Contents

- [Encounter setup and scene flow](#encounter-setup-and-scene-flow)
- [Data: definitions vs runtime instances](#data-definitions-vs-runtime-instances)
- [Items, equipment, and consumables](#items-equipment-and-consumables)
- [Save and load](#save-and-load)

## Encounter setup and scene flow

The tutorials converge on an **additive two-scene** layout that fits a CRPG well:

- A **persistent systems scene** — the combat manager, camera, UI canvas, forces — loaded once and set as the *active* scene (so instantiation and lighting resolve there).
- A **battlefield scene** loaded **additively** per encounter, holding only terrain and props. Designers edit battlefields in isolation; systems never move between scenes.

Spawn points are **authored world transforms** (position + facing), not grid anchors — snap them to the NavMesh with `NavMesh.SamplePosition` at spawn. A probabilistic spawner (per-entry chance to place a prop/enemy) is a cheap way to vary encounters.

**Decouple the scenes with a ScriptableObject channel, not `FindObjectOfType`.** The tutorials' best version: a placement-list SO into which battlefield objects self-register on `Start`, read by the systems scene. Generalize this to an **encounter descriptor** passed from the world map into the battle: which battlefield, which units, which spawn points, mission parameters.

⚠️ **The footgun:** ScriptableObject state persists across scene loads and editor sessions. Any SO used as a runtime channel must be **explicitly cleared** on encounter start and on teardown (`OnDestroy`), or stale data leaks into the next battle. And per the SKILL.md rule: snapshot the SO's contents into immutable combat state at battle start — never read or write a live mutable SO during resolution, or determinism and replay break.

On the world-map ↔ battle round trip, carry an encounter *descriptor* (and on the way back, the resulting squad state), not just a scene name string — the tutorials only pass the battlefield name and rely on scene lookups, which doesn't preserve squad state.

## Data: definitions vs runtime instances

The split that the inventory series nails, applied to combat:

- **Definition (ScriptableObject):** the shared, authored template. A `UnitDefinition`, `AbilityDefinition`, `ItemDefinition` — stable identity plus rules data (base stats, an icon, an ability's range/effects/target-selection strategy, an item's stack size and combat fields). Subclass a base SO for specialized types. Definitions are referenced, never copied or mutated.
- **Runtime instance (plain C#):** the mutable per-encounter state — current HP/AP, position, cooldowns, status list, a slot's `(definition reference, count)`. This is what lives in `CombatState`, what gets cloned for AI simulation, and what gets serialized. It is **not** a MonoBehaviour.
- **Holder / view (MonoBehaviour):** owns a runtime instance, raises change events, and renders. Keeps Unity lifecycle out of the data.

Wire data → UI with **change events**, not polling: a runtime container fires "this slot/stat changed", and views subscribe and refresh only the affected element. The UI holds no authoritative state. This is the same observer boundary the combat HUD, initiative tracker, and status panels should use.

## Items, equipment, and consumables

Model combat items as definitions + runtime slots (above). Practical patterns from the sources:

- An **`ItemDatabase` ScriptableObject** holds every item definition and assigns each a **stable integer ID** (a context-menu action scans `Resources.LoadAll` and numbers them). Saves store the stable ID, not Unity's volatile instance ID; load resolves ID → definition. This is what makes persistence survive editor/build sessions.
- **Stacking math:** headroom = `maxStack − current`; transfer only what fits, keep the remainder; half-split via a temporary slot used only for intermediate arithmetic. Reusable for ammo/charges/consumable stacks.
- A unit can own **several holders** (equipped / quick-use / pack), all sharing one container abstraction and one save contract.
- **Select-then-use** maps an item to a combat action: track a selected index, and "use" calls the definition's effect — consume (decrement) or equip. A using-an-item action flows through the same resolver as any other `GameAction` (see `turn-and-resolution.md`).
- **`GetAllItemsHeld()`** aggregation ("how many of X across all slots?") is handy for ability/cost gating.
- Add a combat item-type/category field (consumable vs equipment, target type, action cost) — the inventory sources only imply it via stack size.

The shop/merchant economy from the sources is **out of scope** for combat. Two ideas survive: keep price/cost math out of the UI in a static helper, and the **staged-mutation-before-commit** pattern (a cart that mutates a copy and commits only on confirm) — which is exactly the shape of an **action preview / combat forecast** (compute the outcome on a clone, show it, commit only when the player confirms).

## Save and load

For a single-player CRPG, `JsonUtility` is sufficient and the sources' approach is sound:

- Convert runtime state into plain **`[System.Serializable]` DTOs** — no MonoBehaviour, no SO references. Items become `{ stableId, amount }`. Resolve IDs back to definitions via the `ItemDatabase` on load.
- **Nest DTOs** to build the save graph: a `UnitSaveData` contains its `InventorySaveData`; an `EncounterSaveData` contains unit positions, HP/AP, cooldowns, status lists, the initiative order, **and the RNG seed/stream position**. Serializing the seed is what lets a battle replay or resume deterministically (see `turn-and-resolution.md` and `testing-and-determinism.md`).
- Persist to `Application.persistentDataPath` with `File.WriteAllText`/`ReadAllText`. Avoid the deprecated `BinaryFormatter`.
- Identify stateful world objects (chests, defeated enemies, levers, encounter flags) by a **stable GUID** via a `UniqueId` component, keyed in a central save dictionary. (`JsonUtility` can't serialize a `Dictionary` directly — use a `[Serializable]` wrapper with parallel key/value lists via `ISerializationCallbackReceiver`.)
- A static save/load broker exposing `OnSave`/`OnLoad` events lets each system serialize itself without a central object knowing all of them.

Because combat state is plain data (the spine), **saving combat is just serializing that state** — the same property that enables testing, AI simulation, and replay. Keep DTOs as pure snapshots; don't store live system references in save data.
