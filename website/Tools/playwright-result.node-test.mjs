// Run with node --test, separately from the website's Vitest suites.
import assert from 'node:assert/strict'
import test from 'node:test'
import { parsePlaywrightResult } from './playwright-result.mjs'

test('parses LF-delimited result', () => {
  assert.deepEqual(parsePlaywrightResult('prefix\n### Result\n{"status":"passed"}\n### Ran Playwright code\nsuffix'), { status: 'passed' })
})

test('parses CRLF output and whitespace after heading', () => {
  assert.deepEqual(parsePlaywrightResult('### Result \t\r\n {"status":"passed"}\r\n### Ran Playwright code'), { status: 'passed' })
})

test('accepts whitespace-only heading lines', () => {
  assert.deepEqual(parsePlaywrightResult('### Result\t \n\t\n{"checks":7}\n### Ran Playwright code'), { checks: 7 })
})

test('returns undefined when either delimiter is missing', () => {
  assert.equal(parsePlaywrightResult('{"status":"passed"}'), undefined)
  assert.equal(parsePlaywrightResult('### Result\n{"status":"passed"}'), undefined)
  assert.equal(parsePlaywrightResult('### Result without newline\n{"status":"passed"}\n### Ran Playwright code'), undefined)
})

test('skips a malformed heading-like string before the actual result', () => {
  const output = 'prefix ### Result not a header\n### Result\r\n{"status":"passed"}\r\n### Ran Playwright code'
  assert.deepEqual(parsePlaywrightResult(output), { status: 'passed' })
})

test('rejects invalid JSON in a delimited result', () => {
  assert.throws(
    () => parsePlaywrightResult('### Result\n{invalid}\n### Ran Playwright code'),
    SyntaxError,
  )
})

test('rejects empty or whitespace-only JSON instead of reporting missing delimiters', () => {
  for (const payload of ['', ' \t', '\n\r\n']) {
    assert.throws(() => parsePlaywrightResult(`### Result\n${payload}\n### Ran Playwright code`), SyntaxError)
  }
})
