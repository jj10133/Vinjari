'use strict'

const { errorBuf, encodeReply, parseRange } = require('../utils/encode')
const resolvePaths = require('../utils/paths')
const mime         = require('../utils/mime')

module.exports = async function fetch (req, getSession) {
  let key, rawPath, headers

  try {
    const body = JSON.parse(req.data)
    key     = body.key
    rawPath = body.path || '/'
    headers = body.headers || {}
  } catch {
    return req.reply(errorBuf('fetch: bad json'))
  }

  try {
    const session = getSession(key)
    await session.waitReady()

    const { drive } = session
    const candidates = resolvePaths(rawPath)

    let entry    = null
    let filePath = candidates[0]

    for (const candidate of candidates) {
      // drive.entry() queries the trie locally — fast but may miss
      // trie nodes not yet replicated on first visit.
      // drive.get() forces full trie path resolution from peers if needed.
      const e = drive.writable
        ? await drive.entry(candidate)
        : await drive.entry(candidate, { wait: true })

      if (e?.value?.blob?.byteLength) {
        entry    = e
        filePath = candidate
        break
      }
    }

    if (!entry) {
      return req.reply(errorBuf('fetch: not found ' + rawPath))
    }

    const total = entry.value.blob.byteLength
    const range = parseRange(headers.Range || headers.range, total)
    const start = range ? range.start : 0
    const end   = range ? range.end   : total - 1

    const meta = {
      statusCode: range ? 206 : 200,
      headers: {
        'Content-Type'               : mime(filePath),
        'Content-Length'             : String(end - start + 1),
        'Accept-Ranges'              : 'bytes',
        'Cache-Control'              : 'no-store',
        'Access-Control-Allow-Origin': '*',
      }
    }

    if (range) {
      meta.headers['Content-Range'] = `bytes ${start}-${end}/${total}`
    }

    const chunks = []
    for await (const chunk of drive.createReadStream(filePath, { start, end })) {
      chunks.push(chunk)
    }

    req.reply(encodeReply(meta, Buffer.concat(chunks)))

  } catch (err) {
    req.reply(errorBuf(err.message))
  }
}
