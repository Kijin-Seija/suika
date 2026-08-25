#!/usr/bin/env node

const fs = require("node:fs");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");
const { spawn, spawnSync } = require("node:child_process");

const SQLITE_WARNING_FLAG = "--disable-warning=ExperimentalWarning";
if (process.env.PUSH_CODE_SQLITE_WARNING_SUPPRESSED !== "1") {
  const existingNodeOptions = String(process.env.NODE_OPTIONS || "");
  if (!existingNodeOptions.includes(SQLITE_WARNING_FLAG)) {
    const env = {
      ...process.env,
      NODE_OPTIONS: `${existingNodeOptions} ${SQLITE_WARNING_FLAG}`.trim(),
      PUSH_CODE_SQLITE_WARNING_SUPPRESSED: "1",
    };
    const restarted = spawnSync(process.execPath, process.argv.slice(1), {
      stdio: "inherit",
      env,
    });
    process.exit(restarted.status === null ? 1 : restarted.status);
  }
}

const { DatabaseSync } = require("node:sqlite");

function codexHomeDir() {
  return path.resolve(process.env.CODEX_HOME || path.join(os.homedir(), ".codex"));
}

const SCRIPT_PATH = fs.realpathSync(process.argv[1]);
const SCRIPT_DIR = path.dirname(SCRIPT_PATH);
const SKILL_DIR = path.dirname(SCRIPT_DIR);
const GLOBAL_MONITOR_DIR = path.join(codexHomeDir(), "push-code-monitor");
const DEFAULT_CONFIG_PATH = path.join(GLOBAL_MONITOR_DIR, "config.json");
const DEFAULT_DB_PATH = path.join(GLOBAL_MONITOR_DIR, "monitor.db");
const DEFAULT_LEGACY_STATE_PATH = path.join(GLOBAL_MONITOR_DIR, "state.json");
const DEFAULT_SERVICE_STATUS_PATH = path.join(GLOBAL_MONITOR_DIR, "service.json");
const DEFAULT_LAUNCHER_PATH = path.join(SCRIPT_DIR, "push-code-run.sh");

function fail(message, exitCode = 1) {
  console.error(`错误: ${message}`);
  process.exit(exitCode);
}

function nowMs() {
  return Date.now();
}

function printJson(value) {
  process.stdout.write(`${JSON.stringify(value, null, 2)}\n`);
}

function ensureParentDir(filePath) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
}

function readJsonFile(filePath, fallback) {
  if (!fs.existsSync(filePath)) {
    return fallback;
  }
  try {
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    fail(`无法读取 JSON 文件 ${filePath}: ${error.message}`);
  }
}

function writeJsonFile(filePath, value) {
  ensureParentDir(filePath);
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`, "utf8");
}

function parseBoolean(value, defaultValue = false) {
  if (value === undefined || value === null || value === "") {
    return defaultValue;
  }
  const normalized = String(value).trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) {
    return true;
  }
  if (["0", "false", "no", "off"].includes(normalized)) {
    return false;
  }
  fail(`无法解析布尔值: ${value}`);
}

function parsePositiveInteger(value, defaultValue) {
  if (value === undefined || value === null || value === "") {
    return defaultValue;
  }
  const parsed = Number.parseInt(String(value), 10);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    fail(`请输入大于 0 的整数: ${value}`);
  }
  return parsed;
}

function parsePort(value, defaultValue) {
  if (value === undefined || value === null || value === "") {
    return defaultValue;
  }
  const parsed = Number.parseInt(String(value), 10);
  if (!Number.isFinite(parsed) || parsed < 0 || parsed > 65535) {
    fail(`请输入 0-65535 之间的端口号: ${value}`);
  }
  return parsed;
}

function parseArgs(argv) {
  if (argv.length === 0) {
    fail("缺少子命令");
  }
  const [command, ...rest] = argv;
  const options = { _: [] };
  for (let index = 0; index < rest.length; index += 1) {
    const token = rest[index];
    if (!token.startsWith("--")) {
      options._.push(token);
      continue;
    }
    const key = token.slice(2);
    const next = rest[index + 1];
    if (next === undefined || next.startsWith("--")) {
      options[key] = "true";
      continue;
    }
    options[key] = next;
    index += 1;
  }
  return { command, options };
}

function requireOption(options, key) {
  const value = options[key];
  if (value === undefined || value === null || value === "") {
    fail(`缺少 --${key}`);
  }
  return String(value);
}

function normalizePath(filePath, fallback) {
  const raw = filePath || fallback;
  return path.resolve(String(raw));
}

function defaultMonitorConfig() {
  return {
    version: 1,
    enabled: false,
    intervalSeconds: 300,
    codexBin: "",
    dashboardHost: "127.0.0.1",
    dashboardPort: 4635,
  };
}

function loadMonitorConfig(configPath) {
  const existing = readJsonFile(configPath, defaultMonitorConfig());
  return {
    ...defaultMonitorConfig(),
    ...existing,
  };
}

function saveMonitorConfig(configPath, config) {
  writeJsonFile(configPath, config);
}

function serviceStatusPath(options) {
  return normalizePath(options["service-status-path"], DEFAULT_SERVICE_STATUS_PATH);
}

function loadServiceStatus(filePath) {
  return readJsonFile(filePath, {
    pid: 0,
    startedAt: 0,
    logPath: "",
    dbPath: "",
    configPath: "",
    launcherPath: "",
    intervalSeconds: 0,
    model: "",
    dashboardHost: "",
    dashboardPort: 0,
    dashboardUrl: "",
    lastScanAt: 0,
    lastScanNotificationCount: 0,
    lastScanErrorCount: 0,
  });
}

function saveServiceStatus(filePath, value) {
  writeJsonFile(filePath, value);
}

function openDatabase(dbPath) {
  ensureParentDir(dbPath);
  const database = new DatabaseSync(dbPath);
  database.exec("PRAGMA journal_mode = WAL");
  database.exec("PRAGMA foreign_keys = ON");
  return database;
}

function initDatabase(database) {
  database.exec(`
    CREATE TABLE IF NOT EXISTS mr_threads (
      mr_id TEXT PRIMARY KEY,
      thread_id TEXT NOT NULL DEFAULT '',
      branch TEXT NOT NULL DEFAULT '',
      target_branch TEXT NOT NULL DEFAULT '',
      mr_url TEXT NOT NULL DEFAULT '',
      project_id TEXT NOT NULL DEFAULT '',
      project_root TEXT NOT NULL DEFAULT '',
      launcher_path TEXT NOT NULL DEFAULT '',
      active INTEGER NOT NULL DEFAULT 1,
      last_status TEXT NOT NULL DEFAULT '',
      last_raw_status TEXT NOT NULL DEFAULT '',
      last_head_sha TEXT NOT NULL DEFAULT '',
      last_note_id TEXT NOT NULL DEFAULT '',
      last_note_created_at TEXT NOT NULL DEFAULT '',
      last_fingerprint TEXT NOT NULL DEFAULT '',
      last_notified_fingerprint TEXT NOT NULL DEFAULT '',
      last_checked_at INTEGER NOT NULL DEFAULT 0,
      last_notified_at INTEGER NOT NULL DEFAULT 0,
      closed_reason TEXT NOT NULL DEFAULT '',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  `);
  ensureDatabaseColumn(database, "mr_threads", "project_root", "TEXT NOT NULL DEFAULT ''");
  ensureDatabaseColumn(database, "mr_threads", "launcher_path", "TEXT NOT NULL DEFAULT ''");
  database.exec(`
    CREATE TABLE IF NOT EXISTS scan_runs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      trigger_source TEXT NOT NULL DEFAULT '',
      triggered_at INTEGER NOT NULL DEFAULT 0,
      completed_at INTEGER NOT NULL DEFAULT 0,
      duration_ms INTEGER NOT NULL DEFAULT 0,
      scanned_mr_count INTEGER NOT NULL DEFAULT 0,
      ready_count INTEGER NOT NULL DEFAULT 0,
      needs_attention_count INTEGER NOT NULL DEFAULT 0,
      still_waiting_count INTEGER NOT NULL DEFAULT 0,
      notification_count INTEGER NOT NULL DEFAULT 0,
      error_count INTEGER NOT NULL DEFAULT 0,
      notifications_json TEXT NOT NULL DEFAULT '[]',
      scan_errors_json TEXT NOT NULL DEFAULT '[]',
      result_json TEXT NOT NULL DEFAULT '{}'
    )
  `);
}

function ensureDatabaseColumn(database, tableName, columnName, definition) {
  const columns = database.prepare(`PRAGMA table_info(${tableName})`).all();
  if (columns.some((column) => String(column.name || "") === columnName)) {
    return;
  }
  database.exec(`ALTER TABLE ${tableName} ADD COLUMN ${columnName} ${definition}`);
}

function tableCount(database, tableName) {
  const row = database
    .prepare(`SELECT COUNT(*) AS count FROM ${tableName}`)
    .get();
  return Number(row.count || 0);
}

function parseJsonText(value, fallback) {
  try {
    return JSON.parse(String(value || ""));
  } catch (_error) {
    return fallback;
  }
}

function normalizeLegacyEntries(legacyState) {
  const entries = Array.isArray(legacyState?.entries) ? legacyState.entries : [];
  return entries.map((entry) => ({
    mrId: String(entry.mrId || ""),
    threadId: String(entry.threadId || ""),
    branch: String(entry.branch || ""),
    targetBranch: String(entry.targetBranch || ""),
    mrUrl: String(entry.mrUrl || ""),
    projectId: String(entry.projectId || ""),
    projectRoot: String(entry.projectRoot || ""),
    launcherPath: String(entry.launcherPath || ""),
    active: entry.active !== false,
    lastStatus: String(entry.lastStatus || ""),
    lastRawStatus: String(entry.lastRawStatus || ""),
    lastHeadSha: String(entry.lastHeadSha || ""),
    lastNoteId: String(entry.lastNoteId || ""),
    lastNoteCreatedAt: String(entry.lastNoteCreatedAt || ""),
    lastFingerprint: String(entry.lastFingerprint || ""),
    lastNotifiedFingerprint: String(entry.lastNotifiedFingerprint || ""),
    lastCheckedAt: Number(entry.lastCheckedAt || 0),
    lastNotifiedAt: Number(entry.lastNotifiedAt || 0),
    closedReason: String(entry.closedReason || ""),
    createdAt: Number(entry.createdAt || 0),
    updatedAt: Number(entry.updatedAt || 0),
  }));
}

function upsertEntry(database, entry) {
  database.prepare(`
    INSERT INTO mr_threads (
      mr_id,
      thread_id,
      branch,
      target_branch,
      mr_url,
      project_id,
      project_root,
      launcher_path,
      active,
      last_status,
      last_raw_status,
      last_head_sha,
      last_note_id,
      last_note_created_at,
      last_fingerprint,
      last_notified_fingerprint,
      last_checked_at,
      last_notified_at,
      closed_reason,
      created_at,
      updated_at
    ) VALUES (
      @mrId,
      @threadId,
      @branch,
      @targetBranch,
      @mrUrl,
      @projectId,
      @projectRoot,
      @launcherPath,
      @active,
      @lastStatus,
      @lastRawStatus,
      @lastHeadSha,
      @lastNoteId,
      @lastNoteCreatedAt,
      @lastFingerprint,
      @lastNotifiedFingerprint,
      @lastCheckedAt,
      @lastNotifiedAt,
      @closedReason,
      @createdAt,
      @updatedAt
    )
    ON CONFLICT(mr_id) DO UPDATE SET
      thread_id = excluded.thread_id,
      branch = excluded.branch,
      target_branch = excluded.target_branch,
      mr_url = excluded.mr_url,
      project_id = excluded.project_id,
      project_root = excluded.project_root,
      launcher_path = excluded.launcher_path,
      active = excluded.active,
      last_status = excluded.last_status,
      last_raw_status = excluded.last_raw_status,
      last_head_sha = excluded.last_head_sha,
      last_note_id = excluded.last_note_id,
      last_note_created_at = excluded.last_note_created_at,
      last_fingerprint = excluded.last_fingerprint,
      last_notified_fingerprint = excluded.last_notified_fingerprint,
      last_checked_at = excluded.last_checked_at,
      last_notified_at = excluded.last_notified_at,
      closed_reason = excluded.closed_reason,
      created_at = COALESCE(mr_threads.created_at, excluded.created_at),
      updated_at = excluded.updated_at
  `).run({
    ...entry,
    active: entry.active ? 1 : 0,
  });
}

function maybeMigrateLegacyState(database, legacyStatePath) {
  if (!legacyStatePath || !fs.existsSync(legacyStatePath)) {
    return {
      migrated: false,
      source: "",
      entries: 0,
    };
  }
  const legacyState = readJsonFile(legacyStatePath, { entries: [] });
  const entries = normalizeLegacyEntries(legacyState);
  for (const entry of entries) {
    if (!entry.mrId) {
      continue;
    }
    upsertEntry(database, entry);
  }
  return {
    migrated: true,
    source: legacyStatePath,
    entries: entries.length,
  };
}

function maybeMigrateLegacyDatabase(database, legacyDbPath, targetDbPath = "") {
  if (!legacyDbPath || !fs.existsSync(legacyDbPath)) {
    return {
      migrated: false,
      source: "",
      entries: 0,
    };
  }

  if (targetDbPath && path.resolve(legacyDbPath) === path.resolve(targetDbPath)) {
    return {
      migrated: false,
      source: legacyDbPath,
      entries: 0,
    };
  }

  let sourceDatabase;
  try {
    sourceDatabase = new DatabaseSync(legacyDbPath, { readonly: true });
  } catch (_error) {
    return {
      migrated: false,
      source: legacyDbPath,
      entries: 0,
    };
  }

  try {
    const table = sourceDatabase
      .prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'mr_threads'")
      .get();
    if (!table) {
      return {
        migrated: false,
        source: legacyDbPath,
        entries: 0,
      };
    }

    const rows = sourceDatabase.prepare("SELECT * FROM mr_threads").all();
    const entries = rowsToEntries(rows);
    for (const entry of entries) {
      if (!entry.mrId) {
        continue;
      }
      upsertEntry(database, entry);
    }
    return {
      migrated: true,
      source: legacyDbPath,
      entries: entries.length,
    };
  } finally {
    sourceDatabase.close();
  }
}

function dbPathFromOptions(options) {
  return normalizePath(options["db-path"], DEFAULT_DB_PATH);
}

function resolveEntryProjectRoot(entry, options) {
  if (entry.projectRoot) {
    return path.resolve(entry.projectRoot);
  }
  return normalizePath(options["project-root"], process.cwd());
}

function resolveEntryLauncherPath(entry, options, projectRoot) {
  if (entry.launcherPath) {
    return path.resolve(entry.launcherPath);
  }
  return normalizePath(options["launcher-path"], DEFAULT_LAUNCHER_PATH);
}

function rowsToEntries(rows) {
  return rows.map((row) => ({
    mrId: String(row.mr_id || ""),
    threadId: String(row.thread_id || ""),
    branch: String(row.branch || ""),
    targetBranch: String(row.target_branch || ""),
    mrUrl: String(row.mr_url || ""),
    projectId: String(row.project_id || ""),
    projectRoot: String(row.project_root || ""),
    launcherPath: String(row.launcher_path || ""),
    active: Number(row.active || 0) === 1,
    lastStatus: String(row.last_status || ""),
    lastRawStatus: String(row.last_raw_status || ""),
    lastHeadSha: String(row.last_head_sha || ""),
    lastNoteId: String(row.last_note_id || ""),
    lastNoteCreatedAt: String(row.last_note_created_at || ""),
    lastFingerprint: String(row.last_fingerprint || ""),
    lastNotifiedFingerprint: String(row.last_notified_fingerprint || ""),
    lastCheckedAt: Number(row.last_checked_at || 0),
    lastNotifiedAt: Number(row.last_notified_at || 0),
    closedReason: String(row.closed_reason || ""),
    createdAt: Number(row.created_at || 0),
    updatedAt: Number(row.updated_at || 0),
  }));
}

function listEntries(database, activeOnly = false) {
  const query = activeOnly
    ? "SELECT * FROM mr_threads WHERE active = 1 ORDER BY mr_id"
    : "SELECT * FROM mr_threads ORDER BY mr_id";
  return rowsToEntries(database.prepare(query).all());
}

function listRecentScanRuns(database, limit = 20) {
  return database
    .prepare(`
      SELECT *
      FROM scan_runs
      ORDER BY triggered_at DESC, id DESC
      LIMIT ?
    `)
    .all(limit)
    .map((row) => ({
      id: Number(row.id || 0),
      trigger_source: String(row.trigger_source || ""),
      triggered_at: Number(row.triggered_at || 0),
      completed_at: Number(row.completed_at || 0),
      duration_ms: Number(row.duration_ms || 0),
      scanned_mr_count: Number(row.scanned_mr_count || 0),
      ready_count: Number(row.ready_count || 0),
      needs_attention_count: Number(row.needs_attention_count || 0),
      still_waiting_count: Number(row.still_waiting_count || 0),
      notification_count: Number(row.notification_count || 0),
      error_count: Number(row.error_count || 0),
      notifications: parseJsonText(row.notifications_json, []),
      scan_errors: parseJsonText(row.scan_errors_json, []),
      result: parseJsonText(row.result_json, {}),
    }));
}

function recordScanRun(database, result) {
  database.prepare(`
    INSERT INTO scan_runs (
      trigger_source,
      triggered_at,
      completed_at,
      duration_ms,
      scanned_mr_count,
      ready_count,
      needs_attention_count,
      still_waiting_count,
      notification_count,
      error_count,
      notifications_json,
      scan_errors_json,
      result_json
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
  `).run(
    String(result.trigger_source || ""),
    Number(result.triggered_at || 0),
    Number(result.completed_at || 0),
    Number(result.duration_ms || 0),
    Array.isArray(result.scanned_mrs) ? result.scanned_mrs.length : 0,
    Array.isArray(result.ready_to_submit) ? result.ready_to_submit.length : 0,
    Array.isArray(result.needs_attention) ? result.needs_attention.length : 0,
    Array.isArray(result.still_waiting) ? result.still_waiting.length : 0,
    Array.isArray(result.notifications) ? result.notifications.length : 0,
    Array.isArray(result.scan_errors) ? result.scan_errors.length : 0,
    JSON.stringify(result.notifications || []),
    JSON.stringify(result.scan_errors || []),
    JSON.stringify(result),
  );
}

function activeChatProcessesPath() {
  return path.join(codexHomeDir(), "process_manager", "chat_processes.json");
}

function pidIsAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) {
    return false;
  }
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error.code === "EPERM";
  }
}

function threadRunningState(threadId) {
  let payload = [];
  const filePath = activeChatProcessesPath();
  if (fs.existsSync(filePath)) {
    try {
      const parsed = JSON.parse(fs.readFileSync(filePath, "utf8"));
      if (Array.isArray(parsed)) {
        payload = parsed;
      }
    } catch (_error) {
      payload = [];
    }
  }

  const activeEntries = payload
    .filter((item) => item && String(item.conversationId || "") === threadId)
    .filter((item) => pidIsAlive(item.osPid))
    .map((item) => ({
      command: String(item.command || ""),
      os_pid: item.osPid,
      process_id: String(item.processId || ""),
      turn_id: String(item.turnId || ""),
      updated_at_ms: item.updatedAtMs || 0,
    }));

  return {
    thread_id: threadId,
    running: activeEntries.length > 0,
    active_entries: activeEntries,
    source: filePath,
  };
}

function monitorServiceState(statusPath) {
  const payload = loadServiceStatus(statusPath);
  const pid = Number(payload.pid || 0);
  const running = pidIsAlive(pid);
  return {
    service_status_path: statusPath,
    running,
    pid,
    started_at: Number(payload.startedAt || 0),
    log_path: String(payload.logPath || ""),
    db_path: String(payload.dbPath || ""),
    config_path: String(payload.configPath || ""),
    launcher_path: String(payload.launcherPath || ""),
    interval_seconds: Number(payload.intervalSeconds || 0),
    model: String(payload.model || ""),
    dashboard_host: String(payload.dashboardHost || ""),
    dashboard_port: Number(payload.dashboardPort || 0),
    dashboard_url: String(payload.dashboardUrl || ""),
    last_scan_at: Number(payload.lastScanAt || 0),
    last_scan_notification_count: Number(payload.lastScanNotificationCount || 0),
    last_scan_error_count: Number(payload.lastScanErrorCount || 0),
  };
}

function dashboardHost(config, options) {
  return String(options["dashboard-host"] || config.dashboardHost || "127.0.0.1");
}

function dashboardPort(config, options) {
  return parsePort(options["dashboard-port"], Number(config.dashboardPort || 4635));
}

function dashboardUrl(host, port) {
  return `http://${host}:${port}/`;
}

function codexBin(config) {
  if (process.env.PUSH_CODE_MR_MONITOR_CODEX_BIN) {
    return process.env.PUSH_CODE_MR_MONITOR_CODEX_BIN;
  }
  if (config.codexBin) {
    return config.codexBin;
  }
  return "codex";
}

function notifyThread(threadId, message, config, model = "") {
  const state = threadRunningState(threadId);
  if (state.running) {
    return {
      thread_id: threadId,
      notified: false,
      deferred: true,
      reason: "thread_running",
      active_entries: state.active_entries,
    };
  }

  const codexCommand = codexBin(config);
  const logDir = path.join(GLOBAL_MONITOR_DIR, "logs");
  fs.mkdirSync(logDir, { recursive: true });
  const timestamp = nowMs();
  const logPath = path.join(logDir, `notify-${threadId}-${timestamp}.log`);
  const output = fs.openSync(logPath, "a");
  const command = ["exec", "resume", "--skip-git-repo-check", threadId, "-"];
  if (model) {
    command.push("--model", model);
  }

  const child = spawn(codexCommand, command, {
    detached: true,
    stdio: ["pipe", output, output],
  });
  child.stdin.end(message, "utf8");
  child.unref();

  return {
    thread_id: threadId,
    notified: true,
    deferred: false,
    spawned_pid: child.pid,
    log_path: logPath,
    command: [codexCommand, ...command],
  };
}

function runJsonCommand(command, args, cwd) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: "utf8",
    env: process.env,
  });

  if (result.error) {
    return {
      ok: false,
      exitCode: 1,
      stderr: result.error.message,
      stdout: result.stdout || "",
    };
  }

  if (result.status !== 0) {
    return {
      ok: false,
      exitCode: result.status,
      stderr: result.stderr || "",
      stdout: result.stdout || "",
    };
  }

  try {
    return {
      ok: true,
      value: JSON.parse(result.stdout || "{}"),
      stdout: result.stdout || "",
    };
  } catch (error) {
    return {
      ok: false,
      exitCode: 1,
      stderr: `JSON 解析失败: ${error.message}`,
      stdout: result.stdout || "",
    };
  }
}

function activeMappingItem(entry) {
  return {
    mr_id: entry.mrId,
    thread_id: entry.threadId,
    project_id: entry.projectId,
    branch: entry.branch,
    target_branch: entry.targetBranch,
    mr_url: entry.mrUrl,
    project_root: entry.projectRoot,
    launcher_path: entry.launcherPath,
    active: entry.active,
    last_status: entry.lastStatus,
    last_raw_status: entry.lastRawStatus,
    last_checked_at: entry.lastCheckedAt,
    last_notified_at: entry.lastNotifiedAt,
    closed_reason: entry.closedReason,
    created_at: entry.createdAt,
    updated_at: entry.updatedAt,
  };
}

function dashboardData(options = {}) {
  const configPath = normalizePath(options["config-path"], DEFAULT_CONFIG_PATH);
  const dbPath = dbPathFromOptions(options);
  const statusPath = serviceStatusPath(options);
  const config = loadMonitorConfig(configPath);
  const database = openDatabase(dbPath);
  initDatabase(database);
  const activeEntries = listEntries(database, true).map(activeMappingItem);
  const allEntries = listEntries(database, false).map(activeMappingItem);
  const recentScans = listRecentScanRuns(
    database,
    parsePositiveInteger(options.limit, 20),
  );
  database.close();

  return {
    generated_at: nowMs(),
    service_status: monitorServiceState(statusPath),
    config: {
      enabled: config.enabled,
      interval_seconds: config.intervalSeconds,
      codex_bin: config.codexBin,
      dashboard_host: config.dashboardHost,
      dashboard_port: config.dashboardPort,
    },
    counts: {
      active_mr_count: activeEntries.length,
      all_mr_count: allEntries.length,
      recent_scan_count: recentScans.length,
    },
    active_mrs: activeEntries,
    all_mrs: allEntries,
    recent_scans: recentScans,
  };
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function dashboardHtml() {
  return `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Push Code Monitor Dashboard</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f4f7fb;
      --card: #ffffff;
      --text: #162033;
      --muted: #5b6880;
      --line: #d8e0ec;
      --accent: #1f6feb;
      --good: #1a7f37;
      --warn: #9a6700;
      --bad: #cf222e;
      --shadow: 0 18px 40px rgba(22, 32, 51, 0.08);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: ui-sans-serif, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: linear-gradient(180deg, #eef4ff 0%, var(--bg) 38%, #f7f9fc 100%);
      color: var(--text);
    }
    main {
      max-width: 1280px;
      margin: 0 auto;
      padding: 28px 20px 40px;
    }
    h1, h2, h3, p { margin: 0; }
    .hero {
      display: flex;
      justify-content: space-between;
      gap: 16px;
      align-items: flex-end;
      margin-bottom: 20px;
    }
    .hero h1 { font-size: 30px; }
    .hero p { color: var(--muted); margin-top: 8px; }
    .grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 14px;
      margin-bottom: 18px;
    }
    .card {
      background: var(--card);
      border: 1px solid var(--line);
      border-radius: 18px;
      box-shadow: var(--shadow);
      padding: 16px;
    }
    .stat-value {
      font-size: 28px;
      font-weight: 700;
      margin-top: 8px;
    }
    .stat-label, .meta, .empty, .pill {
      color: var(--muted);
      font-size: 13px;
    }
    .section {
      margin-top: 20px;
    }
    .section-header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      margin-bottom: 10px;
    }
    table {
      width: 100%;
      border-collapse: collapse;
      font-size: 14px;
    }
    th, td {
      text-align: left;
      padding: 10px 8px;
      border-bottom: 1px solid var(--line);
      vertical-align: top;
    }
    th { color: var(--muted); font-weight: 600; }
    code, pre {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 12px;
    }
    pre {
      white-space: pre-wrap;
      word-break: break-word;
      background: #f6f8fa;
      border-radius: 12px;
      padding: 12px;
      margin: 8px 0 0;
    }
    .pill {
      display: inline-block;
      padding: 4px 8px;
      border-radius: 999px;
      background: #eef2ff;
      color: #3651d3;
      font-weight: 600;
    }
    .status-good { color: var(--good); }
    .status-bad { color: var(--bad); }
    .status-warn { color: var(--warn); }
    details {
      border: 1px solid var(--line);
      border-radius: 14px;
      padding: 12px 14px;
      background: #fff;
    }
    details + details { margin-top: 10px; }
    summary {
      cursor: pointer;
      font-weight: 600;
    }
    .scan-meta {
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      margin-top: 8px;
      color: var(--muted);
      font-size: 13px;
    }
    .empty {
      padding: 16px 0;
    }
    a { color: var(--accent); text-decoration: none; }
    @media (max-width: 700px) {
      .hero { flex-direction: column; align-items: flex-start; }
      table { display: block; overflow-x: auto; }
    }
  </style>
</head>
<body>
  <main>
    <section class="hero">
      <div>
        <h1>Push Code Monitor Dashboard</h1>
        <p>自动刷新当前 monitor 状态、会话与 MR 映射，以及最近巡检记录。</p>
      </div>
      <div class="pill" id="refreshLabel">加载中</div>
    </section>

    <section class="grid" id="stats"></section>

    <section class="section card">
      <div class="section-header">
        <h2>Monitor 状态</h2>
      </div>
      <div id="serviceStatus" class="meta">加载中...</div>
    </section>

    <section class="section card">
      <div class="section-header">
        <h2>会话 / MR 映射</h2>
        <span class="meta" id="mappingCount"></span>
      </div>
      <div id="mappings"></div>
    </section>

    <section class="section card">
      <div class="section-header">
        <h2>最近巡检记录</h2>
        <span class="meta">包含触发时间、分析结果、通知会话</span>
      </div>
      <div id="scanHistory"></div>
    </section>
  </main>

  <script>
    const REFRESH_MS = 5000;

    function fmtTime(value) {
      if (!value) return "-";
      return new Date(value).toLocaleString("zh-CN", { hour12: false });
    }

    function escapeHtml(value) {
      return String(value ?? "")
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;");
    }

    function renderStats(data) {
      const stats = [
        ["运行状态", data.service_status.running ? "运行中" : "未运行"],
        ["活跃 MR", data.counts.active_mr_count],
        ["历史登记", data.counts.all_mr_count],
        ["最近巡检", data.counts.recent_scan_count],
      ];
      document.getElementById("stats").innerHTML = stats.map(([label, value]) => \`
        <article class="card">
          <div class="stat-label">\${escapeHtml(label)}</div>
          <div class="stat-value">\${escapeHtml(value)}</div>
        </article>
      \`).join("");
    }

    function renderServiceStatus(data) {
      const status = data.service_status;
      const cls = status.running ? "status-good" : "status-bad";
      document.getElementById("serviceStatus").innerHTML = \`
        <div><strong class="\${cls}">\${status.running ? "运行中" : "未运行"}</strong></div>
        <div class="scan-meta">
          <span>PID: \${escapeHtml(status.pid || "-")}</span>
          <span>间隔: \${escapeHtml(status.interval_seconds || data.config.interval_seconds)}s</span>
          <span>Dashboard: \${status.dashboard_url ? \`<a href="\${escapeHtml(status.dashboard_url)}" target="_blank" rel="noreferrer">\${escapeHtml(status.dashboard_url)}</a>\` : "-"}</span>
          <span>上次巡检: \${escapeHtml(fmtTime(status.last_scan_at))}</span>
          <span>上次通知: \${escapeHtml(status.last_scan_notification_count)}</span>
          <span>上次错误: \${escapeHtml(status.last_scan_error_count)}</span>
        </div>
        <pre>\${escapeHtml(JSON.stringify({
          config_path: status.config_path,
          db_path: status.db_path,
          log_path: status.log_path,
          dashboard_host: status.dashboard_host,
          dashboard_port: status.dashboard_port,
          codex_bin: data.config.codex_bin
        }, null, 2))}</pre>
      \`;
    }

    function renderMappings(data) {
      const rows = data.active_mrs || [];
      document.getElementById("mappingCount").textContent = \`\${rows.length} 条活跃记录\`;
      if (!rows.length) {
        document.getElementById("mappings").innerHTML = '<div class="empty">当前没有活跃会话 / MR 映射。</div>';
        return;
      }
      document.getElementById("mappings").innerHTML = \`
        <table>
          <thead>
            <tr>
              <th>会话</th>
              <th>MR</th>
              <th>项目</th>
              <th>分支</th>
              <th>状态</th>
              <th>最近巡检</th>
              <th>最近通知</th>
            </tr>
          </thead>
          <tbody>
            \${rows.map((item) => \`
              <tr>
                <td><code>\${escapeHtml(item.thread_id)}</code></td>
                <td>\${item.mr_url ? \`<a href="\${escapeHtml(item.mr_url)}" target="_blank" rel="noreferrer">!\${escapeHtml(item.mr_id)}</a>\` : \`<code>!\${escapeHtml(item.mr_id)}</code>\`}</td>
                <td>\${escapeHtml(item.project_id || "-")}</td>
                <td><code>\${escapeHtml(item.branch || "-")} -> \${escapeHtml(item.target_branch || "-")}</code></td>
                <td>\${escapeHtml(item.last_status || "-")} / \${escapeHtml(item.last_raw_status || "-")}</td>
                <td>\${escapeHtml(fmtTime(item.last_checked_at))}</td>
                <td>\${escapeHtml(fmtTime(item.last_notified_at))}</td>
              </tr>
            \`).join("")}
          </tbody>
        </table>
      \`;
    }

    function scanNotificationSummary(scan) {
      const notifications = scan.notifications || [];
      if (!notifications.length) return "本轮没有发送消息";
      return notifications.map((item) => {
        const action = item.notified ? "已发送" : item.deferred ? \`已跳过(\${item.reason || "deferred"})\` : (item.reason || "未发送");
        return \`\${item.thread_id || "-"} / !\${item.mr_id || "-"} / \${action}\`;
      }).join("\\n");
    }

    function renderScanHistory(data) {
      const scans = data.recent_scans || [];
      if (!scans.length) {
        document.getElementById("scanHistory").innerHTML = '<div class="empty">还没有巡检记录。</div>';
        return;
      }
      document.getElementById("scanHistory").innerHTML = scans.map((scan) => \`
        <details>
          <summary>#\${escapeHtml(scan.id)} \${escapeHtml(fmtTime(scan.triggered_at))} / \${escapeHtml(scan.trigger_source || "scan")} / 通知 \${escapeHtml(scan.notification_count)} 个会话</summary>
          <div class="scan-meta">
            <span>耗时: \${escapeHtml(scan.duration_ms)}ms</span>
            <span>已扫描: \${escapeHtml(scan.scanned_mr_count)}</span>
            <span>可提交: \${escapeHtml(scan.ready_count)}</span>
            <span>需处理: \${escapeHtml(scan.needs_attention_count)}</span>
            <span>继续观察: \${escapeHtml(scan.still_waiting_count)}</span>
            <span>错误: \${escapeHtml(scan.error_count)}</span>
          </div>
          <pre>\${escapeHtml(scanNotificationSummary(scan))}</pre>
          <pre>\${escapeHtml(JSON.stringify(scan.result, null, 2))}</pre>
        </details>
      \`).join("");
    }

    async function load() {
      const response = await fetch("/api/dashboard", { cache: "no-store" });
      if (!response.ok) {
        throw new Error(\`HTTP \${response.status}\`);
      }
      const data = await response.json();
      document.getElementById("refreshLabel").textContent = \`最近刷新: \${fmtTime(data.generated_at)}\`;
      renderStats(data);
      renderServiceStatus(data);
      renderMappings(data);
      renderScanHistory(data);
    }

    async function refreshLoop() {
      try {
        await load();
      } catch (error) {
        document.getElementById("refreshLabel").textContent = \`刷新失败: \${error.message}\`;
      } finally {
        setTimeout(refreshLoop, REFRESH_MS);
      }
    }

    refreshLoop();
  </script>
</body>
</html>`;
}

function sendJson(response, statusCode, payload) {
  response.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  });
  response.end(`${JSON.stringify(payload, null, 2)}\n`);
}

function startDashboardServer(options = {}) {
  const configPath = normalizePath(options["config-path"], DEFAULT_CONFIG_PATH);
  const dbPath = dbPathFromOptions(options);
  const statusPath = serviceStatusPath(options);
  const config = loadMonitorConfig(configPath);
  const host = dashboardHost(config, options);
  const port = dashboardPort(config, options);
  const server = http.createServer((request, response) => {
    const requestPath = new URL(request.url || "/", "http://127.0.0.1").pathname;
    if (requestPath === "/api/health") {
      sendJson(response, 200, { ok: true, generated_at: nowMs() });
      return;
    }
    if (requestPath === "/api/dashboard") {
      sendJson(response, 200, dashboardData({
        "config-path": configPath,
        "db-path": dbPath,
        "service-status-path": statusPath,
      }));
      return;
    }
    if (requestPath !== "/") {
      response.writeHead(404, { "Content-Type": "text/plain; charset=utf-8" });
      response.end("not found\n");
      return;
    }
    response.writeHead(200, {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store",
    });
    response.end(dashboardHtml());
  });

  return new Promise((resolve, reject) => {
    server.on("error", reject);
    server.listen(port, host, () => {
      const address = server.address();
      const actualPort = address && typeof address === "object" ? address.port : port;
      resolve({
        server,
        host,
        port: actualPort,
        url: dashboardUrl(host, actualPort),
      });
    });
  });
}

function latestNonSystemNote(notes) {
  if (!Array.isArray(notes)) {
    return null;
  }
  for (let index = notes.length - 1; index >= 0; index -= 1) {
    const note = notes[index];
    if (note && note.system !== true) {
      return note;
    }
  }
  return null;
}

function buildFingerprint(bundle) {
  const meta = bundle.meta || {};
  const mr = bundle.merge_request || {};
  return JSON.stringify(
    {
      status: String(bundle.status || ""),
      raw_status: String(bundle.raw_status || ""),
      head_pipeline_status: String(meta.head_pipeline_status || ""),
      pipelines_failed: meta.pipelines_failed ?? null,
      pipelines_pending: meta.pipelines_pending ?? null,
      unresolved_threads: meta.unresolved_threads ?? null,
      latest_non_system_note_id: meta.latest_non_system_note_id ?? null,
      latest_non_system_note_created_at: meta.latest_non_system_note_created_at ?? null,
      latest_non_system_note_updated_at: meta.latest_non_system_note_updated_at ?? null,
      latest_non_system_note_revision_key: meta.latest_non_system_note_revision_key ?? null,
      review_notes_fingerprint: String(meta.review_notes_fingerprint || ""),
      head_sha: String(mr.sha || meta.head_sha || ""),
    },
    Object.keys({
      status: "",
      raw_status: "",
      head_pipeline_status: "",
      pipelines_failed: "",
      pipelines_pending: "",
      unresolved_threads: "",
      latest_non_system_note_id: "",
      latest_non_system_note_created_at: "",
      latest_non_system_note_updated_at: "",
      latest_non_system_note_revision_key: "",
      review_notes_fingerprint: "",
      head_sha: "",
    }).sort(),
  );
}

function fingerprintField(fingerprint, fieldName) {
  if (!fingerprint) {
    return "";
  }
  try {
    const payload = JSON.parse(fingerprint);
    return String(payload[fieldName] || "");
  } catch (_error) {
    return "";
  }
}

function reviewRevisionChanged(entry, bundle) {
  const meta = bundle.meta || {};
  const revisionsTotal = Number(meta.review_note_revisions_total || meta.non_system_notes_total || 0);
  const currentFingerprint = String(meta.review_notes_fingerprint || "");
  if (revisionsTotal <= 0 || !currentFingerprint) {
    return false;
  }
  const previousFingerprint = fingerprintField(entry.lastFingerprint, "review_notes_fingerprint");
  return currentFingerprint !== previousFingerprint;
}

function classifyBundle(bundle, context = {}) {
  const status = String(bundle.status || "");
  const guidance = bundle.workflow_guidance || {};
  const recommendedNextAction = String(guidance.recommended_next_action || "");
  const userFacingState = String(guidance.user_facing_state || "");
  const hasReviewRevisionChange = context.reviewRevisionChanged === true;
  const readyToSubmit =
    !hasReviewRevisionChange && (guidance.review_complete === true || status === "approved");
  const pendingFinding =
    hasReviewRevisionChange ||
    (status === "pending" &&
      (recommendedNextAction === "keep_waiting_in_current_session_and_treat_note_as_pending_finding" ||
        userFacingState === "ci_running_with_pending_finding"));
  const needsAttention =
    status === "changes_requested" ||
    status === "needs_rebase" ||
    pendingFinding;

  return {
    readyToSubmit,
    pendingFinding,
    reviewRevisionChanged: hasReviewRevisionChange,
    needsAttention,
    recommendedNextAction,
    userFacingState,
  };
}

function summaryItem(entry, bundle, classification) {
  return {
    mr_id: entry.mrId,
    mr_url: entry.mrUrl,
    thread_id: entry.threadId,
    branch: entry.branch,
    target_branch: entry.targetBranch,
    project_id: entry.projectId,
    status: String(bundle.status || ""),
    raw_status: String(bundle.raw_status || ""),
    ready_to_submit: classification.readyToSubmit,
    needs_attention: classification.needsAttention,
    review_revision_changed: classification.reviewRevisionChanged,
  };
}

function buildNotificationMessage(entry, bundle, classification) {
  const meta = bundle.meta || {};
  const note = latestNonSystemNote(bundle.notes || []);
  let conclusion = "当前 MR 需要继续处理。";
  if (classification.readyToSubmit) {
    conclusion = "当前 MR 已达到可提交状态，请回到原会话确认后由人工提交。";
  } else if (String(bundle.status || "") === "needs_rebase") {
    conclusion = "当前 MR 需要先 rebase 目标分支，再继续后续 push-code 流程。";
  } else if (classification.reviewRevisionChanged) {
    conclusion = "检测到 reviewer note 内容新增或被编辑，请重新阅读对应 revision 后再判断是否可提交。";
  } else if (classification.pendingFinding) {
    conclusion = "当前 MR 仍在等待检查，但已经出现待处理 reviewer finding，请继续跟进。";
  }

  const lines = [
    "Push-code MR 定时巡检结果：",
    `- 项目: ${entry.projectId || path.basename(process.cwd())}`,
    `- MR: !${entry.mrId}`,
    `- 链接: ${entry.mrUrl || "unknown"}`,
    `- 分支: ${entry.branch || "unknown"} -> ${entry.targetBranch || "unknown"}`,
    `- status: ${String(bundle.status || "unknown")}`,
    `- raw_status: ${String(bundle.raw_status || "unknown")}`,
    `- head_pipeline_status: ${String(meta.head_pipeline_status || "unknown")}`,
    `- pipelines_failed: ${meta.pipelines_failed ?? "unknown"}`,
    `- pipelines_pending: ${meta.pipelines_pending ?? "unknown"}`,
    `- unresolved_threads: ${meta.unresolved_threads ?? "unknown"}`,
  ];

  if (note) {
    lines.push(
      `- 最新非 system note: #${note.id || meta.latest_non_system_note_id || "unknown"} by ${note.author || meta.latest_non_system_note_author || "unknown"}`,
    );
    if (note.updated_at || meta.latest_non_system_note_updated_at) {
      lines.push(`- note_updated_at: ${note.updated_at || meta.latest_non_system_note_updated_at}`);
    }
  }
  if (classification.recommendedNextAction) {
    lines.push(`- recommended_next_action: ${classification.recommendedNextAction}`);
  }
  lines.push("");
  lines.push(conclusion);
  lines.push("请继续原来的 push-code 会话；如果已经可提交，也不要自动 merge，由人工完成提交。");
  return lines.join("\n");
}

function commandInit(options) {
  const configPath = normalizePath(options["config-path"], DEFAULT_CONFIG_PATH);
  const dbPath = dbPathFromOptions(options);
  const legacyDbPath = options["legacy-db-path"]
    ? path.resolve(String(options["legacy-db-path"]))
    : "";
  const legacyStatePath = normalizePath(
    options["legacy-state-path"],
    options["state-path"] || DEFAULT_LEGACY_STATE_PATH,
  );
  const existingConfig = loadMonitorConfig(configPath);
  const config = {
    ...existingConfig,
    enabled: parseBoolean(options.enabled, existingConfig.enabled),
    intervalSeconds: parsePositiveInteger(
      options["interval-seconds"],
      existingConfig.intervalSeconds || 300,
    ),
  };

  const database = openDatabase(dbPath);
  initDatabase(database);
  const legacyDbMigration = maybeMigrateLegacyDatabase(database, legacyDbPath, dbPath);
  const migration = maybeMigrateLegacyState(database, legacyStatePath);
  database.close();
  saveMonitorConfig(configPath, config);

  printJson({
    initialized: true,
    config_path: configPath,
    db_path: dbPath,
    enabled: config.enabled,
    interval_seconds: config.intervalSeconds,
    legacy_db_migration: legacyDbMigration,
    migration,
  });
  return 0;
}

function commandRegistrationUpsert(options) {
  const dbPath = dbPathFromOptions(options);
  const database = openDatabase(dbPath);
  initDatabase(database);
  const mrId = requireOption(options, "mr-id");
  const current = nowMs();
  const existing = database.prepare("SELECT created_at FROM mr_threads WHERE mr_id = ?").get(mrId);
  const entry = {
    mrId,
    threadId: requireOption(options, "thread-id"),
    branch: requireOption(options, "branch"),
    targetBranch: String(options["target-branch"] || ""),
    mrUrl: String(options["mr-url"] || ""),
    projectId: String(options["project-id"] || ""),
    projectRoot: requireOption(options, "project-root"),
    launcherPath: requireOption(options, "launcher-path"),
    active: true,
    lastStatus: "",
    lastRawStatus: "",
    lastHeadSha: "",
    lastNoteId: "",
    lastNoteCreatedAt: "",
    lastFingerprint: "",
    lastNotifiedFingerprint: "",
    lastCheckedAt: 0,
    lastNotifiedAt: 0,
    closedReason: "",
    createdAt: Number(existing?.created_at || current),
    updatedAt: current,
  };

  upsertEntry(database, entry);
  database.close();
  printJson({
    registered: true,
    db_path: dbPath,
    mr_id: mrId,
    thread_id: entry.threadId,
  });
  return 0;
}

function commandThreadRunning(options) {
  printJson(threadRunningState(requireOption(options, "thread-id")));
  return 0;
}

function commandNotifyThread(options) {
  const configPath = normalizePath(options["config-path"], DEFAULT_CONFIG_PATH);
  const config = loadMonitorConfig(configPath);
  let message = String(options.message || "");
  if (!message) {
    const messageFile = requireOption(options, "message-file");
    message = fs.readFileSync(path.resolve(messageFile), "utf8");
  }
  printJson(
    notifyThread(
      requireOption(options, "thread-id"),
      message,
      config,
      String(options.model || ""),
    ),
  );
  return 0;
}

function commandConfigSet(options) {
  const configPath = normalizePath(options["config-path"], DEFAULT_CONFIG_PATH);
  const config = loadMonitorConfig(configPath);
  if (options["codex-bin"] !== undefined) {
    config.codexBin = String(options["codex-bin"] || "");
  }
  if (options["interval-seconds"] !== undefined) {
    config.intervalSeconds = parsePositiveInteger(
      options["interval-seconds"],
      config.intervalSeconds || 300,
    );
  }
  if (options.enabled !== undefined) {
    config.enabled = parseBoolean(options.enabled, config.enabled);
  }
  if (options["dashboard-host"] !== undefined) {
    config.dashboardHost = String(options["dashboard-host"] || "127.0.0.1");
  }
  if (options["dashboard-port"] !== undefined) {
    config.dashboardPort = parsePort(options["dashboard-port"], config.dashboardPort || 4635);
  }
  saveMonitorConfig(configPath, config);
  printJson({
    configured: true,
    config_path: configPath,
    enabled: config.enabled,
    interval_seconds: config.intervalSeconds,
    codex_bin: config.codexBin,
    dashboard_host: config.dashboardHost,
    dashboard_port: config.dashboardPort,
  });
  return 0;
}

function commandServiceStatus(options) {
  const statusPath = serviceStatusPath(options);
  printJson(monitorServiceState(statusPath));
  return 0;
}

function commandDashboardData(options) {
  printJson(dashboardData(options));
  return 0;
}

function commandStart(options) {
  const statusPath = serviceStatusPath(options);
  const current = monitorServiceState(statusPath);
  if (current.running) {
    printJson({
      started: false,
      already_running: true,
      ...current,
    });
    return 0;
  }

  const configPath = normalizePath(options["config-path"], DEFAULT_CONFIG_PATH);
  const dbPath = dbPathFromOptions(options);
  const launcherPath = normalizePath(options["launcher-path"], DEFAULT_LAUNCHER_PATH);
  const config = loadMonitorConfig(configPath);
  const intervalSeconds = parsePositiveInteger(
    options["interval-seconds"],
    config.intervalSeconds || 300,
  );
  const model = String(options.model || "");
  const resolvedDashboardHost = dashboardHost(config, options);
  const resolvedDashboardPort = dashboardPort(config, options);
  const logsDir = path.join(GLOBAL_MONITOR_DIR, "logs");
  fs.mkdirSync(logsDir, { recursive: true });
  const logPath = path.join(logsDir, "service.log");
  const output = fs.openSync(logPath, "a");
  const childArgs = [
    SCRIPT_PATH,
    "service",
    "--config-path",
    configPath,
    "--db-path",
    dbPath,
    "--launcher-path",
    launcherPath,
    "--interval-seconds",
    String(intervalSeconds),
    "--service-status-path",
    statusPath,
    "--dashboard-host",
    resolvedDashboardHost,
    "--dashboard-port",
    String(resolvedDashboardPort),
  ];
  if (options["project-root"] !== undefined) {
    childArgs.push("--project-root", normalizePath(options["project-root"], process.cwd()));
  }
  if (options.notify !== undefined) {
    childArgs.push("--notify", String(options.notify));
  }
  if (model) {
    childArgs.push("--model", model);
  }

  const child = spawn(process.execPath, childArgs, {
    cwd: process.cwd(),
    detached: true,
    stdio: ["ignore", output, output],
    env: {
      ...process.env,
      PUSH_CODE_SQLITE_WARNING_SUPPRESSED: "1",
    },
  });
  child.unref();

  const payload = {
    pid: child.pid,
    startedAt: nowMs(),
    logPath,
    dbPath,
    configPath,
    launcherPath,
    intervalSeconds,
    model,
    dashboardHost: resolvedDashboardHost,
    dashboardPort: resolvedDashboardPort,
    dashboardUrl: dashboardUrl(resolvedDashboardHost, resolvedDashboardPort),
    lastScanAt: 0,
    lastScanNotificationCount: 0,
    lastScanErrorCount: 0,
  };
  saveServiceStatus(statusPath, payload);
  printJson({
    started: true,
    already_running: false,
    service_status_path: statusPath,
    pid: child.pid,
    log_path: logPath,
    db_path: dbPath,
    config_path: configPath,
    launcher_path: launcherPath,
    interval_seconds: intervalSeconds,
    model,
    dashboard_host: resolvedDashboardHost,
    dashboard_port: resolvedDashboardPort,
    dashboard_url: dashboardUrl(resolvedDashboardHost, resolvedDashboardPort),
  });
  return 0;
}

function commandStop(options) {
  const statusPath = serviceStatusPath(options);
  const current = monitorServiceState(statusPath);
  if (!current.running) {
    if (fs.existsSync(statusPath)) {
      fs.unlinkSync(statusPath);
    }
    printJson({
      stopped: false,
      already_stopped: true,
      ...current,
    });
    return 0;
  }

  try {
    process.kill(current.pid, "SIGTERM");
  } catch (error) {
    fail(`停止 monitor 失败: ${error.message}`);
  }
  if (fs.existsSync(statusPath)) {
    fs.unlinkSync(statusPath);
  }
  printJson({
    stopped: true,
    already_stopped: false,
    ...current,
  });
  return 0;
}

async function runScan(options) {
  const triggeredAt = nowMs();
  const configPath = normalizePath(options["config-path"], DEFAULT_CONFIG_PATH);
  const dbPath = dbPathFromOptions(options);
  const notifyEnabled = parseBoolean(options.notify, true);
  const config = loadMonitorConfig(configPath);
  const database = openDatabase(dbPath);
  initDatabase(database);
  const entries = listEntries(database, true);
  const readyToSubmit = [];
  const needsAttention = [];
  const stillWaiting = [];
  const notifications = [];
  const scanErrors = [];

  for (const entry of entries) {
    if (!entry.projectRoot || !entry.launcherPath) {
      database.prepare(`
        UPDATE mr_threads
        SET active = 0, closed_reason = ?, updated_at = ?
        WHERE mr_id = ?
      `).run("missing_monitor_registration_context", nowMs(), entry.mrId);
      scanErrors.push({
        mr_id: entry.mrId,
        thread_id: entry.threadId,
        exit_code: 1,
        stderr: "missing project_root or launcher_path in monitor registration",
        stdout: "",
      });
      continue;
    }
    const projectRoot = resolveEntryProjectRoot(entry, options);
    const launcherPath = resolveEntryLauncherPath(entry, options, projectRoot);
    const statusResult = runJsonCommand(
      launcherPath,
      ["status", "--mr-id", entry.mrId],
      projectRoot,
    );

    if (!statusResult.ok) {
      scanErrors.push({
        mr_id: entry.mrId,
        thread_id: entry.threadId,
        exit_code: statusResult.exitCode,
        stderr: String(statusResult.stderr || "").trim(),
        stdout: String(statusResult.stdout || "").trim(),
      });
      database.prepare(`
        UPDATE mr_threads
        SET updated_at = ?, last_checked_at = ?
        WHERE mr_id = ?
      `).run(nowMs(), nowMs(), entry.mrId);
      continue;
    }

    const bundle = statusResult.value;
    const meta = bundle.meta || {};
    const mr = bundle.merge_request || {};
    const fingerprint = buildFingerprint(bundle);
    const classification = classifyBundle(bundle, {
      reviewRevisionChanged: reviewRevisionChanged(entry, bundle),
    });
    const item = summaryItem(entry, bundle, classification);

    if (classification.readyToSubmit) {
      readyToSubmit.push(item);
    } else if (classification.needsAttention) {
      needsAttention.push(item);
    } else {
      stillWaiting.push(item);
    }

    database.prepare(`
      UPDATE mr_threads
      SET
        last_status = ?,
        last_raw_status = ?,
        last_head_sha = ?,
        last_note_id = ?,
        last_note_created_at = ?,
        last_fingerprint = ?,
        last_checked_at = ?,
        updated_at = ?
      WHERE mr_id = ?
    `).run(
      String(bundle.status || ""),
      String(bundle.raw_status || ""),
      String(mr.sha || ""),
      String(meta.latest_non_system_note_id || ""),
      String(meta.latest_non_system_note_created_at || ""),
      fingerprint,
      nowMs(),
      nowMs(),
      entry.mrId,
    );

    const shouldNotify =
      notifyEnabled &&
      entry.threadId &&
      fingerprint !== entry.lastNotifiedFingerprint &&
      (classification.readyToSubmit || classification.needsAttention);

    if (!shouldNotify) {
      continue;
    }

    const notification = notifyThread(
      entry.threadId,
      buildNotificationMessage(entry, bundle, classification),
      config,
      String(options.model || ""),
    );
    if (notification.notified) {
      database.prepare(`
        UPDATE mr_threads
        SET last_notified_fingerprint = ?, last_notified_at = ?, updated_at = ?
        WHERE mr_id = ?
      `).run(fingerprint, nowMs(), nowMs(), entry.mrId);
    }
    notifications.push({
      mr_id: entry.mrId,
      thread_id: entry.threadId,
      status: item.status,
      raw_status: item.raw_status,
      notified: notification.notified,
      deferred: notification.deferred,
      reason: notification.reason || "",
      log_path: notification.log_path || "",
    });
  }

  const result = {
    trigger_source: String(options["trigger-source"] || "scan"),
    triggered_at: triggeredAt,
    completed_at: nowMs(),
    duration_ms: 0,
    project_root: normalizePath(options["project-root"], process.cwd()),
    db_path: dbPath,
    config_path: configPath,
    scanned_mrs: [...readyToSubmit, ...needsAttention, ...stillWaiting],
    ready_to_submit: readyToSubmit,
    needs_attention: needsAttention,
    still_waiting: stillWaiting,
    notifications,
    scan_errors: scanErrors,
  };
  result.duration_ms = Math.max(0, result.completed_at - triggeredAt);
  recordScanRun(database, result);
  database.close();
  return result;
}

async function commandScan(options) {
  printJson(await runScan(options));
  return 0;
}

function sleep(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function updateServiceStatusFile(statusPath, patch) {
  const current = loadServiceStatus(statusPath);
  saveServiceStatus(statusPath, {
    ...current,
    ...patch,
  });
}

async function commandRunLoop(options) {
  const configPath = normalizePath(options["config-path"], DEFAULT_CONFIG_PATH);
  const config = loadMonitorConfig(configPath);
  const intervalSeconds = parsePositiveInteger(
    options["interval-seconds"],
    config.intervalSeconds || 300,
  );

  for (;;) {
    const result = await runScan({
      ...options,
      "trigger-source": String(options["trigger-source"] || "run-loop"),
    });
    printJson(result);
    await sleep(intervalSeconds * 1000);
  }
}

async function commandService(options) {
  const statusPath = serviceStatusPath(options);
  const configPath = normalizePath(options["config-path"], DEFAULT_CONFIG_PATH);
  const dbPath = dbPathFromOptions(options);
  const config = loadMonitorConfig(configPath);
  const intervalSeconds = parsePositiveInteger(
    options["interval-seconds"],
    config.intervalSeconds || 300,
  );
  const launcherPath = normalizePath(options["launcher-path"], DEFAULT_LAUNCHER_PATH);
  const model = String(options.model || "");
  const dashboard = await startDashboardServer(options);
  let shouldStop = false;

  updateServiceStatusFile(statusPath, {
    pid: process.pid,
    startedAt: nowMs(),
    dbPath,
    configPath,
    launcherPath,
    intervalSeconds,
    model,
    dashboardHost: dashboard.host,
    dashboardPort: dashboard.port,
    dashboardUrl: dashboard.url,
  });

  const shutdown = () => {
    shouldStop = true;
    dashboard.server.close(() => {
      if (fs.existsSync(statusPath)) {
        fs.unlinkSync(statusPath);
      }
      process.exit(0);
    });
    setTimeout(() => {
      process.exit(0);
    }, 2000).unref();
  };

  process.on("SIGTERM", shutdown);
  process.on("SIGINT", shutdown);

  for (;;) {
    if (shouldStop) {
      return 0;
    }
    const result = await runScan({
      ...options,
      "trigger-source": "service",
      "config-path": configPath,
      "db-path": dbPath,
    });
    printJson(result);
    updateServiceStatusFile(statusPath, {
      lastScanAt: result.completed_at,
      lastScanNotificationCount: Array.isArray(result.notifications) ? result.notifications.length : 0,
      lastScanErrorCount: Array.isArray(result.scan_errors) ? result.scan_errors.length : 0,
      dashboardHost: dashboard.host,
      dashboardPort: dashboard.port,
      dashboardUrl: dashboard.url,
    });
    await sleep(intervalSeconds * 1000);
  }
}

async function main() {
  const { command, options } = parseArgs(process.argv.slice(2));
  switch (command) {
    case "init":
      return commandInit(options);
    case "start":
      return commandStart(options);
    case "stop":
      return commandStop(options);
    case "status":
      return commandServiceStatus(options);
    case "dashboard-data":
      return commandDashboardData(options);
    case "registration-upsert":
      return commandRegistrationUpsert(options);
    case "thread-running":
      return commandThreadRunning(options);
    case "notify-thread":
      return commandNotifyThread(options);
    case "config-set":
      return commandConfigSet(options);
    case "scan":
      return commandScan(options);
    case "service":
      return commandService(options);
    case "run-loop":
      return commandRunLoop(options);
    default:
      fail(`未知子命令: ${command}`);
  }
}

main().catch((error) => {
  fail(error && error.message ? error.message : String(error));
});
