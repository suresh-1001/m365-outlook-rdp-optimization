# Shared Mailbox Architecture

This document covers the design and configuration of shared mailboxes in Exchange Online for a multi-user environment, based on a real engagement with a logistics company operating 20+ shared mailboxes.

---

## What Is a Shared Mailbox?

A shared mailbox in Exchange Online is a mailbox that multiple users can access without requiring a dedicated Microsoft 365 license (up to 50 GB). It has its own email address and can send and receive mail independently of any individual user.

**Common use cases:**
- Departmental inboxes (e.g., accounts@, operations@, support@)
- Partner-facing mailboxes (e.g., dhl@, vendor@)
- Shared team inboxes (e.g., quotes@, careers@)

---

## Architecture in This Engagement

This deployment managed **20 shared mailboxes** across multiple departments and business units, all hosted in Exchange Online.

```
Exchange Online Tenant
│
├── Shared Mailboxes (20)
│   ├── Accounts Payable          → 14.58 GB (before archive)
│   ├── Accounts Receivable       → 9.68 GB  (before archive)
│   ├── Business Unit 1           → 15.96 GB (before archive)
│   ├── Business Unit 2           → 8.12 GB  (before archive)
│   ├── Business Unit 3           → 7.88 GB  (before archive)
│   ├── Business Unit 4           → 7.36 GB  (before archive)
│   ├── Operations Team           → 2.05 GB  (before archive)
│   └── [additional mailboxes...] → various
│
└── User Mailboxes (5)
    ├── Executive 1               → 49.49 GB (before archive)
    ├── Executive 2               → 48.97 GB (before archive)
    ├── Manager 1                 → 26.10 GB (before archive)
    ├── Manager 2                 → 11.89 GB (before archive)
    └── User 1                   → 351 MB
```

**Total unarchived data before remediation: >150 GB**

---

## Permission Model

Each shared mailbox uses a combination of three permission types:

| Permission Type | What It Does | When to Use |
|---|---|---|
| **Full Access** | User can open and read the mailbox | All users who need to see the mailbox |
| **Send As** | Emails appear as coming from the shared mailbox address | Primary senders — most common choice |
| **Send on Behalf** | Emails show "User on behalf of SharedMailbox" | Avoid — confusing for recipients |

> ⚠️ **Do not use "Send on Behalf"** for business mailboxes. Recipients see "User on behalf of shared@company.com" which looks unprofessional. Always use "Send As" instead.

---

## Sent Items Problem (Common in All Exchange Online Environments)

**Default behavior (broken):** When a user sends an email from a shared mailbox, the sent copy goes to *that user's personal Sent Items* — not to the shared mailbox Sent Items. Other members of the shared mailbox cannot see what was sent.

**Fix:** Enable `MessageCopyForSentAsEnabled` and `MessageCopyForSendOnBehalfEnabled` on all shared mailboxes.

See [`scripts/shared_mailbox_sentitems_fix.ps1`](../scripts/shared_mailbox_sentitems_fix.ps1) — this script fixes all shared mailboxes in the tenant in one run.

**After fix:** Sent emails appear in the shared mailbox Sent Items folder, visible to all members with Full Access.

---

## Converting a Licensed Mailbox to a Shared Mailbox

When a user leaves or a role-based mailbox is created:

1. Log into **Microsoft 365 Admin Center** → https://admin.microsoft.com
2. Navigate to: **Users → Active Users**
3. Select the user account to convert
4. In the mailbox panel → click **Convert to Shared Mailbox**
5. Confirm the conversion

Once converted:
- The mailbox no longer requires a Microsoft 365 license (up to 50 GB)
- Remove the license from the user account to reclaim it
- Assign Full Access and Send As permissions to the appropriate users

> ⚠️ If the shared mailbox exceeds 50 GB, it requires an **Exchange Online Archiving** add-on or an **Exchange Online Plan 2** license to enable Online Archive.

---

## Assigning Permissions

### Full Access (via Exchange Admin Center)

1. Go to **Exchange Admin Center** → https://admin.exchange.microsoft.com
2. Navigate to: **Recipients → Mailboxes → Shared**
3. Select the shared mailbox
4. Go to: **Mailbox Delegation → Read and Manage (Full Access)**
5. Click **Edit** → Add the user(s)
6. Save

### Send As (via Exchange Admin Center)

1. Same path as above
2. Go to: **Mailbox Delegation → Send As**
3. Click **Edit** → Add the user(s)
4. Save

### Via PowerShell (Bulk Assignment)

```powershell
# Grant Full Access
Add-MailboxPermission -Identity "sharedmailbox@company.com" `
    -User "user@company.com" `
    -AccessRights FullAccess `
    -InheritanceType All `
    -AutoMapping $true

# Grant Send As
Add-RecipientPermission -Identity "sharedmailbox@company.com" `
    -Trustee "user@company.com" `
    -AccessRights SendAs `
    -Confirm:$false
```

---

## Email Forwarding via Mail Flow Rules

If additional users need copies of incoming mail without accessing the mailbox directly:

1. Go to **Exchange Admin Center → Mail Flow → Rules**
2. Create a new rule:
   - **Condition:** Sent to `sharedmailbox@company.com`
   - **Action:** Forward a copy to `user@company.com` using redirect
   - **Exceptions:** Add as needed
3. Name the rule and set priority
4. Enable the rule

> Use forwarding rules sparingly — they can cause mail loops if misconfigured and add latency to delivery.

---

## Audit — Who Has Access to What

Use [`scripts/shared_mailbox_audit.ps1`](../scripts/shared_mailbox_audit.ps1) to generate a full permission report across all shared mailboxes in the tenant.

**Output columns:** SharedMailbox, EmailAddress, User, PermissionType (FullAccess / SendAs / SendOnBehalf)

Run this before any permission changes and keep a copy as a baseline.
