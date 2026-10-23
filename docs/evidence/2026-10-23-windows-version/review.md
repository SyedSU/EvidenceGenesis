# Windows resource source review

Read-only independent review of scripts/windows_version.py, scripts/build_native.py, native/export_presets.cfg and tests/test_windows_version.py found no important correctness defect. Reviewed pointer-sized Win32 prototypes/callback calling convention, resource-name lifetime, preservation of unrelated resources, failure-discard handling, VS_VERSION_INFO DWORD alignment/lengths, and build placement before PCK embedding. Final EXE is read, not resource-patched. Actual Windows API and exported-game CI remained required at review time.

The Windows round-trip test now also independently queries FileVersion, ProductVersion and ProductName through version.dll to check nested resource serialization. Preservation of non-version resource bytes is reviewed at source/API-contract level, not independently enumerated by this test. No production signer or target-device acceptance was inferred.
