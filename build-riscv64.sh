#! /usr/bin/env bash
set -e

outputFolder='_output'
testPackageFolder='_tests'
artifactsFolder="_artifacts";

ProgressStart()
{
    echo "Start '$1'"
}

ProgressEnd()
{
    echo "Finish '$1'"
}

UpdateVersionNumber()
{
    if [ "$PROWLARRVERSION" != "" ]; then
        echo "Updating Version Info"
        sed -i'' -e "s/<AssemblyVersion>[0-9.*]\+<\/AssemblyVersion>/<AssemblyVersion>$PROWLARRVERSION<\/AssemblyVersion>/g" src/Directory.Build.props
        sed -i'' -e "s/<AssemblyConfiguration>[\$()A-Za-z-]\+<\/AssemblyConfiguration>/<AssemblyConfiguration>${BUILD_SOURCEBRANCHNAME}<\/AssemblyConfiguration>/g" src/Directory.Build.props
        sed -i'' -e "s/<string>10.0.0.0<\/string>/<string>$PROWLARRVERSION<\/string>/g" distribution/osx/Prowlarr.app/Contents/Info.plist
    fi
}

LintUI()
{
    ProgressStart 'ESLint'
    yarn lint
    ProgressEnd 'ESLint'

    ProgressStart 'Stylelint'
    if [ "$os" = "windows" ]; then
        yarn stylelint-windows
    else
        yarn stylelint-linux
    fi
    ProgressEnd 'Stylelint'
}

Build()
{
    ProgressStart 'Build'

    rm -rf $outputFolder
    rm -rf $testPackageFolder

    slnFile=src/Prowlarr.riscv-64.slnx

    if [ $os = "windows" ]; then
        platform=Windows
    else
        platform=Posix
    fi

    dotnet clean $slnFile -c Debug
    dotnet clean $slnFile -c Release

    if [[ -z "$RID" || -z "$FRAMEWORK" ]];
    then
        dotnet msbuild -restore $slnFile -p:SelfContained=True -p:Configuration=Release -p:Platform=$platform -t:PublishAllRids
    else
        dotnet msbuild -restore $slnFile -p:SelfContained=True -p:Configuration=Release -p:Platform=$platform -p:RuntimeIdentifiers=$RID -t:PublishAllRids
    fi

    ProgressEnd 'Build'
}

YarnInstall()
{
    ProgressStart 'yarn install'
    yarn install --frozen-lockfile --network-timeout 120000
    ProgressEnd 'yarn install'
}

RunWebpack()
{
    ProgressStart 'Running webpack'
    yarn run build --env production
    ProgressEnd 'Running webpack'
}

PackageFiles()
{
    local folder="$1"
    local framework="$2"
    local runtime="$3"

    rm -rf $folder
    mkdir -p $folder
    cp -r $outputFolder/$framework/$runtime/publish/* $folder
    cp -r $outputFolder/Prowlarr.Update/$framework/$runtime/publish $folder/Prowlarr.Update
    cp -r $outputFolder/UI $folder

    echo "Adding LICENSE"
    cp LICENSE $folder
}

PackageLinux()
{
    local framework="$1"
    local runtime="$2"

    ProgressStart "Creating $runtime Package for $framework"

    local folder=$artifactsFolder/$runtime/$framework/Prowlarr

    PackageFiles "$folder" "$framework" "$runtime"

    echo "Removing Service helpers"
    rm -f $folder/ServiceUninstall.*
    rm -f $folder/ServiceInstall.*

    echo "Removing Prowlarr.Windows"
    rm $folder/Prowlarr.Windows.*

    echo "Adding Prowlarr.Mono to UpdatePackage"
    cp $folder/Prowlarr.Mono.* $folder/Prowlarr.Update
    cp $folder/Mono.Posix.NETStandard.* $folder/Prowlarr.Update
    cp $folder/libMonoPosixHelper.* $folder/Prowlarr.Update

    ProgressEnd "Creating $runtime Package for $framework"
}

Package()
{
    local framework="$1"
    local runtime="$2"
    local SPLIT

    IFS='-' read -ra SPLIT <<< "$runtime"

    PackageLinux "$framework" "$runtime"
}

PackageTests()
{
    local framework="$1"
    local runtime="$2"

    cp test.sh "$testPackageFolder/$framework/$runtime/publish"

    rm -f $testPackageFolder/$framework/$runtime/*.log.config

    ProgressEnd 'Creating Test Package'
}

os="posix"

    echo "No arguments provided, building everything"
    BACKEND=YES
    FRONTEND=YES
    PACKAGES=YES
    INSTALLER=NO
    LINT=YES
    ENABLE_EXTRA_PLATFORMS=NO
    ENABLE_EXTRA_PLATFORMS_IN_SDK=NO
    RID="linux-riscv64"
    FRAMEWORK="net10.0"

if [ "$BACKEND" = "YES" ];
then
    UpdateVersionNumber
    Build
#    PackageTests "$FRAMEWORK" "$RID"
fi

if [[ "$LINT" = "YES" || "$FRONTEND" = "YES" ]];
then
    YarnInstall
fi

if [ "$LINT" = "YES" ];
then
    LintUI
fi

if [ "$FRONTEND" = "YES" ];
then
    RunWebpack
fi

if [ "$PACKAGES" = "YES" ];
then
    UpdateVersionNumber
    Package "$FRAMEWORK" "$RID"
fi
