export function Crown({ size = 28, className }: { size?: number; className?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 64 64" className={className} aria-hidden="true">
      <defs>
        <linearGradient id="crown-gold" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#F6D77A" />
          <stop offset="1" stopColor="#C9922E" />
        </linearGradient>
      </defs>
      <path fill="url(#crown-gold)" d="M8 46 4 18l15 12 13-20 13 20 15-12-4 28z" />
      <rect x="8" y="49" width="48" height="7" rx="2" fill="url(#crown-gold)" />
      <circle cx="4" cy="16" r="4" fill="#F6D77A" />
      <circle cx="32" cy="8" r="4" fill="#F6D77A" />
      <circle cx="60" cy="16" r="4" fill="#F6D77A" />
    </svg>
  );
}
