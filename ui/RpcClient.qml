import QtQuick
import Quickshell.Io

// Persistent `omaset rpc` client. Requests are newline-delimited JSON-RPC 2.0
// and responses are matched by id, so several UI operations can be in flight
// without spawning a process per call. Calls made before the process has
// started are queued (up to `maxQueued`) and flushed on start.
//
// This client's deadline is a watchdog, not a cancellation of in-flight Lua:
// if a request is still unanswered after `timeoutMs` it is rejected and the
// worker is restarted (never replayed), so a wedged engine cannot leave the
// panel stuck with a pending write. The backend's own `run_capture` bound is
// what interrupts a stuck subprocess; this watchdog only stops waiting on it.
Item {
  id: root

  property string binary: ""
  property int timeoutMs: 40000
  property int maxQueued: 256
  property var pending: ({})
  property var pendingAt: ({})
  property var outbox: []
  property int nextId: 1
  property bool started: false
  property bool restarting: false

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
      var a = pendingAt
      a[id] = Date.now()
      pendingAt = a
    }
    var req = { jsonrpc: "2.0", id: id, method: method }
    if (params !== undefined && params !== null) req.params = params
    proc.write(JSON.stringify(req) + "\n")
    return id
  }

  function call(method, params, cb) {
    if (!started) {
      if (outbox.length >= maxQueued) {
        if (cb) cb(null, "omaset rpc worker not started; queue full", -1)
        return -1
      }
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
    pendingAt = ({})
    for (var id in p) p[id](null, message, code)
  }

  // Reject requests that have outlived the deadline and restart the worker
  // rather than wait for it or replay the uncertain write.
  function expire() {
    var now = Date.now()
    var expired = []
    for (var id in pendingAt)
      if (now - pendingAt[id] >= timeoutMs) expired.push(id)
    if (expired.length === 0) return
    for (var i = 0; i < expired.length; i++) {
      var id = expired[i]
      var cb = pending[id]
      delete pendingAt[id]
      if (cb) {
        delete pending[id]
        cb(null, "request timed out", -1)
      }
    }
    restart()
  }

  function restart() {
    if (restarting) return
    restarting = true
    started = false
    proc.running = false
    killTimer.start()
  }

  Process {
    id: proc
    command: root.binary !== "" ? [root.binary, "rpc"] : []
    running: false
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
        var a = root.pendingAt
        delete a[msg.id]
        root.pendingAt = a
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
      killTimer.stop()
      root.started = false
      root.failAll("omaset rpc exited (" + code + ")", code)
      if (root.restarting) {
        root.restarting = false
        proc.running = true
      }
    }

    // A failed start emits neither `started` nor `exited`, so settle queued
    // work here (and drop any restart flag) instead of leaving it stuck.
    onErrorOccurred: function(error) {
      if (root.started) return
      killTimer.stop()
      root.failAll("omaset rpc failed to start (" + error + ")", error)
      root.restarting = false
    }
  }

  // Escalation for a worker that ignores SIGTERM: kill it hard after a grace
  // period so onExited can settle and a replacement can start.
  Timer {
    id: killTimer
    interval: 3000
    repeat: false
    onTriggered: {
      if (proc.running) proc.signal(9)
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.started
    onTriggered: root.expire()
  }

  Component.onCompleted: {
    if (root.binary !== "") proc.running = true
  }
}
