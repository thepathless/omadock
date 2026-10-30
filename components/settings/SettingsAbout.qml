import QtQuick 6.11
import qs.Commons
import qs.Ui
import "../strings"

import Quickshell

// Settings page: version, update channel, supporters and contributors.
// Instantiated by SettingsPanel, which injects root (the Dock, for
// values and setters) and panel (page/edit state).

Column {
  property var root: null
  property var panel: null
  width: parent.width


  SectionLabel { title: "omadock" }

  SettingRow {
    label: Tr.t("about.version", "Version")
    hint: Tr.t("about.versionHint", "Free and open-source application dock for Omarchy · MIT license")
    Text {
      text: (root && root.manifest && root.manifest.version) ? "v" + root.manifest.version : "unknown"
      textFormat: Text.PlainText
      color: Color.menu.text
      font.family: Style.font.family
      font.pixelSize: Style.font.subtitle
    }
  }
  SettingRow {
    label: Tr.t("about.project", "Project & feedback")
    hint: Tr.t("about.projectHint", "Report bugs, follow development, or contribute.")
    Button {
      focusable: true
      text: "GitHub"
      foreground: Color.menu.text
      bordered: true
      onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/thepathless/omadock"))
    }
  }

  SectionLabel { title: "Updates" }
  ChoiceRow {
    key: "updateChannel"
    label: "Update channel"
    hint: "Stable receives verified releases; Experimental gets features early. Switching reloads the shell immediately."
    options: [{ value: "stable", label: "Stable" }, { value: "experiment", label: "Experimental" }]
    value: panel.channel !== "" ? panel.channel : "stable"
    onPicked: function(v) {
      if (panel.channel === "" || v === panel.channel) return
      Quickshell.execDetached(["omadock-switch", v === "stable" ? "stable" : "experiment"])
    }
  }

  SettingsSection {
    title: Tr.t("settings.credits", "Credits & acknowledgments")
  SectionLabel { title: "Supporters & acknowledgments" }

  Text {
    width: parent.width
    topPadding: Style.spacing.lg
    bottomPadding: Style.spacing.lg
    text: "omadock is built with love by thepathless — a medical student, between classes and clinics. It is free, and it always will be.\n\nIf it earns a place on your desktop, you can give some love back to its maker. No tiers, no perks — just support returned."
    textFormat: Text.PlainText
    color: Color.menu.text
    wrapMode: Text.WordWrap
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  SettingRow {
    label: "Supporter #1 — thepathless"
    hint: Tr.t("about.makerHint", "The maker. Its first and forever supporter.")

    Button {
      focusable: true
      text: Tr.t("about.support", "Support ❤")
      foreground: Color.menu.text
      bordered: true
      onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/sponsors/thepathless"))
    }
  }

  SettingRow {
    label: Tr.t("about.wall", "Supporters wall")
    hint: Tr.t("about.wallHint", "Everyone who has supported omadock, honored in the repository.")

    Button {
      focusable: true
      text: Tr.t("about.viewWall", "View wall")
      foreground: Color.menu.text
      bordered: true
      onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/thepathless/omadock/blob/main/SPONSORS.md"))
    }
  }

  SectionLabel { title: "Code Contributors" }

  SettingRow {
    label: "@priard (Lukasz)"
    hint: "macOS folder stacks, icon shaders, gradients, grain, drop-to-open"

    Button {
      focusable: true
      text: "GitHub ↗"
      foreground: Color.menu.text
      bordered: true
      onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/priard"))
    }
  }

  SettingRow {
    label: "@G-Pappas (George P.)"
    hint: "Multi-monitor docks & per-output instance management"

    Button {
      focusable: true
      text: "GitHub ↗"
      foreground: Color.menu.text
      bordered: true
      onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/G-Pappas"))
    }
  }

  SettingRow {
    label: "@NothingManTR (Taha Can)"
    hint: "Removable media drives & safe eject, smart app matching, jump lists"

    Button {
      focusable: true
      text: "GitHub ↗"
      foreground: Color.menu.text
      bordered: true
      onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/NothingManTR"))
    }
  }

  SettingRow {
    label: "@assada"
    hint: "Window focus dispatch & Hyprland layout awareness"

    Button {
      focusable: true
      text: "GitHub ↗"
      foreground: Color.menu.text
      bordered: true
      onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/assada"))
    }
  }

  SettingRow {
    label: "@tdslot"
    hint: "Desktop entry launch suffix validation fix for pinned apps"

    Button {
      focusable: true
      text: "GitHub ↗"
      foreground: Color.menu.text
      bordered: true
      onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/tdslot"))
    }
  }

  SettingRow {
    label: "@Tech0001"
    hint: "Application matching restoration"

    Button {
      focusable: true
      text: "GitHub ↗"
      foreground: Color.menu.text
      bordered: true
      onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/Tech0001"))
    }
  }

  SectionLabel { title: "Bug Hunters & Diagnostics" }

  SettingRow {
    label: "@justinlharter"
    hint: "Suspend/resume screen null recovery diagnostics"

    Button {
      focusable: true
      text: "GitHub ↗"
      foreground: Color.menu.text
      bordered: true
      onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/justinlharter"))
    }
  }

  SettingRow {
    label: "@maugustoldo (Marcos Augusto)"
    hint: "GTK icon resolving, launcher matching, and theme accent"

    Button {
      focusable: true
      text: "GitHub ↗"
      foreground: Color.menu.text
      bordered: true
      onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/maugustoldo"))
    }
  }

  SettingRow {
    label: "@m-bowden (Michael Bowden)"
    hint: "Webapp Exec-URL .execString desktop entry investigation"

    Button {
      focusable: true
      text: "GitHub ↗"
      foreground: Color.menu.text
      bordered: true
      onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/m-bowden"))
    }
  }

  SettingRow {
    label: "@herman6888"
    hint: "Omarchy 4.x overlay plugin appLibrary diagnostic"

    Button {
      focusable: true
      text: "GitHub ↗"
      foreground: Color.menu.text
      bordered: true
      onClicked: Util.execDetached("uwsm-app -- xdg-open " + Util.shellQuote("https://github.com/herman6888"))
    }
  }
  }
}
