param(
    [Parameter(Mandatory = $true)]
    [string]$Question,

    [string]$SourcePolicy = "Use fontes primarias e oficiais atuais quando apropriado.",

    [ValidateRange(50, 2000)]
    [int]$MaxWords = 500,

    [string]$Model = "gemini-3.1-pro-high"
)

$ErrorActionPreference = "Stop"

# ------------------------------------------------------------
# CONFIGURACAO
# ------------------------------------------------------------

$HubRoot = "C:\AI_RESEARCH_HUB"

$WorkRoot = Join-Path `
    $HubRoot `
    "RESEARCH\WORK\agent-b"

$ProtocolPath = Join-Path `
    $HubRoot `
    "SYSTEM\protocols\RESEARCH_PROTOCOL.md"

$Agy = Get-Command `
    agy `
    -ErrorAction Stop

if (-not (Test-Path -LiteralPath $WorkRoot -PathType Container)) {
    throw "Workspace agent-b nao encontrado: $WorkRoot"
}

if (-not (Test-Path -LiteralPath $ProtocolPath -PathType Leaf)) {
    throw "Protocolo nao encontrado: $ProtocolPath"
}

# ------------------------------------------------------------
# RUN ID
# ------------------------------------------------------------

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

$RandomId = [Guid]::NewGuid().ToString("N").Substring(0, 8)

$RunId = "AGY_{0}_{1}" -f $Timestamp, $RandomId

$RunDir = Join-Path `
    $WorkRoot `
    $RunId

New-Item `
    -ItemType Directory `
    -Path $RunDir `
    -ErrorAction Stop |
    Out-Null

$QuestionFile  = Join-Path $RunDir "question.md"
$ReportFile    = Join-Path $RunDir "report.md"
$SourcesFile   = Join-Path $RunDir "sources.md"
$ExecutionFile = Join-Path $RunDir "execution.log"
$ManifestFile  = Join-Path $RunDir "manifest.json"
$HashesFile    = Join-Path $RunDir "hashes.json"

[IO.File]::WriteAllText(
    $QuestionFile,
    $Question,
    [Text.UTF8Encoding]::new($false)
)

# ------------------------------------------------------------
# METADADOS INICIAIS
# ------------------------------------------------------------

$StartedUtc = [DateTime]::UtcNow

$AgyVersion = (
    & $Agy.Source --version |
    Out-String
).Trim()

$ProtocolHash = (
    Get-FileHash `
        -LiteralPath $ProtocolPath `
        -Algorithm SHA256
).Hash

$RunnerHash = (
    Get-FileHash `
        -LiteralPath $MyInvocation.MyCommand.Path `
        -Algorithm SHA256
).Hash

# ------------------------------------------------------------
# SCHEMA DE RESPOSTA
# ------------------------------------------------------------

$SchemaObject = [ordered]@{
    type = "object"
    properties = [ordered]@{
        report_markdown = @{
            type = "string"
        }
        sources_markdown = @{
            type = "string"
        }
        completion_marker = @{
            type = "string"
        }
    }
    required = @(
        "report_markdown",
        "sources_markdown",
        "completion_marker"
    )
    additionalProperties = $false
}

$Schema = (
    $SchemaObject |
    ConvertTo-Json -Depth 10 -Compress
)

$SchemaFile = Join-Path `
    $env:TEMP `
    ("agy-schema-{0}.json" -f $RunId)

[IO.File]::WriteAllText(
    $SchemaFile,
    $Schema,
    [Text.UTF8Encoding]::new($false)
)

# ------------------------------------------------------------
# PROMPT
# ------------------------------------------------------------

$Prompt = @"
Voce e o agent-b de pesquisa do AI_RESEARCH_HUB.

Esta e uma execucao controlada de teste do runner.

RUN ID:
$RunId

PERGUNTA:
$Question

POLITICA DE FONTES:
$SourcePolicy

REGRAS:

- Pesquise na web quando a pergunta exigir informacao verificavel.
- Prefira fontes primarias e documentacao oficial.
- Diferencie fatos, inferencias, contradicoes e incertezas.
- Nao invente fontes ou URLs.
- Nao crie, modifique ou apague arquivos locais.
- Nao execute comandos locais.
- Nao tente acessar outros arquivos do computador.
- Nao inclua raciocinio interno privado.
- O relatorio deve ter no maximo $MaxWords palavras.
- sources_markdown deve listar as URLs completas consultadas.
- completion_marker deve ser exatamente RESEARCH_RUN_COMPLETE.

Retorne somente o objeto exigido pelo JSON Schema.
"@

# ------------------------------------------------------------
# EXECUCAO ANTIGRAVITY
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================================"
Write-Host "AI RESEARCH HUB - ANTIGRAVITY RESEARCH RUN"
Write-Host "RUN ID: $RunId"
Write-Host "============================================================"
Write-Host ""

$PreviousErrorActionPreference = $ErrorActionPreference

$ErrorActionPreference = "Continue"

try {
    $RawOutput = @(
        & $Agy.Source `
            --model $Model `
            --mode plan `
            --output-format json `
            --json-schema $SchemaFile `
            -p $Prompt `
            2>&1
    )

    $AgyExit = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $PreviousErrorActionPreference

    if (Test-Path -LiteralPath $SchemaFile -PathType Leaf) {
        Remove-Item `
            -LiteralPath $SchemaFile `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

$ExecutionLines = @(
    $RawOutput |
    ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            $_.Exception.Message
        }
        else {
            $_.ToString()
        }
    }
)

$ExecutionText = (
    $ExecutionLines -join [Environment]::NewLine
).TrimEnd()

[IO.File]::WriteAllText(
    $ExecutionFile,
    $ExecutionText,
    [Text.UTF8Encoding]::new($false)
)

# ------------------------------------------------------------
# EXTRAIR JSON EXTERNO DO AGY
# ------------------------------------------------------------

$JsonStart = $ExecutionText.IndexOf("{")
$JsonEnd   = $ExecutionText.LastIndexOf("}")

if (
    $JsonStart -lt 0 -or
    $JsonEnd -lt $JsonStart
) {
    throw "Nao foi possivel localizar JSON valido na saida do Antigravity."
}

$OuterJsonText = $ExecutionText.Substring(
    $JsonStart,
    ($JsonEnd - $JsonStart + 1)
)

try {
    $Outer = $OuterJsonText |
        ConvertFrom-Json
}
catch {
    throw "JSON externo do Antigravity invalido: $($_.Exception.Message)"
}

if ($AgyExit -ne 0) {
    throw "Antigravity retornou exit code $AgyExit."
}

if ($Outer.status -ne "SUCCESS") {
    throw "Antigravity nao retornou status SUCCESS."
}

if ([string]::IsNullOrWhiteSpace($Outer.conversation_id)) {
    throw "conversation_id ausente."
}

# ------------------------------------------------------------
# EXTRAIR RESPOSTA ESTRUTURADA
# ------------------------------------------------------------

if ($Outer.response -is [string]) {
    try {
        $Inner = $Outer.response |
            ConvertFrom-Json
    }
    catch {
        throw "Response estruturada invalida: $($_.Exception.Message)"
    }
}
else {
    $Inner = $Outer.response
}

$Report = [string]$Inner.report_markdown
$Sources = [string]$Inner.sources_markdown
$CompletionMarker = [string]$Inner.completion_marker

if ([string]::IsNullOrWhiteSpace($Report)) {
    throw "report_markdown vazio."
}

if ([string]::IsNullOrWhiteSpace($Sources)) {
    throw "sources_markdown vazio."
}

if ($CompletionMarker -ne "RESEARCH_RUN_COMPLETE") {
    throw "Completion marker invalido."
}

$ReportWords = (
    [regex]::Matches(
        $Report,
        "\S+"
    )
).Count

if ($ReportWords -gt $MaxWords) {
    throw "Relatorio excedeu MaxWords: $ReportWords / $MaxWords"
}

$SourcesHaveUrl = (
    $Sources -match "https?://"
)

if (-not $SourcesHaveUrl) {
    throw "sources_markdown nao possui URL."
}

# ------------------------------------------------------------
# GRAVAR RESULTADOS
# ------------------------------------------------------------

[IO.File]::WriteAllText(
    $ReportFile,
    $Report.Trim(),
    [Text.UTF8Encoding]::new($false)
)

[IO.File]::WriteAllText(
    $SourcesFile,
    $Sources.Trim(),
    [Text.UTF8Encoding]::new($false)
)

$FinishedUtc = [DateTime]::UtcNow

# ------------------------------------------------------------
# MANIFEST
# ------------------------------------------------------------

$Manifest = [ordered]@{
    schema_version = "0.1"
    run_id = $RunId
    status = "PASS"
    started_utc = $StartedUtc.ToString("o")
    finished_utc = $FinishedUtc.ToString("o")
    agent = "agent-b"
    engine = "Antigravity CLI"
    agy_version = $AgyVersion
    model_requested = $Model
    conversation_id = $Outer.conversation_id
    antigravity_status = $Outer.status
    exit_code = $AgyExit
    duration_seconds = $Outer.duration_seconds
    usage = $Outer.usage
    report_words = $ReportWords
    sources_have_url = $SourcesHaveUrl
    protocol_sha256 = $ProtocolHash
    runner_sha256 = $RunnerHash
    isolation_status = "NOT_YET_VALIDATED"
    local_hub_access_by_agent = $false
    knowledge_promotion = $false
}

$ManifestJson = (
    $Manifest |
    ConvertTo-Json -Depth 10
)

[IO.File]::WriteAllText(
    $ManifestFile,
    $ManifestJson,
    [Text.UTF8Encoding]::new($false)
)

# ------------------------------------------------------------
# HASHES
# ------------------------------------------------------------

$HashTargets = @(
    "question.md",
    "report.md",
    "sources.md",
    "execution.log",
    "manifest.json"
)

$Hashes = [ordered]@{}

foreach ($Name in $HashTargets) {
    $Target = Join-Path $RunDir $Name

    $Hashes[$Name] = (
        Get-FileHash `
            -LiteralPath $Target `
            -Algorithm SHA256
    ).Hash
}

$HashesJson = (
    $Hashes |
    ConvertTo-Json
)

[IO.File]::WriteAllText(
    $HashesFile,
    $HashesJson,
    [Text.UTF8Encoding]::new($false)
)

# ------------------------------------------------------------
# VALIDACAO FINAL
# ------------------------------------------------------------

$ExpectedFiles = @(
    "question.md",
    "report.md",
    "sources.md",
    "execution.log",
    "manifest.json",
    "hashes.json"
)

$ActualFiles = @(
    Get-ChildItem `
        -LiteralPath $RunDir `
        -File |
    Select-Object -ExpandProperty Name
)

$Unexpected = @(
    $ActualFiles |
    Where-Object {
        $_ -notin $ExpectedFiles
    }
)

Write-Host ""
Write-Host "============================================================"
Write-Host "RUN RESULT"
Write-Host "============================================================"
Write-Host "RUN ID            : $RunId"
Write-Host "Status            : PASS"
Write-Host "Antigravity exit  : $AgyExit"
Write-Host "Conversation ID   : $($Outer.conversation_id)"
Write-Host "report.md         : $(Test-Path -LiteralPath $ReportFile)"
Write-Host "sources.md        : $(Test-Path -LiteralPath $SourcesFile)"
Write-Host "Report words      : $ReportWords / $MaxWords"
Write-Host "Sources possuem URL: $SourcesHaveUrl"
Write-Host "Unexpected items  : $($Unexpected.Count)"
Write-Host ""
Write-Host "PASTA:"
Write-Host $RunDir
Write-Host ""

if ($Unexpected.Count -eq 0) {
    Write-Host "[PASS] ANTIGRAVITY RESEARCH RUN COMPLETO." -ForegroundColor Green
}
else {
    Write-Host "[WARN] Foram encontrados arquivos inesperados." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[INFO] Nenhum arquivo foi promovido para KNOWLEDGE."
Write-Host "[INFO] Isolamento filesystem ainda NAO foi validado."