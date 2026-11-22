# Wake-on-LAN on menadion

Work in progress on the branch `feat/wol-link`. The short version is in
`docs/decisions.md` (Hardware → Wake-on-LAN); this file keeps the whole
investigation, the fix and the tests still to run.

## Where it stands (2026-11-22)

- menadion's network card: Intel I225-V (`8086:15f3`, 2.5G), driver `igc`,
  interface `enp4s0`, MAC `d8:bb:c1:8a:38:87`, PCI `0000:04:00.0`.
- **Cause found.** Asleep (D3), the card may only link at 10 Mbit/s: that's
  its NVM default for PHY power management (`PHPM`), and Linux's `igc` never
  changes it. Port 3 of the Freebox (2.5G) doesn't take 10 Mbit/s, so the
  link drops and the magic packet never arrives. Windows' driver allows
  100 Mbit/s in D3 and sleeps on a 100BaseTX link.
- **Proven 2026-11-22:** with that one bit (`DIS_100_D3`) cleared by hand,
  Linux hibernated and a magic packet woke it.
- Next: test the patched `igc` (below), then a local package until the
  patch is upstream.

Freebox OS → Réseau local → Switch, menadion on port 3 (Ethernet 3, 2.5G):

| menadion | port 3 | mode | card's port LEDs |
|---|---|---|---|
| awake, either OS | Actif | 2500BaseT-FD | on |
| hibernated from Windows | Actif | **100BaseTX-FD** | on |
| hibernated or powered off from Linux | **Inactif** | | off |
| hibernated from Linux, `DIS_100_D3` cleared | Actif | | woke on the magic packet |

The TV, on port 2, keeps a minimal link in standby (10BaseT-HD, no MAC
learned), which is also why it doesn't answer pings.

## Already ruled out

- Linux arms the card: NetworkManager `ethernet.wake-on-lan=magic`, `ethtool`
  shows `Wake-on: g`.
- The card and its root port are ACPI wake sources (PCI `power/wakeup`
  enabled on both); the DSDT path (`_PRW` → GPE 0x69, S4) has nothing
  OS-dependent.
- `d3cold_allowed=0`, MSI "Wake Up Event By BIOS" + "Resume By PCI-E
  Device".
- The board: Windows keeps this one's link up in S4, and other boards with
  the same chip fail the same way on Linux (CachyOS and Proxmox reports,
  below).
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
- The packet that woke it on 2026-11-22: a UDP broadcast to port 9 from
  192.168.1.194, the MAC 16 times after 6 × `ff`.

## Register comparison (2026-11-17): no answer, some findings

The idea: boot once with `igc` blacklisted, right after a Windows hibernate
and right after a Linux poweroff, and read what each OS left in the card's
wake registers before `igc` resets them.

The reader is a throwaway Python script, not in the repo
(`~/wol-test/igc-regs.py`). It maps BAR0 through
`/sys/bus/pci/devices/0000:04:00.0/resource0`: root, lockdown is off, and
only while no driver holds the BAR (Arch builds with
`CONFIG_IO_STRICT_DEVMEM`). It prints the PCI power-management state, CTRL,
STATUS, CTRL_EXT, LEDCTL, PHPM, EEER, IPCNFG, WUC, WUFC, WUS, MANC, the MAC
filter and the wake packet buffer (WUPM); `--clear-wake-status` then clears
WUS, `--allow-100-in-d3` clears PHPM's `DIS_100_D3`. Reads have no side
effect except PHPM bit 8 (PHY reset done), cleared when read; harmless.

Result: the two dumps are the same, and WUFC reads 0 after the Linux
poweroff although `igc` writes 2 (magic packet) there: the card reloads its
wake configuration from its NVM when it powers up, so the dumps show the
card's power-on defaults, not what either OS left. Still:

- The card's own default is APM wake on: `WUC = 0x9` (`APME`), the card
  waking the machine by itself through the WAKE# pin. `igc` writes WUC in
  one place only, `__igc_shutdown`, with `PME_EN` (`0x2`), which clears it.
- Without `igc` the card links up by itself (`STATUS` link up, 2.5G).
- **The card keeps its standby power under Linux.** `WUS = MAG` (it saw a
  magic packet at some point) was still there after a Linux poweroff; a
  power loss would have reset it. `igc` clears WUS only on resume.
- WUPL/WUPM only mean something when WUS is set: the buffer otherwise holds
  whatever frame the card last looked at and changes while it is up (an ARP
  request from a Freebox device, `38:07:16:…`, on VLAN 400).
- Power-on values, for later: `CTRL 0x081c0641`, `PHPM 0x00045398`,
  `IPCNFG 0x1`, `EEER 0`, `MANC 0x40000000`.

## Linux sleeping with the card untouched (2026-11-17): link still drops

Booted with `igc` blacklisted (the journal shows no `igc` until after the
test), the card in its power-on state, then `systemctl hibernate`: port 3
**Inactif**. WUS stayed 0 (no packet sent, the link was down).

| sleeping with | card at sleep | port 3 |
|---|---|---|
| Linux + `igc` | D3hot, PME_En 1, WUC `PME_EN`, WUFC `MAG` (from the source) | Inactif |
| Linux, card untouched | D0, PME_En 0, WUC `APME`, WUFC 0, link 2.5G (read) | Inactif |
| Windows | unknown | Actif |

So `igc`'s WUC overwrite is not the whole story: APM wake on doesn't keep
the link either. The card has power under Linux, so it is the card that
turns its link off in sleep, and Windows' driver sets something that neither
the NVM defaults nor `igc` set.

## What Windows' driver does (2026-11-17)

**Hibernated, Windows keeps the link at 100 Mbit/s**: the Freebox shows port 3
in `2500BaseT-FD` while Windows runs, `100BaseTX-FD` once it hibernates. It
renegotiates a slow, low-power link for sleep; under Linux the link is gone
instead.

Its settings (Intel driver 2.1.4.2, 2023-10-03; `Get-NetAdapterAdvancedProperty
-AllProperties`, dump in `C:\Users\nicol\wol-windows.txt`): Wake on Magic
Packet on, Wake on Pattern Match on, Wake on Magic Packet from S5 on, ARP and
NS offload on, speed auto, and hidden `EnablePME=1`, `WakeOnLink=2`,
`EnableModernStandby=1`. No "Reduce Speed On Power Down" or EEE setting is
offered for this card: the slowdown isn't a user setting, the driver does it.

## Linux at 100 Mbit/s before sleeping (2026-11-17): link still drops

`sudo ethtool -s enp4s0 advertise 0x008` (ethtool installed as a trial):
the journal shows the link at 100 Mbps Full from 21:04 until the hibernate
at 21:05, and port 3 still went Inactif. The speed before sleeping isn't it:
what counts is the speed allowed once asleep.

ACPI side, checked meanwhile: `RP02` (root port) and `RP02.PXSX` (the card)
are wake-enabled for S4 in `/proc/acpi/wakeup`. `PXSX` has two power
resources, `WRST` and `DRST`, unused (`resource_in_use 0`) and not in its
wake list: the BIOS's generic template for Wi-Fi modules.

## The cause: asleep, the card may only link at 10 Mbit/s

Intel's shared code (used by FreeBSD's and DPDK's `igc`, not Linux's) names
PHPM's bits (`sys/dev/igc/igc_phy.h` in FreeBSD). The card's power-on value
`0x00045398` decodes as:

| bit | name | meaning | at power-on |
|---|---|---|---|
| `0x0008` | `DIS_1000_D3` | no 1G in D3 | **set** |
| `0x0010` | `LINK_ENERGY` | link energy detect | set |
| `0x0080` | `SPD_B2B_EN` | smart power down | set |
| `0x0100` | `RST_COMPL` | PHY reset done (clears on read) | set |
| `0x0200` | `DIS_100_D3` | no 100M in D3 | **set** |
| `0x1000` | `DIS_2500_D3` | no 2.5G in D3 | **set** |

So in D3 the PHY may only use 10 Mbit/s, and Linux's `igc` never writes
PHPM. Windows sleeps at 100BaseTX: its driver clears `DIS_100_D3`. Intel's
shared code has `igc_set_d3_lplu_state_i225()` for these bits, but
FreeBSD's driver doesn't call it either, and has the same bug.

Both tests of 2026-11-22 confirm it:

- **A. Port 3 doesn't take 10 Mbit/s.** `sudo ethtool -s enp4s0 advertise
  0x003` (10baseT only): no link.
- **B. Allowing 100M in D3 by hand fixes it.** Booted with `igc`
  blacklisted, `igc-regs.py --allow-100-in-d3 --clear-wake-status`
  (PHPM `0x00045298` → `0x00045098`, `~/wol-test/5-allow100.txt`), then
  `systemctl hibernate` at 12:39:32: port 3 stayed Actif, and a magic packet
  woke menadion (resume logged at 12:40:48). Read after the wake
  (`6-after.txt`): `WUS = MAG`, and the wake packet buffer holds the magic
  packet for `d8:bb:c1:8a:38:87`. PHPM was back at `0x00045398`: the card
  reloads it from its NVM at every power-up and reset.

That test woke through the card's own APM wake, with no driver. With `igc`,
the same bit has to be cleared by the driver itself: `igc` resets the card
while going down (`__igc_close` → `igc_down` → `igc_reset` → `CTRL.RST`,
which reloads the NVM defaults), so a write from userspace before sleeping
would be undone.

## The fix

In `__igc_shutdown` (`igc_main.c`), the function for suspend, hibernate and
poweroff, clear `DIS_100_D3` when the card stays armed, after
`igc_power_up_link`:

```c
	wake = wufc || adapter->en_mng_pt;
	if (!wake) {
		igc_power_down_phy_copper_base(&adapter->hw);
	} else {
		igc_power_up_link(adapter);
		/* The NVM default only allows a 10 Mb/s link in D3. A link
		 * partner without 10BASE-T then drops the link and the wake
		 * packet never arrives. Allow 100 Mb/s, as the Windows driver
		 * does.
		 */
		wr32(IGC_I225_PHPM,
		     rd32(IGC_I225_PHPM) & ~IGC_I225_PHPM_DIS_100_D3);
	}
```

plus `#define IGC_I225_PHPM_DIS_100_D3 0x0200` in `igc_defines.h`. Only the
100M bit, as Windows does: 1G and 2.5G stay off in D3 (lower standby power).
Nothing to undo on resume: `igc_resume` resets the card, which reloads the
NVM value.

Built out of tree against menadion's kernel (`linux-headers` 7.3.4.arch1-2),
from the stable v7.3.4 source of `drivers/net/ethernet/intel/igc` (Arch's
kernel patch doesn't touch `igc`; built unpatched, every function has the
same size as in Arch's module): `~/wol-test/igc-7.3.4-wol/igc.ko`, patch in
`~/wol-test/igc-allow-100-in-d3.patch`.

### Test C: the patched module (no reboot)

1. `sudo modprobe -r igc && sudo insmod ~/wol-test/igc-7.3.4-wol/igc.ko`
2. Check it's ours: `cat /sys/module/igc/taint` prints `OE` (out of tree,
   unsigned; Arch's module prints nothing). Then `sudo ethtool enp4s0 | grep
   Wake-on` shows `g` once NetworkManager has brought the connection up.
3. `systemctl hibernate`, then Freebox: port 3 and its mode (expected:
   Actif, `100BaseTX-FD`).
4. Wake it as in B. After the resume the patched module is still the one
   loaded (it's in the hibernation image).
5. Then the same with `systemctl poweroff` (same driver function, through
   `igc_shutdown`): port 3, then wake.

Nothing to clean up: the next boot loads Arch's `igc` again. To go back
without rebooting: `sudo rmmod igc && sudo modprobe igc`.

## Then

1. **Local package until it's upstream.** A DKMS package of the repo
   (`modules/igc-wol/pkg`: `igc`'s source + the patch; DKMS is already here
   for `nvidia-open-dkms`). DKMS rebuilds it for each kernel and installs it
   under `updates/`, which wins over Arch's module. The source is pinned to
   one kernel version: bump it when `igc` changes. If a build fails, Arch's
   `igc` loads: network fine, no Wake-on-LAN.
2. **Upstream.** A patch to `intel-wired-lan@lists.osuosl.org` (Intel's
   `igc` maintainers), `netdev` in copy, with the evidence above (PHPM
   decode, port 3 with and without the bit, Windows' 100BaseTX). Romain
   sends it under his name with `Signed-off-by:` (DCO: a human certifies it)
   and must be able to defend it in review. Check the kernel's current rules
   on disclosing AI help (an `Assisted-by:`-style tag) before sending. A
   `Fixes:` tag on the commit that added `__igc_shutdown` gets it into
   stable kernels. Expect weeks to months; drop the local package once
   Arch's kernel has it. The FreeBSD bug (below) could get the same fix
   (`igc_set_d3_lplu_state_i225()` exists there).
3. **Optional checks:** `systemctl suspend` (same function), and whether a
   2.5G or 1G link in D3 would also work (not needed: Windows uses 100M).

## Sources

- [CachyOS: WOL on Intel I225-V (Rev 03)](https://discuss.cachyos.org/t/wol-on-intel-i225-v-rev-03/10013):
  works from Windows, not Linux; later, a `.link` file reportedly fixed it
  (not here; maybe their switch takes 10 Mbit/s).
- [Proxmox: WoL not working on NUC 12 with I225-V](https://forum.proxmox.com/threads/wol-not-working-on-intel-nuc-12-nuc12wski7-with-i225-v-nic-under-proxmox.184101/):
  Linux seems to cut the card's power at shutdown; Windows keeps the link LED on.
- [intel-wired-lan: igc driver doesn't power down the PHY when link is brought down](https://lore.kernel.org/all/Y926GPvm0f544ogG@wantstofly.org/T/)
- [FreeBSD: Wake-on-LAN not working on igc, I226-V](https://forums.freebsd.org/threads/wake-on-lan-not-working-on-igc-driver-nic-intel-i226-v.94598/post-667925)
  and [FreeBSD bug 282140](https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=282140)
