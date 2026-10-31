import QtQuick 6.11
import Quickshell
import qs.Commons

// The apps button's anchored launcher ("appsButtonAction": "start").
//
// The dock owns the open flag; this host owns the popup's life and its window
// (DockPopupWindow), the same pair every dock popup uses, so the Start panel
// is one more popup in the dock's system rather than a second window type.
// Its anchor is the apps button: the popup machinery centres it over the
// button's centre, clamped to the screen, with the same 6px gap above the
// card that the folder and group popups use.
Item {
  id: menuHost

  property var dockRoot: null
  property bool open: false

  readonly property var card: menuHost.dockRoot ? menuHost.dockRoot.dockCardComp : null
  readonly property var button: menuHost.card ? menuHost.card.appsButton : null
  // Read-only, for the live suite: the window and the panel it hosts.
  readonly property var menuWindow: startLoader.item
  readonly property var menu: menuHost.menuWindow ? menuHost.menuWindow.body : null
  readonly property bool wanted: menuHost.open && !!menuHost.dockRoot && menuHost.dockRoot.dockVisible

  // Centre the menu is anchored to, in the dock window's coordinates (what
  // DockPopupWindow.centerX expects), taken when it opens. It is a snapshot,
  // not a binding: the button's place in the row is laid out after the host
  // is built, and mapToItem does not notify a binding when an ancestor moves.
  property real anchorX: 0
  function buttonCentreX() {
    if (!menuHost.dockRoot || !menuHost.card) return 0
    var item = menuHost.button
    if (item && item.visible && item.width > 0)
      return item.mapToItem(menuHost.dockRoot.contentItemRef, item.width / 2, 0).x
    var c = menuHost.card.dockCard
    return c.mapToItem(menuHost.dockRoot.contentItemRef, c.width / 2, 0).x
  }

  function toggle() {
    if (menuHost.open) menuHost.close()
    else menuHost.show()
  }

  function show() {
    if (!menuHost.dockRoot) return
    // One popup at a time, as the other opens do.
    menuHost.dockRoot.closeContext()
    menuHost.dockRoot.closeFolderStack()
    menuHost.dockRoot.closeAppGroup()
    menuHost.anchorX = menuHost.buttonCentreX()
    menuHost.open = true
    menuHost.dockRoot.syncVisibility()
  }

  function close() {
    if (!menuHost.open) return
    menuHost.open = false
    if (menuHost.dockRoot) menuHost.dockRoot.syncVisibility()
  }

  // A dock that hides takes its menu with it; the next open starts fresh.
  Connections {
    target: menuHost.dockRoot
    function onDockVisibleChanged() { if (!menuHost.dockRoot.dockVisible) menuHost.open = false }
  }

  PopupLife {
    id: startLife
    dockRoot: menuHost.dockRoot
    want: menuHost.wanted
  }

  LazyLoader {
    id: startLoader
    active: startLife.alive

    DockPopupWindow {
      id: startWindow
      life: startLife
      dockRoot: menuHost.dockRoot
      open: true
      centerX: menuHost.anchorX
      body: startMenuBody
      // Escape is answered on the panel, so the keyboard has to land on this
      // popup rather than be dropped on the dock's layer surface.
      holdsKeyboard: true
      onDismissed: menuHost.close()

      StartMenu {
        id: startMenuBody
        rootRef: menuHost.dockRoot
        popupWindow: startWindow
      }
    }
  }
}
