const assert = require('node:assert/strict')
const { readFileSync } = require('node:fs')
const { join } = require('node:path')
const vm = require('node:vm')
const { test } = require('node:test')

const model = vm.createContext({ console, Quickshell: { iconPath: () => '' } })
vm.runInContext(readFileSync(join(__dirname, '../../DockModel.js'), 'utf8'), model)
const plain = value => JSON.parse(JSON.stringify(value))
const library = {
  entryName: entry => entry.name,
  iconSource: name => ['ghostty', 'kitty', 'btop', 'firefox', 'antigravity', 'kitty-session'].includes(name)
    ? `file:///icons/${name}.svg` : 'file:///icons/application-x-executable.svg',
}
const rows = [
  { id: 'com.mitchellh.ghostty', name: 'Ghostty', icon: 'ghostty' },
  { id: 'kitty', name: 'Kitty', icon: 'kitty' },
  { id: 'btop', name: 'btop', icon: 'btop' },
  { id: 'firefox', name: 'Firefox', icon: 'firefox' },
  { id: 'antigravity', name: 'Antigravity', icon: 'antigravity' },
  { id: 'kitty-session', name: 'Kitty Session', icon: 'kitty-session' },
]
function entries(appId, host, cliApps = {}) {
  return model.buildEntries([], [{ appId, title: 'Window' }], rows, library,
    () => ({ address: 'abc', workspace: { name: '1' } }), '', {}, [], host, cliApps)
}

test('custom TUI app-id prefers btop over its hosting terminal', () => {
  const result = entries('org.omarchy.btop', { '0xabc': 'com.mitchellh.ghostty' })
  assert.equal(result.running[0].icon, 'file:///icons/btop.svg')
  assert.equal(result.running[0].appId, 'org.omarchy.btop')
  assert.equal(result.running[0].name, 'btop')
})
test('host mapping uses the actual emulator rather than the default terminal', () => {
  assert.equal(entries('org.omarchy.unknown-tui', { '0xabc': 'kitty' }).running[0].icon,
    'file:///icons/kitty.svg')
})
test('generic or unresolved CLI uses its known terminal only as icon fallback', () => {
  const generic = { ...library, iconSource: name => name === 'application-x-executable'
    ? 'file:///icons/application-x-executable.svg'
    : name === 'kitty' ? 'file:///icons/kitty.svg' : '' }
  const result = model.buildEntries([], [{ appId: 'unknown-tui', title: 'TUI' }], [], generic,
    () => ({ address: 'abc', workspace: { name: '1' } }), '', {}, [],
    { '0xabc': 'kitty' })
  assert.equal(result.running[0].icon, 'file:///icons/kitty.svg')
})
test('Antigravity CLI command alias resolves a nonblank product icon', () => {
  for (const id of ['agy', 'org.omarchy.agy', 'antigravity']) {
    assert.equal(entries(id, { '0xabc': 'com.mitchellh.ghostty' }).running[0].icon,
      'file:///icons/antigravity.svg')
    assert.equal(model.isAppMatch(id, 'antigravity.desktop'), true)
  }
  assert.equal(model.isAppMatch('unknown-agy-app', 'antigravity'), false)
  const result = model.buildEntries(['antigravity'], [{ appId: 'org.omarchy.agy', title: 'agy' }], rows,
    library, () => ({ address: 'abc', workspace: { name: '1' } }), '', {}, [],
    { '0xabc': 'com.mitchellh.ghostty' })
  assert.equal(result.pinned[0].running, true)
  assert.equal(result.pinned[0].icon, 'file:///icons/antigravity.svg')
})
test('CLI pin aliases find desktop entries and select the product identity', () => {
  const result = model.buildEntries(['agy', 'org.omarchy.btop'],
    [{ appId: 'org.omarchy.agy', title: 'agy' }, { appId: 'org.omarchy.btop', title: 'btop' }],
    rows, library, () => ({ address: 'abc', workspace: { name: '1' } }), '', {}, [],
    { '0xabc': 'com.mitchellh.ghostty' })
  assert.equal(result.pinned[0].name, 'Antigravity')
  assert.equal(result.pinned[0].running, true)
  assert.equal(result.pinned[0].icon, 'file:///icons/antigravity.svg')
  assert.equal(result.pinned[1].name, 'btop')
  assert.equal(result.pinned[1].running, true)
  assert.equal(result.pinned[1].icon, 'file:///icons/btop.svg')
})
test('recognized CLI descendant owns the terminal window and product icon', () => {
  const result = model.buildEntries(['btop', 'com.mitchellh.ghostty'],
    [{ appId: 'org.omarchy.btop', title: 'btop' }], rows, library,
    () => ({ address: 'abc', workspace: { name: '1' } }), '', {}, [],
    { '0xabc': 'com.mitchellh.ghostty' }, { '0xabc': 'btop' })
  assert.equal(result.pinned[0].running, true)
  assert.equal(result.pinned[0].icon, 'file:///icons/btop.svg')
  assert.equal(result.pinned[1].running, false)
  assert.equal(result.running.length, 0)
})
test('unrecognized CLI preserves the compositor identity and terminal fallback', () => {
  const result = entries('org.omarchy.unknown-tui', { '0xabc': 'kitty' })
  assert.equal(result.running[0].appId, 'org.omarchy.unknown-tui')
  assert.equal(result.running[0].icon, 'file:///icons/kitty.svg')
})
test('GUI application icon resolution is unchanged', () => {
  assert.equal(entries('firefox', {}).running[0].icon, 'file:///icons/firefox.svg')
})
test('unknown apps have a non-blank generic fallback', () => {
  assert.equal(entries('unknown-app', {}).running[0].icon,
    'file:///icons/application-x-executable.svg')
})
test('persisted array-like objects cannot amplify bounded collection reads', () => {
  const hostile = { length: 1e9, 0: { id: 'g', apps: [] } }
  assert.deepEqual(plain(model.boundAppGroups(hostile)), [])
  assert.deepEqual(plain(model.boundPinnedFolders(hostile)), [])
  assert.deepEqual(plain(model.boundAppGroups([{ id: 'g', apps: { length: 1e9 } }])),
    [{ id: 'g', name: 'Group', icon: 'folder', apps: [], cols: 3, before: '' }])
})
test('pins reject hostile array-like objects, nonstrings, and excessive IDs', () => {
  assert.deepEqual(plain(model.parsePinned('{"pinned":{"length":1000000000}}')), [])
  assert.deepEqual(plain(model.parsePinned(JSON.stringify(['btop.desktop', { appId: 'kitty' }, 7, 'btop', '__proto__', 'x'.repeat(513)]))), ['btop', '__proto__'])
  assert.equal(model.parsePinned(JSON.stringify(Array.from({ length: 1000 }, (_, i) => `app${i}`))).length, 256)
})
test('TUI app-id launch wrapper is scoped to the two requested CLI products', () => {
  assert.equal(model.isKnownCli('agy'), true)
  assert.equal(model.isKnownCli('org.omarchy.agy'), true)
  assert.equal(model.isKnownCli('antigravity'), true)
  assert.equal(model.isKnownCli('btop'), true)
  assert.equal(model.isKnownCli('org.omarchy.btop'), true)
  assert.equal(model.isKnownCli('org.omarchy.btop-alt'), true)
  // Anything else keeps its normal launch path, whatever its terminal flag says.
  for (const id of ['htop', 'neovim', 'kitty', 'org.omarchy.unknown-tui', '', 'kitty-session'])
    assert.equal(model.isKnownCli(id), false, id)
})
test('notification alias ids live in one place and cover the CLI spellings', () => {
  assert.deepEqual(plain(model.notificationAliasIds('antigravity')),
    ['antigravity', 'antigravity', 'agy', 'org.omarchy.agy'])
  assert.deepEqual(plain(model.notificationAliasIds('agy')), ['agy', 'antigravity', 'agy', 'org.omarchy.agy'])
  assert.deepEqual(plain(model.notificationAliasIds('btop')), ['btop', 'btop', 'org.omarchy.btop'])
  assert.deepEqual(plain(model.notificationAliasIds('org.omarchy.btop')),
    ['org.omarchy.btop', 'btop', 'org.omarchy.btop'])
  // Non-CLI ids are untouched: no invented aliases.
  assert.deepEqual(plain(model.notificationAliasIds('firefox')), ['firefox'])
  assert.deepEqual(plain(model.notificationAliasIds('')), [''])
})
test('known CLI notifications match the pinned product app, not its host terminal', () => {
  for (const app of ['org.omarchy.agy', 'agy', 'Antigravity']) {
    const entries = [{ appId: 'antigravity', pinned: true }, { appId: 'com.mitchellh.ghostty', pinned: true }]
    assert.deepEqual(plain(model.notificationCounts(entries, rows, [{ app }])), { antigravity: 1 })
  }
  assert.deepEqual(plain(model.notificationCounts([{ appId: 'btop', pinned: true }], rows,
    [{ app: 'org.omarchy.btop' }])), { btop: 1 })
  assert.deepEqual(plain(model.notificationCounts([{ appId: 'btop', pinned: true }], rows,
    [{ app: 'btop' }])), { btop: 1 })
  assert.deepEqual(plain(model.notificationCounts([{ appId: 'antigravity', pinned: true },
    { appId: 'com.mitchellh.ghostty', pinned: true }], rows,
    [{ app: 'org.omarchy.agy' }])), { antigravity: 1 })
})
test('badges count snapshots per matching entry and clear on replacement/removal', () => {
  const apps = [{ appId: 'firefox', name: 'Firefox', pinned: true },
    { appId: 'btop', name: 'btop', pinned: false }]
  const notices = [{ app: 'Firefox', appIcon: 'firefox' }, { app: 'Firefox' }, { app: 'btop' }]
  // Unpinned entries count too: display gating moved to the UI.
  assert.deepEqual(plain(model.notificationCounts(apps, rows, notices)), { firefox: 2, btop: 1 })
  assert.deepEqual(plain(model.notificationCounts(apps, rows, notices.slice(0, 1))), { firefox: 1 })
  assert.deepEqual(plain(model.notificationCounts(apps, rows, [{ app: 'Other' }])), {})
  assert.deepEqual(plain(model.notificationCounts(apps, rows, [])), {})
  assert.deepEqual(plain(model.notificationCounts(apps, rows, 'not-an-array')), {})
})
test('grouped entries count even when unpinned (steam-in-folder badge fix)', () => {
  // Live IPC shape: steam lives in grouped with pinned:false.
  const grouped = [{ id: 'steam', appId: 'steam', pinned: false, running: true,
    windowList: [{ address: '0x1', title: 'Steam', appId: 'steam' }] }]
  assert.deepEqual(plain(model.notificationCounts(grouped, rows,
    [{ app: 'steam', summary: 'Download complete' }])), { steam: 1 })
  // The 512-row bound survives the gate removal.
  assert.deepEqual(plain(model.notificationCounts(grouped, rows,
    Array.from({ length: 600 }, () => ({ app: 'steam' })))), { steam: 512 })
})
test('sticky badge helpers bump, clear, and sum by alias without mutating input', () => {
  const base = { steam: 2 }
  assert.deepEqual(plain(model.bumpNotificationCounts(base, ['steam', 'steam', 'btop'], 1)),
    { steam: 3, btop: 1 })
  assert.deepEqual(plain(model.bumpNotificationCounts(base, [], 1)), { steam: 2 })
  assert.deepEqual(plain(model.bumpNotificationCounts(base, ['x'], 0)), { steam: 2 })
  assert.deepEqual(plain(model.bumpNotificationCounts(base, ['x'], -3)), { steam: 2 })
  assert.deepEqual(plain(model.bumpNotificationCounts(null, ['x'], 2)), { x: 2 })
  assert.deepEqual(base, { steam: 2 })

  // Clearing drops every spelling the app may be filed under.
  const cli = { btop: 1, 'org.omarchy.btop': 2, agy: 3, other: 4 }
  assert.deepEqual(plain(model.clearNotificationCounts(cli, 'org.omarchy.btop')),
    { agy: 3, other: 4 })
  assert.deepEqual(plain(model.clearNotificationCounts(cli, 'agy')),
    { btop: 1, 'org.omarchy.btop': 2, other: 4 })
  assert.deepEqual(cli, { btop: 1, 'org.omarchy.btop': 2, agy: 3, other: 4 })

  // Folder totals sum members via aliases, each spelling once.
  assert.equal(model.groupBadgeTotal(['btop', 'org.omarchy.btop', 'steam'], cli), 3)
  assert.equal(model.groupBadgeTotal(['agy'], cli), 3)
  assert.equal(model.groupBadgeTotal([], cli), 0)
  assert.equal(model.groupBadgeTotal(['missing'], cli), 0)
  assert.equal(model.groupBadgeTotal(null, cli), 0)
})
test('row keys dedupe by timestamp/id and fingerprint watcher fallback rows', () => {
  assert.equal(model.notificationRowKey({ timestamp: 5, id: 'x' }), '5-x')
  assert.equal(model.notificationRowKey({ timestamp: 5, id: 'x', body: 'hi' }), '5-x')
  // Fallback rows carry neither field: identical content is one row.
  assert.equal(model.notificationRowKey({ app: 'steam', summary: 's', body: 'b' }),
    model.notificationRowKey({ app: 'steam', summary: 's', body: 'b' }))
  assert.notEqual(model.notificationRowKey({ app: 'steam', summary: 's', body: 'b' }),
    model.notificationRowKey({ app: 'steam', summary: 's', body: 'c' }))
  assert.equal(model.notificationRowKey(null), '')
})
test('PWA notification badge is not also attributed to its browser', () => {
  const apps = [{ appId: 'firefox', name: 'Firefox', pinned: true },
    { appId: 'chrome-web.whatsapp.com__-Default', name: 'WhatsApp', pinned: true }]
  assert.deepEqual(plain(model.notificationCounts(apps, rows,
    [{ app: 'Firefox', body: 'https://web.whatsapp.com/ message' }])),
    { 'chrome-web.whatsapp.com__-Default': 1 })
})
test('UTF-8 byte ceiling counts surrogate pairs as four bytes', () => {
  assert.equal(model.readCapped('😀', 4), '😀')
  assert.equal(model.readCapped('😀', 3), '')
  assert.equal(model.readCapped('é', 2), 'é')
  assert.equal(model.readCapped('é', 1), '')
})
test('groups and folders retain their collection ceilings', () => {
  assert.equal(model.boundAppGroups(Array.from({ length: 100 }, (_, i) => ({ id: `g${i}` }))).length, 32)
  assert.equal(model.boundPinnedFolders(Array.from({ length: 100 }, () => ({ path: '/tmp' }))).length, 12)
})
test('presets include classic/long divider geometry and reject nonscalar look values', () => {
  const look = plain(model.pickLook({ dividerGeometry: 'long', hoverEffect: 'glow', bgColor: {}, iconSize: Infinity }))
  assert.equal(look.dividerGeometry, 'long')
  assert.equal(look.hoverEffect, 'glow')
  assert.equal(look.bgColor, undefined)
  assert.equal(look.iconSize, 0)
  assert.deepEqual(plain(model.boundPresets({ length: 1e9 })), [])
})
test('ungroup retains application order without duplicating existing pins', () => {
  const row = [{ kind: 'group', id: 'g', group: { apps: ['kitty', 'firefox'] } },
    { kind: 'app', appId: 'firefox' }]
  assert.deepEqual(plain(model.ungroupRow(row, 'g')), [
    { kind: 'app', appId: 'kitty' }, { kind: 'app', appId: 'firefox' },
  ])
})
