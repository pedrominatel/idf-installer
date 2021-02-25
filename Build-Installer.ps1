[CmdletBinding()]
param (
    [Parameter()]
    [String]
    $Compression = 'lzma',
    [String]
    $IdfPythonWheelsVersion = '3.8-2021-01-21',
    [String]
    $InstallerType = 'online',
    [String]
    $Python = 'python'
)

# Stop on error
$ErrorActionPreference = "Stop"

function DownloadIdfVersions() {
    if (Test-Path -Path $Versions -PathType Leaf) {
        "$Versions exists."
        return
    }
    "Downloading idf_versions.txt..."
    Invoke-WebRequest -O $Versions https://dl.espressif.com/dl/esp-idf/idf_versions.txt
}

function PrepareIdfGit {

}

function PrepareIdfPython {

}

function PrepareIdfPythonWheels {

}

function PrepareOfflineBranches {
    $BundleDir="build\$InstallerType\releases\esp-idf-bundle"

    if ( Test-Path -Path $BundleDir -PathType Container ) {
        git -C "$BundleDir" fetch
    } else {
        "Performing full clone."
        git clone --shallow-since=2020-01-01 --jobs 8 --recursive https://github.com/espressif/esp-idf.git "$BundleDir"

        # Fix repo mode
        git -C "$BundleDir" config --local core.fileMode false
        git -C "$BundleDir" submodule foreach --recursive git config --local core.fileMode false
        # Allow deleting directories by git clean --force
        # Required when switching between versions which does not have a module present in current branch
        git -C "$BundleDir" config --local clean.requireForce false
        git -C "$BundleDir" reset --hard
        git -C "$BundleDir" submodule foreach git reset --hard

    }

    $Content = Get-Content -Path $Versions
    [array]::Reverse($Content)
    $Content | ForEach-Object {
        $Branch = $_

        if ($null -eq $Branch) {
            continue;
        }

        Push-Location "$BundleDir"

        "Processing branch: ($Branch)"
        git fetch origin tag "$Branch"
        git checkout "$Branch"

        # Pull changes only for branches, tags does not support pull
        #https://stackoverflow.com/questions/1593188/how-to-programmatically-determine-whether-the-git-checkout-is-a-tag-and-if-so-w
        git describe --exact-match HEAD
        if (0 -ne $LASTEXITCODE) {
            git pull
        }

        git submodule update --init --recursive

        # Clean up left over submodule directories after switching to other branch
        git clean --force -d
        # Some modules are very persistent like cmok and needs 2nd round of cleaning
        git clean --force -d

        git reset --hard
        git submodule foreach git reset --hard

        if (0 -ne (git status -s | Measure-Object).Count) {
            "git status not empty. Repository is dirty. Aborting."
            git status
            Exit 1
        }

        &$Python tools\idf_tools.py --tools-json tools/tools.json --non-interactive download --platform Windows-x86_64 all
        Pop-Location
    }

    # Remove symlinks which are not supported on Windws, unfortunatelly -c core.symlinks=false does not work
    Get-ChildItem "$BundleDir" -recurse -force | Where-Object { $_.Attributes -match "ReparsePoint" }
}

$OutputFileBaseName = "esp-idf-tools-setup-${InstallerType}-unsigned"
$IdfToolsPath = (Get-Location).Path + "\build\$InstallerType"
$Versions = $IdfToolsPath + '\idf_versions.txt'
$env:IDF_TOOLS_PATH=$IdfToolsPath
if (!(Test-Path -PathType Container -Path  $IdfToolsPath)) {
    mkdir $IdfToolsPath
}
"Using IDF_TOOLS_PATH specific for installer type: $IdfToolsPath"
$IsccParameters = @("/DCOMPRESSION=$Compression", "/DSOLIDCOMPRESSION=no", "/DPYTHONWHEELSVERSION=$IdfPythonWheelsVersion")
$IsccParameters += "/DDIST=..\..\build\$InstallerType"

if ('offline' -eq $InstallerType) {
    $IsccParameters += '/DOFFLINE=yes'
    PrepareIdfGit
    PrepareIdfPython
    PrepareIdfPythonWheels
    Copy-Item .\src\Resources\idf_versions_offline.txt $Versions
    PrepareOfflineBranches
} elseif ('online' -eq $InstallerType) {
    PrepareIdfGit
    PrepareIdfPython
    DownloadIdfVersions
    $IsccParameters += '/DOFFLINE=no'
} else {
    $IsccParameters += '/DOFFLINE=no'
}

$IsccParameters += "/DINSTALLERBUILDTYPE=$InstallerType"

$IsccParameters += ".\src\InnoSetup\IdfToolsSetup.iss"
$IsccParameters += "/F$OutputFileBaseName"

$Command = "iscc $IsccParameters"
$Command
iscc $IsccParameters
if (0 -eq $LASTEXITCODE) {
    $Command
    Get-ChildItem -l build\$OutputFileName
} else {
    "Build failed!"
}
