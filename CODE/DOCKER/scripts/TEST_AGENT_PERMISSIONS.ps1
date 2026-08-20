$ErrorActionPreference = "Continue"

$Root = "C:\AI_RESEARCH_HUB"

$Agents = @(
    @{
        Name = "agent-a"
        Container = "ai-research-agent-a-test"
        Other = "agent-b"
    },
    @{
        Name = "agent-b"
        Container = "ai-research-agent-b-test"
        Other = "agent-c"
    },
    @{
        Name = "agent-c"
        Container = "ai-research-agent-c-test"
        Other = "agent-a"
    }
)

$Failures = 0

foreach ($Agent in $Agents) {

    $Name = $Agent.Name
    $Container = $Agent.Container
    $Other = $Agent.Other

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "TESTE $Name" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    docker exec $Container ls -ld /hub/KNOWLEDGE /hub/RESEARCH /hub/SOURCES | Out-Null
    $ReadExit = $LASTEXITCODE

    docker exec $Container sh -c "echo permission-test > /hub/RESEARCH/WORK/$Name/_docker_permission_test.txt"
    $OwnExit = $LASTEXITCODE

    docker exec $Container sh -c "echo forbidden > /hub/RESEARCH/WORK/$Other/_FORBIDDEN_$Name.txt" 2>$null
    $CrossExit = $LASTEXITCODE

    docker exec $Container sh -c "echo forbidden > /hub/KNOWLEDGE/_FORBIDDEN_$Name.txt" 2>$null
    $KnowledgeExit = $LASTEXITCODE

    $OwnFile = "$Root\RESEARCH\WORK\$Name\_docker_permission_test.txt"
    $CrossFile = "$Root\RESEARCH\WORK\$Other\_FORBIDDEN_$Name.txt"
    $KnowledgeFile = "$Root\KNOWLEDGE\_FORBIDDEN_$Name.txt"

    $OwnExists = Test-Path -LiteralPath $OwnFile
    $CrossExists = Test-Path -LiteralPath $CrossFile
    $KnowledgeExists = Test-Path -LiteralPath $KnowledgeFile

    $Pass =
        ($ReadExit -eq 0) -and
        ($OwnExit -eq 0) -and
        ($CrossExit -ne 0) -and
        ($KnowledgeExit -ne 0) -and
        $OwnExists -and
        (-not $CrossExists) -and
        (-not $KnowledgeExists)

    Write-Host "Leitura           : $ReadExit"
    Write-Host "Escrita propria   : $OwnExit"
    Write-Host "Escrita cruzada   : $CrossExit"
    Write-Host "KNOWLEDGE         : $KnowledgeExit"

    if ($Pass) {
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }

    if (-not $Pass) {
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        $Failures++
    }

    if (Test-Path -LiteralPath $OwnFile) {
        Remove-Item -LiteralPath $OwnFile -Force
    }

    if (Test-Path -LiteralPath $CrossFile) {
        Remove-Item -LiteralPath $CrossFile -Force
    }

    if (Test-Path -LiteralPath $KnowledgeFile) {
        Remove-Item -LiteralPath $KnowledgeFile -Force
    }
}

Write-Host "`n========================================"

if ($Failures -eq 0) {
    Write-Host "[PASS] TODOS OS AGENTES PASSARAM." -ForegroundColor Green
    exit 0
}

Write-Host "[FAIL] $Failures agente(s) falharam." -ForegroundColor Red
exit 1

