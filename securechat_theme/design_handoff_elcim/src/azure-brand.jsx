// Elçim Azure — blue as accent only; neutral transparent base.
// Background uses a doodle art SVG pattern + soft tint.

const AZ = {
  // neutral dark base (midnight ink, not blue)
  night: '#0D1014',
  nightRaise: '#151A21',
  nightEdge: '#1E242D',
  // neutral light base (paper/bone)
  paper: '#F4F2EC',
  paperDim: '#EAE7DD',
  // ink
  ink: '#13161B',
  inkMute: '#5D6570',
  inkSoft: '#8A929C',
  frost: '#ECEEF2',
  frostMute: '#9BA3AE',
  frostSoft: '#6B737D',
  // PRIMARY ACCENT: blue — used only for CTAs, badges, highlights
  azure: '#3E7BFA',
  azureDeep: '#1E52D9',
  azureGlow: '#5EA3FF',
  azureSoft: '#7B9BF0',
  // minor accents
  cyan: '#22D3EE',
  // status
  warn: '#FFB800',
  danger: '#FF5E87',
  ok: '#22C55E',
};

const azTheme = (dark) => dark ? {
  bg: AZ.night,
  bgTint: 'rgba(62,123,250,0.035)', // very subtle blue wash
  raise: 'rgba(255,255,255,0.04)',
  glassBg: 'rgba(255,255,255,0.05)',
  glassBgStrong: 'rgba(255,255,255,0.08)',
  glassBorder: 'rgba(255,255,255,0.09)',
  glassBorderStrong: 'rgba(255,255,255,0.14)',
  text: AZ.frost, textMute: AZ.frostMute, textSoft: AZ.frostSoft,
  accent: AZ.azureGlow,
  // chat bubbles
  bubbleMe: 'rgba(62,123,250,0.28)',         // blue primary, transparent
  bubbleMeBorder: 'rgba(94,163,255,0.35)',
  bubbleMeText: '#FFFFFF',
  bubbleThem: 'rgba(15,20,28,0.55)',         // darker, transparent
  bubbleThemBorder: 'rgba(255,255,255,0.08)',
  bubbleThemText: AZ.frost,
  shadow: '0 4px 20px rgba(0,0,0,0.35)',
  doodleStroke: 'rgba(255,255,255,0.055)',
  doodleStrokeStrong: 'rgba(94,163,255,0.07)',
} : {
  bg: AZ.paper,
  bgTint: 'rgba(62,123,250,0.04)',
  raise: 'rgba(255,255,255,0.55)',
  glassBg: 'rgba(255,255,255,0.55)',
  glassBgStrong: 'rgba(255,255,255,0.75)',
  glassBorder: 'rgba(19,22,27,0.07)',
  glassBorderStrong: 'rgba(19,22,27,0.12)',
  text: AZ.ink, textMute: AZ.inkMute, textSoft: AZ.inkSoft,
  accent: AZ.azureDeep,
  bubbleMe: 'rgba(62,123,250,0.18)',
  bubbleMeBorder: 'rgba(62,123,250,0.35)',
  bubbleMeText: AZ.azureDeep,
  bubbleThem: 'rgba(19,22,27,0.06)',
  bubbleThemBorder: 'rgba(19,22,27,0.09)',
  bubbleThemText: AZ.ink,
  shadow: '0 4px 18px rgba(19,22,27,0.07)',
  doodleStroke: 'rgba(19,22,27,0.07)',
  doodleStrokeStrong: 'rgba(30,82,217,0.10)',
};

const SANS_AZ = '"Inter", -apple-system, BlinkMacSystemFont, system-ui, sans-serif';
const DISP_AZ = '"Space Grotesk", "Inter", system-ui, sans-serif';
const MONO_AZ = '"JetBrains Mono", ui-monospace, Menlo, monospace';

// ─── Doodle Art Background ──────────────────────────────────
// Hand-drawn glyphs: envelopes, peer nodes, waves, locks, dots, connecting lines.
// Rendered as an SVG pattern; covers full backdrop.
function AzDoodleBackdrop({ dark = false, tint = true }) {
  const t = azTheme(dark);
  const s = t.doodleStroke;
  const sStrong = t.doodleStrokeStrong;
  return (
    <div style={{ position: 'absolute', inset: 0, overflow: 'hidden', pointerEvents: 'none' }}>
      {/* base color */}
      <div style={{ position: 'absolute', inset: 0, background: t.bg }}/>
      {/* very subtle blue tint */}
      {tint && <div style={{ position: 'absolute', inset: 0, background: t.bgTint }}/>}
      {/* doodles */}
      <svg width="100%" height="100%" style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <pattern id={`az-doodles-${dark ? 'd' : 'l'}`} x="0" y="0" width="280" height="280" patternUnits="userSpaceOnUse">
            {/* envelope */}
            <g stroke={s} strokeWidth="1.4" fill="none" strokeLinecap="round" strokeLinejoin="round">
              <rect x="22" y="30" width="34" height="22" rx="2"/>
              <path d="M22 32 L39 44 L56 32"/>
            </g>
            {/* peer dots linked */}
            <g stroke={s} strokeWidth="1.4" fill="none">
              <circle cx="110" cy="36" r="3.5"/>
              <circle cx="150" cy="54" r="3.5"/>
              <circle cx="128" cy="72" r="3.5"/>
              <path d="M110 36 L150 54 M150 54 L128 72 M128 72 L110 36" strokeDasharray="2 3"/>
            </g>
            {/* wave */}
            <path d="M180 48 q 10 -10 20 0 t 20 0 t 20 0" stroke={sStrong} strokeWidth="1.6" fill="none" strokeLinecap="round"/>
            {/* lock */}
            <g stroke={s} strokeWidth="1.4" fill="none" strokeLinecap="round">
              <rect x="38" y="108" width="16" height="13" rx="2"/>
              <path d="M41 108 v-4 a5 5 0 0 1 10 0 v4"/>
            </g>
            {/* speech bubble */}
            <g stroke={sStrong} strokeWidth="1.5" fill="none" strokeLinecap="round" strokeLinejoin="round">
              <path d="M86 122 h40 a4 4 0 0 1 4 4 v14 a4 4 0 0 1 -4 4 h-28 l-10 8 v-8 h-2 a4 4 0 0 1 -4 -4 v-14 a4 4 0 0 1 4 -4 z"/>
            </g>
            {/* small x mesh */}
            <g stroke={s} strokeWidth="1.2" fill="none">
              <path d="M170 112 l10 10 M180 112 l-10 10"/>
              <circle cx="175" cy="117" r="10" strokeDasharray="2 3"/>
            </g>
            {/* @ sign */}
            <g stroke={s} strokeWidth="1.4" fill="none" strokeLinecap="round">
              <circle cx="228" cy="120" r="10"/>
              <circle cx="228" cy="120" r="4"/>
              <path d="M232 120 v3 a4 4 0 0 0 7 -2"/>
            </g>
            {/* dashed path */}
            <path d="M30 180 C 70 160, 120 200, 170 180 T 260 180" stroke={sStrong} strokeWidth="1.4" fill="none" strokeDasharray="1 4" strokeLinecap="round"/>
            {/* node with pulses */}
            <g stroke={s} strokeWidth="1.3" fill="none">
              <circle cx="60" cy="220" r="3"/>
              <circle cx="60" cy="220" r="10" strokeDasharray="2 3"/>
              <circle cx="60" cy="220" r="18" strokeDasharray="1 4"/>
            </g>
            {/* key */}
            <g stroke={s} strokeWidth="1.4" fill="none" strokeLinecap="round">
              <circle cx="130" cy="225" r="5"/>
              <path d="M135 225 h18 M148 225 v5 M153 225 v7"/>
            </g>
            {/* zigzag */}
            <path d="M180 228 l6 -6 l6 6 l6 -6 l6 6 l6 -6 l6 6" stroke={s} strokeWidth="1.4" fill="none" strokeLinecap="round" strokeLinejoin="round"/>
            {/* tiny stars */}
            <g stroke={sStrong} strokeWidth="1.2" fill="none" strokeLinecap="round">
              <path d="M254 44 v5 M251.5 46.5 h5 M252 43 l5 5 M257 43 l-5 5"/>
              <path d="M12 92 v3 M10.5 93.5 h3"/>
              <path d="M254 264 v3 M252.5 265.5 h3"/>
              <path d="M76 260 v3 M74.5 261.5 h3"/>
            </g>
            {/* signal arcs */}
            <g stroke={s} strokeWidth="1.4" fill="none" strokeLinecap="round">
              <path d="M216 222 q 8 -8 16 0"/>
              <path d="M220 226 q 4 -4 8 0"/>
              <circle cx="224" cy="229" r="1.2" fill={s}/>
            </g>
          </pattern>
        </defs>
        <rect width="100%" height="100%" fill={`url(#az-doodles-${dark ? 'd' : 'l'})`}/>
      </svg>
    </div>
  );
}

// ─── Glass surface (transparent + blur, neutral) ────────────
function Glass({ children, dark = false, radius = 18, style = {}, strong = false, noBlur = false }) {
  const t = azTheme(dark);
  return (
    <div style={{
      position: 'relative',
      background: strong ? t.glassBgStrong : t.glassBg,
      backdropFilter: noBlur ? 'none' : 'blur(18px) saturate(160%)',
      WebkitBackdropFilter: noBlur ? 'none' : 'blur(18px) saturate(160%)',
      border: `1px solid ${strong ? t.glassBorderStrong : t.glassBorder}`,
      borderRadius: radius,
      boxShadow: t.shadow,
      overflow: 'hidden',
      ...style,
    }}>
      {children}
    </div>
  );
}

// ─── Azure logo mark ────────────────────────────────────────
function AzureMark({ size = 32 }) {
  return (
    <svg width={size} height={size} viewBox="0 0 36 36" fill="none">
      <rect x="3" y="3" width="30" height="30" rx="9" stroke={AZ.azure} strokeWidth="2.2" fill="none"/>
      <path d="M10 13 L18 19 L26 13" stroke={AZ.azure} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"/>
      <path d="M10 23 L22 23" stroke={AZ.azure} strokeWidth="2.2" strokeLinecap="round"/>
      <circle cx="10" cy="13" r="1.8" fill={AZ.azure}/>
      <circle cx="26" cy="13" r="1.8" fill={AZ.azure}/>
    </svg>
  );
}

function AzureWordmark({ size = 26, dark = false }) {
  const t = azTheme(dark);
  return (
    <div style={{
      fontFamily: DISP_AZ, fontWeight: 600, fontSize: size, letterSpacing: -1,
      color: t.text, display: 'flex', alignItems: 'baseline', gap: 0,
    }}>
      elçim<span style={{ color: AZ.azure, fontWeight: 700 }}>.</span>
    </div>
  );
}

// ─── Avatar — neutral with subtle tinted grays ──────────────
const AZ_AVATAR_BG = [
  '#3E7BFA', // blue (primary)
  '#6B737D', // slate
  '#8A929C', // silver
  '#5D6570', // graphite
  '#4A535E', // charcoal
  '#9BA3AE', // mist
  '#7B8491', // pebble
  '#556070', // steel
];
function azAvatarBg(seed) {
  let h = 0;
  for (let i = 0; i < seed.length; i++) h = (h * 31 + seed.charCodeAt(i)) >>> 0;
  return AZ_AVATAR_BG[h % AZ_AVATAR_BG.length];
}

function AzAvatar({ name, size = 44, online = false, dark = false, ring = false }) {
  const bg = azAvatarBg(name || 'x');
  const initials = (name || '?').split(' ').map(s => s[0]).slice(0, 2).join('').toUpperCase();
  return (
    <div style={{
      width: size, height: size, borderRadius: size / 2,
      background: bg, color: '#fff',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontFamily: DISP_AZ, fontWeight: 600, fontSize: size * 0.36, letterSpacing: -0.3,
      position: 'relative', flexShrink: 0,
      border: ring ? `2px solid ${AZ.azure}` : 'none',
    }}>
      {initials}
      {online && (
        <span style={{
          position: 'absolute', bottom: 0, right: 0,
          width: size * 0.26, height: size * 0.26,
          background: AZ.ok, borderRadius: '50%',
          boxShadow: `0 0 0 2px ${dark ? AZ.night : AZ.paper}`,
        }}/>
      )}
    </div>
  );
}

// ─── Chip ───────────────────────────────────────────────────
function AzChip({ label, dot, icon, tone = 'neutral', dark = false, primary = false }) {
  const t = azTheme(dark);
  const dotColor = tone === 'ok' ? AZ.ok : tone === 'warn' ? AZ.warn : tone === 'bad' ? AZ.danger : AZ.azure;
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 6,
      fontFamily: SANS_AZ, fontSize: 11, fontWeight: 500, letterSpacing: 0.2,
      color: primary ? '#fff' : t.text,
      padding: '4px 10px',
      borderRadius: 100,
      background: primary ? AZ.azure : t.glassBg,
      backdropFilter: primary ? 'none' : 'blur(10px)',
      WebkitBackdropFilter: primary ? 'none' : 'blur(10px)',
      border: `1px solid ${primary ? 'transparent' : t.glassBorder}`,
    }}>
      {dot && <span style={{ width: 6, height: 6, background: dotColor, borderRadius: '50%' }}/>}
      {icon}
      {label}
    </span>
  );
}

function AzLock({ size = 11, color = '#fff' }) {
  return (
    <svg width={size} height={size * 1.15} viewBox="0 0 11 12.5" fill="none">
      <path d="M2.5 5.5V3.5a2.5 2.5 0 015 0v2" stroke={color} strokeWidth="1.3"/>
      <rect x="1.5" y="5.5" width="8" height="6" rx="1.5" fill={color}/>
    </svg>
  );
}

// Primary action button (the only place blue is fully solid)
function AzPrimary({ children, radius = 100, style = {}, full = false }) {
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
      padding: '14px 22px', borderRadius: radius,
      background: AZ.azure, color: '#fff',
      fontFamily: SANS_AZ, fontWeight: 600, fontSize: 15,
      boxShadow: `0 8px 24px rgba(62,123,250,0.35)`,
      width: full ? '100%' : undefined,
      ...style,
    }}>
      {children}
    </div>
  );
}

Object.assign(window, {
  AZ, azTheme, SANS_AZ, DISP_AZ, MONO_AZ,
  Glass, AzDoodleBackdrop, AzureMark, AzureWordmark, AzAvatar, azAvatarBg,
  AzChip, AzLock, AzPrimary,
});
