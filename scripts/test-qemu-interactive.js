// test-qemu-interactive.js — Run QEMU with stdin pipe, send commands, capture output
// Usage: node test-qemu-interactive.js <iso-path> <cmd1> [cmd2] ... [timeout-ms]
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');

// Resolve paths relative to repo root (parent of scripts/)
const ROOT = path.resolve(__dirname, '..');
const BUILD = path.join(ROOT, 'build');

const iso = process.argv[2];
const commands = process.argv.slice(3);
const timeout = parseInt(process.argv[process.argv.length - 1].match(/^\d+$/) ? process.argv[process.argv.length - 1] : '15000');
const serialLog = path.join(BUILD, 'serial-interactive.log');

const qemu = spawn('C:/Program Files/qemu/qemu-system-x86_64.exe', [
  '-cdrom', iso,
  '-m', '256',
  '-serial', 'file:' + serialLog,
  '-no-reboot', '-display', 'none'
], { stdio: ['pipe', 'pipe', 'pipe'] });

qemu.stderr.on('data', d => process.stderr.write('[QEMU] ' + d));

let output = '';
let cmdIdx = 0;
let lastOutputTime = Date.now();
let waitingForBoot = true;

// Poll the serial log file for output
const pollInterval = setInterval(() => {
  try {
    const log = fs.readFileSync(serialLog, 'utf8');
    if (log.length > output.length) {
      output = log;
      lastOutputTime = Date.now();
      
      // If we see the shell prompt and haven't sent commands yet
      if (waitingForBoot && output.includes('> ')) {
        waitingForBoot = false;
        // Send first command after a short delay
        setTimeout(() => {
          if (cmdIdx < commands.length && !commands[cmdIdx].match(/^\d+$/)) {
            qemu.stdin.write(commands[cmdIdx] + '\n');
            cmdIdx++;
          }
        }, 500);
      }
      
      // If we see a prompt after sending a command, send next command
      if (!waitingForBoot && cmdIdx < commands.length) {
        const cmd = commands[cmdIdx];
        if (cmd.match(/^\d+$/)) return; // skip timeout args
        // Check if prompt appeared after last command
        const promptCount = (output.match(/> /g) || []).length;
        if (promptCount > cmdIdx) {
          setTimeout(() => {
            qemu.stdin.write(commands[cmdIdx] + '\n');
            cmdIdx++;
          }, 300);
        }
      }
    }
  } catch(e) {}
}, 200);

setTimeout(() => {
  clearInterval(pollInterval);
  qemu.kill();
  setTimeout(() => {
    try {
      const log = fs.readFileSync(serialLog, 'utf8');
      console.log('---SERIAL OUTPUT---');
      console.log(log.substring(0, 4000));
    } catch(e) {
      console.log('No serial log');
    }
    process.exit(0);
  }, 1000);
}, timeout);
