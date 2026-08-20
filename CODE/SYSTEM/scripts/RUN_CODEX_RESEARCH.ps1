param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Question,

    [ValidateRange(100, 5000)]
    [int]$MaxWords = 900,

    [string]$SourcePolicy = "Use as melhores fontes disponiveis. Prefira fontes primarias, oficiais, documentacao tecnica, artigos cientificos e fontes diretamente responsaveis pelos fatos. Nao invente URLs ou citacoes."
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$Root = "C:\AI_RESEARCH_HUB"
$Image = "ai-research-codex-agent-a:local"
$AuthVolume = "codex-agent-a-home"
$Agent = "agent-a"

$ProtocolPath = Join-Path $Root "SYSTEM\protocols\RESEARCH_PROTOCOL.md"

if (-not (Test-Path -LiteralPath $ProtocolPath -PathType Leaf)) {
    Write-Host "[FAIL] Protocolo de pesquisa nao encontrado: $ProtocolPath" -ForegroundColor Red
    return
}

$ResearchProtocol = Get-Content `
    -LiteralPath $ProtocolPath `
    -Raw

$ProtocolHash = (
    Get-FileHash `
        -LiteralPath $ProtocolPath `
        -Algorithm SHA256
).Hash

$ProtocolVersionMatch = [regex]::Match(
    $ResearchProtocol,
    '(?m)^Version:\s*(.+)$'
)

if (-not $ProtocolVersionMatch.Success) {
    Write-Host "[FAIL] Version nao encontrada no RESEARCH_PROTOCOL.md." -ForegroundColor Red
    return
}

$ProtocolVersion = $ProtocolVersionMatch.Groups[1].Value.Trim()

$RunId = "Q_" +
    (Get-Date -Format "yyyyMMdd_HHmmss") +
    "_" +
    ([guid]::NewGuid().ToString("N").Substring(0, 8))

$HostRunDir = Join-Path $Root "RESEARCH\WORK\agent-a\$RunId"
$ContainerRunDir = "/hub/RESEARCH/WORK/agent-a/$RunId"
$RunContainer = ("ai-research-codex-run-" + $RunId.ToLower())

$StartedUtc = [DateTime]::UtcNow.ToString("o")

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "AI RESEARCH HUB - CODEX RESEARCH RUN" -ForegroundColor Cyan
Write-Host "RUN ID: $RunId"
Write-Host "============================================================" -ForegroundColor Cyan

# ------------------------------------------------------------
# PREREQUISITOS
# ------------------------------------------------------------

docker image inspect $Image *> $null

if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Imagem Docker nao encontrada: $Image" -ForegroundColor Red
    return
}

docker volume inspect $AuthVolume *> $null

if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Volume de autenticacao nao encontrado: $AuthVolume" -ForegroundColor Red
    return
}

$LoginOutput = docker run --rm `
    -v "${AuthVolume}:/home/codex/.codex" `
    $Image `
    codex login status 2>&1

$LoginExit = $LASTEXITCODE
$LoginText = ($LoginOutput | Out-String).Trim()

if (($LoginExit -ne 0) -or ($LoginText -notmatch "Logged in")) {
    Write-Host "[FAIL] Codex nao esta autenticado." -ForegroundColor Red
    Write-Host $LoginText
    return
}

Write-Host "[OK] Codex autenticado." -ForegroundColor Green

# ------------------------------------------------------------
# CRIAR PASTA VAZIA DO RUN
# ------------------------------------------------------------

New-Item `
    -ItemType Directory `
    -Path $HostRunDir `
    -ErrorAction Stop | Out-Null

$Prompt = @"
Voce e o agente de pesquisa CODEX do AI_RESEARCH_HUB.

RUN ID:
$RunId

PERGUNTA:
$Question

POLITICA DE FONTES:
$SourcePolicy

PROTOCOLO CANONICO DE PESQUISA:

$ResearchProtocol

INSTRUCAO DE PROTOCOLO:

O protocolo acima e obrigatorio para esta execucao.
Aplique-o ao pesquisar, navegar pelo HUB, avaliar fontes,
comparar conhecimento existente e produzir o resultado.

REGRAS OBRIGATORIAS:

- Pesquise ativamente na web quando a pergunta exigir informacao factual.
- Conhecimento local pode ser contexto inicial, mas nunca limite da pesquisa.
- Diferencie fatos documentados, inferencias e incertezas.
- Nao invente fontes, URLs, citacoes ou resultados.
- Se uma fonte nao puder ser acessada, declare isso.
- Nao use sudo.
- Nao altere permissoes.
- Nao tente remontar filesystems.
- Nao tente contornar restricoes Docker.
- Nao modifique nada fora da pasta de trabalho atual.
- Nao crie subpastas.
- Crie exatamente dois arquivos:
  1. report.md
  2. sources.md

REPORT.MD:
- pergunta;
- resposta estruturada;
- fatos relevantes;
- inferencias claramente identificadas;
- conclusao;
- limitacoes;
- maximo de $MaxWords palavras.

SOURCES.MD:
Para cada fonte inclua:
- titulo;
- URL completa;
- tipo de fonte;
- quais afirmacoes ela sustenta.

Nao inclua raciocinio interno privado.
Registre apenas metodo observavel, evidencias, fontes e conclusoes.

Ao terminar responda exatamente:
RESEARCH_RUN_COMPLETE
"@

# ------------------------------------------------------------
# METADADOS ANTES DA EXECUCAO
# ------------------------------------------------------------

$CodexVersionOutput = docker run --rm $Image codex --version 2>&1
$CodexVersion = ($CodexVersionOutput | Out-String).Trim()

$DockerVersion = (docker --version 2>&1 | Out-String).Trim()
$ComposeVersion = (docker compose version 2>&1 | Out-String).Trim()

# ------------------------------------------------------------
# EXECUTAR EM CONTAINER EFEMERO
# ------------------------------------------------------------

$DockerArgs = @(
    "run",
    "--rm",
    "--name", $RunContainer,

    "--read-only",

    "--cap-drop", "ALL",

    "--security-opt",
    "no-new-privileges:true",

    "--tmpfs",
    "/tmp",

    "-e",
    "HOME=/home/codex",

    "-e",
    "CODEX_HOME=/home/codex/.codex",

    "-e",
    "XDG_CACHE_HOME=/tmp/.cache",

    "-v",
    "${Root}:/hub:ro",

    "-v",
    "${HostRunDir}:${ContainerRunDir}:rw",

    "-v",
    "${AuthVolume}:/home/codex/.codex:rw",

    "-w",
    $ContainerRunDir,

    $Image,

    "codex",
    "exec",

    "--dangerously-bypass-approvals-and-sandbox",
    "--skip-git-repo-check",
    "--ephemeral",

    $Prompt
)

Write-Host ""
Write-Host "=== CODEX EXEC ===" -ForegroundColor Cyan

# --- PRE-FLIGHT: REFRESH DISCOVERY INDEXES ---

$PreflightHubRoot = "C:\AI_RESEARCH_HUB"

$PreflightAuditorPath = Join-Path `
    $PreflightHubRoot `
    "SYSTEM\scripts\AUDIT_AI_RESEARCH_HUB_DYNAMIC_TREE.ps1"

$PreflightIndexJson = Join-Path `
    $PreflightHubRoot `
    "GENERATED\indexes\hub-index.json"

$PreflightIndexMarkdown = Join-Path `
    $PreflightHubRoot `
    "GENERATED\indexes\hub-tree.md"

Write-Host ""
Write-Host "=== PRE-FLIGHT: REFRESH DISCOVERY INDEXES ==="

if (-not (Test-Path -LiteralPath $PreflightAuditorPath -PathType Leaf)) {
    throw "Pre-flight abortado: auditor nao encontrado em $PreflightAuditorPath"
}

$PreflightStartedUtc = [DateTime]::UtcNow

$PreflightAuditorOutput = & $PreflightAuditorPath 2>&1
$PreflightAuditorSucceeded = $?

if (-not $PreflightAuditorSucceeded) {
    $PreflightAuditorOutput | Out-Host
    throw "Pre-flight abortado: auditor retornou falha."
}

if (-not (Test-Path -LiteralPath $PreflightIndexJson -PathType Leaf)) {
    throw "Pre-flight abortado: hub-index.json nao foi gerado."
}

if (-not (Test-Path -LiteralPath $PreflightIndexMarkdown -PathType Leaf)) {
    throw "Pre-flight abortado: hub-tree.md nao foi gerado."
}

try {
    $null = Get-Content `
        -LiteralPath $PreflightIndexJson `
        -Raw `
        | ConvertFrom-Json
}
catch {
    throw "Pre-flight abortado: hub-index.json invalido."
}

$PreflightJsonInfo = Get-Item `
    -LiteralPath $PreflightIndexJson

$PreflightMarkdownInfo = Get-Item `
    -LiteralPath $PreflightIndexMarkdown

$PreflightToleranceUtc = $PreflightStartedUtc.AddSeconds(-2)

if (
    $PreflightJsonInfo.LastWriteTimeUtc -lt $PreflightToleranceUtc -or
    $PreflightMarkdownInfo.LastWriteTimeUtc -lt $PreflightToleranceUtc
) {
    throw "Pre-flight abortado: os indices nao parecem ter sido atualizados nesta execucao."
}

Write-Host "[OK] Discovery indexes atualizados e validados." -ForegroundColor Green
Write-Host ""
$ExecutionOutput = & docker @DockerArgs 2>&1
$CodexExit = $LASTEXITCODE

$ExecutionText = (
    $ExecutionOutput |
    ForEach-Object {
        if ($_ -is [System.Management.Automation.ErrorRecord]) {
            $_.Exception.Message
        }
        else {
            $_.ToString()
        }
    } |
    Out-String -Width 500
).TrimEnd()

Write-Host $ExecutionText

$FinishedUtc = [DateTime]::UtcNow.ToString("o")

# ------------------------------------------------------------
# VALIDAR SOMENTE O QUE O AGENTE CRIOU
# ------------------------------------------------------------

$ReportFile = Join-Path $HostRunDir "report.md"
$SourcesFile = Join-Path $HostRunDir "sources.md"

$ReportExists = Test-Path -LiteralPath $ReportFile -PathType Leaf
$SourcesExists = Test-Path -LiteralPath $SourcesFile -PathType Leaf

$UnexpectedItems = @(
    Get-ChildItem -LiteralPath $HostRunDir -Force |
    Where-Object {
        $_.Name -notin @(
            "report.md",
            "sources.md"
        )
    } |
    Select-Object -ExpandProperty Name
)

$ReportWordCount = 0
$ReportWithinLimit = $false

if ($ReportExists) {
    $ReportText = Get-Content -LiteralPath $ReportFile -Raw
    $ReportWordCount = [regex]::Matches($ReportText, '\S+').Count
    $ReportWithinLimit = (
        ($ReportWordCount -gt 0) -and
        ($ReportWordCount -le $MaxWords)
    )
}

$SourcesHasUrl = $false

if ($SourcesExists) {
    $SourcesText = Get-Content -LiteralPath $SourcesFile -Raw
    $SourcesHasUrl = ($SourcesText -match 'https?://')
}

$CompletionMarker = (
    $ExecutionText -match '(?m)^RESEARCH_RUN_COMPLETE\s*$'
)

# ------------------------------------------------------------
# AGORA O HOST CRIA OS ARQUIVOS DE AUDITORIA
# ------------------------------------------------------------

$QuestionFile = Join-Path $HostRunDir "question.md"
$ExecutionLog = Join-Path $HostRunDir "execution.log"
$ManifestFile = Join-Path $HostRunDir "manifest.json"
$HashesFile = Join-Path $HostRunDir "hashes.json"

Set-Content `
    -LiteralPath $QuestionFile `
    -Value $Question `
    -Encoding UTF8

Set-Content `
    -LiteralPath $ExecutionLog `
    -Value $ExecutionText `
    -Encoding UTF8

# ------------------------------------------------------------
# EXTRAIR METADADOS OBSERVAVEIS DO LOG
# ------------------------------------------------------------

$ModelMatch = [regex]::Match(
    $ExecutionText,
    '(?m)^model:\s*(.+)$'
)

$ProviderMatch = [regex]::Match(
    $ExecutionText,
    '(?m)^provider:\s*(.+)$'
)

$SessionMatch = [regex]::Match(
    $ExecutionText,
    '(?m)^session id:\s*(.+)$'
)

$Model = ""
$Provider = ""
$SessionId = ""

if ($ModelMatch.Success) {
    $Model = $ModelMatch.Groups[1].Value.Trim()
}

if ($ProviderMatch.Success) {
    $Provider = $ProviderMatch.Groups[1].Value.Trim()
}

if ($SessionMatch.Success) {
    $SessionId = $SessionMatch.Groups[1].Value.Trim()
}

# ------------------------------------------------------------
# RESULTADO DO RUN
# ------------------------------------------------------------

$Pass = (
    ($CodexExit -eq 0) -and
    $CompletionMarker -and
    $ReportExists -and
    $SourcesExists -and
    $ReportWithinLimit -and
    $SourcesHasUrl -and
    ($UnexpectedItems.Count -eq 0)
)

$Status = "FAIL"

if ($Pass) {
    $Status = "PASS"
}

$QuestionHash = (
    Get-FileHash `
        -LiteralPath $QuestionFile `
        -Algorithm SHA256
).Hash

$RunnerHash = ""

if ($PSCommandPath -and (Test-Path -LiteralPath $PSCommandPath)) {
    $RunnerHash = (
        Get-FileHash `
            -LiteralPath $PSCommandPath `
            -Algorithm SHA256
    ).Hash
}

$Manifest = [ordered]@{
    schema_version = "1.0"

    run_id = $RunId
    status = $Status

    started_at_utc = $StartedUtc
    finished_at_utc = $FinishedUtc

    agent = $Agent
    engine = "codex"

    research_protocol_path = "SYSTEM/protocols/RESEARCH_PROTOCOL.md"
    research_protocol_version = $ProtocolVersion
    research_protocol_sha256 = $ProtocolHash

    image = $Image
    container_mode = "ephemeral"

    authentication = "ChatGPT"
    auth_volume = $AuthVolume

    codex_version = $CodexVersion
    docker_version = $DockerVersion
    docker_compose_version = $ComposeVersion

    model = $Model
    provider = $Provider
    session_id = $SessionId

    approval_mode = "never"
    codex_sandbox = "danger-full-access"
    security_boundary = "external-docker"

    hub_mount = "read-only"
    run_mount = "read-write"

    codex_exit_code = $CodexExit
    completion_marker = $CompletionMarker

    report_word_count = $ReportWordCount
    max_report_words = $MaxWords
    report_within_limit = $ReportWithinLimit

    sources_has_url = $SourcesHasUrl

    unexpected_items = $UnexpectedItems

    question_sha256 = $QuestionHash
    runner_script_sha256 = $RunnerHash
}

$Manifest |
    ConvertTo-Json -Depth 8 |
    Set-Content `
        -LiteralPath $ManifestFile `
        -Encoding UTF8

# ------------------------------------------------------------
# HASHES FINAIS
# ------------------------------------------------------------

$FilesToHash = @(
    $QuestionFile,
    $ReportFile,
    $SourcesFile,
    $ExecutionLog,
    $ManifestFile
)

$HashRecords = @()

foreach ($File in $FilesToHash) {

    if (Test-Path -LiteralPath $File -PathType Leaf) {

        $Hash = Get-FileHash `
            -LiteralPath $File `
            -Algorithm SHA256

        $HashRecords += [ordered]@{
            file = Split-Path $File -Leaf
            algorithm = "SHA256"
            sha256 = $Hash.Hash
        }
    }
}

$HashRecords |
    ConvertTo-Json -Depth 5 |
    Set-Content `
        -LiteralPath $HashesFile `
        -Encoding UTF8

# ------------------------------------------------------------
# RESUMO
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "RUN RESULT" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Write-Host "RUN ID            : $RunId"
Write-Host "Status            : $Status"
Write-Host "Codex exit        : $CodexExit"
Write-Host "Completion marker : $CompletionMarker"
Write-Host "report.md         : $ReportExists"
Write-Host "sources.md        : $SourcesExists"
Write-Host "Report words      : $ReportWordCount / $MaxWords"
Write-Host "Sources possuem URL: $SourcesHasUrl"
Write-Host "Unexpected items  : $($UnexpectedItems.Count)"
Write-Host ""
Write-Host "PASTA:"
Write-Host $HostRunDir

if ($Pass) {
    Write-Host ""
    Write-Host "[PASS] RESEARCH RUN COMPLETO." -ForegroundColor Green
}

if (-not $Pass) {
    Write-Host ""
    Write-Host "[FAIL] RESEARCH RUN REQUER REVISAO." -ForegroundColor Red
}

Write-Host ""
Write-Host "[INFO] Nenhum arquivo foi promovido para KNOWLEDGE."


