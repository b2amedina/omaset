import QtQuick
import Quickshell.Io

// Persistent `omaset rpc` client. Requests are newline-delimited JSON-RPC 2.0
// and responses are matched by id, so several UI operations can be in flight
// without spawning a process per call. Calls made before the process has
// started are queued and flushed on start.
Item {
  id: root

  property string binary: ""
  property var pending: ({})
  property var outbox: []
  property int nextId: 1
  property bool started: false

  function pendingCount() {
    var n = outbox.length
    for (var k in pending) n++
    return n
  }

  function send(method, params, cb) {
    var id = nextId
    nextId += 1
    if (cb) {
      var p = pending
      p[id] = cb
      pending = p
    }
    var req = { jsonrpc: "2.0", id: id, method: method }
    if (params !== undefined && params !== null) req.params = params
    proc.write(JSON.stringify(req) + "\n")
    return id
  }

  function call(method, params, cb) {
    if (!started) {
      outbox.push({ method: method, params: params, cb: cb })
      return -1
    }
    return send(method, params, cb)
  }

  function flush() {
    var q = outbox
    outbox = []
    for (var i = 0; i < q.length; i++) send(q[i].method, q[i].params, q[i].cb)
  }

  function failAll(message, code) {
    var q = outbox
    outbox = []
    for (var i = 0; i < q.length; i++)
      if (q[i].cb) q[i].cb(null, message, code)
    var p = pending
    pending = ({})
    for (var id in p) p[id](null, message, code)
  }

  Process {
    id: proc
    command: root.binary !== "" ? [root.binary, "rpc"] : []
    running: root.binary !== ""
    stdinEnabled: true

    onStarted: {
      root.started = true
      root.flush()
    }

    stdout: SplitParser {
      onRead: function(line) {
        if (!line || line.length === 0) return
        var msg
        try { msg = JSON.parse(line) } catch (e) {
          console.warn("omaset rpc: invalid response: " + line)
          return
        }
        if (!msg || msg.id === undefined || msg.id === null) return
        var cb = root.pending[msg.id]
        if (!cb) return
        var p = root.pending
        delete p[msg.id]
        root.pending = p
        if (msg.error)
          cb(null, String(msg.error.message || "rpc error"), Number(msg.error.code || -1))
        else
          cb(msg.result, "", 0)
      }
    }

    stderr: SplitParser {
      onRead: function(line) {
        if (line && line.length > 0) console.warn("omaset rpc: " + line)
      }
    }

    onExited: function(code) {
      root.started = false
      root.failAll("omaset rpc exited (" + code + ")", code)
    }
  }
}
