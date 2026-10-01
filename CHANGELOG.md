# Version 26.10.1.4

- Corner radii now come from the `--radius` scale instead of 17 hardcoded pixel values across 100 declarations. Each was mapped to the nearest step, so the largest change is 2.4px on message bubbles and 4.4px on one floating editor; 22 circular `50%` radii and three sub-4px decorative elements (hamburger lines, voice-wave bars) are deliberately left alone.
- Tokenised the two dominant transition durations (`0.15s`, `0.2s` — 65 of 78 timings) as `--duration` and `--duration-slow`, with `--ease` alongside. Values are unchanged, so no animation timing moved; the remaining hand-tuned durations stay literal on purpose.
