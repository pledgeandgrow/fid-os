// run-qemu-debug.js — Run QEMU with interrupt logging
const { spawn } = require('child_process');
const fs = require('fs');

const iso = process.argv[2] || 'build/fides-os-patched.iso';
const timeout = parseInt(process.argv[3] || '12000');

const qemu = spawn('C:/Program Files/qemu/qemu-system-x86_64.exe', [
  '-cdrom', iso,
  '-m', '256',
  '-serial', 'file:build/serial-debug.log',
  '-d', 'int',
  '-no-reboot', '-display', 'none'
], { stdio: ['pipe', 'pipe', 'pipe'] });

let stderr = '';
qemu.stderr.on('data', d => { stderr += d.toString(); });
qemu.stdout.on('data', d => process.stdout.write(d));

setTimeout(() => {
  qemu.kill();
  setTimeout(() => {
    try {
      const log = fs.readFileSync('build/serial-debug.log', 'utf8');
      console.log('---SERIAL OUTPUT---');
      console.log(log.substring(0, 2000));
    } catch(e) {
      console.log('No serial log:', e.message);
    }
    // Show last 50 lines of QEMU stderr (interrupt log)
    const lines = stderr.split('\n');
    console.log('---QEMU INT LOG (last 30 lines)---');
    console.log(lines.slice(-30).join('\n'));
    process.exit(0);
  }, 1000);
}, timeout);
