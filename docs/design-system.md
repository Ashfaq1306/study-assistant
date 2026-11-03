# Study Mate design system (v1.1, "liquid glass")

Study Mate is used by students aged 9–18, often while they are trying to resist their phone. The design aims to feel **calm, friendly and rewarding**, so studying feels inviting rather than like a punishment. Every screen is built from the same few pieces in `app/lib/core`.

## Principles and the psychology behind them

| Principle | What we do | Why it helps |
| --- | --- | --- |
| **Soft shapes feel safe** | Superellipse ("squircle") corners everywhere: cards, buttons, icon tiles, menus | Rounded forms read as approachable and non-threatening; sharp corners read as warnings. |
| **Depth shows what you can touch** | Raised glass panes, glossy icon tiles and 3D buttons that sink when pressed | Physical cues (affordances) make it obvious what is tappable without labels, which helps younger children. |
| **Rewarding, not punishing** | Bright gradients, sparkles, streak flames and trophies for progress; locks are explained kindly ("It unlocks when you pass your exam") | Positive reinforcement keeps motivation up; shame-free copy lowers anxiety before exams. |
| **One thing at a time** | Wizards with step dots, one main button per screen | Smaller decisions reduce cognitive load and decision fatigue. |
| **Readable for everyone** | Coloured text is darkened until it meets WCAG AA contrast (4.5:1) on glass; layouts survive 200% text size | Students with low vision or a cheap, dim screen can still read everything. |
| **Quick, quiet feedback** | 140–320 ms ease-out motion, light haptics on taps, animations off when the phone asks for reduced motion | Every tap feels answered, without motion that distracts from studying. |

## Tokens (`lib/core/theme/design_tokens.dart`)

- **Space:** 4 · 8 · 12 · 16 · 20 · 24 · 32 · 48 (an 8-point rhythm).
- **Radii:** chips 14, buttons and inputs 22, cards 28, sheets 34; icon tiles round their corners by 30% of their size.
- **Motion:** fast 140 ms, normal 220 ms, slow 320 ms, `easeOutCubic`; pressed things shrink to 96.5%.
- **Glass:** 22 px backdrop blur; light glass is milky white (78% → 56%), dark glass is smoked (11% → 5%); a 1.2 px rim.
- **Colour:** six accent themes (Lavender, Ocean, Emerald, Sunset, Rose, Royal gold) in light and dark, plus sunshine, mint, coral and sky for meaning (warning, success, danger, info). See `app_colors.dart`. Use `AppColors.legible(color)` for coloured text.

## Building blocks

| Widget | Use it for |
| --- | --- |
| `LiquidGlass` | Any frosted pane: blur, tint, light-catching rim and top sheen. |
| `ClayCard` | Cards. Clear glass by default; `color:` for a solid coloured pane (hero cards); `selected:` for choice cards. |
| `GlassIconTile` / `IconBadge` | Every illustrative icon: a glossy squircle tile with a curved highlight and coloured glow. No emoji or flat stickers. |
| `GlassChip` | Feature highlights and tags (icon tile + label). |
| `Button3D` | Main actions. Glossy face, physical edge that sinks when pressed; `.secondary` is glass. |
| `ChoicePill` | Single choices such as subjects. |
| `MessageBanner` | Errors, info and success inside forms (tinted glass, icon tile, readable text). |
| `RoundBackButton` | The glass back button on every page. |
| `WeekBars` | Weekly bar charts. Sizes itself to the text scale. |

Menus, dialogs, bottom sheets, chips and snack bars share the squircle shape and glass rim through `AppTheme`.

## Rules for new screens

1. Build from the widgets above; never draw a raw `Container` card or a pale circle "sticker".
2. One main `Button3D` per screen; other actions are secondary or text buttons.
3. Coloured text goes through `AppColors.legible`.
4. Check the screen in light and dark mode, at 1.3× and 2× text size, and on a small phone.
5. Copy is short, warm and encouraging (see `CLAUDE.md`).

`app/test/core/design_system_test.dart` checks contrast and that the chart never overflows at large text sizes.
