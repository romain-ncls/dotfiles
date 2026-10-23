# Reboot from Windows into Arch Linux -- once -- without changing the default.
#
# Symmetric with the Linux-side `reboot-to-windows` script: both write the
# Boot Loader Interface variable LoaderEntryOneShot, which Limine consumes on
# the next boot and then forgets. Neither side changes what Limine remembers,
# so hibernating either OS still resumes into that OS on an unattended boot.
#
# Requires administrator rights: writing an EFI variable needs
# SeSystemEnvironmentPrivilege, which is only present in an elevated token.
# The script elevates itself, so the UAC prompt is the confirmation.

# --- the entry name, exactly as Limine publishes it -------------------------
# Limine's entry *id* (from LoaderEntries), not the menu title
$EntryName = 'Arch-Linux.linux'
# ---------------------------------------------------------------------------

$ErrorActionPreference = 'Stop'

function Test-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Re-launch elevated if needed; the UAC prompt doubles as the confirmation.
if (-not (Test-Elevated)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$PSCommandPath`""
    )
    exit
}

Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public static class BootLoaderInterface
{
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool SetFirmwareEnvironmentVariableExW(
        string lpName, string lpGuid, byte[] pValue, int nSize, int dwAttributes);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr hObject);

    [StructLayout(LayoutKind.Sequential)]
    private struct LUID { public uint LowPart; public int HighPart; }

    [StructLayout(LayoutKind.Sequential)]
    private struct LUID_AND_ATTRIBUTES { public LUID Luid; public uint Attributes; }

    [StructLayout(LayoutKind.Sequential)]
    private struct TOKEN_PRIVILEGES { public uint PrivilegeCount; public LUID_AND_ATTRIBUTES Privilege; }

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr ProcessHandle, uint DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern bool LookupPrivilegeValueW(string lpSystemName, string lpName, out LUID lpLuid);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool AdjustTokenPrivileges(IntPtr TokenHandle, bool DisableAll,
        ref TOKEN_PRIVILEGES NewState, uint BufferLength, IntPtr PreviousState, IntPtr ReturnLength);

    private const uint TOKEN_ADJUST_PRIVILEGES = 0x0020;
    private const uint TOKEN_QUERY             = 0x0008;
    private const uint SE_PRIVILEGE_ENABLED    = 0x0002;
    private const int  ERROR_NOT_ALL_ASSIGNED  = 1300;

    // systemd Boot Loader Interface vendor GUID -- Limine implements this too.
    private const string LoaderGuid = "{4a67b082-0a4c-41cf-b6c7-440b29bb8c4f}";

    private const int EFI_VARIABLE_NON_VOLATILE       = 0x01;
    private const int EFI_VARIABLE_BOOTSERVICE_ACCESS = 0x02;
    private const int EFI_VARIABLE_RUNTIME_ACCESS     = 0x04;

    private static void EnablePrivilege()
    {
        IntPtr token;
        if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out token))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "OpenProcessToken failed");
        try
        {
            LUID luid;
            if (!LookupPrivilegeValueW(null, "SeSystemEnvironmentPrivilege", out luid))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "LookupPrivilegeValue failed");

            TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
            tp.PrivilegeCount = 1;
            tp.Privilege.Luid = luid;
            tp.Privilege.Attributes = SE_PRIVILEGE_ENABLED;

            bool ok = AdjustTokenPrivileges(token, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
            int err = Marshal.GetLastWin32Error();
            if (!ok) throw new Win32Exception(err, "AdjustTokenPrivileges failed");
            if (err == ERROR_NOT_ALL_ASSIGNED)
                throw new InvalidOperationException(
                    "SeSystemEnvironmentPrivilege was not granted. Run as administrator.");
        }
        finally { CloseHandle(token); }
    }

    public static void SetOneShot(string entry)
    {
        EnablePrivilege();

        // UTF-16LE, NUL-terminated -- byte-for-byte what systemd writes.
        byte[] value = Encoding.Unicode.GetBytes(entry + "\0");

        if (!SetFirmwareEnvironmentVariableExW(
                "LoaderEntryOneShot", LoaderGuid, value, value.Length,
                EFI_VARIABLE_NON_VOLATILE | EFI_VARIABLE_BOOTSERVICE_ACCESS | EFI_VARIABLE_RUNTIME_ACCESS))
            throw new Win32Exception(Marshal.GetLastWin32Error(),
                "SetFirmwareEnvironmentVariableEx failed (is this a UEFI boot?)");
    }
}
'@

Add-Type -AssemblyName System.Windows.Forms | Out-Null

try {
    [BootLoaderInterface]::SetOneShot($EntryName)
}
catch {
    [System.Windows.Forms.MessageBox]::Show(
        "Could not set the one-shot boot entry.`n`n$($_.Exception.Message)",
        'Reboot into Arch Linux',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}

Restart-Computer -Force
