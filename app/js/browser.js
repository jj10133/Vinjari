//
//  HyperBrowser.swift
//  App
//
//  Created by joker on 2026-04-05.
//


'use strict'

const RPC        = require('bare-rpc')
const Hyperswarm = require('hyperswarm')
const Hyperdrive = require('hyperdrive')
const Hyperbee   = require('hyperbee')
const Corestore  = require('corestore')
const b4a        = require('b4a')
const { EventEmitter }      = require('bare-events')
const { decode: decodeKey } = require('hypercore-id-encoding')

const DriveSession = require('./session')
const cmdFetch     = require('./commands/fetch')
const cmdReaddir   = require('./commands/readdir')
const cmdWrite     = require('./commands/write')
const cmdInfo      = require('./commands/info')
const cmdOpen      = require('./commands/open')

// ─── Command IDs — must match RPCClient.swift ─────────────────────────────────

const CMD_FETCH   = 0
const CMD_READDIR = 1
const CMD_WRITE   = 2
const CMD_INFO    = 3
const CMD_OPEN    = 4

// ─── HyperBrowser ─────────────────────────────────────────────────────────────

class HyperBrowser extends EventEmitter {
  constructor (storePath) {
    super()
    this.store    = new Corestore(storePath)
    this.swarm    = new Hyperswarm()
    this.sessions = new Map()
    this.cache    = null
    this.rpc      = new RPC(BareKit.IPC, (req) => this._onrequest(req))
    this._boot()
  }

  async _boot () {
    await this.store.ready()
    this.swarm.on('connection', (conn) => this.store.replicate(conn))

    // Hyperbee session cache — tracks drives seen this session
    const cacheCore = this.store.get({ name: 'session-cache' })
    this.cache = new Hyperbee(cacheCore, {
      keyEncoding  : 'utf-8',
      valueEncoding: 'json',
    })
    await this.cache.ready()

    console.log('[HyperBrowser] booted')
    this.emit('ready')
  }

  // ─── Session management ───────────────────────────────────────────────────
  // Returns a DriveSession instantly — drive opens and swarm join
  // happen in background via DriveSession._setup()

  session (rawKey) {
    const keyBuf = decodeKey(rawKey)
    const hexKey = b4a.toString(keyBuf, 'hex')

    if (this.sessions.has(hexKey)) {
      return this.sessions.get(hexKey)
    }

    const drive   = new Hyperdrive(this.store, keyBuf)
    const session = new DriveSession(drive, this.swarm)

    // Persist to session cache non-blocking
    session.once('ready', async () => {
      try {
        const existing = await this.cache.get(hexKey)
        await this.cache.put(hexKey, {
          firstSeen: existing?.value?.firstSeen ?? Date.now(),
          lastSeen : Date.now(),
          version  : drive.version,
          writable : drive.writable,
        })
      } catch {}
    })

    session.on('update', async ({ version }) => {
      try {
        const existing = await this.cache.get(hexKey)
        if (existing) {
          await this.cache.put(hexKey, { ...existing.value, lastSeen: Date.now(), version })
        }
      } catch {}
    })

    this.sessions.set(hexKey, session)
    return session
  }

  // ─── Request router ───────────────────────────────────────────────────────

  _onrequest (req) {
    const get = (key) => this.session(key)

    switch (req.command) {
      case CMD_FETCH:   cmdFetch(req, get);                break
      case CMD_READDIR: cmdReaddir(req, get);              break
      case CMD_WRITE:   cmdWrite(req, get);                break
      case CMD_INFO:    cmdInfo(req, get, this.cache);     break
      case CMD_OPEN:    cmdOpen(req, get);                break
      default:
        req.reply(Buffer.from(JSON.stringify({ error: 'unknown command: ' + req.command })))
    }
  }
}

module.exports = HyperBrowser
