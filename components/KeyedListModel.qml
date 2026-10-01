import QtQuick

// A ListModel of string keys kept in step with a list by removes, moves and
// inserts. A Repeater over a plain JS array rebuilds every delegate whenever
// the array is replaced, which re-creates (and re-decodes) every icon on any
// change; over this model the delegates of keys that stay are kept, and they
// look their data up by key.
ListModel {
  id: model

  function sync(keys) {
    var want = keys || []
    var wanted = {}
    for (var i = 0; i < want.length; i++) wanted[want[i]] = true
    for (var r = model.count - 1; r >= 0; r--) {
      if (!wanted[model.get(r).key]) model.remove(r)
    }
    for (var j = 0; j < want.length; j++) {
      if (j < model.count && model.get(j).key === want[j]) continue
      var at = -1
      for (var k = j + 1; k < model.count; k++) {
        if (model.get(k).key === want[j]) { at = k; break }
      }
      if (at >= 0) model.move(at, j, 1)
      else model.insert(j, { key: want[j] })
    }
  }
}
