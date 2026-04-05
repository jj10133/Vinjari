//
//  DriveSession.swift
//  App
//
//  Created by joker on 2026-04-05.
//


'use strict'

const EventEmitter = require('bare-events')

// DriveSession — one per drive key.
// Opens immediately, replicates in background.
// Emits: 'ready', 'peer', 'update'

class DriveSession extends EventEmitter {
  constructor (drive, swarm) {
    super()
    this.drive = drive
    this.swarm = swarm
    this.peers = 0
    this.ready = false
    this._setup()
  }

  _setup () {
    this.drive.ready().then(() => {
      this.ready = true
      this.emit('ready')

      // Join swarm in background — never blocks fetch
      this.swarm.join(this.drive.discoveryKey)

      // Watch for new content from drive owner
      if (!this.drive.writable) {
        this.drive.core.on('append', () => {
          this.emit('update', { version: this.drive.version })
        })
      }
    })

    // Peer count tracking
    this.swarm.on('connection', () => {
      this.peers = this.swarm.connections.size
      this.emit('peer', { peers: this.peers })
    })

    this.swarm.on('disconnection', () => {
      this.peers = this.swarm.connections.size
      this.emit('peer', { peers: this.peers })
    })
  }

  // Wait for drive to be locally ready — fast, no network required
  waitReady (timeout = 5000) {
    if (this.ready) return Promise.resolve()
    return new Promise((resolve, reject) => {
      const t = setTimeout(() => reject(new Error('drive open timeout')), timeout)
      this.once('ready', () => { clearTimeout(t); resolve() })
    })
  }
}

module.exports = DriveSession