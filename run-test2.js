const { spawn } = require('child_process');
const qemu = spawn('C:\\Program Files\\qemu\\qemu-system-x86_64.exe', [
  '-cdrom', 'build/fides-os-committed.iso', '-m', '256',
  '-serial', 'file:build/serial-committed2.log',
  '-no-reboot', '-display', 'none', '-monitor', 'none'
], { stdio: ['pipe', 'pipe', 'pipe'] });
qemu.stderr.on('data', (d) => process.stderr.write(d));
setTimeout(() => { qemu.kill(); }, 8000);
qemu.on('close', () => { console.log('QEMU exited'); });
