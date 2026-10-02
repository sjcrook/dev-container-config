def defaultCapAdd: ["CHOWN","SETUID","SETGID","DAC_OVERRIDE","FOWNER"];

(.mountDirectories // []) as $mounts
| (.extraHosts // {}) as $extraHosts
| ($blockedHosts // []) as $blocked
|
{
  name: (.name // "DevContainer"),
  build: { dockerfile: "Dockerfile", context: "." },
  workspaceFolder: (.workspaceFolder // "/workspace"),
  workspaceMount: ("source=${localWorkspaceFolder},target=" + (.workspaceFolder // "/workspace") + ",type=bind,consistency=cached")
}
+ (if ($mounts|length) > 0 then
    { initializeCommand: ([ $mounts[] | "mkdir -p ${localWorkspaceFolder}/" + .hostPath ] | join(" && ")) }
  else {} end)
+ { features: (.features // {}) }
+ (if ($mounts|length) > 0 then
    { mounts: [ $mounts[] | "source=${localWorkspaceFolder}/" + .hostPath + ",target=" + .containerPath + ",type=bind" + (if (.readonly // true) then ",readonly" else "" end) ] }
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
+ (if ((.postCreateCommand // "") != "") then { postCreateCommand: .postCreateCommand } else {} end)
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
