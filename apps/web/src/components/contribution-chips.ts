import type { ChipOption } from "@/components/FilterChip";

/** "any" is the idle state, so it is not an option. */
export const SEARCH_IN_OPTIONS: ChipOption[] = [
  { value: "npc", label: "NPC only" },
  { value: "quest", label: "Quest only" },
  { value: "text", label: "Text only" },
];
