def csv_to_array($s): ($s // "") | split(",") | map(gsub("^\\s+|\\s+$";"")) | map(select(length > 0));
def yes($s): ($s // "") | test("^[Yy]");

({}
  + (if ($nodeVersion|length) > 0 then {node: {version: $nodeVersion}} else {} end)
  + (if ($javaVersion|length) > 0 then {java: {version: $javaVersion}} else {} end)
) as $toolchains
|
{
  schemaVersion: 1,
  name: $name,
  remoteUser: $remoteUser
}
+ (if ($toolchains|length) > 0 then { toolchains: $toolchains } else {} end)
+ (if yes($wantDataMount) then
    { mountDirectories: [ { hostPath: "data", containerPath: "/workspace/data", readonly: true } ] }
  else {} end)
+ (if yes($wantNpmGuard) then
    { files: [ { sourcePath: "templates/npm-guard.sh", targetPath: "/etc/profile.d/npm-guard.sh", executable: true } ] }
  else {} end)
+ (if ($blockedHostsIsFile == "true") then
    { blockedRegistryHostsFile: $blockedHostsRaw }
  elif ($blockedHostsRaw|length) > 0 then
    { blockedRegistryHosts: csv_to_array($blockedHostsRaw) }
  else {} end)
+ (if ($extraHostsRaw|length) > 0 then
    { extraHosts: (csv_to_array($extraHostsRaw) | map(capture("^(?<h>[^:]+):(?<v>.*)$")) | map({(.h): .v}) | add) }
  else {} end)
+ (if ($postCreate|length) > 0 then { postCreateCommand: $postCreate } else {} end)
+ (if ($javaSourcePathsRaw|length) > 0 then { javaProjectSourcePaths: csv_to_array($javaSourcePathsRaw) } else {} end)
+ (if ($extensionsRaw|length) > 0 then
    { customizations: { vscode: { extensions: csv_to_array($extensionsRaw) } } }
  else {} end)
