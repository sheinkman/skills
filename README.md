# skills

Installable [Claude Code](https://claude.com/claude-code) skills.

## Install

```sh
npx github:sheinkman/skills <skill-name>
```

Pass `--force` to overwrite an existing skill at `~/.claude/skills/<skill-name>/`.

Install multiple at once:

```sh
npx github:sheinkman/skills grill-plan some-other-skill
```

## Skills

- **grill-plan** — Adversarial planning skill that grills implementation plans for hidden assumptions, edge cases, and missing context before you commit to them.
- **unity** — Unity 6.4 + URP skill: C# gameplay code, custom Render Graph passes, audio, AI/NavMesh, 2D/isometric, Addressables, performance, editor tooling, and shipping builds. Targets the current Supported release with Forward+.
- **nogrid-tactics-combat** — Turn-based tactical combat with no grid (free positioning in continuous 3D) for a Unity 6 CRPG on the Anime 5E ruleset: NavMesh movement budgets, world-space targeting, raycast line-of-sight/cover, initiative and action economy, a pure `ActionResult` resolution pipeline, enemy AI that simulates outcomes, save/load, and a deterministic engine-independent (`.asmdef`-isolated) rules core.

## Add a skill

1. Drop the skill directory at the repo root (must contain a `SKILL.md`).
2. Add a bullet to the list above.
3. Commit and push to `main`. `npx github:sheinkman/skills <name>` picks it up immediately.
