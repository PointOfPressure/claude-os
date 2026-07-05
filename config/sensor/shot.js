#!/usr/bin/env node
// shot.js — screenshot a URL with headless Chromium, print the output path.
// Deployed to /opt/playwright/shot.js; invoked via /usr/local/bin/shot.
'use strict';

function usage() {
  console.error('usage: shot <url> [out.png] [--full] [--width N] [--height N] [--wait MS]');
  process.exit(2);
}

async function main() {
  const args = process.argv.slice(2);
  let url = null;
  let out = null;
  let full = false;
  let width = 1280;
  let height = 800;
  let wait = 0;

  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--full') full = true;
    else if (a === '--width') width = parseInt(args[++i], 10);
    else if (a === '--height') height = parseInt(args[++i], 10);
    else if (a === '--wait') wait = parseInt(args[++i], 10);
    else if (a.startsWith('--')) usage();
    else if (!url) url = a;
    else if (!out) out = a;
    else usage();
  }
  if (!url) usage();
  if (!/^[a-z]+:/i.test(url)) url = 'http://' + url;
  if (!out) out = `/tmp/shot-${Date.now()}.png`;

  const { chromium } = require('playwright');
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ viewport: { width, height } });
    await page.goto(url, { waitUntil: 'load', timeout: 30000 });
    if (wait > 0) await page.waitForTimeout(wait);
    await page.screenshot({ path: out, fullPage: full });
  } finally {
    await browser.close();
  }
  console.log(out);
}

main().catch((e) => {
  console.error('shot: ' + (e && e.message ? e.message.split('\n')[0] : String(e)));
  process.exit(1);
});
