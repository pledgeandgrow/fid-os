@echo off
REM test-windows.bat — Build and boot Fides OS on Windows with QEMU
REM Usage: test-windows.bat [qemu-path]

setlocal

set QEMU=%1
if "%QEMU%"=="" set "QEMU=C:\Program Files\qemu\qemu-system-x86_64.exe"
set FIDESC=C:\Users\ADMIN\CascadeProjects\fid\p-lang\target\release\fidesc.exe
set ROOT=%~dp0

echo === Fides OS Windows Test ===
echo.

echo [1/4] Compiling modular kernel...
"%FIDESC%" emit kernel\shell.fd --boot -o build\kernel-raw.bin
if errorlevel 1 (
    echo ERROR: Compilation failed
    exit /b 1
)

echo [2/4] Wrapping kernel in ELF...
node make-elf.js build\kernel-raw.bin build\kernel-new.elf 0x100000 0x100018
if errorlevel 1 (
    echo ERROR: ELF wrapping failed
    exit /b 1
)

echo [3/4] Swapping kernel into ISO...
node swap-kernel.js build\fides-os.iso build\kernel-new.elf build\fides-os-new.iso
if errorlevel 1 (
    echo ERROR: ISO swap failed
    exit /b 1
)

echo [4/4] Booting in QEMU...
echo.
echo Serial output will appear below. Press Ctrl+C to stop.
echo.
"%QEMU%" -cdrom build\fides-os-new.iso -m 256 -serial stdio -no-reboot

endlocal
