# Exchange Online Mailbox Optimization & Shared Mailbox Management

![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue?logo=powershell)
![Exchange Online](https://img.shields.io/badge/Exchange-Online-0078D4?logo=microsoft)
![Microsoft 365](https://img.shields.io/badge/Microsoft-365-0078D4?logo=microsoftazure)
![License](https://img.shields.io/badge/license-MIT-green)

PowerShell toolkit and runbooks for Exchange Online mailbox optimization — including shared mailbox auditing, online archive enablement, sent items fix, and Outlook performance tuning in RDS/RDP environments.

> Built from a real engagement with a logistics company operating 20+ shared mailboxes totalling over 150 GB of unarchived mail.

---

## Project Overview

This project documents the remediation of an Exchange Online environment where multiple shared mailboxes had grown to critical sizes, archiving had never been enabled, and Outlook performance was degraded in a Remote Desktop Server (RDS) environment.

**Environment scale:** 25 mailboxes audited — 20 shared mailboxes + 5 user mailboxes. Largest single mailbox: 49.49 GB. Total unarchived mail across shared mailboxes exceeded 75 GB before remediation.

---

## Environment

| Component | Details |
|---|---|
| Email Platform | Microsoft 365 / Exchange Online |
| Client | Outlook Classic (desktop) |
| Access Model | Remote Desktop Server (RDS/RDP) |
| Mailbox Types | Shared Mailboxes + User Mailboxes |
| Archiving | Online Archive (Exchange Online Archiving) |
| Admin Tools | Exchange Admin Center + PowerShell (ExchangeOnlineManagement) |

---

## Problem Statement

| Issue | Impact |
|---|---|
| No online archiving enabled on any mailbox | Primary mailboxes approaching Exchange Online limits |
| Shared mailbox Sent Items not copying correctly | Sent emails lost from shared mailbox history |
| Large mailboxes in RDS environment | Outlook slow to load, sync, and search |
| No visibility into shared mailbox permissions | Unknown who had Full Access / Send As rights |
| Inconsistent mailbox rule behavior | Rules firing incorrectly or not at all |

---

## Mailbox Size Snapshot (Before Remediation)

Key mailboxes identified as critical before archiving:

| Mailbox | Type | Size Before Archive |
|---|---|---|
| User — Executive 1 | User | 49.49 GB |
| User — Executive 2 | User | 48.97 GB |
| Shared — Business Unit 1 | Shared | 15.96 GB |
| Shared — Accounts Payable | Shared | 14.58 GB |
| User — Manager 1 | User | 11.89 GB |
| Shared — Business Unit 2 | Shared | 9.68 GB |
| Shared — Business Unit 3 | Shared | 8.115 GB |
| Shared — Business Unit 4 | Shared | 7.875 GB |
| Shared — Business Unit 5 | Shared | 7.355 GB |
| Shared — Operations | Shared | 4.893 GB |

---

## Scripts

### 1. `shared_mailbox_audit.ps1` — Shared Mailbox Permission Audit

Enumerates all shared mailboxes and outputs a full permission report covering Full Access, Send As, and Send on Behalf grants.

```powershell
# Connect to Exchange Online first, then run:
.\shared_mailbox_audit.ps1
# Output: SharedMailbox_Full_Audit.csv
```

**Output columns:** SharedMailbox, EmailAddress, User, PermissionType

---

### 2. `shared_mailbox_sentitems_fix.ps1` — Sent Items Copy Fix

Enables `MessageCopyForSentAsEnabled` and `MessageCopyForSendOnBehalfEnabled` on all shared mailboxes so sent emails are stored in the shared mailbox Sent Items — not lost in the sender's personal mailbox.

```powershell
.\shared_mailbox_sentitems_fix.ps1
# Auto-connects to Exchange Online
# Output: shared-mailbox-sent-items-report.csv
```

**Before fix:** Emails sent from a shared mailbox appeared only in the individual sender's Sent Items.  
**After fix:** Emails appear in the shared mailbox Sent Items, visible to all members.

---

### 3. `Archive_after_1_year.ps1` — Online Archive Enablement (1-Year Policy)

Enables Online Archive on all user and shared mailboxes, creates a retention tag to move mail older than 1 year to archive, and links the tag to the Default MRM Policy.

```powershell
.\Archive_after_1_year.ps1
# Output: C:\Temp\Archive_Enablement_Report.csv
```

**What it does:**
1. Creates an `Archive after 1 year` retention tag if not present
2. Links tag to the Default MRM Policy
3. Enables Online Archive on all user + shared mailboxes
4. Generates a CSV report of all changes

---

### 4. `Enable_Archive_6Months_AllMailboxes.ps1` — Archive Enablement (6-Month Policy)

Variant of the archive script with a 6-month retention threshold — for environments requiring faster mailbox size reduction.

---

### 5. `Audit-MailboxSpace.ps1` — Mailbox Size Audit

Reports mailbox sizes, item counts, and archive status across all mailboxes. Run this before and after archiving to measure impact.

```powershell
.\Audit-MailboxSpace.ps1
# Output: MailboxSizes report with TotalItemSize and ArchiveStatus
```

---

## Shared Mailbox Configuration Guide

See `docs/Shared-Mailbox-Configuration-Guide.md` for step-by-step instructions covering:

- Converting a licensed mailbox to a shared mailbox
- Assigning Full Access and Send As permissions (and why to avoid Send on Behalf)
- Configuring email forwarding via mail flow rules
- Optimizing Outlook for shared mailbox use in RDS environments
- Caching configuration for RDP/RDS Outlook deployments

---

## RDS / Outlook Performance Optimization

Key recommendations applied in this engagement for Outlook running in an RDS environment:

- Disable Cached Exchange Mode for shared mailboxes accessed over RDP
- Separate shared mailbox accounts to prevent OST bloat
- Reduce primary mailbox sizes via archiving before enabling Cached Exchange Mode
- Tune OST file location to local temp storage on RDS hosts
- Rebuild OST cache after major mailbox restructuring

---

## Repository Structure

| Path | Description |
|---|---|
| `scripts/shared_mailbox_audit.ps1` | Full permission audit for all shared mailboxes |
| `scripts/shared_mailbox_sentitems_fix.ps1` | Fix sent items copy for Send As / Send on Behalf |
| `scripts/Archive_after_1_year.ps1` | Enable archive + 1-year retention policy |
| `scripts/Enable_Archive_6Months_AllMailboxes.ps1` | Enable archive + 6-month retention policy |
| `scripts/Audit-MailboxSpace.ps1` | Mailbox size and archive status report |
| `scripts/Mailboxes_List.ps1` | Enumerate all mailboxes with type and address |
| `docs/Shared-Mailbox-Configuration-Guide.md` | Step-by-step shared mailbox setup guide |
| `docs/rdp-outlook-optimization.md` | Outlook performance tuning for RDS environments |
| `reports/` | Sample audit CSV and report outputs |

---

## Prerequisites

| Requirement | Details |
|---|---|
| PowerShell | 5.1 or later |
| Module | `ExchangeOnlineManagement` (auto-installed by scripts) |
| M365 Role | Exchange Administrator or Global Administrator |
| Licenses | Exchange Online Plan 2 or Exchange Online Archiving add-on required for Online Archive |

---

## Typical Consulting Use Cases

| Scenario | Script / Artifact |
|---|---|
| Audit who has access to shared mailboxes | `shared_mailbox_audit.ps1` |
| Fix missing sent items in shared mailboxes | `shared_mailbox_sentitems_fix.ps1` |
| Reduce mailbox sizes before hitting quotas | `Archive_after_1_year.ps1` |
| Baseline mailbox sizes before/after changes | `Audit-MailboxSpace.ps1` |
| Set up a new shared mailbox from scratch | `docs/Shared-Mailbox-Configuration-Guide.md` |
| Improve Outlook performance on RDS | `docs/rdp-outlook-optimization.md` |

---

## License

[MIT](LICENSE) — free to use, adapt, and share.

---

## Author

**Suresh Chand** — Director of IT | Enterprise Infrastructure & Security Engineer  
📍 San Jose, CA &nbsp;|&nbsp; 📧 [suresh@echand.com](mailto:suresh@echand.com) &nbsp;|&nbsp; 💼 [LinkedIn](https://linkedin.com/in/sureshchand01) &nbsp;|&nbsp; 🐙 [GitHub](https://github.com/suresh-1001)
