'use strict'

const RPC        = require('bare-rpc')
const Hyperswarm = require('hyperswarm')
const Hyperdrive = require('hyperdrive')
const Corestore  = require('corestore')
const b4a        = require('b4a')
const{ decode: decodeKey } = require('hypercore-id-encoding')

// Commands — must match RPCClient.swift Command enum
const CMD_FETCH   = 0
const CMD_READDIR = 1
const CMD_WRITE   = 2
const CMD_INFO    = 3

// ─── HyperBrowser ─────────────────────────────────────────────────────────────

class HyperBrowser {
  constructor () {
    this.store  = new Corestore('/tmp/hyper-browser')
    this.swarm  = new Hyperswarm()
    this.drives = new Map()
    this.rpc    = new RPC(BareKit.IPC, (req) => this._onrequest(req))
    this.opened = this._open()
  }

  async _open () {
    await this.store.ready()
    this.swarm.on('connection', (conn) => this.store.replicate(conn))
  }

  // ─── Drive cache ────────────────────────────────────────────────────────────
  // Each drive opened once. Concurrent requests for the same key
  // await the same `opening` promise — no duplicate open() calls.

  async _drive (rawKey) {
    await this.opened

    // Accepts 64-char hex or 52-char z-base-32 — normalise to hex for cache key
    const keyBuf = decodeKey(rawKey)
    const hexKey = b4a.toString(keyBuf, 'hex')

    if (this.drives.has(hexKey)) {
      const { drive, opening } = this.drives.get(hexKey)
      await opening
      return drive
    }

    const drive   = new Hyperdrive(this.store, keyBuf)
    const opening = drive.ready().then(() => {
      this.swarm.join(drive.discoveryKey)
      return this.swarm.flush()
    })

    this.drives.set(hexKey, { drive, opening })
    await opening
    return drive
  }

  // ─── Request router ─────────────────────────────────────────────────────────

  _onrequest (req) {
    switch (req.command) {
      case CMD_FETCH:   this._fetch(req);   break
      case CMD_READDIR: this._readdir(req); break
      case CMD_WRITE:   this._write(req);   break
      case CMD_INFO:    this._info(req);    break
      default:
        req.reply(errorBuf('unknown command: ' + req.command))
  
    }
  }

  // ─── CMD 0: fetch ────────────────────────────────────────────────────────────

  async _fetch (req) {
    let key, rawPath, headers

    try {
      const body = JSON.parse(req.data)
      key     = body.key
      rawPath = body.path || '/'
      headers = body.headers || {}
    } catch {
      req.reply(errorBuf('fetch: bad json'))

      return
    }

    // Path resolution — try candidates in order until one exists in the drive:
    //   /          → [/index.html]
    //   /about/    → [/about/index.html]
    //   /x.html    → [/x.html]
    //   /about     → [/about, /about.html, /about/index.html]

    const candidates = resolvePaths(rawPath)
    let replied = false

    try {
      const drive = await this._drive(key)

      let entry    = null
      let filePath = candidates[0]

      for (const candidate of candidates) {
        const e = await drive.entry(candidate)
        if (e?.value?.blob?.byteLength) {
          entry    = e
          filePath = candidate
          break
        }
      }

      if (!entry) {
        req.reply(errorBuf('fetch: not found ' + rawPath))
  
        return
      }

      const total = entry.value.blob.byteLength
      const range = parseRange(headers.Range || headers.range, total)
      const start = range ? range.start : 0
      const end   = range ? range.end   : total - 1

      const meta = {
        statusCode: range ? 206 : 200,
        headers: {
          'Content-Type'  : mime(filePath),
          'Content-Length': String(end - start + 1),
          'Accept-Ranges' : 'bytes',
          'Cache-Control' : 'no-store',
        }
      }

      if (range) {
        meta.headers['Content-Range'] = `bytes ${start}-${end}/${total}`
      }

      const chunks = []
      for await (const chunk of drive.createReadStream(filePath, { start, end })) {
        chunks.push(chunk)
      }

      replied = true
      req.reply(encodeReply(meta, Buffer.concat(chunks)))

    } catch (err) {
      if (!replied) {
        req.reply(errorBuf(err.message))
  
      }
    }
  }

  // ─── CMD 1: readdir ──────────────────────────────────────────────────────────

  async _readdir (req) {
    let key, dirPath

    try {
      const body = JSON.parse(req.data)
      key     = body.key
      dirPath = body.path || '/'
    } catch {
      req.reply(errorBuf('readdir: bad json'))

      return
    }

    try {
      const drive   = await this._drive(key)
      const entries = []

      for await (const entry of drive.list(dirPath)) {
        const name = entry.key.slice(dirPath === '/' ? 1 : dirPath.length + 1)
        if (!name || name.includes('/')) continue
        entries.push({
          name,
          path       : (dirPath === '/' ? '' : dirPath) + '/' + name,
          isDirectory: false,
          size       : entry.value?.blob?.byteLength ?? 0,
          mtime      : entry.value?.metadata?.mtime ?? null,
        })
      }

      req.reply(Buffer.from(JSON.stringify({ entries })))

    } catch (err) {
      req.reply(errorBuf(err.message))

    }
  }

  // ─── CMD 2: write ────────────────────────────────────────────────────────────

  async _write (req) {
    let key, filePath, data

    try {
      const body = JSON.parse(req.data)
      key      = body.key
      filePath = body.path
      data     = body.data
    } catch {
      req.reply(errorBuf('write: bad json'))

      return
    }

    try {
      const drive = await this._drive(key)
      await drive.put(filePath, Buffer.from(data, 'base64'))
      req.reply(Buffer.from(JSON.stringify({ ok: true })))

    } catch (err) {
      req.reply(errorBuf(err.message))

    }
  }

  // ─── CMD 3: info ─────────────────────────────────────────────────────────────

  async _info (req) {
    let key

    try {
      key = JSON.parse(req.data).key
    } catch {
      req.reply(errorBuf('info: bad json'))

      return
    }

    try {
      const drive = await this._drive(key)
      req.reply(Buffer.from(JSON.stringify({
        key,
        version : drive.version,
        writable: drive.writable,
        peers   : this.swarm.connections.size,
      })))

    } catch (err) {
      req.reply(errorBuf(err.message))

    }
  }
}

// ─── Path resolution ──────────────────────────────────────────────────────────

function resolvePaths (raw) {
  const path = raw || '/'

  // Root or trailing slash → index
  if (path === '/' || path.endsWith('/')) {
    return [path.endsWith('/') ? path + 'index.html' : '/index.html']
  }

  // Has a file extension → exact match only
  const last = path.split('/').pop() || ''
  if (last.includes('.')) {
    return [path]
  }

  // Extensionless — try three candidates
  return [path, path + '.html', path + '/index.html']
}

// ─── Module helpers ───────────────────────────────────────────────────────────

function errorBuf (message) {
  return Buffer.from(JSON.stringify({ error: message }))
}

function encodeReply (meta, body) {
  const header = Buffer.from(JSON.stringify(meta))
  const len    = Buffer.allocUnsafe(4)
  len.writeUInt32BE(header.length, 0)
  return Buffer.concat([len, header, body])
}

function parseRange (header, total) {
  if (!header) return null
  const m = header.match(/bytes=(\d+)-(\d*)/)
  if (!m) return null
  const start = parseInt(m[1], 10)
  const end   = m[2] ? Math.min(parseInt(m[2], 10), total - 1) : total - 1
  return start > end ? null : { start, end }
}

const MIME = {
  '.html': 'text/html',  '.css': 'text/css',
  '.js'  : 'application/javascript', '.json': 'application/json',
  '.md'  : 'text/markdown', '.mp4': 'video/mp4', '.mov': 'video/quicktime',
  '.webm': 'video/webm', '.mp3': 'audio/mpeg',  '.ogg': 'audio/ogg',
  '.wav' : 'audio/wav',  '.png': 'image/png',   '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg', '.gif': 'image/gif',   '.svg': 'image/svg+xml',
  '.ico' : 'image/x-icon', '.pdf': 'application/pdf',
  '.woff': 'font/woff',  '.woff2': 'font/woff2',
}

function mime (path) {
  return MIME[path.slice(path.lastIndexOf('.')).toLowerCase()] || 'application/octet-stream'
}

// ─── Boot ─────────────────────────────────────────────────────────────────────

module.exports = new HyperBrowser()
