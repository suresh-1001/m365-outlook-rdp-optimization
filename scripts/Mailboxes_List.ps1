$OutputFolder = "C:\Temp"
$CsvFile = Join-Path $OutputFolder "MailboxSizes_BeforeArchive.csv"
$TableFile = Join-Path $OutputFolder "MailboxSizes_BeforeArchive_Table.txt"
$TranscriptFile = Join-Path $OutputFolder "MailboxSizes_BeforeArchive_Transcript.txt"

if (!(Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

Start-Transcript -Path $TranscriptFile -Force

$mailboxes = Get-Mailbox -RecipientTypeDetails UserMailbox,SharedMailbox -ResultSize Unlimited

$results = foreach ($mbx in $mailboxes) {
    try {
        $MailboxId = $mbx.PrimarySmtpAddress.ToString()
        $stats = Get-MailboxStatistics -Identity $MailboxId

        [PSCustomObject]@{
            DisplayName        = $mbx.DisplayName
            PrimarySmtpAddress = $mbx.PrimarySmtpAddress
            MailboxType        = $mbx.RecipientTypeDetails
            ArchiveStatus      = $mbx.ArchiveStatus
            TotalItemSize      = $stats.TotalItemSize
            ItemCount          = $stats.ItemCount
            Status             = "OK"
        }
    }
    catch {
        Write-Warning "Failed mailbox: $($mbx.DisplayName) <$($mbx.PrimarySmtpAddress)> : $($_.Exception.Message)"

        [PSCustomObject]@{
            DisplayName        = $mbx.DisplayName
            PrimarySmtpAddress = $mbx.PrimarySmtpAddress
            MailboxType        = $mbx.RecipientTypeDetails
            ArchiveStatus      = $mbx.ArchiveStatus
            TotalItemSize      = ""
            ItemCount          = ""
            Status             = "Failed"
        }
    }
}

$results | Export-Csv -Path $CsvFile -NoTypeInformation -Encoding UTF8
$results | Sort-Object MailboxType, DisplayName | Format-Table -AutoSize | Out-String | Set-Content -Path $TableFile

Write-Host "CSV saved to: $CsvFile"
Write-Host "Table report saved to: $TableFile"
Write-Host "Transcript saved to: $TranscriptFile"

Stop-Transcript