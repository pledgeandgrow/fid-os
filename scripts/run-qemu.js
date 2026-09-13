// run-qemu.js — Run QEMU and capture serial output
// Usage: node run-qemu.js [iso-path] [timeout-ms] [extra-qemu-args...]
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

// Resolve paths relative to repo root (parent of scripts/)
const ROOT = path.resolve(__dirname, '..');
const BUILD = path.join(ROOT, 'build');

const iso = process.argv[2] || path.join(BUILD, 'fides-os.iso');
const timeout = parseInt(process.argv[3] || '12000');
const extraArgs = process.argv.slice(4);
const serialLog = path.join(BUILD, 'serial-qemu.log');

const qemu = spawn('C:/Program Files/qemu/qemu-system-x86_64.exe', [
  '-cdrom', iso,
  '-m', '256',
  '-serial', 'file:' + serialLog,
  '-no-reboot', '-display', 'none',
  ...extraArgs
], { stdio: ['pipe', 'pipe', 'pipe'] });

qemu.stderr.on('data', d => process.stderr.write('[QEMU] ' + d));
qemu.stdout.on('data', d => process.stdout.write(d));

setTimeout(() => {
  qemu.kill();
  setTimeout(() => {
    try {
      const log = fs.readFileSync(serialLog, 'utf8');
      console.log('---SERIAL OUTPUT---');
      console.log(log.substring(0, 3000));
    } catch(e) {
      console.log('No serial log:', e.message);
    }
    process.exit(0);
  }, 1000);
}, timeout);
