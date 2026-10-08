# Evidence Genesis development instructions

- The game is a teachable local-agent prototype, not AGI. Never invent completed tasks or model training.
- Preserve the offline template path. Clearly label generated documents by engine.
- Character memory is user-controlled; allow inspection, correction, deletion, and backup.
- User input and model output are untrusted text. Escape HTML; never execute returned instructions.
- Local AI connections are loopback-only with no silent cloud fallback. Do not commit model weights or personal saves.
- Game animations must correspond to real task state. Progress requires user approval.
- No payment, messaging, calling, file deletion, or arbitrary command execution in this milestone.
- Keep the browser client dependency-free and serve through the standard-library Python launcher.
- Before opening a PR: run `npm test`, `npm run check`, and `python -m unittest discover -s tests -p 'test_*.py'`.
- Check the teach/correct/create/approve flow in a browser, reload persistence, and mobile widths.
