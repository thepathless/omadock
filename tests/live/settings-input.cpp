#include <QQmlExtensionPlugin>
#include <QQmlEngine>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTest>

class SettingsInput : public QObject {
  Q_OBJECT
public:
  using QObject::QObject;
  Q_INVOKABLE bool key(QObject *target, int key, int modifiers = 0) {
    auto *item = qobject_cast<QQuickItem *>(target);
    if (!item || !item->window()) return false;
    // This goes straight to one in-process Qt window, not the OS seat.
    // Never requestActivate(): the owner's compositor focus must not move.
    item->forceActiveFocus(Qt::TabFocusReason);
    QTest::keyClick(item->window(), static_cast<Qt::Key>(key), Qt::KeyboardModifiers(modifiers));
    return true;
  }
  // Same window, but the key goes to whatever holds focus there - for a
  // TextField that took focus itself when an edit started.
  Q_INVOKABLE bool keyFocused(QObject *target, int key, int modifiers = 0) {
    auto *item = qobject_cast<QQuickItem *>(target);
    if (!item || !item->window() || !item->window()->activeFocusItem()) return false;
    QTest::keyClick(item->window(), static_cast<Qt::Key>(key), Qt::KeyboardModifiers(modifiers));
    return true;
  }
  Q_INVOKABLE QString focused(QObject *target) {
    auto *item = qobject_cast<QQuickItem *>(target);
    if (!item || !item->window() || !item->window()->activeFocusItem()) return {};
    return item->window()->activeFocusItem()->objectName();
  }
};

class SettingsInputPlugin : public QQmlExtensionPlugin {
  Q_OBJECT
  Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
  void registerTypes(const char *uri) override { qmlRegisterType<SettingsInput>(uri, 1, 0, "SettingsInput"); }
};

#include "settings-input.moc"
