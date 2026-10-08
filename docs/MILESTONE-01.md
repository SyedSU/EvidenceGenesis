# Milestone 01: the first workshop

## Implemented scope

Two original pixel-art characters in an isometric workshop; character selection, renaming and roles; feeding/resting; room lighting and plant placement; individual lesson notebooks with correction/deletion; template document generation; optional local-model transport; review/edit/approval; Markdown/HTML export and browser print-to-PDF; local browser persistence and backup/restore.

The visual room is drawn from code at 450×330 and upscaled without smoothing. It uses no downloaded art, sprites, fonts, or paid services.

## Honest boundaries

- Teach means saving retrievable context. It is not neural-network training or AGI.
- Template mode organizes user notes deterministically and supports only documented preference keys and glossary entries.
- Local AI runs through a separately installed model. No model-weight download or inference benchmark is performed in this milestone.
- Progress marks user-approved output, not independent evidence of general competence.
- Feed/rest restore energy immediately as a prototype game mechanic; there is no real daily lifecycle yet.
- No arbitrary automation, background scheduling, skill marketplace, multiplayer, voice input, or installer.
- The local server is a development runtime, not a hosted multi-user service. Keep it bound to loopback.

## Next milestones

1. Benchmark an actual local model against document acceptance tests on the user's hardware.
2. Add structured skills with explicit inputs, outputs, and tests before expanding tool access.
3. Expand character animation, rooms, inventory, and lifecycle without obscuring real task status.
4. Package a desktop app after validating the workflow and hardware requirements.
