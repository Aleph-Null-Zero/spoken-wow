// Where the launcher channel lives, and the key its index and manifests are signed with
// (scripts/launcher/keygen.mjs in the repo). A new key needs a new launcher build.
export const PACKS_BASE_URL = 'https://spoken-packs.rusty.one/'
/** Base64 SPKI DER of the channel's ed25519 public key. */
// Placeholder: a key whose private half was discarded, so nothing verifies until the real key from scripts/launcher/keygen.mjs replaces it.
export const PACKS_PUBLIC_KEY = 'MCowBQYDK2VwAyEAlwwfgTG1BeQY7/TTaNXV7FYFDKjBBi2g7k6Cka7zyOg='
