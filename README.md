# jiopc-vps-experiment

> **Can JioPC Actually Be Used as a VPS?**  
> *A 7-day empirical investigation into JioPC's compute, storage, networking, development, AI, server, and persistence capabilities.*

[![Day 1 Status](https://img.shields.io/badge/Day%201-Infrastructure%20Recon-success)](findings/day-01-recon.md)
[![Investigation Progress](https://img.shields.io/badge/Progress-Day%201%20of%207-blue)](#investigation-roadmap)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## 1. Overview & Research Question

JioPC provides a cloud-hosted desktop environment marketed primarily for virtualized office productivity and basic compute. However, underlying the user interface is a virtualized Linux system. 

This repository documents a structured, **7-day hands-on engineering experiment** to determine whether JioPC can be provisioned and operated as a functional Virtual Private Server (VPS) for software engineering, microservices, local AI inference, and background daemons.

### Core Research Questions
1. **Compute & Memory**: Does the provisioned hardware deliver sustained performance comparable to cloud VPS instances?
2. **Privileges & Toolchains**: Can modern development runtimes and servers function without `root` / `sudo` access?
3. **Storage Latency & IOPS**: How does an NFSv4-backed persistent home directory handle developer workloads?
4. **Network Boundaries**: Can the absence of direct inbound IPv4 connectivity and port forwarding be bypassed using user-space overlay networks (e.g., Tailscale, Cloudflare Tunnels)?
5. **Persistence & Lifecycle**: Do background services survive disconnects, logouts, or host reboots?

---

## 2. 7-Day Investigation Roadmap

| Day | Topic / Phase | Focus Areas | Status | Link |
| :---: | :--- | :--- | :---: | :---: |
| **Day 1** | **Infrastructure Reconnaissance** | Compute topology, RAM, storage layout, NFS, egress proxy, inbound reachability | **COMPLETE** | [findings/day-01-recon.md](findings/day-01-recon.md) |
| **Day 2** | **Development Environment** | Non-root package management (Nix, Homebrew, user binaries), compilers, Node.js, Python, Rust | `PENDING` | — |
| **Day 3** | **Server & Service Hosting** | Binding non-root ports (>1024), HTTP servers (Nginx/Caddy/Node), process supervision | `PENDING` | — |
| **Day 4** | **Inbound Connectivity & Mesh Networking** | Tailscale in user-space mode, Cloudflare Tunnels, Reverse SSH, WireGuard feasibility | `PENDING` | — |
| **Day 5** | **Databases & Background Workloads** | PostgreSQL, SQLite concurrency on NFS, Redis, background job scheduling | `PENDING` | — |
| **Day 6** | **AI & Compute Acceleration** | AVX-512 / VNNI vector performance, `llama.cpp`, Ollama, quantized LLM inference | `PENDING` | — |
| **Day 7** | **Stress, Failure & Final Verdict** | RAM saturation (0 B swap), network drop behavior, reboot persistence, comprehensive scorecard | `PENDING` | — |

---

## 3. Day 1: Executive Summary & Status Matrix

Day 1 focused on uncovering the underlying virtual machine architecture, hardware topology, storage hierarchy, and network perimeter boundaries.

### Day 1 Status Matrix

| Subsystem / Test | Day 1 Status | Direct Findings |
| :--- | :---: | :--- |
| **CPU Architecture** | `TESTED` | Intel Xeon Platinum 8370C (4 physical cores, 8 SMT threads, AVX-512 VNNI) |
| **RAM Capacity** | `TESTED` | 15 GiB physical RAM, ~12 GiB baseline available |
| **Swap Space** | `TESTED` | 0 B configured swap; identified as a critical OOM risk |
| **Storage Layout** | `TESTED` | 64G `sda` (root ext4), 128G `sdb` (Flatpak store), NFS persistent `/home` |
| **NFS Performance** | `TESTED` | Sequential write: 342–663 MB/s; Fresh read: 73.1 MB/s; Cache read: 8.4 GB/s |
| **Secondary Disk** | `TESTED` | `/mnt/sfdisk` is root-owned (0755); write permission denied to unprivileged user |
| **Network Interfaces**| `TESTED` | Private IP `10.1.1.167/19` on `eth0`, Gateway `10.1.0.1` |
| **Internet Egress** | `TESTED` | Functional via local forward proxy (`Px` on `127.0.0.1:3128`) |
| **DNS Resolution** | `TESTED` | Functional; successfully resolved IPv6 AAAA records |
| **SSH Daemon** | `PARTIALLY TESTED`| OpenSSH daemon listening on `0.0.0.0:22`; local auth rejected (no key/password) |
| **Inbound Reachability**| `PARTIALLY TESTED`| Inbound TCP port 22 unreachable from external private and public networks |
| **Dev Environment** | `PENDING` | Scheduled for Day 2 |
| **Web Server** | `PENDING` | Scheduled for Day 3 |
| **Database** | `PENDING` | Scheduled for Day 5 |
| **Tailscale / Mesh** | `PENDING` | Scheduled for Day 4 |
| **AI / Inference** | `PENDING` | Scheduled for Day 6 |
| **Stress Testing** | `PENDING` | Scheduled for Day 7 |
| **Failure Testing** | `PENDING` | Scheduled for Day 7 |

---

## 4. Current Working Hypothesis

> *"JioPC contains many of the components of a high-performance VPS—including 4 physical Xeon cores, 15 GiB of RAM, and high-speed network storage—but its unprivileged execution model (non-root) and restrictive proxy/perimeter networking prevent it from functioning like a conventional, publicly reachable VPS out of the box."*

*Note: This is an empirical working hypothesis formulated at the conclusion of Day 1, not the final project verdict. Days 2–7 will test workarounds, including user-space overlays and rootless runtimes.*

---

## 5. Evidence Classification Framework

All documentation in this repository strictly classifies observations to separate empirical measurements from inference:

* **`[MEASURED]`**: Direct numerical or metric output from an empirical diagnostic tool (`dd`, `free`, `ip`, `curl`, `Test-NetConnection`).
* **`[VERIFIED]`**: Directly inspected, reproducible system configuration attribute (`whoami`, `mount`, `lsblk`, `ss`, `ps`).
* **`[REPRODUCED]`**: Result confirmed through multiple independent test executions under identical parameters.
* **`[INFERRED]`**: Logical engineering deduction derived directly from verified attributes and standard OS/cloud networking models.
* **`[UNVERIFIED]`**: Working hypothesis or unconfirmed system detail pending further empirical isolation.

---

## 6. Repository Structure

```
jiopc-vps-experiment/
├── README.md                           # Master project documentation & status
├── findings/
│   ├── day-01-recon.md                 # Day 1: Full infrastructure reconnaissance report
│   └── (day-02 through day-07)         # Subsequent investigation reports
├── benchmarks/
│   ├── day-01-storage.csv              # Raw CSV data for Day 1 storage and capacity tests
│   └── (future benchmark data)
├── diagrams/
│   ├── day-01-architecture.md          # 8 Mermaid diagrams + benchmark visualizations
│   └── (future architectural schematics)
└── scripts/                            # Test scripts and reproducible benchmark runners
```

---

## 7. Key Documentation Links

* **Detailed Day 1 Reconnaissance Report**: [findings/day-01-recon.md](findings/day-01-recon.md)
* **Architecture & Network Topology Diagrams**: [diagrams/day-01-architecture.md](diagrams/day-01-architecture.md)
* **Raw Storage Benchmark Dataset**: [benchmarks/day-01-storage.csv](benchmarks/day-01-storage.csv)
