using module "./python-builder.psm1"

class NixPythonBuilder : PythonBuilder {

    [string] $InstallationTemplateName
    [string] $InstallationScriptName
    [string] $OutputArtifactName

    NixPythonBuilder(
        [semver] $version,
        [string] $architecture,
        [string] $platform
    ) : Base($version, $architecture, $platform) {
        $this.InstallationTemplateName = "nix-setup-template.sh"
        $this.InstallationScriptName   = "setup.sh"
        $this.OutputArtifactName       = "python-$Version-$Platform-$Architecture.tar.gz"
    }

    [uri] GetSourceUri() {
        $base = $this.GetBaseUri()
        $versionName = $this.GetBaseVersion()
        $nativeVersion = Convert-Version -version $this.Version
        return "${base}/${versionName}/Python-${nativeVersion}.tgz"
    }

    [string] GetPythonBinary() {
        return "python3"
    }

    [string] Download() {
        $sourceUri = $this.GetSourceUri()
        Write-Host "Sources URI: $sourceUri"

        $archiveFilepath = Download-File -Uri $sourceUri -OutputFolder $this.WorkFolderLocation
        $expandedSourceLocation = Join-Path $this.TempFolderLocation "SourceCode"
        New-Item -Path $expandedSourceLocation -ItemType Directory -Force | Out-Null

        Extract-TarArchive -ArchivePath $archiveFilepath -OutputDirectory $expandedSourceLocation
        return $expandedSourceLocation
    }

    [void] Configure() {
        Write-Host "Configuring Python build"

        $isLinuxArm =
            $this.Platform -eq "linux" -and
            $this.Architecture -match "arm"

        if ($isLinuxArm) {
            Write-Host "Linux ARM detected → disabling PGO (--enable-optimizations)"
            Execute-Command -Command "./configure --enable-shared" -ErrorAction Stop
        }
        else {
            Write-Host "Non-ARM or non-Linux platform → enabling PGO"
            Execute-Command -Command "./configure --enable-shared --enable-optimizations" -ErrorAction Stop
        }
    }

    [void] Make() {
        Write-Debug "make Python $($this.Version)-$($this.Architecture) $($this.Platform)"

        $buildOutputLocation = Join-Path $this.WorkFolderLocation "build_output.txt"
        Execute-Command -Command "make 2>&1 | tee $buildOutputLocation" -ErrorAction Continue
        Execute-Command -Command "make install" -ErrorAction Continue
    }

    [void] CopyBuildResults() {
        $buildFolder = $this.GetFullPythonToolcacheLocation()
        Move-Item -Path "$buildFolder/*" -Destination $this.WorkFolderLocation -Force
    }

    [void] CreateInstallationScript() {
        $installationScriptLocation = Join-Path $this.WorkFolderLocation $this.InstallationScriptName
        $installationTemplateLocation = Join-Path $this.InstallationTemplatesLocation $this.InstallationTemplateName

        $content = Get-Content $installationTemplateLocation -Raw
        $content = $content.Replace("{{__VERSION_FULL__}}", $this.Version)
        $content = $content.Replace("{{__ARCH__}}", $this.Architecture)

        $content | Out-File $installationScriptLocation -Encoding utf8
        chmod +x $installationScriptLocation
    }

    [void] ArchiveArtifact() {
        $outputPath = Join-Path $this.ArtifactFolderLocation $this.OutputArtifactName
        Create-TarArchive -SourceFolder $this.WorkFolderLocation -ArchivePath $outputPath
    }

    [void] Build() {
        Write-Host "Prepare Python hostedtoolcache location"
        $this.PreparePythonToolcacheLocation()

        Write-Host "Prepare system environment"
        $this.PrepareEnvironment()

        Write-Host "Download Python $($this.Version) [$($this.Architecture)]"
        $sourcesLocation = $this.Download()

        Push-Location $sourcesLocation
        $this.Configure()
        $this.Make()
        Pop-Location

        New-ToolStructureDump `
            -ToolPath $this.GetFullPythonToolcacheLocation() `
            -OutputFolder $this.WorkFolderLocation

        $this.CopyBuildResults()
        $this.CreateInstallationScript()
        $this.ArchiveArtifact()
    }
}
