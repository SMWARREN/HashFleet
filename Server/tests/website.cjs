'use strict';
// The user explicitly rejected a second browser settings product. These checks
// replace the obsolete dashboard behavior tests and guard its old public URLs.
// Original-site behavior is covered by website/src and Tools/browser-acceptance.js.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.join(__dirname, '..');
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');
let checks = 0;
function check(condition, name) { assert.ok(condition, name); checks++; }

const retiredScript = read('public/app.js');
const sideEffects = [];
const forbidden = name => new Proxy(function () {
  sideEffects.push(name);
  throw new Error('Retired endpoint attempted ' + name);
}, {
  get() { sideEffects.push(name); throw new Error('Retired endpoint read ' + name); },
  set() { sideEffects.push(name); throw new Error('Retired endpoint wrote ' + name); },
});
const globals = Object.fromEntries([
  'fetch', 'XMLHttpRequest', 'WebSocket', 'EventSource', 'navigator',
  'document', 'location', 'history', 'localStorage', 'sessionStorage',
  'setTimeout', 'setInterval', 'Notification',
].map(name => [name, forbidden(name)]));
vm.runInNewContext(retiredScript, globals, { timeout: 100 });
check(sideEffects.length === 0, 'Old dashboard JavaScript is inert, with no network, storage, credential, or notification effects');
check(!/installation=|Authorization|Bearer|device_token/.test(retiredScript), 'Old script contains no enrollment or browser credential flow');
check(!/url\s*\(|@import/i.test(read('public/style.css')), 'Retired stylesheet cannot load external resources');
for (const file of ['public/index.html', 'public/companion/index.html']) {
  const html = read(file);
  check(!/<(?:form|input|button|script)\b/i.test(html), file + ' exposes no browser settings or executable script');
  check(/href="\/"/.test(html), file + ' links only back to the existing website');
}
check(/<Files "hashfleet_relay\.py">\s*Require all denied\s*<\/Files>/.test(read('public/.htaccess')),
  'Legacy standalone companion download is denied without deleting unrelated host files');
const original = fs.readFileSync(path.join(root, '../website/src/App.tsx'), 'utf8');
check(!/Connect securely|Manage schedules on|Create LAN companion config/.test(original),
  'Original website source does not promote the rejected notification dashboard');
console.log('PASS: ' + checks + ' retired-endpoint checks. No network access. Original website acceptance is separate.');
