const { spawn } = require('child_process');
const fs = require('fs');
const QEMU = 'C:\\Program Files\\qemu\\qemu-system-x86_64.exe';
const ISO = 'build/fides-os-new.iso';
const qemu = spawn(QEMU, [
  '-cdrom', ISO, '-m', '256',
  '-smp', '2',
  '-netdev', 'user,id=net0',
  '-device', 'e1000,netdev=net0',
  '-object', 'filter-dump,id=net0,file=build/netdump.pcap,netdev=net0',
  '-serial', 'file:build/serial-mmio.log',
  '-no-reboot', '-display', 'none', '-monitor', 'stdio'
], { stdio: ['pipe', 'pipe', 'pipe'] });
const cmds = [
  'sendkey h','sendkey e','sendkey l','sendkey p','sendkey ret',
  'sendkey p','sendkey i','sendkey n','sendkey g','sendkey ret',
  // Test: smp (boot AP) — before net (net crashes)
  'sendkey s','sendkey m','sendkey p','sendkey ret',
  'sendkey n','sendkey e','sendkey t','sendkey ret',
  // Test shell scripting: x=hello  (equal key = =, unshifted)
  'sendkey x','sendkey equal','sendkey h','sendkey e','sendkey l','sendkey l','sendkey o','sendkey ret',
  // Test: echo $x  (shift-4 = $)
  'sendkey e','sendkey c','sendkey h','sendkey o','sendkey spc','sendkey shift-4','sendkey x','sendkey ret',
  // Test: vars
  'sendkey v','sendkey a','sendkey r','sendkey s','sendkey ret',
  // Test: echo foo ; echo bar  (semicolon key = ;)
  'sendkey e','sendkey c','sendkey h','sendkey o','sendkey spc','sendkey f','sendkey o','sendkey o','sendkey semicolon','sendkey spc','sendkey e','sendkey c','sendkey h','sendkey o','sendkey spc','sendkey b','sendkey a','sendkey r','sendkey ret',
  // Test: echo hello | cat  (shift-backslash = |)
  'sendkey e','sendkey c','sendkey h','sendkey o','sendkey spc','sendkey h','sendkey e','sendkey l','sendkey l','sendkey o','sendkey spc','sendkey shift-backslash','sendkey c','sendkey a','sendkey t','sendkey ret',
  // Test: tcp (connect to 10.0.2.2:80)
  'sendkey t','sendkey c','sendkey p','sendkey ret',
  'quit'
];
let i = 0;
function send() {
  if (i >= cmds.length) return;
  const cmd = cmds[i++];
  process.stderr.write(`[SEND] ${cmd}\n`);
  qemu.stdin.write(cmd + '\n');
  const isRet = cmd === 'sendkey ret';
  const isInfo = cmd.startsWith('info') || cmd.startsWith('cpu');
  setTimeout(send, isRet ? 15000 : (isInfo ? 2000 : 700));
}
qemu.stdout.on('data', (d) => { process.stdout.write(d); });
qemu.stderr.on('data', (d) => { process.stderr.write(d); });
qemu.on('close', () => {
  try {
    const s = fs.readFileSync('build/serial-mmio.log', 'utf8');
    const idx = s.indexOf('> help');
    console.log(idx >= 0 ? s.substring(idx) : s);
  } catch(e) { console.log('No serial: ' + e.message); }
});
setTimeout(send, 10000);
