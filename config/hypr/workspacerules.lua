-- Which workspaces belong to which monitor is set per machine in Machine
-- Settings (config/hypr/local.lua)

local appWorkspaces = {
    { class = "^(jetbrains-idea)$",     workspace = "3 silent" },
    { class = "^(jetbrains-goland)$",   workspace = "3 silent" },
    { class = "^(steam)$",              workspace = "4 silent" },
    { class = "^(steam_.*)$",           workspace = "4 silent" },
    { class = "^(.*\\.exe)$",           workspace = "4 silent" },
    { class = "^(net\\.lutris\\.Lutris)$", workspace = "4 silent" },
    { class = "org.mozilla.Thunderbird", workspace = "7 silent" },
}
for _, rule in ipairs(appWorkspaces) do
    hl.window_rule({ match = { class = rule.class }, workspace = rule.workspace })
end
