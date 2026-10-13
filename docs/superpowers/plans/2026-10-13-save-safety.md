# Genesis P0 Save Safety Implementation Plan

> Use superpowers:executing-plans inline; owner authorizes this one C workstream and direct main execution. No additional design approval is needed.

**Goal:** Failed workshop/profile saves report failure and preserve recoverable original data; failed care/profile operations do not claim persisted progress.
**Architecture:** One checked JSON persistence helper stages and verifies bytes, backs up validated originals, checks every filesystem result, restores missing originals after failed replacement and reads valid backup only when the primary is missing. Existing v4 formats/epoch4 remain unchanged. Corrupt primary data stays in place, disables writes and is copied to a uniquely identified quarantine file when possible.
**Tech Stack:** Existing Godot4.7.2/GDScript/FileAccess/DirAccess, Python standard-library isolated fault harness; no new runtime dependency.
**Spec:** canonical RELEASE-BRIEF.md §7.3C; RELEASE-STATE.md S24/S19/K01.

## Constraints and review focus

- Real isolated filesystem failures and RED→GREEN tests before implementation; retain existing state/startup/panel checks.
- Check serialization validation, size/write/flush/readback/copy/rename outcomes and propagate actionable errors.
- Preserve corrupt originals/legacy imports and selected profile state; no automatic reward/retry or save-schema change.
- No AI/packaging/model change or public gate/source-lock promotion.
- Godot4.7.2 Unix flush is fflush, not fsync; Windows rename deletes destination before move. Process-crash recovery is testable; power-loss/native fsync/atomic Windows acceptance remains explicitly blocked rather than claimed.
- Keep test-only fault/kill/mutation code under native/tests or tests; storage adapter primitives provide platform abstraction, not production test flags.

## Task1: Checked save persistence and regressions

Files: native/scripts/save_files.gd; native/scripts/state.gd; native/scripts/profiles.gd; native/tests/save_safety_test.gd; native/tests/state_test.gd.
Interface: GenesisSaveFiles.write_json(path,text,validator,limit) returns error String (empty on success); read_json returns checked data/error/source; state/profile errors remain existing public fields.

- [x] Write failing real backup-directory, blocked temp/write, invalid candidate and profile-selection/care rollback regressions; run them with pinned4.7.2 and capture RED.
- [x] Implement checked stages/backups/replacement, invalid-file quarantine and missing-primary backup recovery; preserve compatibility.
- [x] Route profile/care state through checked commit and report errors; run GREEN state/startup/panel tests.

## Task2: Crash/negative proof, review and release-state handoff

Files: native/tests/save_crash_fixture.gd; tests/test_native_save_safety.py; docs/SAVE-SAFETY.md; canonical state/evidence/dependency ledger updates.

- [x] Kill isolated child processes at real staging/backup/replacement boundaries; assert old/new validated save or recoverable backup, original corrupt bytes retained, no duplicated credit/reward.
- [x] Run meaningful targeted mutants against backup/write/validation/reward paths without installing unvetted mutation libraries; capture killed/surviving results honestly. Formal GUT/GdUnit4/gdmutant adoption stays blocked until vetted.
- [x] Run existing native state/startup/panel and npm/Python suites; independently review source/test changes and fix material findings.
- [x] Commit verified Genesis source and save-safety documentation; canonical evidence/state and main push outcomes complete this handoff in the release ledger.

Pinned engine temporary verification tool: official Godot4.7.2 source ed1daf0bf001b61586d9930840f2f1394092c079, MIT LICENSE read, release2026-08-18, Linux archiveSHA256cadd3204e728a35d3f13adb7fd0d7902636b79f6b95c40c265eb73b6c35329e4 verified. Stored under work/, not global setup or a shipped player dependency.

Evidence before commit: original13 failures reproduced on4.7.2; settings/encoding and review recovery regressions RED→GREEN; final67 save assertions,8 process-kill cases,14 Python tests and6 JavaScript tests/syntax passed. Final-source five mutants killed; initial survivor retained and first-save test gap corrected. Independent static review recovery finding fixed; no follow-up acceptance or fsync/nativeWindows claim.
