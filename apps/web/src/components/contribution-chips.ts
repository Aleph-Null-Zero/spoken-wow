import type { ChipOption } from "@/components/FilterChip";
import { CLIENT_BIN_LABELS, CLIENT_FAMILIES, CLIENT_FAMILY_LABELS } from "@/lib/contributions/client";

/** "any" is the idle state, so it is not an option. */
export const SEARCH_IN_OPTIONS: ChipOption[] = [
  { value: "npc", label: "NPC only" },
  { value: "quest", label: "Quest only" },
  { value: "text", label: "Text only" },
];

/** "all" is the reset, so it is not an option. */
export const CLIENT_CHIP_OPTIONS: ChipOption[] = [
  { value: "focus", label: CLIENT_BIN_LABELS.focus },
  { value: "low-effort", label: CLIENT_BIN_LABELS["low-effort"] },
  ...CLIENT_FAMILIES.map((option) => ({ value: option, label: CLIENT_FAMILY_LABELS[option] })),
];
