export interface AnsiRun {
  text: string
  color?: string
  backgroundColor?: string
  fontWeight?: number
  opacity?: number
}

/** Render text and the CLI's limited SGR palette, never HTML or terminal commands. */
export function ansiRuns(input: string): AnsiRun[] {
  const runs: AnsiRun[] = []
  let style: Omit<AnsiRun, 'text'> = {}
  for (const part of input.split(/(\x1b\[[0-9;?]*[A-Za-z])/)) {
    if (part.startsWith('\x1b[')) {
      if (!part.endsWith('m')) continue
      const codes = part.slice(2, -1).split(';').map(Number)
      for (let index = 0; index < codes.length; index++) {
        const code = codes[index]
        if (code === 0) style = {}
        else if (code === 1) style = { ...style, fontWeight: 700 }
        else if (code === 2) style = { ...style, opacity: 0.72 }
        else if (code === 22) style = { ...style, fontWeight: undefined, opacity: undefined }
        else if (code === 39) style = { ...style, color: undefined }
        else if (code === 49) style = { ...style, backgroundColor: undefined }
        else if ((code === 38 || code === 48) && codes[index + 1] === 2) {
          const rgb = codes.slice(index + 2, index + 5)
          if (rgb.length === 3 && rgb.every(value => Number.isInteger(value) && value >= 0 && value <= 255)) {
            style = { ...style, [code === 38 ? 'color' : 'backgroundColor']: `rgb(${rgb.join(', ')})` }
          }
          index += 4
        }
      }
    } else if (part) {
      runs.push({ ...style, text: part.replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, '') })
    }
  }
  return runs
}

export function plainAnsi(input: string): string {
  return ansiRuns(input).map(run => run.text).join('')
}
