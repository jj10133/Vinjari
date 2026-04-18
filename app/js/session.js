'use strict'

const EventEmitter = require('bare-events')

const OPEN_TIMEOUT_MS = 30000

class DriveSession extends EventEmitter {
  constructor (drive, swarm) {
    super()
    this.drive   = drive
    this.swarm   = swarm
    this.peers   = 0
    this.ready   = false
    this._readyP = this._open()
  }

  async _open () {
    await this.drive.ready()

    if (this.drive.writable) {
      this.swarm.join(this.drive.discoveryKey)
      this.ready = true
      return
    }

    // Join and wait for swarm to fully flush — ensures replication
    // handshake completes before we attempt any block requests
    const joined = this.swarm.join(this.drive.discoveryKey)
    await joined.flushed()
    console.log('[session] swarm flushed, connections:', this.swarm.connections.size)

    // Pull trie root from peers
    await this.drive.update()
    console.log('[session] drive updated, version:', this.drive.version)

    this.peers = this.swarm.connections.size
    this.ready = true

    // Continue tracking peers
    this.swarm.on('connection', () => {
      this.peers = this.swarm.connections.size
      this.emit('peer', { peers: this.peers })
    })

    this.swarm.on('disconnection', () => {
      this.peers = this.swarm.connections.size
      this.emit('peer', { peers: this.peers })
    })

    this.drive.core.on('append', () => {
      this.emit('update', { version: this.drive.version })
    })
  }

  waitReady (timeout = OPEN_TIMEOUT_MS) {
    if (this.ready) return Promise.resolve()
    return new Promise((resolve, reject) => {
      const t = setTimeout(
        () => reject(new Error('drive open timeout after ' + timeout + 'ms')),
        timeout
      )
      this._readyP
        .then(() => { clearTimeout(t); resolve() })
        .catch((err) => { clearTimeout(t); reject(err) })
    })
  }
}

module.exports = DriveSession
