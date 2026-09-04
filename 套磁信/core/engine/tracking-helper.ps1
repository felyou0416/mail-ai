<#
.SYNOPSIS
  套磁追踪记录辅助模块 (Tracking Helper)
#>

function Write-TrackingRecord {
    param(
        [string]$Recipient,
        [string]$Name,
        [string]$Org,
        [string]$Subject,
        [string]$Template,
        [string]$Status, # "draft", "sent", "failed"
        [string]$SentVia
    )

    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    $personalDir = Join-Path (Split-Path -Parent (Split-Path -Parent $scriptDir)) "personal"
    $trackingFile = Join-Path $personalDir "tracking.csv"

    if (-not (Test-Path $personalDir)) {
        New-Item -ItemType Directory -Path $personalDir -Force | Out-Null
    }

    $records = @()
    if (Test-Path $trackingFile) {
        try {
            $records = @(Import-Csv $trackingFile)
        } catch {}
    }

    $nowStr = Get-Date -Format "yyyy-MM-dd HH:mm"
    $found = $false

    foreach ($r in $records) {
        $matchRecip = $Recipient -and ($r.recipient -ieq $Recipient)
        $matchNameOrg = $Name -and $Org -and ($r.name -eq $Name) -and ($r.org -eq $Org)
        if ($matchRecip -or $matchNameOrg) {
            $r.date = $nowStr
            $r.subject = $Subject
            if ($Template) { $r.template = $Template }
            $r.status = $Status
            if ($SentVia) { $r.sent_via = $SentVia }
            $found = $true
            break
        }
    }

    if (-not $found) {
        $newObj = [PSCustomObject]@{
            date = $nowStr
            sender = ""
            recipient = $Recipient
            name = $Name
            org = $Org
            subject = $Subject
            template = if ($Template) { $Template } else { "A" }
            status = $Status
            sent_via = $SentVia
            days_no_reply = "0"
        }
        $records += $newObj
    }

    $records | Export-Csv $trackingFile -NoTypeInformation -Encoding UTF8
}
