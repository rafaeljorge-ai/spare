# Spare: visual system

Approved by the owner on 2026-10-22 from the prototype in `Prototype/` (run `Prototype/run.sh`).
Inspired by the feel of CleanMyMac, never its logo, icons, names or illustrations.

## Direction
Night sky over a calm sea. Dark gradient backdrop, one focal element per screen, mint means "space coming back to you".

## Tokens (`Prototype/Sources/SpareProto/Theme.swift`, enum `Ink`)
- Backdrop: linear `night` (0.09, 0.08, 0.22) to `tide` (0.04, 0.17, 0.23), top leading to bottom trailing, plus radial `glow` (0.16, 0.72, 0.78) at 22% from the top.
- Meaning colors: `spare` mint (0.37, 0.95, 0.75) safe; `review` amber (1.0, 0.78, 0.42); `busy` coral (1.0, 0.50, 0.50) in use or destructive.
- Text: white at 100 / 72 / 50 / 32%.
- Surfaces: white at 6% (cards) and 10% (controls, active row). Lines white 8%. Ring track 7%, used 22%.
- Depth: surface tints plus hairline borders. No drop shadows except the mint glow on the ring and the scan button.

## Type (enum `Txt`)
SF Pro for text, SF Pro Rounded for figures. display 44 semibold rounded · h1 26 semibold (tracking -0.3) · h2 20 rounded · h3 15 semibold · body 13 · label 13 medium · caption 11 medium · figure 22 rounded. All figures `monospacedDigit`.

## Layout
- Window 1000 x 660, hidden title bar. Sidebar 216 px with the same backdrop, 1 px line divider.
- Spacing base 4, screen padding 32 horizontal, header top 40. Cards 16 padding, radius 14 continuous. Grid gap 14.

## Signature: the Spare Ring
Whole disk as one circle, 280 px, 18 px stroke, starting at 12 o'clock: used (white 22%), then the review slice (amber) and the safe slice (mint with glow) at the end of the used arc, the empty track is free space. Idle: the round "Analisar" button (168 px, mint to glow gradient) sits inside. Scanning: rotating mint sweep plus percent. Done: safe size in mint display type.

## Components
- Sidebar row: 36 h, tile 24 (radius 28% of side, vertical gradient of the tint), label 13 medium, active row white 10% radius 9.
- PrimaryButton: capsule 34 h, mint to glow gradient, night text 13 semibold, press scale 0.97.
- QuietButton: capsule 34 h, white 10%, text 13 medium.
- Badge: capsule 20 h, tint text on tint 14%.
- Checkbox: 18 px radius 5, mint fill when on, 35% opacity when disabled (in use).
- Review row: 54 h, monospaced 11 path truncated in the middle, footer bar 68 h with selection total and the primary action.
- Motion: ease out, 120 to 250 ms for UI, 600 ms for the ring.
