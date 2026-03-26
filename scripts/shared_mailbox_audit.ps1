# shared_mailbox_audit.ps1
# Audits all shared mailboxes in Exchange Online and exports a full permission report.
# Covers: Full Access, Send As, and Send on Behalf permissions.
#
# Author: Suresh Chand — https://github.com/suresh-1001
# Usage:
#   .\shared_mailbox_audit.ps1 [-OutputPath "C:\Temp\SharedMailbox_Audit.csv"]

[CmdletBinding()]
param(
    [string]$OutputPath = "C:\Temp\SharedMailbox_Full_Audit_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
)

$ErrorActionPreference = "Stop"

if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
    Write-Host "Installing ExchangeOnlineManagement module..." -ForegroundColor Yellow
    Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
}

Import-Module ExchangeOnlineManagement

Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan
Connect-ExchangeOnline -ShowBanner:$false

Write-Host "Retrieving shared mailboxes..." -ForegroundColor Cyan

$sharedMailboxes = Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited |
    Sort-Object DisplayName

Write-Host "Found $($sharedMailboxes.Count) shared mailboxes." -ForegroundColor Green

$result = @()

foreach ($mbx in $sharedMailboxes) {
    Write-Host "  Processing: $($mbx.DisplayName) <$($mbx.PrimarySmtpAddress)>" -ForegroundColor Yellow

    # Full Access
    $fullAccessPerms = Get-MailboxPermission -Identity $mbx.Identity |
        Where-Object {
            $_.User -notlike "NT AUTHORITY\SELF" -and
            $_.IsInherited -eq $false
        }

    foreach ($perm in $fullAccessPerms) {
        $result += [PSCustomObject]@{
            SharedMailbox  = $mbx.DisplayName
            EmailAddress   = $mbx.PrimarySmtpAddress
            User           = $perm.User
            PermissionType = "FullAccess"
        }
    }

    # Send As
    $sendAsPerms = Get-RecipientPermission -Identity $mbx.Identity |
        Where-Object { $_.Trustee -notlike "NT AUTHORITY\SELF" }

    foreach ($perm in $sendAsPerms) {
        $result += [PSCustomObject]@{
            SharedMailbox  = $mbx.DisplayName
            EmailAddress   = $mbx.PrimarySmtpAddress
            User           = $perm.Trustee
            PermissionType = "SendAs"
        }
    }

    # Send on Behalf
    $sobUsers = (Get-Mailbox $mbx.Identity).GrantSendOnBehalfTo

    foreach ($user in $sobUsers) {
        $result += [PSCustomObject]@{
            SharedMailbox  = $mbx.DisplayName
            EmailAddress   = $mbx.PrimarySmtpAddress
            User           = $user
            PermissionType = "SendOnBehalf"
        }
    }
}

$outputDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$result | Export-Csv $OutputPath -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Audit complete. Total entries: $($result.Count)" -ForegroundColor Green
Write-Host "Report saved to: $OutputPath" -ForegroundColor Green

$result | Format-Table -AutoSize

Disconnect-ExchangeOnline -Confirm:$false
