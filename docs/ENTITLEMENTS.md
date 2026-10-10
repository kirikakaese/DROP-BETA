# Entitlements

DROP currently uses **no entitlements** (`App/DROP.entitlements` is empty).

It is not sandboxed: it talks to GitHub and package registries over HTTPS and keeps its data in
`~/Library/Application Support/DROP` and the Keychain, none of which needs an entitlement
outside the sandbox. Team-signed builds use the Hardened Runtime without exceptions. Releases are
ad-hoc signed without the Hardened Runtime (`scripts/adhoc_sign.sh` explains why), so the embedded
Sparkle framework, its XPC services and its `Autoupdate` helper load without entitlements either.

Any entitlement added later is listed here with the reason it is needed.
