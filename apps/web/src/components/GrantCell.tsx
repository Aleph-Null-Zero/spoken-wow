"use client";

import { useState } from "react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import type { GrantRow } from "@/lib/grants/store";
import { CODES, isLang, langName, type Lang } from "@/lib/lang";
import { CAPABILITIES, canGrant, capabilityLabel, type Capability, type Viewer } from "@/lib/permissions";

/**
 * One person's languages: what they hold in each, every capability removable, and a way to
 * add another.
 *
 * Offers only what `viewer` may hand out (lib/permissions.ts `canGrant`), so a language
 * admin sees edit and regenerate in their own languages and nothing else. The server
 * refuses anything else whatever this offers.
 */
export default function GrantCell({
  grants,
  viewer,
  busy,
  onGrant,
  onRevoke,
}: {
  /** This person's grants, as far as the viewer may see them. */
  grants: readonly GrantRow[];
  viewer: Viewer;
  busy: boolean;
  onGrant: (lang: Lang, capabilities: Capability[]) => Promise<boolean>;
  onRevoke: (lang: Lang, capability: Capability) => void;
}) {
  // Which popover is open: "new" for any language, or the language whose "+" was clicked.
  const [open, setOpen] = useState<"new" | Lang | null>(null);
  const byLang = new Map<Lang, Capability[]>();
  for (const grant of grants) {
    if (!isLang(grant.lang)) continue;
    const held = byLang.get(grant.lang);
    if (held) held.push(grant.capability);
    else byLang.set(grant.lang, [grant.capability]);
  }
  const offer = (lang: Lang) =>
    CAPABILITIES.filter((cap) => canGrant(viewer, cap, lang) && !byLang.get(lang)?.includes(cap));

  return (
    <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
      {[...byLang].map(([lang, capabilities]) => (
        <span key={lang} className="flex items-center gap-1">
          <span className="text-muted-foreground text-xs">{langName(lang)}</span>
          {capabilities.map((capability) => {
            const removable = canGrant(viewer, capability, lang);
            return (
              <Badge key={capability} variant="outline" className={removable ? "pr-0.5" : undefined}>
                {capabilityLabel(capability)}
                {removable ? (
                  <button
                    type="button"
                    disabled={busy}
                    aria-label={`Remove ${capabilityLabel(capability)} in ${langName(lang)}`}
                    className="text-muted-foreground hover:text-foreground rounded-full px-1 disabled:opacity-50"
                    onClick={() => onRevoke(lang, capability)}
                  >
                    ×
                  </button>
                ) : null}
              </Badge>
            );
          })}
          {offer(lang).length > 0 ? (
            <GrantPopover
              open={open === lang}
              onOpenChange={(next) => setOpen(next ? lang : null)}
              trigger={
                <Button
                  variant="ghost"
                  size="icon-xs"
                  disabled={busy}
                  aria-label={`Grant more in ${langName(lang)}`}
                >
                  +
                </Button>
              }
            >
              <GrantPicker
                offer={offer}
                lang={lang}
                busy={busy}
                onPick={(lang, capabilities) =>
                  void onGrant(lang, capabilities).then((ok) => {
                    if (ok) setOpen(null);
                  })
                }
              />
            </GrantPopover>
          ) : null}
        </span>
      ))}
      {CODES.some((lang) => offer(lang).length > 0) ? (
        <GrantPopover
          open={open === "new"}
          onOpenChange={(next) => setOpen(next ? "new" : null)}
          trigger={
            <Button variant="ghost" size="xs" disabled={busy}>
              + Grant
            </Button>
          }
        >
          <GrantPicker
            offer={offer}
            busy={busy}
            onPick={(lang, capabilities) =>
              void onGrant(lang, capabilities).then((ok) => {
                if (ok) setOpen(null);
              })
            }
          />
        </GrantPopover>
      ) : null}
    </div>
  );
}

function GrantPopover({
  open,
  onOpenChange,
  trigger,
  children,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  trigger: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <Popover open={open} onOpenChange={onOpenChange}>
      <PopoverTrigger asChild>{trigger}</PopoverTrigger>
      {/* Mounted only while open, so the choice starts fresh each time. */}
      <PopoverContent align="start" className="w-auto max-w-[min(32rem,calc(100vw-2rem))]">
        {children}
      </PopoverContent>
    </Popover>
  );
}

/**
 * A language, the capabilities to give in it, and a button: what every grant is made from.
 * Several at once, since somebody brought into a language usually needs more than one.
 *
 * `offer` says what may be granted in each language; languages it offers nothing in are
 * left out, and changing the language clears what was ticked. `lang` fixes the language and
 * hides its select, for adding to one somebody already holds.
 */
export function GrantPicker({
  offer,
  lang: fixed,
  busy,
  onPick,
  children,
}: {
  offer: (lang: Lang) => readonly Capability[];
  lang?: Lang;
  busy: boolean;
  onPick: (lang: Lang, capabilities: Capability[]) => void;
  /** Anything to put before the selects, such as an email field; the whole is one form. */
  children?: React.ReactNode;
}) {
  const langs = CODES.filter((code) => offer(code).length > 0);
  const [lang, setLang] = useState(fixed ?? langs[0]);
  const [picked, setPicked] = useState<ReadonlySet<Capability>>(new Set());
  const offered = lang ? offer(lang) : [];

  const toggle = (capability: Capability) =>
    setPicked((current) => {
      const next = new Set(current);
      if (!next.delete(capability)) next.add(capability);
      return next;
    });

  return (
    <form
      className="flex flex-wrap items-center gap-2"
      onSubmit={(event) => {
        event.preventDefault();
        // In CAPABILITIES' order, whatever order they were ticked in.
        if (lang && picked.size) onPick(lang, offered.filter((cap) => picked.has(cap)));
      }}
    >
      {children}
      {fixed ? null : (
        <Select
          value={lang}
          onValueChange={(value) => {
            setLang(value as Lang);
            setPicked(new Set());
          }}
        >
          <SelectTrigger className="w-40" aria-label="Language">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {langs.map((code) => (
              <SelectItem key={code} value={code}>
                {langName(code)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      )}
      <div role="group" aria-label="Capabilities" className="flex flex-wrap gap-1">
        {offered.map((cap) => (
          <Button
            key={cap}
            type="button"
            size="sm"
            variant={picked.has(cap) ? "default" : "outline"}
            aria-pressed={picked.has(cap)}
            onClick={() => toggle(cap)}
          >
            {capabilityLabel(cap)}
          </Button>
        ))}
      </div>
      <Button type="submit" size="sm" disabled={busy || !lang || picked.size === 0}>
        {fixed ? `Grant in ${langName(fixed)}` : "Grant"}
      </Button>
    </form>
  );
}
