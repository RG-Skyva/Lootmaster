local ADDON_FOLDER = ...
local ADDON_VERSION = (GetAddOnMetadata and GetAddOnMetadata(ADDON_FOLDER or "SkyvasLootmaster", "Version")) or "1.0"
local ADDON_MESSAGE_PREFIX = "SkyvasLM"

SkyvasLootmasterDB = SkyvasLootmasterDB or {}

local SLM = CreateFrame("Frame", "SkyvasLootmasterCore")
SLM.items = {}
SLM.currentIndex = 0
SLM.activeItem = nil
SLM.rows = {}
SLM.loaded = false
SLM.recentWins = {}
SLM.pendingTradeItems = {}
SLM.pendingTradePlayerName = nil
SLM.shortcutHookedButtons = {}
SLM.currentView = "loot"
SLM.wishlistRows = {}
SLM.linkHooked = false

local UpdateDialog
local UpdateWishlistView
local UpdateMasterLootSettingsView
local CreateButton
local SmallHeaderFont
local HandleMasterLootOpened
local WIN_TRADE_WINDOW_SECONDS = 300
local ROLL_WINDOW_SECONDS = 300
local SHARD_ITEM_IDS = {
    [45038] = true,
    [50274] = true,
}

local GROUP_ORDER = {
    { key = "UlduarMount", label = "Ulduar Mount", range = "50%-100%" },
    { key = "FR", label = "Fokus Roll", range = "101-200" },
    { key = "Main", label = "Main", range = "1-100" },
    { key = "Sec", label = "Second", range = "1-99" },
}

local GROUP_LABEL_BY_MAX = {
    [99] = "Sec",
    [100] = "Main",
}

local function ExtractItemLink(message)
    if not message then
        return nil
    end

    return string.match(message, "(|c%x+|Hitem:[^|]+|h%[[^%]]+%]|h|r)")
end

local function ExtractSingleItemLink(message)
    local itemLink
    local itemCount = 0

    if not message then
        return nil
    end

    for link in string.gmatch(message, "(|c%x+|Hitem:[^|]+|h%[[^%]]+%]|h|r)") do
        itemCount = itemCount + 1
        itemLink = link
        if itemCount > 1 then
            return nil
        end
    end

    if itemCount == 1 then
        return itemLink
    end

    return nil
end

local function ExtractItemName(itemLink)
    return string.match(itemLink or "", "%[([^%]]+)%]") or itemLink or "Unbekanntes Item"
end

local function ExtractItemId(itemLink)
    return tonumber(string.match(itemLink or "", "item:(%d+)"))
end

local function GetBaseItemLink(itemLink)
    local itemId = ExtractItemId(itemLink)
    if not itemId then
        return itemLink
    end

    local _, baseItemLink = GetItemInfo(itemId)
    if baseItemLink then
        return baseItemLink
    end

    local color = string.match(itemLink or "", "^(|c%x%x%x%x%x%x%x%x)") or "|cffffffff"
    local itemName = ExtractItemName(itemLink)
    return color .. "|Hitem:" .. itemId .. ":0:0:0:0:0:0:0:0|h[" .. itemName .. "]|h|r"
end

local function IsBindOnEquip(itemLink)
    if not itemLink then
        return false
    end

    if not SLM.scanTooltip then
        SLM.scanTooltip = CreateFrame("GameTooltip", "SkyvasLootmasterScanTooltip", UIParent, "GameTooltipTemplate")
        SLM.scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end

    SLM.scanTooltip:ClearLines()
    SLM.scanTooltip:SetHyperlink(itemLink)

    for index = 1, SLM.scanTooltip:NumLines() do
        local line = _G["SkyvasLootmasterScanTooltipTextLeft" .. index]
        local text = line and line:GetText()
        if text == ITEM_BIND_ON_EQUIP or text == "Wird beim Anlegen gebunden" or text == "Binds when equipped" then
            return true
        end
    end

    return false
end

local function GetItemStatText(itemLink)
    if not itemLink then
        return ""
    end

    if not SLM.scanTooltip then
        SLM.scanTooltip = CreateFrame("GameTooltip", "SkyvasLootmasterScanTooltip", UIParent, "GameTooltipTemplate")
        SLM.scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end

    SLM.scanTooltip:ClearLines()
    SLM.scanTooltip:SetHyperlink(itemLink)

    local stats = {
        { label = "Stärke", patterns = { "Stärke", "Strength" } },
        { label = "Bewe", patterns = { "Beweglichkeit", "Agility" } },
        { label = "ZM", patterns = { "Zaubermacht", "Spell Power" }, requireEquipLine = true },
        { label = "Tempo", patterns = { "Tempo", "Haste" }, requireEquipLine = true },
        { label = "Wille", patterns = { "Willenskraft", "Spirit" }, requireEquipLine = true },
        { label = "Hit", patterns = { "Erhöht Trefferwertung", "Increases hit rating", "Increases your hit rating" }, requireEquipLine = true },
        { label = "Krit", patterns = { "kritische Trefferwertung", "Critical Strike Rating", "Crit Rating" }, requireEquipLine = true },
        { label = "ARP", patterns = { "Rüstungsdurchschlagwertung", "Armor Penetration" }, requireEquipLine = true },
        { label = "WK", patterns = { "Waffenkundewertung", "Expertise Rating" }, requireEquipLine = true },
        { label = "mp5", patterns = { "alle 5 Sek", "per 5 sec", "per 5 seconds", "MP5" }, requireEquipLine = true },
        { label = "Def", patterns = { "Verteidigungswertung", "Defense Rating" }, requireEquipLine = true },
        { label = "Dodge", patterns = { "Ausweichwertung", "Dodge Rating" }, requireEquipLine = true },
        { label = "Parry", patterns = { "Parierwertung", "Parry Rating" }, requireEquipLine = true },
    }
    local found = {}

    for index = 1, SLM.scanTooltip:NumLines() do
        local line = _G["SkyvasLootmasterScanTooltipTextLeft" .. index]
        local text = line and line:GetText()
        if text then
            local isEquipLine = string.find(text, "Anlegen")
            for statIndex, stat in ipairs(stats) do
                if not found[statIndex] and (not stat.requireEquipLine or isEquipLine) then
                    for _, pattern in ipairs(stat.patterns) do
                        if string.find(text, pattern) then
                            found[statIndex] = true
                            break
                        end
                    end
                end
            end
        end
    end

    local labels = {}
    for statIndex, stat in ipairs(stats) do
        if found[statIndex] then
            table.insert(labels, stat.label)
        end
    end

    return table.concat(labels, "/")
end

local function GetItemEquipLocationText(itemLink)
    local _, _, _, _, _, _, _, _, equipLocation = GetItemInfo(itemLink)
    local locations = {
        INVTYPE_HEAD = "Kopf",
        INVTYPE_NECK = "Hals",
        INVTYPE_SHOULDER = "Schulter",
        INVTYPE_CLOAK = "Umhang",
        INVTYPE_CHEST = "Brust",
        INVTYPE_ROBE = "Brust",
        INVTYPE_WRIST = "Handgelenk",
        INVTYPE_HAND = "Hand",
        INVTYPE_WAIST = "Taille",
        INVTYPE_LEGS = "Beine",
        INVTYPE_FEET = "Füße",
        INVTYPE_FINGER = "Ring",
        INVTYPE_TRINKET = "Trinket",
        INVTYPE_WEAPON = "Waffe",
        INVTYPE_2HWEAPON = "2H",
        INVTYPE_WEAPONMAINHAND = "Mainhand",
        INVTYPE_WEAPONOFFHAND = "Offhand",
        INVTYPE_HOLDABLE = "Offhand",
        INVTYPE_SHIELD = "Schild",
        INVTYPE_RANGED = "Fernkampf",
        INVTYPE_RANGEDRIGHT = "Fernkampf",
        INVTYPE_THROWN = "Wurfwaffe",
        INVTYPE_RELIC = "Relikt",
    }

    return locations[equipLocation] or ""
end

local function GetItemArmorTypeText(itemLink)
    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(itemLink)
    if itemType ~= ARMOR and itemType ~= "Armor" and itemType ~= "Rüstung" then
        return ""
    end

    if itemSubType == "Plate" or itemSubType == "Platte" then
        return "Platte"
    elseif itemSubType == "Mail" or itemSubType == "Schwere Rüstung" then
        return "Rüssi"
    elseif itemSubType == "Leather" or itemSubType == "Leder" then
        return "Leder"
    elseif itemSubType == "Cloth" or itemSubType == "Stoff" then
        return "Stoff"
    end

    if not SLM.scanTooltip then
        SLM.scanTooltip = CreateFrame("GameTooltip", "SkyvasLootmasterScanTooltip", UIParent, "GameTooltipTemplate")
        SLM.scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end

    SLM.scanTooltip:ClearLines()
    SLM.scanTooltip:SetHyperlink(itemLink)

    for index = 1, SLM.scanTooltip:NumLines() do
        local line = _G["SkyvasLootmasterScanTooltipTextLeft" .. index]
        local text = line and line:GetText()
        if text then
            if string.find(text, "Platte") or string.find(text, "Plate") then
                return "Platte"
            elseif string.find(text, "Schwere Rüstung") or string.find(text, "Mail") then
                return "Rüssi"
            elseif string.find(text, "Leder") or string.find(text, "Leather") then
                return "Leder"
            elseif string.find(text, "Stoff") or string.find(text, "Cloth") then
                return "Stoff"
            end
        end
    end

    return ""
end

local function GetItemWeaponTypeText(itemLink)
    local _, _, _, _, _, itemType, itemSubType = GetItemInfo(itemLink)
    if itemType ~= WEAPON and itemType ~= "Weapon" and itemType ~= "Waffe" then
        return ""
    end

    itemSubType = itemSubType or ""
    local normalizedItemSubType = string.lower(itemSubType)
    if string.find(normalizedItemSubType, "dolch") or string.find(normalizedItemSubType, "dagger") then
        return "Dolch"
    elseif string.find(normalizedItemSubType, "schwert") or string.find(normalizedItemSubType, "schwerter") or string.find(normalizedItemSubType, "sword") then
        return "Schwert"
    elseif string.find(normalizedItemSubType, "axt") or string.find(normalizedItemSubType, "äxte") or string.find(normalizedItemSubType, "axe") then
        return "Axt"
    elseif string.find(normalizedItemSubType, "streitkolben") or string.find(normalizedItemSubType, "mace") then
        return "Streitkolben"
    elseif string.find(normalizedItemSubType, "stab") or string.find(normalizedItemSubType, "staff") then
        return "Stab"
    elseif string.find(normalizedItemSubType, "stangenwaffe") or string.find(normalizedItemSubType, "polearm") then
        return "Stangenwaffe"
    elseif string.find(normalizedItemSubType, "faustwaffe") or string.find(normalizedItemSubType, "fist") then
        return "Faustwaffe"
    elseif string.find(normalizedItemSubType, "bogen") or string.find(normalizedItemSubType, "bow") then
        return "Bogen"
    elseif string.find(normalizedItemSubType, "armbrust") or string.find(normalizedItemSubType, "crossbow") then
        return "Armbrust"
    elseif string.find(normalizedItemSubType, "schusswaffe") or string.find(normalizedItemSubType, "gun") then
        return "Schusswaffe"
    elseif string.find(normalizedItemSubType, "zauberstab") or string.find(normalizedItemSubType, "wand") then
        return "Zauberstab"
    elseif string.find(normalizedItemSubType, "wurfwaffe") or string.find(normalizedItemSubType, "thrown") then
        return "Wurfwaffe"
    elseif string.find(normalizedItemSubType, "angel") or string.find(normalizedItemSubType, "fishing") then
        return "Angel"
    end

    return itemSubType
end

local function IsRecipeLikeItem(itemLink)
    local itemName = ExtractItemName(itemLink)
    if string.find(itemName, "^Muster:") or string.find(itemName, "^Pläne:") or string.find(itemName, "^Rezept:") then
        return true
    end
    if string.find(itemName, "^Pattern:") or string.find(itemName, "^Plans:") or string.find(itemName, "^Recipe:") then
        return true
    end

    if not SLM.scanTooltip then
        SLM.scanTooltip = CreateFrame("GameTooltip", "SkyvasLootmasterScanTooltip", UIParent, "GameTooltipTemplate")
        SLM.scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end

    SLM.scanTooltip:ClearLines()
    SLM.scanTooltip:SetHyperlink(itemLink)

    for index = 1, SLM.scanTooltip:NumLines() do
        local line = _G["SkyvasLootmasterScanTooltipTextLeft" .. index]
        local text = line and line:GetText()
        if text and (
            string.find(text, "Muster:")
            or string.find(text, "Pläne:")
            or string.find(text, "Rezept:")
            or string.find(text, "Pattern:")
            or string.find(text, "Plans:")
            or string.find(text, "Recipe:")
        ) then
            return true
        end
    end

    return false
end

local function IsSoulboundOrBindOnPickup(itemLink)
    if not itemLink then
        return false
    end

    if not SLM.scanTooltip then
        SLM.scanTooltip = CreateFrame("GameTooltip", "SkyvasLootmasterScanTooltip", UIParent, "GameTooltipTemplate")
        SLM.scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end

    SLM.scanTooltip:ClearLines()
    SLM.scanTooltip:SetHyperlink(itemLink)

    for index = 1, SLM.scanTooltip:NumLines() do
        local line = _G["SkyvasLootmasterScanTooltipTextLeft" .. index]
        local text = line and line:GetText()
        if text and (
            text == ITEM_BIND_ON_PICKUP
            or text == ITEM_SOULBOUND
            or text == ITEM_BIND_QUEST
            or text == "Wird beim Aufheben gebunden"
            or text == "Seelengebunden"
            or text == "Binds when picked up"
            or text == "Soulbound"
        ) then
            return true
        end
    end

    return false
end

local function IsEpicNotSoulbound(itemLink)
    local _, _, quality = GetItemInfo(itemLink)
    local isEpic = quality == 4 or string.match(itemLink or "", "^|cffa335ee")
    return isEpic and not IsSoulboundOrBindOnPickup(itemLink)
end

local function GetTimestamp()
    return date("%H:%M:%S")
end

local function ParseSystemRoll(message)
    if not message then
        return nil
    end

    local name, roll, minRoll, maxRoll = string.match(message, "^([^%s]+) rolls (%d+) %((%d+)%-(%d+)%)")
    if not name then
        name, roll, minRoll, maxRoll = string.match(message, "^([^%s]+) würfelt. Ergebnis: (%d+) %((%d+)%-(%d+)%)")
    end
    if not name then
        name, roll, minRoll, maxRoll = string.match(message, "^([^%s]+) würfelt (%d+) %((%d+)%-(%d+)%)")
    end

    if not name then
        return nil
    end

    roll = tonumber(roll)
    minRoll = tonumber(minRoll)
    maxRoll = tonumber(maxRoll)

    if minRoll == 101 and maxRoll == 200 then
        return name, roll, "FR", maxRoll
    end

    if minRoll * 2 == maxRoll then
        return name, roll, "UlduarMount", maxRoll
    end

    if minRoll == 1 and GROUP_LABEL_BY_MAX[maxRoll] then
        return name, roll, GROUP_LABEL_BY_MAX[maxRoll], maxRoll
    end

    return nil
end

local function SortRolls(a, b)
    if a.roll == b.roll then
        return a.name < b.name
    end

    return a.roll > b.roll
end

local function NormalizePlayerName(name)
    return string.match(name or "", "^([^-]+)") or name
end

local function GetPlayerKey(name)
    return string.lower(NormalizePlayerName(name or ""))
end

local function IsOwnMessage(sender)
    if not sender then
        return false
    end

    return GetPlayerKey(sender) == GetPlayerKey(UnitName("player"))
end

local function FindPlayerClass(name)
    local normalizedName = NormalizePlayerName(name)

    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for index = 1, GetNumRaidMembers() do
            local raidName, _, _, _, _, classFile = GetRaidRosterInfo(index)
            if NormalizePlayerName(raidName) == normalizedName then
                return classFile
            end
        end
    end

    if GetNumPartyMembers and GetNumPartyMembers() > 0 then
        for index = 1, GetNumPartyMembers() do
            local unit = "party" .. index
            local partyName = UnitName(unit)
            if NormalizePlayerName(partyName) == normalizedName then
                local _, classFile = UnitClass(unit)
                return classFile
            end
        end
    end

    if NormalizePlayerName(UnitName("player")) == normalizedName then
        local _, classFile = UnitClass("player")
        return classFile
    end

    return nil
end

local function ColorizeName(name, classFile)
    local color = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if not color then
        return name
    end

    local red = math.floor((color.r or 1) * 255)
    local green = math.floor((color.g or 1) * 255)
    local blue = math.floor((color.b or 1) * 255)
    return string.format("|cff%02x%02x%02x%s|r", red, green, blue, name)
end

local function GetCurrentItem()
    if SLM.currentIndex <= 0 then
        return nil
    end

    return SLM.items[SLM.currentIndex]
end

local function GetLatestItem()
    local itemCount = table.getn(SLM.items)
    if itemCount == 0 then
        return nil
    end

    return SLM.items[itemCount]
end

local function SaveSession()
    SkyvasLootmasterDB.items = SLM.items
    SkyvasLootmasterDB.currentIndex = SLM.currentIndex
    SkyvasLootmasterDB.recentWins = SLM.recentWins
    SkyvasLootmasterDB.wishlistByCharacter = SkyvasLootmasterDB.wishlistByCharacter or {}
end

local function GetCharacterKey()
    local playerName = UnitName("player") or "Unknown"
    local realmName = GetRealmName and GetRealmName() or "Realm"
    return realmName .. " - " .. playerName
end

local function GetWishlist()
    SkyvasLootmasterDB.wishlistByCharacter = SkyvasLootmasterDB.wishlistByCharacter or {}
    local characterKey = GetCharacterKey()
    SkyvasLootmasterDB.wishlistByCharacter[characterKey] = SkyvasLootmasterDB.wishlistByCharacter[characterKey] or {}
    return SkyvasLootmasterDB.wishlistByCharacter[characterKey]
end

local function GetWishlistSettings()
    SkyvasLootmasterDB.wishlistSettingsByCharacter = SkyvasLootmasterDB.wishlistSettingsByCharacter or {}
    local characterKey = GetCharacterKey()
    SkyvasLootmasterDB.wishlistSettingsByCharacter[characterKey] = SkyvasLootmasterDB.wishlistSettingsByCharacter[characterKey] or {
        soundEnabled = true,
    }

    if SkyvasLootmasterDB.wishlistSettingsByCharacter[characterKey].soundEnabled == nil then
        SkyvasLootmasterDB.wishlistSettingsByCharacter[characterKey].soundEnabled = true
    end
    if SkyvasLootmasterDB.wishlistSettingsByCharacter[characterKey].boeEnabled == nil then
        SkyvasLootmasterDB.wishlistSettingsByCharacter[characterKey].boeEnabled = false
    end
    if SkyvasLootmasterDB.wishlistSettingsByCharacter[characterKey].onlyWishlistPopup == nil then
        SkyvasLootmasterDB.wishlistSettingsByCharacter[characterKey].onlyWishlistPopup = false
    end

    return SkyvasLootmasterDB.wishlistSettingsByCharacter[characterKey]
end

local function GetMasterLootSettings()
    SkyvasLootmasterDB.masterLootSettings = SkyvasLootmasterDB.masterLootSettings or {}
    local settings = SkyvasLootmasterDB.masterLootSettings

    if settings.enabled == nil then
        settings.enabled = false
    end
    if settings.locked == nil then
        settings.locked = false
    end
    if settings.assistantWhisperEnabled == nil then
        settings.assistantWhisperEnabled = false
    end
    if settings.itemStatsEnabled == nil then
        settings.itemStatsEnabled = false
    end
    settings.lootTarget = settings.lootTarget or ""
    settings.shardTarget = settings.shardTarget or ""
    settings.autoInviteKeyword = settings.autoInviteKeyword or ""

    return settings
end

local function SaveMasterLootSettings()
    local settings = GetMasterLootSettings()
    if SLM.masterLootEnabledButton then
        settings.enabled = SLM.masterLootEnabledButton:GetChecked() and true or false
    end
    if SLM.masterLootLockButton then
        settings.locked = SLM.masterLootLockButton:GetChecked() and true or false
    end
    if SLM.assistantWhisperButton then
        settings.assistantWhisperEnabled = SLM.assistantWhisperButton:GetChecked() and true or false
    end
    if SLM.itemStatsButton then
        settings.itemStatsEnabled = SLM.itemStatsButton:GetChecked() and true or false
    end
    if SLM.masterLootTargetInput then
        settings.lootTarget = SLM.masterLootTargetInput:GetText() or ""
    end
    if SLM.masterLootShardInput then
        settings.shardTarget = SLM.masterLootShardInput:GetText() or ""
    end
    if SLM.autoInviteInput then
        settings.autoInviteKeyword = SLM.autoInviteInput:GetText() or ""
    end
    SaveSession()
end

local function IsInRaidGroup()
    return GetNumRaidMembers and GetNumRaidMembers() > 0
end

local function PrintVersionMessage(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffSLM:|r " .. message)
    end
end

local function GetShortPlayerName(playerName)
    return string.match(playerName or "", "^[^-]+") or playerName or "Unbekannt"
end

local function RegisterVersionMessagePrefix()
    if RegisterAddonMessagePrefix then
        RegisterAddonMessagePrefix(ADDON_MESSAGE_PREFIX)
    end
end

local function RequestRaidVersions()
    if not IsInRaidGroup() then
        PrintVersionMessage("Versionsabfrage nur im Raid möglich.")
        return
    end

    RegisterVersionMessagePrefix()
    SLM.versionRequestActive = true
    PrintVersionMessage("Versionsabfrage gesendet. Antworten:")
    PrintVersionMessage(GetShortPlayerName(UnitName("player")) .. " - " .. ADDON_VERSION)
    SendAddonMessage(ADDON_MESSAGE_PREFIX, "VERSION_REQUEST", "RAID")
end

local function HandleVersionAddonMessage(prefix, addonMessage, addonChannel, addonSender)
    if prefix ~= ADDON_MESSAGE_PREFIX or not addonMessage then
        return
    end

    local playerName = GetShortPlayerName(UnitName("player"))
    local senderName = GetShortPlayerName(addonSender)
    if senderName == playerName then
        return
    end

    if addonMessage == "VERSION_REQUEST" then
        if addonSender and addonSender ~= "" then
            SendAddonMessage(ADDON_MESSAGE_PREFIX, "VERSION_RESPONSE:" .. ADDON_VERSION, "WHISPER", addonSender)
        end
        return
    end

    local version = string.match(addonMessage, "^VERSION_RESPONSE:(.+)$")
    if version and SLM.versionRequestActive then
        PrintVersionMessage(senderName .. " - " .. version)
    end
end

local function ClearMasterLootTargets()
    local settings = GetMasterLootSettings()
    settings.lootTarget = ""
    settings.shardTarget = ""

    if SLM.masterLootTargetInput then
        SLM.masterLootTargetInput:SetText("")
    end
    if SLM.masterLootShardInput then
        SLM.masterLootShardInput:SetText("")
    end

    SaveSession()
end

local function HandleRaidRosterUpdate()
    local isInRaid = IsInRaidGroup()
    if isInRaid and not SLM.wasInRaidGroup then
        ClearMasterLootTargets()
    end

    SLM.wasInRaidGroup = isInRaid and true or false
end

local function TrimText(text)
    return string.gsub(text or "", "^%s*(.-)%s*$", "%1")
end

local function NormalizePlayerName(name)
    name = TrimText(name)
    name = string.gsub(name, "%-.+$", "")
    return string.lower(name)
end

local function IsWishlistSoundEnabled()
    return GetWishlistSettings().soundEnabled
end

local function SetWishlistSoundEnabled(enabled)
    GetWishlistSettings().soundEnabled = enabled and true or false
    SaveSession()
end

local function IsWishlistBoeEnabled()
    return GetWishlistSettings().boeEnabled
end

local function SetWishlistBoeEnabled(enabled)
    GetWishlistSettings().boeEnabled = enabled and true or false
    SaveSession()
end

local function IsOnlyWishlistPopupEnabled()
    return GetWishlistSettings().onlyWishlistPopup
end

local function SetOnlyWishlistPopupEnabled(enabled)
    GetWishlistSettings().onlyWishlistPopup = enabled and true or false
    SaveSession()
end

local function UpdateWishlistSoundButton()
    if not SLM.wishlistSoundButton then
        return
    end

    SLM.wishlistSoundButton:SetChecked(IsWishlistSoundEnabled())
end

local function UpdateWishlistBoeButton()
    if not SLM.wishlistBoeButton then
        return
    end

    SLM.wishlistBoeButton:SetChecked(IsWishlistBoeEnabled())
end

local function UpdateOnlyWishlistPopupButton()
    if not SLM.onlyWishlistPopupButton then
        return
    end

    SLM.onlyWishlistPopupButton:SetChecked(IsOnlyWishlistPopupEnabled())
end

local function PlayWishlistSound()
    if not IsWishlistSoundEnabled() then
        return
    end

    local soundPath = "Interface\\AddOns\\" .. (ADDON_FOLDER or "SkyvasLootmaster") .. "\\DerSchatz.mp3"
    if not PlaySoundFile(soundPath, "Master") then
        PlaySoundFile(soundPath)
    end
end

local function AddWishlistItem(itemText)
    if not itemText or itemText == "" then
        return
    end

    local newItemId = ExtractItemId(itemText)
    for _, wishlistEntry in ipairs(GetWishlist()) do
        local existingItemId = ExtractItemId(wishlistEntry)
        if newItemId and existingItemId == newItemId then
            return
        end

        if not newItemId and not existingItemId and wishlistEntry == itemText then
            return
        end
    end

    table.insert(GetWishlist(), itemText)
    SaveSession()
end

local function InstallWishlistLinkHook()
    if SLM.linkHooked or not hooksecurefunc or not ChatEdit_InsertLink then
        return
    end

    hooksecurefunc("ChatEdit_InsertLink", function(link)
        if SLM.currentView == "wishlist" and SLM.wishlistInput and SLM.wishlistInput:HasFocus() and link then
            SLM.wishlistInput:Insert(link)
        end
    end)

    SLM.linkHooked = true
end

local function AddWishlistItemLink(itemLink)
    if not itemLink then
        return
    end

    AddWishlistItem(itemLink)
    if SLM.currentView == "wishlist" then
        UpdateWishlistView()
    end
end

local function ResetWishlist()
    SkyvasLootmasterDB.wishlistByCharacter = SkyvasLootmasterDB.wishlistByCharacter or {}
    SkyvasLootmasterDB.wishlistByCharacter[GetCharacterKey()] = {}
    SaveSession()
end

local function ConfirmResetWishlist()
    StaticPopupDialogs.SKYVAS_LOOTMASTER_RESET_WISHLIST = {
        text = "Wishlist wirklich zurücksetzen?",
        button1 = YES,
        button2 = NO,
        OnAccept = function()
            ResetWishlist()
            UpdateWishlistView()
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
    StaticPopup_Show("SKYVAS_LOOTMASTER_RESET_WISHLIST")
end

local function WishlistContainsItem(itemLink)
    local itemId = ExtractItemId(itemLink)
    if not itemId then
        return false
    end

    for _, wishlistEntry in ipairs(GetWishlist()) do
        if ExtractItemId(wishlistEntry) == itemId then
            return true
        end
    end

    return false
end

local function CreateWishlistAlert()
    if SLM.alertFrame then
        return
    end

    local frame = CreateFrame("Frame", "SkyvasLootmasterWishlistAlert", UIParent)
    frame:SetAllPoints(UIParent)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:Hide()

    local size = 86
    frame.top = frame:CreateTexture(nil, "OVERLAY")
    frame.top:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    frame.top:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    frame.top:SetHeight(size)
    frame.top:SetBlendMode("ADD")

    frame.bottom = frame:CreateTexture(nil, "OVERLAY")
    frame.bottom:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    frame.bottom:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
    frame.bottom:SetHeight(size)
    frame.bottom:SetBlendMode("ADD")

    frame.left = frame:CreateTexture(nil, "OVERLAY")
    frame.left:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    frame.left:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    frame.left:SetWidth(size)
    frame.left:SetBlendMode("ADD")

    frame.right = frame:CreateTexture(nil, "OVERLAY")
    frame.right:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 0, 0)
    frame.right:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, 0)
    frame.right:SetWidth(size)
    frame.right:SetBlendMode("ADD")

    frame.textures = {
        { texture = frame.top, direction = "VERTICAL", outerFirst = false },
        { texture = frame.bottom, direction = "VERTICAL", outerFirst = true },
        { texture = frame.left, direction = "HORIZONTAL", outerFirst = true },
        { texture = frame.right, direction = "HORIZONTAL", outerFirst = false },
    }
    SLM.alertFrame = frame
end

local function SetWishlistAlertTexture(edge, alpha)
    local texture = edge.texture
    local red, green, blue = 0.05, 1, 0.1

    texture:SetTexture(red, green, blue)
    texture:SetAlpha(1)

    if texture.SetGradientAlpha then
        if edge.outerFirst then
            texture:SetGradientAlpha(edge.direction, red, green, blue, alpha, red, green, blue, 0)
        else
            texture:SetGradientAlpha(edge.direction, red, green, blue, 0, red, green, blue, alpha)
        end
    else
        texture:SetAlpha(alpha * 0.45)
    end
end

local function ShowWishlistAlert()
    CreateWishlistAlert()

    local frame = SLM.alertFrame
    frame.elapsed = 0
    frame.duration = 5
    frame:Show()
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= self.duration then
            self:Hide()
            self:SetScript("OnUpdate", nil)
            return
        end

        local alpha = 0.35 + (math.sin(self.elapsed * 9) + 1) * 0.25
        for _, edge in ipairs(self.textures) do
            SetWishlistAlertTexture(edge, alpha)
        end
    end)
end

local function NormalizeRecentWins()
    for playerKey, wins in pairs(SLM.recentWins) do
        if wins.itemId then
            SLM.recentWins[playerKey] = { wins }
        end
    end
end

local function MigrateItem(item)
    item.rolls = item.rolls or {
        UlduarMount = {},
        FR = {},
        Main = {},
        Sec = {},
    }
    item.rollCountByPlayer = item.rollCountByPlayer or {}
    item.nextRollId = item.nextRollId or 1

    for _, group in ipairs(GROUP_ORDER) do
        item.rolls[group.key] = item.rolls[group.key] or {}
        for _, rollInfo in ipairs(item.rolls[group.key]) do
            rollInfo.groupKey = rollInfo.groupKey or group.key
            if not rollInfo.rollId then
                rollInfo.rollId = item.nextRollId
                item.nextRollId = item.nextRollId + 1
            elseif rollInfo.rollId >= item.nextRollId then
                item.nextRollId = rollInfo.rollId + 1
            end
            if not rollInfo.classFile then
                rollInfo.classFile = FindPlayerClass(rollInfo.name)
            end
            rollInfo.timestamp = rollInfo.timestamp or "--:--:--"
            item.rollCountByPlayer[rollInfo.name] = math.max(item.rollCountByPlayer[rollInfo.name] or 0, rollInfo.rollCount or 1)
        end
    end

    item.startedAt = item.startedAt or time()
end

local function RestoreSession()
    if SLM.loaded then
        return
    end

    SLM.items = SkyvasLootmasterDB.items or {}
    SLM.currentIndex = tonumber(SkyvasLootmasterDB.currentIndex) or table.getn(SLM.items)
    SLM.recentWins = SkyvasLootmasterDB.recentWins or {}
    NormalizeRecentWins()

    for _, item in ipairs(SLM.items) do
        MigrateItem(item)
    end

    if SLM.currentIndex < 1 or SLM.currentIndex > table.getn(SLM.items) then
        SLM.currentIndex = table.getn(SLM.items)
    end

    SLM.activeItem = GetCurrentItem()
    SLM.loaded = true
end

local function ResetSession()
    SLM.items = {}
    SLM.currentIndex = 0
    SLM.activeItem = nil
    SLM.recentWins = {}
    SkyvasLootmasterDB.items = {}
    SkyvasLootmasterDB.currentIndex = 0
    SkyvasLootmasterDB.recentWins = {}
    UpdateDialog()
end

local function ConfirmResetSession()
    StaticPopupDialogs.SKYVAS_LOOTMASTER_RESET_SESSION = {
        text = "Session wirklich zurücksetzen?",
        button1 = YES,
        button2 = NO,
        OnAccept = function()
            ResetSession()
            if SLM.statusText then
                SLM.statusText:SetText("Session zurückgesetzt.")
            end
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
    StaticPopup_Show("SKYVAS_LOOTMASTER_RESET_SESSION")
end

local function GetMasterLootCandidateLegacy(index)
    if not GetMasterLootCandidate or not index then
        return nil
    end

    local ok, name = pcall(GetMasterLootCandidate, index)
    if ok then
        return name
    end

    return nil
end

local function GetMasterLootCandidates(slot)
    local candidates = {}
    local seenNames = {}

    local function addCandidate(index, name, isLootCandidate)
        local normalizedName = NormalizePlayerName(name)
        if normalizedName == "" then
            return
        end

        if seenNames[normalizedName] then
            if isLootCandidate then
                seenNames[normalizedName].index = index
                seenNames[normalizedName].isLootCandidate = true
            end
            return
        end

        local candidate = { index = index, name = name, isLootCandidate = isLootCandidate and true or false }
        table.insert(candidates, candidate)
        seenNames[normalizedName] = candidate
    end

    if not GetMasterLootCandidate then
        return candidates
    end

    for index = 1, 40 do
        addCandidate(index, GetMasterLootCandidateLegacy(index), true)
    end

    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for raidIndex = 1, GetNumRaidMembers() do
            local name = GetRaidRosterInfo(raidIndex)
            local normalizedRaidName = NormalizePlayerName(name)
            if normalizedRaidName ~= "" then
                addCandidate(nil, name, false)
            end
        end
    end

    return candidates
end

local function GetMasterLootCandidateIndexMap()
    local candidatesByName = {}

    if not GetMasterLootCandidate then
        return candidatesByName
    end

    for index = 1, 40 do
        local candidateName = GetMasterLootCandidateLegacy(index)
        local normalizedName = NormalizePlayerName(candidateName)
        if normalizedName ~= "" and not candidatesByName[normalizedName] then
            candidatesByName[normalizedName] = index
        end
    end

    return candidatesByName
end

local function IsPlayerInGroupOrRaid(playerName)
    local normalizedTarget = NormalizePlayerName(playerName)
    if normalizedTarget == "" then
        return false
    end

    if NormalizePlayerName(UnitName("player")) == normalizedTarget then
        return true
    end

    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for index = 1, GetNumRaidMembers() do
            local name = GetRaidRosterInfo(index)
            if NormalizePlayerName(name) == normalizedTarget then
                return true
            end
        end
        return false
    end

    if GetNumPartyMembers and GetNumPartyMembers() > 0 then
        for index = 1, GetNumPartyMembers() do
            if NormalizePlayerName(UnitName("party" .. index)) == normalizedTarget then
                return true
            end
        end
    end

    return false
end

local function GetAutoLootItemQuality(slot, itemLink)
    if itemLink then
        local _, _, itemQuality = GetItemInfo(itemLink)
        if itemQuality then
            return itemQuality
        end

        local color = string.match(itemLink, "^|c(%x%x%x%x%x%x%x%x)")
        if color == "ff1eff00" then
            return 2
        elseif color == "ff0070dd" then
            return 3
        elseif color == "ffa335ee" then
            return 4
        elseif color == "ffff8000" then
            return 5
        elseif color == "ffe6cc80" then
            return 7
        elseif color == "ffffffff" then
            return 1
        elseif color == "ff9d9d9d" then
            return 0
        end
    end

    if GetLootSlotInfo then
        local _, _, _, lootQuality = GetLootSlotInfo(slot)
        return lootQuality
    end

    return nil
end

local function GiveLootToCandidate(slot, candidateIndex)
    if GiveMasterLoot and slot and candidateIndex then
        GiveMasterLoot(slot, candidateIndex)
        return true
    end
    return false
end

local function CancelMasterLootAssignments()
    SLM.masterLootPendingAssignments = nil
    SLM.masterLootPendingElapsed = nil
    SLM.masterLootPendingIndex = nil
    if SLM.masterLootTimerFrame then
        SLM.masterLootTimerFrame:SetScript("OnUpdate", nil)
    end
end

local function ScheduleMasterLootAssignments(assignments)
    if table.getn(assignments or {}) == 0 then
        return
    end

    table.sort(assignments, function(a, b)
        return (a.slot or 0) > (b.slot or 0)
    end)

    SLM.masterLootTimerFrame = SLM.masterLootTimerFrame or CreateFrame("Frame")
    SLM.masterLootPendingAssignments = assignments
    SLM.masterLootPendingElapsed = 0
    SLM.masterLootPendingIndex = 1
    SLM.masterLootTimerFrame:SetScript("OnUpdate", function(_, elapsed)
        SLM.masterLootPendingElapsed = (SLM.masterLootPendingElapsed or 0) + elapsed
        if SLM.masterLootPendingElapsed < 0.04 then
            return
        end

        if SLM.masterLootSelectionPending or (SLM.masterLootFallbackDialog and SLM.masterLootFallbackDialog:IsShown()) then
            CancelMasterLootAssignments()
            return
        end

        SLM.masterLootPendingElapsed = 0
        local pendingAssignments = SLM.masterLootPendingAssignments or {}
        local assignment = pendingAssignments[SLM.masterLootPendingIndex or 1]
        if not assignment then
            CancelMasterLootAssignments()
            return
        end

        GiveLootToCandidate(assignment.slot, assignment.candidateIndex)
        SLM.masterLootPendingIndex = (SLM.masterLootPendingIndex or 1) + 1
    end)
end

local function ApplyMasterLootFallbackSelection()
    local selectedName = SLM.masterLootFallbackSelectedName
    if not selectedName then
        return nil
    end

    if SLM.masterLootFallbackOption == "shard" then
        if SLM.masterLootShardInput then
            SLM.masterLootShardInput:SetText(selectedName)
        end
    else
        if SLM.masterLootTargetInput then
            SLM.masterLootTargetInput:SetText(selectedName)
        end
    end

    SaveMasterLootSettings()
    return selectedName
end

local function GetMasterLootOptionLabel(optionKey)
    if optionKey == "shard" then
        return "Shard/Frag"
    end
    return "Loot"
end

local function ShowMasterLootFallbackDialog(slot, itemLink, wantedName, optionKey)
    local candidates = GetMasterLootCandidates(slot)
    if table.getn(candidates) == 0 then
        return
    end

    SLM.masterLootSelectionPending = true
    CancelMasterLootAssignments()
    SLM.masterLootFallbackSlot = slot
    SLM.masterLootFallbackCandidates = candidates
    SLM.masterLootFallbackOption = optionKey or "loot"
    SLM.masterLootFallbackSelectedName = candidates[1].name
    local wantedNormalized = NormalizePlayerName(wantedName)
    for _, candidate in ipairs(candidates) do
        if wantedNormalized ~= "" and NormalizePlayerName(candidate.name) == wantedNormalized then
            SLM.masterLootFallbackSelectedName = candidate.name
            break
        end
    end
    for _, candidate in ipairs(candidates) do
        if wantedNormalized == "" and NormalizePlayerName(candidate.name) == NormalizePlayerName(UnitName("player")) then
            SLM.masterLootFallbackSelectedName = candidate.name
            break
        end
    end

    if not SLM.masterLootFallbackDialog then
        local dialog = CreateFrame("Frame", "SkyvasLootmasterMasterLootFallbackDialog", UIParent)
        dialog:SetWidth(260)
        dialog:SetHeight(118)
        dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 90)
        dialog:SetFrameStrata("DIALOG")
        dialog:SetMovable(true)
        dialog:EnableMouse(true)
        dialog:RegisterForDrag("LeftButton")
        dialog:SetScript("OnDragStart", dialog.StartMoving)
        dialog:SetScript("OnDragStop", dialog.StopMovingOrSizing)
        dialog:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
        dialog:Hide()

        dialog.text = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dialog.text:SetPoint("TOP", dialog, "TOP", 0, -22)
        dialog.text:SetWidth(220)
        dialog.text:SetJustifyH("CENTER")

        dialog.dropdown = CreateFrame("Frame", "SkyvasLootmasterMasterLootFallbackDropdown", dialog, "UIDropDownMenuTemplate")
        dialog.dropdown:SetPoint("TOP", dialog.text, "BOTTOM", -18, -6)

        UIDropDownMenu_SetWidth(dialog.dropdown, 150)
        UIDropDownMenu_Initialize(dialog.dropdown, function()
            for _, candidate in ipairs(SLM.masterLootFallbackCandidates or {}) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = candidate.name
                info.value = candidate.name
                info.checked = NormalizePlayerName(SLM.masterLootFallbackSelectedName) == NormalizePlayerName(candidate.name)
                info.func = function(self)
                    SLM.masterLootFallbackSelectedName = self.value
                    UIDropDownMenu_SetSelectedValue(dialog.dropdown, self.value)
                    UIDropDownMenu_SetText(dialog.dropdown, self:GetText())
                end
                UIDropDownMenu_AddButton(info)
            end
        end)

        dialog.okButton = CreateButton(dialog, "SkyvasLootmasterMasterLootFallbackOkButton", "OK", 70)
        dialog.okButton:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", 48, 18)
        dialog.okButton:SetScript("OnClick", function()
            if SLM.masterLootFallbackSelectedName then
                local selectedName = ApplyMasterLootFallbackSelection()
                if selectedName then
                    SLM.masterLootSelectionPending = false
                    dialog:Hide()
                    return
                end
            end
        end)

        dialog.cancelButton = CreateButton(dialog, "SkyvasLootmasterMasterLootFallbackCancelButton", "Abbrechen", 90)
        dialog.cancelButton:SetPoint("LEFT", dialog.okButton, "RIGHT", 8, 0)
        dialog.cancelButton:SetScript("OnClick", function()
            SLM.masterLootSelectionPending = false
            dialog:Hide()
        end)

        SLM.masterLootFallbackDialog = dialog
    end

    local dialog = SLM.masterLootFallbackDialog
    dialog.text:SetText(GetMasterLootOptionLabel(SLM.masterLootFallbackOption) .. ": Spieler auswählen")
    local selectedName = SLM.masterLootFallbackSelectedName or candidates[1].name
    UIDropDownMenu_SetSelectedValue(dialog.dropdown, selectedName)
    UIDropDownMenu_SetText(dialog.dropdown, selectedName)
    dialog:Show()
end

local function IsPlayerMasterLooter()
    if GetLootMethod then
        local lootMethod, partyMaster, raidMaster = GetLootMethod()
        if lootMethod ~= "master" then
            return false
        end
        if partyMaster == 0 or raidMaster == 0 then
            return true
        end
        if raidMaster and UnitName("raid" .. raidMaster) == UnitName("player") then
            return true
        end
        if partyMaster and UnitName("party" .. partyMaster) == UnitName("player") then
            return true
        end
    end

    return false
end

HandleMasterLootOpened = function()
    local settings = GetMasterLootSettings()
    if not settings.enabled or not IsPlayerMasterLooter() or not GetNumLootItems then
        return
    end
    if SLM.masterLootSelectionPending then
        return
    end
    if SLM.masterLootFallbackDialog and SLM.masterLootFallbackDialog:IsShown() then
        return
    end

    local lootSlots = {}
    local requiredTargets = {}

    for slot = 1, GetNumLootItems() do
        local itemLink = GetLootSlotLink(slot)
        local itemId = ExtractItemId(itemLink)
        local lootQuality = GetAutoLootItemQuality(slot, itemLink)
        if itemId and lootQuality and lootQuality >= 2 then
            local optionKey = "loot"
            local targetName = TrimText(settings.lootTarget)
            if SHARD_ITEM_IDS[itemId] then
                optionKey = "shard"
                targetName = TrimText(settings.shardTarget)
            end

            table.insert(lootSlots, {
                slot = slot,
                itemLink = itemLink,
                optionKey = optionKey,
                targetName = targetName,
            })

            if not requiredTargets[optionKey] then
                requiredTargets[optionKey] = {
                    slot = slot,
                    itemLink = itemLink,
                    targetName = targetName,
                }
            end
        end
    end

    for optionKey, targetInfo in pairs(requiredTargets) do
        if TrimText(targetInfo.targetName) == "" or not IsPlayerInGroupOrRaid(targetInfo.targetName) then
            ShowMasterLootFallbackDialog(targetInfo.slot, targetInfo.itemLink, targetInfo.targetName, optionKey)
            return
        end
    end

    local assignments = {}
    local candidateIndexByName = GetMasterLootCandidateIndexMap()

    for _, lootInfo in ipairs(lootSlots) do
        local candidateIndex = candidateIndexByName[NormalizePlayerName(lootInfo.targetName)]
        if candidateIndex then
            table.insert(assignments, { slot = lootInfo.slot, candidateIndex = candidateIndex })
        else
            ShowMasterLootFallbackDialog(lootInfo.slot, lootInfo.itemLink, lootInfo.targetName, lootInfo.optionKey)
            return
        end
    end

    ScheduleMasterLootAssignments(assignments)
end

local function IsAssistantWhisperEnabled()
    return GetMasterLootSettings().assistantWhisperEnabled
end

local function ConfirmGroupLootRequest(playerName)
    StaticPopupDialogs.SKYVAS_LOOTMASTER_GROUP_LOOT_REQUEST = {
        text = (playerName or "Ein Spieler") .. " möchte auf Gruppenplündern umstellen.",
        button1 = YES,
        button2 = NO,
        OnAccept = function()
            if SetLootMethod then
                SetLootMethod("group")
            end
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
    StaticPopup_Show("SKYVAS_LOOTMASTER_GROUP_LOOT_REQUEST")
end

local function FindLootMethodUnit(playerName)
    local normalizedTarget = NormalizePlayerName(playerName)
    if normalizedTarget == "" then
        return nil, nil
    end

    if NormalizePlayerName(UnitName("player")) == normalizedTarget then
        return "player", 0
    end

    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for index = 1, GetNumRaidMembers() do
            local name = GetRaidRosterInfo(index)
            if NormalizePlayerName(name) == normalizedTarget then
                return "raid" .. index, index
            end
        end
    elseif GetNumPartyMembers then
        for index = 1, GetNumPartyMembers() do
            if NormalizePlayerName(UnitName("party" .. index)) == normalizedTarget then
                return "party" .. index, index
            end
        end
    end

    return nil, nil
end

local function SetMasterLootTo(playerName, unitToken, fallbackIndex)
    if not SetLootMethod then
        return
    end

    local name = string.gsub(playerName or "", "%-.+$", "")
    if name ~= "" then
        local ok = pcall(SetLootMethod, "master", name)
        if ok then
            return
        end
    end

    if unitToken then
        local ok = pcall(SetLootMethod, "master", unitToken)
        if ok then
            return
        end
    end

    if fallbackIndex ~= nil then
        pcall(SetLootMethod, "master", fallbackIndex)
    end
end

local function ConfirmMasterLootForPlayerRequest(playerName)
    StaticPopupDialogs.SKYVAS_LOOTMASTER_PM_PLAYER_REQUEST = {
        text = (playerName or "Ein Spieler") .. " möchte Plündermeister werden.",
        button1 = YES,
        button2 = NO,
        OnAccept = function()
            local unitToken, fallbackIndex = FindLootMethodUnit(playerName)
            SetMasterLootTo(playerName, unitToken, fallbackIndex)
        end,
        timeout = 0,
        whileDead = 1,
        hideOnEscape = 1,
        preferredIndex = 3,
    }
    StaticPopup_Show("SKYVAS_LOOTMASTER_PM_PLAYER_REQUEST")
end

local function HandleAssistantWhisper(message, sender)
    if not sender then
        return
    end

    local command = string.lower(TrimText(message or ""))
    local playerName = string.gsub(sender, "%-.+$", "")
    local settings = GetMasterLootSettings()
    local autoInviteKeyword = string.lower(TrimText(settings.autoInviteKeyword or ""))

    if autoInviteKeyword ~= "" and command == autoInviteKeyword then
        if InviteUnit then
            InviteUnit(playerName)
        elseif InviteByName then
            InviteByName(playerName)
        end
        return
    end

    if command == "!pm me" then
        ConfirmMasterLootForPlayerRequest(playerName)
        return
    end

    if command == "!pm" then
        SetMasterLootTo(UnitName("player"), "player", 0)
        return
    end

    if command == "!group" then
        ConfirmGroupLootRequest(playerName)
        return
    end

    if not IsAssistantWhisperEnabled() then
        return
    end

    if command == "!assi" then
        if PromoteToAssistant then
            PromoteToAssistant(playerName)
        end
    elseif command == "!keinassi" then
        if DemoteAssistant then
            DemoteAssistant(playerName)
        end
    end
end

local function EnsureRollBuckets(item)
    item.rolls = item.rolls or {
        FR = {},
        Main = {},
        Sec = {},
    }
    item.rolls.FR = item.rolls.FR or {}
    item.rolls.Main = item.rolls.Main or {}
    item.rolls.Sec = item.rolls.Sec or {}
    item.rolls.UlduarMount = item.rolls.UlduarMount or {}
    item.rollCountByPlayer = item.rollCountByPlayer or {}
end

local function FindRollById(item, rollId)
    if not item or not rollId then
        return nil
    end

    EnsureRollBuckets(item)

    for _, group in ipairs(GROUP_ORDER) do
        for _, rollInfo in ipairs(item.rolls[group.key]) do
            if rollInfo.rollId == rollId then
                return rollInfo, group
            end
        end
    end

    return nil
end

local function GetWinner(item)
    if not item then
        return nil
    end

    EnsureRollBuckets(item)

    local selectedRoll, selectedGroup = FindRollById(item, item.selectedRollId)
    if selectedRoll then
        return selectedRoll, selectedGroup, true
    end

    for _, group in ipairs(GROUP_ORDER) do
        local rolls = item.rolls[group.key]
        table.sort(rolls, SortRolls)
        if rolls[1] then
            return rolls[1], group
        end
    end

    return nil
end

local function RememberWinner(item, winnerRoll)
    if not item or not winnerRoll or not winnerRoll.name then
        return
    end

    local playerKey = GetPlayerKey(winnerRoll.name)
    for _, wins in pairs(SLM.recentWins) do
        for index = table.getn(wins), 1, -1 do
            if wins[index].sessionItem == item then
                table.remove(wins, index)
            end
        end
    end

    SLM.recentWins[playerKey] = SLM.recentWins[playerKey] or {}
    table.insert(SLM.recentWins[playerKey], {
        playerName = winnerRoll.name,
        itemLink = item.link,
        itemId = ExtractItemId(item.link),
        sessionItem = item,
        wonAt = time(),
    })
    SaveSession()
end

local function RememberCurrentWinner(item)
    local winnerRoll = GetWinner(item)
    if winnerRoll then
        RememberWinner(item, winnerRoll)
    end
end

local function ForgetWinnerForItem(item)
    if not item then
        return
    end

    for playerKey, wins in pairs(SLM.recentWins or {}) do
        for index = table.getn(wins), 1, -1 do
            if wins[index].sessionItem == item then
                table.remove(wins, index)
            end
        end

        if table.getn(wins) == 0 then
            SLM.recentWins[playerKey] = nil
        end
    end

    if SLM.pendingTradeItems then
        for index = table.getn(SLM.pendingTradeItems), 1, -1 do
            if SLM.pendingTradeItems[index].sessionItem == item then
                table.remove(SLM.pendingTradeItems, index)
            end
        end
    end
end

local function RemoveRollFromItem(item, rollInfo)
    if not item or not rollInfo or not rollInfo.rollId then
        return
    end

    EnsureRollBuckets(item)

    for _, group in ipairs(GROUP_ORDER) do
        local rolls = item.rolls[group.key]
        for index = table.getn(rolls), 1, -1 do
            if rolls[index].rollId == rollInfo.rollId then
                table.remove(rolls, index)
                if item.selectedRollId == rollInfo.rollId then
                    item.selectedRollId = nil
                    item.statusText = nil
                end
                ForgetWinnerForItem(item)
                RememberCurrentWinner(item)
                SaveSession()
                UpdateDialog()
                return
            end
        end
    end
end

local function GetItemIndex(item)
    if not item then
        return nil
    end

    for index, sessionItem in ipairs(SLM.items or {}) do
        if sessionItem == item then
            return index
        end
    end

    return nil
end

local function CopyRollInfo(rollInfo)
    local copy = {}
    for key, value in pairs(rollInfo or {}) do
        copy[key] = value
    end
    return copy
end

local function MoveRollToItemIndex(sourceItem, rollInfo, targetIndex)
    local targetItem = SLM.items and SLM.items[targetIndex]
    if not sourceItem or not targetItem or sourceItem == targetItem or not rollInfo or not rollInfo.rollId then
        return
    end

    EnsureRollBuckets(sourceItem)
    EnsureRollBuckets(targetItem)

    local movedRoll
    local sourceRollId = rollInfo.rollId

    for _, group in ipairs(GROUP_ORDER) do
        local rolls = sourceItem.rolls[group.key]
        for index = table.getn(rolls), 1, -1 do
            if rolls[index].rollId == sourceRollId then
                movedRoll = CopyRollInfo(rolls[index])
                movedRoll.groupKey = movedRoll.groupKey or group.key
                table.remove(rolls, index)
                break
            end
        end
        if movedRoll then
            break
        end
    end

    if not movedRoll then
        return
    end

    if sourceItem.selectedRollId == sourceRollId then
        sourceItem.selectedRollId = nil
        sourceItem.statusText = nil
    end

    movedRoll.rollId = targetItem.nextRollId or 1
    targetItem.nextRollId = movedRoll.rollId + 1
    movedRoll.rollCount = (targetItem.rollCountByPlayer[movedRoll.name] or 0) + 1
    targetItem.rollCountByPlayer[movedRoll.name] = movedRoll.rollCount

    local groupKey = movedRoll.groupKey or "Main"
    targetItem.rolls[groupKey] = targetItem.rolls[groupKey] or {}
    table.insert(targetItem.rolls[groupKey], movedRoll)

    ForgetWinnerForItem(sourceItem)
    ForgetWinnerForItem(targetItem)
    RememberCurrentWinner(sourceItem)
    RememberCurrentWinner(targetItem)
    SaveSession()
    UpdateDialog()
end

local function FindFirstBagItem(itemId, usedSlots)
    if not itemId then
        return nil
    end

    usedSlots = usedSlots or {}
    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local slotKey = bag .. ":" .. slot
            local itemLink = GetContainerItemLink(bag, slot)
            if not usedSlots[slotKey] and ExtractItemId(itemLink) == itemId then
                return bag, slot, itemLink
            end
        end
    end

    return nil
end

local function PutItemIntoTrade(itemId, usedSlots, tradeSlot)
    local bag, slot = FindFirstBagItem(itemId, usedSlots)
    if not bag then
        return nil
    end

    PickupContainerItem(bag, slot)
    ClickTradeButton(tradeSlot)
    usedSlots[bag .. ":" .. slot] = true
    return true
end

local function GetTradeTargetName()
    if TradeFrameRecipientNameText and TradeFrameRecipientNameText:GetText() then
        return TradeFrameRecipientNameText:GetText()
    end

    return UnitName("NPC")
end

local function HandleTradeShow()
    local playerName = GetTradeTargetName()
    local playerKey = GetPlayerKey(playerName)
    local wins = SLM.recentWins[playerKey]

    if not wins or table.getn(wins) == 0 then
        return
    end

    local now = time()
    for index = table.getn(wins), 1, -1 do
        if not wins[index].itemId or now - (wins[index].wonAt or 0) > WIN_TRADE_WINDOW_SECONDS then
            table.remove(wins, index)
        end
    end

    if table.getn(wins) == 0 then
        SLM.recentWins[playerKey] = nil
        SaveSession()
        return
    end

    local usedSlots = {}
    local pendingTradeItems = {}
    local tradeSlot = 1
    for _, winInfo in ipairs(wins) do
        if table.getn(pendingTradeItems) >= 6 then
            break
        end

        if FindFirstBagItem(winInfo.itemId, usedSlots) and PutItemIntoTrade(winInfo.itemId, usedSlots, tradeSlot) then
            table.insert(pendingTradeItems, winInfo)
            tradeSlot = tradeSlot + 1
        end
    end

    if table.getn(pendingTradeItems) == 0 then
        return
    end

    SLM.pendingTradeItems = pendingTradeItems
    SLM.pendingTradePlayerName = playerName
    SaveSession()
end

local function HandleTradeSuccess()
    if not SLM.pendingTradeItems or table.getn(SLM.pendingTradeItems) == 0 then
        return
    end

    for _, winInfo in ipairs(SLM.pendingTradeItems) do
        if winInfo.sessionItem then
            winInfo.sessionItem.traded = true
            winInfo.sessionItem.tradedTo = SLM.pendingTradePlayerName
            winInfo.sessionItem.tradedAt = GetTimestamp()
        end
    end

    local playerKey = GetPlayerKey(SLM.pendingTradePlayerName)
    local wins = SLM.recentWins[playerKey]
    if wins then
        for _, tradedWin in ipairs(SLM.pendingTradeItems) do
            for index = table.getn(wins), 1, -1 do
                if wins[index] == tradedWin then
                    table.remove(wins, index)
                    break
                end
            end
        end

        if table.getn(wins) == 0 then
            SLM.recentWins[playerKey] = nil
        end
    end
    SLM.pendingTradeItems = {}
    SLM.pendingTradePlayerName = nil
    SaveSession()
    if SLM.frame and SLM.frame:IsShown() then
        UpdateDialog()
    end
end

local function ClearRows()
    for _, row in ipairs(SLM.rows) do
        row:Hide()
    end
end

local function GetRow(index)
    if SLM.rows[index] then
        return SLM.rows[index]
    end

    local row = CreateFrame("Button", nil, SLM.content)
    row:SetWidth(150)
    row:SetHeight(18)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetAllPoints(row)
    row.text:SetJustifyH("LEFT")
    row.text:SetTextColor(1, 1, 1)
    SLM.rows[index] = row
    return row
end

local function GetSmallHeaderFont()
    if SmallHeaderFont then
        return SmallHeaderFont
    end

    SmallHeaderFont = CreateFont("SkyvasLootmasterSmallHeaderFont")
    SmallHeaderFont:SetFontObject(GameFontNormalSmall)
    local fontPath = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    SmallHeaderFont:SetFont(fontPath, 10, "")
    return SmallHeaderFont
end

local function AddRow(index, text, red, green, blue, fontObject)
    local row = GetRow(index)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", SLM.content, "TOPLEFT", 8, -((index - 1) * 18) - 8)
    row:RegisterForClicks("LeftButtonUp")
    row:SetScript("OnClick", nil)
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row.text:SetFontObject(fontObject or GameFontNormal)
    row.text:SetText(text)
    row.text:SetTextColor(red or 1, green or 1, blue or 1)
    row:Show()
end

local function GetRollTimestampText(rollInfo)
    return rollInfo.timestamp or "--:--:--"
end

local function GetRollDelayColorCode(rollInfo)
    local elapsedSeconds = tonumber(rollInfo.elapsedSeconds)
    if not elapsedSeconds then
        return "|cffffffff"
    end

    if elapsedSeconds >= 180 then
        return "|cffff2020"
    elseif elapsedSeconds >= 120 then
        return "|cffff8c00"
    elseif elapsedSeconds >= 60 then
        return "|cffffff00"
    end

    return "|cffffffff"
end

local function MarkRollAsWinner(item, rollInfo)
    if not item or not rollInfo or not rollInfo.rollId then
        return
    end

    item.selectedRollId = rollInfo.rollId
    item.statusText = rollInfo.name .. " mit " .. rollInfo.roll
    RememberWinner(item, rollInfo)
    SaveSession()
    UpdateDialog()
end

local function ShowRollContextMenu(row, item, rollInfo)
    if not SLM.rollContextMenuFrame then
        SLM.rollContextMenuFrame = CreateFrame("Frame", "SkyvasLootmasterRollContextMenu", UIParent, "UIDropDownMenuTemplate")
    end

    local rollText = (rollInfo.roll or "?") .. " - " .. (rollInfo.name or "?")
    local itemIndex = GetItemIndex(item)
    local itemCount = table.getn(SLM.items or {})
    local previousItemIndex = itemIndex and itemIndex - 1 or nil
    local nextItemIndex = itemIndex and itemIndex + 1 or nil
    local canMovePrevious = previousItemIndex and previousItemIndex >= 1
    local canMoveNext = nextItemIndex and nextItemIndex <= itemCount
    local menu = {
        {
            text = rollText,
            isTitle = true,
            notCheckable = true,
        },
        {
            text = "Als Gewinner markieren",
            notCheckable = true,
            func = function()
                MarkRollAsWinner(item, rollInfo)
            end,
        },
        {
            text = "Zum vorherigen Item verschieben",
            notCheckable = true,
            disabled = not canMovePrevious,
            func = function()
                MoveRollToItemIndex(item, rollInfo, previousItemIndex)
            end,
        },
        {
            text = "Zum nächsten Item verschieben",
            notCheckable = true,
            disabled = not canMoveNext,
            func = function()
                MoveRollToItemIndex(item, rollInfo, nextItemIndex)
            end,
        },
        {
            text = "Roll entfernen",
            notCheckable = true,
            func = function()
                RemoveRollFromItem(item, rollInfo)
            end,
        },
        {
            text = CANCEL,
            notCheckable = true,
        },
    }

    EasyMenu(menu, SLM.rollContextMenuFrame, row, 0, 0, "MENU")
end

local function AddRollRow(index, item, rollInfo)
    local rollCount = rollInfo.rollCount or 1
    local countText = ""
    local selectedText = "  "
    local delayColor = GetRollDelayColorCode(rollInfo)

    if rollCount > 1 then
        countText = " (" .. rollCount .. ")"
    end

    if item.selectedRollId == rollInfo.rollId then
        selectedText = "|cff00ff00> |r"
    end

    AddRow(index, selectedText .. delayColor .. rollInfo.roll .. countText .. " - |r" .. ColorizeName(rollInfo.name, rollInfo.classFile), 1, 1, 1)

    local row = GetRow(index)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            ShowRollContextMenu(self, item, rollInfo)
            return
        end

        local now = GetTime()
        if not row.lastClickTime or now - row.lastClickTime > 0.35 then
            row.lastClickTime = now
            return
        end

        row.lastClickTime = nil
        MarkRollAsWinner(item, rollInfo)
    end)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Roll-Zeit: " .. GetRollTimestampText(rollInfo), 1, 1, 1)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

local function RemoveWishlistItem(index)
    local wishlist = GetWishlist()
    if index and wishlist[index] then
        table.remove(wishlist, index)
        SaveSession()
    end
end

local function ClearWishlistRows()
    for _, row in ipairs(SLM.wishlistRows) do
        row:Hide()
    end
end

local function GetWishlistRow(index)
    if SLM.wishlistRows[index] then
        return SLM.wishlistRows[index]
    end

    local row = CreateFrame("Button", nil, SLM.wishlistContent)
    row:SetWidth(150)
    row:SetHeight(18)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.text:SetAllPoints(row)
    row.text:SetJustifyH("LEFT")
    SLM.wishlistRows[index] = row
    return row
end

function UpdateWishlistView()
    if not SLM.wishlistFrame then
        return
    end

    ClearWishlistRows()

    local wishlist = GetWishlist()
    local rowIndex = 1

    if table.getn(wishlist) == 0 then
        local row = GetWishlistRow(rowIndex)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", SLM.wishlistContent, "TOPLEFT", 8, -8)
        row:SetScript("OnClick", nil)
        row:SetScript("OnEnter", nil)
        row:SetScript("OnLeave", nil)
        row.text:SetText("Keine Items")
        row.text:SetTextColor(0.65, 0.65, 0.65)
        row:Show()
        rowIndex = rowIndex + 1
    else
        for wishlistIndex, itemText in ipairs(wishlist) do
            local row = GetWishlistRow(rowIndex)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", SLM.wishlistContent, "TOPLEFT", 8, -((rowIndex - 1) * 18) - 8)
            row.text:SetText(itemText)
            row.text:SetTextColor(1, 1, 1)
            row:SetScript("OnEnter", function(self)
                if string.find(itemText, "|Hitem:") then
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:SetHyperlink(itemText)
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            row:SetScript("OnClick", function(self)
                local now = GetTime()
                if not self.lastClickTime or now - self.lastClickTime > 0.35 then
                    self.lastClickTime = now
                    return
                end

                self.lastClickTime = nil
                RemoveWishlistItem(wishlistIndex)
                UpdateWishlistView()
            end)
            row:Show()
            rowIndex = rowIndex + 1
        end
    end

    SLM.wishlistContent:SetHeight(math.max(50, (rowIndex - 1) * 18 + 8))
    SLM.wishlistScroll:SetVerticalScroll(0)
end

local function ShowLootView()
    SLM.currentView = "loot"
    SLM.lootFrame:Show()
    SLM.wishlistFrame:Hide()
    if SLM.settingsFrame then
        SLM.settingsFrame:Hide()
    end
    SLM.viewToggleButton:SetText("L")
    UpdateDialog()
end

local function ShowWishlistView()
    SLM.currentView = "wishlist"
    SLM.lootFrame:Hide()
    if SLM.settingsFrame then
        SLM.settingsFrame:Hide()
    end
    SLM.wishlistFrame:Show()
    SLM.viewToggleButton:SetText("W")
    UpdateWishlistView()
end

local function ShowSettingsView()
    SLM.currentView = "settings"
    SLM.lootFrame:Hide()
    SLM.wishlistFrame:Hide()
    SLM.settingsFrame:Show()
    SLM.viewToggleButton:SetText("S")
    UpdateMasterLootSettingsView()
end

function UpdateMasterLootSettingsView()
    if not SLM.settingsFrame then
        return
    end

    local settings = GetMasterLootSettings()
    SLM.masterLootEnabledButton:SetChecked(settings.enabled and true or false)
    SLM.masterLootLockButton:SetChecked(settings.locked and true or false)
    SLM.assistantWhisperButton:SetChecked(settings.assistantWhisperEnabled and true or false)
    SLM.itemStatsButton:SetChecked(settings.itemStatsEnabled and true or false)
    SLM.masterLootTargetInput:SetText(settings.lootTarget or "")
    SLM.masterLootShardInput:SetText(settings.shardTarget or "")
    SLM.autoInviteInput:SetText(settings.autoInviteKeyword or "")
    if settings.locked then
        SLM.masterLootTargetInput:ClearFocus()
        SLM.masterLootShardInput:ClearFocus()
        SLM.autoInviteInput:ClearFocus()
        SLM.masterLootTargetInput:EnableMouse(false)
        SLM.masterLootShardInput:EnableMouse(false)
        SLM.autoInviteInput:EnableMouse(false)
        SLM.masterLootTargetInput:SetTextColor(0.55, 0.55, 0.55)
        SLM.masterLootShardInput:SetTextColor(0.55, 0.55, 0.55)
        SLM.autoInviteInput:SetTextColor(0.55, 0.55, 0.55)
    else
        SLM.masterLootTargetInput:EnableMouse(true)
        SLM.masterLootShardInput:EnableMouse(true)
        SLM.autoInviteInput:EnableMouse(true)
        SLM.masterLootTargetInput:SetTextColor(1, 1, 1)
        SLM.masterLootShardInput:SetTextColor(1, 1, 1)
        SLM.autoInviteInput:SetTextColor(1, 1, 1)
    end
end

function UpdateDialog()
    if not SLM.frame then
        return
    end

    if SLM.currentView == "wishlist" then
        UpdateWishlistView()
        return
    elseif SLM.currentView == "settings" then
        UpdateMasterLootSettingsView()
        return
    end

    ClearRows()

    local item = GetCurrentItem()
    if not item then
        SLM.itemButton.link = nil
        SLM.timestampText:SetText("--:--:--")
        SLM.pageText:SetText("0 / 0")
        SLM.itemText:SetText("Kein Item")
        SLM.statusText:SetText("")
        SLM.content:SetHeight(50)
        return
    end

    EnsureRollBuckets(item)

    SLM.itemButton.link = item.link
    local tradeMarker = ""
    if item.traded then
        tradeMarker = " TRD"
    end
    SLM.timestampText:SetText((item.timestamp or "--:--:--") .. tradeMarker)
    SLM.itemText:SetText(item.link)
    SLM.pageText:SetText(SLM.currentIndex .. " / " .. table.getn(SLM.items))

    local rowIndex = 1
    local winnerRoll, winnerGroup, isManualWinner = GetWinner(item)
    if item.statusText then
        SLM.statusText:SetText(item.statusText)
    elseif winnerRoll and winnerGroup and not isManualWinner then
        SLM.statusText:SetText(ColorizeName(winnerRoll.name, winnerRoll.classFile) .. " mit " .. winnerRoll.roll)
    else
        SLM.statusText:SetText("")
    end

    if false and winnerRoll and winnerGroup then
        local winnerPrefix = "Aktueller Gewinner: "
        if isManualWinner then
            winnerPrefix = "Ausgewählter Gewinner: "
        end
        AddRow(rowIndex, winnerPrefix .. winnerRoll.roll .. " - " .. ColorizeName(winnerRoll.name, winnerRoll.classFile) .. " (" .. winnerGroup.label .. ")", 0.2, 1, 0.2)
        rowIndex = rowIndex + 1
        AddRow(rowIndex, " ", 1, 1, 1)
        rowIndex = rowIndex + 1
    end

    for _, group in ipairs(GROUP_ORDER) do
        local rolls = item.rolls[group.key]
        table.sort(rolls, SortRolls)

        if group.key ~= "Main" and table.getn(rolls) == 0 then
            -- Only show optional categories once someone rolled for them.
        else
        AddRow(rowIndex, group.label .. " (" .. group.range .. ")", 1, 0.82, 0, GetSmallHeaderFont())
        rowIndex = rowIndex + 1

        if table.getn(rolls) == 0 then
            AddRow(rowIndex, "  Keine Rolls", 0.65, 0.65, 0.65)
            rowIndex = rowIndex + 1
        else
            for _, rollInfo in ipairs(rolls) do
                AddRollRow(rowIndex, item, rollInfo)
                rowIndex = rowIndex + 1
            end
        end

        end
    end

    SLM.content:SetHeight(math.max(50, (rowIndex - 1) * 18 + 8))
    SLM.scroll:SetVerticalScroll(0)
end

function CreateButton(parent, name, text, width)
    local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    button:SetWidth(width)
    button:SetHeight(24)
    button:SetText(text)
    return button
end

local function CreateDialog()
    if SLM.frame then
        return
    end

    local frame = CreateFrame("Frame", "SkyvasLootmasterFrame", UIParent)
    frame:SetWidth(226)
    frame:SetHeight(324)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)

    local viewToggleButton = CreateButton(frame, "SkyvasLootmasterViewToggleButton", "L", 24)
    viewToggleButton:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    viewToggleButton:SetScript("OnClick", function()
        if SLM.currentView == "loot" then
            ShowWishlistView()
        elseif SLM.currentView == "wishlist" then
            ShowSettingsView()
        else
            ShowLootView()
        end
    end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -18)
    title:SetText("Skyva's Lootmaster")

    local lootFrame = CreateFrame("Frame", "SkyvasLootmasterLootView", frame)
    lootFrame:SetAllPoints(frame)

    local wishlistFrame = CreateFrame("Frame", "SkyvasLootmasterWishlistView", frame)
    wishlistFrame:SetAllPoints(frame)
    wishlistFrame:Hide()

    local wishlistTitle = wishlistFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    wishlistTitle:SetPoint("TOP", wishlistFrame, "TOP", 0, -42)
    wishlistTitle:SetText("Wunschliste")

    local settingsFrame = CreateFrame("Frame", "SkyvasLootmasterSettingsView", frame)
    settingsFrame:SetAllPoints(frame)
    settingsFrame:Hide()

    local settingsTitle = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    settingsTitle:SetPoint("TOP", settingsFrame, "TOP", 0, -42)
    settingsTitle:SetText("Settings")

    local timestampText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    timestampText:SetPoint("TOPLEFT", frame, "TOPLEFT", 28, -46)
    timestampText:SetWidth(100)
    timestampText:SetHeight(14)
    timestampText:SetJustifyH("LEFT")
    timestampText:SetText("--:--:--")

    local timestampButton = CreateFrame("Button", "SkyvasLootmasterTimestampButton", frame)
    timestampButton:SetPoint("TOPLEFT", timestampText, "TOPLEFT", 0, 0)
    timestampButton:SetWidth(100)
    timestampButton:SetHeight(14)
    timestampButton:SetScript("OnEnter", function(self)
        local item = GetCurrentItem()
        if item and item.traded and item.tradedTo then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Gehandelt an: " .. item.tradedTo, 1, 1, 1)
            if item.tradedAt then
                GameTooltip:AddLine("Zeit: " .. item.tradedAt, 1, 1, 1)
            end
            GameTooltip:Show()
        end
    end)
    timestampButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local pageText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pageText:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, -46)
    pageText:SetWidth(45)
    pageText:SetHeight(14)
    pageText:SetJustifyH("RIGHT")
    pageText:SetText("0 / 0")

    local itemButton = CreateFrame("Button", "SkyvasLootmasterItemButton", frame)
    itemButton:SetPoint("TOP", frame, "TOP", 0, -60)
    itemButton:SetWidth(165)
    itemButton:SetHeight(22)
    itemButton:SetScript("OnClick", function(self, button)
        if self.link then
            local itemString = string.match(self.link, "|H([^|]+)|h")
            if itemString then
                SetItemRef(itemString, self.link, button)
            end
        end
    end)
    itemButton:SetScript("OnEnter", function(self)
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetHyperlink(self.link)
            GameTooltip:Show()
        end
    end)
    itemButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local itemText = itemButton:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    itemText:SetAllPoints(itemButton)
    itemText:SetHeight(22)
    itemText:SetJustifyH("CENTER")
    itemText:SetText("Kein Item")

    local scroll = CreateFrame("ScrollFrame", "SkyvasLootmasterScrollFrame", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -80)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -42, 82)

    local content = CreateFrame("Frame", "SkyvasLootmasterScrollContent", scroll)
    content:SetWidth(150)
    content:SetHeight(50)
    scroll:SetScrollChild(content)

    local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 62)
    statusText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 62)
    statusText:SetHeight(18)
    statusText:SetJustifyH("CENTER")
    statusText:SetText("")

    local firstButton = CreateButton(frame, "SkyvasLootmasterFirstButton", "<<", 30)
    firstButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 34)
    firstButton:SetScript("OnClick", function()
        if table.getn(SLM.items) == 0 then
            return
        end

        SLM.currentIndex = 1
        SLM.activeItem = GetCurrentItem()
        SaveSession()
        UpdateDialog()
    end)

    local previousButton = CreateButton(frame, "SkyvasLootmasterPreviousButton", "<", 24)
    previousButton:SetPoint("LEFT", firstButton, "RIGHT", 2, 0)
    previousButton:SetScript("OnClick", function()
        if table.getn(SLM.items) == 0 then
            return
        end

        SLM.currentIndex = SLM.currentIndex - 1
        if SLM.currentIndex < 1 then
            SLM.currentIndex = table.getn(SLM.items)
        end
        SLM.activeItem = GetCurrentItem()
        SaveSession()
        UpdateDialog()
    end)

    local announceButton = CreateButton(frame, "SkyvasLootmasterAnnounceButton", "Gewinner", 74)
    announceButton:SetPoint("LEFT", previousButton, "RIGHT", 2, 0)
    announceButton:SetScript("OnClick", function()
        local item = GetCurrentItem()
        local winnerRoll, winnerGroup, isManualWinner = GetWinner(item)

        if not item then
            SLM.statusText:SetText("Kein Item ausgewählt.")
            return
        end

        if not winnerRoll then
            item.statusText = "Keine gültigen Rolls für " .. item.name .. "."
            SaveSession()
            UpdateDialog()
            return
        end

        local winnerText = "Gewinner: "
        if isManualWinner then
            winnerText = "Manueller Gewinner: "
        end
        item.statusText = winnerRoll.name .. " mit " .. winnerRoll.roll
        RememberWinner(item, winnerRoll)
        SendChatMessage("Gewinner: " .. winnerRoll.name .. " mit " .. winnerRoll.roll .. " (" .. winnerGroup.label .. ") gewinnt " .. item.link, "RAID")
        SaveSession()
        UpdateDialog()
    end)

    local nextButton = CreateButton(frame, "SkyvasLootmasterNextButton", ">", 24)
    nextButton:SetPoint("LEFT", announceButton, "RIGHT", 2, 0)
    nextButton:SetScript("OnClick", function()
        if table.getn(SLM.items) == 0 then
            return
        end

        SLM.currentIndex = SLM.currentIndex + 1
        if SLM.currentIndex > table.getn(SLM.items) then
            SLM.currentIndex = 1
        end
        SLM.activeItem = GetCurrentItem()
        SaveSession()
        UpdateDialog()
    end)

    local latestButton = CreateButton(frame, "SkyvasLootmasterLatestButton", ">>", 30)
    latestButton:SetPoint("LEFT", nextButton, "RIGHT", 2, 0)
    latestButton:SetScript("OnClick", function()
        if table.getn(SLM.items) == 0 then
            return
        end

        SLM.currentIndex = table.getn(SLM.items)
        SLM.activeItem = GetCurrentItem()
        SaveSession()
        UpdateDialog()
    end)

    local focusRollButton = CreateButton(frame, "SkyvasLootmasterFocusRollButton", "FR", 36)
    focusRollButton:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 10)
    focusRollButton:SetScript("OnClick", function()
        RandomRoll(101, 200)
    end)

    local mainRollButton = CreateButton(frame, "SkyvasLootmasterMainRollButton", "Main", 52)
    mainRollButton:SetPoint("LEFT", focusRollButton, "RIGHT", 4, 0)
    mainRollButton:SetScript("OnClick", function()
        RandomRoll(1, 100)
    end)

    local secRollButton = CreateButton(frame, "SkyvasLootmasterSecRollButton", "Sec", 44)
    secRollButton:SetPoint("LEFT", mainRollButton, "RIGHT", 4, 0)
    secRollButton:SetScript("OnClick", function()
        RandomRoll(1, 99)
    end)

    local settingsButton = CreateButton(frame, "SkyvasLootmasterSettingsButton", "Reset", 52)
    settingsButton:SetPoint("LEFT", secRollButton, "RIGHT", 4, 0)
    settingsButton:SetScript("OnClick", function()
        ConfirmResetSession()
    end)

    timestampText:SetParent(lootFrame)
    timestampButton:SetParent(lootFrame)
    pageText:SetParent(lootFrame)
    itemButton:SetParent(lootFrame)
    scroll:SetParent(lootFrame)
    statusText:SetParent(lootFrame)
    previousButton:SetParent(lootFrame)
    firstButton:SetParent(lootFrame)
    announceButton:SetParent(lootFrame)
    nextButton:SetParent(lootFrame)
    latestButton:SetParent(lootFrame)
    focusRollButton:SetParent(lootFrame)
    mainRollButton:SetParent(lootFrame)
    secRollButton:SetParent(lootFrame)
    settingsButton:SetParent(lootFrame)

    local wishlistScroll = CreateFrame("ScrollFrame", "SkyvasLootmasterWishlistScrollFrame", wishlistFrame, "UIPanelScrollFrameTemplate")
    wishlistScroll:SetPoint("TOPLEFT", wishlistFrame, "TOPLEFT", 24, -62)
    wishlistScroll:SetPoint("BOTTOMRIGHT", wishlistFrame, "BOTTOMRIGHT", -42, 112)

    local wishlistContent = CreateFrame("Frame", "SkyvasLootmasterWishlistContent", wishlistScroll)
    wishlistContent:SetWidth(150)
    wishlistContent:SetHeight(50)
    wishlistScroll:SetScrollChild(wishlistContent)

    local wishlistInput = CreateFrame("EditBox", "SkyvasLootmasterWishlistInput", wishlistFrame, "InputBoxTemplate")
    wishlistInput:SetPoint("BOTTOMLEFT", wishlistFrame, "BOTTOMLEFT", 24, 84)
    wishlistInput:SetWidth(175)
    wishlistInput:SetHeight(20)
    wishlistInput:SetAutoFocus(false)

    local wishlistAddButton = CreateButton(wishlistFrame, "SkyvasLootmasterWishlistAddButton", "+", 52)
    wishlistAddButton:SetPoint("BOTTOMLEFT", wishlistFrame, "BOTTOMLEFT", 55, 56)
    wishlistAddButton:SetScript("OnClick", function()
        AddWishlistItem(wishlistInput:GetText())
        wishlistInput:SetText("")
        UpdateWishlistView()
    end)

    wishlistInput:SetScript("OnEnterPressed", function(self)
        AddWishlistItem(self:GetText())
        self:SetText("")
        self:ClearFocus()
        UpdateWishlistView()
    end)
    wishlistInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    local wishlistResetButton = CreateButton(wishlistFrame, "SkyvasLootmasterWishlistResetButton", "Reset", 52)
    wishlistResetButton:SetPoint("LEFT", wishlistAddButton, "RIGHT", 6, 0)
    wishlistResetButton:SetScript("OnClick", function()
        ConfirmResetWishlist()
    end)

    local wishlistSoundButton = CreateFrame("CheckButton", "SkyvasLootmasterWishlistSoundButton", wishlistFrame, "UICheckButtonTemplate")
    wishlistSoundButton:SetPoint("BOTTOMLEFT", wishlistFrame, "BOTTOMLEFT", 56, 28)
    wishlistSoundButton:SetWidth(24)
    wishlistSoundButton:SetHeight(24)
    wishlistSoundButton:SetScript("OnClick", function()
        SetWishlistSoundEnabled(wishlistSoundButton:GetChecked())
        UpdateWishlistSoundButton()
    end)
    SLM.wishlistSoundButton = wishlistSoundButton
    UpdateWishlistSoundButton()

    local wishlistSoundText = wishlistFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    wishlistSoundText:SetPoint("LEFT", wishlistSoundButton, "RIGHT", -2, 0)
    wishlistSoundText:SetText("Sound")

    local wishlistBoeButton = CreateFrame("CheckButton", "SkyvasLootmasterWishlistBoeButton", wishlistFrame, "UICheckButtonTemplate")
    wishlistBoeButton:SetPoint("LEFT", wishlistSoundText, "RIGHT", 8, 0)
    wishlistBoeButton:SetWidth(24)
    wishlistBoeButton:SetHeight(24)
    wishlistBoeButton:SetScript("OnClick", function()
        SetWishlistBoeEnabled(wishlistBoeButton:GetChecked())
        UpdateWishlistBoeButton()
    end)

    local wishlistBoeText = wishlistFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    wishlistBoeText:SetPoint("LEFT", wishlistBoeButton, "RIGHT", -2, 0)
    wishlistBoeText:SetText("BOE")

    SLM.wishlistBoeButton = wishlistBoeButton
    UpdateWishlistBoeButton()

    local onlyWishlistPopupButton = CreateFrame("CheckButton", "SkyvasLootmasterOnlyWishlistPopupButton", wishlistFrame, "UICheckButtonTemplate")
    onlyWishlistPopupButton:SetPoint("BOTTOMLEFT", wishlistFrame, "BOTTOMLEFT", 34, 6)
    onlyWishlistPopupButton:SetWidth(24)
    onlyWishlistPopupButton:SetHeight(24)
    onlyWishlistPopupButton:SetScript("OnClick", function()
        SetOnlyWishlistPopupEnabled(onlyWishlistPopupButton:GetChecked())
        UpdateOnlyWishlistPopupButton()
    end)

    local onlyWishlistPopupText = wishlistFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    onlyWishlistPopupText:SetPoint("LEFT", onlyWishlistPopupButton, "RIGHT", -2, 2)
    onlyWishlistPopupText:SetText("Only Wishlist Popup")

    SLM.onlyWishlistPopupButton = onlyWishlistPopupButton
    UpdateOnlyWishlistPopupButton()

    local masterLootEnabledButton = CreateFrame("CheckButton", "SkyvasLootmasterMasterLootEnabledButton", settingsFrame, "UICheckButtonTemplate")
    masterLootEnabledButton:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 24, -62)
    masterLootEnabledButton:SetWidth(24)
    masterLootEnabledButton:SetHeight(24)
    masterLootEnabledButton:SetScript("OnClick", function()
        SaveMasterLootSettings()
    end)

    local masterLootEnabledText = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    masterLootEnabledText:SetPoint("LEFT", masterLootEnabledButton, "RIGHT", -2, 0)
    masterLootEnabledText:SetText("Auto Loot")

    local masterLootLockButton = CreateFrame("CheckButton", "SkyvasLootmasterMasterLootLockButton", settingsFrame, "UICheckButtonTemplate")
    masterLootLockButton:SetPoint("LEFT", masterLootEnabledText, "RIGHT", 16, 0)
    masterLootLockButton:SetWidth(24)
    masterLootLockButton:SetHeight(24)
    masterLootLockButton:SetScript("OnClick", function()
        SaveMasterLootSettings()
        UpdateMasterLootSettingsView()
    end)

    local masterLootLockText = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    masterLootLockText:SetPoint("LEFT", masterLootLockButton, "RIGHT", -2, 0)
    masterLootLockText:SetText("Lock")

    local assistantWhisperButton = CreateFrame("CheckButton", "SkyvasLootmasterAssistantWhisperButton", settingsFrame, "UICheckButtonTemplate")
    assistantWhisperButton:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 24, -84)
    assistantWhisperButton:SetWidth(24)
    assistantWhisperButton:SetHeight(24)
    assistantWhisperButton:SetScript("OnClick", function()
        SaveMasterLootSettings()
    end)

    local assistantWhisperText = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    assistantWhisperText:SetPoint("LEFT", assistantWhisperButton, "RIGHT", -2, 0)
    assistantWhisperText:SetText("Assi via Whisper")

    local itemStatsButton = CreateFrame("CheckButton", "SkyvasLootmasterItemStatsButton", settingsFrame, "UICheckButtonTemplate")
    itemStatsButton:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 24, -106)
    itemStatsButton:SetWidth(24)
    itemStatsButton:SetHeight(24)
    itemStatsButton:SetScript("OnClick", function()
        SaveMasterLootSettings()
    end)

    local itemStatsText = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    itemStatsText:SetPoint("LEFT", itemStatsButton, "RIGHT", -2, 0)
    itemStatsText:SetText("Item with Stats")

    local masterLootTargetLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    masterLootTargetLabel:SetPoint("TOPLEFT", settingsFrame, "TOPLEFT", 28, -130)
    masterLootTargetLabel:SetText("Loot")

    local masterLootTargetInput = CreateFrame("EditBox", "SkyvasLootmasterMasterLootTargetInput", settingsFrame, "InputBoxTemplate")
    masterLootTargetInput:SetPoint("TOPLEFT", masterLootTargetLabel, "BOTTOMLEFT", -4, -6)
    masterLootTargetInput:SetWidth(170)
    masterLootTargetInput:SetHeight(20)
    masterLootTargetInput:SetAutoFocus(false)
    masterLootTargetInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        SaveMasterLootSettings()
    end)
    masterLootTargetInput:SetScript("OnEditFocusLost", function()
        SaveMasterLootSettings()
    end)
    masterLootTargetInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    local masterLootShardLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    masterLootShardLabel:SetPoint("TOPLEFT", masterLootTargetInput, "BOTTOMLEFT", 4, -12)
    masterLootShardLabel:SetText("Shard/Frag")

    local masterLootShardInput = CreateFrame("EditBox", "SkyvasLootmasterMasterLootShardInput", settingsFrame, "InputBoxTemplate")
    masterLootShardInput:SetPoint("TOPLEFT", masterLootShardLabel, "BOTTOMLEFT", -4, -6)
    masterLootShardInput:SetWidth(170)
    masterLootShardInput:SetHeight(20)
    masterLootShardInput:SetAutoFocus(false)
    masterLootShardInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        SaveMasterLootSettings()
    end)
    masterLootShardInput:SetScript("OnEditFocusLost", function()
        SaveMasterLootSettings()
    end)
    masterLootShardInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    local autoInviteLabel = settingsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    autoInviteLabel:SetPoint("TOPLEFT", masterLootShardInput, "BOTTOMLEFT", 4, -12)
    autoInviteLabel:SetText("AutoInv")

    local autoInviteInput = CreateFrame("EditBox", "SkyvasLootmasterAutoInviteInput", settingsFrame, "InputBoxTemplate")
    autoInviteInput:SetPoint("TOPLEFT", autoInviteLabel, "BOTTOMLEFT", -4, -6)
    autoInviteInput:SetWidth(170)
    autoInviteInput:SetHeight(20)
    autoInviteInput:SetAutoFocus(false)
    autoInviteInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        SaveMasterLootSettings()
    end)
    autoInviteInput:SetScript("OnEditFocusLost", function()
        SaveMasterLootSettings()
    end)
    autoInviteInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    SLM.frame = frame
    SLM.viewToggleButton = viewToggleButton
    SLM.lootFrame = lootFrame
    SLM.wishlistFrame = wishlistFrame
    SLM.settingsFrame = settingsFrame
    SLM.timestampText = timestampText
    SLM.timestampButton = timestampButton
    SLM.itemButton = itemButton
    SLM.itemText = itemText
    SLM.pageText = pageText
    SLM.statusText = statusText
    SLM.scroll = scroll
    SLM.content = content
    SLM.wishlistScroll = wishlistScroll
    SLM.wishlistContent = wishlistContent
    SLM.wishlistInput = wishlistInput
    SLM.masterLootEnabledButton = masterLootEnabledButton
    SLM.masterLootLockButton = masterLootLockButton
    SLM.assistantWhisperButton = assistantWhisperButton
    SLM.itemStatsButton = itemStatsButton
    SLM.masterLootTargetInput = masterLootTargetInput
    SLM.masterLootShardInput = masterLootShardInput
    SLM.autoInviteInput = autoInviteInput
    UpdateMasterLootSettingsView()
end

local function AddItem(itemLink, openDialog)
    RestoreSession()
    CreateDialog()
    if openDialog == nil then
        openDialog = true
    end

    local item = {
        link = itemLink,
        name = ExtractItemName(itemLink),
        timestamp = GetTimestamp(),
        startedAt = time(),
        rolls = {
            UlduarMount = {},
            FR = {},
            Main = {},
            Sec = {},
        },
        rollCountByPlayer = {},
        nextRollId = 1,
    }

    table.insert(SLM.items, item)
    SLM.activeItem = item
    SLM.currentIndex = table.getn(SLM.items)
    if openDialog then
        SLM.frame:Show()
        UpdateDialog()
    else
        if SLM.frame:IsShown() then
            UpdateDialog()
        end
    end
    SaveSession()
end

local function AddRoll(name, roll, groupKey, maxRoll)
    RestoreSession()
    local item = GetLatestItem()
    if not item then
        return
    end

    EnsureRollBuckets(item)

    if item.traded or time() - (item.startedAt or 0) > ROLL_WINDOW_SECONDS then
        return
    end

    local rollCount = (item.rollCountByPlayer[name] or 0) + 1
    item.rollCountByPlayer[name] = rollCount

    local rollInfo = {
        rollId = item.nextRollId or 1,
        name = name,
        roll = roll,
        groupKey = groupKey,
        maxRoll = maxRoll,
        classFile = FindPlayerClass(name),
        rollCount = rollCount,
        timestamp = GetTimestamp(),
        elapsedSeconds = time() - (item.startedAt or time()),
    }
    item.nextRollId = rollInfo.rollId + 1

    table.insert(item.rolls[groupKey], rollInfo)
    RememberCurrentWinner(item)
    SaveSession()

    if SLM.frame and SLM.frame:IsShown() then
        UpdateDialog()
    end
end

local function AnnounceRollItem(itemLink)
    if not itemLink then
        return
    end

    local analysisItemLink = GetBaseItemLink(itemLink)
    local boeText = ""
    if IsBindOnEquip(analysisItemLink) then
        boeText = " BOE"
    end
    local statsText = ""
    local equipLocation = GetItemEquipLocationText(analysisItemLink)
    if GetMasterLootSettings().itemStatsEnabled and equipLocation ~= "" and not IsRecipeLikeItem(analysisItemLink) then
        local itemParts = {}
        local armorType = GetItemArmorTypeText(analysisItemLink)
        local weaponType = GetItemWeaponTypeText(analysisItemLink)
        local itemStats = GetItemStatText(analysisItemLink)
        if armorType ~= "" then
            table.insert(itemParts, armorType)
        end
        table.insert(itemParts, equipLocation)
        if weaponType ~= "" then
            table.insert(itemParts, weaponType)
        end
        if itemStats ~= "" then
            table.insert(itemParts, itemStats)
        end
        if table.getn(itemParts) > 0 then
            statsText = " " .. table.concat(itemParts, " ")
        end
    end

    SendChatMessage("Roll " .. itemLink .. boeText .. statsText, "RAID_WARNING")
end

local function HandleItemShortcut(itemLink)
    if SLM.currentView == "wishlist" then
        AddWishlistItemLink(itemLink)
    else
        AnnounceRollItem(itemLink)
    end
end

local function GetChatItemLink(link, text)
    if text and string.find(text, "|Hitem:") then
        return text
    end

    local _, itemLink = GetItemInfo(link)
    if itemLink then
        return itemLink
    end

    local itemId = ExtractItemId(link)
    if itemId then
        local itemName = ExtractItemName(text)
        if not itemName or itemName == "" or itemName == text then
            itemName = "item:" .. itemId
        end
        return "|cffffffff|H" .. link .. "|h[" .. itemName .. "]|h|r"
    end

    return nil
end

local function InstallChatItemShortcut()
    if SLM.chatItemShortcutHooked or type(SetItemRef) ~= "function" then
        return
    end

    local originalSetItemRef = SetItemRef
    SetItemRef = function(link, text, button, chatFrame)
        if button == "RightButton"
            and IsAltKeyDown()
            and IsControlKeyDown()
            and link
            and string.sub(link, 1, 5) == "item:"
        then
            local itemLink = GetChatItemLink(link, text)
            if itemLink then
                AnnounceRollItem(itemLink)
                return
            end
        end

        return originalSetItemRef(link, text, button, chatFrame)
    end

    SLM.chatItemShortcutHooked = true
end

local function IsItemShortcut(mouseButton)
    return mouseButton == "RightButton" and IsAltKeyDown() and IsControlKeyDown()
end

local function GetBagSlotFromButton(button)
    if not button then
        return nil, nil
    end

    local parent = button:GetParent()
    local bag = button.bagID or button.BagID or button.bag or button.Bag
    local slot = button.slotID or button.SlotID or button.slot or button.Slot or button:GetID()

    if not bag and parent then
        bag = parent.bagID or parent.BagID or parent.bag or parent.Bag or parent:GetID()
    end

    if not bag or not slot then
        local name = button:GetName()
        if name then
            local nameBag, nameSlot = string.match(name, "Bag(%d+)Slot(%d+)")
            bag = bag or tonumber(nameBag)
            slot = slot or tonumber(nameSlot)
        end
    end

    return tonumber(bag), tonumber(slot)
end

local function HandleItemShortcutButton(button, mouseButton)
    if not IsItemShortcut(mouseButton) then
        return
    end

    local bag, slot = GetBagSlotFromButton(button)
    if bag and slot then
        local itemLink = GetContainerItemLink(bag, slot)
        local now = GetTime()
        if SLM.lastShortcutItemLink == itemLink and SLM.lastShortcutTime and now - SLM.lastShortcutTime < 0.08 then
            return
        end
        SLM.lastShortcutItemLink = itemLink
        SLM.lastShortcutTime = now
        HandleItemShortcut(itemLink)
    end
end

local function HookItemShortcutButton(button)
    if button and not SLM.shortcutHookedButtons[button] then
        button:HookScript("OnMouseUp", function(self, mouseButton)
            HandleItemShortcutButton(self, mouseButton)
        end)
        SLM.shortcutHookedButtons[button] = true
    end
end

local function InstallItemShortcut()
    local frameCount = NUM_CONTAINER_FRAMES or 13
    local slotCount = MAX_CONTAINER_ITEMS or 36

    for frameIndex = 1, frameCount do
        for slotIndex = 1, slotCount do
            HookItemShortcutButton(_G["ContainerFrame" .. frameIndex .. "Item" .. slotIndex])
        end
    end

    for bag = 0, 4 do
        for slot = 1, slotCount do
            HookItemShortcutButton(_G["ElvUI_ContainerFrameBag" .. bag .. "Slot" .. slot])
            HookItemShortcutButton(_G["ElvUI_ContainerFrameBag" .. bag .. "Item" .. slot])
            HookItemShortcutButton(_G["ElvUI_Bag" .. bag .. "Slot" .. slot])
        end
    end
end

SLM:SetScript("OnEvent", function(_, event, message, sender, addonChannel, addonSender)
    if event == "ADDON_LOADED" then
        if message == ADDON_FOLDER or message == "SkyvasLootmaster" then
            RestoreSession()
            InstallWishlistLinkHook()
            InstallChatItemShortcut()
            RegisterVersionMessagePrefix()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        SLM.wasInRaidGroup = IsInRaidGroup() and true or false
        InstallItemShortcut()
        InstallWishlistLinkHook()
        InstallChatItemShortcut()
        RegisterVersionMessagePrefix()
        return
    end

    if event == "CHAT_MSG_ADDON" then
        HandleVersionAddonMessage(message, sender, addonChannel, addonSender)
        return
    end

    if event == "RAID_ROSTER_UPDATE" then
        HandleRaidRosterUpdate()
        return
    end

    if event == "PLAYER_LOGOUT" then
        SaveSession()
        return
    end

    if event == "TRADE_SHOW" then
        HandleTradeShow()
        return
    end

    if event == "LOOT_OPENED" then
        HandleMasterLootOpened()
        return
    end

    if event == "LOOT_CLOSED" then
        CancelMasterLootAssignments()
        return
    end

    if event == "CHAT_MSG_WHISPER" then
        HandleAssistantWhisper(message, sender)
        return
    end

    if event == "UI_INFO_MESSAGE" and message == ERR_TRADE_COMPLETE then
        HandleTradeSuccess()
        return
    end

    if event == "CHAT_MSG_RAID_WARNING" then
        local itemLink = ExtractSingleItemLink(message)
        if itemLink and not string.match(message, "^Gewinner:") and not string.match(message, "^Keine ") then
            local isWishlistItem = WishlistContainsItem(itemLink)
            local isBoePopupItem = IsWishlistBoeEnabled() and IsEpicNotSoulbound(itemLink)
            local shouldShowPopup = isWishlistItem or isBoePopupItem
            local shouldOpenDialog = not IsOnlyWishlistPopupEnabled() or shouldShowPopup
            if shouldShowPopup then
                ShowWishlistAlert()
                PlayWishlistSound()
            end
            AddItem(itemLink, shouldOpenDialog)
        end
        return
    end

    if event == "CHAT_MSG_SYSTEM" then
        local name, roll, groupKey, maxRoll = ParseSystemRoll(message)
        if name then
            AddRoll(name, roll, groupKey, maxRoll)
        end
    end
end)

SLASH_SKYVASLOOTMASTER1 = "/slm"
SLASH_SKYVASLOOTMASTER2 = "/skyvaloot"
SlashCmdList.SKYVASLOOTMASTER = function(input)
    local command = string.lower(string.match(input or "", "^%s*(.-)%s*$") or "")
    if command == "ver" or command == "version" then
        RequestRaidVersions()
        return
    end

    RestoreSession()
    CreateDialog()
    SLM.frame:Show()
    UpdateDialog()
end

SLM:RegisterEvent("ADDON_LOADED")
SLM:RegisterEvent("PLAYER_LOGIN")
SLM:RegisterEvent("PLAYER_LOGOUT")
SLM:RegisterEvent("RAID_ROSTER_UPDATE")
SLM:RegisterEvent("TRADE_SHOW")
SLM:RegisterEvent("LOOT_OPENED")
SLM:RegisterEvent("LOOT_CLOSED")
SLM:RegisterEvent("UI_INFO_MESSAGE")
SLM:RegisterEvent("CHAT_MSG_RAID_WARNING")
SLM:RegisterEvent("CHAT_MSG_SYSTEM")
SLM:RegisterEvent("CHAT_MSG_WHISPER")
SLM:RegisterEvent("CHAT_MSG_ADDON")
