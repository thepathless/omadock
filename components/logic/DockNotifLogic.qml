import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import qs.Commons
import qs.Ui
import "../../DockModel.js" as DockModel
import "../../DockTasks.js" as DockTasks

// Logic extracted from Dock.qml: stateless functions, the dock root
// is passed in and owns all state. Bodies are verbatim.

QtObject {
  function updateNotifService(root) {
    if (!root.notifService && root.shell && typeof root.shell.serviceFor === "function") {
      var s = root.shell.serviceFor("omarchy.notifications") || root.shell.firstPartyServiceFor("omarchy.notifications")
      if (s) {
        root.notifService = s
        root._notifServiceAttempts = 0
      }
    }
  }

  // Sticky badges: a count arrives with its notification and stays until its
  // app is focused (clearNotificationBadgesFor). Rows are deduped by
  // DockModel.notificationRowKey, so model churn and re-emitted snapshots
  // never double-count; the seen-key store is bounded to the same 512 as the
  // row walks. The 20ms timer debounces the several signals that ask for a
  // rebuild.
  function processNotifRowSticky(root, row) {
    if (!row || !root.showNotificationBadges) return
    var key = DockModel.notificationRowKey(row)
    if (!key || root._notifSeenKeys[key]) return
    root._notifSeenKeys[key] = true
    root._notifSeenOrder.push(key)
    while (root._notifSeenOrder.length > 512) delete root._notifSeenKeys[root._notifSeenOrder.shift()]

    var rowCounts = DockModel.notificationCounts(root.notifEntries, root.appRows, [row])
    var ids = []
    for (var id in rowCounts) {
      // A focused app shows no badge; its counts clear at the focus event.
      if (id && !(root.activeId && DockModel.isAppMatch(id, root.activeId))) ids.push(id)
    }
    if (ids.length) root.notificationBadges = DockModel.bumpNotificationCounts(root.notificationBadges, ids, 1)
    // The seen key counts as a state change too: a row skipped now must stay
    // counted-out after a restart.
    root.scheduleBadgeSave()
  }

  function refreshNotificationBadges(root) {
    if (!root.showNotificationBadges) {
      if (root._notifSeenOrder.length) {
        root._notifSeenKeys = {}
        root._notifSeenOrder = []
      }
      if (JSON.stringify(root.notificationBadges) !== "{}") root.notificationBadges = {}
      root.scheduleBadgeSave()
      return
    }
    // The watcher's snapshot rows hold every live popup, so nothing is lost
    // to a dismissal between two emissions.
    var rows = root.notificationPopupRows
    var popups = root.notifService ? root.notifService.popupModel : null
    if (popups) {
      rows = []
      for (var i = 0; i < Math.min(popups.count, 512); i++) rows.push(popups.get(i))
    }
    for (var r = 0; r < Math.min(rows.length, 512); r++) root.processNotifRowSticky(rows[r])
  }

  function handleNotificationReceived(root, row) {
    if (!row) return
    var ts = row.timestamp || row.id || 0
    if (ts && ts === root._lastProcessedNotifTimestamp) return
    root._lastProcessedNotifTimestamp = ts

    var allEntries = root.notifEntries
    var matchedEntries = DockModel.findNotificationTargets(allEntries, root.appRows, row)
    if (!matchedEntries || matchedEntries.length === 0) return

    var activeHandle = root.hyprToplevelFor(ToplevelManager.activeToplevel)
    var activeAddr = root.windowAddress(activeHandle)

    var map = DockModel.copyMap(root.urgentMap)
    var found = false
    var eventKeys = []

    for (var e = 0; e < matchedEntries.length; e++) {
      var entry = matchedEntries[e]
      if (!entry) continue
      var appId = entry.appId || entry.id
      var wins = entry.windowList || []
      var isFocused = false

      for (var w = 0; w < wins.length; w++) {
        var wa = wins[w] ? wins[w].address : ""
        if (wa && wa === activeAddr) {
          isFocused = true
          break
        }
      }

      if (!isFocused && root.activeId && (DockModel.isAppMatch(appId, root.activeId) || (entry.id && DockModel.isAppMatch(entry.id, root.activeId)))) {
        isFocused = true
      }

      // Foreground Suppression Rule: An app currently focused in the foreground suppresses urgency bounce
      if (!isFocused) {
        map[appId] = true
        eventKeys.push(appId)
        for (var w2 = 0; w2 < wins.length; w2++) {
          var wa2 = wins[w2] ? wins[w2].address : ""
          if (wa2) { map[wa2] = true; eventKeys.push(wa2) }
        }
        found = true
      }
    }

    if (found) {
      root.urgentMap = map
      root.urgentEventKeys = eventKeys
      root.urgentEvents++
      root.modelTimerRestart()
    }

    // Play notification alert sound (suppressed if DND is active)
    // Only one dock chimes when several run side by side.
    if (root.isPrimary && root.urgentSound && root.urgentSoundName !== "none" && !root.isDndActive) {
      Quickshell.execDetached(["canberra-gtk-play", "-i", root.urgentSoundName])
    }
  }

  // Everything the dock remembers about a window is keyed by address, so one
  // pass over the live windows is enough to drop what closed.
  function pruneWindowState(root) {
    var live = {}
    var list = Hyprland.toplevels ? Hyprland.toplevels.values : []
    for (var i = 0; i < list.length; i++) {
      var address = root.windowAddress(list[i])
      if (address) live[address] = true
    }

    root.minimizedOrigins = root.keepLive(root.minimizedOrigins, live, false)
    root.parkedAt = root.keepLive(root.parkedAt, live, false)
    root.appRecentWindow = root.keepLive(root.appRecentWindow, live, true)
    root.urgentMap = root.keepUrgentLive(root.urgentMap, live)

    // Drop notification badges for closed apps (apps with no live windows)
    if (root.notificationBadges && Object.keys(root.notificationBadges).length > 0) {
      var badges = root.notificationBadges
      var nextBadges = {}
      var badgeChanged = false
      var allEntries = root.notifEntries || []
      var bkeys = Object.keys(badges)
      for (var bi = 0; bi < bkeys.length; bi++) {
        var bkey = bkeys[bi]
        var isLive = false
        if (root.launchPending && root.launchPending[bkey]) {
          isLive = true
        } else {
          for (var ej = 0; ej < allEntries.length; ej++) {
            var ent = allEntries[ej]
            if (!ent) continue
            var entId = ent.appId || ent.id
            if (entId === bkey || DockModel.isAppMatch(entId, bkey)) {
              if (ent.running) {
                var eWins = ent.windowList || []
                for (var ew = 0; ew < eWins.length; ew++) {
                  var ewa = eWins[ew] ? eWins[ew].address : ""
                  if (ewa && live[ewa]) {
                    isLive = true
                    break
                  }
                }
              }
              break
            }
          }
        }
        if (isLive) {
          nextBadges[bkey] = badges[bkey]
        } else {
          badgeChanged = true
        }
      }
      if (badgeChanged) {
        root.notificationBadges = nextBadges
        root.scheduleBadgeSave()
      }
    }

    // recentOpenedWindowAddrs entries carry their own expiry; drop the stale ones.
    var now = Date.now()
    var roa = root.recentOpenedWindowAddrs || {}
    var nextRoa = {}
    var roaChanged = false
    for (var rkey in roa) {
      if (roa[rkey] < now) roaChanged = true
      else nextRoa[rkey] = roa[rkey]
    }
    if (roaChanged) root.recentOpenedWindowAddrs = nextRoa
  }

  // urgentMap mixes two key shapes: "0x…" per-window addresses and bare appIds
  // set by the notification service. Address keys die with their window; bare appId
  // keys only survive while the app is running with active windows or launching.
  function keepUrgentLive(root, map, live) {
    var keys = Object.keys(map)
    if (keys.length === 0) return map

    var next = {}
    var dropped = false
    var allEntries = root.notifEntries

    for (var i = 0; i < keys.length; i++) {
      var key = keys[i]
      if (key.slice(0, 2) === "0x") {
        if (!live[key]) dropped = true
        else next[key] = map[key]
      } else {
        var isLiveApp = false
        if (root.launchPending && root.launchPending[key]) {
          isLiveApp = true
        } else {
          for (var e = 0; e < allEntries.length; e++) {
            var entry = allEntries[e]
            if (!entry) continue
            var eId = entry.appId || entry.id
            if (eId === key || DockModel.isAppMatch(eId, key)) {
              var wins = entry.windowList || []
              for (var w = 0; w < wins.length; w++) {
                var wa = wins[w] ? wins[w].address : ""
                if (wa && live[wa]) {
                  isLiveApp = true
                  break
                }
              }
              break
            }
          }
        }
        if (isLiveApp) {
          next[key] = map[key]
        } else {
          dropped = true
        }
      }
    }
    return dropped ? next : map
  }

  // Sticky badges are "notifications you have not looked at": they clear for
  // the app (and whatever entry owns the address) as soon as it gains focus,
  // independently of whether any urgency entry exists.
  function clearNotificationBadgesFor(root, appId, address) {
    if (!root.notificationBadges) return
    var next = DockModel.clearNotificationCounts(root.notificationBadges, appId)
    var normAddr = address ? DockModel.windowAddress({ address: address }) : ""
    if (normAddr) {
      var allEntries = root.notifEntries
      for (var i = 0; i < allEntries.length; i++) {
        var entry = allEntries[i]
        var wins = entry ? (entry.windowList || []) : []
        for (var w = 0; w < wins.length; w++) {
          if (wins[w] && wins[w].address === normAddr) {
            next = DockModel.clearNotificationCounts(next, entry.appId || entry.id)
            break
          }
        }
      }
    }
    if (JSON.stringify(next) !== JSON.stringify(root.notificationBadges)) {
      root.notificationBadges = next
      root.scheduleBadgeSave()
    }
  }

  // Clears urgency entries from urgentMap for an application and its windows.
  // Called whenever an app/window receives focus or is activated/clicked by user.
  function clearUrgentApp(root, appId, address) {
    root.clearNotificationBadgesFor(appId, address)
    if (root && root.sharedState && root.sharedState.taskStatus) {
      root.sharedState.taskStatus = DockTasks.clearTaskStatusFor(DockModel, root.sharedState.taskStatus, appId)
    }
    if (!root.urgentMap) return
    var hasKeys = false
    for (var k in root.urgentMap) {
      if (root.urgentMap[k]) { hasKeys = true; break }
    }
    if (!hasKeys) return

    var map = DockModel.copyMap(root.urgentMap)
    var changed = false

    var normAddr = ""
    if (address) {
      var rawAddr = String(address).trim()
      if (rawAddr.slice(0, 2) === "0x" || rawAddr.slice(0, 2) === "0X") rawAddr = rawAddr.slice(2)
      if (rawAddr) normAddr = "0x" + rawAddr
    }

    if (normAddr && map[normAddr]) {
      delete map[normAddr]
      changed = true
    }

    var allEntries = root.notifEntries
    var targetEntries = []

    for (var i = 0; i < allEntries.length; i++) {
      var entry = allEntries[i]
      if (!entry) continue
      var entryId = entry.appId || entry.id
      var matched = false

      if (appId && (entryId === appId || DockModel.isAppMatch(entryId, appId))) {
        matched = true
      }

      if (!matched && normAddr && entry.windowList) {
        for (var w = 0; w < entry.windowList.length; w++) {
          var winAddr = entry.windowList[w] ? entry.windowList[w].address : ""
          if (winAddr && winAddr === normAddr) {
            matched = true
            break
          }
        }
      }

      if (matched) {
        targetEntries.push(entry)
      }
    }

    if (appId) {
      var rawId = DockModel.stripDesktop(appId)
      var normId = DockModel.normalizeId(appId)
      if (map[appId]) { delete map[appId]; changed = true }
      if (rawId && map[rawId]) { delete map[rawId]; changed = true }
      if (normId && map[normId]) { delete map[normId]; changed = true }
    }

    for (var t = 0; t < targetEntries.length; t++) {
      var tEntry = targetEntries[t]
      var tId = tEntry.appId || tEntry.id
      if (tId && map[tId]) { delete map[tId]; changed = true }
      if (tEntry.id && map[tEntry.id]) { delete map[tEntry.id]; changed = true }
      if (tEntry.appId && map[tEntry.appId]) { delete map[tEntry.appId]; changed = true }
      var tWins = tEntry.windowList || []
      for (var tw = 0; tw < tWins.length; tw++) {
        var twAddr = tWins[tw] ? tWins[tw].address : ""
        if (twAddr && map[twAddr]) {
          delete map[twAddr]
          changed = true
        }
      }
    }

    // Also check if any remaining key in map matches appId via DockModel.isAppMatch
    if (appId) {
      for (var mKey in map) {
        if (mKey.slice(0, 2) !== "0x" && DockModel.isAppMatch(mKey, appId)) {
          delete map[mKey]
          changed = true
        }
      }
    }

    if (changed) {
      root.urgentMap = map
      root.modelTimerRestart()
    }
  }

  // byValue: the map holds addresses as values (app -> window) rather than keys.
  function keepLive(root, map, live, byValue) {
    var keys = Object.keys(map)
    if (keys.length === 0) return map

    var next = {}
    var dropped = false
    for (var i = 0; i < keys.length; i++) {
      var key = keys[i]
      if (live[byValue ? map[key] : key]) next[key] = map[key]
      else dropped = true
    }
    return dropped ? next : map
  }
}
