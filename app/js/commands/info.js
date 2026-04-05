//
//  info.js
//  App
//
//  Created by joker on 2026-04-05.
//


'use strict'

const { errorBuf } = require('../utils/encode')

module.exports = async function write (req, getSession) {
  let key, filePath, data

  try {
    const body = JSON.parse(req.data)
    key      = body.key
    filePath = body.path
    data     = body.data
  } catch {
    return req.reply(errorBuf('write: bad json'))
  }

  try {
    const { drive } = getSession(key)
    await drive.put(filePath, Buffer.from(data, 'base64'))
    req.reply(Buffer.from(JSON.stringify({ ok: true })))
  } catch (err) {
    req.reply(errorBuf(err.message))
  }
}