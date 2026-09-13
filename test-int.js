const { spawn } = require('child_process');
const QEMU = 'C:\\Program Files\\qemu\\qemu-system-x86_64.exe';
const qemu = spawn(QEMU, [
  '-cdrom', 'build/fides-os-new.iso', '-m', '256',
  '-smp', '2',
  '-netdev', 'user,id=net0',
  '-device', 'e1000,netdev=net0',
  '-serial', 'file:build/serial-mmio.log',
  '-no-reboot', '-display', 'none', '-monitor', 'stdio',
  '-d', 'int'
], { stdio: ['pipe', 'pipe', 'pipe'] });
const cmds = [
  'sendkey h','sendkey e','sendkey l','sendkey p','sendkey ret',
  'sendkey p','sendkey i','sendkey n','sendkey g','sendkey ret',
];
let i = 0;
function send() {
  if (i < cmds.length) { qemu.stdin.write(cmds[i] + '\n'); i++; setTimeout(send, 500); }
  else { setTimeout(() => { qemu.kill(); }, 5000); }
}
setTimeout(send, 5000);
qemu.stderr.on('data', (d) => { process.stderr.write(d); });
qemu.on('close', () => { process.exit(0); });
