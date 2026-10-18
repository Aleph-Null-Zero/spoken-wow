// Where the launcher channel lives, and the key its index and manifests are signed with
// (scripts/launcher/keygen.mjs in the repo). A new key needs a new launcher build.
export const PACKS_BASE_URL = 'https://spoken-packs.rusty.one/'
/** Base64 SPKI DER of the channel's ed25519 public key. */
export const PACKS_PUBLIC_KEY = 'MCowBQYDK2VwAyEAtiV14d1ANsreuZtPlaGdosc1ZUyk9QlC7I4KpXjNrA4='
