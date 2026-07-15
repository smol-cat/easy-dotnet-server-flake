# EasyDotnet Server Flake

This repository packages the [EasyDotnet
server](https://github.com/GustavEikaas/easy-dotnet-server) as a reproducible
Nix flake.

The package builds EasyDotnet from a pinned source revision and includes its
locked NuGet dependencies, Nix-specific source patch, Roslyn language server,
and `netcoredbg`. Runtime wrappers configure the paths EasyDotnet uses to find
Roslyn and the debugger.

> [!NOTE]
> Unlike the upstream .NET tool, this flake does not include the `dncdbg`
> debugger or `SharpDbg.Cli.dll`. These debugger engines are not currently
> packaged in nixpkgs, so they cannot be reused here as Nix dependencies.
> Debugging through `netcoredbg` remains available because nixpkgs provides it
> and I do not really care about the other debuggers

## Build

```console
nix build
```

The flake provides both `packages.<system>.default` and
`packages.<system>.easy-dotnet` for `x86_64-linux` and `aarch64-linux`.

## Run

After building, run either installed executable:

```console
./result/bin/dotnet-easydotnet
./result/bin/EasyDotnet.IDE
```
