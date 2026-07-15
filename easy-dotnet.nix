{
  buildDotnetModule,
  fetchFromGitHub,
  pkgs,
  ...
}:

let
  inherit (pkgs) lib;
  version = "3.4.11";
  runtimeId = pkgs.dotnetCorePackages.systemToDotnetRid pkgs.stdenvNoCC.hostPlatform.system;
  roslynDir = "${pkgs.roslyn-ls}/lib/roslyn-ls";
  buildDotnetSdk = pkgs.dotnetCorePackages.combinePackages (
    with pkgs.dotnetCorePackages;
    [
      # Roslyn from nixpkgs targets net10.0. EasyDotnet itself still targets
      # net8.0, whose ASP.NET runtime and targeting pack are included below.
      sdk_10_0
      aspnetcore_8_0
    ]
  );
  runtimeDotnetSdk = pkgs.dotnetCorePackages.combinePackages (
    with pkgs.dotnetCorePackages;
    [
      # `dotnet-easydotnet roslyn start` uses MSBuildLocator and requires an SDK.
      # Keep ASP.NET 8 available for EasyDotnet's net8.0 application host.
      sdk_10_0
      aspnetcore_8_0
    ]
  );
  roslynLanguageServer = pkgs.writeShellScriptBin "roslyn-language-server" ''
    exec ${lib.getExe pkgs.roslyn-ls} "$@"
  '';
in
buildDotnetModule {
  pname = "EasyDotnet";
  inherit version;
  src = fetchFromGitHub {
    owner = "GustavEikaas";
    repo = "easy-dotnet-server";
    rev = "88f9b8028990b61875ac31b8718685fdad794e76";
    hash = "sha256-r7na/nkBLQ4nNhCSxoXH/Jxd4kfMI/MwNanPgAMpTow=";
  };
  patches = [ ./easy-dotnet.patch ];

  projectFile = "EasyDotnet.IDE/EasyDotnet.IDE.csproj";
  inherit runtimeId;

  executables = [ "EasyDotnet.IDE" ];
  nugetDeps = ./deps.json;

  dotnet-sdk = buildDotnetSdk;
  dotnet-runtime = runtimeDotnetSdk;
  dotnetFlags = [
    # Newer SDKs surface existing CS1998 warnings in this release.
    "-p:TreatWarningsAsErrors=false"
  ];

  makeWrapperArgs = [
    "--set"
    "EASY_DOTNET_ROSLYN_DLL_PATH"
    "${roslynDir}/Microsoft.CodeAnalysis.LanguageServer.dll"
    "--set"
    "EASY_DOTNET_DEBUGGER_BIN_PATH"
    "${lib.getExe pkgs.netcoredbg}"
    "--prefix"
    "PATH"
    ":"
    "${lib.makeBinPath [
      roslynLanguageServer
      pkgs.netcoredbg
    ]}"
  ];

  postConfigure = ''
    local -a extraRestoreFlags
    concatTo extraRestoreFlags dotnetFlags dotnetRestoreFlags

    # These payload projects are published from custom MSBuild targets, so the
    # normal ProjectReference restore for EasyDotnet.IDE does not see them.
    for project in \
      EasyDotnet.Aspire/EasyDotnet.Aspire.csproj \
      EasyDotnet.AppWrapper/EasyDotnet.AppWrapper.csproj \
      EasyDotnet.BuildServer/EasyDotnet.BuildServer.csproj \
      EasyDotnet.RoslynLanguageServices/EasyDotnet.RoslynLanguageServices.csproj \
      EasyDotnet.StartupHook/EasyDotnet.StartupHook.csproj
    do
      dotnet restore "$project" \
        -p:ContinuousIntegrationBuild=true \
        -p:Deterministic=true \
        -p:NuGetAudit=false \
        "''${extraRestoreFlags[@]}"

      dotnet restore "$project" \
        -p:ContinuousIntegrationBuild=true \
        -p:Deterministic=true \
        -p:NuGetAudit=false \
        --runtime "${runtimeId}" \
        "''${extraRestoreFlags[@]}"
    done
  '';

  postBuild = ''
    dotnet build EasyDotnet.RoslynLanguageServices/EasyDotnet.RoslynLanguageServices.csproj \
      --configuration Release \
      --no-restore \
      -p:NixRoslynDir=${roslynDir} \
      -p:ContinuousIntegrationBuild=true \
      -p:Deterministic=true \
      -p:TreatWarningsAsErrors=false
  '';

  postInstall = ''
    local builtPayloads="EasyDotnet.IDE/bin/Release/net8.0/${runtimeId}"
    local roslynAssets="$out/lib/EasyDotnet/Tools/Roslyn"
    mkdir -p \
      "$out/lib/EasyDotnet/Tools" \
      "$roslynAssets/Analyzers" \
      "$roslynAssets/DevKit" \
      "$roslynAssets/Extensions/EasyDotnet"

    cp -r "$builtPayloads/Tools/Aspire" "$out/lib/EasyDotnet/Tools/"
    cp -r "$builtPayloads/Tools/AppWrapper" "$out/lib/EasyDotnet/Tools/"
    cp -r "$builtPayloads/Tools/BuildServer" "$out/lib/EasyDotnet/"
    cp -r "$builtPayloads/DebuggerPayloads" "$out/lib/EasyDotnet/"

    cp EasyDotnet.RoslynLanguageServices/bin/Release/net10.0/EasyDotnet.RoslynLanguageServices.dll \
      "$roslynAssets/Analyzers/"
    cp EasyDotnet.RoslynLanguageServices/bin/Release/net10.0/EasyDotnet.RoslynLanguageServices.dll \
      "$roslynAssets/Extensions/EasyDotnet/"
    ln -s ${roslynDir}/Microsoft.CodeAnalysis.ExternalAccess.Extensions.dll \
      "$roslynAssets/DevKit/Microsoft.CodeAnalysis.ExternalAccess.Extensions.dll"
  '';

  postFixup = ''
    ln -s "$out/bin/EasyDotnet.IDE" "$out/bin/dotnet-easydotnet"
  '';
}
