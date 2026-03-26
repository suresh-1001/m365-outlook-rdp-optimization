# Audit-MailboxSpace.ps1
# Reports mailbox size usage for user and shared mailboxes in Exchange Online
# Exports:
#   1. Mailbox summary report
#   2. Folder statistics report
#
# Run in elevated PowerShell after:
# Install-Module ExchangeOnlineManagement -Scope CurrentUser
# Import-Module ExchangeOnlineManagement
# Connect-ExchangeOnline

$OutputPath = "C:\Temp"
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$SummaryReport = Join-Path $OutputPath "MailboxSpaceSummary.csv"
$FolderReport  = Join-Path $OutputPath "MailboxFolderStats.csv"

Write-Host "Getting all user and shared mailboxes..." -ForegroundColor Cyan

$mailboxes = Get-EXOMailbox -ResultSize Unlimited -RecipientTypeDetails UserMailbox,SharedMailbox `
    -Properties DisplayName,PrimarySmtpAddress,RecipientTypeDetails,ArchiveStatus,ProhibitSendReceiveQuota,IssueWarningQuota

$summaryResults = @()
$folderResults  = @()

function Convert-SizeStringToMB {
    param([string]$SizeString)

    if ([string]::IsNullOrWhiteSpace($SizeString)) { return $null }

    # Examples:
    # "49.5 GB (53,147,123,712 bytes)"
    # "125.3 MB (131,345,112 bytes)"
    # "950 KB (972,800 bytes)"

    if ($SizeString -match '\(([\d,]+)\sbytes\)') {
        $bytes = [double](($matches[1] -replace ",",""))
        return [math]::Round($bytes / 1MB, 2)
    }

    return $null
}

foreach ($mbx in $mailboxes) {
    Write-Host "Processing $($mbx.PrimarySmtpAddress) ..." -ForegroundColor Yellow

    try {
        $stats = Get-EXOMailboxStatistics -Identity $mbx.PrimarySmtpAddress
        $folders = Get-EXOMailboxFolderStatistics -Identity $mbx.PrimarySmtpAddress

        $totalSizeMB = Convert-SizeStringToMB -SizeString $stats.TotalItemSize.ToString()
        $deletedSizeMB = $null
        $recoverableSizeMB = $null

        $deletedFolder = $folders | Where-Object { $_.Name -eq "Deleted Items" } | Select-Object -First 1
        if ($deletedFolder) {
            $deletedSizeMB = Convert-SizeStringToMB -SizeString $deletedFolder.FolderAndSubfolderSize.ToString()
        }

        $recoverableFolder = $folders | Where-Object { $_.FolderType -eq "RecoverableItemsRoot" } | Select-Object -First 1
        if ($recoverableFolder) {
            $recoverableSizeMB = Convert-SizeStringToMB -SizeString $recoverableFolder.FolderAndSubfolderSize.ToString()
        }

        $topFolders = $folders |
            Where-Object { $_.FolderPath -notlike "/Sync Issues*" } |
            Sort-Object {
                Convert-SizeStringToMB -SizeString $_.FolderAndSubfolderSize.ToString()
            } -Descending |
            Select-Object -First 10

        foreach ($folder in $topFolders) {
            $folderResults += [pscustomobject]@{
                MailboxType      = $mbx.RecipientTypeDetails
                DisplayName      = $mbx.DisplayName
                PrimarySmtp      = $mbx.PrimarySmtpAddress
                FolderName       = $folder.Name
                FolderPath       = $folder.FolderPath
                ItemsInFolder    = $folder.ItemsInFolder
                ItemsInSubfolders= $folder.ItemsInFolderAndSubfolders
                FolderSizeMB     = Convert-SizeStringToMB -SizeString $folder.FolderAndSubfolderSize.ToString()
            }
        }

        $summaryResults += [pscustomobject]@{
            MailboxType            = $mbx.RecipientTypeDetails
            DisplayName            = $mbx.DisplayName
            PrimarySmtp            = $mbx.PrimarySmtpAddress
            ArchiveStatus          = $mbx.ArchiveStatus
            TotalItemSizeMB        = $totalSizeMB
            ItemCount              = $stats.ItemCount
            DeletedItemsSizeMB     = $deletedSizeMB
            RecoverableItemsSizeMB = $recoverableSizeMB
            IssueWarningQuota      = $mbx.IssueWarningQuota
            ProhibitSendRecvQuota  = $mbx.ProhibitSendReceiveQuota
            LastLogonTime          = $stats.LastLogonTime
        }
    }
    catch {
        Write-Warning "Failed for $($mbx.PrimarySmtpAddress): $($_.Exception.Message)"
        $summaryResults += [pscustomobject]@{
            MailboxType            = $mbx.RecipientTypeDetails
            DisplayName            = $mbx.DisplayName
            PrimarySmtp            = $mbx.PrimarySmtpAddress
            ArchiveStatus          = $mbx.ArchiveStatus
            TotalItemSizeMB        = "ERROR"
            ItemCount              = ""
            DeletedItemsSizeMB     = ""
            RecoverableItemsSizeMB = ""
            IssueWarningQuota      = $mbx.IssueWarningQuota
            ProhibitSendRecvQuota  = $mbx.ProhibitSendReceiveQuota
            LastLogonTime          = ""
        }
    }
}

$summaryResults |
    Sort-Object {
        if ($_."TotalItemSizeMB" -is [double] -or $_."TotalItemSizeMB" -is [int]) { [double]$_."TotalItemSizeMB" } else { -1 }
    } -Descending |
    Export-Csv -Path $SummaryReport -NoTypeInformation -Encoding UTF8

$folderResults |
    Sort-Object PrimarySmtp, FolderSizeMB -Descending |
    Export-Csv -Path $FolderReport -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Summary report: $SummaryReport"
Write-Host "Folder report : $FolderReport"