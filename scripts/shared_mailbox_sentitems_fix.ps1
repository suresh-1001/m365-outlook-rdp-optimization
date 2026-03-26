# Fix Shared Mailbox Sent Items Copy Settings
# This script enables copies of sent messages to be stored in the shared mailbox
# for both Send As and Send on Behalf actions.
#
# Run in PowerShell as an admin account with Exchange Admin or Global Admin rights.
# Example:
#   powershell -ExecutionPolicy Bypass -File .\shared_mailbox_sentitems_fix.ps1

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Installing Exchange Online module if needed..." -ForegroundColor Cyan
    if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
        Install-Module ExchangeOnlineManagement -Scope CurrentUser -Force
    }

    Write-Host "Importing Exchange Online module..." -ForegroundColor Cyan
    Import-Module ExchangeOnlineManagement

    Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan
    Connect-ExchangeOnline

    Write-Host "Getting all shared mailboxes..." -ForegroundColor Cyan
    $sharedMailboxes = Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited |
        Sort-Object DisplayName

    if (-not $sharedMailboxes) {
        Write-Host "No shared mailboxes found." -ForegroundColor Yellow
        return
    }

    $results = foreach ($mailbox in $sharedMailboxes) {
        Write-Host "Updating $($mailbox.DisplayName) <$($mailbox.PrimarySmtpAddress)>" -ForegroundColor Green

        Set-Mailbox -Identity $mailbox.PrimarySmtpAddress `
            -MessageCopyForSentAsEnabled $true `
            -MessageCopyForSendOnBehalfEnabled $true

        $verify = Get-Mailbox -Identity $mailbox.PrimarySmtpAddress |
            Select-Object DisplayName, PrimarySmtpAddress, MessageCopyForSentAsEnabled, MessageCopyForSendOnBehalfEnabled

        [PSCustomObject]@{
            DisplayName                        = $verify.DisplayName
            PrimarySmtpAddress                 = $verify.PrimarySmtpAddress
            MessageCopyForSentAsEnabled        = $verify.MessageCopyForSentAsEnabled
            MessageCopyForSendOnBehalfEnabled  = $verify.MessageCopyForSendOnBehalfEnabled
            Status                             = 'Updated'
        }
    }

    Write-Host "`nDone. Summary:" -ForegroundColor Cyan
    $results | Format-Table -AutoSize

    $reportPath = Join-Path $PSScriptRoot 'shared-mailbox-sent-items-report.csv'
    $results | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8

    Write-Host "Report saved to: $reportPath" -ForegroundColor Yellow
}
catch {
    Write-Error $_.Exception.Message
}
finally {
    Write-Host "Disconnecting from Exchange Online..." -ForegroundColor Cyan
    Disconnect-ExchangeOnline -Confirm:$false
}
