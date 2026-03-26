# =========================================================
# Enable Online Archive + 1-Year Archive Policy
# For User Mailboxes and Shared Mailboxes
# =========================================================

$OutputFolder = "C:\Temp"
$ReportFile   = Join-Path $OutputFolder "Archive_Enablement_Report.csv"
$TagName      = "Archive after 1 year"
$PolicyName   = "Default MRM Policy"

if (!(Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

# Connect first if not already connected
# Connect-ExchangeOnline

$results = @()

# 1. Create the retention tag if it does not already exist
$existingTag = Get-RetentionPolicyTag -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $TagName }

if (-not $existingTag) {
    Write-Host "Creating retention tag: $TagName"
    New-RetentionPolicyTag `
        -Name $TagName `
        -Type All `
        -RetentionEnabled $true `
        -AgeLimitForRetention 365 `
        -RetentionAction MoveToArchive
}
else {
    Write-Host "Retention tag already exists: $TagName"
}

# 2. Add the tag to the Default MRM Policy if not already linked
$policy = Get-RetentionPolicy -Identity $PolicyName
if ($policy.RetentionPolicyTagLinks -notcontains $TagName) {
    $updatedTags = @($policy.RetentionPolicyTagLinks) + $TagName
    Write-Host "Adding tag to retention policy: $PolicyName"
    Set-RetentionPolicy -Identity $PolicyName -RetentionPolicyTagLinks $updatedTags
}
else {
    Write-Host "Retention tag already linked to policy: $PolicyName"
}

# 3. Process user + shared mailboxes
$mailboxes = Get-Mailbox -RecipientTypeDetails UserMailbox,SharedMailbox -ResultSize Unlimited

foreach ($mbx in $mailboxes) {
    $status = "OK"
    $notes  = ""

    try {
        # Enable archive if not already active
        if ($mbx.ArchiveStatus -ne "Active") {
            Write-Host "Enabling archive for $($mbx.PrimarySmtpAddress)..."
            Enable-Mailbox -Identity $mbx.PrimarySmtpAddress.ToString() -Archive -ErrorAction Stop
            $notes += "Archive enabled. "
        }
        else {
            $notes += "Archive already active. "
        }

        # Apply retention policy
        Write-Host "Applying retention policy to $($mbx.PrimarySmtpAddress)..."
        Set-Mailbox -Identity $mbx.PrimarySmtpAddress.ToString() -RetentionPolicy $PolicyName -ErrorAction Stop
        $notes += "Retention policy applied. "

        # Start Managed Folder Assistant
        Write-Host "Starting Managed Folder Assistant for $($mbx.PrimarySmtpAddress)..."
        Start-ManagedFolderAssistant -Identity $mbx.PrimarySmtpAddress.ToString() -ErrorAction Stop
        $notes += "Managed Folder Assistant started."
    }
    catch {
        $status = "Failed"
        $notes += $_.Exception.Message
    }

    $results += [PSCustomObject]@{
        DisplayName        = $mbx.DisplayName
        PrimarySmtpAddress = $mbx.PrimarySmtpAddress
        MailboxType        = $mbx.RecipientTypeDetails
        ArchiveStatus      = $mbx.ArchiveStatus
        RetentionPolicy    = $PolicyName
        Status             = $status
        Notes              = $notes
    }
}

# 4. Export report
$results | Export-Csv -Path $ReportFile -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "Done."
Write-Host "Report saved to: $ReportFile"