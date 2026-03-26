# ============================================================
# Enable Online Archive + 6-Month Archive Policy
# For All User and Shared Mailboxes
# ============================================================

$OutputFolder = "C:\Temp"
$CsvReport    = Join-Path $OutputFolder "Archive_Enablement_6Months_Report.csv"
$LogReport    = Join-Path $OutputFolder "Archive_Enablement_6Months_Log.txt"
$Transcript   = Join-Path $OutputFolder "Archive_Enablement_6Months_Transcript.txt"

$TagName      = "Archive after 6 months"
$PolicyName   = "Default MRM Policy"
$AgeDays      = 180

if (!(Test-Path $OutputFolder)) {
    New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
}

Start-Transcript -Path $Transcript -Force

function Write-Log {
    param(
        [string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$timestamp - $Message"
    Write-Host $line
    Add-Content -Path $LogReport -Value $line
}

$results = @()

Write-Log "Starting archive enablement script."
Write-Log "Checking Exchange organization customization status."

try {
    $orgConfig = Get-OrganizationConfig -ErrorAction Stop

    if ($orgConfig.IsDehydrated -eq $true) {
        Write-Log "Organization customization is not enabled. Running Enable-OrganizationCustomization."
        Enable-OrganizationCustomization -ErrorAction Stop
        Write-Log "Enable-OrganizationCustomization completed."
    }
    else {
        Write-Log "Organization customization already enabled."
    }
}
catch {
    Write-Log "ERROR: Failed checking or enabling organization customization. $($_.Exception.Message)"
}

# Create retention tag if needed
try {
    $existingTag = Get-RetentionPolicyTag -ErrorAction Stop | Where-Object { $_.Name -eq $TagName }

    if (-not $existingTag) {
        Write-Log "Creating retention tag: $TagName"
        New-RetentionPolicyTag `
            -Name $TagName `
            -Type All `
            -RetentionEnabled $true `
            -AgeLimitForRetention $AgeDays `
            -RetentionAction MoveToArchive -ErrorAction Stop
        Write-Log "Retention tag created successfully."
    }
    else {
        Write-Log "Retention tag already exists: $TagName"
    }
}
catch {
    Write-Log "ERROR: Failed creating or checking retention tag. $($_.Exception.Message)"
}

# Add retention tag to policy if needed
try {
    $policy = Get-RetentionPolicy -Identity $PolicyName -ErrorAction Stop
    $existingLinks = @($policy.RetentionPolicyTagLinks | ForEach-Object { $_.ToString() })

    if ($existingLinks -notcontains $TagName) {
        Write-Log "Adding retention tag to policy: $PolicyName"
        Set-RetentionPolicy -Identity $PolicyName -RetentionPolicyTagLinks @{Add=$TagName} -ErrorAction Stop
        Write-Log "Retention tag added to policy successfully."
    }
    else {
        Write-Log "Retention tag already linked to policy: $PolicyName"
    }
}
catch {
    Write-Log "ERROR: Failed checking or updating retention policy. $($_.Exception.Message)"
}

# Get all user and shared mailboxes
try {
    $mailboxes = Get-Mailbox -RecipientTypeDetails UserMailbox,SharedMailbox -ResultSize Unlimited -ErrorAction Stop
    Write-Log "Retrieved $($mailboxes.Count) mailboxes."
}
catch {
    Write-Log "ERROR: Failed retrieving mailbox list. $($_.Exception.Message)"
    $mailboxes = @()
}

foreach ($mbx in $mailboxes) {
    $archiveAction = ""
    $policyAction  = ""
    $mfaAction     = ""
    $overallStatus = "Success"
    $errorDetails  = @()

    $primarySmtp = $mbx.PrimarySmtpAddress.ToString()

    Write-Log "Processing mailbox: $primarySmtp [$($mbx.RecipientTypeDetails)]"

    # Enable archive
    try {
        if ($mbx.ArchiveStatus -ne "Active") {
            Enable-Mailbox -Identity $primarySmtp -Archive -ErrorAction Stop
            $archiveAction = "Archive enabled"
            Write-Log "Archive enabled for $primarySmtp"
        }
        else {
            $archiveAction = "Already active"
            Write-Log "Archive already active for $primarySmtp"
        }
    }
    catch {
        $archiveAction = "Failed"
        $overallStatus = "Failed"
        $errorDetails += "Archive enable failed: $($_.Exception.Message)"
        Write-Log "ERROR: Archive enable failed for $primarySmtp. $($_.Exception.Message)"
    }

    # Apply retention policy
    try {
        Set-Mailbox -Identity $primarySmtp -RetentionPolicy $PolicyName -ErrorAction Stop
        $policyAction = "Retention policy applied"
        Write-Log "Retention policy applied to $primarySmtp"
    }
    catch {
        $policyAction = "Failed"
        $overallStatus = "Failed"
        $errorDetails += "Retention policy failed: $($_.Exception.Message)"
        Write-Log "ERROR: Retention policy failed for $primarySmtp. $($_.Exception.Message)"
    }

    # Start Managed Folder Assistant
    try {
        Start-ManagedFolderAssistant -Identity $primarySmtp -ErrorAction Stop
        $mfaAction = "Started"
        Write-Log "Managed Folder Assistant started for $primarySmtp"
    }
    catch {
        $mfaAction = "Failed"
        if ($overallStatus -ne "Failed") {
            $overallStatus = "Partial"
        }
        $errorDetails += "Managed Folder Assistant failed: $($_.Exception.Message)"
        Write-Log "WARNING: Managed Folder Assistant failed for $primarySmtp. $($_.Exception.Message)"
    }

    # Re-check current archive status
    try {
        $currentMailbox = Get-Mailbox -Identity $primarySmtp -ErrorAction Stop
        $currentArchiveStatus = $currentMailbox.ArchiveStatus
        $currentRetentionPolicy = $currentMailbox.RetentionPolicy
    }
    catch {
        $currentArchiveStatus = "Unknown"
        $currentRetentionPolicy = "Unknown"
        $errorDetails += "Post-check failed: $($_.Exception.Message)"
        Write-Log "WARNING: Post-check failed for $primarySmtp. $($_.Exception.Message)"
    }

    $results += [PSCustomObject]@{
        DisplayName            = $mbx.DisplayName
        PrimarySmtpAddress     = $primarySmtp
        MailboxType            = $mbx.RecipientTypeDetails
        InitialArchiveStatus   = $mbx.ArchiveStatus
        CurrentArchiveStatus   = $currentArchiveStatus
        RetentionPolicy        = $currentRetentionPolicy
        ArchiveAction          = $archiveAction
        RetentionPolicyAction  = $policyAction
        ManagedFolderAction    = $mfaAction
        OverallStatus          = $overallStatus
        ErrorDetails           = ($errorDetails -join " | ")
    }
}

try {
    $results | Sort-Object MailboxType, DisplayName | Export-Csv -Path $CsvReport -NoTypeInformation -Encoding UTF8
    Write-Log "CSV report saved to: $CsvReport"
}
catch {
    Write-Log "ERROR: Failed exporting CSV report. $($_.Exception.Message)"
}

Write-Log "Script completed."
Write-Host ""
Write-Host "CSV report: $CsvReport"
Write-Host "Log file: $LogReport"
Write-Host "Transcript: $Transcript"

Stop-Transcript