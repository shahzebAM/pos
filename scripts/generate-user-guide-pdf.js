import { readFileSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { jsPDF } from 'jspdf'

const __dirname = dirname(fileURLToPath(import.meta.url))
const rootDir = resolve(__dirname, '..')
const sourcePath = resolve(rootDir, 'docs', 'complete-user-guide.md')
const outputPath = resolve(rootDir, 'docs', 'Multi-Branch-POS-Complete-User-Guide.pdf')

const markdown = readFileSync(sourcePath, 'utf8')
const doc = new jsPDF({ unit: 'pt', format: 'a4' })

const page = {
  width: doc.internal.pageSize.getWidth(),
  height: doc.internal.pageSize.getHeight(),
  marginX: 46,
  marginTop: 54,
  marginBottom: 58,
}

let y = page.marginTop
let firstHeading = true

function setText(color = '#23332d') {
  doc.setTextColor(color)
}

function ensureSpace(height = 18) {
  if (y + height > page.height - page.marginBottom) {
    doc.addPage()
    y = page.marginTop
  }
}

function addWrappedText(text, options = {}) {
  const {
    size = 10.5,
    style = 'normal',
    color = '#23332d',
    indent = 0,
    gap = 5,
    lineHeight = 14,
    align = 'left',
    maxWidth = page.width - page.marginX * 2 - indent,
  } = options

  doc.setFont('helvetica', style)
  doc.setFontSize(size)
  setText(color)

  const lines = doc.splitTextToSize(text, maxWidth)
  ensureSpace(lines.length * lineHeight + gap)
  const x = align === 'center' ? page.width / 2 : page.marginX + indent
  doc.text(lines, x, y, { align })
  y += lines.length * lineHeight + gap
}

function addSectionHeading(text) {
  if (!firstHeading) {
    y += 8
    ensureSpace(86)
  }
  firstHeading = false

  doc.setFillColor('#e8f5ef')
  doc.roundedRect(page.marginX - 10, y - 20, page.width - page.marginX * 2 + 20, 36, 7, 7, 'F')
  addWrappedText(text, {
    size: 14,
    style: 'bold',
    color: '#0b5f4c',
    lineHeight: 16,
    gap: 12,
  })
}

function addTitle(text) {
  y = 118
  doc.setFillColor('#0f8f6f')
  doc.rect(0, 0, page.width, 170, 'F')
  addWrappedText(text, {
    size: 26,
    style: 'bold',
    color: '#ffffff',
    align: 'center',
    lineHeight: 30,
    gap: 16,
    maxWidth: page.width - 100,
  })
  addWrappedText('Complete operating guide for admins, managers, cashiers, auditors, and inventory staff.', {
    size: 12,
    color: '#eefaf5',
    align: 'center',
    lineHeight: 16,
    gap: 24,
    maxWidth: page.width - 140,
  })
  y = 210
}

function addFooter() {
  const totalPages = doc.internal.getNumberOfPages()
  for (let pageNumber = 1; pageNumber <= totalPages; pageNumber += 1) {
    doc.setPage(pageNumber)
    doc.setDrawColor('#c9ddd5')
    doc.line(page.marginX, page.height - 38, page.width - page.marginX, page.height - 38)
    doc.setFont('helvetica', 'normal')
    doc.setFontSize(8)
    doc.setTextColor('#5d736a')
    doc.text('Multi-Branch POS Complete User Guide', page.marginX, page.height - 22)
    doc.text(`Page ${pageNumber} of ${totalPages}`, page.width - page.marginX, page.height - 22, { align: 'right' })
  }
}

function renderLine(rawLine) {
  const line = rawLine.trimEnd()

  if (!line.trim()) {
    y += 6
    return
  }

  if (line.startsWith('# ')) {
    addTitle(line.replace(/^# /, ''))
    return
  }

  if (line.startsWith('## ')) {
    addSectionHeading(line.replace(/^## /, ''))
    return
  }

  if (line.startsWith('### ')) {
    ensureSpace(30)
    addWrappedText(line.replace(/^### /, ''), {
      size: 13,
      style: 'bold',
      color: '#0b5f4c',
      lineHeight: 16,
      gap: 8,
    })
    return
  }

  if (/^\d+\.\s/.test(line)) {
    addWrappedText(line, {
      size: 10,
      indent: 16,
      lineHeight: 13.5,
      gap: 4,
    })
    return
  }

  if (line.startsWith('- ')) {
    addWrappedText(`- ${line.slice(2)}`, {
      size: 10,
      indent: 18,
      lineHeight: 13.5,
      gap: 3,
    })
    return
  }

  if (line.endsWith(':')) {
    ensureSpace(20)
    addWrappedText(line, {
      size: 10.5,
      style: 'bold',
      color: '#173d33',
      lineHeight: 14,
      gap: 5,
    })
    return
  }

  addWrappedText(line)
}

markdown.split(/\r?\n/).forEach(renderLine)
addFooter()

writeFileSync(outputPath, Buffer.from(doc.output('arraybuffer')))
console.log(`Generated ${outputPath}`)
