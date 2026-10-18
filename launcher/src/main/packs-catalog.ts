// Voice packs the launcher channel carries, as the catalog and the statuses see them.

/** The tag of a channel install: `channel/` and the rev of each of the product's folders, in order. */
export const CHANNEL_TAG = 'channel/'

export function channelTag(revs: string[]): string {
  return CHANNEL_TAG + revs.join('+')
}
