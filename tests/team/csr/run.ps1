param(
    [string]$VivadoBin = 'E:\Vivado\Vivado\2023.2\bin',
    [string]$OutputDir = '',
    [string]$CsrSource = '',
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
if (-not $CsrSource) { $CsrSource = Join-Path $repoRoot 'myCPU/csr.v' }
$CsrSource = (Resolve-Path -LiteralPath $CsrSource).Path
$testbench = Join-Path $PSScriptRoot 'tb_csr.sv'
if (-not $OutputDir) {
    $OutputDir = Join-Path $env:TEMP ('la32-csr-test-' + [guid]::NewGuid().ToString('N'))
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$OutputDir = (Resolve-Path -LiteralPath $OutputDir).Path

# Each tool has a wall-clock timeout; the testbench also has a simulation timeout.
function Invoke-VivadoTool([string]$Tool, [string[]]$ToolArgs) {
    $executable = Join-Path $VivadoBin "$Tool.bat"
    if (-not (Test-Path -LiteralPath $executable)) { throw "Missing tool: $executable" }
    $stdout = Join-Path $OutputDir "$Tool.stdout.txt"
    $stderr = Join-Path $OutputDir "$Tool.stderr.txt"
    # Source paths are arguments, never evaluated as PowerShell expressions.
    $quotedArgs = $ToolArgs | ForEach-Object {
        if ($_ -match '["\r\n]') { throw 'Quotes/newlines in tool arguments are unsupported.' }
        '"' + $_ + '"'
    }
    $process = Start-Process -FilePath $executable -ArgumentList $quotedArgs `
        -WorkingDirectory $OutputDir -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $null = $process.Handle
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        & taskkill.exe /PID $process.Id /T /F | Out-Null
        throw "$Tool exceeded $TimeoutSeconds seconds"
    }
    $process.WaitForExit()
    Get-Content -LiteralPath $stdout
    Get-Content -LiteralPath $stderr
    if ($process.ExitCode -ne 0) { throw "$Tool exited with code $($process.ExitCode)" }
}

$result = [ordered]@{
    status = 'FAIL'
    timestamp = (Get-Date).ToString('o')
    source = $CsrSource
    source_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $CsrSource).Hash
    testbench_sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $testbench).Hash
    output_dir = $OutputDir
    summary = $null
    error = $null
}
try {
    Invoke-VivadoTool 'xvlog' @('-sv', $CsrSource, $testbench)
    Invoke-VivadoTool 'xelab' @('work.tb_csr', '-s', 'csr_test', '-debug', 'typical', '--timescale', '1ns/1ps')
    Invoke-VivadoTool 'xsim' @('csr_test', '-runall')
    $simText = Get-Content -Raw -LiteralPath (Join-Path $OutputDir 'xsim.stdout.txt')
    if ($simText -notmatch '(?m)^CSR_TEST_PASS\s*$' -or $simText -match '(?m)^FAIL ') {
        throw 'CSR test did not produce a clean PASS marker. See simulation log.'
    }
    $result.status = 'PASS'
} catch {
    $result.error = $_.Exception.Message
    Write-Host "FAIL: $($result.error)"
} finally {
    $simLog = Join-Path $OutputDir 'xsim.stdout.txt'
    if (Test-Path -LiteralPath $simLog) {
        $summary = Select-String -LiteralPath $simLog -Pattern '^CSR_SUMMARY ' | Select-Object -Last 1
        if ($summary) { $result.summary = $summary.Line }
    }
    $result | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $OutputDir 'result.json')
    Write-Host "Results: $OutputDir"
}
if ($result.status -ne 'PASS') { exit 1 }
exit 0
