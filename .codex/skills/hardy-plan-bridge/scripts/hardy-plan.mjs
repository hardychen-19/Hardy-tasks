#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "../../../..");
const defaultConfigPath = path.join(repoRoot, ".hardy-plan.local.json");
const repositoryCli = path.join(repoRoot, "Scripts", "quiet-tasks-cli");
const defaultCli = fs.existsSync(repositoryCli) ? repositoryCli : path.join(os.homedir(), ".local", "bin", "quiet-tasks-cli");

function die(message, details = null) {
  console.error(JSON.stringify({ ok: false, error: message, details }, null, 2));
  process.exit(1);
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const item = argv[index];
    if (!item.startsWith("--")) die(`Unexpected argument: ${item}`);
    const key = item.slice(2);
    const next = argv[index + 1];
    if (next === undefined || next.startsWith("--")) args[key] = true;
    else { args[key] = next; index += 1; }
  }
  return args;
}

function readJson(filePath, label) {
  try { return JSON.parse(fs.readFileSync(filePath, "utf8")); }
  catch (error) { die(`Cannot read ${label}`, error.message); }
}

function stable(value) {
  if (Array.isArray(value)) return value.map(stable);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stable(value[key])]));
  }
  return value;
}

function digest(value) {
  const data = Buffer.isBuffer(value) ? value : Buffer.from(typeof value === "string" ? value : JSON.stringify(stable(value)));
  return crypto.createHash("sha256").update(data).digest("hex");
}

function localIso(value, label) {
  if (!/^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}$/.test(value || "")) throw new Error(`${label} must use YYYY-MM-DD HH:MM`);
  const date = new Date(value.replace(" ", "T"));
  if (Number.isNaN(date.getTime())) throw new Error(`Invalid ${label}: ${value}`);
  return date.toISOString();
}

function taskDue(value) {
  if (value === undefined || value === null || value === "") return null;
  if (!/^\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2})?$/.test(value)) throw new Error("Task due must use YYYY-MM-DD or YYYY-MM-DD HH:MM");
  return value;
}

function localDateText(value) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function dueMatches(task, desired) {
  const normalized = desired ?? null;
  if (task._plannedDue !== undefined) return task._plannedDue === normalized;
  if (normalized === null || normalized === "") return !task.deadline;
  if (/^\d{4}-\d{2}-\d{2}$/.test(normalized)) return localDateText(task.deadline) === normalized;
  return task.deadline === localIso(normalized, "task due");
}

function runCli(cli, cliArgs, allowFailure = false) {
  const result = spawnSync(cli, cliArgs, { encoding: "utf8", env: process.env });
  if (result.error) die(`Cannot run Hardy Tasks CLI at ${cli}`, result.error.message);
  if (result.status !== 0 && !allowFailure) die("Hardy Tasks CLI failed", { args: cliArgs, stderr: result.stderr.trim() });
  return result;
}

function cliJson(cli, cliArgs) {
  const result = runCli(cli, cliArgs);
  try { return JSON.parse(result.stdout || "[]"); }
  catch (error) { die("Hardy Tasks CLI returned invalid JSON", { args: cliArgs, output: result.stdout, error: error.message }); }
}

function resolveOne(items, operation, kind) {
  if (!operation.id && !operation.matchTitle) throw new Error(`${kind} requires id or matchTitle`);
  const matches = operation.id ? items.filter((item) => item.id === operation.id) : items.filter((item) => item.title === operation.matchTitle);
  if (matches.length === 0) throw new Error(`No matching ${kind}`);
  if (matches.length > 1) throw new Error(`Multiple matching ${kind}; use id`);
  return matches[0];
}

function overlap(items, candidate, ignoredId = null) {
  return items.filter((item) => item.id !== ignoredId && candidate.startAt < item.endAt && candidate.endAt > item.startAt);
}

function loadPlan(planPath) {
  const document = readJson(planPath, "plan");
  const plan = document?.version === 1 ? document : document?.suggestedPlan;
  if (plan?.version !== 1 || !Array.isArray(plan.operations)) die("Plan must contain version 1 and an operations array");
  if (plan.operations.length > 500) die("Plan exceeds the 500-operation safety limit");
  return plan;
}

function validateOptionalText(value, label) {
  if (value !== undefined && value !== null && typeof value !== "string") throw new Error(`${label} must be text or null`);
}

function rejectPlannedTarget(item) {
  if (String(item.id).startsWith("planned-")) throw new Error("Cannot update or complete an item added earlier in the same plan; merge the fields into its add operation");
}

function analyzePlan(plan, cli) {
  const schedules = cliJson(cli, ["schedule-list"]);
  const tasks = cliJson(cli, ["list", "--include-done"]);
  const stagedSchedules = schedules.map((item) => ({ ...item }));
  const stagedTasks = tasks.map((item) => ({ ...item }));
  const actions = [];

  for (let index = 0; index < plan.operations.length; index += 1) {
    const operation = plan.operations[index];
    const sequence = index + 1;
    try {
      if (!operation || typeof operation !== "object") throw new Error("Operation must be an object");
      if (operation.type === "schedule.add") {
        const title = String(operation.title || "").trim();
        if (!title) throw new Error("schedule.add requires title");
        validateOptionalText(operation.notes, "schedule notes");
        if (operation.allowConflict !== undefined && typeof operation.allowConflict !== "boolean") throw new Error("allowConflict must be boolean");
        const candidate = { id: `planned-${sequence}`, title, startAt: localIso(operation.start, "start"), endAt: localIso(operation.end, "end"), notes: operation.notes ?? null };
        if (candidate.endAt <= candidate.startAt) throw new Error("Schedule end must be after start");
        const duplicate = stagedSchedules.find((item) => item.title === candidate.title && item.startAt === candidate.startAt && item.endAt === candidate.endAt);
        if (duplicate) { actions.push({ sequence, type: operation.type, status: "skip", reason: "duplicate", existingId: duplicate.id }); continue; }
        const conflicts = overlap(stagedSchedules, candidate);
        const blocked = conflicts.length > 0 && operation.allowConflict !== true;
        actions.push({ sequence, type: operation.type, status: blocked ? "blocked" : "ready", title, start: operation.start, end: operation.end,
          conflicts: conflicts.map((item) => ({ id: item.id, title: item.title, startAt: item.startAt, endAt: item.endAt })), allowConflict: operation.allowConflict === true });
        if (!blocked) stagedSchedules.push(candidate);
      } else if (operation.type === "schedule.update") {
        const current = resolveOne(stagedSchedules, operation, "schedule");
        rejectPlannedTarget(current);
        validateOptionalText(operation.notes, "schedule notes");
        if (operation.allowConflict !== undefined && typeof operation.allowConflict !== "boolean") throw new Error("allowConflict must be boolean");
        const next = { ...current, title: operation.title === undefined ? current.title : String(operation.title).trim(),
          startAt: operation.start === undefined ? current.startAt : localIso(operation.start, "start"),
          endAt: operation.end === undefined ? current.endAt : localIso(operation.end, "end"), notes: operation.notes === undefined ? current.notes : operation.notes };
        if (!next.title || next.endAt <= next.startAt) throw new Error("Invalid updated schedule");
        const unchanged = next.title === current.title && next.startAt === current.startAt && next.endAt === current.endAt && (next.notes ?? null) === (current.notes ?? null);
        if (unchanged) { actions.push({ sequence, type: operation.type, status: "skip", reason: "already matches", existingId: current.id }); continue; }
        const conflicts = overlap(stagedSchedules, next, current.id);
        const blocked = conflicts.length > 0 && operation.allowConflict !== true;
        actions.push({ sequence, type: operation.type, status: blocked ? "blocked" : "ready", id: current.id, title: next.title,
          conflicts: conflicts.map((item) => ({ id: item.id, title: item.title })) });
        if (!blocked) Object.assign(current, next);
      } else if (operation.type === "task.add") {
        const title = String(operation.title || "").trim();
        if (!title) throw new Error("task.add requires title");
        taskDue(operation.due);
        validateOptionalText(operation.notes, "task notes");
        if (operation.pin !== undefined && typeof operation.pin !== "boolean") throw new Error("task pin must be boolean");
        if (operation.subtasks !== undefined && (!Array.isArray(operation.subtasks) || operation.subtasks.some((item) => typeof item !== "string" || !item.trim()))) throw new Error("subtasks must be an array of non-empty strings");
        const priority = operation.priority ?? "normal";
        if (!["low", "normal", "high"].includes(priority)) throw new Error("Invalid task priority");
        const duplicate = stagedTasks.find((item) => !item.done && item.title === title && dueMatches(item, operation.due));
        if (duplicate) { actions.push({ sequence, type: operation.type, status: "skip", reason: "duplicate", existingId: duplicate.id }); continue; }
        actions.push({ sequence, type: operation.type, status: "ready", title, due: operation.due ?? null, priority });
        stagedTasks.push({ id: `planned-${sequence}`, title, done: false, priority, pinned: operation.pin === true,
          notes: operation.notes ?? null, _plannedDue: operation.due ?? null });
      } else if (operation.type === "task.update") {
        const current = resolveOne(stagedTasks, operation, "task");
        rejectPlannedTarget(current);
        if (operation.due === null) throw new Error("Hardy Tasks CLI cannot clear an existing due date");
        if (operation.due !== undefined) taskDue(operation.due);
        validateOptionalText(operation.notes, "task notes");
        if (operation.pin !== undefined && typeof operation.pin !== "boolean") throw new Error("task pin must be boolean");
        if (operation.priority !== undefined && !["low", "normal", "high"].includes(operation.priority)) throw new Error("Invalid task priority");
        const next = { ...current,
          title: operation.title === undefined ? current.title : String(operation.title).trim(),
          priority: operation.priority === undefined ? current.priority : operation.priority,
          pinned: operation.pin === undefined ? current.pinned : operation.pin,
          notes: operation.notes === undefined ? current.notes : operation.notes };
        if (operation.due !== undefined) next._plannedDue = operation.due;
        if (!next.title) throw new Error("Invalid updated task title");
        const unchanged = next.title === current.title && next.priority === current.priority && next.pinned === current.pinned &&
          (next.notes ?? null) === (current.notes ?? null) && (operation.due === undefined || dueMatches(current, operation.due));
        if (unchanged) { actions.push({ sequence, type: operation.type, status: "skip", reason: "already matches", existingId: current.id }); continue; }
        actions.push({ sequence, type: operation.type, status: "ready", id: current.id, title: next.title });
        Object.assign(current, next);
      } else if (operation.type === "task.complete") {
        const current = resolveOne(stagedTasks, operation, "task");
        rejectPlannedTarget(current);
        if (current.done) actions.push({ sequence, type: operation.type, status: "skip", reason: "already complete", existingId: current.id });
        else { actions.push({ sequence, type: operation.type, status: "ready", id: current.id, title: current.title }); current.done = true; }
      } else throw new Error(`Unsupported operation type: ${operation.type}`);
    } catch (error) {
      actions.push({ sequence, type: operation?.type ?? null, status: "blocked", reason: error.message });
    }
  }

  const stateHash = digest({ schedules, tasks });
  const planHash = digest(plan);
  return { ok: !actions.some((item) => item.status === "blocked"), planHash, stateHash,
    confirmationToken: digest(`${planHash}:${stateHash}`),
    counts: { ready: actions.filter((item) => item.status === "ready").length, skipped: actions.filter((item) => item.status === "skip").length,
      conflicts: actions.reduce((sum, item) => sum + (item.conflicts?.length ?? 0), 0), blocked: actions.filter((item) => item.status === "blocked").length }, actions };
}

function operationArgs(operation, action) {
  if (operation.type === "schedule.add") {
    const args = ["schedule-add", "--title", operation.title, "--start", operation.start, "--end", operation.end];
    if (operation.notes !== undefined) args.push("--notes", String(operation.notes ?? ""));
    if (operation.allowConflict === true) args.push("--allow-conflict");
    return args;
  }
  if (operation.type === "schedule.update") {
    const args = ["schedule-update", "--id", action.id];
    if (operation.title !== undefined) args.push("--new-title", operation.title);
    if (operation.start !== undefined) args.push("--start", operation.start);
    if (operation.end !== undefined) args.push("--end", operation.end);
    if (operation.notes !== undefined) args.push("--notes", String(operation.notes ?? ""));
    if (operation.allowConflict === true) args.push("--allow-conflict");
    return args;
  }
  if (operation.type === "task.add") {
    const args = ["add", "--title", operation.title];
    if (operation.due) args.push("--due", operation.due);
    if (operation.priority) args.push("--priority", operation.priority);
    if (operation.pin === true) args.push("--pin");
    if (operation.notes !== undefined) args.push("--notes", String(operation.notes ?? ""));
    for (const subtask of operation.subtasks ?? []) args.push("--subtask", subtask);
    return args;
  }
  if (operation.type === "task.update") {
    const args = ["update", "--id", action.id];
    if (operation.title !== undefined) args.push("--new-title", operation.title);
    if (operation.due !== undefined) args.push("--due", operation.due);
    if (operation.priority !== undefined) args.push("--priority", operation.priority);
    if (operation.pin === true) args.push("--pin");
    if (operation.pin === false) args.push("--unpin");
    if (operation.notes !== undefined) args.push("--notes", String(operation.notes ?? ""));
    return args;
  }
  if (operation.type === "task.complete") return ["complete", "--id", action.id];
  throw new Error(`Unsupported operation type: ${operation.type}`);
}

function decodeXml(value) {
  return String(value ?? "").replaceAll("&lt;", "<").replaceAll("&gt;", ">").replaceAll("&quot;", '"')
    .replaceAll("&apos;", "'").replaceAll("&amp;", "&").replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)));
}

function unzipText(input, member, optional = false) {
  const result = spawnSync("/usr/bin/unzip", ["-p", input, member], { encoding: "utf8" });
  if (result.status !== 0) { if (optional) return ""; die(`Cannot read ${member} from XLSX`, result.stderr.trim()); }
  return result.stdout;
}

function attr(text, name) { return decodeXml(text.match(new RegExp(`\\b${name}="([^"]*)"`))?.[1] ?? ""); }

function columnIndex(reference) {
  const letters = reference.match(/^[A-Z]+/)?.[0] ?? "";
  let value = 0;
  for (const letter of letters) value = value * 26 + letter.charCodeAt(0) - 64;
  return value - 1;
}

function parseSharedStrings(xml) {
  const result = [];
  for (const match of xml.matchAll(/<si\b[^>]*>([\s\S]*?)<\/si>/g)) {
    result.push([...match[1].matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map((item) => decodeXml(item[1])).join(""));
  }
  return result;
}

function parseSheet(xml, shared) {
  const rows = [];
  for (const rowMatch of xml.matchAll(/<row\b[^>]*>([\s\S]*?)<\/row>/g)) {
    const row = [];
    for (const cellMatch of rowMatch[1].matchAll(/<c\b([^>]*)>([\s\S]*?)<\/c>/g)) {
      const attrs = cellMatch[1]; const body = cellMatch[2]; const index = columnIndex(attr(attrs, "r")); const type = attr(attrs, "t");
      const raw = body.match(/<v\b[^>]*>([\s\S]*?)<\/v>/)?.[1] ?? "";
      const inline = [...body.matchAll(/<t\b[^>]*>([\s\S]*?)<\/t>/g)].map((item) => decodeXml(item[1])).join("");
      row[index] = type === "s" ? (shared[Number(raw)] ?? "") : (type === "inlineStr" ? inline : decodeXml(raw));
    }
    rows.push(row);
  }
  return rows;
}

function addDays(dateText, days) {
  const date = new Date(`${dateText}T12:00:00`); date.setDate(date.getDate() + days);
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`;
}

function minutesToClock(total) { const value = (total + 1440) % 1440; return `${String(Math.floor(value / 60)).padStart(2, "0")}:${String(value % 60).padStart(2, "0")}`; }
function clockToMinutes(value) { const [hours, minutes] = value.split(":").map(Number); return hours * 60 + minutes; }
function writeOutput(value, outputPath) { const text = `${JSON.stringify(value, null, 2)}\n`; if (outputPath) fs.writeFileSync(outputPath, text, { mode: 0o600 }); process.stdout.write(text); }

function parseWeekNumber(fileName) {
  const token = fileName.match(/第\s*(\d+|[一二三四五六七八九十]+)\s*周/)?.[1];
  if (!token) return null;
  if (/^\d+$/.test(token)) return Number(token);
  const digits = { 一: 1, 二: 2, 三: 3, 四: 4, 五: 5, 六: 6, 七: 7, 八: 8, 九: 9 };
  if (token === "十") return 10;
  const [left, right] = token.split("十");
  if (token.includes("十")) return (left ? digits[left] : 1) * 10 + (right ? digits[right] : 0);
  return digits[token] ?? null;
}

function extractCourse(args) {
  const input = path.resolve(String(args.input || ""));
  if (!args.input || !fs.existsSync(input)) die("extract-course requires an existing --input XLSX path");
  const configPath = path.resolve(String(args.config || defaultConfigPath));
  const config = fs.existsSync(configPath) ? readJson(configPath, "local config") : {};
  const className = String(args.class || config.className || "").trim();
  if (!className) die("Missing class name; set --class or className in .hardy-plan.local.json");
  const commuteMinutes = Number(args["commute-min"] ?? config.commuteMinutes ?? 15);
  const weekNumber = Number(args.week ?? parseWeekNumber(path.basename(input)));
  const week1Monday = args["week1-monday"] || config.week1Monday;
  if (!Number.isInteger(weekNumber) || weekNumber < 1) die("Cannot determine week number; use --week");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(week1Monday || "")) die("Missing valid week1Monday in local config");
  const weekStart = addDays(week1Monday, (weekNumber - 1) * 7);
  const periods = config.periods || {};
  const listing = execFileSync("/usr/bin/unzip", ["-Z1", input], { encoding: "utf8" });
  const sheetMembers = listing.split("\n").filter((name) => /^xl\/worksheets\/sheet\d+\.xml$/.test(name));
  if (sheetMembers.length === 0) die("No worksheet XML found in XLSX");
  const shared = parseSharedStrings(unzipText(input, "xl/sharedStrings.xml", true));
  const facts = [];

  for (const member of sheetMembers) {
    const rows = parseSheet(unzipText(input, member), shared);
    if (rows.length === 0) continue;
    const headers = rows[0].map((value) => String(value ?? "").trim());
    const find = (names) => names.map((name) => headers.indexOf(name)).find((index) => index >= 0) ?? -1;
    const indexes = { weekday: find(["星期几", "星期"]), periods: find(["上课节次", "节次"]), course: find(["课程名称", "课程"]),
      teacher: find(["姓名", "教师"]), roomCode: find(["场地编号", "教室编号"]), room: find(["场地名称", "教室"]), classes: find(["教学班组成", "班级"]) };
    if (Object.values(indexes).some((index) => index < 0)) continue;
    for (let rowIndex = 1; rowIndex < rows.length; rowIndex += 1) {
      const row = rows[rowIndex];
      const classes = String(row[indexes.classes] ?? "").split(";").map((item) => item.trim());
      if (!classes.includes(className)) continue;
      const weekday = Number(row[indexes.weekday]); const periodText = String(row[indexes.periods] ?? ""); const periodMatch = periodText.match(/(\d+)\s*-\s*(\d+)节/);
      if (!Number.isInteger(weekday) || weekday < 1 || weekday > 7 || !periodMatch) continue;
      const first = Number(periodMatch[1]); const last = Number(periodMatch[2]); const startClock = periods[String(first)]?.[0]; const endClock = periods[String(last)]?.[1];
      const date = addDays(weekStart, weekday - 1);
      facts.push({ sheet: path.basename(member, ".xml"), row: rowIndex + 1, date, weekday, periodText, firstPeriod: first, lastPeriod: last,
        start: startClock ? `${date} ${startClock}` : null, end: endClock ? `${date} ${endClock}` : null,
        course: String(row[indexes.course] ?? "").trim(), teacher: String(row[indexes.teacher] ?? "").trim(),
        roomCode: String(row[indexes.roomCode] ?? "").trim(), room: String(row[indexes.room] ?? "").trim() });
    }
  }

  const warnings = [];
  if (facts.length === 0) warnings.push(`No rows exactly matched ${className}`);
  if (facts.some((fact) => !fact.start || !fact.end)) warnings.push("One or more periods are missing clock mappings");
  const operations = [];
  for (const fact of facts.filter((item) => item.start && item.end)) {
    const [date, startClock] = fact.start.split(" "); const [, endClock] = fact.end.split(" "); const destination = fact.room || fact.roomCode;
    const segments = fact.firstPeriod <= 4 && fact.lastPeriod >= 5
      ? [[fact.firstPeriod, 4], [5, fact.lastPeriod]]
      : [[fact.firstPeriod, fact.lastPeriod]];
    operations.push({ type: "schedule.add", title: "步行去上课", start: `${date} ${minutesToClock(clockToMinutes(startClock) - commuteMinutes)}`, end: fact.start, notes: `前往${destination}` });
    for (const [first, last] of segments) {
      const segmentStart = periods[String(first)]?.[0]; const segmentEnd = periods[String(last)]?.[1];
      if (!segmentStart || !segmentEnd) { warnings.push(`${date} ${first}-${last}节缺少时间映射`); continue; }
      operations.push({ type: "schedule.add", title: fact.course, start: `${date} ${segmentStart}`, end: `${date} ${segmentEnd}`,
        notes: `${first}-${last}节｜${destination}｜教师：${fact.teacher}` });
    }
    operations.push({ type: "schedule.add", title: "步行返程", start: fact.end, end: `${date} ${minutesToClock(clockToMinutes(endClock) + commuteMinutes)}`, notes: `从${destination}返回` });
  }
  writeOutput({ ok: warnings.length === 0, source: { fileName: path.basename(input), sha256: digest(fs.readFileSync(input)) }, className, weekNumber, weekStart,
    commuteMinutes, facts, warnings, suggestedPlan: { version: 1, operations } }, args.output);
}

const [command = "help", ...argv] = process.argv.slice(2);
const args = parseArgs(argv);
const cli = path.resolve(String(args.cli || process.env.HARDY_TASKS_CLI || defaultCli));

if (command === "extract-course") extractCourse(args);
else if (command === "preflight") {
  if (!args.plan) die("preflight requires --plan");
  writeOutput(analyzePlan(loadPlan(path.resolve(args.plan)), cli), args.output);
} else if (command === "apply") {
  if (!args.plan || !args.token) die("apply requires --plan and --token");
  const plan = loadPlan(path.resolve(args.plan)); const preflight = analyzePlan(plan, cli);
  if (preflight.confirmationToken !== args.token) die("Stale or incorrect confirmation token", preflight);
  if (!preflight.ok) die("Plan has blocked operations", preflight);
  const results = [];
  for (const action of preflight.actions) {
    if (action.status === "skip") { results.push({ sequence: action.sequence, type: action.type, status: "skipped", reason: action.reason }); continue; }
    const operation = plan.operations[action.sequence - 1]; const result = runCli(cli, operationArgs(operation, action), true);
    let output = result.stderr.trim();
    if (result.status === 0) { try { output = JSON.parse(result.stdout)[0]; } catch { output = result.stdout.trim(); } }
    results.push({ sequence: action.sequence, type: action.type, status: result.status === 0 ? "applied" : "failed", output });
    if (result.status !== 0) break;
  }
  const failed = results.filter((item) => item.status === "failed").length;
  writeOutput({ ok: failed === 0, planHash: preflight.planHash,
    counts: { added: results.filter((item) => item.status === "applied" && item.type.endsWith(".add")).length,
      updated: results.filter((item) => item.status === "applied" && item.type.endsWith(".update")).length,
      completed: results.filter((item) => item.status === "applied" && item.type === "task.complete").length,
      skipped: results.filter((item) => item.status === "skipped").length, failed }, results, verification: analyzePlan(plan, cli) }, args.output);
} else console.log(`Usage:
  hardy-plan.mjs extract-course --input FILE [--class NAME] [--week N] [--week1-monday YYYY-MM-DD] [--commute-min N] [--config FILE] [--output FILE]
  hardy-plan.mjs preflight --plan FILE [--cli FILE] [--output FILE]
  hardy-plan.mjs apply --plan FILE --token TOKEN [--cli FILE] [--output FILE]`);
