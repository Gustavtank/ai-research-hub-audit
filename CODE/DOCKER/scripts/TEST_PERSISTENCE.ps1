$ErrorActionPreference = "Continue"

$Compose = "C:\AI_RESEARCH_HUB\DOCKER\compose.yaml"
$Root = "C:\AI_RESEARCH_HUB"

$TestId = [guid]::NewGuid().ToString("N")

$Agents = @(
    @{
        Name = "agent-a"
        Container = "ai-research-agent-a-test"
    },
    @{
        Name = "agent-b"
        Container = "ai-research-agent-b-test"
    },
    @{
        Name = "agent-c"
        Container = "ai-research-agent-c-test"
    }
)

$Failures = 0
$Files = @()

Write-Host "`n=== PERSISTENCE TEST ===" -ForegroundColor Cyan
Write-Host "TEST ID: $TestId"

docker compose -f $Compose up -d | Out-Host
$UpInitial = $LASTEXITCODE

if ($UpInitial -ne 0) {
    Write-Host "[FAIL] Nao foi possivel iniciar os containers." -ForegroundColor Red
    exit 1
}

foreach ($Agent in $Agents) {

    $Name = $Agent.Name
    $Container = $Agent.Container

    $HostFile = "$Root\RESEARCH\WORK\$Name\_persistence_$TestId.txt"
    $ContainerFile = "/hub/RESEARCH/WORK/$Name/_persistence_$TestId.txt"
    $Value = "$Name-persist-$TestId"

    docker exec $Container sh -c "echo $Value > $ContainerFile"
    $CreateExit = $LASTEXITCODE

    $Exists = Test-Path -LiteralPath $HostFile

    Write-Host "$Name create exit : $CreateExit"
    Write-Host "$Name host exists : $Exists"

    if (($CreateExit -ne 0) -or (-not $Exists)) {
        $Failures++
    }

    $Files += @{
        Name = $Name
        Container = $Container
        HostFile = $HostFile
        ContainerFile = $ContainerFile
        Value = $Value
    }
}

Write-Host "`n=== RESTART ===" -ForegroundColor Cyan

docker compose -f $Compose restart | Out-Host
$RestartExit = $LASTEXITCODE

foreach ($Item in $Files) {
    $Exists = Test-Path -LiteralPath $Item.HostFile
    Write-Host "$($Item.Name) apos restart : $Exists"

    if (-not $Exists) {
        $Failures++
    }
}

Write-Host "`n=== DOWN ===" -ForegroundColor Cyan

docker compose -f $Compose down | Out-Host
$DownExit = $LASTEXITCODE

foreach ($Item in $Files) {
    $Exists = Test-Path -LiteralPath $Item.HostFile
    Write-Host "$($Item.Name) apos down : $Exists"

    if (-not $Exists) {
        $Failures++
    }
}

Write-Host "`n=== UP NOVAMENTE ===" -ForegroundColor Cyan

docker compose -f $Compose up -d | Out-Host
$UpExit = $LASTEXITCODE

foreach ($Item in $Files) {
    $Exists = Test-Path -LiteralPath $Item.HostFile
    Write-Host "$($Item.Name) apos up : $Exists"

    if (-not $Exists) {
        $Failures++
    }
}

Write-Host "`n=== VALIDACAO DE CONTEUDO ===" -ForegroundColor Cyan

foreach ($Item in $Files) {

    $Content = docker exec $Item.Container cat $Item.ContainerFile
    $CatExit = $LASTEXITCODE
    $Matches = ($Content.Trim() -eq $Item.Value)

    Write-Host "$($Item.Name) cat exit : $CatExit"
    Write-Host "$($Item.Name) conteudo correto : $Matches"

    if (($CatExit -ne 0) -or (-not $Matches)) {
        $Failures++
    }
}

Write-Host "`n=== LIMPEZA ===" -ForegroundColor Cyan

foreach ($Item in $Files) {

    if (Test-Path -LiteralPath $Item.HostFile) {
        Remove-Item -LiteralPath $Item.HostFile -Force
    }

    $Removed = -not (Test-Path -LiteralPath $Item.HostFile)

    Write-Host "$($Item.Name) removido : $Removed"

    if (-not $Removed) {
        $Failures++
    }
}

Write-Host "`n========================================"

if (
    ($Failures -eq 0) -and
    ($RestartExit -eq 0) -and
    ($DownExit -eq 0) -and
    ($UpExit -eq 0)
) {
    Write-Host "[PASS] PERSISTENCIA COMPLETA." -ForegroundColor Green
    exit 0
}

Write-Host "[FAIL] Falhas detectadas: $Failures" -ForegroundColor Red
exit 1
