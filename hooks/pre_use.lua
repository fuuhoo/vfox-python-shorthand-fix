-- vfox-python v0.6.2 hooks/pre_use.lua, modified so that a shorthand version
-- ("3.12") resolves to an installed patch version ("3.12.14").
-- See README.md for the root cause and upstream.diff for the exact change.
require("util")

--- Expand a shorthand version such as "3.12" into the highest installed
--- version that carries it ("3.12.14"), the same rule vfox core applies in
--- internal/sdk/sdk.go preUse(). Returns nil when nothing is installed for it.
local function resolveInstalledVersion(version, installedSdks)
    if version == nil or installedSdks == nil then
        return nil
    end
    if installedSdks[version] ~= nil then
        return version
    end

    local prefix = version .. "."
    local best = nil
    for name in pairs(installedSdks) do
        if type(name) == "string" and name:sub(1, #prefix) == prefix then
            if best == nil or compare_versions(name, best) > 0 then
                best = name
            end
        end
    end
    return best
end

-- PreUse hook: Called before switching to a Python version
-- This ensures the target version is healthy and has correct shebang lines
function PLUGIN:PreUse(ctx)
    local resolved = resolveInstalledVersion(ctx.version, ctx.installedSdks)

    -- Only process on Unix systems (Windows doesn't have shebang issues)
    if OS_TYPE == "windows" then
        return {
            version = resolved or ctx.version
        }
    end

    local version = resolved
    local previousVersion = ctx.previousVersion
    local scope = ctx.scope
    local cwd = ctx.cwd
    local installedSdks = ctx.installedSdks

    if not version then
        -- Hand the request back to vfox so it can report the version as
        -- unusable instead of silently switching to a non-existent one.
        print("Warning: Target version " .. ctx.version .. " is not installed")
        return ""
    end

    print("Preparing Python " .. version .. " for use...")

    local installPath = resolvePythonInstallPath(installedSdks[version].path, version)
    print("Checking Python installation at: " .. installPath)

    -- Perform health check
    local healthReport = checkPythonHealth(installPath, version)
    
    -- Report health status and fix if needed
    local needsRecheck = false

    if healthReport.overallHealth == "healthy" then
        print("Python " .. version .. " is healthy and ready to use")
    elseif healthReport.overallHealth == "warning" then
        print("Python " .. version .. " has minor issues:")
        for _, problem in ipairs(healthReport.problemsFound) do
            print("  - " .. problem)
        end
        print("Attempting to fix issues...")

        -- Fix shebang issues
        local success, fixedCount = fixShebangForVersion(installPath, version)
        if success and fixedCount > 0 then
            print("Fixed " .. fixedCount .. " shebang issues")
            needsRecheck = true
        end
    elseif healthReport.overallHealth == "critical" then
        print("Python " .. version .. " has critical issues:")
        for _, problem in ipairs(healthReport.problemsFound) do
            print("  - " .. problem)
        end

        if #healthReport.problemsFound > 0 then
            print("Attempting to fix critical issues...")
            local success, fixedCount = fixShebangForVersion(installPath, version)
            if success and fixedCount > 0 then
                print("Fixed " .. fixedCount .. " critical issues")
                needsRecheck = true
            else
                print("Some issues may require manual intervention")
            end
        end
    end

    -- Only perform final health check if we made fixes
    if needsRecheck then
        print("Verifying fixes...")
        local finalHealthReport = checkPythonHealth(installPath, version)
        if finalHealthReport.overallHealth == "healthy" then
            print("Python " .. version .. " is now ready for use")
        else
            print("Python " .. version .. " still has some issues but should be usable")
            if #finalHealthReport.problemsFound > 0 then
                print("Remaining issues:")
                for _, problem in ipairs(finalHealthReport.problemsFound) do
                    print("  - " .. problem)
                end
            end
        end
    end

    -- Return the version in the correct format
    return {
        version = version
    }
end
