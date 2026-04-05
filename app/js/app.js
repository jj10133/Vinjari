'use strict'

const HyperBrowser = require('./browser')

// Store in /tmp — session only, wiped on reboot by design.
// Users are browsing, not storing.
const browser = new HyperBrowser('/tmp/hyper-browser')

module.exports = browser
