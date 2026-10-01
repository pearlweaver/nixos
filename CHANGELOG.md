# Version 26.10.1.3

- Gave the companion UI shadcn/ui's design-token architecture, keeping Perla's colours exactly as they were. Tokens are now named by role (`--background`/`--foreground`, `--card`, `--primary`, `--muted-foreground`, `--border`, `--input`, `--ring`, `--destructive`) rather than by appearance (`--ink-faint`, `--brass`, `--wax`), with shadcn's convention that a surface token is paired with its `-foreground`. 334 `var()` references were renamed across the CSS and JS. Palette values are byte-identical — this is a rename, not a restyle — and a test asserts they have not drifted.
- Borders now default to `--border` from one global rule rather than being hand-picked per component. All 96 existing border declarations already named a colour, `none`, or `transparent`, so nothing renders differently today; this is insurance for new components.
- Added `:focus-visible` styling. There was none at all, so keyboard focus on the phone-first UI was invisible.
- Defined a radius scale derived from a single `--radius`. Components are not yet moved onto it — that is the next phase.
