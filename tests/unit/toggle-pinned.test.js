const assert = require('node:assert/strict')
const { readFileSync } = require('node:fs')
const { join } = require('node:path')
const vm = require('node:vm')
const { test } = require('node:test')

const model = vm.createContext({ console })
vm.runInContext(readFileSync(join(__dirname, '../../DockModel.js'), 'utf8'), model)
const togglePinned = model.togglePinned
const plain = value => JSON.parse(JSON.stringify(value))

// The id shape that triggers the bug: the pin was made when the app's entry was
// named "hermes", the entry it resolves to now is "com.nousresearch.hermes".
const LEGACY = 'hermes'
const ENTRY = 'com.nousresearch.hermes'
const pins = ['org.gnome.Nautilus', LEGACY, 'WhatsApp']

test('unpin by the entry id removes the legacy pin', () => {
  assert.deepEqual(plain(togglePinned(pins, ENTRY)), ['org.gnome.Nautilus', 'WhatsApp'])
})

test('unpin by the pinned id still removes it', () => {
  assert.deepEqual(plain(togglePinned(pins, LEGACY)), ['org.gnome.Nautilus', 'WhatsApp'])
})

test('unpin by the window class removes the pin', () => {
  assert.deepEqual(plain(togglePinned(pins, 'com.nousresearch.hermes')), ['org.gnome.Nautilus', 'WhatsApp'])
})

test('a list already holding both ids is cleaned up by one unpin', () => {
  assert.deepEqual(
    plain(togglePinned(['org.gnome.Nautilus', LEGACY, 'WhatsApp', ENTRY], ENTRY)),
    ['org.gnome.Nautilus', 'WhatsApp'])
})

test('unpinning an app that is not pinned appends it', () => {
  assert.deepEqual(plain(togglePinned(['foot'], ENTRY)), ['foot', ENTRY])
})

test('a .desktop suffix is stripped from the id being pinned', () => {
  assert.deepEqual(plain(togglePinned(['foot'], `${ENTRY}.desktop`)), ['foot', ENTRY])
})

test('an unrelated app is left alone', () => {
  assert.deepEqual(
    plain(togglePinned(pins, 'Discord')),
    ['org.gnome.Nautilus', LEGACY, 'WhatsApp', 'Discord'])
})

test('blank entries and blank ids are passed through untouched', () => {
  assert.deepEqual(plain(togglePinned(['foot', '', '  '], '')), ['foot', '', '  '])
})

test('the input list is not mutated', () => {
  const input = pins.slice()
  togglePinned(input, ENTRY)
  assert.deepEqual(input, pins)
})
