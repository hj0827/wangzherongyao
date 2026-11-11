<#
.SYNOPSIS
    Run a window-requiring Godot render/screenshot tool on a hidden Windows desktop,
    so nothing ever appears on the user's visible desktop.

.DESCRIPTION
    Why this exists:
      godot/tools/*_shot.gd depend on RenderingServer.frame_post_draw, which never
      fires under --headless (the run hangs forever). They therefore need a real
      rendering context, i.e. a real window. Launching them directly pops a game
      window on the user's desktop - even at 1x1 moved to 5200,3200 there is a
      visible flash during create/destroy, and the user works on this same machine.

    How it works:
      CreateDesktop() makes a desktop that is not the visible session desktop and
      starts Godot on it. The window is still created, OpenGL still initialises,
      screenshots are identical - but they land on a desktop nobody is looking at.
      Output paths are unchanged (godot/shots/*.png).

.PARAMETER Script
    The res:// tool script, e.g. tools/ui_shot.gd or tools/skill_fx_shot.gd.

.PARAMETER ToolArgs
    Extra arguments forwarded to the Godot script, written directly after the
    script path. Do NOT put a `--` separator in between: Windows PowerShell
    treats a bare `--` as an ambiguous parameter name and aborts.

.PARAMETER TimeoutSec
    Timeout, default 300 seconds. On timeout the whole process tree is killed.

.PARAMETER LogFile
    Where to write the Godot stdout/stderr. Defaults to .tmp/offscreen_<name>_<hhmmss>.log.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\ui_shot.gd

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 tools\unit_attack_shot.gd --fixed-fps 30

.NOTES
    Plain Windows PowerShell 5.1 is enough; no Godot editor needed.
    Requires Add-Type (FullLanguage). Under ConstrainedLanguage the script aborts
    with a clear error instead of silently falling back to a visible window.
    This file is deliberately ASCII-only so it parses identically under any
    console code page.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Script,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ToolArgs,

    [int]$TimeoutSec = 300,

    [string]$LogFile
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------- paths
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$godotDir = Join-Path $repoRoot 'godot'
$shotsDir = Join-Path $godotDir 'shots'
$tmpDir = Join-Path $repoRoot '.tmp'

if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir | Out-Null }
if (-not (Test-Path $shotsDir)) { New-Item -ItemType Directory -Path $shotsDir | Out-Null }

# ---------------------------------------------------------------- godot binary
$candidates = @(
    'D:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe',
    'D:\Software\Godot\Godot_v4.7-stable_win64_console.exe',
    'D:\Tools\Godot\Godot_v4.7.2-stable_win64.exe',
    'D:\Software\Godot\Godot_v4.7-stable_win64.exe'
)
$godotExe = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $godotExe) {
    Write-Error "Godot executable not found. Checked: $($candidates -join '; ')"
    exit 1
}

# accept tools/ui_shot.gd, res://tools/ui_shot.gd or an absolute path
$scriptRes = $Script
if ($scriptRes -notmatch '^res://') {
    if (Test-Path $Script) {
        $abs = (Resolve-Path $Script).Path
    } else {
        $abs = Join-Path $godotDir $Script
    }
    if (-not (Test-Path $abs)) { Write-Error "Script not found: $Script"; exit 1 }
    $scriptRes = 'res://' + ($abs.Substring($godotDir.Length + 1) -replace '\\', '/')
}

if (-not $LogFile) {
    $sym = [IO.Path]::GetFileNameWithoutExtension($scriptRes)
    $LogFile = Join-Path $tmpDir ("offscreen_{0}_{1}.log" -f $sym, (Get-Date -Format 'HHmmss'))
}

# ---------------------------------------------------------------- hidden desktop API
if (-not ('DshOffscreenDesktop' -as [type])) {
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public class DshOffscreenDesktop {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern IntPtr CreateDesktopW(string name, IntPtr dev, IntPtr dm, int flags, uint access, IntPtr sa);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool CloseDesktop(IntPtr h);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb;
        [MarshalAs(UnmanagedType.LPWStr)] public string lpReserved;
        [MarshalAs(UnmanagedType.LPWStr)] public string lpDesktop;
        [MarshalAs(UnmanagedType.LPWStr)] public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION {
        public IntPtr hProcess, hThread;
        public int dwProcessId, dwThreadId;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool CreateProcessW(
        string lpApplicationName, string lpCommandLine, IntPtr lpProcessAttributes,
        IntPtr lpThreadAttributes, bool bInheritHandles, int dwCreationFlags,
        IntPtr lpEnvironment, string lpCurrentDirectory,
        ref STARTUPINFO si, out PROCESS_INFORMATION pi);

    [DllImport("kernel32.dll")] public static extern uint WaitForSingleObject(IntPtr h, uint ms);
    [DllImport("kernel32.dll")] public static extern bool GetExitCodeProcess(IntPtr h, out uint code);
    [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] public static extern bool TerminateProcess(IntPtr h, uint code);

    const int CREATE_NO_WINDOW = 0x08000000;
    const uint DESKTOP_ALL_ACCESS = 0x01FF | 0x10000000;
    const int STARTF_USESHOWWINDOW = 0x00000001;
    const short SW_HIDE = 0;

    // Run one command line synchronously on a fresh hidden desktop. Returns the exit code.
    public static int RunOnHiddenDesktop(string desktopName, string commandLine, string workingDir,
                                         int timeoutMs, out string error) {
        error = "";
        IntPtr desk = CreateDesktopW(desktopName, IntPtr.Zero, IntPtr.Zero, 0, DESKTOP_ALL_ACCESS, IntPtr.Zero);
        if (desk == IntPtr.Zero) {
            error = "CreateDesktop failed, Win32 error " + Marshal.GetLastWin32Error();
            return -1;
        }
        try {
            STARTUPINFO si = new STARTUPINFO();
            si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
            si.lpDesktop = desktopName;
            si.dwFlags = STARTF_USESHOWWINDOW;
            si.wShowWindow = SW_HIDE;

            PROCESS_INFORMATION pi;
            bool ok = CreateProcessW(null, commandLine, IntPtr.Zero, IntPtr.Zero, false,
                                     CREATE_NO_WINDOW, IntPtr.Zero, workingDir, ref si, out pi);
            if (!ok) {
                error = "CreateProcess failed, Win32 error " + Marshal.GetLastWin32Error();
                return -2;
            }
            try {
                uint wait = WaitForSingleObject(pi.hProcess, (uint)timeoutMs);
                if (wait != 0) {
                    error = "Timed out after " + (timeoutMs / 1000) + "s, killed";
                    TerminateProcess(pi.hProcess, 124);
                    return 124;
                }
                uint code;
                GetExitCodeProcess(pi.hProcess, out code);
                return (int)code;
            } finally {
                CloseHandle(pi.hThread);
                CloseHandle(pi.hProcess);
            }
        } finally {
            CloseDesktop(desk);
        }
    }
}
'@ -ErrorAction Stop
    } catch {
        Write-Error ("Cannot load the hidden-desktop API (PowerShell language mode is probably ConstrainedLanguage). " +
                     "This script refuses to degrade into a visible window. Re-run under FullLanguage: " +
                     "powershell -ExecutionPolicy Bypass -File godot\tools\shot_offscreen.ps1 $Script . " +
                     "Underlying error: $_")
        exit 2
    }
}

# ---------------------------------------------------------------- build command line
function Get-Quoted([string]$value) {
    if ($value -eq '') { return '""' }
    if ($value -match '[\s"]') { return '"' + ($value -replace '"', '\"') + '"' }
    return $value
}

$parts = New-Object System.Collections.Generic.List[string]
$parts.Add((Get-Quoted $godotExe))
$parts.Add('--path')
$parts.Add((Get-Quoted $godotDir))
$parts.Add('--audio-driver')
$parts.Add('Dummy')
$parts.Add('--script')
$parts.Add((Get-Quoted $scriptRes))
if ($ToolArgs) {
    foreach ($a in $ToolArgs) { $parts.Add((Get-Quoted $a)) }
}

$inner = ($parts -join ' ') + ' > ' + (Get-Quoted $LogFile) + ' 2>&1'
# the outer pair of quotes keeps the redirect bound to the whole command
$cmdLine = 'cmd.exe /c "' + $inner + '"'

$desktopName = 'dsh-offscreen-' + [guid]::NewGuid().ToString('N').Substring(0, 12)

Write-Host "[offscreen] script   : $scriptRes"
Write-Host "[offscreen] godot    : $godotExe"
Write-Host "[offscreen] desktop  : $desktopName (hidden)"
Write-Host "[offscreen] command  : $inner"
Write-Host "[offscreen] log      : $LogFile"

# ---------------------------------------------------------------- baseline of outputs
$before = @{}
Get-ChildItem $shotsDir -Filter *.png -ErrorAction SilentlyContinue | ForEach-Object {
    $before[$_.FullName] = $_.LastWriteTimeUtc
}

# ---------------------------------------------------------------- run
$err = ''
$sw = [Diagnostics.Stopwatch]::StartNew()
$exitCode = [DshOffscreenDesktop]::RunOnHiddenDesktop($desktopName, $cmdLine, $repoRoot, ($TimeoutSec * 1000), ([ref]$err))
$sw.Stop()

if ($err) { Write-Host "[offscreen] error    : $err" -ForegroundColor Yellow }

# ---------------------------------------------------------------- echo interesting log lines
if (Test-Path $LogFile) {
    $log = Get-Content $LogFile
    $interesting = $log | Where-Object {
        $_ -match 'SHOT|SHEET|capture|PASS|FAIL|ERROR|WARNING|SCRIPT ERROR|done'
    }
    if ($interesting) {
        Write-Host "[offscreen] log tail :"
        $interesting | Select-Object -Last 40 | ForEach-Object { Write-Host "    $_" }
    } else {
        Write-Host "[offscreen] log tail : (no matching lines, see the full log path above)"
    }
}

# ---------------------------------------------------------------- report outputs
$changed = @()
Get-ChildItem $shotsDir -Filter *.png -ErrorAction SilentlyContinue | ForEach-Object {
    $prev = $before[$_.FullName]
    if (-not $prev -or $_.LastWriteTimeUtc -gt $prev) { $changed += $_ }
}
if ($changed.Count -gt 0) {
    Write-Host "[offscreen] new/updated png: $($changed.Count) (newest 5)"
    $changed | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object {
        Write-Host ("    {0}  {1} KB" -f $_.Name, [math]::Round($_.Length / 1KB, 1))
    }
} else {
    Write-Host "[offscreen] new/updated png: 0 (the script probably never reached its save step, check the log)" -ForegroundColor Yellow
}

Write-Host ("[offscreen] exit {0} in {1:N1}s" -f $exitCode, $sw.Elapsed.TotalSeconds)
if ($exitCode -ne 0) { exit $exitCode }
