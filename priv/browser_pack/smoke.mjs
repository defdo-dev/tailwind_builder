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

// The pack bundles only the plugins it was built with, so the harness must ask
// for exactly those. Importing a stylesheet the pack does not carry is the
// error case this same harness asserts on below — a fixed theme source turned
// every partial build (e.g. a daisyui-only release) into a false failure.
const pluginKeys = new Set((pack.pluginSet ?? []).map((plugin) => plugin.plugin_key))

const imports = ['@import "tailwindcss";']
// A core utility, so there is always something to assert on even with no plugins.
const candidates = ["underline"]

if (pluginKeys.has("tw_animate_css")) {
  imports.push('@import "tw-animate-css";')
  candidates.push("animate-in", "fade-in", "slide-in-from-top")
}

if (pluginKeys.has("tailwind_animations")) {
  imports.push('@import "tailwind-animations";')
  candidates.push("animate-fade-in")
}

if (pluginKeys.has("daisyui_v5")) {
  imports.push('@plugin "daisyui";')
  candidates.push("btn", "btn-primary")
}

const themeSource = imports.join(" ")

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
