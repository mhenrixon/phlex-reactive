// Micro-bench: #extractToken — the regex pass that reads THIS controller's next
// signed token out of the turbo-stream response body after every action (issue
// #46). It runs on the client hot path once per round trip; on a large
// collection response it scans the whole body. Driven through the PUBLIC
// dispatch() with a stubbed fetch, mirroring reactive_extract_token.test.js.
//
// Two bodies bracket the real range:
//   - ~2KB: a single-component self replace (the common counter/toggle case).
//   - ~500KB: a 200-row reactive collection (prepended row token first, the
//     container's reactive:token last) — the worst realistic scan.
// A DOMParser-equivalent parse of the SAME html is benched as the CEILING: what
// it would cost to parse the body into a document instead of regex-scanning it.
// (extractToken's regex numbers are engine-faithful under bun/JSC; the parse
// comparison shows why a full parse was never the right tool for token lookup.)

import { bench, group } from "mitata"
import { fakeRoot, stubExtractEnv, stubFetchReturning, buildController, dispatchOnce } from "./support/harness.js"

// A single self-replace body (~2KB once padded with realistic markup).
function smallBody() {
  const filler = "<span class='cell'>x</span>".repeat(60) // ~1.6KB of realistic content
  return (
    `<turbo-stream action="replace" target="counter">` +
    `<template><div id="counter" data-controller="reactive" data-reactive-token-value="SELF-FRESH">${filler}</div></template>` +
    `</turbo-stream>`
  )
}

// A 200-row reactive collection add response (~500KB): each row is a reactive
// root carrying its own token FIRST, the container's reactive:token LAST — the
// exact shape extractToken must skip past to find OUR (container) token.
function largeBody(rows = 200) {
  const container = "reactive-rows"
  let html = `<turbo-stream action="prepend" target="${container}">`
  for (let i = 0; i < rows; i++) {
    html +=
      `<template><li id="row_${i}" data-controller="reactive" data-reactive-token-value="ROW-TOKEN-${i}">` +
      `<span class='title'>Row ${i}</span>` +
      `<span class='meta'>${"detail ".repeat(20)}</span>` +
      `</li></template>`
  }
  html += `</turbo-stream>`
  html += `<turbo-stream action="reactive:token" target="${container}" data-reactive-token-value="CONTAINER-FRESH"></turbo-stream>`
  return html
}

const SMALL = smallBody()
const LARGE = largeBody()

// One happy-dom DOMParser, built once — so the ceiling bench measures PARSING,
// not Window construction. happy-dom is imported at module load (the bench file
// runs under `bun run`, top-level await is fine).
const { Window } = await import("happy-dom")
const domParser = new Window({ url: "http://localhost/" }).DOMParser
const parser = new domParser()

// Drive one full dispatch (fetch stubbed to return `body`); extractToken runs on
// the response inside #perform. The controller's id matches the body's self /
// container target so the real self-match branch is exercised (not the fallback).
function benchExtract(body, id) {
  const controller = buildController(fakeRoot(id))
  stubExtractEnv()
  stubFetchReturning(body)
  return dispatchOnce(controller)
}

group("extractToken (dispatch → regex scan of the response body)", () => {
  bench("~2KB single-component body", () => benchExtract(SMALL, "counter"))
  bench("~500KB 200-row collection body", () => benchExtract(LARGE, "reactive-rows"))

  // The comparison ceiling: parse the SAME html into a document (what a
  // DOMParser would do) instead of a targeted regex. happy-dom's DOMParser is
  // the off-browser stand-in; engine-relative, but same-machine comparable.
  bench("~500KB body — DOMParser parse (ceiling)", () => parser.parseFromString(LARGE, "text/html"))
})
