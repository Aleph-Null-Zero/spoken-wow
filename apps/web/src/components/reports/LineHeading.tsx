"use client";

/**
 * What a reported line is and who says it. The quest title opens the explorer on the quest's
 * lines; the NPC's name opens their NPC page, with a search icon beside it for the explorer on
 * their lines. Shared by the triage table and the sort queue.
 */
import { Search } from "lucide-react";

import Link from "@/components/LocaleLink";
import { useSession } from "@/lib/auth-client";
import { isAdmin } from "@/lib/permissions";
import type { LineDetail } from "@/lib/reports/detail";
import { cn } from "@/lib/utils";

const LINK = "underline-offset-2 hover:underline";

export default function LineHeading({
  detail,
  className,
  asideClassName,
}: {
  detail: LineDetail;
  className?: string;
  asideClassName?: string;
}) {
  const { speaker } = detail;

  return (
    <>
      {speaker && detail.speakerIsHeading ? (
        <Speaker speaker={speaker} className={cn("font-medium", className)} />
      ) : detail.headingHref ? (
        <Link href={detail.headingHref} className={cn("font-medium", LINK, className)}>
          {detail.heading}
        </Link>
      ) : (
        <span className={cn("font-medium", className)}>{detail.heading}</span>
      )}
      <span className={cn("text-muted-foreground text-xs", asideClassName)}>
        {speaker && !detail.speakerIsHeading ? (
          <>
            <Speaker speaker={speaker} className="hover:text-foreground" />
            {detail.aside ? " · " : null}
          </>
        ) : null}
        {detail.aside}
      </span>
    </>
  );
}

/**
 * The NPC page is the admins' alone and 404s for anybody else, so for them the name opens the
 * explorer instead and there is no icon to repeat it.
 */
function Speaker({ speaker, className }: { speaker: NonNullable<LineDetail["speaker"]>; className?: string }) {
  const { data: session } = useSession();
  const admin = isAdmin(session?.user.role);

  return (
    <span className="inline-flex items-center gap-1">
      <Link
        href={admin ? speaker.page : speaker.search}
        title={admin ? "Open this NPC on the NPCs page" : `Show ${speaker.name}'s lines`}
        className={cn(LINK, className)}
      >
        {speaker.name}
      </Link>
      {admin ? (
        <Link
          href={speaker.search}
          title={`Show ${speaker.name}'s lines`}
          aria-label={`Show ${speaker.name}'s lines`}
          className="text-muted-foreground hover:text-foreground"
        >
          <Search className="size-3.5" />
        </Link>
      ) : null}
    </span>
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
