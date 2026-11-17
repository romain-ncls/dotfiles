# Wake-on-LAN on menadion

Work in progress on the branch `feat/wol-link`. The short version is in
`docs/decisions.md` (Hardware → Wake-on-LAN); this file keeps the whole
investigation, the tests to run at home and the plan to fix `igc`.

## Where it stands (2026-11-17)

- menadion's network card: Intel I225-V (`8086:15f3`, 2.5G), driver `igc`,
  interface `enp4s0`, MAC `d8:bb:c1:8a:38:87`, PCI `0000:04:00.0`.
- Wake-on-LAN never works after a suspend, hibernate or poweroff from Linux.
  From Windows: the link stays up after a hibernate (below); whether a magic
  packet then wakes it, and what a Windows shutdown does, are still to test.
- **Linux drops the link, Windows keeps it.** Freebox OS → Réseau local →
  Switch: menadion is on port 3 (Ethernet 3, 2.5G; its MAC is learned
  there). In the same sleep state, S4:

  | menadion | port 3 | card's port LEDs |
  |---|---|---|
  | hibernated from Windows | Actif | on |
  | hibernated or powered off from Linux | **Inactif** | off |

  With no link, the magic packet has nothing to arrive on, whoever sends it.
  Same hardware, firmware and sleep state: the difference is software, most
  likely `igc` (or what Linux's PCI code does around it).
- The TV, on port 2, keeps a minimal link in standby (10BaseT-HD, no MAC
  learned), which is also why it doesn't answer pings.
- USB wake works, but nothing at home can make a USB event remotely today.

## Already ruled out

- Linux arms the card: NetworkManager `ethernet.wake-on-lan=magic`, `ethtool`
  shows `Wake-on: g`.
- The card and its root port are ACPI wake sources (PCI `power/wakeup`
  enabled on both); the DSDT path (`_PRW` → GPE 0x69, S4) has nothing
  OS-dependent.
- Link speed forced to 10/100, `d3cold_allowed=0`, MSI "Wake Up Event By
  BIOS" + "Resume By PCI-E Device".
- The board: Windows keeps this one's link up in S4, and other boards with the same chip fail
  the same way on Linux (CachyOS and Proxmox reports, below).
- udev arming it too: a `.link` file matching `Driver=igc` with
  `WakeOnLan=magic`, which a CachyOS user with the same card said made it
  wake. Tried 2026-11-17 on kernel 7.3.4: udev applied it
  (`ID_NET_LINK_FILE`), port 3 still Inactif after a hibernate and after a
  poweroff. Removed. On paper it is the same ethtool call NetworkManager
  makes.
- The port LEDs are not misleading (an earlier note blamed `igc`'s
  `led_suspend`): they follow the link, off after Linux, on after Windows.

## Sending the magic packet

- From outside, the WireGuard tunnel to home carries no broadcast: the packet
  has to come from inside the home network. The Freebox can send it: the
  Freebox Connect app (device → wake), or Freebox OS at http://192.168.1.254
  over the VPN. The home server could too (wandersail's key isn't authorized
  on it yet).
- The Freebox lists menadion twice: `menadion.home` (192.168.1.157) and
  `menadion1.home` (192.168.1.102). Wake the one with the wired card's MAC,
  `d8:bb:c1:8a:38:87`; the other is probably Windows registering separately,
  or the Wi-Fi.

## Next test: what Windows leaves in the card's registers

The wake registers (WUC, WUFC, WUS…) should survive a reboot: the card keeps
them on standby power so it can report why it woke. `igc` resets them when it
loads, so boot once with `igc` blacklisted and read them before anything
touches them. Done after a Windows hibernate and after a Linux poweroff
(same driver function as a Linux hibernate), it shows what Windows sets that
Linux doesn't. Self-check: after the Linux
poweroff WUFC must read `0x2` (magic packet, set by `igc`); if it reads 0,
the registers don't survive and the method fails.

The reader is a throwaway Python script, not in the repo
(`~/wol-test/igc-regs.py`): it maps BAR0 through
`/sys/bus/pci/devices/0000:04:00.0/resource0` (root; kernel lockdown is off),
turns on the device's memory decoding if nothing has, and prints CTRL,
STATUS, CTRL_EXT, LEDCTL, PHPM, EEER, IPCNFG, WUC, WUFC, WUS, MANC, the MAC
filter and the PCI power-management state. If the investigation goes on, it
moves into the repo with the `igc` package.

Windows **hibernates** (`shutdown /h`): it is the one state where it is seen
to keep the link, so its registers are the good reference; a Windows shutdown
isn't known to keep the link. Linux then boots under a hibernated Windows, as
after any hibernate: the `ntfs` driver mounts C: read-only. The ESP they share
stays writable, so avoid `lds upgrade` (kernels go to `/boot`) until Windows
has resumed once.

1. Check the reader with `igc` loaded:
   `sudo python3 -I ~/wol-test/igc-regs.py --live` (RAL0/RAH0 must spell the
   card's MAC).
2. `echo 'blacklist igc' | sudo tee /etc/modprobe.d/zz-wol-test.conf`.
   `igc` isn't in the initramfs, so no rebuild; `sudo modprobe igc` still
   loads it by hand.
3. Windows: boot it (it resumes if hibernated), hibernate it
   (`shutdown /h`), check port 3 is Actif. Power on, boot Linux (no network
   now):
   `sudo python3 -I ~/wol-test/igc-regs.py | tee ~/wol-test/1-windows.txt`.
4. Linux: `sudo modprobe igc`, wait for the network (NetworkManager arms
   Wake-on-LAN when it connects), `poweroff`, note port 3. Power on:
   `sudo python3 -I ~/wol-test/igc-regs.py | tee ~/wol-test/2-linux.txt`.
5. Clean up: `sudo rm /etc/modprobe.d/zz-wol-test.conf && sudo modprobe igc`.

## Tests at home

Done (2026-11-17): port mapping (menadion is on port 3); Windows hibernate
keeps port 3 Actif, Linux hibernate and poweroff don't; the `.link` file
changes nothing.

Still to do, in order:

1. **Windows registers vs Linux registers**, with a Windows hibernate
   (above).
2. **Windows, the wake itself.** Hibernated from Windows, does a magic packet
   from the Freebox wake it? And after a Windows shutdown, is port 3 still
   Actif? Not needed for the `igc` hunt; tells what to expect of a fix.
3. **Linux suspend** (`systemctl suspend`): port 3? Suspend and poweroff go
   through the same driver function, and suspend is much faster to iterate.
4. **RTC alarm as a safety net.** `sudo rtcwake -m off -s 180` must power it
   back on after 3 minutes (`-m mem` for suspend). Needed so automated tries
   never leave it off.
5. **Freebox API token.** Request one (`POST /api/v16/login/authorize/`; the
   version is in http://192.168.1.254/api_version) and approve it on the box
   side, then check which permission `GET /api/v16/switch/status/` needs.
   With it, a script on wandersail reads port 3 without anyone looking at
   the page.

## Finding the bug in `igc`

Why it's within reach: Windows keeps the link on the same hardware in the
same sleep state, so it's software. Intel's I225 datasheet is public
(wake-up registers WUC, WUFC, WUS; PHY power management).

What the source of kernel 7.3.4 says (`drivers/net/ethernet/intel/igc/`):

- `__igc_shutdown` (`igc_main.c`) runs for suspend, hibernate (it is also
  the `.poweroff` callback) and poweroff. With Wake-on-LAN armed it does
  **not** power the PHY down: it resets it and restarts autonegotiation
  (`igc_power_up_link`). The power-down write (`MII_CR_POWER_DOWN` in
  `igc_power_down_phy_copper`) is active in this kernel (the 2023 thread
  below found it disabled), but it is only taken when nothing should wake
  the machine. So the driver doesn't cut the link on purpose: the link drops
  after it hands the card back (`igc_release_hw_control`, then
  `pci_disable_device` and D3).
- It writes `IGC_WUC = IGC_WUC_PME_EN`, overwriting the whole wake-control
  register, which clears APM wake (`APME`) if the firmware or Windows had set
  it. `igb` does exactly the same and I210 cards wake, so not proven to be it.
- **Main lead:** it never writes `PHPM` (PHY power management, `0x0E14`); it
  only reads it while waiting for a PHY reset to finish. That register
  decides what the PHY does outside D0 (low-power link-up, speeds allowed,
  link disconnect), so it stays at its reset value. Windows' "Reduce link
  speed during standby" and "Wake on Magic Packet from power off state"
  settings probably write there or in WUC; the register comparison above
  should show it.
- Still to check: EEE, `PME_En` in the PCI config space at the moment of
  sleep.

Method:

1. Build `igc` out of tree from the source of menadion's kernel, as a local
   package of the repo (`modules/<tool>/pkg`, like logi-smartshift):
   installed, it replaces the in-kernel module; removed, the stock one is back.
2. Log CTRL, WUC, WUFC, PHPM and the PHY control registers in
   `__igc_shutdown` (dmesg).
3. One change per try, starting with what the register comparison shows
   (Windows' PHPM and WUC values): set the RTC alarm, suspend or poweroff,
   read port 3 from wandersail through the Freebox API, let the alarm bring
   menadion back, next. Port 3 Actif after a Linux shutdown = found; then the
   wake test.
4. Last resort: compare with what the Windows driver does (disassembly, as
   done for Options+).

Even without a fix, a precise report (registers, port status, Windows vs
Linux) to intel-wired-lan is useful to Intel's maintainers.

## Publishing a fix

- First as our local package, so menadion has it at once.
- Upstream: a patch to `intel-wired-lan@lists.osuosl.org` (Intel's `igc`
  maintainers), `netdev` in copy. Romain sends it under his name with
  `Signed-off-by:` (DCO: a human certifies it) and must be able to defend it
  in review. Check the kernel's current rules on disclosing AI help (an
  `Assisted-by:`-style tag) before sending. A `Fixes:` tag gets it into stable
  kernels. Expect weeks to months.

## If there is no fix: other ways to wake it remotely

- A smart plug, with the BIOS set to power on when power comes back (MSI:
  Settings → Advanced → Power Management Setup → Restore after AC Power
  Loss = Power On): turning the plug off and on boots it. The easiest.
- An ESP32, or a Pi Zero acting as a USB keyboard, on a USB port, sending a
  key on request over the network (USB wake works).
- A relay on the motherboard's power-button pins, driven by a small board on
  Wi-Fi.
- A second network card whose Wake-on-LAN works on Linux.

## Sources

- [CachyOS: WOL on Intel I225-V (Rev 03)](https://discuss.cachyos.org/t/wol-on-intel-i225-v-rev-03/10013):
  works from Windows, not Linux; later, a `.link` file reportedly fixed it
  (not here).
- [Proxmox: WoL not working on NUC 12 with I225-V](https://forum.proxmox.com/threads/wol-not-working-on-intel-nuc-12-nuc12wski7-with-i225-v-nic-under-proxmox.184101/):
  Linux seems to cut the card's power at shutdown; Windows keeps the link LED on.
- [intel-wired-lan: igc driver doesn't power down the PHY when link is brought down](https://lore.kernel.org/all/Y926GPvm0f544ogG@wantstofly.org/T/)
- [FreeBSD: Wake-on-LAN not working on igc, I226-V](https://forums.freebsd.org/threads/wake-on-lan-not-working-on-igc-driver-nic-intel-i226-v.94598/post-667925)
  and [FreeBSD bug 282140](https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=282140)
