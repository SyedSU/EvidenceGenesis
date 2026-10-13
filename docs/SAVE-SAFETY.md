# Native save safety — 2026-10-13

Genesis0.5.0 remains a development candidate; save format/compatibility epoch4 is unchanged. This source fixes failed-save handling and recovery. It does not approve public distribution or reuse of older built artifacts. Actual source/validation evidence is recorded in canonical RELEASE-STATE.md.

Workshop saves and the profile index share GenesisSaveFiles. The writer validates bounded JSON and existing originals/backups, writes unique same-directory stages, flushes/checks write status, closes and verifies exact bytes. It stages the previous backup before replacing it, checks replacement/recovery outcomes, and retains verified recovery stages when rollback fails. Failed first writes cannot activate a partial stage. Invalid or oversized data cannot replace previous files.

Care/task/profile/settings changes roll back on failure. Feed/harvest/rest cannot grant persisted progress; a full task queue restores evicted history. Failed profile creation leaves the previous index/selection intact and retains any unindexed new profile rather than deleting it. Settings and autosave report errors; ordinary Exit refuses a failed active save so the user can correct it and retry. Menu startup without a writable profile can still Exit.

Missing primary: read only a validated `.backup`, with a recovery message. Present corrupt primary: preserve original bytes, disable writes, and copy readable bounded bytes to `.corrupt-<SHA256>` when possible. Never silently replace corrupt primary data. Unreadable/oversized originals remain preserved even when quarantine is unavailable; invalid existing backups block replacement.

Recovery: stop gameplay writes and copy the whole EvidenceGenesis directory, normally `%APPDATA%/EvidenceGenesis`, before repair. Preserve primary, `.backup`, `.corrupt-*` and any recovery stage named by the error. Fix free-space/permissions/incorrect-directory problems and retry. If recovery itself fails, use the verified backup/stage identified by the error. Restart to the main menu and use Restore backup to create a separate restored workshop when no healthy current profile opens; retain the corrupt original. Corrupt index files are preserved for manual backup/support recovery, not automatically rewritten. Never remove legacy originals or blindly restore a different save epoch.

## Verification

Pinned official Godot4.7.2 source ed1daf0bf was used, with verified Linux archiveSHA256cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4, reviewed MIT license and2026-08-18 release metadata. The temporary tool is outside source; no new player runtime dependency is added.

Original13 failing checks went GREEN. Review exposed another rollback-loss path: five new failing checks went GREEN after recovery-stage preservation. Final67 save assertions cover blocked backup directories, invalid candidates, injected partial writes, delete-before-failed-move, rollback/recovery failure, quarantine, strict UTF8/Unicode round trips, sole-backup preservation and care/queue/profile rollback. Eight actual process kills cover workshop/index staging, backup rotation, simulated Windows pre-move deletion and committed replacement; fresh processes recover old/new valid generations without repeated approval credit.

Five targeted source mutants were killed. The initial partial-write mutant survived; adding the missing first-save case killed it. This is explicit mutation proof, not GUT/GdUnit4/gdmutant adoption. Existing state/startup/panel tests, failed-companion-settings UI regression,14 Python tests and6 JavaScript tests/syntax passed locally with isolated saves. No screenshots or target-performance claims are derived from these headless runs.

## Remaining durability limits

Godot's pinned Unix FileAccess.flush uses `fflush`, not disk `fsync`. Pinned Windows DirAccess.rename removes an existing destination before MoveFileW. Process-interruption recovery does not establish physical power-loss durability or atomic Windows overwrite. Native file/directory synchronization strategy, hardware/filesystem fault testing, genuine Windows kill/recovery and concurrent writers remain unverified. A reviewed native durability strategy and target evidence are required before canonical S24/K01 can close. No player Python/PowerShell/SDK or arbitrary command bridge is introduced to claim those guarantees.

AI code/package layout is unchanged. No new bundled-model run occurred locally; existing main CI attempts Windows/model build, whose actual steps/artifacts must be reported separately. Old source locks/artifacts are never relabeled.

## Repeat checks

Import native with the verified4.7.2 engine and isolated user-data, then run `res://tests/state_test.gd`, `res://tests/startup_test.gd -- --no-brain`, and `-- --no-brain --smoke-test`. Save assertions run inside the existing state test/Windows builder. `GENESIS_TEST_GODOT=/absolute/path/to/verified4.7.2 python -m unittest discover -s tests -p test_native_save_safety.py -v` copies native to a temporary project and isolates all crash saves; optional `GENESIS_SAVE_EVIDENCE_DIR` retains logs outside source. Missing/wrong engine explicitly skips native proof. Players need no editor/compiler/Python/Node.
