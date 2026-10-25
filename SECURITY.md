# Security Policy

## Supported versions

The latest release is the supported one. The app updates itself through Sparkle,
so fixes ship in the next release rather than as patches to older builds. Please
reproduce on the current version before reporting.

## Reporting a vulnerability

**Do not open a public GitHub issue for a security vulnerability.**

Email **security@arcbox.dev** with:

- A description of the vulnerability
- Steps to reproduce
- Affected versions
- Any mitigations you have identified

We acknowledge within **48 hours** and aim to have a fix or mitigation plan within
**7 days**.

## Scope

This repo is the macOS app. The surfaces we care most about here:

- **Deep links** — the app registers `arcbox://` for deep links and
  `com.arcboxlabs.desktop://` for the OAuth redirect. Anything that lets a crafted
  URL drive an action the user did not ask for, or intercept an authorization code.
- **Sign-in and tokens** — the OIDC/PKCE flow in `Packages/ArcBoxAuth` and the
  tokens it keeps in the keychain.
- **The update channel** — appcast fetching and Sparkle's EdDSA signature check.
  Anything that could get unsigned or downgraded code installed.
- **Bundle integrity** — code signing, notarization, and the identifiers on the
  binaries embedded in the app (`abctl`, `arcbox-helper`, `arcbox-daemon`), which
  peer authentication depends on.
- **Telemetry leakage** — Sentry and PostHog payloads are meant to be scrubbed of
  paths and other PII. Report anything that escapes.

**Out of scope here — report against the runtime instead:** VM escape or
guest-to-host breakout, container isolation bypass, privilege escalation through
`arcbox-helper`'s root mutations, and denial of service against the daemon. Those
live in [arcboxlabs/arcbox](https://github.com/arcboxlabs/arcbox/blob/master/SECURITY.md),
under the same email and the same timelines.
