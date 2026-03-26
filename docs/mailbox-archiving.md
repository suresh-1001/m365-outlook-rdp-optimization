# Mailbox Archiving Strategy

This document covers the design and implementation of Exchange Online Archiving (Online Archive) to reduce primary mailbox sizes, improve Outlook performance, and prevent mailboxes from hitting storage quotas.

---

## Why Archiving Was Critical in This Engagement

At the start of this engagement, **no mailboxes had archiving enabled**. The result:

| Problem | Impact |
|---|---|
| Primary mailboxes approaching 50 GB shared mailbox limit | Risk of mailbox being locked (no send/receive) |
| User mailboxes at 49+ GB | Outlook slow, OST file enormous, sync issues |
| No automated retention policy | Mail accumulating indefinitely with no cleanup |
| RDS/RDP environment with large OSTs | Severe Outlook performance degradation |

**Key mailbox sizes before archiving:**

| Mailbox | Type | Size |
|---|---|---|
| Executive 1 | User | 49.49 GB |
| Executive 2 | User | 48.97 GB |
| Business Unit 1 | Shared | 15.96 GB |
| Accounts Payable | Shared | 14.58 GB |
| Manager 1 | User | 26.10 GB |
| Business Unit 2 | Shared | 9.68 GB |
| Business Unit 3 | Shared | 8.12 GB |

---

## Exchange Online Storage Limits Reference

| Mailbox Type | Primary Limit | Archive Limit |
|---|---|---|
| User mailbox (Exchange Online Plan 1) | 50 GB | Not included |
| User mailbox (Exchange Online Plan 2) | 100 GB | Unlimited (auto-expanding) |
| Shared mailbox (no license) | 50 GB | Not included |
| Shared mailbox (EXO Plan 2 or EOA add-on) | 50 GB | Unlimited |

> ⚠️ Shared mailboxes require **Exchange Online Plan 2** or the **Exchange Online Archiving** add-on to enable Online Archive. A shared mailbox without a license cannot have an archive enabled.

---

## Archiving Strategy Chosen

**6-month retention policy** — mail older than 6 months moves automatically to the Online Archive.

This was chosen over 1-year because:
- Several mailboxes were already close to their quota limit
- The 6-month policy reduces primary mailbox sizes faster
- Users still retain full access to archived mail via Outlook

**Retention tag configuration:**

| Setting | Value |
|---|---|
| Tag name | Archive after 6 months |
| Tag type | Default (applies to all items) |
| Age limit | 180 days |
| Retention action | Move to Archive |
| Policy | Default MRM Policy |

---

## How Online Archive Works

```
Primary Mailbox (50 GB limit)          Online Archive (Unlimited*)
┌────────────────────────────┐         ┌──────────────────────────────┐
│  Recent mail (< 6 months)  │         │  Older mail (> 6 months)     │
│  Inbox                     │ ──────► │  Archive Inbox               │
│  Sent Items                │  MFA    │  Archive Sent Items          │
│  Folders                   │ runs    │  Archive Folders             │
│                            │  nightly│                              │
└────────────────────────────┘         └──────────────────────────────┘
       Outlook sees both seamlessly — users access archive in same interface
```

The **Managed Folder Assistant (MFA)** runs automatically (usually nightly) and moves items that meet the retention tag criteria. You can trigger it manually with `Start-ManagedFolderAssistant`.

---

## Implementation Scripts

### Script 1 — Enable Archive with 6-Month Policy (All Mailboxes)

[`scripts/Enable_Archive_6Months_AllMailboxes.ps1`](../scripts/Enable_Archive_6Months_AllMailboxes.ps1)

Covers:
- Checks and enables Organization Customization (required in some tenants)
- Creates the `Archive after 6 months` retention tag if not present
- Links the tag to the Default MRM Policy
- Enables Online Archive on all user + shared mailboxes
- Starts the Managed Folder Assistant on each mailbox
- Generates a detailed CSV report and log file

### Script 2 — Enable Archive with 1-Year Policy (Alternative)

[`scripts/Archive_after_1_year.ps1`](../scripts/Archive_after_1_year.ps1)

Use this for environments where a more gradual archiving pace is preferred.

### Script 3 — Mailbox Size Audit (Run Before and After)

[`scripts/Audit-MailboxSpace.ps1`](../scripts/Audit-MailboxSpace.ps1)

Run this before enabling archiving to baseline mailbox sizes. Run again after 24–48 hours (after MFA has processed) to measure the reduction.

---

## Step-by-Step: Enable Archiving

### Prerequisites

1. Ensure users have Exchange Online Plan 2 license OR Exchange Online Archiving add-on assigned
2. Connect to Exchange Online:

```powershell
Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
Import-Module ExchangeOnlineManagement
Connect-ExchangeOnline
```

### Run the Archiving Script

```powershell
# Enable archive + 6-month retention policy on all mailboxes
.\Enable_Archive_6Months_AllMailboxes.ps1

# Output files:
#   C:\Temp\Archive_Enablement_6Months_Report.csv
#   C:\Temp\Archive_Enablement_6Months_Log.txt
#   C:\Temp\Archive_Enablement_6Months_Transcript.txt
```

### Trigger MFA Manually (Speed Up Initial Archive)

After enabling the archive, the MFA runs automatically but you can trigger it immediately:

```powershell
# Trigger for a specific mailbox
Start-ManagedFolderAssistant -Identity "user@company.com"

# Trigger for all mailboxes (use carefully in large tenants)
Get-Mailbox -ResultSize Unlimited | ForEach-Object {
    Start-ManagedFolderAssistant -Identity $_.PrimarySmtpAddress
}
```

> ⚠️ `Start-ManagedFolderAssistant` queues the job — it doesn't run instantly. Large mailboxes (30–50 GB) may take 24–48 hours to fully archive.

---

## Validation Checklist

After running the archiving script:

- [ ] Archive status shows "Active" for all mailboxes: `Get-Mailbox -ResultSize Unlimited | Select DisplayName, ArchiveStatus`
- [ ] Retention policy shows "Default MRM Policy" on all mailboxes
- [ ] Run `Audit-MailboxSpace.ps1` — compare to pre-archive baseline
- [ ] Open Outlook for an affected user — confirm "Online Archive" folder appears in folder pane
- [ ] Check a heavy mailbox after 24–48 hours — primary mailbox size should be reducing

---

## User Communication Template

Send this to users before archiving runs:

> **Subject: Mailbox Archive Being Enabled — No Action Required**
>
> We are enabling the Online Archive feature for your mailbox. Emails older than 6 months will automatically move to your "Online Archive" folder, which you can access directly in Outlook.
>
> Your emails are not being deleted. They remain fully searchable and accessible at any time.
>
> No action is required on your part. If you have any questions, please contact IT.
