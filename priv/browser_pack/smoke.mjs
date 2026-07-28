// BrowserPack smoke harness — runs the pack under node, no DOM, no fetch.
// Usage: node smoke.mjs <path-to-tailwind-browser-pack.mjs>
// Prints the produced CSS on stdout; exits non-zero on any failure.

import { pathToFileURL } from "node:url"
import { writeFileSync } from "node:fs"
import { resolve } from "node:path"

const packPath = process.argv[2]

if (!packPath) {
  console.error("usage: node smoke.mjs <path-to-tailwind-browser-pack.mjs>")
  process.exit(2)
}

const { default: pack } = await import(pathToFileURL(resolve(packPath)).href)

if (pack.contract !== 1) {
  console.error(`unexpected pack contract: ${pack.contract}`)
  process.exit(2)
}

const themeSource =
  '@import "tailwindcss"; @import "tw-animate-css"; @import "tailwind-animations"; @plugin "daisyui";'
const candidates = [
  "btn",
  "btn-primary",
  "animate-fade-in",
  "animate-in",
  "fade-in",
  "slide-in-from-top",
]

const compiler = await pack.createCompiler(themeSource)
const css = compiler.build(candidates)

// An unknown @import id must throw naming the id and the bundled set.
let unknownThrew = false

try {
  const bad = await pack.createCompiler('@import "tailwindcss"; @import "not-bundled/pkg";')
  bad.build(["btn"])
} catch (error) {
  unknownThrew =
    error.message.includes("not-bundled/pkg") && error.message.includes("only bundles")
}

if (!unknownThrew) {
  console.error("pack did not throw a naming error for an unknown stylesheet id")
  process.exit(3)
}

writeFileSync(1, css)
