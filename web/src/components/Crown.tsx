/** The Monarchy crown, drawn in the current text colour. */
export function Crown({ size = 28, className }: { size?: number; className?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 64 64" className={className} aria-hidden="true" fill="currentColor">
      <path d="M8 46 4 18l15 12 13-20 13 20 15-12-4 28z" />
      <rect x="8" y="49" width="48" height="7" />
      <rect x="1" y="13" width="6" height="6" transform="rotate(45 4 16)" />
      <rect x="29" y="5" width="6" height="6" transform="rotate(45 32 8)" />
      <rect x="57" y="13" width="6" height="6" transform="rotate(45 60 16)" />
    </svg>
  );
}
