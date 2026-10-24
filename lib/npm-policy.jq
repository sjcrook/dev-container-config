# JSON is also valid YAML; keeping the generated file in this subset lets jq
# validate and render it without introducing a host-side YAML dependency.
split("\n")
| map(gsub("\r$"; "") | select(test("^\\s*([#;]|$)") | not)
    | if test("^\\s*[^=\\s]+\\s*=")
      then capture("^\\s*(?<key>[^=\\s]+)\\s*=\\s*(?<value>.*?)\\s*$")
      else error("Corporate .npmrc must use key=value entries") end)
| if any(.[]; (.key | test("(_authToken|_auth|_password|password)$"; "i"))
    and (.value | test("^\\$\\{[A-Za-z_][A-Za-z0-9_]*\\}$") | not))
  then error("Do not copy literal registry credentials into the build context; use environment placeholders and build/runtime secrets")
  else . end
| if any(.[]; (.key | test("(^|:)registry$"))
    and (.value | test("^https?://[^/]*@")))
  then error("Registry URLs must not embed credentials; configure authentication separately")
  else . end
| from_entries
| if (.registry // "" | length) == 0 then error("Corporate .npmrc requires registry=") else . end
| (.["min-release-age"] // "0") as $days
| if ($days | test("^[0-9]+$") | not) then error("min-release-age must be a non-negative integer in days") else . end
| (.["ignore-scripts"] // "false") as $scripts
| if ($scripts != "true" and $scripts != "false") then error("ignore-scripts must be true or false") else . end
| {
    minimumReleaseAge: (($days | tonumber) * 1440),
    minimumReleaseAgeStrict: true,
    minimumReleaseAgeIgnoreMissingTime: false,
    ignoreScripts: ($scripts == "true"),
    globalBinDir: "/opt/devcontainer/bin",
    globalDir: "/opt/devcontainer/pnpm"
  }
  + (if has("verify-deps-before-run") then
      .["verify-deps-before-run"] as $verify
      | if ($verify == "never" or $verify == "false") then {verifyDepsBeforeRun: false}
        elif $verify == "true" then {verifyDepsBeforeRun: true}
        elif (["install", "warn", "error", "prompt"] | index($verify)) != null
        then {verifyDepsBeforeRun: $verify}
        else error("Unsupported verify-deps-before-run value") end
    else {} end)
  + (if has("strict-ssl") then
      if (.["strict-ssl"] != "true" and .["strict-ssl"] != "false")
      then error("strict-ssl must be true or false")
      else {strictSsl: (.["strict-ssl"] == "true")} end
    else {} end)
