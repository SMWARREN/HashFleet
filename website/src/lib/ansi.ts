export interface AnsiRun {
  text: string
  color?: string
  backgroundColor?: string
  fontWeight?: number
  opacity?: number
}

type AnsiStyle = Omit<AnsiRun, 'text'>

function basicStyle(style: AnsiStyle, code: number): AnsiStyle {
  switch (code) {
    case 0: return {}
    case 1: return { ...style, fontWeight: 700 }
    case 2: return { ...style, opacity: 0.72 }
    case 22: return { ...style, fontWeight: undefined, opacity: undefined }
    case 39: return { ...style, color: undefined }
    case 49: return { ...style, backgroundColor: undefined }
    default: return style
  }
}

function sgrStyle(initial: AnsiStyle, codes: number[]): AnsiStyle {
  let style = initial
  for (let index = 0; index < codes.length; index++) {
    const code = codes[index]
    if ((code === 38 || code === 48) && codes[index + 1] === 2) {
      const rgb = codes.slice(index + 2, index + 5)
      if (rgb.length === 3 && rgb.every(value => Number.isInteger(value) && value >= 0 && value <= 255)) {
        style = { ...style, [code === 38 ? 'color' : 'backgroundColor']: `rgb(${rgb.join(', ')})` }
      }
      index += 4
    } else {
      style = basicStyle(style, code)
    }
  }
  return style
}

/** Render text and the CLI's limited SGR palette, never HTML or terminal commands. */
export function ansiRuns(input: string): AnsiRun[] {
  const runs: AnsiRun[] = []
  let style: AnsiStyle = {}
  for (const part of input.split(/(\x1b\[[0-9;?]*[A-Za-z])/)) {
    if (part.startsWith('\x1b[')) {
      if (!part.endsWith('m')) continue
      style = sgrStyle(style, part.slice(2, -1).split(';').map(Number))
    } else if (part) {
      runs.push({ ...style, text: part.replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, '') })
    }
  }
  return runs
}

export function plainAnsi(input: string): string {
  return ansiRuns(input).map(run => run.text).join('')
}
