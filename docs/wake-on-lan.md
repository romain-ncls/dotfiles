# Wake-on-LAN on menadion

Work in progress on the branch `feat/wol-link`. The short version is in
`docs/decisions.md` (Hardware → Wake-on-LAN); this file keeps the whole
investigation, the tests to run at home and the plan to fix `igc`.

## Where it stands (2026-11-17)

- menadion's network card: Intel I225-V (`8086:15f3`, 2.5G), driver `igc`.
- Wake-on-LAN works after a shutdown from Windows, never after a suspend,
  hibernate or poweroff from Linux.
- **After a Linux poweroff the card has no link at all.** Freebox OS →
  Réseau local → Switch, menadion off:

  | port | | link | mode |
  |---|---|---|---|
  | Ethernet 1 (1G + power) | free | Inactif | |
  | Ethernet 2 (1G) | the TV, in standby | Actif | 10BaseT-HD, no MAC learned |
  | Ethernet 3 (2.5G) | menadion | **Inactif** | |

  So the magic packet has nothing to arrive on, whoever sends it. The port
  mapping (menadion on the 2.5G port, the TV beside it) is from memory: to
  confirm. The TV kept a minimal link while asleep, which is also why it
  didn't answer pings.
- USB wake works, but nothing at home can make a USB event remotely today.
- On trial on this branch: a udev `.link` file arming Wake-on-LAN at boot
  (below).

## Already ruled out

- Linux arms the card: NetworkManager `ethernet.wake-on-lan=magic`, `ethtool`
  shows `Wake-on: g`.
- The card and its root port are ACPI wake sources; the DSDT path (`_PRW` →
  GPE 0x69, S4) has nothing OS-dependent.
- Link speed forced to 10/100, `d3cold_allowed=0`, MSI "Wake Up Event By
  BIOS" + "Resume By PCI-E Device".
- The board: Windows wakes this one, and other boards with the same chip fail
  the same way on Linux (CachyOS and Proxmox reports, below).
- The card's dark port LEDs mean nothing (`igc`'s `led_suspend` turns them
  off), but the Freebox's port status does: the link is really down.

## Sending the magic packet

- From outside, the WireGuard tunnel to home carries no broadcast: the packet
  has to come from inside the home network. The Freebox can send it: the
  Freebox Connect app (device → wake), or Freebox OS at http://192.168.1.254
  over the VPN. The home server could too (wandersail's key isn't authorized
  on it yet).
- The Freebox lists menadion twice: `menadion.home` (192.168.1.157) and
  `menadion1.home` (192.168.1.102). Check both MACs: probably Linux and
  Windows registering separately, but if they differ, one isn't the wired
  card (Wi-Fi?) and a wake sent to it can never work.

## Trial: the `.link` file

`hosts/menadion/system/etc/systemd/network/10-wake-on-lan.link` sets
`WakeOnLan=magic` from udev as soon as the card appears, on top of
NetworkManager. A CachyOS user with the same card reported that it made the
card wake; nobody else confirmed it, and on paper it is the same ethtool call
NetworkManager makes. Cheap to try. Only the first matching `.link` file
applies, so it replaces `99-default.link` for the card and copies systemd's
naming policies: the interface name must not change.

At home:

1. On menadion, get the branch. If `~/dotfiles` is on `main` and clean:
   `git fetch && git switch feat/wol-link`; otherwise cherry-pick its commit.
2. `lds apply`, then reboot: udev reads `.link` files only when the device
   appears.
3. Check: `ip -br link` (same interface name as before),
   `udevadm info /sys/class/net/<if> | grep ID_NET_LINK_FILE` (→
   `10-wake-on-lan.link`), `ethtool <if> | grep Wake-on` (→ `g`).
4. `poweroff`, then Freebox OS → Switch. Port 3 **Actif**: it helped, send a
   wake from the Freebox. **Inactif**: it didn't; drop the `.link` file and
   go to the `igc` hunt.

## Tests at home, in order

1. **Port mapping.** With both on, the Switch page lists the MACs seen on each
   port: confirm menadion is on port 3.
2. **Control, from Windows.** Shut down from Windows: port 3 should stay
   Actif (note its mode); then wake it from the Freebox. If port 3 goes
   Inactif after Windows too, the explanation above is wrong.
3. **Linux poweroff with the `.link`** (above).
4. **Linux suspend** (`systemctl suspend`): port 3? Suspend and poweroff go
   through the same driver function, and suspend is much faster to iterate.
5. **RTC alarm as a safety net.** `sudo rtcwake -m off -s 180` must power it
   back on after 3 minutes (`-m mem` for suspend). Needed so automated tries
   never leave it off.
6. **Freebox API token.** Request one (`POST /api/v16/login/authorize/`; the
   version is in http://192.168.1.254/api_version) and approve it on the box
   side, then check which permission `GET /api/v16/switch/status/` needs.
   With it, a script on wandersail reads port 3 without anyone looking at
   the page.

## Finding the bug in `igc`

Why it's within reach: Windows wakes the same hardware, so it's software.
Intel's I225 datasheet is public (wake-up registers WUC, WUFC, WUS; PHY power
management). Suspend and poweroff both go through `__igc_shutdown` in
`drivers/net/ethernet/intel/igc/igc_main.c`.

Leads, to verify in the source of menadion's kernel:

- The driver doesn't switch off the cable side on purpose: the PHY
  power-down write in `igc_power_down_phy_copper` is disabled (2023
  intel-wired-lan thread, below). So the chip drops the link itself when it
  sleeps; a chip like this keeps it only when told to wake on something.
- `__igc_shutdown` seems to write `IGC_WUC = IGC_WUC_PME_EN`, overwriting the
  whole wake-control register. That would clear APM wake (`APME`) if the
  firmware or Windows had set it. First thing to check.
- The PHY's power settings for sleep states (low-power link-up, 1G/2.5G
  disabled in D3), EEE, `PME_En` in the PCI config space.

Method:

1. Build `igc` out of tree from the source of menadion's kernel, as a local
   package of the repo (`modules/<tool>/pkg`, like logi-smartshift):
   installed, it replaces the in-kernel module; removed, the stock one is back.
2. Log CTRL, WUC, WUFC, PHPM and the PHY control registers in
   `__igc_shutdown` (dmesg; or read BAR0 from
   `/sys/bus/pci/devices/<addr>/resource0` as root).
3. One change per try: set the RTC alarm, suspend or poweroff, read port 3
   from wandersail through the Freebox API, let the alarm bring menadion back,
   next. Port 3 Actif after a Linux shutdown = found; then the wake test.
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
  works from Windows, not Linux; later, a `.link` file reportedly fixed it.
- [Proxmox: WoL not working on NUC 12 with I225-V](https://forum.proxmox.com/threads/wol-not-working-on-intel-nuc-12-nuc12wski7-with-i225-v-nic-under-proxmox.184101/):
  Linux seems to cut the card's power at shutdown; Windows keeps the link LED on.
- [intel-wired-lan: igc driver doesn't power down the PHY when link is brought down](https://lore.kernel.org/all/Y926GPvm0f544ogG@wantstofly.org/T/)
- [FreeBSD: Wake-on-LAN not working on igc, I226-V](https://forums.freebsd.org/threads/wake-on-lan-not-working-on-igc-driver-nic-intel-i226-v.94598/post-667925)
  and [FreeBSD bug 282140](https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=282140)
