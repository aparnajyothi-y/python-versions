using module "./python-builder.psm1"

class NixPythonBuilder : PythonBuilder {

    [string] $InstallationTemplateName
    [string] $InstallationScriptName
    [string] $OutputArtifactName
    [string] $PinnedBzip2Version = "1.0.8"

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

    [string] BuildPinnedBzip2() {
        Write-Host "Building pinned libbz2 $($this.PinnedBzip2Version)"

        $bz2Url = "https://sourceware.org/pub/bzip2/bzip2-$($this.PinnedBzip2Version).tar.gz"
        $bz2Root = Join-Path $this.TempFolderLocation "bzip2"
        $bz2Prefix = Join-Path $bz2Root "install"

        New-Item -ItemType Directory -Path $bz2Root -Force | Out-Null

        $archive = Download-File -Uri $bz2Url -OutputFolder $bz2Root
        Extract-TarArchive -ArchivePath $archive -OutputDirectory $bz2Root

        Push-Location (Join-Path $bz2Root "bzip2-$($this.PinnedBzip2Version)")

        Execute-Command -Command "make -f Makefile-libbz2_so" -ErrorAction Stop
        Execute-Command -Command "make clean" -ErrorAction Continue
        Execute-Command -Command "make" -ErrorAction Stop

        New-Item -ItemType Directory -Path $bz2Prefix -Force | Out-Null
        Copy-Item -Path "libbz2.so*" -Destination $bz2Prefix -Force
        Copy-Item -Path "bzlib.h" -Destination $bz2Prefix -Force

        Pop-Location

        return $bz2Prefix
    }

    [void] Configure() {
        Write-Host "Configuring Python with pinned libbz2"

        $bz2Prefix = $this.BuildPinnedBzip2()

        $env:CFLAGS   = "-I$bz2Prefix"
        $env:LDFLAGS  = "-L$bz2Prefix"
        $env:LD_LIBRARY_PATH = $bz2Prefix

        Execute-Command `
            -Command "./configure --enable-shared --enable-optimizations" `
            -ErrorAction Stop
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
