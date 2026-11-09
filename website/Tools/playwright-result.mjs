const RESULT_HEADING = '### Result'
const RESULT_END = '\n### Ran Playwright code'

/** Parse the JSON result block emitted by the Playwright CLI, or return undefined if delimiters are absent. */
export function parsePlaywrightResult(output) {
  let searchFrom = 0
  while (searchFrom < output.length) {
    const headingIndex = output.indexOf(RESULT_HEADING, searchFrom)
    if (headingIndex < 0) return undefined

    let cursor = headingIndex + RESULT_HEADING.length
    let headingNewline = -1
    while (cursor < output.length && /\s/.test(output[cursor])) {
      if (output[cursor] === '\n') {
        headingNewline = cursor
        break
      }
      cursor += 1
    }
    if (headingNewline >= 0) {
      const jsonStart = headingNewline + 1
      const resultEnd = output.indexOf(RESULT_END, jsonStart)
      if (resultEnd >= 0) return JSON.parse(output.slice(jsonStart, resultEnd).trim())
    }
    searchFrom = headingIndex + RESULT_HEADING.length
  }
  return undefined
}
