// run-qemu-kernel.js — Run QEMU with -kernel flag (ELF file)
const { spawn } = require('child_process');
const fs = require('fs');

const elf = process.argv[2];
const timeout = parseInt(process.argv[3] || '10000');

const qemu = spawn('C:/Program Files/qemu/qemu-system-x86_64.exe', [
  '-kernel', elf,
  '-m', '256',
  '-serial', 'file:build/serial-kernel.log',
  '-no-reboot', '-display', 'none'
], { stdio: ['pipe', 'pipe', 'pipe'] });

qemu.stderr.on('data', d => process.stderr.write('[QEMU] ' + d));
qemu.stdout.on('data', d => process.stdout.write(d));

setTimeout(() => {
  qemu.kill();
  setTimeout(() => {
    try {
      const log = fs.readFileSync('build/serial-kernel.log', 'utf8');
      console.log('---SERIAL OUTPUT---');
      console.log(log.substring(0, 2000));
    } catch(e) {
      console.log('No serial log:', e.message);
    }
    process.exit(0);
  }, 1000);
}, timeout);
