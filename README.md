# Artifact Acquisition Tool

[![Platform](https://img.shields.io/badge/platform-Linux-blue)](https://www.kernel.org/)
[![Language](https://img.shields.io/badge/language-Bash-4EAA25?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Memory Acquisition](https://img.shields.io/badge/memory-LiME-orange)](https://github.com/504ensicsLabs/LiME)
[![License](https://img.shields.io/badge/license-GPL%20v2-green)](./LiME/LICENSE)

A Linux-based digital forensics triage tool that automates volatile memory acquisition and systematic extraction of forensic artifacts from live systems. Designed to run entirely from removable media, ensuring zero write-back to the target system.

## Table of Contents

1. [Overview](#overview)
2. [Background](#background)
3. [Features](#features)
4. [Architecture](#architecture)
5. [Repository Structure](#repository-structure)
6. [Requirements](#requirements)
7. [Installation](#installation)
8. [Usage](#usage)
9. [Output Structure](#output-structure)
10. [Forensic Soundness](#forensic-soundness)
11. [Validation](#validation)
12. [Limitations](#limitations)
13. [Roadmap](#roadmap)
14. [Operational Notes](#operational-notes)
15. [Disclaimer](#disclaimer)
16. [References](#references)
17. [Acknowledgments](#acknowledgments)

---

## Overview

The Artifact Acquisition Tool automates two critical phases of a Linux forensic triage response:

1. **Volatile Memory Acquisition** — Captures a full physical memory image using [LiME (Linux Memory Extractor)](https://github.com/504ensicsLabs/LiME), loaded as a kernel module.
2. **Artifact Collection** — Extracts system, network, filesystem, user activity, and browser artifacts into an organized, timestamped directory hierarchy.

Every memory image is automatically fingerprinted with **MD5, SHA-1, and SHA-256** digests, accompanied by acquisition timing metadata to preserve evidentiary integrity and support chain-of-custody documentation.

By integrating memory acquisition and artifact extraction into a single modular workflow, the tool addresses a persistent gap in forensic practice — where these processes are typically performed separately, manually, and inconsistently — thereby reducing acquisition time and human error during incident response.

## Background

### The `/dev/mem` Problem

Modern Linux distributions restrict or disable direct access to system memory through `/dev/mem` as a kernel-level security measure. While this hardening improves overall system security, it renders traditional memory-acquisition methods inoperable: tools such as `dd`, which historically read memory through `/dev/mem`, are no longer viable on most contemporary systems.

### Rationale for LiME over `dd`

| Criterion | `dd` | LiME |
|---|---|---|
| Operation under `/dev/mem` restrictions | Not feasible | Loads directly into the kernel |
| Built-in integrity verification | None | Designed for forensically sound capture |
| Live-response suitability | Manual and fragile | Purpose-built kernel module |
| Output control | Limited | Raw format with per-range dumping |

LiME bypasses these restrictions by loading directly into the Linux kernel, enabling full physical memory acquisition in raw format even when raw-memory access is blocked. It therefore forms the acquisition backbone of this tool.

## Features

| Feature | Description |
|---|---|
| Memory dump automation | Compiles and loads LiME on-the-fly; captures all RAM in raw format |
| Integrity verification | Generates MD5, SHA-1, and SHA-256 digests plus timing metadata for every dump |
| Structured artifact collection | Logs, system configuration, network state, filesystem info, shell history, browser data |
| Multi-browser support | Firefox, Chrome, Chromium, Brave, Vivaldi, Opera |
| Multi-shell history capture | Bash, Zsh, Ksh, Fish |
| Portable operation | All output written to external media; zero writes to the evidence disk |
| Timestamped output | Each extraction produces an isolated timestamped directory for repeat acquisitions |

## Architecture

```
+-------------------------------------------------------------+
|                   USB Drive (Evidence Media)                 |
|                                                              |
|  +--------------+      +----------------------------------+  |
|  |  LiME (.ko)  |----->|   Target Linux System (live)     |  |
|  +--------------+      |                                  |  |
|                        |  1. insmod lime.ko -> RAM dump   |  |
|  +--------------+      |  2. Hash MD5/SHA1/SHA256         |  |
|  | triage script|----->|  3. Copy artifacts               |  |
|  +--------------+      +----------------------------------+  |
|                        |                                     |
|        memory_dump/*.raw + hash_info_*.txt                   |
|        artifacts/<timestamp>/{logs,system,network,...}       |
+-------------------------------------------------------------+
```

**Memory acquisition flow:** Detect USB via UUID/label → verify kernel headers → compile LiME module → insert module (`format=raw`, `dump=all`, `tcp=off`) → await completion → hash the image → unload the module.

**Artifact extraction flow:** Create timestamped output tree → copy logs, configurations, histories, and browser profiles with metadata preservation (`cp --preserve=all`) → snapshot live system, network, and filesystem state via command output capture.

> For detailed internals, see [CODE_DOCUMENTATION.md](./CODE_DOCUMENTATION.md).

## Repository Structure

```
.
├── FYP_Final_LKH.sh          # Main triage tool script
├── LiME/                     # Linux Memory Extractor (source + prebuilt module)
│   ├── src/
│   │   ├── lime.ko           # Compiled kernel module
│   │   ├── main.c            # LiME source
│   │   └── ...
│   ├── doc/
│   └── LICENSE
├── kernel_headers/
│   └── linux-6.8.11          # Pre-staged kernel headers
├── artifacts/                # Output: extracted artifacts (timestamped)
├── memory_dump/              # Output: RAM images + hash manifests
└── README.md
```

## Requirements

### Operating System

- Linux-based distribution (Debian/Ubuntu recommended)

### Kernel

- Version compatible with LiME (`uname -r` must match available headers)

### Hardware

- USB or external drive with at least **64 GB** free space (image size scales with installed RAM)

### Software Dependencies

| Category | Packages / Utilities |
|---|---|
| Build tools | `build-essential`, `gcc`, `make` |
| Core utilities | `findmnt`, `cp`, `lsblk`, `md5sum`, `sha1sum`, `sha256sum` |
| Networking | `net-tools` (`netstat`, `arp`), `lsof`, `iproute2` (`ip`, `ss`) |
| Kernel headers | Must exactly match the running kernel |

**Best practice:** Pre-stage matching headers in `/usr/src/linux-headers-<kernel-version>` (or use the bundled `kernel_headers/`). A fallback auto-install via `sudo apt-get install linux-headers-$(uname -r)` exists — see [Forensic Soundness](#forensic-soundness).

## Installation

### 1. Configure USB Detection

Identify the evidence drive's UUID and label:

```bash
blkid
```

Edit the configuration block at the top of `FYP_Final_LKH.sh`:

```bash
USB_UUID="your-usb-uuid"      # e.g. 8940cbca-b7ee-4d29-9d0b-3c20d101a017
USB_LABEL="your-usb-label"    # optional fallback identifier
```

### 2. Prepare the USB Directory Layout

```
USB/
├── FYP_Final_LKH.sh
├── FYP/
│   ├── LiME/
│   │   └── src/              # LiME source code
│   ├── memory_dump/          # created automatically
│   └── artifacts/            # created automatically
```

### 3. Stage Kernel Headers

Place headers matching the target kernel in `/usr/src/linux-headers-$(uname -r)`. If unavailable, the script will attempt to install them automatically (**not recommended** — see [Operational Notes](#operational-notes)).

### 4. Grant Execution Permissions

```bash
chmod +x FYP_Final_LKH.sh
```

### 5. Install Required Utilities

```bash
sudo apt-get update
sudo apt-get install build-essential gcc net-tools lsof
```

## Usage

Execute from the mounted evidence drive:

```bash
sudo ./FYP_Final_LKH.sh
```

### Menu Options

```
Select an option:
1. Create Memory Dump
2. Extract Artifacts
3. Exit
Enter choice:
```

| Option | Action | Output Location |
|---|---|---|
| 1 | Verifies headers → compiles LiME → acquires RAM → generates digests and timing report | `FYP/memory_dump/mem_dump_<timestamp>.raw`<br>`FYP/memory_dump/hash_info_<timestamp>.txt` |
| 2 | Collects logs, system/network/filesystem state, user activity, browser data | `FYP/artifacts/<timestamp>/` |
| 3 | Exits cleanly | — |

> **Note:** Follow proper triage order — acquire **volatile memory first** (Option 1) before extracting disk artifacts (Option 2).

## Output Structure

```
artifacts/<YYYYMMDD_HHMMSS>/
├── logs/                  # /var/log, systemd journals, docker/cron logs
├── system/                # os-release, passwd, sudoers, fstab, ssh, gnupg,
│                          # aws/docker configs + system_info.txt
├── network/               # network_info.txt (ip, route, netstat, ss, lsof, arp),
│                          # /etc/hosts{,.allow,.deny}, /etc/network
├── filesystem/            # filesystem_info.txt (lsblk, fdisk, mount, stat)
├── activity/              # shell histories (bash/zsh/ksh/fish), rc/profile files
├── web/                   # firefox, chrome, chromium, brave, vivaldi, opera
├── other/                 # /root contents
└── tmp/                   # /tmp, /var/tmp contents, swap file

memory_dump/
├── mem_dump_20250116_130016.raw
└── hash_info_20250116_130016.txt
```

Sample integrity manifest:

```
==================== Hashes and Timings ====================
Memory dump file: .../mem_dump_20250116_130016.raw
MD5:     <digest>
SHA1:    <digest>
SHA256:  <digest>
Script start time: 2025-01-16 13:00:16
Script end time:   2025-01-16 13:04:52
Total time taken: 276 seconds
============================================================
```

### Evidentiary Value of Collected Artifacts

| Artifact Class | Investigative Relevance |
|---|---|
| System logs (`auth.log`, `syslog`, `kern.log`) | Authentication events, sudo usage, intrusion indicators |
| Network data | Active connections, routing tables, ARP cache — C2/exfiltration detection |
| User activity | Shell command history and login sessions across four shells |
| Filesystem | Mounted filesystems, partition tables, hidden or anomalous partitions |
| Memory image | Running processes, encryption keys, malware/rootkit remnants invisible to disk-based tools |
| Web browsing data | Histories, caches, cookies — hijacked session token recovery |
| System configuration | `/etc/passwd`, `/etc/sudoers` modifications indicating persistence or privilege escalation |
| Temporary files | Attacker scripts and payloads staged in `/tmp`, `/var/tmp`, swap |

## Forensic Soundness

- **Minimal footprint.** All evidence is written to external media; the target disk is never written to.
- **Headers first.** Stage kernel headers before deployment. Runtime installation modifies system state and contaminates the acquisition environment — reserve it for unavoidable cases only.
- **Hash everything.** Every image receives MD5/SHA-1/SHA-256 digests and timing metadata immediately after creation.
- **Metadata preserved.** Artifacts are copied with `cp --preserve=all`, retaining timestamps, permissions, and ownership.
- **Validate before deployment.** Exercise the full workflow in a controlled VM environment prior to field use.

## Validation

The tool was validated in controlled laboratory environments simulating real-world attack scenarios — brute-force attacks, malware intrusion, and unauthorized logins — across multiple distributions:

- Ubuntu
- Debian
- CentOS

## Limitations

- **Linux only.** Relies on Linux-specific tooling (`cp`, `netstat`, `ss`, LiME); Windows/macOS require different acquisition stacks.
- **System load affects acquisition time.** Heavily loaded systems (particularly ≥ 32 GB RAM) take longer; volatile evidence may shift during prolonged acquisitions.
- **Kernel header dependency.** LiME must be compiled against the exact running kernel version.

## Roadmap

- [ ] Cross-platform support — Windows (WinPmem, registry hives, event logs, prefetch) and macOS (pmem, Keychain data)
- [ ] Advanced volatile-data acquisition — live process analysis, packet capture (`tcpdump`), Volatility/Rekall integration
- [ ] Automated analysis and reporting — artifact correlation, timeline visualization, standardized HTML/PDF reports
- [ ] Performance tuning — targeted memory-region dumping for high-load systems

## Operational Notes

- Run with `sudo`; memory dumping and most artifact paths require root privileges.
- Verify USB UUID/label configuration — a mismatch safely aborts execution.
- The bundled `lime.ko` targets a specific kernel version; recompilation is automatic but requires matching headers.
- High-RAM systems produce proportionally large `.raw` images; ensure adequate drive capacity.
- Never commit real case data. Evidence output (`memory_dump/`, `artifacts/`) is excluded via `.gitignore`.

## Disclaimer

This tool is intended **solely for authorized digital forensics investigations, incident response, and educational purposes**. Unauthorized access to computer systems is illegal. The authors assume no liability for misuse or damages arising from use of this software. Always obtain proper legal authorization before acquiring data from any system.

## References

1. Svetlana Ostrovskaya and Oleg Skulkin, *Practical Memory Forensics*, O'Reilly Media, 2023.
2. Michael Hale Ligh, Andrew Case, Jamie Levy, and Aaron Walters, *The Art of Memory Forensics: Detecting Malware and Threats in Windows, Linux, and Mac Memory*, Wiley, 2014.
3. LiME Documentation, *Linux Memory Extractor (LiME)*.
4. *Enhancing Digital Forensics: Cross-Platform Artifact Extraction*, Journal of Cybersecurity Research, 2024.
5. *Automated Forensic Analysis Using Machine Learning*, Proceedings of the International Digital Forensics Conference, 2024.
6. *Challenges in Live Forensics: Capturing and Analyzing Volatile Data*, Digital Forensic Journal, 2023.

## Acknowledgments

Memory acquisition is powered by [LiME — Linux Memory Extractor](https://github.com/504ensicsLabs/LiME) © 504Ensics Labs, released under the GNU GPL v2. See [`LiME/LICENSE`](./LiME/LICENSE).
