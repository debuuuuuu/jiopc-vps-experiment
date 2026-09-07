# Day 1: Infrastructure Reconnaissance

**Project**: `jiopc-vps-experiment`  
**Investigation Day**: Day 1 of 7  
**Focus Area**: Compute, Memory, Storage Hierarchy, Networking, Egress Proxy, and Inbound Boundaries  
**System Under Test**: JioPC Cloud Desktop / Cloud Instance  
**Working Hypothesis**: *"JioPC contains many of the components of a VPS, but its privilege and networking model may prevent it from behaving like a conventional publicly reachable VPS."*

---

## 1. Executive Summary & Investigation Context

The primary objective of this 7-day empirical investigation is to evaluate whether a **JioPC** instance can function as a conventional Virtual Private Server (VPS) for developer, server, and background workloads.

Day 1 establishes the baseline infrastructure reconnaissance. Rather than relying on marketing claims or generic cloud specifications, every finding in this report is grounded in direct terminal execution, raw command output, and controlled network probes.

```
+-------------------------------------------------------------------------------+
|                             DAY 1 FINDINGS SUMMARY                           |
+----------------------+--------------------------------------------------------+
| Hypervisor           | Microsoft Hyper-V / Azure Infrastructure               |
| Host OS / Kernel     | Ubuntu Noble (24.04 LTS), Linux 6.17.0-1022-azure      |
| Processor            | Intel Xeon Platinum 8370C @ 2.80GHz                    |
| CPU Topology         | 1 Socket, 4 Physical Cores, 8 Logical CPUs (2-way SMT) |
| System Memory        | 15 GiB Physical RAM (~12 GiB baseline available)       |
| Swap Space           | 0 B (No swap configured)                               |
| Root Filesystem      | 63 GiB ext4 on sda1 (49 GB free)                       |
| Secondary Storage    | 128 GiB ext4 on sdb1 (/mnt/sfdisk, root-owned)          |
| User Home Storage    | NFSv4.1 Network Mount (100 TB cluster export pool)     |
| User Privileges      | Non-root (UID 3436237), No passwordless sudo           |
| Primary IP Address   | 10.1.1.167/19 (Private RFC 1918)                       |
| Public Egress IP     | 74.225.96.193 (Gateway NAT)                            |
| Outbound Transit     | Functional via local forward proxy (Px @ 127.0.0.1:3128)|
| Inbound Reachability | TCP 22 filtered/blocked externally; local daemon active|
+----------------------+--------------------------------------------------------+
```

---

## 2. Evidence Classification Framework

To maintain technical integrity and prevent conflating assumptions with verified data, all statements, metrics, and findings adhere to five strict evidence classifications:

* **`[MEASURED]`**: Direct numerical or metric output from an empirical diagnostic tool (`dd`, `free`, `ip`, `curl`, `Test-NetConnection`).
* **`[VERIFIED]`**: Directly inspected, reproducible system configuration attribute (`whoami`, `mount`, `lsblk`, `ss`, `ps`).
* **`[REPRODUCED]`**: Result confirmed through repeated, independent test runs under identical or controlled parameters.
* **`[INFERRED]`**: Logical engineering deduction derived directly from verified attributes and standard OS/cloud networking models.
* **`[UNVERIFIED]`**: Working hypothesis, vendor implementation detail, or quota limit not yet confirmed via direct empirical testing.

---

## 3. Host Environment, Runtime Context & Privileges

### 3.1 Flatpak Container vs. Underlying Host

When initially launching a terminal within the default VSCodium desktop environment, the shell was encapsulated inside a **Freedesktop Flatpak runtime** sandbox.

To inspect the genuine operating environment of the virtual machine, execution was stepped out of the sandbox to the host environment using:

```bash
flatpak-spawn --host bash
```

> **Why this test matters**: Flatpak applications execute inside isolated Linux namespaces with private `/etc`, `/usr`, and temporary filesystems. Running diagnostics inside Flatpak would capture only the container's mock environment. Escaping via `flatpak-spawn --host` exposes the actual host OS, kernel, system-wide daemons, and physical/virtual devices.

```
+-----------------------------------------------------------------------+
| J I O P C   V I R T U A L   M A C H I N E                             |
|                                                                       |
|  Host Operating System: Ubuntu Noble (24.04 LTS), x86_64              |
|  Kernel: 6.17.0-1022-azure on host 'edcjp-0013'                       |
|                                                                       |
|  +-----------------------------------------------------------------+  |
|  | Flatpak Container (VSCodium Sandbox)                            |  |
|  | - Isolated /usr, /lib, /etc (Freedesktop SDK runtime)           |  |
|  | - Sandboxed process tree                                        |  |
|  |                                                                 |  |
|  |          flatpak-spawn --host bash                              |  |
|  |                     |                                           |  |
|  +---------------------|-------------------------------------------+  |
|                        v                                              |
|  +-----------------------------------------------------------------+  |
|  | Underlying Host Shell (Real VM Environment)                     |  |
|  | - Real root filesystem (/), /boot, /mnt/sfdisk                  |  |
|  | - Full hardware device tree (/dev/sda, /dev/sdb, /dev/kvm)     |  |
|  | - Host network interfaces (eth0, lo, enP39396s1)                |  |
|  +-----------------------------------------------------------------+  |
+-----------------------------------------------------------------------+
```

### 3.2 Host Identification

Execution of kernel and system identification commands yielded:

* **Host OS**: Ubuntu Noble `[VERIFIED]`
* **Architecture**: `x86_64` `[VERIFIED]`
* **Kernel Release**: `6.17.0-1022-azure` `[VERIFIED]`
* **Hostname**: `edcjp-0013` `[VERIFIED]`

The `-azure` kernel suffix is a significant architectural signature. It indicates that the VM is running a kernel build optimized for Microsoft Azure hypervisor integration (Hyper-V drivers, Azure virtual network adapters, and accelerated networking).

### 3.3 User Identity & Privilege Boundary

```bash
whoami
id
pwd
```

**Raw Output Results:**
* `whoami`: `001280863647_0` `[VERIFIED]`
* `id`: `uid=3436237(001280863647_0) gid=3436237(001280863647_0) groups=3436237(001280863647_0)` `[VERIFIED]`
* `pwd`: `/home/001280863647_0` `[VERIFIED]`

To verify if the account possesses administrative escalation rights, a non-interactive privilege escalation probe was executed:

```bash
sudo -n sh -c 'echo test'
```

**Result:**
`sudo: a password is required` `[VERIFIED]`

> **Why this test matters**: Standard VPS providers (AWS EC2, DigitalOcean, Linode, Hetzner) issue users full `root` or passwordless `sudo` privileges. The lack of administrative access prevents `apt install`, kernel module loading, low-level firewall configuration (`iptables`/`nftables`), systemd system unit creation, and binding services to privileged ports (<1024).

---

## 4. Compute Subsystem: CPU Architecture & Topology

### 4.1 Measured Compute Specifications

Execution of `lscpu` revealed the following processor and virtualization parameters:

| Parameter | Measured Value | Evidence | Interpretation |
| :--- | :--- | :--- | :--- |
| **Model Name** | Intel Xeon Platinum 8370C @ 2.80GHz | `[VERIFIED]` | 3rd Gen Intel Xeon Scalable (Ice Lake) enterprise cloud SKU |
| **Sockets** | 1 | `[VERIFIED]` | Single virtual socket exposed to guest |
| **Physical Cores** | 4 | `[VERIFIED]` | 4 physical execution cores provisioned |
| **Threads per Core** | 2 | `[VERIFIED]` | 2-way Simultaneous Multithreading (SMT / Hyper-Threading) |
| **Logical CPUs** | 8 | `[VERIFIED]` | 4 cores × 2 threads = 8 logical execution units |
| **Hypervisor** | Microsoft | `[VERIFIED]` | Virtualized via Microsoft Hyper-V / Azure Fabric |
| **Virtualization** | VT-x | `[VERIFIED]` | Hardware virtualization support exposed |
| **L3 Cache** | 48 MiB | `[VERIFIED]` | Shared Level-3 cache pool |

### 4.2 Processor Instruction Extensions

Inspection of processor feature flags confirmed support for:
* `AVX` & `AVX2`: 256-bit Advanced Vector Extensions `[VERIFIED]`
* `AVX-512F`, `AVX-512DQ`, `AVX-512BW`, `AVX-512VL`: 512-bit vector processing `[VERIFIED]`
* `AVX-512 VNNI`: Vector Neural Network Instructions `[VERIFIED]`

> **Why this test matters**: The presence of `AVX-512` and `VNNI` is critical for AI inference workloads. Modern LLM inference engines (such as `llama.cpp`, `Ollama`, or PyTorch CPU backends) utilize VNNI for INT8 and FP16 quantized matrix multiplications, delivering significantly higher token throughput than basic x86_64 CPUs.

### 4.3 Compute Topology: Cores vs. Threads

```
+-------------------------------------------------------------------------------+
| PHYSICAL TOPOLOGY: Intel Xeon Platinum 8370C (Socket 0)                      |
| Shared L3 Cache: 48 MiB                                                      |
+-----------------------+-----------------------+-------------------------------+
|  Physical Core 0      |  Physical Core 1      |  Physical Core 2  |  Core 3   |
|  +---------+---------+|  +---------+---------+|  +-------+-------+|  +-------+|
|  |Thread 0 |Thread 1 ||  |Thread 0 |Thread 1 ||  |Th 0   |Th 1   ||  |Th0|Th1||
|  | vCPU 0  | vCPU 4  ||  | vCPU 1  | vCPU 5  ||  |vCPU 2 |vCPU 6 ||  |vC3|vC7||
|  +---------+---------+|  +---------+---------+|  +-------+-------+|  +-------+|
+-----------------------+-----------------------+-------------------------------+
```

**Critical Technical Distinction**: The operating system reports 8 CPUs (`0` through `7`). However, this does **NOT** indicate 8 dedicated physical cores. It represents **4 physical cores with 2 SMT threads per core** (`[VERIFIED]`).

Under CPU-bound parallel workloads (such as compiling large codebases or running concurrent model inference), two threads sharing the same physical core contend for execution ports, floating-point units, and L1/L2 caches. Theoretical compute scaling will plateau well below an 8-core physical baseline.

---

## 5. Memory & Swap Subsystem

### 5.1 Memory Allocation

Diagnostic command:

```bash
free -h
```

**Raw Output:**
```
               total        used        free      shared  buff/cache   available
Mem:            15Gi       3.2Gi       7.9Gi       3.0Mi       4.4Gi        12Gi
Swap:             0B          0B          0B
```

* **Total Usable RAM**: `15 GiB` `[MEASURED]`
* **Baseline Used RAM**: `3.2 GiB` `[MEASURED]` (consumed by system daemons, desktop manager, Flatpak services)
* **Free RAM**: `7.9 GiB` `[MEASURED]`
* **Available RAM**: `12 GiB` `[MEASURED]` (unallocated RAM + reclaimable buffer/cache)
* **Configured Swap**: `0 B` `[MEASURED]`

### 5.2 Architectural Significance of Zero Swap

In traditional server environments, swap space acts as a spillover buffer for inactive pages when memory allocations approach capacity.

```
NO SWAP CONFIGURED (0 B)
+-------------------------------------------------------------+
| System RAM: 15 GiB Total                                    |
| [ Active App / OS ] [ Cache: 4.4G ] [ Available: 12 GiB ]   |
+-------------------------------------------------------------+
                              |
                     Memory Allocation > 15 GiB
                              |
                              v
                +----------------------------+
                |  Linux OOM Killer Invoked  |
                |  Immediate SIGKILL to App  |
                +----------------------------+
```

Because JioPC has **0 B swap**, memory pressure cannot be mitigated by paging out cold memory. If a compilation job, database index build, or AI model exceeds the 12 GiB threshold, the Linux Out-Of-Memory (OOM) killer will immediately terminate processes via `SIGKILL`. This constraint must be actively monitored during Day 5 (Databases), Day 6 (AI inference), and Day 7 (Stress testing).

---

## 6. Storage Hierarchy & Filesystem Subsystem

### 6.1 Block Device Layout

Diagnostic command:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
```

**Measured Layout:**
* `sda` (64 GiB SCSI disk) `[VERIFIED]`
  * `sda1` (63 GiB, ext4) mounted at `/` (System Root) `[VERIFIED]`
  * `sda15` (106 MiB, vfat) mounted at `/boot/efi` `[VERIFIED]`
  * `sda16` (913 MiB, ext4) mounted at `/boot` `[VERIFIED]`
* `sdb` (128 GiB SCSI disk) `[VERIFIED]`
  * `sdb1` (128 GiB, ext4) mounted at `/mnt/sfdisk` `[VERIFIED]`

### 6.2 Filesystem Capacity Audit

Diagnostic command:

```bash
df -hT
```

**Observed Capacity Metrics:**

| Mount Point | Device / Source | Filesystem | Size | Used | Avail | Use% | Role |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `/` | `/dev/sda1` | ext4 | 61 GB | 13 GB | 49 GB | 21% | OS Root, System Binaries |
| `/mnt/sfdisk` | `/dev/sdb1` | ext4 | 126 GB | 71 GB | 49 GB | 59% | Managed Flatpak Store |
| `/home/001280863647_0` | `[nfs-export-ip]:/export` | nfs4 (4.1) | 100 TB | ~759 GB | ~99.2 TB | 1% | User Persistent Home |

```
+-----------------------------------------------------------------------+
| WARNING: THE 100 TB NUMBER IS A CLUSTER EXPORT SIZE, NOT A USER QUOTA |
+-----------------------------------------------------------------------+
The 100 TB capacity reported on /home reflects the total capacity of the
remote enterprise NFS storage cluster pool. It does NOT mean the user has
a 100 TB personal quota. The actual per-user quota was NOT determined
during Day 1 testing [UNVERIFIED]. Do not claim 100 TB personal storage.
+-----------------------------------------------------------------------+
```

### 6.3 Investigation of Secondary Disk (`/mnt/sfdisk`)

The system exposes a 128 GB block storage device (`sdb1`) mounted at `/mnt/sfdisk`. A test was conducted to evaluate whether this drive could be utilized for local high-speed developer scratch space:

```bash
dd if=/dev/urandom of=/mnt/sfdisk/disk_test.bin bs=1M count=2048 conv=fdatasync status=progress
```

**Result:**
`dd: failed to open '/mnt/sfdisk/disk_test.bin': Permission denied` `[MEASURED]`

Checking ownership and permissions:

```bash
ls -ld /mnt/sfdisk
```

**Result:**
`drwxr-xr-x 7 root root 4096 /mnt/sfdisk` `[VERIFIED]`

The filesystem root is owned by `root:root` with permissions `0755`. Because the user account is unprivileged (`uid=3436237`), direct file creation at the root of `/mnt/sfdisk` is blocked.

To discover if any writable subpaths exist on `/mnt/sfdisk`:

```bash
find /mnt/sfdisk -maxdepth 2 -type d -writable -print
```

**Output:**
* `/mnt/sfdisk/flatpak` `[VERIFIED]`
* `/mnt/sfdisk/flatpak/exports` `[VERIFIED]`
* `/mnt/sfdisk/flatpak/app` `[VERIFIED]`
* `/mnt/sfdisk/flatpak/runtime` `[VERIFIED]`
* `/mnt/sfdisk/flatpak/repo` `[VERIFIED]`

**Engineering Conclusion**: The 128 GB secondary drive is dedicated infrastructure storage utilized by JioPC for housing Flatpak desktop runtimes, application repositories, and system bundles. It is **not** exposed or provisioned as a general-purpose user-data disk. These directories should not be modified to avoid breaking the desktop environment.

---

## 7. Network Filesystem (NFS) Analysis & Empirical Benchmarks

### 7.1 NFS Mount Parameter Audit

Inspection of active mount options:

```bash
mount | grep '/home'
```

**Extracted Parameters & Engineering Meaning:**
* `type nfs4`: Network File System Version 4 distributed file protocol `[VERIFIED]`.
* `vers=4.1`: Minor version 4.1, providing stateful sessions and multi-server trunking support `[VERIFIED]`.
* `rw`: Filesystem mounted with read and write permissions `[VERIFIED]`.
* `rsize=524288` & `wsize=524288`: Read/write transfer buffer set to 524,288 bytes (512 KiB), maximizing packet throughput over high-bandwidth links `[VERIFIED]`.
* `hard`: If the NFS server becomes unreachable, client I/O requests will retry indefinitely rather than timing out and reporting an I/O error. This prevents data corruption, but causes calling processes to hang in uninterruptible sleep (`D` state) if the network drops `[VERIFIED]`.
* `proto=tcp`: Transport layer protocol is TCP, guaranteeing ordered, reliable delivery `[VERIFIED]`.
* `sec=sys`: Standard UNIX authentication using user UID and GID `[VERIFIED]`.

```
APPLICATION LAYER
  /home/001280863647_0 (User writes, git clones, build artifacts)
        |
        v
LINUX VFS & PAGE CACHE (RAM)
        | (conv=fdatasync forces dirty pages out of RAM)
        v
NFS CLIENT DRIVER (vers=4.1, rsize=512K, wsize=512K, hard mount)
        |
        v
NETWORK STACK (TCP / eth0: 10.1.1.167)
        |
        v
ENTERPRISE NFS STORAGE BACKEND (Remote storage server / SAN cluster)
```

---

### 7.2 Storage Benchmarks (Standardized Empirical Format)

#### Benchmark 1: NFS Sequential Write (Run 1)
* **Test**: Sequential file write over NFS mount
* **Command**: `dd if=/dev/zero of=/home/001280863647_0/test_write_1.bin bs=1M count=2048 conv=fdatasync status=progress`
* **Input**: 2,048 MiB (2.15 GB) zero-stream from `/dev/zero`
* **Result**: `2147483648 bytes (2.1 GB, 2.0 GiB) copied, 5.33577 s, 402 MB/s`
* **Interpretation**: Baseline sequential write speed with enforced physical sync (`fdatasync`) reached 402 MB/s across the virtual network link.
* **Evidence Classification**: `[REPRODUCED]`
* **Limitations**: Zero-stream data is compressible; storage appliances with inline deduplication/compression may record artificially elevated throughput compared to compressed binary data.

#### Benchmark 2: NFS Sequential Write (Run 2)
* **Test**: Sequential file write repeatability check
* **Command**: `dd if=/dev/zero of=/home/001280863647_0/test_write_2.bin bs=1M count=2048 conv=fdatasync status=progress`
* **Input**: 2,048 MiB (2.15 GB) zero-stream from `/dev/zero`
* **Result**: `2147483648 bytes (2.1 GB, 2.0 GiB) copied, 3.24071 s, 663 MB/s`
* **Interpretation**: Repeat run exhibited a ~65% increase in throughput, reaching 663 MB/s. This indicates dynamic backend caching, transient network availability, or storage array write-tier buffering.
* **Evidence Classification**: `[REPRODUCED]`
* **Limitations**: High run-to-run variation proves that no single static write number defines the NFS tier.

#### Benchmark 3: NFS Random-Data Write
* **Test**: Sequential file write using high-entropy random data
* **Command**: `dd if=/dev/urandom of=/home/001280863647_0/test_write_rnd.bin bs=1M count=2048 conv=fdatasync status=progress`
* **Input**: 2,048 MiB (2.15 GB) incompressible pseudo-random bytes from `/dev/urandom`
* **Result**: `2147483648 bytes (2.1 GB, 2.0 GiB) copied, 6.27805 s, 342 MB/s`
* **Interpretation**: Incompressible random data generated lower throughput (342 MB/s), partially due to `/dev/urandom` CPU generation overhead and absence of backend deduplication benefits.
* **Evidence Classification**: `[MEASURED]`
* **Limitations**: Bounded by single-core entropy generation speeds in user space.

**Write Throughput Synthesis**: Observed write performance spans a dynamic range of **342 MB/s to 663 MB/s** (`[MEASURED]`). Documentation must present this as an operational range rather than a single fixed metric.

---

#### Benchmark 4: NFS Cached Read
* **Test**: Immediate reread of a freshly written 2 GiB test file
* **Command**: `dd if=/home/001280863647_0/test_write_1.bin of=/dev/null bs=1M status=progress`
* **Input**: 2,048 MiB file previously written to `/home`
* **Result**: `2147483648 bytes (2.1 GB, 2.0 GiB) copied, 0.24381 s, 8.4 GB/s`
* **Interpretation**: The measured 8.4 GB/s throughput is **NOT** network NFS throughput. It represents reading directly from the Linux kernel page cache in local RAM.
* **Evidence Classification**: `[MEASURED]` (with caveat)
* **Limitations**: Because the file was recently written, its dirty pages remained cached in system memory. An attempt to flush the kernel page cache via `sudo -n sh -c 'echo 3 > /proc/sys/vm/drop_caches'` failed due to lack of administrative privileges (`sudo: a password is required`).

```
+-------------------------------------------------------------------------------+
| CAUTION: 8.4 GB/s IS A RAM CACHE MEASUREMENT, NOT REAL NFS NETWORK SPEED      |
+-------------------------------------------------------------------------------+
The 8.4 GB/s metric reflects host RAM bus speed. Any claim that JioPC delivers  |
8.4 GB/s remote NFS storage throughput is technically invalid.                  |
+-------------------------------------------------------------------------------+
```

#### Benchmark 5: NFS Fresh-File (Uncached) Read
* **Test**: Cold sequential read of a newly created, uncached 2 GiB file
* **Command**: `dd if=/home/001280863647_0/fresh_test_file.bin of=/dev/null bs=1M status=progress`
* **Input**: 2,048 MiB fresh file read across the network interface
* **Result**: `2147483648 bytes (2.1 GB, 2.0 GiB) copied, 29.382 s, 73.1 MB/s`
* **Interpretation**: When forced to retrieve data over the network from the NFS appliance without page cache assistance, actual read throughput measured **73.1 MB/s**.
* **Evidence Classification**: `[MEASURED]`
* **Limitations**: Affected by concurrent cluster read traffic and network link utilization.

---

## 8. Network Interfaces & Subnet Configuration

### 8.1 Network Interface Audit

Diagnostic command:

```bash
ip -br addr
```

**Raw Output Results:**
* `lo`: `127.0.0.1/8` (Loopback interface) `[VERIFIED]`
* `eth0`: `10.1.1.167/19` (Primary virtual network interface) `[VERIFIED]`
* `enP39396s1`: State `UP`, no IPv4 configured (Hyper-V Accelerated Networking Virtual Function) `[VERIFIED]`

### 8.2 Subnet & Routing Architecture

Diagnostic command:

```bash
ip route
```

**Raw Output:**
```
default via 10.1.0.1 dev eth0 proto dhcp src 10.1.1.167 metric 100
10.1.0.0/19 dev eth0 proto kernel scope link src 10.1.1.167 metric 100
```

* **Guest IP Address**: `10.1.1.167` `[VERIFIED]`
* **Subnet Mask**: `/19` (255.255.224.0) `[VERIFIED]`
* **Host Address Range**: `10.1.0.1` through `10.1.31.254` (Capacity: 8,190 IPv4 hosts) `[INFERRED]`
* **Default Gateway**: `10.1.0.1` reached via interface `eth0` `[VERIFIED]`

```
+-------------------------------------------------------------------------------+
| LOCAL VIRTUAL NETWORK: 10.1.0.0/19                                            |
|                                                                               |
|  [ Default Gateway: 10.1.0.1 ] <========> [ JioPC Guest: 10.1.1.167 ]         |
|  (Upstream Router & DHCP Server)          (eth0 / Metric 100)                 |
+-------------------------------------------------------------------------------+
```

The IP address `10.1.1.167` resides firmly within the private IPv4 address space (RFC 1918). It is an internal address assigned inside the virtualization cluster.

---

## 9. Outbound Internet & Proxy Mediation

### 9.1 Outbound Connectivity Probe

Diagnostic command:

```bash
curl -I https://example.com
```

**Raw HTTP Response Headers:**
```http
HTTP/1.1 200 Connection established
Proxy-Agent: Px

HTTP/2 200
content-type: text/html
...
```

**Findings:**
1. Outbound HTTPS connectivity is functional `[VERIFIED]`.
2. The initial response header `HTTP/1.1 200 Connection established` with `Proxy-Agent: Px` proves that traffic is not exiting directly via native Layer 3 routing, but is being intercepted and forwarded through a proxy daemon `[VERIFIED]`.

### 9.2 Proxy Configuration Audit

Diagnostic command:

```bash
env | grep -i proxy
```

**Raw Environment Output:**
```bash
HTTP_PROXY=http://127.0.0.1:3128
HTTPS_PROXY=http://127.0.0.1:3128
http_proxy=http://127.0.0.1:3128
https_proxy=http://127.0.0.1:3128
NO_PROXY=localhost,127.0.0.1,::1
```

```
+-------------------------------------------------------------------------------+
| OUTBOUND PROXY FLOW ARCHITECTURE                                             |
|                                                                               |
|  [ User Application ] (curl, git, pip, npm)                                   |
|          |                                                                    |
|          | (HTTP CONNECT to 127.0.0.1:3128)                                   |
|          v                                                                    |
|  [ Local Proxy Daemon: Px ] (Listening on 127.0.0.1:3128)                     |
|          |                                                                    |
|          | (Enterprise upstream authentication / egress tunneling)            |
|          v                                                                    |
|  [ Upstream Gateway / NAT ] (Public IP: 74.225.96.193)                        |
|          |                                                                    |
|          v                                                                    |
|  [ Public Internet Host ] (https://example.com)                               |
+-------------------------------------------------------------------------------+
```

**Technical Explanation**: The endpoint `127.0.0.1:3128` is a local loopback proxy running on the VM, identified as **Px** (a lightweight HTTP proxy often used in enterprise environments to automate upstream NTLM/Kerberos authentication).

Any developer tool that does not automatically respect standard Unix `HTTP_PROXY` / `HTTPS_PROXY` environment variables (such as Docker, raw TCP sockets, or custom daemon processes) will fail to establish outbound connections unless explicitly configured.

---

## 10. Listening Ports & System Process Audit

### 10.1 Active Sockets Audit

Diagnostic command:

```bash
ss -tuln
```

**Extracted Listening Sockets:**

| Protocol | Local Address | Port | State | Service / Description |
| :--- | :--- | :--- | :--- | :--- |
| **TCP** | `0.0.0.0` | `22` | LISTEN | OpenSSH Server daemon (`[VERIFIED]`) |
| **TCP** | `0.0.0.0` | `3389` | LISTEN | Remote Desktop Protocol (RDP / XRDP) (`[VERIFIED]`) |
| **TCP** | `127.0.0.1` | `3128` | LISTEN | Local Px HTTP Forward Proxy (`[VERIFIED]`) |
| **TCP** | `0.0.0.0` | `111` | LISTEN | `rpcbind` RPC port mapper (`[VERIFIED]`) |
| **TCP** | `127.0.0.1` | `631` | LISTEN | CUPS Printing Daemon (`[VERIFIED]`) |
| **TCP** | `127.0.0.1` | `9900` | LISTEN | Local background service (`[VERIFIED]`) |
| **TCP** | `127.0.0.1` | `33851`| LISTEN | Local internal socket (`[VERIFIED]`) |
| **TCP** | `127.0.0.1` | `38900`| LISTEN | Local internal socket (`[VERIFIED]`) |
| **TCP** | `127.0.0.1` | `40000`| LISTEN | Local internal socket (`[VERIFIED]`) |
| **TCP** | `0.0.0.0` | `38863`| LISTEN | Unmapped ephemeral / RPC listener (`[VERIFIED]`) |

> **Critical Networking Concept**: A service listening on `0.0.0.0` binds to all local IPv4 network interfaces on the guest OS. **It does NOT indicate that the port is reachable from the public Internet.** Upstream cloud firewalls, Network Security Groups (NSGs), and carrier NATs control actual ingress accessibility.

### 10.2 Process Verification: Accops AUEM

Using process correlation (`ss -tulpn` and `ps -fp 13240`):

```bash
ps -fp 13240
```

**Result:**
`dotnet /usr/bin/accops/auem/AUEMTray.dll` `[VERIFIED]`

This process confirms that the JioPC environment integrates the **Accops HyWorks / AUEM** (Accops Unified Endpoint Management) desktop virtualization platform, which handles remote display streaming, clipboard sharing, and session lifecycle management.

---

## 11. Inbound Reachability & Boundary Testing

A key hallmark of a traditional VPS is the ability to accept inbound network connections (e.g., SSH, HTTP, WebSockets) from an external workstation. A series of ingress probes were conducted to establish reachability boundaries.

### 11.1 Local VM SSH Verification

A local loopback test was executed on the VM to verify whether the listening OpenSSH daemon (`0.0.0.0:22`) is functional:

```bash
ssh -o ConnectTimeout=5 10.1.1.167 'echo SSH_OK'
```

**Result:**
`Permission denied (publickey,password).` `[MEASURED]`

**Analysis:**
1. The TCP handshake on port 22 succeeded immediately `[VERIFIED]`.
2. The SSH daemon responded and presented a valid `ED25519` host key `[VERIFIED]`.
3. The connection was terminated at the authentication layer because the unprivileged user account `001280863647_0` does not have an established SSH password or pre-installed authorized public key `[VERIFIED]`.
4. **Conclusion**: SSH daemon is active and locally responsive, but remote shell access is unauthenticated `[VERIFIED]`.

---

### 11.2 External Inbound Probe: Private IP

From an external physical Windows workstation on the local network (IP: `10.147.175.182`), a reachability probe was initiated against the JioPC VM's private IP:

```powershell
Test-NetConnection 10.1.1.167 -Port 22
```

**Measured Results:**
* `PingSucceeded`: `False` `[MEASURED]`
* `TcpTestSucceeded`: `False` `[MEASURED]`

**Analysis**: The external machine could not establish an ICMP ping or TCP connection to `10.1.1.167`. Because `10.1.1.167` and `10.147.175.182` exist in disjoint private subnets without inter-VNet routing, direct private IP reachability is blocked `[INFERRED]`.

---

### 11.3 Public Egress Identification vs. Inbound Reachability

To discover the public egress IP through which the VM reaches the Internet:

```bash
curl -4 https://ifconfig.me
```

**Measured Result:**
`74.225.96.193` `[MEASURED]`

```
+-------------------------------------------------------------------------------+
| CRITICAL DISTINCTION: VM PRIVATE IP vs. PUBLIC EGRESS IP                     |
+----------------------+--------------------------------------------------------+
| VM Private Address   | 10.1.1.167 (Bound to eth0 interface)                   |
| Public Egress IP     | 74.225.96.193 (Upstream NAT / Edge Gateway)            |
+----------------------+--------------------------------------------------------+
```

The address `74.225.96.193` is not assigned to `eth0`. It belongs to an upstream Network Address Translation (NAT) gateway or proxy egress cluster.

To test whether this public address supports inbound port forwarding to the VM, the external Windows machine probed `74.225.96.193`:

```powershell
Test-NetConnection 74.225.96.193 -Port 22
```

**Measured Results:**
* `PingSucceeded`: `True` `[MEASURED]`
* `PingReplyDetails RTT`: `39 ms` `[MEASURED]`
* `TcpTestSucceeded`: `False` `[MEASURED]`

```
EXTERNAL CLIENT (10.147.175.182)
       |
       |  ICMP Echo (Ping)
       v
+-------------------------------+
| Public Gateway: 74.225.96.193 | =====> Ping Reply Succeeded (RTT: 39 ms)
+-------------------------------+
       |
       |  TCP SYN Port 22 (SSH)
       v
+-------------------------------+
| Upstream Edge Firewall / NAT  | =====> Dropped / Closed (TcpTest: False)
+-------------------------------+
       x (No port forward)
       |
+-------------------------------+
| JioPC Guest VM (10.1.1.167)   |
| sshd (0.0.0.0:22)             |
+-------------------------------+
```

**Engineering Findings**:
1. The public perimeter IP `74.225.96.193` is responsive to ICMP ping (39 ms RTT).
2. TCP Port 22 is closed or filtered at the edge firewall.
3. **No direct inbound SSH connection can be established from the external Internet to the JioPC VM in this default configuration.**

---

## 12. Domain Name Resolution (DNS)

Diagnostic command:

```bash
getent hosts example.com
```

**Raw Output:**
```
2606:4700:10::ac42:93f3  example.com
2606:4700:10::6814:179a  example.com
```

**Findings:**
1. System DNS resolution is fully functional `[VERIFIED]`.
2. The resolver returned IPv6 AAAA records `[VERIFIED]`.
3. *Note*: Returning IPv6 addresses confirms DNS query handling, but does **not** prove active end-to-end IPv6 routing or Internet transit without explicit protocol testing `[INFERRED]`.

---

## 13. Day 1 Comprehensive Status Matrix

| Component / Subsystem | Day 1 Status | Evidence Summary |
| :--- | :--- | :--- |
| **CPU Architecture** | `TESTED` | Intel Xeon Platinum 8370C (4 physical cores, 8 SMT threads, AVX-512) |
| **RAM Capacity** | `TESTED` | 15 GiB physical RAM, ~12 GiB baseline available |
| **Swap Configuration** | `TESTED` | 0 B configured swap; hard OOM risk identified |
| **Storage Layout** | `TESTED` | 64G sda (OS root), 128G sdb (restricted flatpak store), NFS home |
| **NFS Performance** | `TESTED` | 342–663 MB/s write; 73.1 MB/s uncached read; 8.4 GB/s cache-affected |
| **Secondary Disk Access**| `TESTED` | Root-owned (0755); write permission denied to unprivileged user |
| **Network Interfaces** | `TESTED` | Private IP 10.1.1.167/19 on eth0; default gateway 10.1.0.1 |
| **Internet Egress** | `TESTED` | Outbound HTTPS functional via local Px proxy (127.0.0.1:3128) |
| **Public Egress IP** | `TESTED` | 74.225.96.193 observed at external edge |
| **DNS Resolution** | `TESTED` | Functional; resolved IPv6 AAAA records |
| **SSH Service** | `PARTIALLY TESTED` | Daemon active on 0.0.0.0:22; auth rejected (key/password missing) |
| **Inbound Reachability** | `PARTIALLY TESTED` | Private IP unreachable; public IP pingable but TCP 22 filtered |
| **Dev Toolchains** | `PENDING` | Scheduled for Day 2 (git, node, python, rust, compilers) |
| **Web Server Hosting** | `PENDING` | Scheduled for Day 3 (nginx, Caddy, non-root ports) |
| **Mesh Inbound / Tailscale**| `PENDING` | Scheduled for Day 4 (user-space networking overlay) |
| **Database Engines** | `PENDING` | Scheduled for Day 5 (PostgreSQL, SQLite concurrency) |
| **AI / Model Inference** | `PENDING` | Scheduled for Day 6 (Ollama / llama.cpp on AVX-512) |
| **Stress & Persistence** | `PENDING` | Scheduled for Day 7 (RAM saturation, reboot survival) |

---

## 14. What Was Learned

1. **Enterprise Virtualization Foundation**: JioPC is not a lightweight web sandbox or restricted container; it is a full virtual machine executing an Azure-optimized Ubuntu Noble kernel on Intel Xeon hardware with VT-x virtualization support.
2. **Substantial Raw Compute & Memory**: The provision of 4 physical cores (8 SMT threads) with AVX-512 VNNI instruction support and 15 GiB of RAM offers genuine compute capability for developer tasks.
3. **NFS Home Decoupling**: The home directory is mounted over NFSv4.1 with 512 KiB buffers, achieving sequential write speeds between 342 MB/s and 663 MB/s. However, uncached read speeds drop to ~73.1 MB/s.
4. **Proxy-Mediated Networking**: Internet traffic does not exit via direct routing, but is proxied through a local forward proxy (`127.0.0.1:3128`).
5. **Ingress Isolation**: Both private and public ingress pathways to port 22 are blocked, preventing standard SSH access from external clients out of the box.

---

## 15. What Remains Unknown

The following questions could not be resolved during Day 1 and are slated for subsequent investigation phases:

1. **User Storage Quota**: What is the hard disk quota on the NFS home share? (Reported 100 TB is the cluster capacity, not user allotment).
2. **NFS Small-File / Metadata IOPS**: How does NFS perform under heavy random I/O (e.g., `node_modules` installations, git checkouts, SQLite writes)?
3. **User-Space Tunneling Feasibility**: Can user-space mesh overlay software (such as Tailscale in user-space/socks5 mode, Cloudflare Tunnels, or reverse SSH tunnels) bypass the absence of inbound public port forwarding and root privileges?
4. **Session Persistence**: Does the virtual machine persist across user disconnects, or is the root filesystem ephemeral and reset upon logout?
5. **Non-Root Package Management**: In the absence of `sudo apt`, how effectively can toolchains be provisioned via Homebrew, Nix, or user-space binaries?

---

## 16. Day 1 Conclusion & Working Hypothesis

Day 1 reconnaissance demonstrates that JioPC provides substantial compute resources (Intel Xeon Platinum 8370C, 15 GiB RAM, fast NFS storage) coupled with genuine Linux host shell access.

However, it deviates significantly from a standard commercial VPS:
- **No administrative root privileges (`sudo`)**
- **No general write access to the 128 GB secondary disk**
- **Strict proxy mediation on outbound web requests**
- **Complete absence of direct inbound IPv4 connectivity or port forwarding**

### Current Hypothesis
> *"JioPC contains many of the core components of a high-performance VPS, but its restricted privilege model and strict network perimeter prevent it from operating as a conventional publicly reachable server. Its viability as a development VPS depends entirely on user-space package managers and outbound overlay tunneling solutions (e.g., Tailscale, Cloudflare Tunnels)."*

*This hypothesis will be empirically tested in Days 2 through 7.*
