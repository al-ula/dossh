#!/usr/bin/env luajit

local function colorText(text, color)
    local colors = {
        red = "\27[31m",
        green = "\27[32m",
        blue = "\27[34m",
        yellow = "\27[33m",
        teal = "\27[36m",
        normal = "\27[0m"
    }
    return colors[color] .. text .. colors.normal
end

local function executeCommand(command)
    local handle = io.popen(command)
    if handle then
        local result = handle:read("*a")
        handle:close()
        return result:gsub("%s+$", "") -- Remove trailing whitespace
    else
        error("Failed to execute command: " .. command)
    end
end

local function splitString(str, delimiter)
    local result = {}
    for match in (str .. delimiter):gmatch("(.-)" .. delimiter) do
        table.insert(result, match)
    end
    return result
end

local function getCurrentIPAddress()
    return executeCommand("curl -s ifconfig.me")
end

local function getFirewall()
    local firewallListRaw = executeCommand("doctl compute firewall list --format ID,Name --no-header")
    local firewallList = splitString(firewallListRaw, "\n")
    if #firewallList == 0 then
        error("No firewalls found.")
    end
    local firstFirewall = firewallList[1]
    local firewallFields = splitString(firstFirewall, "    ")
    return firewallFields[1], firewallFields[2]
end

local function getCurrentFirewallRules(id)
    local currentInboundRaw = executeCommand("doctl compute firewall get " .. id .. " --format InboundRules --no-header")
    local currentInbound = splitString(currentInboundRaw, " ")
    local currentOutboundRaw = executeCommand("doctl compute firewall get " ..
        id .. " --format OutboundRules --no-header")
    local currentOutbound = splitString(currentOutboundRaw, " ")
    return currentInbound, currentOutbound
end

--

local currentIP = getCurrentIPAddress()

print("The current IP address is: " .. colorText(currentIP, "teal") .. "\n")

local firewallId, firewallName = getFirewall()

print("Updating firewall " .. colorText(firewallName, "yellow") .. " to change allowed inbound SSH to current IP\n")

local currentInbound, currentOutbound = getCurrentFirewallRules(firewallId)
local isSSHRulePresent = false
local sshRuleIndex = nil

print("Current inbound rules:")
for i, rule in ipairs(currentInbound) do
    print(" " .. rule)
    if rule:match("^protocol:tcp,ports:22") then
        isSSHRulePresent = true
    end
end
print()

print("Current outbound rules:")
for _, rule in ipairs(currentOutbound) do
    print(" " .. rule)
end
print()

local newInboundRuleset = {}

if isSSHRulePresent then
    print("Replacing ssh rule...\n")
    for i, rule in ipairs(currentInbound) do
        if rule:match("^protocol:tcp,ports:22") then
            table.insert(newInboundRuleset, "protocol:tcp,ports:22,address:" .. currentIP)
        else
            table.insert(newInboundRuleset, rule)
        end
    end
else
    print("Adding ssh rule...\n")
    table.insert(newInboundRuleset, "protocol:tcp,ports:22,address:" .. currentIP)
    for _, rule in ipairs(currentInbound) do
        table.insert(newInboundRuleset, rule)
    end
end

print("New inbound rules:")
for _, rule in ipairs(newInboundRuleset) do
    print(" " .. rule)
end
print()
local inboundRules = table.concat(newInboundRuleset, " ")
local outboundRules = table.concat(currentOutbound, " ")

local response = executeCommand("doctl compute firewall update " ..
    firewallId ..
    " --name " ..
    firewallName ..
    " --inbound-rules '" ..
    inboundRules .. "' --outbound-rules '" .. outboundRules .. "' --format Name,Status --no-header")

local responseFields = splitString(response, "    ")
local responseStatus = responseFields[2]

for _, responseField in ipairs(responseFields) do
    print(responseField)
end

local statusColor = responseStatus == "succeeded" and "green" or "red"

print("Updating " .. colorText(responseFields[1], "yellow") .. " is " .. colorText(responseStatus, statusColor))
