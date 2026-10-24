def defaultCapAdd: ["CHOWN","SETUID","SETGID","DAC_OVERRIDE","FOWNER"];

(.mounts // []) as $mounts
| (.extraHosts // {}) as $extraHosts
| ($blockedHosts // []) as $blocked
| (.workspaceFolder // "/workspace") as $workspaceFolder
# VS Code terminals are non-login shells, so /etc/profile.d isn't sourced automatically -- bashrc is.
| (
    (if (.dockerfileBuild.toolchains.pnpm != null) then
      ["grep -q npm-guard ~/.bashrc || echo '. " + $workspaceFolder + "/.devcontainer/npm-guard.sh' >> ~/.bashrc"]
    else [] end)
    + (if ((.postCreateCommand // "") != "") then [.postCreateCommand] else [] end)
    | if length > 0 then join(" && ") else null end
  ) as $postCreateCommand
|
{
  name: (.name // "DevContainer"),
  build: { dockerfile: "Dockerfile", context: "." },
  workspaceFolder: $workspaceFolder,
  workspaceMount: ("source=${localWorkspaceFolder},target=" + $workspaceFolder + ",type=bind,consistency=cached")
}
+ (if ($mounts|length) > 0 then
    { initializeCommand: ([ $mounts[] | "mkdir -p " + (("${localWorkspaceFolder}/" + .source) | @sh) ] | join(" && ")) }
  else {} end)
+ { features: (.features // {}) }
+ (if ($mounts|length) > 0 then
    { mounts: [ $mounts[] | "source=${localWorkspaceFolder}/" + .source + ",target=" + .target + ",type=bind" + (if (.readonly != false) then ",readonly" else "" end) ] }
  else {} end)
+ {
    runArgs: (
      ["--security-opt","no-new-privileges","--cap-drop","ALL"]
      + ([ defaultCapAdd[] | "--cap-add", . ])
      + ["--add-host","host.docker.internal:host-gateway"]
      + ([ $extraHosts | to_entries[] | "--add-host", (.key + ":" + .value) ])
      + ([ $blocked[] as $h | "--add-host", ($h + ":0.0.0.0") ])
      + ([ $blocked[] as $h | "--add-host", ($h + ":[::1]") ])
    )
  }
+ { remoteUser: (.remoteUser // "vscode") }
+ (if ((.remoteEnv // {})|length) > 0 then { remoteEnv: (.remoteEnv // {}) } else {} end)
+ (if ($postCreateCommand != null) then { postCreateCommand: $postCreateCommand } else {} end)
+ {
    customizations: {
      vscode: (
        {
          settings: (
            {
              "files.watcherExclude": {
                "**/*.lnk": true,
                "**/node_modules/**": true,
                "**/target/**": true,
                "**/.git/objects/**": true,
                "**/.git/subtree-cache/**": true
              },
              "files.exclude": { "**/*.lnk": true },
              "terminal.integrated.defaultProfile.linux": "bash"
            }
            + (if ((.javaProjectSourcePaths // [])|length) > 0 then { "java.project.sourcePaths": .javaProjectSourcePaths } else {} end)
            + ((.customizations.vscode.settings) // {})
          ),
          extensions: (((.customizations.vscode.extensions) // []) | unique)
        }
      )
    }
  }
+ ((.devcontainerExtra) // {})
