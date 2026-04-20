//
//  open.js
//  App
//
//  Created by Janardhan on 2026-04-18.
//


'use strict'

const { errorBuf } = require('../utils/encode')

// CMD 4: open(key)
// Pre-warms a drive session — swarm flush + drive.update().
// Called by Swift before the first fetch for a key.
// On repeat calls returns instantly (session already ready).

module.exports = async function open (req, getSession) {
  let key

  try {
    key = JSON.parse(req.data).key
  } catch {
    return req.reply(errorBuf('open: bad json'))
  }

  try {
    const session = getSession(key)
    await session.waitReady()
    req.reply(Buffer.from(JSON.stringify({ ok: true })))
  } catch (err) {
    req.reply(errorBuf(err.message))
  }
}