# Notarization: what it takes, and what players would notice

Written at Mohamed's request, to be decided later. This is a decision document, not a plan of
work that has been started.

## The problem it solves

A freshly downloaded build is refused on first launch. macOS sees an app it cannot vouch for and
shows *"Apple could not verify SteamMMO is free of malware"*, with only **Move to Trash** and
**Done** on it. On current macOS, right-click -> **Open** does NOT clear that dialog, which is why
`ITCH_PAGE.md` and `ITCH.md` were corrected to say what actually works: drag the app out of
Downloads into Applications first, click Done, then **System Settings -> Privacy & Security ->
Open Anyway** (or `xattr -dr com.apple.quarantine`).

That is one manual step, once, per player, and it is where a download most often gets reported as
broken even though the build is fine. Measured on the SERVED 0.0015 zip fetched back from itch: the
signature verifies, the bytes match the release ledger, and the app boots - the block is purely
"macOS does not know the author", not a defect.

## What notarization is

You sign the app with an Apple-issued **Developer ID Application** certificate, upload it to
Apple's notary service, Apple scans it and issues a ticket, and you **staple** that ticket to the
bundle. macOS then trusts the app on first launch, offline, with no dialog at all.

## What it requires

1. An **Apple Developer Program membership** - an Apple account matter, and the human's decision.
   Nothing below can be done from this machine without it, and it cannot be shared as a secret
   file: the credentials belong on the machine that cuts releases.
2. A **Developer ID Application certificate** in the login keychain.
3. `codesign` with the hardened runtime and a **secure timestamp** (currently the release runs an
   ad-hoc `--sign -` signature, which is what makes the bundle valid-but-untrusted).
4. `xcrun notarytool submit --wait` with credentials - an **app-specific password** or an App Store
   Connect **API key** (key id + issuer id + .p8 file).
5. `xcrun stapler staple` on the bundle, so the ticket travels with the download and works offline.

## What changes for players

* No dialog at all on first launch: unzip, drag to Applications, double-click, playing.
* The "damaged"/"could not verify" family of reports disappears for good.
* Nothing else changes: it is still not an App Store app, and no sandbox rules change.

## What changes in the release process

`tools/release.sh` already re-signs the macOS bundle and refuses to ship unless
`codesign --verify --deep --strict` passes. Notarization adds three steps in the same place:
sign with the Developer ID identity instead of ad-hoc, submit and wait, staple, then **fail the
release unless `xcrun stapler validate` and `spctl -a -vvv -t install` both pass**. That keeps the
existing rule - an unverifiable bundle is never published - and extends it to trust rather than
just integrity.

## What I can and cannot do

* **Can**: write and test the release-script changes, run them on this machine, and verify the
  result on the SERVED artifact rather than on what was uploaded.
* **Cannot**: create an Apple account, accept Apple's agreements, or hold credentials. Those stay
  with Mohamed, entered on the release machine, never in a file that gets committed.

## If not now

Zero code needed: the page already explains the one-time step accurately, so downloads work today.
The honest cost of waiting is the trust story and the support noise, not a broken build.
