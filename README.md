# Evidence Genesis

A native 2.5D companion game for Windows. Walk around a little workshop, care for two companions, teach editable lessons, and turn source notes into documents using the bundled local AI.

## Play the packaged game

Extract the entire `EvidenceGenesis-Windows-v0.4.0.zip`, open its `EvidenceGenesis` folder, and double-click `EvidenceGenesis.exe`. Keep `brain/` and `model/` beside the executable. No Unity, Python, editor, account, or API key is required on the player's computer.

Windows 10/11 x64 and OpenGL 3.3 graphics are required. AI speed depends on CPU and available memory; minimum hardware has not been benchmarked. The package uses a small CPU model and offers clearly labeled template mode. The preview executable is unsigned. On a fresh Windows installation, the AI may require Microsoft’s C++ x64 runtime. If missing, the game provides an official Microsoft download link in Settings; install it once and restart. That setup download requires internet.

WASD/arrows or click: move. E: interact. Tab: switch companions. Escape: close a panel or settings. Teach → Create → Review → Approve is the first quest. Use Settings to rename companions, assign roles, feed berries, change lighting and music, or back up and restore the workshop. Approved documents earn skill stars; two stars unlock a flower garden.

Markdown and printable HTML export are implemented. HTML can be printed to PDF through the operating system's browser print dialog. Direct PDF generation is not implemented.

## Version 0.4 gameplay

The native main menu offers Continue, New Workshop, Settings, Credits and Exit. Named workshops isolate companions, memory, documents and rewards. For a new game, choose New Workshop. To bring forward a version 0.2 or 0.3 workshop, choose **Import legacy workshop (keep original)** from the main menu. Import creates a separate profile and preserves the original `workshop.json` and its backup byte-for-byte. Subsequent **Continue workshop** opens the selected profile; Continue does not automatically import legacy saves. Profile payloads use version 4 and distribution compatibility epoch `saveSchema=4`; older releases cannot open the new profiles, so rollback across these save compatibility epochs is unsupported. Saves are in `profiles/<id>.json`, indexed by `profiles.json` inside the platform EvidenceGenesis directory. A corrupt profile/index is preserved rather than silently replaced.

Document task history records queued, running, completed, failed and canceled work. Interrupted work becomes failed, retains source notes and requires intentional retry. No recovery automatically awards rewards. Settings provide music volume, standard/large UI text independent from the pixel world, fullscreen and reduced ambient motion. Keyboard remapping and direct PDF generation remain unavailable.

The mission board tracks six milestones: teaching, first delivery, first approval, feeding and rest, approved work from both companions, and planting a garden. Rewards can be collected once. Workshop upgrades include a flower garden, glowing evening lanterns and a picnic reading corner. Companion levels increase every three approved documents. Legacy version 0.2 and 0.3 data migrate only when explicitly imported into a new profile; companion names update on the selection buttons.

## Included AI and data

The Windows package contains llama.cpp b11429 and Qwen2.5-0.5B-Instruct Q4_K_M. The game starts an authenticated loopback-only model process and stops its own process when closing. No cloud fallback is used. Teaching saves user-controlled context; it does not train model weights or create AGI. The small model may make mistakes; review its output.

Saves are kept in the platform's `EvidenceGenesis` user-data directory, usually `%APPDATA%\EvidenceGenesis` on Windows. The profile index is `%APPDATA%\EvidenceGenesis\profiles.json`; each profile autosaves to `%APPDATA%\EvidenceGenesis\profiles\<id>.json`. Settings opens the actual folder. Back up the entire EvidenceGenesis directory before changing versions or moving computers. The legacy `workshop.json` is never the autosave target for a managed profile. Save writes use a temporary file and preserve a previous backup; invalid saves are not silently overwritten. Learned lessons and documents persist. Conversation transcripts are session-only.

## Build and verification

`native/` is the Godot 4.7.2 project. Godot is used by the build machine; players receive an executable. Original art is drawn procedurally and original ambient music is synthesized. Model weights and executables are excluded from source control.

On a development machine with Python 3.12, run `python scripts/build_native.py`. The builder downloads the pinned engine, export template, CPU runtime and model, verifies the model SHA-256, runs state tests, exports Windows, includes license notices, and writes a verified ZIP with a file hash manifest. On Windows it additionally runs the exported game's panel smoke test and an actual bundled-model document test.

The `Native Windows game` workflow builds and tests the package on Windows and publishes a downloadable workflow artifact. A workflow can also be started manually.

For local source testing with Godot: import the project, run `--headless --path native --script res://tests/state_test.gd`, then run `--headless --path native -- --no-brain --smoke-test`. Use isolated user-data directories for tests. An AI integration test uses `-- --ai-smoke-test`; optionally set `GENESIS_LLAMA_PATH` and `GENESIS_MODEL_PATH` to local runtime paths.

This is a playable first release with one workshop, two companions, document creation, note review and companion chat. Mobile packaging, arbitrary computer automation, voice, multiplayer and additional worlds are not implemented.

The earlier browser prototype remains available; see [BROWSER-PROTOTYPE.md](BROWSER-PROTOTYPE.md).
