//
//  encode.js
//  App
//
//  Created by joker on 2026-04-05.
//


'use strict'

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

module.exports = { errorBuf, encodeReply, parseRange }