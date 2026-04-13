# iOS Wallet Repo Guidance

- Use GPT-5.4 by default for standards-sensitive and cross-repo wallet work.
- Treat `project-docs/docs/EIDAS_ARF_Implementation_Brief.md` and `project-docs/docs/AI_Working_Agreement.md` as mandatory constraints.
- This repo owns the iOS wallet implementation used as the local reference client for Apple-platform validation.
- Keep iOS changes focused on interoperability, local trust, simulator and signing enablement, or explicitly approved wallet workstreams.
- When wallet behaviour, trust material, local integration behaviour, or signing and entitlement assumptions change, update `project-docs` in the same task.

## Local Checks

- `xcodebuild -project EudiReferenceWallet.xcodeproj -scheme "EUDI Wallet Dev" -configuration "Debug Dev" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build`
- `xcodebuild -project EudiReferenceWallet.xcodeproj -scheme "EUDI Wallet Demo" -configuration "Debug Demo" -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath .build/DerivedData CODE_SIGNING_ALLOWED=NO build`
- Use `project-docs/scripts/preflight-ios-wallet.sh`, `build-ios-wallet-simulator.sh`, and `smoke-ios-wallet-simulator.sh` for the shared local path when working across repos.

## Sensitive Areas

- Do not casually modify network trust behaviour, wallet core protocol handling, deep-link behaviour, or preregistered issuer or verifier configuration.
- Treat Apple signing, keychain sharing, entitlement-gated capabilities, and the Identity Document Provider extension as sensitive runtime areas; simulator shortcuts must not silently change device assumptions.
- Keep local certificate handling aligned with the shared local runtime trust model documented in `project-docs`.