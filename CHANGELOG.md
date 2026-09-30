# Version 26.9.30.5

- Tier 1 Perla can now use the `question` tool. The old "No Interactive Prompts" rule told her she had no way to ask and must never use it, which made the question card and the voice answer loop unreachable in Tier 1. Replaced with guidance that still defaults to deciding rather than asking, and asks only when a wrong guess would actually cost something.
- Voice mode: a missed answer no longer dead-ends the turn. An unanswered *question* is answered with a nudge so Perla proceeds on her own best guess (once only, so a question-asking model can't loop). A missed *permission* is still never auto-decided — silence must never mean allow — and now says a permission is waiting.
