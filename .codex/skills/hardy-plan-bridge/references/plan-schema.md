# Plan schema

Use JSON with `version: 1` and an `operations` array. Extra top-level context is allowed but ignored by the writer.

```json
{
  "version": 1,
  "operations": [
    {
      "type": "schedule.add",
      "title": "示例课程",
      "start": "2030-09-09 14:00",
      "end": "2030-09-09 15:40",
      "notes": "第5–6节｜教学楼 A101"
    },
    {
      "type": "task.add",
      "title": "完成课程复盘",
      "due": "2030-09-09",
      "priority": "normal",
      "pin": false,
      "notes": "整理三条关键结论",
      "subtasks": ["整理课堂笔记", "写出三个问题"]
    }
  ]
}
```

Supported operations:

- `schedule.add`: `title`, `start`, `end`, optional `notes`, optional `allowConflict`.
- `schedule.update`: `id` or exact `matchTitle`, then optional `title`, `start`, `end`, `notes`, `allowConflict`.
- `task.add`: `title`, optional `due`, `priority`, `pin`, `notes`, `subtasks`.
- `task.update`: `id` or exact `matchTitle`, then optional `title`, `due`, `priority`, `pin`, `notes`.
- `task.complete`: `id` or exact `matchTitle`.

Dates use local time. Schedule timestamps must be `YYYY-MM-DD HH:MM`. Task due values may be `YYYY-MM-DD` or `YYYY-MM-DD HH:MM`.

The bridge intentionally rejects deletion, invalid times, unresolved targets, exact duplicate unfinished tasks, and unapproved schedule conflicts. It also rejects clearing an existing due date because the current Hardy Tasks CLI has no corresponding action. Put the final desired fields directly on an `add` operation instead of adding and then updating or completing the same item within one plan.
