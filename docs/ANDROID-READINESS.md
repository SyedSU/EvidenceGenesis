# Android native readiness — 2026-10-23

Android remains unreleased. The approved roadmap requires local AI on Windows and Android before a product launches on either platform. This first milestone cross-compiles the mandatory save adapter, not an accepted APK or an inference demonstration.

## Reproducible native save build

Use Android NDK r28c (`Pkg.Revision = 28.2.13676358`) on a Linux/Windows x64 build machine. The source script rejects another NDK revision. Run `python scripts/build_save_adapter.py --project /isolated/native --android-ndk /path/to/android-ndk-r28c`. It compiles the same first-party durability and transaction C implementation against the pinned Godot4.7.2 C ABI for arm64-v8a/API26. The output is `genesis_save.android.arm64.so`; the GDExtension has a matching Android arm64 selector. SDKs/compilers are build tools only.

`GENESIS_ANDROID_NDK=/path/to/android-ndk-r28c python -m unittest tests.test_android_adapter -v` verifies ELF64 little-endian AArch64 output and persistence/transaction entrypoints, and rejects mismatched NDKs. Missing NDK skips this cross-compile test explicitly. Device execution, app-private filesystem behavior, lifecycle recovery, model bridge/inference, touch controls, signing and final APK alignment/inspection remain blocked; a successful compiler invocation proves none of those.

The local reviewed NDK archive was downloaded from Google's repository, checked against repository metadata SHA1 a7b54a5de87fecd125a17d54f73c446199e72a64, and independently inventoried with SHA256 dfb20d396df28ca02a8c708314b814a4d961dc9074f9a161932746f815aa552f. Apache/LLVM notices and source.properties were read. This is scoped build-tool use, not permission to redistribute the NDK. Save adapter libraries remain outside Git.

## CPU inference runtime cross-build

`build_android_runtime.py` builds the existing reviewed llama.cpp b11429 commit d81235049384534c167caea52b85a694f6103d14 from an explicit clean local Git checkout. No source or dependency download occurs inside the builder. It pins NDK28.2.13676358, CMake3.31.6 and the Ninja1.11.1.git.kitware.jobserver-1 binary supplied by the hash-verified ninja1.11.1.4 build-tool wheel. It uses CPU-only armv8-a/API26, shared libc++, disabled network/server/examples/tests/GPU/fetched backends, and flexible16KiB-page support. These flags are recorded in runtime-build.json with exact output byte hashes and actual source commit.

The successful local cross-build emits libllama/libggml/libggml-base/libggml-cpu plus NDK libc++_shared, with source/runtime notices. The builder requires a fresh empty output directory, so an existing CMake cache cannot retain unreviewed flags. Bundle validation checks all five exact library names, ELF64/AArch64 shared-object structure, bounded dynamic tables, SONAMEs, dependency closure, minimum16KiB load alignment, executable-stack/write-execute restrictions, and required notices. RPATH/RUNPATH and text relocations are rejected. The bundle test also checks output hashes and rejects missing libraries/notices or an undeclared dependency. Build outputs are outside Git. The report explicitly records deviceAcceptance:unrun, localInferenceVerified:false and publicationAuthorized:false. The Godot model bridge, actual GGUF generation on a phone, APK packaging/signing/alignment and lifecycle/thermal tests are not implemented or passed by this compile-only result.

Example: `python scripts/build_android_runtime.py --source /clean/reviewed/llama.cpp --ndk /android-ndk-r28c --cmake /cmake3.31.6/bin/cmake --ninja /reviewed/ninja --output /outside/source/android-runtime`. Run `GENESIS_ANDROID_RUNTIME_OUTPUT=/outside/source/android-runtime python -m unittest tests.test_android_runtime -v` for source-cleanliness/architecture/bundle checks. Never substitute host binaries or call a cross-build proof Android AI acceptance.

Local verification: the fresh hardened build and 40-case Python suite completed on Linux (39 passed, one Windows-only skip), including actual NDK save compilation and actual runtime bundle validation/mutation checks. Six browser-core tests and JavaScript syntax checks also passed. This does not establish Android device execution.
