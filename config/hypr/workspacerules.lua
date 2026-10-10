hl.workspace_rule({ workspace = "1", monitor = "DP-1", default = true, decorate = true })
for i = 2, 9 do
    hl.workspace_rule({ workspace = tostring(i), monitor = "DP-1" })
end
hl.workspace_rule({ workspace = "10", monitor = "DP-2", default = true })

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
