# Every Layout — Modern CSS Skill

Source: *Every Layout* by Heydon Pickering & Andy Bell (3rd ed.)

Apply these principles to ALL layout work unless the user explicitly overrides them. This is the binding CSS paradigm for this harness.

---

## Core Philosophy

- **Suggest, don't prescribe.** Use `flex-basis`, `min-inline-size`, and `clamp()` to give the browser an ideal target. Let the browser calculate the result, not you.
- **Intrinsic web design.** Size by content, not by viewport. No `@media` breakpoints for layout reconfiguration — use flexbox/grid algorithms to produce *quantum* layouts that exist in multiple states simultaneously.
- **Logical properties always.** Never use `margin-left`, `margin-right`, `width`, `height`. Use `margin-inline`, `margin-block`, `inline-size`, `block-size`.
- **Relative units only.** `rem` for block elements, `em` for inline context, `ch` for measure/line-length. No `px` except for `1px` borders.
- **Exception-based styling.** Apply universal rules globally; use the cascade for exceptions. High reach = low specificity (ITCSS inverted triangle).

---

## Modular Scale (required in every project)

```css
:root {
  --ratio: 1.5;
  --s-2: calc(var(--s-1) / var(--ratio));
  --s-1: calc(var(--s0) / var(--ratio));
  --s0: 1rem;
  --s1: calc(var(--s0) * var(--ratio));
  --s2: calc(var(--s1) * var(--ratio));
  --s3: calc(var(--s2) * var(--ratio));
  --s4: calc(var(--s3) * var(--ratio));
  --s5: calc(var(--s4) * var(--ratio));
  --measure: 60ch;
  --border-thin: 1px;
  --gutter: var(--s1);
}
```

---

## Universal Reset (required)

```css
*, *::before, *::after {
  box-sizing: border-box;
}
```

---

## Axioms (global rules applied pervasively)

```css
/* Measure axiom: all text elements are constrained to readable line length */
* { max-inline-size: var(--measure); }
html, body, div, header, nav, main, footer, aside, section, article {
  max-inline-size: none;
}

/* Responsive images */
img { max-inline-size: 100%; }
```

---

## Layout Primitives

### The Stack

Vertical rhythm via adjacent sibling combinator. No orphan margins.

```css
.stack {
  display: flex;
  flex-direction: column;
  justify-content: flex-start;
}

.stack > * { margin-block: 0; }
.stack > * + * { margin-block-start: var(--space, var(--s1)); }
```

**Use for:** any vertical sequence of elements (editor content, file tree items, form fields).

---

### The Box

Uniform padding + border. Children inherit color. Inversion via custom properties.

```css
.box {
  padding: var(--s1);
  border: var(--border-thin) solid;
  --color-light: #fff;
  --color-dark: #000;
  color: var(--color-dark);
  background-color: var(--color-light);
}
.box * { color: inherit; }
.box.invert {
  color: var(--color-light);
  background-color: var(--color-dark);
}
```

**Use for:** cards, panels, callouts, app shell root.

---

### The Center

Horizontally centered content container with optional padding.

```css
.center {
  box-sizing: content-box;
  max-inline-size: var(--measure);
  margin-inline: auto;
  padding-inline: var(--s1);
}
```

**Use for:** prose content, dialog bodies, centered page sections.

---

### The Cluster

Horizontally grouped variable-width elements that wrap. Use `gap` not margins.

```css
.cluster {
  display: flex;
  flex-wrap: wrap;
  gap: var(--space, var(--s1));
  justify-content: flex-start;
  align-items: center;
}
```

**Use for:** toolbars, tag groups, button rows, nav links.

---

### The Sidebar

Two-element layout: one fixed-width sidebar, one fluid content area. Wraps intrinsically when content is squeezed below 50% of container — no `@media` query needed.

```css
.with-sidebar {
  display: flex;
  flex-wrap: wrap;
  gap: var(--gutter, var(--s1));
}

/* Sidebar side (left by default) */
.with-sidebar > :first-child {
  flex-basis: 20rem;   /* ideal sidebar width */
  flex-grow: 1;
}

/* Content side */
.with-sidebar > :last-child {
  flex-basis: 0;
  flex-grow: 999;
  min-inline-size: 50%;  /* triggers wrap when content < 50% container */
}
```

**Key insight:** `.not-sidebar` has `flex-grow: 999` so it takes all available space. The sidebar's `flex-basis` is subtracted from the total. When the container is too narrow, both elements fill 100%.

For intrinsic sidebar width (sidebar sized by its content, not a fixed rem value), omit `flex-basis` on the sidebar child entirely.

**Use for:** app shell (file tree + editor), media objects, form input + button combos.

---

### The Switcher

Switches a Flexbox context between horizontal and vertical at a *container-based* threshold (not viewport). Uses the "Holy Albatross" `calc()` trick.

```css
.switcher {
  display: flex;
  flex-wrap: wrap;
  gap: var(--gutter, var(--s1));
  --threshold: 30rem;
}

.switcher > * {
  flex-grow: 1;
  flex-basis: calc((var(--threshold) - 100%) * 999);
}

/* Limit: force vertical when there are 5+ children */
.switcher > :nth-last-child(n+5),
.switcher > :nth-last-child(n+5) ~ * {
  flex-basis: 100%;
}
```

**How it works:** When container < `--threshold`, `flex-basis` becomes a large positive number, each element takes a full row (vertical). When container > `--threshold`, `flex-basis` is negative (invalid, dropped), elements share space equally (horizontal).

**Use for:** navigation that flips from horizontal to vertical, step indicators, equal-width panels.

---

## Rules Checklist (apply on every PR)

- [ ] No `@media` used for layout reconfiguration (only for fine-tuning like font sizes)
- [ ] No `px` values except `1px` borders
- [ ] No physical properties (`margin-left`, `width`, etc.) — use logical equivalents
- [ ] Modular scale tokens used for all spacing and sizing
- [ ] Measure axiom in place for text containers
- [ ] `gap` used for gutters, not margins on children
- [ ] Flexbox `flex-basis` + `flex-grow` used to suggest widths, not prescribe them
- [ ] No hardcoded breakpoints based on device widths (720px, 1024px)
