def csv_to_array($s): ($s // "") | split(",") | map(gsub("^\\s+|\\s+$";"")) | map(select(length > 0));
# Interactive mode's answers file is a throwaway temp file, not the project
# root, so "./x"/"../x" paths typed at the prompt must be made absolute now
# (while $cwd is still the directory generate.sh was invoked from) rather than
# left to resolve against the temp file's directory later.
def abs_if_relative($cwd):
  if test("^\\./|^\\.\\./") then ($cwd + "/" + .) else . end;
# "sourcePath:targetPath" or "sourcePath:targetPath:x" (x = executable)
def parse_file_entry($cwd):
  capture("^(?<src>[^:]+):(?<tgt>[^:]+)(:(?<flag>.+))?$")
  | { sourcePath: (.src | abs_if_relative($cwd)), targetPath: .tgt }
  + (if ((.flag // "") | test("^(x|exec|true)$";"i")) then {executable: true} else {} end);

({}
  + (if ($nodeVersion|length) > 0 then {node: {version: $nodeVersion}} else {} end)
  + (if ($javaVersion|length) > 0 then {java: {version: $javaVersion}} else {} end)
  + (if ($pnpmNpmrcPath|length) > 0 then {pnpm: {npmrcPath: ($pnpmNpmrcPath | abs_if_relative($cwd))}} else {} end)
) as $toolchains
|
{
  schemaVersion: 1,
  name: $name,
  remoteUser: $remoteUser
}
+ (if ($toolchains|length) > 0 then { toolchains: $toolchains } else {} end)
+ (if ($mountDirectories|length) > 0 then
    { mountDirectories: $mountDirectories }
  else {} end)
+ (if ($blockedHostsIsFile == "true") then
    { blockedRegistryHostsFile: $blockedHostsRaw }
  elif ($blockedHostsRaw|length) > 0 then
    { blockedRegistryHosts: csv_to_array($blockedHostsRaw) }
  else {} end)
+ (if ($extraHostsRaw|length) > 0 then
    { extraHosts: (csv_to_array($extraHostsRaw) | map(capture("^(?<h>[^:]+):(?<v>.*)$")) | map({(.h): .v}) | add) }
  else {} end)
+ (if ($filesRaw|length) > 0 then
    { files: (csv_to_array($filesRaw) | map(parse_file_entry($cwd))) }
  else {} end)
+ (if ($postCreate|length) > 0 then { postCreateCommand: $postCreate } else {} end)
+ (if ($javaSourcePathsRaw|length) > 0 then { javaProjectSourcePaths: csv_to_array($javaSourcePathsRaw) } else {} end)
+ (if ($extensionsRaw|length) > 0 then
    { customizations: { vscode: { extensions: csv_to_array($extensionsRaw) } } }
  else {} end)
