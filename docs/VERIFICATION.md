# Verification for founding prototype

## Executed checks

- JavaScript game-rule tests: lesson correction and isolation, save restoration, real format changes, sign-off/glossary use, approval progress without double credit, safe Unicode-preserving export, supported Markdown rendering, and invalid-input rejection.
- Python runtime tests: health discovery, task/context transport to a controlled mock model, rejected cross-origin requests, input validation, loopback-only model configuration, static-file isolation, and failed-model handling without a cloud fallback.
- JavaScript syntax checks and Python bytecode compilation.

The mock model tests prove transport, not language-model quality. No actual model inference has been run in this environment.

## Browser verification blocker

A local Playwright browser could not be installed: the downloaded archive was invalid/truncated. The available cloud browser could not reach the loopback application server. The interface is therefore awaiting browser, responsive-layout, keyboard, and print-dialog verification. Do not treat it as a production-ready release.

## Manual acceptance checklist

- Start `python runtime/server.py`, open the displayed address, and check that the scene and controls render.
- Teach `format` → `numbered steps`; create from source notes; review and approve; reload and confirm memory/output/progress persist.
- Edit the preference to `bullet points`; repeat and confirm the new format.
- Confirm Pip's notebook is separate from Milo's.
- Rename a companion, feed/rest, switch lighting, and move the plant.
- Download Markdown and HTML. Open HTML and confirm readable headings/lists and escaped input.
- Print/save PDF through the browser; inspect layout and Urdu text if supplied.
- Download a save backup and restore it. Invalid backups must not replace current state.
- Test a disconnected local model: show an error and retain the notes.
- Run with a real compatible model and review factual accuracy and lesson adherence.
- Test widths 320, 768, 1024, and 1440; keyboard-only controls, tab navigation, dialogs, and focus indicators.
