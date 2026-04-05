//
//  mime.js
//  App
//
//  Created by joker on 2026-04-05.
//


'use strict'

const TYPES = {
  '.html' : 'text/html',
  '.css'  : 'text/css',
  '.js'   : 'application/javascript',
  '.json' : 'application/json',
  '.md'   : 'text/markdown',
  '.mp4'  : 'video/mp4',
  '.mov'  : 'video/quicktime',
  '.webm' : 'video/webm',
  '.mp3'  : 'audio/mpeg',
  '.ogg'  : 'audio/ogg',
  '.wav'  : 'audio/wav',
  '.png'  : 'image/png',
  '.jpg'  : 'image/jpeg',
  '.jpeg' : 'image/jpeg',
  '.gif'  : 'image/gif',
  '.svg'  : 'image/svg+xml',
  '.ico'  : 'image/x-icon',
  '.pdf'  : 'application/pdf',
  '.woff' : 'font/woff',
  '.woff2': 'font/woff2',
}

function mime (path) {
  const ext = path.slice(path.lastIndexOf('.')).toLowerCase()
  return TYPES[ext] || 'application/octet-stream'
}

module.exports = mime