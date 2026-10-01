type P = { size?: number; className?: string };

const base = (size = 24) => ({
  width: size,
  height: size,
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.8,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
  "aria-hidden": true,
});

export const PlaneIcon = ({ size, className }: P) => (
  <svg {...base(size)} className={className}>
    <path d="M21.5 3.5 2.8 10.6c-.7.3-.7 1.3 0 1.6l6.3 2.3 2.3 6.3c.3.7 1.3.7 1.6 0z" fill="currentColor" fillOpacity=".18" />
    <path d="m9.1 14.5 5.4-5.4" />
  </svg>
);

export const RightClickIcon = ({ size, className }: P) => (
  <svg {...base(size)} className={className}>
    <rect x="4" y="3.5" width="16" height="17" rx="3.5" />
    <path d="M7.5 8h9M7.5 12h5.5" />
    <rect x="6.5" y="14.6" width="11" height="3.4" rx="1.4" fill="currentColor" fillOpacity=".3" />
  </svg>
);

export const DragIcon = ({ size, className }: P) => (
  <svg {...base(size)} className={className}>
    <rect x="3.5" y="4" width="9" height="11" rx="2.2" />
    <path d="M14 13.5 20.5 16l-3 1.2-1.2 3z" fill="currentColor" fillOpacity=".25" />
    <path d="M16.5 4.5h3v3M8 18.5h-3v-1.5" strokeDasharray="1.5 2.5" />
  </svg>
);

export const KeyboardIcon = ({ size, className }: P) => (
  <svg {...base(size)} className={className}>
    <rect x="2.5" y="6" width="19" height="12" rx="3" />
    <path d="M6.5 10h1M10.5 10h1M14.5 10h1M17.5 10h.5M7.5 14h9" />
  </svg>
);

export const MenuBarIcon = ({ size, className }: P) => (
  <svg {...base(size)} className={className}>
    <path d="M3 5.5h18" />
    <rect x="11" y="8.5" width="9.5" height="11" rx="2.4" />
    <path d="M13.5 12h4.5M13.5 15.5h3" />
    <circle cx="17.5" cy="5.5" r="1.4" fill="currentColor" />
  </svg>
);

export const ShieldIcon = ({ size, className }: P) => (
  <svg {...base(size)} className={className}>
    <path d="M12 3 4.5 6v5.5c0 4.6 3.1 8.2 7.5 9.5 4.4-1.3 7.5-4.9 7.5-9.5V6z" fill="currentColor" fillOpacity=".12" />
    <path d="m8.8 12.2 2.2 2.2 4.4-4.6" />
  </svg>
);

export const NoAccountIcon = ({ size, className }: P) => (
  <svg {...base(size)} className={className}>
    <circle cx="12" cy="8.5" r="3.5" />
    <path d="M5 19.5c1.2-3.3 3.7-5 7-5s5.8 1.7 7 5" />
    <path d="M4 4l16 16" />
  </svg>
);

export const FolderIcon = ({ size, className }: P) => (
  <svg {...base(size)} className={className}>
    <path d="M3.5 7.5a2 2 0 0 1 2-2h4l2 2h7a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z" fill="currentColor" fillOpacity=".12" />
    <path d="m9.5 13.5 1.8 1.8 3.4-3.6" />
  </svg>
);

export const GiftIcon = ({ size, className }: P) => (
  <svg {...base(size)} className={className}>
    <rect x="4" y="9" width="16" height="11" rx="2" />
    <path d="M3.5 9h17M12 9v11M12 9c-1.5-3.5-5.5-4-5.5-1.5S10 9 12 9c1.5-3.5 5.5-4 5.5-1.5S14 9 12 9" />
  </svg>
);

export const ClockIcon = ({ size, className }: P) => (
  <svg {...base(size)} className={className}>
    <circle cx="12" cy="12" r="8.5" />
    <path d="M12 7.5V12l3 2" />
  </svg>
);

export const InfinityIcon = ({ size, className }: P) => (
  <svg {...base(size)} className={className}>
    <path d="M7 15.5c-2 0-3.5-1.6-3.5-3.5S5 8.5 7 8.5c3.5 0 6.5 7 10 7 2 0 3.5-1.6 3.5-3.5S19 8.5 17 8.5c-3.5 0-6.5 7-10 7z" />
  </svg>
);

export const CheckIcon = ({ size, className }: P) => (
  <svg {...base(size)} className={className}>
    <path d="m5 12.5 4.5 4.5L19 7.5" />
  </svg>
);

export const ArrowUpRight = ({ size, className }: P) => (
  <svg {...base(size)} className={className}>
    <path d="M7 17 17 7M9 7h8v8" />
  </svg>
);

export const SparkIcon = ({ size, className }: P) => (
  <svg {...base(size)} className={className}>
    <path d="M12 3.5c.6 4.4 2.1 5.9 6.5 6.5-4.4.6-5.9 2.1-6.5 6.5-.6-4.4-2.1-5.9-6.5-6.5 4.4-.6 5.9-2.1 6.5-6.5z" fill="currentColor" fillOpacity=".25" />
    <path d="M18.5 16.5c.3 1.6.9 2.2 2.5 2.5-1.6.3-2.2.9-2.5 2.5-.3-1.6-.9-2.2-2.5-2.5 1.6-.3 2.2-.9 2.5-2.5z" />
  </svg>
);

export const XIcon = ({ size = 18, className }: P) => (
  <svg width={size} height={size} viewBox="0 0 24 24" className={className} aria-hidden>
    <path fill="currentColor" d="M17.8 3h3.1l-6.8 7.8L22 21h-6.2l-4.9-6.4L5.3 21H2.2l7.3-8.3L1.9 3h6.4l4.4 5.8zm-1.1 16.2h1.7L7.4 4.7H5.6z" />
  </svg>
);

export const RedditIcon = ({ size = 18, className }: P) => (
  <svg width={size} height={size} viewBox="0 0 24 24" className={className} aria-hidden>
    <circle cx="12" cy="13.5" r="7.5" fill="currentColor" fillOpacity=".2" stroke="currentColor" strokeWidth="1.6" />
    <circle cx="9.2" cy="13" r="1.2" fill="currentColor" />
    <circle cx="14.8" cy="13" r="1.2" fill="currentColor" />
    <path d="M9 16.3c1.8 1.2 4.2 1.2 6 0" stroke="currentColor" strokeWidth="1.5" fill="none" strokeLinecap="round" />
    <path d="m12 6 1.2-3.2 3.3.8" stroke="currentColor" strokeWidth="1.5" fill="none" strokeLinecap="round" />
    <circle cx="17.5" cy="3.8" r="1.3" fill="currentColor" />
  </svg>
);

export const GitHubIcon = ({ size = 18, className }: P) => (
  <svg width={size} height={size} viewBox="0 0 24 24" className={className} aria-hidden>
    <path
      fill="currentColor"
      d="M12 2.5a9.5 9.5 0 0 0-3 18.5c.5.1.7-.2.7-.5v-1.7c-2.7.6-3.2-1.2-3.2-1.2-.4-1.1-1-1.4-1-1.4-.9-.6.1-.6.1-.6 1 .1 1.5 1 1.5 1 .9 1.5 2.3 1.1 2.9.8.1-.6.3-1.1.6-1.3-2.1-.2-4.3-1.1-4.3-4.7 0-1 .4-1.9 1-2.6-.1-.2-.4-1.2.1-2.6 0 0 .8-.3 2.6 1a9 9 0 0 1 4.7 0c1.8-1.3 2.6-1 2.6-1 .5 1.4.2 2.4.1 2.6.6.7 1 1.6 1 2.6 0 3.7-2.2 4.5-4.3 4.7.3.3.6.9.6 1.8v2.6c0 .3.2.6.7.5A9.5 9.5 0 0 0 12 2.5"
    />
  </svg>
);

export const PlayIcon = ({ size = 18, className }: P) => (
  <svg width={size} height={size} viewBox="0 0 24 24" className={className} aria-hidden>
    <rect x="2" y="5" width="20" height="14" rx="4" fill="currentColor" fillOpacity=".2" stroke="currentColor" strokeWidth="1.6" />
    <path d="M10 9v6l5-3z" fill="currentColor" />
  </svg>
);

export const TrophyIcon = ({ size, className }: P) => (
  <svg {...base(size)} className={className}>
    <path d="M8 4h8v5a4 4 0 0 1-8 0z" fill="currentColor" fillOpacity=".15" />
    <path d="M8 6H5a3 3 0 0 0 3 4M16 6h3a3 3 0 0 1-3 4M12 13v4M8.5 20h7M10 17h4" />
  </svg>
);
