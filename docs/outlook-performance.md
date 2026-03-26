# Outlook Performance Troubleshooting

General Outlook performance troubleshooting guide for Exchange Online environments, covering both desktop and RDS/RDP deployments.

---

## Common Symptoms and Causes

| Symptom | Likely Cause |
|---|---|
| Outlook slow to open | Large OST file, corrupted OST, too many add-ins |
| Folder takes long to load | Large folder (10,000+ items), no archiving, slow network |
| Search returns stale or missing results | Indexing not caught up, OST out of sync |
| Sent Items missing from shared mailbox | `MessageCopyForSentAsEnabled` not set — see [shared-mailbox-architecture.md](shared-mailbox-architecture.md) |
| Rules not firing consistently | Rules stored server-side vs client-side conflict |
| Outlook disconnects or shows "Trying to connect" | Network/proxy issue, OAuth token expiry, large OST sync |
| High memory usage per Outlook instance | Large cached mailbox, shared mailboxes with caching enabled |
| Outlook crashes on RDS | Too many concurrent sessions, OST on slow storage |

---

## Diagnostic Step 1 — Check Mailbox Size

```powershell
# Connect to Exchange Online first, then:
Get-MailboxStatistics -Identity "user@company.com" |
    Select DisplayName, TotalItemSize, ItemCount, LastLogonTime
```

If the mailbox is over 20 GB and running in Cached Exchange Mode, that alone is the primary performance issue. See [mailbox-archiving.md](mailbox-archiving.md).

---

## Diagnostic Step 2 — Check OST File Size

On the local machine or RDS host:

```powershell
$ostPath = "$env:LOCALAPPDATA\Microsoft\Outlook"
Get-ChildItem -Path $ostPath -Filter "*.ost" |
    Select Name, @{N="SizeGB";E={[math]::Round($_.Length/1GB,2)}}
```

OST files over 10 GB begin to impact Outlook performance noticeably. Over 25 GB, performance degradation is significant, especially on shared RDS storage.

---

## Diagnostic Step 3 — Check Folder Item Counts

Large folders with tens of thousands of items cause slow rendering and search issues.

```powershell
Get-MailboxFolderStatistics -Identity "user@company.com" |
    Sort ItemsInFolderAndSubfolders -Descending |
    Select FolderPath, ItemsInFolder, ItemsInFolderAndSubfolders, FolderAndSubfolderSize |
    Select-Object -First 15 |
    Format-Table -AutoSize
```

Folders with >10,000 items should be archived or split into subfolders.

---

## Diagnostic Step 4 — Check Outlook Add-ins

Add-ins are a frequent cause of Outlook slowness. Check load times:

1. Open Outlook → File → Options → Add-ins
2. At the bottom, select **COM Add-ins** → Go
3. Disable non-essential add-ins and restart Outlook
4. If performance improves, re-enable add-ins one at a time to identify the culprit

Alternatively, start Outlook in safe mode to disable all add-ins:

```
Win + R → outlook.exe /safe
```

---

## Diagnostic Step 5 — Check Cached Exchange Mode Settings

1. File → Account Settings → Account Settings
2. Select Exchange account → Change
3. Verify **Use Cached Exchange Mode** is checked
4. Verify the slider is set to an appropriate window (3 months recommended for large mailboxes)
5. Verify **Download shared folders** is unchecked

---

## Fix — Rebuild the OST (Outlook Cache)

If Outlook is slow, showing sync errors, or search is returning wrong results, rebuilding the OST often resolves the issue.

**Step 1:** Close Outlook completely (check Task Manager — `OUTLOOK.EXE` must not be running)

**Step 2:** Locate the OST file:

```powershell
$ostPath = "$env:LOCALAPPDATA\Microsoft\Outlook"
Get-ChildItem -Path $ostPath -Filter "*.ost" | Select FullName, Length
```

**Step 3:** Rename (don't delete — keep as backup):

```powershell
$ostPath = "$env:LOCALAPPDATA\Microsoft\Outlook"
Get-ChildItem -Path $ostPath -Filter "*.ost" | ForEach-Object {
    Rename-Item $_.FullName "$($_.FullName).bak"
}
```

**Step 4:** Reopen Outlook — it will create a new OST and re-sync from Exchange Online.

> ⚠️ Initial sync for large mailboxes (20+ GB) may take several hours. User should keep Outlook open and connected to allow sync to complete.

---

## Fix — Repair the Outlook Profile

If Outlook is crashing or showing persistent connection errors, the profile itself may be corrupted.

**Option A — Repair existing profile:**

```
Control Panel → Mail → Email Accounts → Repair
```

**Option B — Create a new profile:**

1. Control Panel → Mail → Show Profiles → Add
2. Create new profile with same account
3. Set as default
4. Remove old profile after confirming new one works

---

## Fix — Server-Side vs Client-Side Rules Conflict

Outlook rules can be stored server-side (apply on all devices, work when Outlook is closed) or client-side (apply only when Outlook is open on that specific machine).

**Symptoms of rule conflicts:**
- Rules fire inconsistently
- "One or more rules could not be uploaded to Exchange" error
- Rules apply on webmail but not Outlook desktop

**Fix:**

1. Open Outlook → Home → Rules → Manage Rules & Alerts
2. Export rules as a backup: **Options → Export Rules**
3. Delete all rules
4. Recreate critical rules from scratch — choose server-side actions (Move to folder, Forward) over client-side actions (Play sound, Display alert)
5. Keep rule total size under 256 KB (Exchange Online limit per mailbox)

---

## Fix — Outlook Search Issues

If search results are missing or stale:

**Rebuild search index:**

1. File → Options → Search → Indexing Options
2. Click **Advanced** → **Rebuild**
3. Allow indexing to complete (may take 1–2 hours for large mailboxes)

**For persistent search issues in RDS environments:**

Outlook search in RDS can be unreliable because Windows Search indexing doesn't roam with user profiles by default. Consider directing users to **Outlook on the Web** (OWA) for search-heavy tasks — OWA searches server-side and is not affected by local index state.

---

## Performance Baseline Metrics (Post-Optimization Targets)

| Metric | Target |
|---|---|
| Outlook cold start time | < 30 seconds |
| Folder load time (1,000–5,000 items) | < 5 seconds |
| Primary mailbox OST size | < 10 GB (after archiving) |
| Search results return time | < 5 seconds |
| Shared mailbox open time | < 10 seconds |
