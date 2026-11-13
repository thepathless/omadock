#!/usr/bin/env node
// Unit test for DockModel.togglePinned — the pin toggle behind "Pin to Dock" /
// "Unpin from Dock" in both the app and the minimized-tile context menus.
//
// DockModel.js is a plain script with no exports, so it is evaluated in a
// sandbox and its functions are read off the global object. No Quickshell or
// shell config is needed: togglePinned is pure.
//
// Run: node tests/toggle-pinned.js   (tests/toggle-pinned.sh wraps it)
'use strict'

const fs = require('fs')
const path = require('path')
const vm = require('vm')
const assert = require('assert')

const source = fs.readFileSync(path.join(__dirname, '..', 'DockModel.js'), 'utf8')
const sandbox = { console }
vm.createContext(sandbox)
// Run the model in its own context so its top-level functions stay isolated.
vm.runInContext(source, sandbox, { filename: 'DockModel.js' })
const togglePinned = sandbox.togglePinned

let checks = 0
function check(name, actual, expected) {
  checks++
  // Compare through JSON: the model's arrays come from another realm (vm), so
  // deepStrictEqual would trip over the Array prototype rather than the values.
  const got = JSON.stringify(actual)
  const want = JSON.stringify(expected)
  assert.strictEqual(got, want, `${name}\n  actual:   ${got}\n  expected: ${want}`)
  console.log(`  ok  ${name}`)
}

// The id shape that triggers the bug: the pin was made when the app's entry was
// named "hermes", the entry it resolves to now is "com.nousresearch.hermes".
const LEGACY = 'hermes'
const ENTRY = 'com.nousresearch.hermes'
const pins = ['org.gnome.Nautilus', LEGACY, 'WhatsApp']

check('unpin by the entry id removes the legacy pin',
  togglePinned(pins, ENTRY), ['org.gnome.Nautilus', 'WhatsApp'])

check('unpin by the pinned id still removes it',
  togglePinned(pins, LEGACY), ['org.gnome.Nautilus', 'WhatsApp'])

check('unpin by the window class removes the pin',
  togglePinned(pins, 'com.nousresearch.hermes'), ['org.gnome.Nautilus', 'WhatsApp'])

check('a list already holding both ids is cleaned up by one unpin',
  togglePinned(['org.gnome.Nautilus', LEGACY, 'WhatsApp', ENTRY], ENTRY),
  ['org.gnome.Nautilus', 'WhatsApp'])

check('unpinning an app that is not pinned appends it',
  togglePinned(['foot'], ENTRY), ['foot', ENTRY])

check('a .desktop suffix is stripped from the id being pinned',
  togglePinned(['foot'], `${ENTRY}.desktop`), ['foot', ENTRY])

check('an unrelated app is left alone',
  togglePinned(pins, 'Discord'), ['org.gnome.Nautilus', LEGACY, 'WhatsApp', 'Discord'])

check('blank entries and blank ids are passed through untouched',
  togglePinned(['foot', '', '  '], ''), ['foot', '', '  '])

check('the input list is not mutated',
  (() => { const input = pins.slice(); togglePinned(input, ENTRY); return input })(), pins)

console.log(`\ntoggle-pinned: ${checks} checks passed`)
