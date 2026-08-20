param(
    [Parameter(Mandatory = $true)]
    [string]$Title,

    [Parameter(Mandatory = $true)]
    [string]$Component,

    [Parameter(Mandatory = $true)]
    [string]$Category,

    [Parameter(Mandatory = $true)]
    [ValidateSet(
        "CONFIRMED",
        "TEST",
        "OBSERVED",
        "LIMITATION",
        "ERROR",
        "INFERENCE",
        "PENDING"
    )]
    [string]$Status,

    [Parameter(Mandatory = $true)]
    [string]$Summary,

    [string]$Evidence = "",

    [string]$Impact = "",

    [string]$Remediation = ""
)

$ErrorActionPreference = "Stop"

$AuditRoot = "C:\AI_RESEARCH_HUB\SECURITY_AUDIT"
$EventsRoot = Join-Path $AuditRoot "EVENTS"

if (-not (Test-Path -LiteralPath $EventsRoot -PathType Container)) {
    throw "SECURITY_AUDIT\EVENTS nao encontrado."
}

$Utf8 = [Text.UTF8Encoding]::new($false)

function Sanitize-Text {
    param(
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return ""
    }

    $Result = $Text

    # --------------------------------------------------------
    # PERFIL WINDOWS ATUAL
    # --------------------------------------------------------

    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {

        $EscapedProfile = [regex]::Escape(
            $env:USERPROFILE.TrimEnd("\")
        )

        $Result = [regex]::Replace(
            $Result,
            $EscapedProfile,
            "%USERPROFILE%",
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    }

    $CurrentUserFolder = [IO.Path]::GetFileName(
        $env:USERPROFILE.TrimEnd("\")
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentUserFolder)) {

        $Result = [regex]::Replace(
            $Result,
            [regex]::Escape($CurrentUserFolder),
            "<REDACTED_USERNAME>",
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    }

    # --------------------------------------------------------
    # QUALQUER PATH C:\Users\<REDACTED_USER>
    # --------------------------------------------------------

    $Result = [regex]::Replace(
        $Result,
        'C:\\Users\\[^\\\s]+',
        'C:\Users\<REDACTED_USER>
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    # --------------------------------------------------------
    # EMAIL
    # --------------------------------------------------------

    $Result = [regex]::Replace(
        $Result,
        '[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
        '<REDACTED_EMAIL>',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    # --------------------------------------------------------
    # BEARER TOKEN
    # --------------------------------------------------------

    $Result = [regex]::Replace(
        $Result,
        'Bearer\s+[A-Za-z0-9._\-]+',
        'Bearer <REDACTED_SECRET>',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    # --------------------------------------------------------
    # JWT
    # --------------------------------------------------------

    $Result = [regex]::Replace(
        $Result,
        'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+',
        '<REDACTED_JWT>'
    )

    # --------------------------------------------------------
    # OPENAI-LIKE KEY
    # --------------------------------------------------------

    $Result = [regex]::Replace(
        $Result,
        'sk-[A-Za-z0-9_-]{16,}',
        '<REDACTED_SECRET>',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    # --------------------------------------------------------
    # GOOGLE-LIKE KEY
    # --------------------------------------------------------

    $Result = [regex]::Replace(
        $Result,
        'AIza[0-9A-Za-z_-]{20,}',
        '<REDACTED_SECRET>'
    )

    # --------------------------------------------------------
    # TEMP
    # --------------------------------------------------------

    if (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {

        $EscapedTemp = [regex]::Escape(
            $env:TEMP.TrimEnd("\")
        )

        $Result = [regex]::Replace(
            $Result,
            $EscapedTemp,
            "%TEMP%",
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
    }

    return $Result
}

function Test-SanitizedText {
    param(
        [string]$Text
    )

    $Findings = @()

    $Patterns = [ordered]@{
        "Real Windows user path" = 'C:\\Users\\(?!<)[^\\\s]+'
        "Email address"          = '[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}'
        "Bearer token"           = 'Bearer\s+(?!<REDACTED_SECRET>)[A-Za-z0-9._\-]+'
        "JWT-like token"         = 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+'
        "OpenAI-like key"        = 'sk-[A-Za-z0-9_-]{16,}'
        "Google-like key"        = 'AIza[0-9A-Za-z_-]{20,}'
    }

    foreach ($Pattern in $Patterns.GetEnumerator()) {

        if (
            [regex]::IsMatch(
                $Text,
                $Pattern.Value,
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            )
        ) {
            $Findings += $Pattern.Key
        }
    }

    return @($Findings)
}

# ------------------------------------------------------------
# SANITIZAR TODOS OS CAMPOS
# ------------------------------------------------------------

$SafeTitle       = Sanitize-Text $Title
$SafeComponent   = Sanitize-Text $Component
$SafeCategory    = Sanitize-Text $Category
$SafeSummary     = Sanitize-Text $Summary
$SafeEvidence    = Sanitize-Text $Evidence
$SafeImpact      = Sanitize-Text $Impact
$SafeRemediation = Sanitize-Text $Remediation

$Now = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ")
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"

# ------------------------------------------------------------
# NOME SEGURO DO ARQUIVO
# ------------------------------------------------------------

$Slug = $SafeTitle.ToUpperInvariant()

$Slug = [regex]::Replace(
    $Slug,
    '[^A-Z0-9]+',
    '_'
).Trim("_")

if ([string]::IsNullOrWhiteSpace($Slug)) {
    $Slug = "SECURITY_EVENT"
}

if ($Slug.Length -gt 80) {
    $Slug = $Slug.Substring(0, 80).TrimEnd("_")
}

$EventFile = Join-Path `
    $EventsRoot `
    ("{0}_{1}.txt" -f $Stamp, $Slug)

if (Test-Path -LiteralPath $EventFile) {
    $Suffix = [Guid]::NewGuid().ToString("N").Substring(0, 6)

    $EventFile = Join-Path `
        $EventsRoot `
        ("{0}_{1}_{2}.txt" -f $Stamp, $Slug, $Suffix)
}

# ------------------------------------------------------------
# CONSTRUIR EVENTO
# ------------------------------------------------------------

$Body = @"
SECURITY AUDIT EVENT
====================

Timestamp UTC:
$Now

Title:
$SafeTitle

Component:
$SafeComponent

Category:
$SafeCategory

Status:
$Status


SUMMARY
-------

$SafeSummary


EVIDENCE
--------

$SafeEvidence


SECURITY IMPACT
---------------

$SafeImpact


REMEDIATION
-----------

$SafeRemediation


AUDIT RULE
----------

This file contains sanitized technical evidence.

It must not contain personal names, email addresses, passwords,
OAuth tokens, API keys, cookies or authentication-file contents.

Only observed facts should be marked CONFIRMED or OBSERVED.

Unverified conclusions must remain TEST, INFERENCE or PENDING.
"@

# ------------------------------------------------------------
# VERIFICAR ANTES DE GRAVAR
# ------------------------------------------------------------

$ResidualFindings = @(
    Test-SanitizedText $Body
)

if ($ResidualFindings.Count -gt 0) {

    Write-Host "[ABORTADO] Dados potencialmente sensiveis permaneceram apos sanitizacao." -ForegroundColor Red

    foreach ($Finding in $ResidualFindings) {
        Write-Host " - $Finding"
    }

    return
}

# ------------------------------------------------------------
# GRAVAR SOMENTE CONTEUDO JA SANITIZADO
# ------------------------------------------------------------

[IO.File]::WriteAllText(
    $EventFile,
    $Body,
    $Utf8
)

# ------------------------------------------------------------
# VERIFICAR ARQUIVO FINAL
# ------------------------------------------------------------

$WrittenText = Get-Content `
    -LiteralPath $EventFile `
    -Raw

$PostWriteFindings = @(
    Test-SanitizedText $WrittenText
)

if ($PostWriteFindings.Count -gt 0) {

    Remove-Item `
        -LiteralPath $EventFile `
        -Force

    Write-Host "[ROLLBACK] Evento removido por falha de sanitizacao." -ForegroundColor Red
    return
}

$Hash = (
    Get-FileHash `
        -LiteralPath $EventFile `
        -Algorithm SHA256
).Hash

Write-Host ""
Write-Host "[PASS] Evento de seguranca registrado." -ForegroundColor Green
Write-Host "File   : $EventFile"
Write-Host "SHA256 : $Hash"
Write-Host "Status : $Status"