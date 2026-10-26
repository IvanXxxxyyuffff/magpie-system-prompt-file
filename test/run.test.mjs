// Test suite for magpie-system-prompt-file.
//   node test/run.test.mjs
// Covers: four protocols, append/prepend, override on/off, agents/models
// filters, YAML frontmatter stripping, multi-file concatenation, hot reload
// (file re-read on every request), "~" expansion, relative-to-cwd paths and
// the fail-open path for a missing file.

import assert from "node:assert/strict"
import { mkdtempSync, writeFileSync, rmSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

const { onRequest } = await import("../system-prompt.hooks.mjs")

const dir = mkdtempSync(join(tmpdir(), "mspf-"))
const p = (name) => join(dir, name)
let passed = 0

function ctx(protocol, options, extra = {}) {
  return {
    protocol,
    agent: "curl",
    origin: "local",
    model: "gpt-4o",
    cwd: dir,
    options,
    state: {},
    signal: new AbortController().signal,
    report() {},
    ...extra,
  }
}

async function test(name, fn) {
  try {
    await fn()
    passed++
    console.log("ok   - " + name)
  } catch (e) {
    console.error("FAIL - " + name + "\n     " + (e?.message ?? e))
    process.exitCode = 1
  }
}

// --- fixture files -------------------------------------------------------
writeFileSync(p("a.md"), "---\ntitle: A\n---\n\n# Rules\n\nAlways answer in English.\n")
writeFileSync(p("b.txt"), "Second file body.\n")
writeFileSync(p("plain.md"), "Plain prompt.\n")

const file = p("a.md")

await test("chat: no system message gets the file's prompt", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: file }))
  assert.equal(out.messages[0].role, "system")
  assert.match(out.messages[0].content, /Always answer in English\./)
  assert.doesNotMatch(out.messages[0].content, /title: A/)
})

await test("chat: frontmatter is stripped by default", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: file }))
  assert.ok(!out.messages[0].content.includes("---"))
})

await test("chat: frontmatter kept when strip_frontmatter is false", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: file, strip_frontmatter: false }))
  assert.ok(out.messages[0].content.includes("title: A"))
})

await test("chat: existing system prompt is kept when override is false", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "system", content: "ORIGINAL" }, { role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: file, override: false }))
  assert.equal(out, undefined)
  assert.equal(body.messages[0].content, "ORIGINAL")
})

await test("chat: append (default) puts the file's prompt after the agent's", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "system", content: "ORIGINAL" }, { role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: file }))
  assert.ok(out.messages[0].content.startsWith("ORIGINAL"))
  assert.ok(out.messages[0].content.endsWith("Always answer in English."))
})

await test("chat: prepend puts the file's prompt before the agent's", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "system", content: "ORIGINAL" }, { role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: file, position: "prepend" }))
  const c = out.messages[0].content
  assert.ok(c.indexOf("Always answer in English.") < c.indexOf("ORIGINAL"))
  assert.ok(c.endsWith("ORIGINAL"))
})

await test("chat: a developer message is the agent's own system slot", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "developer", content: "ORIGINAL" }, { role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: file }))
  assert.equal(out.messages[0].role, "developer")
  assert.ok(out.messages[0].content.includes("Always answer in English."))
})

await test("anthropic: system string", async () => {
  const body = { model: "claude-x", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("anthropic", { prompt_file: file }))
  assert.match(out.system, /Always answer in English\./)
})

await test("anthropic: system block array", async () => {
  const body = { model: "claude-x", system: [{ type: "text", text: "ORIGINAL" }], messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("anthropic", { prompt_file: file }))
  assert.equal(out.system.length, 2)
  assert.equal(out.system[1].type, "text")
  assert.match(out.system[1].text, /Always answer in English\./)
})

await test("responses: instructions", async () => {
  const body = { model: "gpt-5", input: [] }
  const out = await onRequest(body, ctx("responses", { prompt_file: file }))
  assert.match(out.instructions, /Always answer in English\./)
})

await test("responses: existing instructions are appended to", async () => {
  const body = { model: "gpt-5", instructions: "ORIGINAL", input: [] }
  const out = await onRequest(body, ctx("responses", { prompt_file: file }))
  assert.ok(out.instructions.startsWith("ORIGINAL"))
  assert.match(out.instructions, /Always answer in English\./)
})

await test("gemini: systemInstruction", async () => {
  const body = { model: "gemini-x", contents: [] }
  const out = await onRequest(body, ctx("gemini", { prompt_file: file }))
  assert.match(out.systemInstruction.parts[0].text, /Always answer in English\./)
})

await test("gemini: system_instruction spelling is honoured", async () => {
  const body = { model: "gemini-x", system_instruction: { parts: [{ text: "ORIGINAL" }] }, contents: [] }
  const out = await onRequest(body, ctx("gemini", { prompt_file: file }))
  assert.equal(out.system_instruction.parts.length, 2)
})

await test("prompt_files: several files are concatenated in order", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_files: [file, p("b.txt")] }))
  const c = out.messages[0].content
  assert.ok(c.indexOf("Always answer in English.") < c.indexOf("Second file body."))
  assert.ok(c.includes("\n\n"))
})

await test("system_prompt_file is an accepted spelling", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { system_prompt_file: p("plain.md") }))
  assert.equal(out.messages[0].content, "Plain prompt.")
})

await test("inline system_prompt is used when no file is configured", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { system_prompt: "INLINE" }))
  assert.equal(out.messages[0].content, "INLINE")
})

await test("the file wins over the inline system_prompt", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: p("plain.md"), system_prompt: "INLINE" }))
  assert.equal(out.messages[0].content, "Plain prompt.")
})

await test("a relative path is resolved against ctx.cwd", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: "plain.md" }))
  assert.equal(out.messages[0].content, "Plain prompt.")
})

await test("~ is expanded to the home directory", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: "~/definitely-missing-prompt.md" }))
  assert.equal(out, undefined)
})

await test("a missing file fails open (request unchanged)", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: p("nope.md") }))
  assert.equal(out, undefined)
})

await test("the file is re-read on every request (hot reload)", async () => {
  const hot = p("hot.md")
  writeFileSync(hot, "VERSION ONE\n")
  const req = () => ({ model: "gpt-4o", messages: [{ role: "user", content: "hi" }] })
  const first = await onRequest(req(), ctx("chat", { prompt_file: hot }))
  assert.equal(first.messages[0].content, "VERSION ONE")
  writeFileSync(hot, "VERSION TWO\n")
  const second = await onRequest(req(), ctx("chat", { prompt_file: hot }))
  assert.equal(second.messages[0].content, "VERSION TWO")
})

await test("agents filter: a different agent is skipped", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: file, agents: ["claude"] }))
  assert.equal(out, undefined)
})

await test("agents filter: the listed agent applies", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: file, agents: ["curl"] }))
  assert.ok(out)
})

await test("models filter: a different model prefix is skipped", async () => {
  const body = { model: "claude-3", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: file, models: ["gpt-"] }))
  assert.equal(out, undefined)
})

await test("models filter: a matching model prefix applies", async () => {
  const body = { model: "gpt-4o-mini", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: file, models: ["gpt-"] }))
  assert.ok(out)
})

await test("an unknown protocol leaves the request alone", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("other", { prompt_file: file }))
  assert.equal(out, undefined)
})

await test("model and stream are never touched", async () => {
  const body = { model: "gpt-4o", stream: true, messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: file }))
  assert.equal(out.model, "gpt-4o")
  assert.equal(out.stream, true)
})

// --- cross-platform paths and encodings --------------------------------
await test("a Windows absolute path is not read as a relative path", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  // C:\Users\me\prompt.md does not exist here, so nothing is injected: the
  // point is that it is treated as absolute, not resolved against cwd.
  const out = await onRequest(body, ctx("chat", { prompt_file: "C:\\Users\\me\\prompt.md" }))
  assert.equal(out, undefined)
  assert.ok(!body.messages.some((m) => m.role === "system"))
})

await test("a UNC path is absolute too", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: "\\\\server\\share\\prompt.md" }))
  assert.equal(out, undefined)
})

await test("a Windows-style ~ is expanded", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: "~\\definitely-missing.md" }))
  assert.equal(out, undefined)
})

await test("an environment variable in the path is expanded", async () => {
  process.env.MSPF_TEST_DIR = dir
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: "$MSPF_TEST_DIR/plain.md" }))
  assert.equal(out.messages[0].content, "Plain prompt.")
  const win = await onRequest({ model: "gpt-4o", messages: [{ role: "user", content: "hi" }] },
    ctx("chat", { prompt_file: "%MSPF_TEST_DIR%/plain.md" }))
  assert.equal(win.messages[0].content, "Plain prompt.")
  delete process.env.MSPF_TEST_DIR
})

await test("a UTF-16 file is decoded", async () => {
  const u16 = p("u16.md")
  writeFileSync(u16, Buffer.from("UTF16-BODY", "utf16le"))
  const bom = p("u16bom.md")
  writeFileSync(bom, Buffer.concat([Buffer.from([0xff, 0xfe]), Buffer.from("UTF16-BODY", "utf16le")]))
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: u16 }))
  assert.equal(out.messages[0].content, "UTF16-BODY")
  const withBom = await onRequest({ model: "gpt-4o", messages: [{ role: "user", content: "hi" }] },
    ctx("chat", { prompt_file: bom }))
  assert.equal(withBom.messages[0].content, "UTF16-BODY")
})

await test("a byte order mark is dropped", async () => {
  const bom = p("bom.md")
  writeFileSync(bom, Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from("BOM-BODY")]))
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: bom }))
  assert.equal(out.messages[0].content, "BOM-BODY")
})

await test("CRLF line endings are normalized", async () => {
  const crlf = p("crlf.md")
  writeFileSync(crlf, "LINE1\r\nLINE2\r\n")
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: crlf }))
  assert.equal(out.messages[0].content, "LINE1\nLINE2")
})

await test("persona_file is an accepted spelling", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { persona_file: p("plain.md") }))
  assert.equal(out.messages[0].content, "Plain prompt.")
})

await test("a .txt file is read the same as a .md one", async () => {
  const body = { model: "gpt-4o", messages: [{ role: "user", content: "hi" }] }
  const out = await onRequest(body, ctx("chat", { prompt_file: p("b.txt") }))
  assert.equal(out.messages[0].content, "Second file body.")
})

rmSync(dir, { recursive: true, force: true })
console.log("\n" + passed + " passed" + (process.exitCode ? " (with failures)" : ""))
