# Day 1: Architecture & Topology Diagrams

This document collects architectural schematics, network topologies, and benchmark visualizations produced during Day 1 (*Infrastructure Reconnaissance*) of the 7-day JioPC empirical evaluation.

---

## 1. Overall JioPC Architecture

High-level decomposition of the virtualized environment, showing the hypervisor layer, guest operating system, containerized user session, local block devices, and remote storage mounts.

```mermaid
graph TB
    subgraph CloudInfra["Cloud Infrastructure (Microsoft Azure / Jio Data Center)"]
        HV["Microsoft Hypervisor (VT-x Enabled)"]
        SAN["Remote Enterprise Storage Cluster<br/>(100 TB NFSv4.1 Export)"]
        GW["Upstream Gateway / NAT / Firewall Router<br/>10.1.0.1"]
    end

    subgraph VM["JioPC Virtual Machine (Linux edcjp-0013 / 6.17.0-1022-azure)"]
        subgraph HardwareVirt["Virtual Hardware Allocation"]
            CPU["Intel Xeon Platinum 8370C @ 2.80GHz<br/>4 Cores / 8 SMT Threads / 48 MiB L3"]
            RAM["15 GiB Physical RAM (0 B Swap)"]
            NIC["eth0 (10.1.1.167/19) + enP39396s1"]
            SDA["sda (64 GiB SCSI Disk)"]
            SDB["sdb (128 GiB SCSI Disk)"]
        end

        subgraph OS["Host OS: Ubuntu Noble (Non-Root User: 001280863647_0)"]
            ROOT_FS["/ (sda1: 63 GiB ext4)"]
            SEC_FS["/mnt/sfdisk (sdb1: 128 GiB ext4)<br/>Root-owned (drwxr-xr-x)"]
            HOME_FS["/home/001280863647_0 (NFSv4.1 Mount)"]
            
            subgraph Services["Background Daemons"]
                SSHD["sshd (0.0.0.0:22)"]
                XRDP["RDP Server (0.0.0.0:3389)"]
                PX["Px Forward Proxy (127.0.0.1:3128)"]
                ACCOPS["Accops AUEM Tray (PID 13240)"]
            end

            subgraph Runtime["Application Layer"]
                FLATPAK["Flatpak Sandboxed Runtime<br/>(Freedesktop SDK / VSCodium)"]
                SPAWN["flatpak-spawn --host<br/>(Direct Host Shell Access)"]
            end
        end
    end

    HV --> HardwareVirt
    NIC <-->|Private L2/L3 Network| GW
    HOME_FS <-->|TCP / NFSv4.1 / rsize=wsize=524288| SAN
    SDA --> ROOT_FS
    SDB --> SEC_FS
    FLATPAK --> SPAWN --> OS
    Services -.-> OS
```

---

## 2. CPU Topology

Empirical topology of the compute subsystem determined from `lscpu`. The 8 logical processors reported to the OS stem from 4 physical execution cores leveraging 2-way Simultaneous Multithreading (SMT).

```mermaid
graph TB
    subgraph Socket0["Socket 0: Intel Xeon Platinum 8370C @ 2.80GHz"]
        subgraph L3["Unified L3 Cache: 48 MiB"]
            subgraph Core0["Physical Core 0"]
                L1_0["L1/L2 Cache"]
                CPU0["Logical CPU 0<br/>(Thread 0)"]
                CPU4["Logical CPU 4<br/>(Thread 1)"]
            end

            subgraph Core1["Physical Core 1"]
                L1_1["L1/L2 Cache"]
                CPU1["Logical CPU 1<br/>(Thread 0)"]
                CPU5["Logical CPU 5<br/>(Thread 1)"]
            end

            subgraph Core2["Physical Core 2"]
                L1_2["L1/L2 Cache"]
                CPU2["Logical CPU 2<br/>(Thread 0)"]
                CPU6["Logical CPU 6<br/>(Thread 1)"]
            end

            subgraph Core3["Physical Core 3"]
                L1_3["L1/L2 Cache"]
                CPU3["Logical CPU 3<br/>(Thread 0)"]
                CPU7["Logical CPU 7<br/>(Thread 1)"]
            end
        end
    end

    subgraph Flags["Key Instruction Sets Detected"]
        F1["AVX (Advanced Vector Extensions)"]
        F2["AVX2 (256-bit Vector Math)"]
        F3["AVX-512 (512-bit Vector Math)"]
        F4["AVX-512 VNNI (Vector Neural Network Instructions)"]
    end

    L3 --- Flags
```

---

## 3. Storage Architecture

Hierarchical disk layout distinguishing local block devices from remote networked file storage.

```mermaid
graph TD
    subgraph RootDisk["Local Block Device: sda (64 GiB)"]
        sda15["sda15 (106 MiB vfat) -> /boot/efi"]
        sda16["sda16 (913 MiB ext4) -> /boot"]
        sda1["sda1 (63 GiB ext4) -> / (Root Filesystem)<br/>[Read-Write, System Binaries, Non-Root Home Parent]"]
    end

    subgraph SecondaryDisk["Local Block Device: sdb (128 GiB)"]
        sdb1["sdb1 (128 GiB ext4) -> /mnt/sfdisk<br/>drwxr-xr-x root:root<br/>Unprivileged user: Write Denied at Root"]
        subgraph FlatpakData["Writable Subdirectories: /mnt/sfdisk/flatpak/"]
            FP_APP["app/"]
            FP_RUNTIME["runtime/"]
            FP_REPO["repo/"]
            FP_EXP["exports/"]
        end
        sdb1 --> FlatpakData
    end

    subgraph RemoteNFS["Network Storage Backend (Enterprise SAN / NAS)"]
        NFS_SHARE["Remote Export: 100 TB Pool (759 GB used cluster-wide)<br/>Mount Target: /home/001280863647_0<br/>User Personal Quota: UNVERIFIED"]
    end

    JioPC_VM["JioPC Operating Environment"] --> RootDisk
    JioPC_VM --> SecondaryDisk
    JioPC_VM --> RemoteNFS
```

---

## 4. NFS Architecture & Protocol Pipeline

Data flow between user-space application processes and the remote enterprise storage backend via NFSv4.1.

```mermaid
sequenceDiagram
    autonumber
    participant App as User Application (dd / editor / compiler)
    participant VFS as Linux VFS & Page Cache (RAM)
    participant NFS_Client as In-Kernel NFS Client (vers=4.1, TCP)
    participant Net as Virtual Network Interface (eth0 / 10.1.1.167)
    participant NFS_Server as Remote NFS Storage Appliance

    App->>VFS: write(fd, buffer, 512 KiB)
    Note over VFS: Dirties kernel page cache.<br/>If conv=fdatasync, forces flush.
    VFS->>NFS_Client: Flush dirty pages via wsize=524288
    NFS_Client->>Net: Encapsulate in NFSv4.1 RPC over TCP
    Net->>NFS_Server: TCP Payload to remote storage port
    NFS_Server-->>Net: Commit ACK (hard mount: wait for completion)
    Net-->>NFS_Client: TCP ACK
    NFS_Client-->>VFS: File sync completed
    VFS-->>App: Return 0 (Write OK)
```

---

## 5. Network Topology & Interface Map

Logical network configuration showing VM interface assignments, private subnet addressing, default gateway, and public NAT egress point.

```mermaid
graph LR
    subgraph JioPC_VM["JioPC Virtual Machine"]
        LO["lo<br/>127.0.0.1/8"]
        ETH0["eth0<br/>10.1.1.167/19<br/>(Private IPv4)"]
        ENP["enP39396s1<br/>State: UP<br/>(Hypervisor Virtual Function)"]
    end

    subgraph InternalSubnet["Subnet: 10.1.0.0/19 (Broadcast: 10.1.31.255)"]
        GW["Default Gateway<br/>10.1.0.1 (via DHCP, metric 100)"]
    end

    subgraph EgressNAT["Upstream Network & Perimeter Gateway"]
        NAT["Stateful NAT / Edge Router<br/>Outbound Public IP: 74.225.96.193<br/>ICMP Echo: Responded (39 ms RTT)<br/>Inbound TCP 22: Closed / Filtered"]
    end

    subgraph ExternalInternet["Public Internet"]
        EXT_WEB["External Web Target<br/>(example.com / ifconfig.me)"]
    end

    ETH0 <-->|L2/L3 Private Traffic| GW
    GW <-->|Routing & Translation| NAT
    NAT <-->|Egress via Proxy / HTTP-HTTPS| EXT_WEB
```

---

## 6. Outbound Proxy Traffic Path

Path of outbound HTTP and HTTPS requests from user processes through the locally running `Px` forward proxy instance.

```mermaid
graph TD
    subgraph ClientLayer["Client Layer (JioPC Shell)"]
        CLI["CLI Tool / App (curl, apt, git, python)"]
        ENV["Environment Variables:<br/>HTTP_PROXY=http://127.0.0.1:3128<br/>HTTPS_PROXY=http://127.0.0.1:3128<br/>NO_PROXY=localhost,127.0.0.1,::1"]
    end

    subgraph LocalProxyLayer["Local Proxy Mediation Layer"]
        PX["Local Proxy Daemon (Px)<br/>127.0.0.1:3128<br/>(Proxy-Agent: Px)"]
    end

    subgraph UpstreamTransit["Enterprise Upstream Transit"]
        PROXY_FWD["Corporate / Cloud Upstream Proxy or NAT Gateway"]
    end

    subgraph RemoteServer["Public Internet"]
        DEST["Remote Host (e.g. https://example.com)"]
    end

    CLI -->|Read proxy config| ENV
    ENV -->|CONNECT or GET to 127.0.0.1:3128| PX
    PX -->|HTTP/1.1 200 Connection established| PROXY_FWD
    PROXY_FWD -->|Negotiate TLS / HTTP/2| DEST
    DEST -->>|Response stream| PROXY_FWD
    PROXY_FWD -->>|Relay| PX
    PX -->>|Forwarded response| CLI
```

---

## 7. Inbound vs. Outbound Connectivity Boundary

Matrix visualizing boundary enforcement: external traffic egress vs. ingress reachability on private and public IP endpoints.

```mermaid
flowchart TD
    subgraph InboundFlow["INBOUND REACHABILITY (Tested from External Windows 10.147.175.182)"]
        EXT_WIN["External Client<br/>10.147.175.182"]
        
        EXT_WIN -->|Test-NetConnection 10.1.1.167 -Port 22| TEST_PRIV["Private IP (10.1.1.167)"]
        TEST_PRIV --> PRIV_RES["Ping: FALSE<br/>TCP 22: FALSE<br/>Outcome: NO ROUTE / ISOLATED"]
        
        EXT_WIN -->|Test-NetConnection 74.225.96.193 -Port 22| TEST_PUB["Public Egress IP (74.225.96.193)"]
        TEST_PUB --> PUB_RES["Ping: TRUE (39 ms RTT)<br/>TCP 22: FALSE<br/>Outcome: EDGE DROPS / NO PORT FORWARD"]
    end

    subgraph OutboundFlow["OUTBOUND REACHABILITY (Tested from JioPC VM)"]
        JIOPC["JioPC VM<br/>10.1.1.167"]
        
        JIOPC -->|curl -I https://example.com via Px Proxy| OUT_HTTPS["Outbound HTTPS Egress"]
        OUT_HTTPS --> HTTPS_RES["HTTP/1.1 200 Connection established<br/>HTTP/2 200 OK<br/>Outcome: FUNCTIONAL"]
        
        JIOPC -->|getent hosts example.com| OUT_DNS["DNS Resolution"]
        OUT_DNS --> DNS_RES["IPv6 Addresses Returned<br/>Outcome: FUNCTIONAL"]
    end
```

---

## 8. Day 1 Experimental Workflow

Chronological flow of reconnaissance procedures executed during Day 1.

```mermaid
flowchart TD
    START([Day 1 Reconnaissance Initiated]) --> STEP1[1. Execution Context & Privileges<br/>- Discover Flatpak container runtime<br/>- Break out via flatpak-spawn --host<br/>- Audit user: 001280863647_0, non-root]
    STEP1 --> STEP2[2. Compute & Topology Audit<br/>- Execute lscpu<br/>- Identify Intel Xeon 8370C<br/>- Map 4 cores / 8 threads / AVX-512]
    STEP2 --> STEP3[3. Memory & Swap Inspection<br/>- Execute free -h<br/>- Measured 15 GiB RAM, 12 GiB avail<br/>- Flag 0 B swap as OOM risk]
    STEP3 --> STEP4[4. Storage Hierarchy Mapping<br/>- Audit lsblk & df -hT<br/>- Classify sda root vs sdb sfdisk<br/>- Discover NFS-backed /home directory]
    STEP4 --> STEP5[5. Storage Benchmarking<br/>- Test /mnt/sfdisk write: Permission Denied<br/>- NFS sequential write: 342 - 663 MB/s<br/>- NFS read: 8.4 GB/s cached vs 73.1 MB/s fresh]
    STEP5 --> STEP6[6. Network & Interface Discovery<br/>- Audit ip addr & ip route<br/>- Private IP: 10.1.1.167/19<br/>- Default Gateway: 10.1.0.1]
    STEP6 --> STEP7[7. Egress & Proxy Analysis<br/>- Discover HTTP_PROXY 127.0.0.1:3128<br/>- Verify HTTPS outbound with curl<br/>- Determine public egress IP: 74.225.96.193]
    STEP7 --> STEP8[8. Listening Ports & Inbound Boundary<br/>- Audit ss -tuln (SSH, RDP, Px, Accops)<br/>- Local SSH reaches daemon, auth rejected<br/>- External Windows probe fails on TCP 22]
    STEP8 --> FINISH([Formulate Day 1 Working Hypothesis])
```

---

## 9. Benchmark Visualizations

### Chart 1: NFS Write Throughput Comparison (MB/s)

Measurements taken with 2 GiB data payloads using `conv=fdatasync` to enforce physical storage synchronization.

```
NFS Sequential Write (Run 1)     [402 MB/s] | ████████████████████ (402)
NFS Sequential Write (Run 2)     [663 MB/s] | █████████████████████████████████ (663)
NFS Random Data Write (/dev/urandom) [342 MB/s] | █████████████████ (342)
                                            +---------+---------+---------+---------+
                                            0        200       400       600     800 MB/s
```

*Note: High variance (342 MB/s to 663 MB/s) illustrates dynamic backend shared storage behavior and burst buffering. No single throughput number characterizes the NFS tier.*

---

### Chart 2: NFS Read Throughput: Cached vs. Fresh File

Comparison highlighting the critical impact of Linux kernel page caching.

```
Fresh Uncached File Read           [73.1 MB/s]   | █ (73.1)
Cached / Immediate Reread [!]    [8400.0 MB/s]   | ████████████████████████████████████████ (8400)
                                                 +---------------------------------------+
                                                 0                                  9000 MB/s

[!] WARNING: The 8,400 MB/s figure reflects reading directly from system RAM (Linux Page Cache).
    It MUST NOT be interpreted as physical or networked NFS throughput.
    Real uncached read throughput over the network interface was measured at 73.1 MB/s.
```

---

### Chart 3: Storage Capacity & Utilization Overview

Comparison across storage tiers based on `df -hT` output.

| Storage Tier | Mount Point | Filesystem | Reported Size | Used Space | Available Space | Utilization % | Role / Accessibility |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Local OS Root** | `/` | ext4 (`sda1`) | 61 GB | 13 GB | 49 GB | 21% | Read-Write, System OS files, Non-root user writable in `/tmp` |
| **Local Secondary** | `/mnt/sfdisk` | ext4 (`sdb1`) | 126 GB | 71 GB | 49 GB | 59% | Root-owned; Flatpak runtime store; User write denied at root |
| **Remote Home** | `/home/001280863647_0` | nfs4 (`vers=4.1`) | 100 TB* | ~759 GB | ~99.2 TB | < 1% | Shared cluster pool export. **User quota is UNVERIFIED.** |

*\*CRITICAL CLARIFICATION: The 100 TB reported figure represents the aggregate capacity of the backend NFS export pool across the infrastructure. It does NOT denote an individual allocation or guaranteed quota for the user account.*
