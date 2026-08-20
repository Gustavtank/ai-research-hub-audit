param(
    [string]$Root = 'C:\AI_RESEARCH_HUB',
    [string]$OutputDirectory = '',
    [switch]$NoExport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# =====================================================================
# AI RESEARCH HUB - DYNAMIC TREE + AI NAVIGATION AUDITOR
# Version: 1.0.0
#
# Objetivo:
# - Escanear dinamicamente tudo o que existe sob $Root.
# - Mostrar uma arvore legivel para humanos.
# - Gerar um indice Markdown e JSON para orientar agentes de IA.
# - Nao seguir junctions, symlinks ou outros reparse points.
# - Nao alterar conhecimento, pesquisas, fontes ou projetos.
# - Quando exporta, escreve SOMENTE em GENERATED\indexes.
#
# Saidas padrao:
#   C:\AI_RESEARCH_HUB\GENERATED\indexes\hub-tree.md
#   C:\AI_RESEARCH_HUB\GENERATED\indexes\hub-index.json
#
# Use -NoExport para uma auditoria 100% read-only.
# =====================================================================

$ScriptVersion = '1.0.0'
$GeneratedFileNames = @('hub-tree.md', 'hub-index.json')
$GeneratedTempPattern = '.hub-audit-*.tmp'

function Format-FileSize {
    param([Parameter(Mandatory = $true)][long]$Bytes)

    if ($Bytes -ge 1TB) { return ('{0:N2} TB' -f ($Bytes / 1TB)) }
    elseif ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    elseif ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    elseif ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    else { return ('{0} B' -f $Bytes) }
}

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
}

function Get-RelativePathSafe {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$FullPath
    )

    if ($FullPath -eq $BasePath) { return '.' }

    $Prefix = $BasePath.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $FullPath.StartsWith($Prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Path fora da raiz esperada: $FullPath"
    }

    return $FullPath.Substring($Prefix.Length)
}

function Test-IsReparsePoint {
    param([Parameter(Mandatory = $true)][System.IO.FileSystemInfo]$Item)
    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Test-IsGeneratedAuditFile {
    param(
        [Parameter(Mandatory = $true)][string]$FullPath,
        [Parameter(Mandatory = $true)][string]$ResolvedOutputDirectory
    )

    $Parent = Split-Path -Parent $FullPath
    if (-not $Parent.Equals($ResolvedOutputDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    $Name = Split-Path -Leaf $FullPath
    if ($GeneratedFileNames -contains $Name) { return $true }
    if ($Name -like $GeneratedTempPattern) { return $true }
    return $false
}

function New-DirectoryRecord {
    param(
        [Parameter(Mandatory = $true)][string]$FullPath,
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][bool]$IsLink
    )

    $Item = Get-Item -LiteralPath $FullPath -Force
    return [pscustomobject][ordered]@{
        type          = $(if ($IsLink) { 'link' } else { 'directory' })
        relative_path = Get-RelativePathSafe -BasePath $BasePath -FullPath $FullPath
        name          = $Item.Name
        modified_utc  = $Item.LastWriteTimeUtc.ToString('o')
        traversed     = (-not $IsLink)
    }
}

function New-FileRecord {
    param(
        [Parameter(Mandatory = $true)][System.IO.FileInfo]$Item,
        [Parameter(Mandatory = $true)][string]$BasePath
    )

    return [pscustomobject][ordered]@{
        type          = 'file'
        relative_path = Get-RelativePathSafe -BasePath $BasePath -FullPath $Item.FullName
        name          = $Item.Name
        extension     = $Item.Extension.ToLowerInvariant()
        size_bytes    = [long]$Item.Length
        modified_utc  = $Item.LastWriteTimeUtc.ToString('o')
    }
}

function Get-HubInventory {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$ResolvedOutputDirectory
    )

    $Directories = [System.Collections.Generic.List[object]]::new()
    $Files = [System.Collections.Generic.List[object]]::new()
    $Links = [System.Collections.Generic.List[object]]::new()
    $Errors = [System.Collections.Generic.List[object]]::new()

    $Directories.Add((New-DirectoryRecord -FullPath $BasePath -BasePath $BasePath -IsLink $false))

    function Scan-Directory {
        param([Parameter(Mandatory = $true)][string]$CurrentPath)

        try {
            $Children = @(
                Get-ChildItem -LiteralPath $CurrentPath -Force -ErrorAction Stop |
                Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name
            )
        }
        catch {
            $Errors.Add([pscustomobject][ordered]@{
                path    = Get-RelativePathSafe -BasePath $BasePath -FullPath $CurrentPath
                message = $_.Exception.Message
            })
            return
        }

        foreach ($Child in $Children) {
            if ($Child.PSIsContainer) {
                if (Test-IsReparsePoint -Item $Child) {
                    $Links.Add((New-DirectoryRecord -FullPath $Child.FullName -BasePath $BasePath -IsLink $true))
                    continue
                }

                $Directories.Add((New-DirectoryRecord -FullPath $Child.FullName -BasePath $BasePath -IsLink $false))
                Scan-Directory -CurrentPath $Child.FullName
            }
            else {
                if (Test-IsGeneratedAuditFile -FullPath $Child.FullName -ResolvedOutputDirectory $ResolvedOutputDirectory) {
                    continue
                }
                $Files.Add((New-FileRecord -Item $Child -BasePath $BasePath))
            }
        }
    }

    Scan-Directory -CurrentPath $BasePath

    return [pscustomobject][ordered]@{
        directories = @($Directories)
        files       = @($Files)
        links       = @($Links)
        errors      = @($Errors)
    }
}

function Get-TopLevelArea {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    if ($RelativePath -eq '.') { return '.' }
    return ($RelativePath -split '[\\/]', 2)[0]
}

function Get-TopLevelSummary {
    param(
        [Parameter(Mandatory = $true)]$Directories,
        [Parameter(Mandatory = $true)]$Files
    )

    $AreaNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($Directory in $Directories) {
        $Area = Get-TopLevelArea -RelativePath $Directory.relative_path
        if ($Area -ne '.') { [void]$AreaNames.Add($Area) }
    }
    foreach ($File in $Files) {
        $Area = Get-TopLevelArea -RelativePath $File.relative_path
        if ($Area -ne '.') { [void]$AreaNames.Add($Area) }
    }

    $Results = @()
    foreach ($Area in @($AreaNames | Sort-Object)) {
        $PrefixA = $Area + '\'
        $PrefixB = $Area + '/'

        $AreaDirectories = @($Directories | Where-Object {
            $_.relative_path -eq $Area -or
            $_.relative_path.StartsWith($PrefixA, [System.StringComparison]::OrdinalIgnoreCase) -or
            $_.relative_path.StartsWith($PrefixB, [System.StringComparison]::OrdinalIgnoreCase)
        })
        $AreaFiles = @($Files | Where-Object {
            $_.relative_path -eq $Area -or
            $_.relative_path.StartsWith($PrefixA, [System.StringComparison]::OrdinalIgnoreCase) -or
            $_.relative_path.StartsWith($PrefixB, [System.StringComparison]::OrdinalIgnoreCase)
        })

        $Bytes = 0L
        foreach ($File in $AreaFiles) { $Bytes += [long]$File.size_bytes }

        $Results += [pscustomobject][ordered]@{
            area        = $Area
            directories = $AreaDirectories.Count
            files       = $AreaFiles.Count
            size_bytes  = $Bytes
        }
    }

    return @($Results)
}

function Get-ExtensionSummary {
    param([Parameter(Mandatory = $true)]$Files)

    $Groups = @($Files | Group-Object extension | Sort-Object -Property @{ Expression = 'Count'; Descending = $true }, @{ Expression = 'Name'; Descending = $false })
    $Results = @()

    foreach ($Group in $Groups) {
        $Bytes = 0L
        foreach ($File in $Group.Group) { $Bytes += [long]$File.size_bytes }
        $Label = if ([string]::IsNullOrWhiteSpace($Group.Name)) { '[no extension]' } else { $Group.Name }

        $Results += [pscustomobject][ordered]@{
            extension  = $Label
            files      = $Group.Count
            size_bytes = $Bytes
        }
    }

    return @($Results)
}

function Write-ConsoleTree {
    param(
        [Parameter(Mandatory = $true)][string]$CurrentPath,
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$ResolvedOutputDirectory,
        [int]$Depth = 0
    )

    $Indent = '    ' * $Depth
    if ($CurrentPath -eq $BasePath) {
        Write-Host ("[ROOT] {0}" -f $CurrentPath)
    }
    else {
        Write-Host ("{0}[DIR ] {1}" -f $Indent, (Split-Path -Leaf $CurrentPath))
    }

    try {
        $Children = @(
            Get-ChildItem -LiteralPath $CurrentPath -Force -ErrorAction Stop |
            Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name
        )
    }
    catch {
        Write-Host ("{0}    [ERR ] {1}" -f $Indent, $_.Exception.Message)
        return
    }

    $VisibleChildren = @()
    foreach ($Child in $Children) {
        if (-not $Child.PSIsContainer -and (Test-IsGeneratedAuditFile -FullPath $Child.FullName -ResolvedOutputDirectory $ResolvedOutputDirectory)) {
            continue
        }
        $VisibleChildren += $Child
    }

    if ($VisibleChildren.Count -eq 0) {
        Write-Host ("{0}    (empty)" -f $Indent)
        return
    }

    foreach ($Child in $VisibleChildren) {
        if ($Child.PSIsContainer) {
            if (Test-IsReparsePoint -Item $Child) {
                Write-Host ("{0}    [LINK] {1}  (reparse point; not traversed)" -f $Indent, $Child.Name)
                continue
            }

            Write-ConsoleTree -CurrentPath $Child.FullName -BasePath $BasePath -ResolvedOutputDirectory $ResolvedOutputDirectory -Depth ($Depth + 1)
        }
        else {
            Write-Host ("{0}    [FILE] {1}  [{2}]" -f $Indent, $Child.Name, (Format-FileSize -Bytes $Child.Length))
        }
    }
}

function New-MarkdownIndex {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedRoot,
        [Parameter(Mandatory = $true)][string]$GeneratedAtUtc,
        [Parameter(Mandatory = $true)]$Inventory,
        [Parameter(Mandatory = $true)]$TopLevelSummary,
        [Parameter(Mandatory = $true)]$ExtensionSummary,
        [Parameter(Mandatory = $true)][long]$TotalBytes
    )

    $Lines = [System.Collections.Generic.List[string]]::new()
    $Lines.Add('# AI Research Hub - Dynamic Navigation Index')
    $Lines.Add('')
    $Lines.Add('> Arquivo gerado automaticamente. Nao e fonte canonica e pode ser regenerado.')
    $Lines.Add('')
    $Lines.Add("- **Root:** ``$ResolvedRoot``")
    $Lines.Add("- **Generated UTC:** $GeneratedAtUtc")
    $Lines.Add("- **Auditor version:** $ScriptVersion")
    $Lines.Add("- **Directories:** $($Inventory.directories.Count)")
    $Lines.Add("- **Files:** $($Inventory.files.Count)")
    $Lines.Add("- **Links not traversed:** $($Inventory.links.Count)")
    $Lines.Add("- **Scan errors:** $($Inventory.errors.Count)")
    $Lines.Add("- **Total file size:** $(Format-FileSize -Bytes $TotalBytes)")
    $Lines.Add('')
    $Lines.Add('## AI navigation policy')
    $Lines.Add('')
    $Lines.Add('1. Start with `INDEX` to locate related topics and prior knowledge.')
    $Lines.Add('2. Read only relevant material in `KNOWLEDGE`; do not treat it as a limit on new research.')
    $Lines.Add('3. Consult related runs in `RESEARCH` for methods, disagreements, evidence and previous findings.')
    $Lines.Add('4. Use `SOURCES` to verify provenance and bibliographic/source records.')
    $Lines.Add('5. Use `PROJECTS` only when the question depends on a linked project or repository.')
    $Lines.Add('6. Read `SYSTEM` before writing outputs; it contains protocols, schemas and agent rules.')
    $Lines.Add('7. Treat `GENERATED` as disposable machine context, never as canonical truth.')
    $Lines.Add('8. Local knowledge is starting context, NOT a boundary: external research remains open when required.')
    $Lines.Add('')
    $Lines.Add('## Top-level areas')
    $Lines.Add('')
    $Lines.Add('| Area | Directories | Files | Size |')
    $Lines.Add('|---|---:|---:|---:|')
    foreach ($Area in $TopLevelSummary) {
        $Lines.Add("| $($Area.area) | $($Area.directories) | $($Area.files) | $(Format-FileSize -Bytes $Area.size_bytes) |")
    }
    $Lines.Add('')
    $Lines.Add('## File extensions')
    $Lines.Add('')
    $Lines.Add('| Extension | Files | Size |')
    $Lines.Add('|---|---:|---:|')
    foreach ($Extension in $ExtensionSummary) {
        $Lines.Add("| $($Extension.extension) | $($Extension.files) | $(Format-FileSize -Bytes $Extension.size_bytes) |")
    }
    $Lines.Add('')
    $Lines.Add('## Files')
    $Lines.Add('')
    foreach ($File in @($Inventory.files | Sort-Object relative_path)) {
        $Lines.Add("- ``$($File.relative_path)`` - $(Format-FileSize -Bytes $File.size_bytes) - modified UTC $($File.modified_utc)")
    }

    if ($Inventory.links.Count -gt 0) {
        $Lines.Add('')
        $Lines.Add('## Links not traversed')
        $Lines.Add('')
        foreach ($Link in @($Inventory.links | Sort-Object relative_path)) {
            $Lines.Add("- ``$($Link.relative_path)``")
        }
    }

    if ($Inventory.errors.Count -gt 0) {
        $Lines.Add('')
        $Lines.Add('## Scan errors')
        $Lines.Add('')
        foreach ($ErrorRecord in $Inventory.errors) {
            $Lines.Add("- ``$($ErrorRecord.path)`` - $($ErrorRecord.message)")
        }
    }

    return ($Lines -join [Environment]::NewLine) + [Environment]::NewLine
}

function Write-AtomicUtf8File {
    param(
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $Parent = Split-Path -Parent $Destination
    $TempName = '.hub-audit-' + [Guid]::NewGuid().ToString('N') + '.tmp'
    $TempPath = Join-Path $Parent $TempName

    try {
        [System.IO.File]::WriteAllText($TempPath, $Content, ([System.Text.UTF8Encoding]::new($false)))
        Move-Item -LiteralPath $TempPath -Destination $Destination -Force
    }
    finally {
        if (Test-Path -LiteralPath $TempPath -PathType Leaf) {
            Remove-Item -LiteralPath $TempPath -Force
        }
    }
}

Write-Host ''
Write-Host ('=' * 78)
Write-Host 'AI RESEARCH HUB - DYNAMIC TREE + AI NAVIGATION AUDIT'
Write-Host ('=' * 78)
Write-Host ''

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    Write-Host '[FAIL] Root folder does not exist:'
    Write-Host "       $Root"
    Write-Host ''
    Write-Host 'No files or folders were changed.'
    return
}

$ResolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$ResolvedRoot = Get-NormalizedFullPath -Path $ResolvedRoot

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Join-Path $ResolvedRoot 'GENERATED') 'indexes'
}

$NormalizedOutputDirectory = Get-NormalizedFullPath -Path $OutputDirectory
$AllowedOutputDirectory = Get-NormalizedFullPath -Path (Join-Path (Join-Path $ResolvedRoot 'GENERATED') 'indexes')

if (-not $NormalizedOutputDirectory.Equals($AllowedOutputDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "ABORTADO: OutputDirectory deve ser exatamente '$AllowedOutputDirectory'. Recebido: '$NormalizedOutputDirectory'"
}

if (-not (Test-Path -LiteralPath $NormalizedOutputDirectory -PathType Container)) {
    throw "ABORTADO: pasta de saida nao existe. Crie/valide antes: $NormalizedOutputDirectory"
}

Write-Host 'Scanning:'
Write-Host "  $ResolvedRoot"
Write-Host ''

$Inventory = Get-HubInventory -BasePath $ResolvedRoot -ResolvedOutputDirectory $NormalizedOutputDirectory
$TopLevelSummary = Get-TopLevelSummary -Directories $Inventory.directories -Files $Inventory.files
$ExtensionSummary = Get-ExtensionSummary -Files $Inventory.files

$TotalBytes = 0L
foreach ($File in $Inventory.files) { $TotalBytes += [long]$File.size_bytes }

Write-Host 'FULL TREE'
Write-Host ('-' * 78)
Write-ConsoleTree -CurrentPath $ResolvedRoot -BasePath $ResolvedRoot -ResolvedOutputDirectory $NormalizedOutputDirectory -Depth 0

Write-Host ''
Write-Host ('-' * 78)
Write-Host 'SUMMARY'
Write-Host ('-' * 78)
Write-Host ("Folders                 : {0}" -f $Inventory.directories.Count)
Write-Host ("Files                   : {0}" -f $Inventory.files.Count)
Write-Host ("Links not traversed     : {0}" -f $Inventory.links.Count)
Write-Host ("Scan errors             : {0}" -f $Inventory.errors.Count)
Write-Host ("Total file size         : {0}" -f (Format-FileSize -Bytes $TotalBytes))

if ($Inventory.errors.Count -gt 0) {
    Write-Host ''
    Write-Host '[WARN] Scan completed with one or more inaccessible paths.'
}

if ($NoExport) {
    Write-Host ''
    Write-Host '[OK] Read-only scan completed. -NoExport active; no files were written.'
    return
}

$GeneratedAtUtc = [DateTime]::UtcNow.ToString('o')

$Manifest = [pscustomobject][ordered]@{
    schema_version = '1.0'
    generated_at_utc = $GeneratedAtUtc
    generated_by = [pscustomobject][ordered]@{
        script = 'AUDIT_AI_RESEARCH_HUB_DYNAMIC_TREE.ps1'
        version = $ScriptVersion
    }
    root = $ResolvedRoot
    safety = [pscustomobject][ordered]@{
        canonical_content_modified = $false
        output_directory = $NormalizedOutputDirectory
        generated_files_excluded_from_scan = $true
        reparse_points_traversed = $false
    }
    navigation = [pscustomobject][ordered]@{
        read_order = @('INDEX', 'KNOWLEDGE', 'RESEARCH', 'SOURCES', 'PROJECTS', 'SYSTEM', 'GENERATED')
        external_research_policy = 'Local knowledge is starting context, not a boundary. External research remains open when required.'
        generated_content_policy = 'GENERATED is disposable context and is not canonical truth.'
    }
    summary = [pscustomobject][ordered]@{
        directories = $Inventory.directories.Count
        files = $Inventory.files.Count
        links_not_traversed = $Inventory.links.Count
        scan_errors = $Inventory.errors.Count
        total_size_bytes = $TotalBytes
        top_level_areas = $TopLevelSummary
        extensions = $ExtensionSummary
    }
    inventory = [pscustomobject][ordered]@{
        directories = $Inventory.directories
        files = $Inventory.files
        links = $Inventory.links
        errors = $Inventory.errors
    }
}

$JsonContent = $Manifest | ConvertTo-Json -Depth 12
$MarkdownContent = New-MarkdownIndex -ResolvedRoot $ResolvedRoot -GeneratedAtUtc $GeneratedAtUtc -Inventory $Inventory -TopLevelSummary $TopLevelSummary -ExtensionSummary $ExtensionSummary -TotalBytes $TotalBytes

$JsonPath = Join-Path $NormalizedOutputDirectory 'hub-index.json'
$MarkdownPath = Join-Path $NormalizedOutputDirectory 'hub-tree.md'

Write-AtomicUtf8File -Destination $JsonPath -Content ($JsonContent + [Environment]::NewLine)
Write-AtomicUtf8File -Destination $MarkdownPath -Content $MarkdownContent

Write-Host ''
Write-Host '[OK] Scan completed.'
Write-Host '[OK] Canonical folders were not modified.'
Write-Host '[OK] Generated AI navigation files:'
Write-Host "     $JsonPath"
Write-Host "     $MarkdownPath"
