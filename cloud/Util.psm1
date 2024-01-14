# Copyright (c) 2020, Indy Ray. All rights reserved.

Function Get-SessionArgs {
    Param($Session)
    if($Session -ne $Null) {
        return @{ Session = $Session }
    }
    else {
        return @{}
    }
}

Function Read-CommandArguments {
    Param($Arguments)
    #TODO: if not powershell, everything is a pos argument.
    $NamedArgs = @{}
    $PosArgs = @()
    for($i = 0; $i -lt $Arguments.Length; $i++) {
        $A = $Arguments[$i]
        if($A -is [string] -and $A[0] -eq '-') {
            $NamedArgs[$A.substring(1)] = $True
            # Pretty hacky way to solve [switch] parameters, should probabally look up command arguments
            if($i+1 -lt $Arguments.Length -and $Arguments[$i+1][0] -ne '-') {
                $NamedArgs[$A.substring(1)] = $Arguments[$i+1]
            }
            $i++
        }
        else {
            $PosArgs += $A
        }
    }
    $NamedArgs, $PosArgs
}

# Helper command to run a command on the remote session, isn't perfect mostly due to Read-CommandArguments function,
# so fallback to Invoke-Command for more complicated stuff.
Function Invoke-RemoteCommand {
    Param([Parameter(Position=0)]
          $Session,
          [Parameter(Position=1, ValueFromRemainingArguments)]
          $Args)
    $SessionArgs = Get-SessionArgs $Session
    $cmd, $rest = $Args
    if($rest -isnot [array]) {
        $rest = @($rest)
    }
    $nargs, $pargs = Read-CommandArguments $rest
    $ArgumentList = @(
        $cmd,
        $nargs,
        $pargs
    )
    Invoke-Command -ScriptBlock {
        Param($cmd, $nargs, $pargs)
        & $cmd @nargs @pargs
    } -ArgumentList $ArgumentList @SessionArgs
}

Function Confirm-Dir {
    Param([string] $Dir, $Session)
    if(!(Invoke-RemoteCommand -Session $Session test-path $Dir))
    {
        [void](Invoke-RemoteCommand -Session $Session New-Item -path $Dir -type directory)
    }
    $Dir
}

Function Get-ScratchPath {
    Param($Session)
    $scratchDir = Confirm-Dir -Session $Session -Dir "C:\Temp\Scratch\"
    return $scratchDir
}

Function Get-UniqueScratchPath {
    Param($Session)
    return Confirm-Dir -Session $Session (Join-Path (Get-ScratchPath -Session $Session) (New-Guid).Guid)
}

Function Ensure-Dir
{
    Param([string] $dir)
    if(!(test-path $dir))
    {
        [void](New-Item -path $dir -type directory -ErrorAction Stop)
    }
    $Dir
}

Function Ensure-Parent-Dir
{
    Param([string] $path)
    Ensure-Dir (Split-Path -parent $path)
}

if($PSCommandPath)
{
    $scriptDir = Split-Path -parent $PSCommandPath
}
else
{
    $scriptDir = Convert-Path .
}

Function Get-InstalledFeaturePath {
    return Join-Path $Home '.ttinstalled'
}

Function Get-ConfigPath {
    $configFileName = "${HOME}/.ttgconfig"
    return $configFileName
}

Function Get-TelltalePath {
    $telltalePath = Ensure-Dir "C:\Telltale"
    return $telltalePath
}

Function Get-WorkspacePath {
    return (Join-Path $PSScriptRoot "..")
}

Function Get-WorkspaceBin {
    return (Join-Path (Get-WorkspacePath) "bin")
}

Function Get-WorkspaceTool {
    Param([string] $Tool)

    return (Join-Path (Get-WorkspaceBin) "$Tool.exe")
}

$cfgDir = Join-Path $scriptDir "config"


$P4Path = "C:\Program Files\Perforce\p4.exe"
Set-Alias -Name p4 -Value $P4Path

Function Load-Config
{
    $config = Get-Content (Get-ConfigPath) -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    return $config
}

Function Save-Config
{
    Param(
        $Config
    )
    ConvertTo-Json $Config -ErrorAction Stop | Set-Content (Get-ConfigPath) -ErrorAction Stop
}

Function Set-ConfigValue
{
    Param(
        [string] $Param,
        $Value
    )
    $Config = Load-Config
    $Config.$Param = $Value
    Save-Config $Config
}

Function Set-Installed
{
    Param(
        [string] $Feature
    )
    Write-Host "Marking feature $Feature as Installed"
    Set-ConfigValue $Feature $False
}

Function Assert-LastExitCode {
    if($LastExitCode -ne 0) {
        $Callstack = Get-PSCallStack | Out-String

        Write-Error @"
Command Failed.
$Callstack
"@
        Write-Error $LastExitCode
        #Throw $LastExitCode
    }
}

Function Test-LastError {
    Assert-LastExitCode
}

Function Load-InstallerUrls
{
    Param([switch]$Versions)
    $urls = Get-Content (Join-Path $scriptDir "InstallerUrls.json") | ConvertFrom-Json
    if($Versions) {
        $u = @{}
        [void]($urls.psobject.properties | % { $u[$_.Name] = if($_.Value.url) { $_.Value } else { [PSCustomObject]@{ url = $_.Value } } })
        return [PSCustomObject]$u
    }
    else {
        $u = @{}
        [void]($urls.psobject.properties | % { $u[$_.Name] = if($_.Value.url) { $_.Value.url } else { $_.Value } })
        return [PSCustomObject]$u
    }
    return $urls
}

function Do-Elevate
{
    Param($cmdDef)
    if($RunImmediate) {
        $myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
        $myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
        $adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator
        if(!($myWindowsPrincipal.IsInRole($adminRole)))
        {
            Start-Process PowerShell -Verb runAs -ArgumentList $cmdDef -Wait
            Exit
        }
    }
}

Function Install-Font {
    Param ([string]$fontFile)
    (New-Object -ComObject Shell.Application).Namespace(0x14).CopyHere($fontFile)
}


Function Append-Path-Env
{
    Param([string] $newDir)
    $oldPath = (Get-ItemProperty -Path 'Registry::HKEY_CURRENT_USER\Environment' -Name 'PATH').Path
    $newPath = "$newDir;$oldPath"
    Set-ItemProperty -Path 'Registry::HKEY_CURRENT_USER\Environment' -Name 'PATH' -Value $newPath -ErrorAction Stop
    $env:Path = $newPath
}

Function Set-GlobalEnv
{
    Param([string] $varName, [string] $varValue)
    Set-ItemProperty -Path 'Registry::HKEY_CURRENT_USER\Environment' -Name $varName -Value $varValue
    [environment]::SetEnvironmentVariable($varName, $varValue)
    #TODO: Broadcast WM_SETTINGCHANGE to get change to take effect.
}

Function Merge-PSObjectDefaults {
    Param(
        [Parameter(Mandatory=$True)]
        [PSCustomObject] $InputObject,
        [Parameter(Mandatory=$True)]
        [PSCustomObject] $DefaultObject
    )
    $DefaultObject.PSObject.Properties | %{if (($InputObject.PSObject.Properties | Where -Property Name -eq $_.Name) -eq $Null) { Add-Member -InputObject $InputObject -Name $_.Name -MemberType $_.MemberType -Value $_.Value}}
}

Function Run-Installer
{
    Param([string] $name, [string] $file, $runParams, $Session)
    $SessionArgs = Get-SessionArgs $Session
    $ArgumentList = @(
        $name,
        $file,
        $runParams
    )
    Invoke-Command -ScriptBlock {
        Param($name, $file, $runParams)
        $proc = if($runParams)
        {
            Start-Process -FilePath $file -ArgumentList $runParams -PassThru -Wait -ErrorAction Stop
        }
        else
        {
            Start-Process -FilePath $file -PassThru -Wait -ErrorAction Stop
        }
        if($proc.ExitCode -ne 0)
        {
            Throw "Error installing"
        }
        return $proc.ExitCode
    } -ArgumentList $ArgumentList @SessionArgs
}

Function P4-Download-Tree
{
    Param([string] $p4Path, [string] $downloadPath)

    Ensure-Dir $downloadPath
    $p4Filter = (Join-Path $p4Path '...').replace('\', '/')

    p4 files -e $p4Filter | Select-String -Pattern '^(//[^#]*)#([0-9]*) - ' | ForEach-Object {
        $p4File = $_.Matches[0].Groups[1].Value
        $p4Rev = $_.Matches[0].Groups[2].Value
        $p4FullPath = "$p4File#$p4Rev"
        $relPath = $p4File.Replace($p4Path, '')
        $localPath = Join-Path $downloadPath $relPath
        p4 print -o $localPath $p4FullPath
        Test-LastError
    }
    Test-LastError
}

Function P4-Download-Tree-Run
{
    Param([string] $name, [string] $urlPath, [string] $runFile, [string] $downloadPrefix, [string] $runParams)

    $downloadPath = Join-Path (Get-ScratchPath) $downloadPrefix
    $runPath = Join-Path $downloadPath $runFile
    P4-Download-Tree $urlPath $downloadPath
    $proc = if($runParams)
    {
        Start-Process -FilePath $runPath -ArgumentList $runParams -PassThru -Wait -ErrorAction Stop
    }
    else
    {
        Start-Process -FilePath $runPath -PassThru -Wait -ErrorAction Stop
    }
    if($proc.ExitCode -ne 0)
    {
        Throw "Error installing"
    }
    return $proc.ExitCode
}

Function P4-Download-Run
{
    Param([string] $name, [string] $urlPath, [string] $downloadFile, [string] $runParams)
    $downloadPath = Join-Path (Get-ScratchPath) $downloadFile
    p4 print -o $downloadPath $urlPath
    Test-LastError
    $proc = if($runParams)
    {
        Start-Process -FilePath $downloadPath -ArgumentList $runParams -PassThru -Wait -ErrorAction Stop
    }
    else
    {
        Start-Process -FilePath $downloadPath -PassThru -Wait -ErrorAction Stop
    }
    if($proc.ExitCode -ne 0)
    {
        Throw "Error installing"
    }
    return $proc.ExitCode
}

Function Download-Run
{
    Param([string] $name, [string] $urlPath, [string] $downloadFile, [string] $runParams, $Session)
    $downloadPath = Join-Path (Get-ScratchPath -Session $Session) $downloadFile
    Invoke-RemoteCommand -Session $Session Invoke-WebRequest $urlPath -OutFile $downloadPath -ErrorAction Stop
    return Run-Installer -Session $Session $name $downloadPath $runParams
}

Function Download-RunMSI
{
    Param([string] $name, [string] $urlPath, [string] $downloadFile, [string] $runParams, $Session)
    $downloadPath = Join-Path (Get-ScratchPath -Session $Session) $downloadFile
    Invoke-RemoteCommand -Session $Session Invoke-WebRequest $urlPath -OutFile $downloadPath -ErrorAction Stop
    return Run-Installer -Session $Session $name 'msiexec' @("/i", $downloadPath, "/qn", $runParams)
}

Function Expand-MSI
{
    Param([string] $Path, [string] $DestinationPath)

    $lessmsi = Find-PackageBinary -PackageName "LessMsi" -Binary "lessmsi" -UpdateIfMissing

    [void](& $lessmsi x $Path "$DestinationPath\")
}

Function Download-ExtractMSI
{
    Param([string] $urlPath, [string] $extractionPath, [string]$extractionPrefix)
    $Filename = ([uri]$urlPath).Segments[-1]
    $scratch = Ensure-Dir (Get-UniqueScratchPath)
    $TempDest = Join-Path $scratch $Filename
    Invoke-WebRequest $urlPath -OutFile $TempDest -ErrorAction Stop
    $ExtractDir = Join-Path $scratch ([io.path]::GetFileNameWithoutExtension($Filename))
    Expand-MSI $TempDest $ExtractDir
    Copy-Item (Join-Path $ExtractDir "$extractionPrefix\*") $extractionPath -Recurse
}

Function Expand-Archive7z
{
    Param([string] $Path, [string] $DestinationPath)
    $DestinationPath = (Get-Item $DestinationPath).FullName
    $7z = $Null
    if(Get-Command 7z -ErrorAction SilentlyContinue) {
        $7z = "7z"
    }
    elseif(Get-Command 7za -ErrorAction SilentlyContinue) {
        $7z = "7za"
    }
    else {
        $7z = Find-PackageBinary -PackageName "7Zip" -Binary "7z" -UpdateIfMissing
    }

    if(![string]::IsNullOrEmpty($7z)) {
        [void] (& $7z x $Path "-o$DestinationPath" -y)
    }
    else {
        Expand-Archive -Path $Path -DestinationPath $DestinationPAth
    }
}

Function Update-EnvironmentPath {
    Param($Session)
    $SessionArgs = Get-SessionArgs $Session
    Invoke-Command @SessionArgs -ScriptBlock { $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") }
}

Function Download-To
{
    Param([string] $urlPath, [string] $destinationPath)
    $Filename = ([uri]$urlPath).Segments[-1]
    $OutFile = (Join-Path $destinationPath $Filename)
    [void](Invoke-WebRequest $urlPath -OutFile $OutFile -ErrorAction Stop)
    return $OutFile
}

Function Download-Extract
{
    Param([string] $urlPath, [string] $extractionPath)
    $Filename = ([uri]$urlPath).Segments[-1]
    $TempDest = Join-Path (Get-ScratchPath) $Filename
    Invoke-WebRequest $urlPath -OutFile $TempDest -ErrorAction Stop
    Expand-Archive7z $TempDest $extractionPath
}

Function Download-ExtractPack
{
    Param([string] $urlPath, [string] $extractionRoot)
    $PackageName = ([system.io.fileinfo]([uri]$urlPath).Segments[-1]).BaseName
    $extractionPath = Join-Path $extractionRoot $PackageName
    Download-Extract $urlPath $extractionPath
    return $extractionPath
}

Function Copy-Tree-Run
{
    Param([string] $name, [string] $urlPath, [string] $runFile, [string] $downloadPrefix, [string] $runParams)

    $downloadPath = Join-Path (Get-ScratchPath) $downloadPrefix
    $runPath = Join-Path $downloadPath $runFile
    cp -r $urlPath $downloadPath
    return Run-Installer $name $runPath $runParams
}

Function Install-Certificate {
    Param([string] $certPath)
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2

    $cert.import($certPath, $Null, "Exportable,PersistKeySet")

    $store = New-Object System.Security.Cryptography.X509Certificates.X509Store "Root", "LocalMachine"
    $store.open("ReadWrite")
    $store.add($cert)
    $store.close()
}

$RunImmediate = $True
$ListFeatures = $False
$MarkInstalledFeatures = $Null
$ForceInstallFeatures = $Null

Function Set-ListFeatures {
    Param($List)
    $script:ListFeatures = $List
    if($script:ListFeatures) {
        $script:RunImmediate = $False
    }
}

Function Set-MarkInstalledFeatures {
    Param($InstalledFeatures)
    $script:MarkInstalledFeatures = $InstalledFeatures
    if($script:MarkInstalledFeatures -ne $Null) {
        $script:RunImmediate = $False
    }
}

Function Set-ForceInstallFeatures {
    Param($InstallFeatures)
    $script:ForceInstallFeatures = $InstallFeatures
}

Function Install-Feature {
    Param(
        [string] $Feature,
        [scriptblock] $Installer,
        [scriptblock] $OnSuccess,
        [scriptblock] $OnFailure
    )
    $Installed = $False
    $InstallList = $Null
    $Config = [PSCustomObject]@{install = $InstallList}
    Try {
        $Config = Load-Config
        $InstallList = $Config.install
    }
    Catch {}

    if($InstallList -eq $Null) {
        $InstallList = [PSCustomObject]@{}
        Add-Member -Force -MemberType NoteProperty -Name 'install' -Value $InstallList -InputObject $Config
        $Config.install = $InstallList
    }
    if($Feature -in $InstallList.PSobject.Properties.Name) {
        $Installed = $InstallList.$Feature
    }

    if($script:ListFeatures) {
        return [PSCustomObject]@{
            Name = $Feature;
            Installed = $Installed;
        }
    }

    # Checking -eq $False so "Skip" will skip install
    $DoInstall = ($Installed -eq $False) -or ($Feature -in $script:ForceInstallFeatures)
    $DoInstall = $DoInstall -or $($Feature -in $script:ForceInstallFeatures)
    if(!$script:RunImmediate) {
        $DoInstall = $False
    }
    if($Feature -in $script:MarkInstalledFeatures) {
        Write-Host "Marking $Feature as Installed"
        Add-Member -Force -MemberType NoteProperty -Name $Feature -Value $True -InputObject $InstallList
        Save-Config $Config
    }
    if($DoInstall) {
        Push-Location
        Try {
            Write-Host "Installing $Feature"
            & ($Installer)
            $Installed = $True
            Add-Member -Force -MemberType NoteProperty -Name $Feature -Value $Installed -InputObject $InstallList
            Save-Config $Config
            if($OnSuccess -ne $Null) {
                & ($OnSuccess)
            }
        }
        Catch {
            if($OnFailure -ne $Null) {
                & ($OnFailure)
            }
            Write-Host "Error!"
            Write-Host $_
            Write-Host "Failed to install $Feature"
        }
        Pop-Location
    }
}

Function Exit-Installer {
    if($RunImmediate) {
        Write-Host -NoNewLine 'Press any key to continue...';
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
    }
}

Function Download-InstallCertificate {
    Param([string] $urlPath, [string] $downloadFile)
    $downloadPath = Join-Path (Get-ScratchPath) $downloadFile
    Invoke-WebRequest $urlPath -OutFile $downloadPath
    return Install-Certificate $downloadPath
}

Function Get-AllInstalledApps {
    Get-ItemProperty HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |  Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, UninstallString, QuietUninstallString
    Get-ItemProperty HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\* |  Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, UninstallString, QuietUninstallString
    Get-ItemProperty HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate, UninstallString, QuietUninstallString
}

Function Get-InstalledApp {
    Param(
        [ValidateNotNullOrEmpty()]
        [string] $AppName,
        [string] $Version
    )
    $InstalledApps = Get-AllInstalledApps
    $MatchingApps = $InstalledApps | Where -Property DisplayName -Like $AppName
    if(![string]::IsNullOrEmpty($Version)) {
        $MatchingApps = $MatchingApps | Where -Property DisplayVersion -Like $Version
    }
    return $MatchingApps
}

Function Confirm-AppRemoved {
    Param(
        [ValidateNotNullOrEmpty()]
        [string] $AppName,
        [string] $Version
    )
    $App = Get-InstalledApp -AppName $AppName -Version $Version
    if($App) {
        if ($App.QuietUninstallString[0] -eq '"') {
            iex "& $($App.QuietUninstallString)"
        }
        else {
            iex $App.QuietUninstallString
        }
    }
}

function Format-XML ([xml]$xml, $indent=2)
{
    $StringWriter = New-Object System.IO.StringWriter
    $XmlWriter = New-Object System.XMl.XmlTextWriter $StringWriter
    $xmlWriter.Formatting = "indented"
    $xmlWriter.Indentation = $Indent
    $xml.WriteContentTo($XmlWriter)
    $XmlWriter.Flush()
    $StringWriter.Flush()
    return $StringWriter.ToString()
}

function Merge-HashTables {
    $HashTables = ($Input + $Args)
    $Out = @{}
    $HashTables | % {
        if($_ -is [Hashtable]) {
            ForEach($Key in $_.Keys) { $Out.$Key = $_.$Key }
        }
    }
    return $Out
}

function Merge-HashTrees {
    $HashTables = ($Input + $Args)
    $Out = @{}
    $HashTables | % {
        if($_ -is [Hashtable]) {
            ForEach($Key in $_.Keys) {
                $Value = $_.$Key
                if($Out.ContainsKey($Key) -and $Out.$Key -is [Hashtable] -and $Value -is [Hashtable]) {
                    $Value = Merge-HashTrees $Out.$Key $Value
                }
                $Out.$Key = $Value
            }
        }
    }
    return $Out
}

Function Get-RandomBase64 {
    Param($Length = 32)
    $Bytes = [byte[]]::new($Length)
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($Bytes)
    $Base64 = [System.Convert]::ToBase64String($Bytes)
    return $Base64
}

Function Get-TableMembers {
    $Objects = ($Input + $Args)
    $Objects | % { ($_.psobject.members) } | Where -Property MemberType -EQ NoteProperty | Select -ExpandProperty Value
}

Export-ModuleMember -Function '*'
Export-ModuleMember -Variable 'scriptDir'
Export-ModuleMember -Variable 'cfgDir'