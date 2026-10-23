---
name: every-layout
description: Every Layout CSS primitives (Stack, Cluster, Sidebar, Switcher, Cover, Grid, Center, Box) and the composition-over-per-element-styling rule. Use when building or reviewing page layout, section structure, spacing or alignment in a project on the every-layout substrate.
---

# Every Layout, Modern CSS Skill

Source: *Every Layout* by Heydon Pickering & Andy Bell (3rd ed.)

Apply these principles to ALL layout work unless the user explicitly overrides them. This is the binding CSS paradigm for this harness.

---

## Core Philosophy

- **Suggest, don't prescribe.** Use `flex-basis`, `min-inline-size`, and `clamp()` to give the browser an ideal target. Let the browser calculate the result, not you.
- **Intrinsic web design.** Size by content, not by viewport. No `@media` breakpoints for layout reconfiguration, use flexbox/grid algorithms to produce *quantum* layouts that exist in multiple states simultaneously.
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

Two-element layout: one fixed-width sidebar, one fluid content area. Wraps intrinsically when content is squeezed below 50% of container, no `@media` query needed.

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

## Composition over per-element styling (BINDING)

Layout, alignment, rhythm, and breathing room are CONTAINER concerns. They
live on the wrapper, not on each child. The moment you find yourself adding
`text-center` (or `items-center`, or `gap-…`, or `padding-…`) to multiple
sibling elements that share a parent, you have written the same intent at
the wrong scope, refactor it onto the parent.

The pattern this skill enforces:

```
<Section> = breathing room (via base section { padding-block: --section-gap })
  <Center> = column width
    <Box align="center" padding="0"> = content alignment
      <h2>...</h2>           ← carries typography only
      <p>...</p>             ← carries typography only
      <a class="button">...  ← carries appearance only
```

Each layer owns one concern. None of the children carry alignment classes;
they inherit from the Box. Switching alignment is a one-prop change on the
Box, every descendant follows. Children stay portable.

### Concrete rules

1. **No `text-center` / `text-start` / `text-end` on individual text
   elements** unless the surrounding container has a deliberately mixed
   alignment policy (rare). If three siblings need the same alignment, the
   parent gets it instead.
2. **No `items-center` / `items-start` on individual flex items.** If
   children share an alignment intent, the flex parent gets it.
3. **No ad-hoc `gap-…` between siblings of a parent.** Use a primitive that
   names the rhythm (Stack, Cluster, Switcher) and let it set the gap once.
4. **No ad-hoc `padding-block:…` on `<section>` elements.** One
   `--section-gap` token + a base `section { padding-block: var(--section-gap) }`
   rule controls the whole site. Per-section overrides are an explicit
   deviation, not a default.
5. **No layout in shared primitives.** A `<Stack>` is alignment-free by
   default, it does rhythm only. Alignment lives on the Box or Center that
   wraps it, not inside Stack itself.

### Why it works

- **Less repetition.** Three centred children become one `align="center"` on
  the parent. Adding a fourth sibling carries no new alignment work.
- **Proper separation of concerns.** A `<h2>` knows its typography. It does
  not know whether its surrounding section is centred or left-aligned. That
  is the container's concern.
- **Cheap re-layout.** Switching a section from centred to left-aligned is
  a single prop change. No file-wide sweep, no risk of one child being
  missed.
- **Flow over wallpaper.** Sections flow correctly because the cascade
  carries intent, not because we have re-stated it everywhere.

### Self-test before claiming a layout task done

For every child element you touched: would removing all alignment /
rhythm / breathing-room classes from it leave it correctly laid out (given
the right parent)? If yes, your composition is right. If no, the intent
escaped to the wrong scope, push it up.

---

## Rules Checklist (apply on every PR)

- [ ] No `@media` used for layout reconfiguration (only for fine-tuning like font sizes)
- [ ] No `px` values except `1px` borders
- [ ] No physical properties (`margin-left`, `width`, etc.), use logical equivalents
- [ ] Modular scale tokens used for all spacing and sizing
- [ ] Measure axiom in place for text containers
- [ ] `gap` used for gutters, not margins on children
- [ ] Flexbox `flex-basis` + `flex-grow` used to suggest widths, not prescribe them
- [ ] No hardcoded breakpoints based on device widths (720px, 1024px)
