@echo off
REM run-qemu.bat — Boot Fides OS in QEMU on Windows
REM
REM Requirements:
REM   - QEMU for Windows (https://qemu.org/download/#windows)
REM   - The fides-os.iso file (build with: make iso on Linux, or download from releases)
REM
REM Usage:
REM   run-qemu.bat
REM   run-qemu.bat path\to\fides-os.iso

REM Resolve repo root (parent of scripts/)
set ROOT=%~dp0..

set ISO=%~1
if "%ISO%"=="" set ISO=%ROOT%\build\fides-os.iso

if not exist "%ISO%" (
    echo Error: ISO file not found: %ISO%
    echo Build it first with: make iso
    echo Or download from: https://github.com/pledgeandgrow/p-lang/releases
    exit /b 1
)

echo Launching Fides OS in QEMU...
echo ISO: %ISO%
echo.

qemu-system-x86_64 -cdrom "%ISO%" -m 256 -serial stdio -no-reboot -no-shutdown

echo.
echo QEMU exited.
