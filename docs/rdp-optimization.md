# Outlook Performance Optimization in RDS/RDP Environments

Outlook running inside a Remote Desktop Server (RDS) session has fundamentally different performance characteristics than Outlook on a local workstation. This document covers the specific issues identified in this engagement and the optimizations applied.

---

## Why RDS + Outlook Is Challenging

In a standard deployment, each user runs Outlook on their own machine. In an RDS environment, multiple users share the same server — and all of their Outlook instances run simultaneously, each with their own OST cache file, network connections, and memory footprint.

**Compounding factors in this engagement:**
- Multiple users with 30–50 GB mailboxes running Outlook on shared RDS hosts
- Shared mailboxes accessed by multiple concurrent users
- No archiving enabled — full mailbox sizes downloading into OST files on the RDS host
- Default Cached Exchange Mode settings not tuned for RDS

---

## Problem Diagnosis

### Performance Data Collected

A full RDS performance diagnostic was captured at engagement start, including:
- CPU and memory usage per process and per user
- TCP connections (Exchange HTTPS traffic)
- Application event log
- System event log
- Running services inventory

**Key findings:**
- Outlook processes consuming high memory per user session
- Multiple concurrent OST sync operations competing for bandwidth
- Large OST files stored on the RDS host system drive
- Shared mailboxes configured with Cached Exchange Mode (inappropriate for RDS)

---

## Optimization 1 — Disable Cached Exchange Mode for Shared Mailboxes

**Problem:** When a shared mailbox is added to Outlook with Cached Exchange Mode enabled, Outlook downloads a full copy of the shared mailbox to the local OST. In an RDS environment with multiple users doing this simultaneously, the disk I/O and memory usage compounds severely.

**Fix:** Disable caching for shared mailboxes specifically.

### Via Group Policy / Intune (Recommended)

Deploy the following setting via Administrative Templates (Outlook ADMX):

```
User Configuration → Administrative Templates → Microsoft Outlook → Account Settings →
Exchange → Cached Exchange Mode → Download shared folders
Set to: Disabled
```

### Via Registry (Per Machine)

```powershell
# Disable shared mailbox caching
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Office\16.0\Outlook\Cached Mode" `
    -Name "CacheOthersMail" -Value 0 -Type DWord
```

### Manually per Outlook Profile

1. File → Account Settings → Account Settings
2. Select the Exchange account → Change
3. Click **More Settings** → **Advanced** tab
4. Uncheck **Download shared folders**
5. Restart Outlook

---

## Optimization 2 — Tune the OST Cache Window

For user mailboxes in Cached Exchange Mode, limit how much mail is cached locally. Caching 12 months of a 50 GB mailbox creates a massive OST file. Caching only 3 months reduces the OST significantly.

### Via Group Policy / Intune

```
User Configuration → Administrative Templates → Microsoft Outlook → Account Settings →
Exchange → Cached Exchange Mode → Sync slider setting
Set to: 3 months (or 1 month for very large mailboxes)
```

### Via Registry

```powershell
# Set cache window to 3 months (value = 3)
# 1 = 1 month, 3 = 3 months, 6 = 6 months, 12 = 12 months, 24 = 24 months
Set-ItemProperty -Path "HKCU:\Software\Microsoft\Office\16.0\Outlook\Cached Mode" `
    -Name "SyncWindowSetting" -Value 3 -Type DWord

Set-ItemProperty -Path "HKCU:\Software\Microsoft\Office\16.0\Outlook\Cached Mode" `
    -Name "SyncWindowSettingDays" -Value 0 -Type DWord
```

---

## Optimization 3 — Move OST Files Off the System Drive

In RDS environments, OST files default to the user's AppData on the system drive (`C:\Users\%username%\AppData\Local\Microsoft\Outlook`). On busy RDS hosts with many concurrent users, this creates heavy I/O on the OS disk.

**Fix:** Redirect OST files to a dedicated data volume with faster storage.

### Via Group Policy

```
User Configuration → Administrative Templates → Microsoft Outlook → Miscellaneous →
PST Settings → Default location for OST files
Set to: D:\OutlookCache\%username%
```

Or via registry:

```powershell
# Redirect OST location
$newPath = "D:\OutlookCache\$env:USERNAME"
New-Item -Path $newPath -ItemType Directory -Force | Out-Null

Set-ItemProperty -Path "HKCU:\Software\Microsoft\Office\16.0\Outlook" `
    -Name "ForceOSTPath" -Value $newPath -Type ExpandString
```

> ⚠️ Changing the OST path requires rebuilding the OST. Plan for an initial sync period after the change.

---

## Optimization 4 — Rebuild Oversized or Corrupted OST Files

After making changes to shared mailbox caching or the cache window, existing OST files should be rebuilt to take effect properly.

```powershell
# Close Outlook first, then delete the OST to force a rebuild
$ostPath = "$env:LOCALAPPDATA\Microsoft\Outlook"
Get-ChildItem -Path $ostPath -Filter "*.ost" | Remove-Item -Force
```

> Outlook will recreate the OST on next launch and re-sync from Exchange Online. On large mailboxes (30–50 GB), initial sync can take several hours — plan accordingly.

---

## Optimization 5 — Separate Shared Mailbox Accounts

**Problem:** When a shared mailbox is added as an additional account inside a user's Outlook profile, it shares the profile's connection and caching settings. This is the most common source of shared mailbox performance issues.

**Better approach:** Add the shared mailbox as a **separate Outlook profile** or use the **web-based shared mailbox** (Outlook on the web) for read-only access.

For power users who need full shared mailbox access, create a dedicated Outlook profile:

1. Control Panel → Mail → Show Profiles → Add
2. Create a new profile using the shared mailbox address
3. Launch Outlook using this profile when working in the shared mailbox

---

## Optimization 6 — Reduce Primary Mailbox Sizes First

The single highest-impact optimization for RDS Outlook performance is **reducing primary mailbox sizes via archiving** before tuning any Outlook settings.

A 50 GB mailbox in Cached Exchange Mode creates a 50 GB OST. A 5 GB mailbox (after archiving old mail) creates a 5 GB OST. The performance difference is dramatic.

**Recommended order:**
1. Enable Online Archive and run archiving scripts (see [mailbox-archiving.md](mailbox-archiving.md))
2. Wait 24–48 hours for the Managed Folder Assistant to run
3. Then apply Outlook caching optimizations
4. Rebuild OST files after archiving has completed

---

## RDS Outlook Optimization Checklist

- [ ] Shared mailbox Cached Exchange Mode disabled
- [ ] OST sync window set to 3 months (or less) for user mailboxes
- [ ] OST files redirected to dedicated data volume (if applicable)
- [ ] Primary mailbox sizes reduced via archiving before OST rebuild
- [ ] OST files rebuilt after caching settings changed
- [ ] Outlook performance tested post-optimization (startup time, folder load time, search speed)
- [ ] Concurrent user session count reviewed on RDS host — consider load balancing if >10 Outlook users per host
