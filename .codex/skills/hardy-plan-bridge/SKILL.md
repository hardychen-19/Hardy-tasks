---
name: hardy-plan-bridge
description: Convert course spreadsheets or natural-language plans into compact, validated Hardy Tasks writes. Use inside the Hardy Tasks repository when the user supplies an XLSX timetable, asks to add schedules, or asks to create actionable tasks while minimizing model context and preserving preview-before-write safety.
---

# Hardy Plan Bridge

Keep interpretation in the model and move extraction, validation, conflict checks, writing, backups, and verification into deterministic scripts.

## Workflow

1. For an XLSX timetable, run:

   ```bash
   node .codex/skills/hardy-plan-bridge/scripts/hardy-plan.mjs extract-course --input PATH
   ```

   Read only the compact JSON output. Do not load or narrate the full workbook unless extraction reports an ambiguity.

2. Convert the useful facts or the user's natural language into the plan schema in `references/plan-schema.md`. Write the plan to a temporary JSON file outside the repository. If the extractor's `suggestedPlan` already matches the request, its output file can be passed directly to `preflight`. Use the model only for:
   - ambiguous class/course matching;
   - unclear dates or deadlines;
   - deciding how to resolve conflicts;
   - decomposing vague goals into actionable tasks.

3. Run deterministic preflight:

   ```bash
   node .codex/skills/hardy-plan-bridge/scripts/hardy-plan.mjs preflight --plan /tmp/plan.json
   ```

4. Show the compact preview and ask for confirmation. Never apply before confirmation. Keep the returned `confirmationToken` unchanged.

5. After confirmation, apply the exact reviewed plan:

   ```bash
   node .codex/skills/hardy-plan-bridge/scripts/hardy-plan.mjs apply --plan /tmp/plan.json --token TOKEN
   ```

6. Report `added`, `updated`, `completed`, `skipped`, and `conflicts` from the script output. Do not claim success if verification fails.

## Safety

- Use the repository's `Scripts/quiet-tasks-cli` as the only mutation backend; never hand-edit task or schedule JSON. The installed `~/.local/bin` copy is only a compatibility fallback.
- Do not implement deletion. Handle deletion through the existing explicit-confirmation workflow.
- Treat a stale confirmation token as a changed plan or changed database. Run preflight again and obtain a new confirmation.
- Do not set `allowConflict` unless the user has explicitly accepted that specific overlap.
- Store personal defaults only in the gitignored `.hardy-plan.local.json`; never commit private schedules or user data.

## Local defaults

`extract-course` reads `.hardy-plan.local.json` from the repository root. It may contain the exact class name, first-week Monday, commute duration, and period times. Command-line flags override the file.
