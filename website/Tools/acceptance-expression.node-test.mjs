// Run with node --test, separately from the website's Vitest suites.
import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'
import test from 'node:test'
import vm from 'node:vm'
import { fileURLToPath } from 'node:url'

const toolsDirectory = path.dirname(fileURLToPath(import.meta.url))
const payloads = [
  'browser-acceptance.js', 'native-parity-acceptance.js', 'navigation-regression.js',
  'privacy-permalink-acceptance.js', 'public-contact-acceptance.js',
  'route-acceptance.js', 'support-acceptance.js', 'watch-acceptance.js',
]

for (const filename of payloads) {
  test(`${filename} evaluates as a single async page function`, () => {
    const code = fs.readFileSync(path.join(toolsDirectory, filename), 'utf8')
    // Fixed repository test inputs only. Construct the function, never invoke it.
    const evaluated = vm.runInNewContext(`(${code})`, {}, {
      timeout: 1000, codeGeneration: { strings: false, wasm: false },
    })
    assert.equal(typeof evaluated, 'function')
    assert.equal(evaluated.constructor.name, 'AsyncFunction')
  })
}

async function nativeHelpers(page) {
  const code = fs.readFileSync(path.join(toolsDirectory, 'native-parity-acceptance.js'), 'utf8')
  const boundary = '  const manifest = __NATIVE_MANIFEST__'
  assert.equal(code.split(boundary).length, 2)
  // Expose only these helpers before setup. No browser or payload journey is run.
  const instrumented = code.replace(boundary,
    '  return { verifyNativeTourPickers, verifyNativeResponsiveLayouts, verifyNativeTerminalResponsive };\n' + boundary)
  const factory = vm.runInNewContext(`(${instrumented})`, {}, {
    timeout: 1000, codeGeneration: { strings: false, wasm: false },
  })
  return factory(page)
}

test('native picker uses the supplied try-local tab rather than a free binding', async () => {
  const reached = new Error('supplied tab reached')
  const helpers = await nativeHelpers({})
  await assert.rejects(helpers.verifyNativeTourPickers({
    macTab: { click: async () => { throw reached } }, mac: {}, phoneTab: {}, phone: {},
  }), error => error === reached)
})

test('native responsive helpers receive their try-local page controls', async () => {
  const reached = new Error('supplied control reached')
  const viewports = []
  const helpers = await nativeHelpers({ setViewportSize: async size => { viewports.push(size.width) } })
  const context = {
    macTab: { click: async () => { throw reached } }, mac: {}, phoneTab: {}, phone: {},
    terminalTab: {}, terminal: {}, dashboard: {}, screen: {},
    input: { fill: async () => { throw reached } },
  }
  await assert.rejects(helpers.verifyNativeResponsiveLayouts(context), error => error === reached)
  assert.deepEqual(viewports, [1440])
  await assert.rejects(helpers.verifyNativeTerminalResponsive(375, context), error => error === reached)
})
