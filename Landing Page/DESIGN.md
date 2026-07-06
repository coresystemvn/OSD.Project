---
name: CoreSystem Visual Language
colors:
  surface: '#0e141a'
  surface-dim: '#0e141a'
  surface-bright: '#343a41'
  surface-container-lowest: '#090f15'
  surface-container-low: '#161c22'
  surface-container: '#1a2027'
  surface-container-high: '#252b31'
  surface-container-highest: '#2f353c'
  on-surface: '#dde3ec'
  on-surface-variant: '#c0c7d4'
  inverse-surface: '#dde3ec'
  inverse-on-surface: '#2b3138'
  outline: '#8a919e'
  outline-variant: '#404752'
  surface-tint: '#a3c9ff'
  primary: '#a3c9ff'
  on-primary: '#00315c'
  primary-container: '#0078d4'
  on-primary-container: '#ffffff'
  inverse-primary: '#0060ab'
  secondary: '#ffb77d'
  on-secondary: '#4d2600'
  secondary-container: '#fd8b00'
  on-secondary-container: '#603100'
  tertiary: '#79dd68'
  on-tertiary: '#003a01'
  tertiary-container: '#22881d'
  on-tertiary-container: '#ffffff'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#d3e3ff'
  primary-fixed-dim: '#a3c9ff'
  on-primary-fixed: '#001c39'
  on-primary-fixed-variant: '#004883'
  secondary-fixed: '#ffdcc3'
  secondary-fixed-dim: '#ffb77d'
  on-secondary-fixed: '#2f1500'
  on-secondary-fixed-variant: '#6e3900'
  tertiary-fixed: '#94fa81'
  tertiary-fixed-dim: '#79dd68'
  on-tertiary-fixed: '#002200'
  on-tertiary-fixed-variant: '#005303'
  background: '#0e141a'
  on-background: '#dde3ec'
  surface-variant: '#2f353c'
typography:
  display-lg:
    fontFamily: Inter
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.02em
  headline-md:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '600'
    lineHeight: 40px
    letterSpacing: -0.01em
  headline-sm:
    fontFamily: Inter
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
  body-lg:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 28px
  body-md:
    fontFamily: Inter
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  mono-label:
    fontFamily: JetBrains Mono
    fontSize: 14px
    fontWeight: '500'
    lineHeight: 20px
    letterSpacing: 0.05em
  mobile-h1:
    fontFamily: Inter
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  unit: 4px
  container-max: 1280px
  gutter: 24px
  margin-mobile: 16px
  stack-sm: 8px
  stack-md: 16px
  stack-lg: 32px
---

## Brand & Style

The design system is engineered to evoke the precision and reliability of an enterprise-grade deployment environment. It targets IT professionals, system administrators, and power users who require a tool that feels as robust as the hardware they manage. 

The aesthetic sits at the intersection of **Corporate Modern** and **Glassmorphism**. It utilizes a "Deep-Space" dark mode foundation inspired by terminal environments but elevates it with high-fidelity translucent layers and vibrant, functional accents. The mood is clinical, efficient, and forward-leaning, ensuring that complex technical data is presented with absolute clarity while maintaining a premium, high-tech finish.

## Colors

The palette is anchored by a deep navy neutral (`#0B1117`) to provide a low-strain environment for technical work. Brand identity is established through a vibrant "Electric Blue" primary, used for core system actions and progress indicators. 

Functional signaling is handled by high-contrast accents: 
- **Secondary (Orange):** Priority tweaks and configuration states.
- **Tertiary (Green):** Deployment success and "Ready" system statuses.
- **Accent Pink:** Critical rescue tools and destructive actions (e.g., Reboot, Format).

All interactive elements must maintain a high contrast ratio against the dark background to ensure visibility in varied lighting conditions typical of server rooms and deployment bays.

## Typography

This design system utilizes **Inter** for all UI and marketing copy due to its exceptional legibility and neutral, professional character. For technical readouts, system paths, and hardware specs, **JetBrains Mono** is employed to provide a clear distinction between "content" and "data."

Headlines should be set with tight letter-spacing to create a "locked-in," engineering-led feel. Body text maintains generous line height to ensure documentation and logs are easy to parse during long deployment sessions.

## Layout & Spacing

The layout follows a **fluid grid** model for the landing page, transitioning to a highly structured **dashboard grid** for the application interface. A strict 4px base unit governs all dimensions, ensuring mathematical harmony across the system.

- **Desktop:** 12-column grid with 24px gutters. Content is often organized into "System Cards" that occupy 4 or 6 column spans.
- **Mobile:** Single column with 16px side margins. Technical tables should reflow into list-based cards.
- **Information Density:** High. The system favors compact vertical spacing (`stack-sm`) for data points and generous padding for high-level call-to-action sections.

## Elevation & Depth

Visual hierarchy is established through **Glassmorphism** and tonal layering rather than traditional shadows. 

1.  **Base Layer:** Solid `#0B1117` background.
2.  **Surface Layer:** Semi-transparent cards with a `backdrop-filter: blur(12px)` and a subtle 1px border of `rgba(255, 255, 255, 0.1)`.
3.  **Interactive Layer:** Primary actions use a slight outer glow (diffused bloom) of their own color to suggest "active" energy.

Avoid heavy black shadows; instead, use "inner glows" on buttons to simulate a physical, backlit hardware interface.

## Shapes

The design system utilizes **Soft** roundedness (`0.25rem` base). This preserves the professional, industrial feel of a technical tool while avoiding the aggressive sharpness of legacy software. 

- **Buttons & Inputs:** 4px radius.
- **Feature Cards:** 8px (`rounded-lg`) to differentiate them from smaller UI components.
- **Visual Accents:** Square edges are permitted for purely decorative terminal-style borders or status tags to reinforce the "system tool" aesthetic.

## Components

### Buttons
- **Primary:** Solid Electric Blue with white text. High-contrast, 4px radius.
- **System Action:** Utilizes the specific functional colors (Green for Go, Pink for Rescue). These include a small mono-spaced "HotKey" indicator (e.g., [F12]) in the corner.
- **Ghost:** Transparent background with a 1px border.

### Cards
- **Technical Card:** Semi-transparent navy with a subtle top-border highlight. Content is divided by 1px dimmed dividers.
- **Feature Card:** Includes a large numeric or icon indicator on the left side, set in a solid block of the accent color.

### Input Fields
- Dark-filled backgrounds (`#161B22`) with an Electric Blue bottom-border on focus. Placeholder text should be mono-spaced to mimic command-line prompts.

### Chips & Badges
- Used for hardware status (e.g., "[LAN CONNECTED]"). These are strictly rectangular or minimally rounded, using a semi-transparent version of the status color with a solid text label.

### Data Lists
- Alternating row highlights (zebra striping) using subtle opacity changes rather than different colors. Labels are always `mono-label` style for alignment.