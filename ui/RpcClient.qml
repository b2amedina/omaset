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
  property bool reaping: false
  property bool reapFailed: false
  property int reapRetryCount: 0
  property int maxReapRetries: 10
  // The worker runs under `setsid`, so its PID is a session leader (SID == PID).
  // Backend commands stay in that session even when GNU timeout moves them into
  // their own process group (timeout calls setpgid(0,0)), so cleanup signals the
  // whole session rather than a single process group.
  property int workerPid: 0
  readonly property string reapScript:
    'pkill -TERM -s "$1" 2>/dev/null; i=0; ' +
    'while pkill -0 -s "$1" 2>/dev/null && [ $i -lt 30 ]; do sleep 0.1; i=$((i+1)); done; ' +
    'pkill -KILL -s "$1" 2>/dev/null; ' +
    'for i in 1 2 3 4 5; do pkill -0 -s "$1" 2>/dev/null || exit 0; sleep 0.05; done; ' +
    'exit 1'

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
    if (reaping) return
    if (restarting && !reapFailed) return
    restarting = true
    started = false
    reapFailed = false
    reapRetryCount = 0
    reap()
  }

  // Stop the old worker session (TERM, then KILL after a grace period) and wait
  // for it to empty before a replacement can start. Runs once at a time.
  function reap() {
    if (reaping) return
    if (workerPid <= 0) {
      finishReap()
      return
    }
    reaping = true
    reaper.launched = false
    reaper.command = ["sh", "-c", reapScript, "sh", String(workerPid)]
    reaper.running = true
  }

  // The old worker and everything in its session are gone (or there was nothing
  // to reap). Clear the recorded PID and, if this was a deliberate restart,
  // start the replacement. A crash (restarting === false) does not auto-restart.
  function finishReap() {
    reaping = false
    reapFailed = false
    reapRetryCount = 0
    workerPid = 0
    if (restarting) {
      restarting = false
      proc.running = true
    }
  }

  // Cleanup did not confirm the old session is empty. Retain workerPid (the old
  // session identity) and do NOT start a replacement; retry until confirmed.
  function failReap() {
    if (!reaping) return
    reaping = false
    reapFailed = true
    console.warn("omaset rpc: cleanup failed; worker session not confirmed empty")
    if (reapRetryCount < maxReapRetries) {
      reapRetryCount += 1
      reapRetry.stop()
      reapRetry.start()
    } else {
      console.warn("omaset rpc: giving up on cleanup after " + maxReapRetries + " retries")
    }
  }

  Process {
    id: reaper
    running: false
    property bool launched: false

    onStarted: reaper.launched = true

    onExited: function(code) {
      if (code !== 0) {
        console.warn("omaset rpc: cleanup exited " + code)
        root.failReap()
      } else {
        root.finishReap()
      }
    }

    // quickshell 0.3.2 has no `errorOccurred` on Process; a cleanup process
    // that cannot even launch flips `running` back to false without emitting
    // `started`, so settle here instead of leaving `restarting` armed forever.
    onRunningChanged: {
      if (!reaper.running && !reaper.launched && root.reaping)
        root.failReap()
    }
  }

  Process {
    id: proc
    command: root.binary !== "" ? ["setsid", root.binary, "rpc"] : []
    running: false
    stdinEnabled: true

    onStarted: {
      root.started = true
      root.workerPid = proc.processId
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
      root.started = false
      root.failAll("omaset rpc exited (" + code + ")", code)
      root.reap()
    }

    // quickshell 0.3.2 has no `errorOccurred` signal on Process. A failed
    // start flips `running` back to false without ever emitting `started` or
    // `exited`, so this is the only place that can settle the pre-start queue.
    // A restart's own exit is not a failed start, so it is skipped here.
    onRunningChanged: {
      if (!proc.running && !root.started && !root.restarting) {
        root.failAll("omaset rpc failed to start", -1)
      }
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.started
    onTriggered: root.expire()
  }

  Timer {
    id: reapRetry
    interval: 1000
    repeat: false
    onTriggered: if (root.reapFailed) root.reap()
  }

  Component.onCompleted: {
    if (root.binary !== "") proc.running = true
  }
}
