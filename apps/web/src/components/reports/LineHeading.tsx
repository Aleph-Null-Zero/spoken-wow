"use client";

/**
 * What a reported line is and who says it, each a way into the explorer: the quest title to
 * the quest's lines, the NPC's name to theirs. Shared by the triage table and the sort queue.
 */
import Link from "@/components/LocaleLink";
import type { LineDetail } from "@/lib/reports/detail";
import { cn } from "@/lib/utils";

export default function LineHeading({
  detail,
  className,
  asideClassName,
}: {
  detail: LineDetail;
  className?: string;
  asideClassName?: string;
}) {
  return (
    <>
      {detail.headingHref ? (
        <Link href={detail.headingHref} className={cn("font-medium underline-offset-2 hover:underline", className)}>
          {detail.heading}
        </Link>
      ) : (
        <span className={cn("font-medium", className)}>{detail.heading}</span>
      )}
      <span className={cn("text-muted-foreground text-xs", asideClassName)}>
        {detail.speaker ? (
          <>
            <Link href={detail.speaker.href} className="hover:text-foreground underline-offset-2 hover:underline">
              {detail.speaker.name}
            </Link>
            {detail.aside ? " · " : null}
          </>
        ) : null}
        {detail.aside}
      </span>
    </>
  );
}

/** The amber the explorers give a take made from text that has since changed. */
export function OutdatedNote({ className }: { className?: string }) {
  return (
    <span className={cn("text-amber-300", className)} title="Made from text that has since changed">
      audio outdated
    </span>
  );
}
