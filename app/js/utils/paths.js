//
//  paths.js
//  App
//
//  Created by joker on 2026-04-05.
//


'use strict'

// Resolve a URL path to ordered candidate drive paths.
//   /          → [/index.html]
//   /about/    → [/about/index.html]
//   /style.css → [/style.css]
//   /about     → [/about, /about.html, /about/index.html]

function resolvePaths (raw) {
  const path = raw || '/'

  if (path === '/' || path.endsWith('/')) {
    return [path === '/' ? '/index.html' : path + 'index.html']
  }

  const last = path.split('/').pop() || ''
  if (last.includes('.')) return [path]

  return [path, path + '.html', path + '/index.html']
}

module.exports = resolvePaths