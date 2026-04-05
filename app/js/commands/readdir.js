//
//  readdir.js
//  App
//
//  Created by joker on 2026-04-05.
//


'use strict'

const { errorBuf } = require('../utils/encode')

module.exports = async function readdir (req, getSession) {
  let key, dirPath

  try {
    const body = JSON.parse(req.data)
    key     = body.key
    dirPath = body.path || '/'
  } catch {
    return req.reply(errorBuf('readdir: bad json'))
  }

  try {
    const { drive } = getSession(key)
    const entries   = []

    for await (const entry of drive.list(dirPath)) {
      const name = entry.key.slice(dirPath === '/' ? 1 : dirPath.length + 1)
      if (!name || name.includes('/')) continue
      entries.push({
        name,
        path       : (dirPath === '/' ? '' : dirPath) + '/' + name,
        isDirectory: false,
        size       : entry.value?.blob?.byteLength ?? 0,
        mtime      : entry.value?.metadata?.mtime  ?? null,
      })
    }

    req.reply(Buffer.from(JSON.stringify({ entries })))
  } catch (err) {
    req.reply(errorBuf(err.message))
  }
}