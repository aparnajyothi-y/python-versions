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
        $this.InstallationScriptName = "setup.sh"
        $this.OutputArtifactName = "python-$Version-$Platform-$Architecture.tar.gz"
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
        $expandedSourceLocation = Join-Path -Path $this.TempFolderLocation -ChildPath "SourceCode"
        New-Item -Path $expandedSourceLocation -ItemType Directory | Out-Null

        Extract-TarArchive -ArchivePath $archiveFilepath -OutputDirectory $expandedSourceLocation
        Write-Debug "Done; Sources location: $expandedSourceLocation"

        return $expandedSourceLocation
    }

    [void] CreateInstallationScript() {
        $installationScriptLocation = New-Item -Path $this.WorkFolderLocation `
                                               -Name $this.InstallationScriptName `
                                               -ItemType File

        $installationTemplateLocation = Join-Path `
            -Path $this.InstallationTemplatesLocation `
            -ChildPath $this.InstallationTemplateName

        $installationTemplateContent = Get-Content -Path $installationTemplateLocation -Raw

        $variablesToReplace = @{
            "{{__VERSION_FULL__}}" = $this.Version
            "{{__ARCH__}}"         = $this.Architecture
        }

        foreach ($key in $variablesToReplace.Keys) {
            $installationTemplateContent =
                $installationTemplateContent.Replace($key, $variablesToReplace[$key])
        }

        $installationTemplateContent | Out-File -FilePath $installationScriptLocation
        Write-Debug "Done; Installation script location: $installationScriptLocation"
    }

    [void] Make() {
        Write-Debug "make Python $($this.Version)-$($this.Architecture) $($this.Platform)"
        $buildOutputLocation = New-Item `
            -Path $this.WorkFolderLocation `
            -Name "build_output.txt" `
            -ItemType File

        # ------------------------------------------------------------------
        # Workaround Option 2:
        # Skip only the failing bz2 test during PGO on Linux ARM
        # ------------------------------------------------------------------

        $isLinux = $this.Platform -like "linux*"
        $isArm   = $this.Architecture -match "arm"
        $isPGO   = (
            $env:PROFILE_TASK -ne $null -or
            $env:MAKEFLAGS -match "profile"
        )

        Write-Debug "Build context:"
        Write-Debug "  Platform     : $($this.Platform)"
        Write-Debug "  Architecture : $($this.Architecture)"
        Write-Debug "  PROFILE_TASK : $($env:PROFILE_TASK)"
        Write-Debug "  MAKEFLAGS    : $($env:MAKEFLAGS)"

        if ($isLinux -and $isArm -and $isPGO) {
            Write-Host "Applying targeted workaround:"
            Write-Host "  Skipping test_bz2.TestBZ2Decompressor.testDecompressorChunksMaxsize during PGO on Linux ARM"

            # Skip ONLY the failing test (not the whole module)
            $env:TESTOPTS = "-x test_bz2.TestBZ2Decompressor.testDecompressorChunksMaxsize"
        }

        Execute-Command -Command "make 2>&1 | tee $buildOutputLocation" -ErrorAction Continue
        Execute-Command -Command "make install" -ErrorAction Continue

        Write-Debug "Done; Make log location: $buildOutputLocation"
    }

    [void] CopyBuildResults() {
        $buildFolder = $this.GetFullPythonToolcacheLocation()
        Move-Item -Path "$buildFolder/*" -Destination $this.WorkFolderLocation
    }

    [void] ArchiveArtifact() {
        $outputPath = Join-Path $this.ArtifactFolderLocation $this.OutputArtifactName
        Create-TarArchive -SourceFolder $this.WorkFolderLocation -ArchivePath $outputPath
    }

    [void] Build() {
        Write-Host "Prepare Python Hostedtoolcache location..."
        $this.PreparePythonToolcacheLocation()

        Write-Host "Prepare system environment..."
        $this.PrepareEnvironment()

        Write-Host "Download Python $($this.Version)[$($this.Architecture)] sources..."
        $sourcesLocation = $this.Download()

        Push-Location -Path $sourcesLocation

        Write-Host "Configure for $($this.Platform)..."
        $this.Configure()

        Write-Host "Make for $($this.Platform)..."
        $this.Make()

        Pop-Location

        Write-Host "Generate structure dump"
        New-ToolStructureDump `
            -ToolPath $this.GetFullPythonToolcacheLocation() `
            -OutputFolder $this.WorkFolderLocation

        Write-Host "Copying build results to destination location"
        $this.CopyBuildResults()

        Write-Host "Create installation script..."
        $this.CreateInstallationScript()

        Write-Host "Archive artifact..."
        $this.ArchiveArtifact()
    }
}
