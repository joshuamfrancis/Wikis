# Citrix – Overview, Delivery Patterns and Architecture

## What is Citrix?

Citrix is a virtualization and remote-delivery platform. Applications and desktops run on servers or virtual machines in a datacenter or cloud. Only screen updates, keyboard, mouse, audio, printing and USB redirection travel to the user's device, over Citrix's **HDX/ICA** protocol. Data stays central and the endpoint can be almost anything: a Windows laptop, Mac, Linux box, thin client, tablet or browser.

The core product, historically XenApp and XenDesktop, is now **Citrix Virtual Apps and Desktops** when you run it yourself, and **Citrix DaaS** when Citrix hosts the control plane in Citrix Cloud. The gateway product, once Citrix ADC or Citrix Gateway, is now branded **NetScaler** again. Product names have changed several times, so check current Citrix docs for exact SKUs.

## Usage (delivery) patterns

| Pattern | Where it runs | What the user sees | Typical use |
|---|---|---|---|
| **Published app** (hosted shared app) | Multi-session Windows Server VM (RDS host); many users share one VM | Only the app window, appearing "seamlessly" next to local apps | Line-of-business apps, ERP clients, apps that need to sit close to their database |
| **Hosted shared desktop** | Same multi-session Server OS VM | A full desktop, but shared with other users on that VM | Task workers, call centres; cheapest per user |
| **VDI (virtual desktop)** | Single-session Windows 10/11 VM, one user per VM | A full personal desktop | Knowledge workers, developers, admin rights or custom software |
| ↳ *Pooled / random (non-persistent)* | Reset at logoff, from a golden image | Same, but changes are discarded | Scale and easy patching |
| ↳ *Static / dedicated (persistent)* | Same VM every time, changes kept | Same, with changes kept | Power users |
| **VM-hosted app** | App published from a single-session VDI VM | Seamless app window | Apps that won't run on Windows Server or multi-session |
| **Remote PC Access** | The user's real physical office PC with a VDA installed | Their own physical desktop, remotely | Work from home without building VDI; GPU or special-hardware desks |

Related options include Citrix Secure Browser (a hosted, isolated browser), Local App Access, App Layering, and app streaming through App-V or MSIX app attach. All of these build on the same core components.

## Components

**User / edge**

- **Citrix Workspace app**: the client (HDX receiver) on the endpoint.
- **NetScaler Gateway**: sits in the DMZ. It handles authentication, MFA and SSL termination, and acts as an ICA proxy so external users never connect directly to internal VMs.

**Access & control plane**

- **StoreFront**: the web or store service that lists the apps and desktops a user is entitled to and generates the launch (`.ica`) file. In DaaS this role is played by Citrix Workspace in the cloud.
- **Delivery Controller (DDC)**: the brain. It runs the Broker service (which VDA gets the session), Machine Creation Services, the Host service (power control of VMs via the hypervisor or cloud API), and the Secure Ticket Authority (STA).
- **SQL Server**: holds the Site, Monitoring and Configuration Logging databases.
- **License Server**: issues Citrix licences.
- **Studio / Web Studio**: the admin console. **Director**: monitoring and helpdesk console.
- **Cloud Connector**: used only with DaaS. It replaces the on-prem DDC and StoreFront link to Citrix Cloud.

**Image & workload**

- **VDA (Virtual Delivery Agent)**: installed *inside* every machine that delivers sessions. It registers with the DDC and serves HDX sessions. It comes in three variants: multi-session (Server OS), single-session (desktop OS), and Remote PC Access.
- **Provisioning Services (PVS)** or **MCS**: build or stream VMs from one golden image.
- **Hypervisor / cloud**: vSphere, Hyper-V, XenServer, Nutanix AHV, AWS EC2 or Azure, reached through a "hosting connection."

**Supporting**

- Active Directory and DNS.
- File servers for user profiles (Citrix Profile Management or FSLogix).
- Optional extras: Workspace Environment Management (WEM), Federated Authentication Service, and Session Recording.

## Architecture diagram (on-prem / self-managed)

```mermaid
%%{init: {"theme":"base","themeVariables":{"fontFamily":"Arial","fontSize":"14px","lineColor":"#334155","edgeLabelBackground":"#FFFFFF","textColor":"#0F172A"}}}%%
flowchart TB
  subgraph EP["User endpoint (Windows / Mac / Linux / thin client / browser)"]
    WA["Citrix Workspace app<br/>(HDX / ICA client)"]
  end

  subgraph DMZ["DMZ"]
    GW["NetScaler Gateway<br/>(auth, MFA, SSL, ICA proxy)"]
  end

  subgraph CTRL["Datacenter / VPC – access & control tier"]
    SF["StoreFront<br/>(enumerate apps, build .ica file)"]
    DDC["Delivery Controller<br/>Broker · MCS · Host svc · STA"]
    SQL[("SQL Server<br/>Site · Monitoring · Logging DBs")]
    LIC["Citrix License Server"]
    STUDIO["Web Studio<br/>(admin console)"]
    DIR["Director<br/>(monitoring / helpdesk)"]
    PVS["Provisioning Services<br/>(optional vDisk streaming)"]
  end

  subgraph SUP["Supporting services"]
    AD["Active Directory / DNS"]
    FS[("File server<br/>profiles · FSLogix · home drives")]
  end

  subgraph HV["Hypervisor host or cloud region<br/>(vSphere / Hyper-V / XenServer / AWS EC2 / Azure)"]
    subgraph RDSH["Multi-session Server OS VM (Windows Server + RDS)"]
      VDA1["VDA – multi-session"]
      PAPP["Published apps<br/>(seamless windows)"]
      HSD["Hosted shared desktops"]
    end
    subgraph VDI["Single-session OS VM (Windows 10/11)"]
      VDA2["VDA – single-session"]
      VDESK["VDI desktop<br/>(pooled or dedicated)<br/>+ VM-hosted apps"]
    end
  end

  subgraph PHYS["Physical office PC"]
    VDA3["VDA – Remote PC Access"]
    PCDESK["User's own physical desktop"]
  end

  %% user access path
  WA -- "HTTPS 443" --> GW
  GW -- "auth + enumeration" --> SF
  GW -- "STA ticket validation" --> DDC
  SF -- "XML / HTTPS" --> DDC
  SF -. "user auth" .-> AD

  %% control plane
  DDC --> SQL
  DDC --> LIC
  DDC -- "hosting connection<br/>(power mgmt / MCS)" --> HV
  STUDIO --> DDC
  DIR --> DDC
  PVS -. "streams golden image" .-> RDSH
  PVS -. "streams golden image" .-> VDI

  %% VDA registration
  VDA1 -- "register (TCP 80/443)" --> DDC
  VDA2 -- "register" --> DDC
  VDA3 -- "register" --> DDC

  %% HDX session path
  GW == "HDX / ICA 1494 · 2598<br/>(TCP or UDP-EDT)" ==> VDA1
  GW == "HDX / ICA" ==> VDA2
  GW == "HDX / ICA" ==> VDA3

  %% workload dependencies
  VDA1 --- PAPP
  VDA1 --- HSD
  VDA2 --- VDESK
  VDA3 --- PCDESK
  RDSH -. "logon / GPO / profiles" .-> AD
  RDSH -.-> FS
  VDI -. "logon / GPO / profiles" .-> AD
  VDI -.-> FS

  %% ---------- node styles (light fill + dark text) ----------
  classDef client  fill:#DBEAFE,stroke:#1E40AF,stroke-width:2px,color:#0B1F4D
  classDef dmz     fill:#FEE2E2,stroke:#B91C1C,stroke-width:2px,color:#450A0A
  classDef control fill:#EDE9FE,stroke:#5B21B6,stroke-width:2px,color:#2E1065
  classDef data    fill:#FEF3C7,stroke:#B45309,stroke-width:2px,color:#451A03
  classDef support fill:#E5E7EB,stroke:#374151,stroke-width:2px,color:#111827
  classDef vda     fill:#BBF7D0,stroke:#15803D,stroke-width:2px,color:#052E16
  classDef workload fill:#FFFFFF,stroke:#15803D,stroke-width:1.5px,color:#052E16

  class WA client
  class GW dmz
  class SF,DDC,LIC,STUDIO,DIR,PVS control
  class SQL,FS data
  class AD support
  class VDA1,VDA2,VDA3 vda
  class PAPP,HSD,VDESK,PCDESK workload

  %% ---------- subgraph (zone) styles ----------
  style EP   fill:#EFF6FF,stroke:#1E40AF,stroke-width:2px,color:#0B1F4D
  style DMZ  fill:#FEF2F2,stroke:#B91C1C,stroke-width:2px,color:#450A0A
  style CTRL fill:#F5F3FF,stroke:#5B21B6,stroke-width:2px,color:#2E1065
  style SUP  fill:#F3F4F6,stroke:#374151,stroke-width:2px,color:#111827
  style HV   fill:#F0FDF4,stroke:#15803D,stroke-width:2px,color:#052E16
  style RDSH fill:#DCFCE7,stroke:#166534,stroke-width:1.5px,color:#052E16
  style VDI  fill:#DCFCE7,stroke:#166534,stroke-width:1.5px,color:#052E16
  style PHYS fill:#ECFDF5,stroke:#166534,stroke-width:2px,stroke-dasharray:5 3,color:#052E16
```

**How to read it:** thick arrows (`==>`) are the actual screen and keyboard session traffic. Thin arrows are control and brokering traffic. Dotted arrows are image, identity and profile dependencies. Internal users on the corporate network usually skip the Gateway and go straight from Workspace app to StoreFront, then directly to the VDA.

**Colour key**

| Colour | What it marks |
|---|---|
| Blue | Endpoint / client |
| Red | DMZ / gateway |
| Purple | Citrix control plane |
| Amber | Data stores |
| Grey | Directory services |
| Green | VDAs and the workloads they host. The physical PC zone has a dashed border to show it isn't a VM. |

## Launch sequence (what happens when a user clicks an app)

```mermaid
sequenceDiagram
  autonumber
  actor U as User
  participant WA as Workspace app
  participant GW as NetScaler Gateway
  participant SF as StoreFront
  participant DDC as Delivery Controller (Broker + STA)
  participant VDA as VDA (on VM / PC)
  participant AD as Active Directory

  U->>WA: Open workspace, sign in
  WA->>GW: HTTPS 443 + credentials / MFA
  GW->>AD: Authenticate
  GW->>SF: Pass-through (SSO)
  SF->>DDC: Enumerate user's apps & desktops
  DDC-->>SF: Entitled resources
  SF-->>WA: Show app/desktop icons
  U->>WA: Click "SAP GUI"
  WA->>SF: Launch request
  SF->>DDC: Which VDA? (load-balanced)
  DDC->>VDA: Prepare session (power on VM if needed)
  DDC-->>SF: VDA address + STA ticket
  SF-->>WA: .ica launch file (ticket, not IP)
  WA->>GW: HDX connection with ticket
  GW->>DDC: Validate STA ticket → real VDA IP
  GW->>VDA: Proxy HDX / ICA (1494/2598)
  VDA->>AD: User logon, GPOs, profile load
  VDA-->>U: App window streamed to device
```

## Citrix DaaS (cloud-managed) variant

With DaaS, StoreFront (replaced by Workspace), the Delivery Controller, SQL, Studio, Director and licensing all move into Citrix Cloud. You run only the **Cloud Connectors**, at least two per resource location, plus the **VDAs** and AD. A NetScaler Gateway can also be swapped for the Citrix-hosted Gateway Service.

```mermaid
%%{init: {"theme":"base","themeVariables":{"fontFamily":"Arial","fontSize":"14px","lineColor":"#334155","edgeLabelBackground":"#FFFFFF","textColor":"#0F172A"}}}%%
flowchart LR
  subgraph CC["Citrix Cloud (Citrix-managed)"]
    WS["Citrix Workspace<br/>(replaces StoreFront)"]
    BRK["Cloud broker / Web Studio / Monitor / Licensing"]
    GWS["Gateway Service (optional)"]
  end
  subgraph RL["Your resource location (on-prem DC or AWS VPC)"]
    CON["Cloud Connectors (x2+)"]
    AD["Active Directory"]
    VDA["VDAs on VMs / EC2 / physical PCs"]
  end
  User["Workspace app"] -->|HTTPS| WS
  WS --> BRK
  BRK <-->|"outbound 443 only"| CON
  CON --> AD
  VDA -->|register| CON
  User ==>|HDX| GWS ==> VDA

  classDef cloud   fill:#EDE9FE,stroke:#5B21B6,stroke-width:2px,color:#2E1065
  classDef vda     fill:#BBF7D0,stroke:#15803D,stroke-width:2px,color:#052E16
  classDef client  fill:#DBEAFE,stroke:#1E40AF,stroke-width:2px,color:#0B1F4D
  classDef support fill:#E5E7EB,stroke:#374151,stroke-width:2px,color:#111827
  class WS,BRK,GWS cloud
  class VDA,CON vda
  class User client
  class AD support
  style CC fill:#F5F3FF,stroke:#5B21B6,stroke-width:2px,color:#2E1065
  style RL fill:#F0FDF4,stroke:#15803D,stroke-width:2px,color:#052E16
```

For an AWS-based setup, this is the common shape: the VDAs and Cloud Connectors run on EC2 inside your VPC, and the hosting connection uses the AWS API to power instances on and off.
