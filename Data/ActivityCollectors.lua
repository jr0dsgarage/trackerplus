---@diagnostic disable: undefined-global
local _, addon = ...

-- Non-quest collectors: achievements, scenarios, professions, monthly activities, endeavors.

-- Localize hot-path globals to avoid repeated global lookups
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local tostring = tostring
local gsub = string.gsub
local max = math.max

-- Collect tracked achievements
function addon:CollectAchievements(trackables)
    -- Achievement details come from the global functions, not C_AchievementInfo.
    -- That namespace exists but only carries a handful of helpers
    -- (IsValidAchievement, GetRewardItemID, SetPortraitTexture and friends) -- it has
    -- no GetInfo/GetCategory/GetCategoryInfo/GetNumCriteria/GetCriteriaInfo.
    -- Clients without achievements have none of these globals.
    if not GetAchievementInfo then return end

    local trackedAchievements
    -- Try C_ContentTracking first (Modern API)
    if C_ContentTracking and C_ContentTracking.GetTrackedIDs then
        trackedAchievements = C_ContentTracking.GetTrackedIDs(Enum.ContentTrackingType.Achievement)
    elseif GetTrackedAchievements then
        trackedAchievements = {GetTrackedAchievements()}
    end
    if not trackedAchievements then return end
    
    for _, achievementID in ipairs(trackedAchievements) do
        local id, name, points, completed, _, _, _, description = GetAchievementInfo(achievementID)

        if id then
            -- Determine Category (Minor Zone)
            local categoryID = GetAchievementCategory(achievementID)
            local categoryName = categoryID and GetCategoryInfo(categoryID) or "General"

            local achievementInfo = {
                type = "achievement",
                id = achievementID,
                title = name,
                description = description,
                isComplete = completed,
                points = points,
                objectives = {},
                zone = categoryName,
                color = self.db.achievementColor,
            }
            
            -- Get criteria
            for i = 1, GetAchievementNumCriteria(achievementID) or 0 do
                local criteriaString, _, criteriaCompleted, quantity, reqQuantity = GetAchievementCriteriaInfo(achievementID, i)

                if criteriaString then
                    achievementInfo.objectives[#achievementInfo.objectives + 1] = {
                        text = criteriaString,
                        finished = criteriaCompleted,
                        numFulfilled = quantity,
                        numRequired = reqQuantity,
                    }
                end
            end

            trackables[#trackables + 1] = achievementInfo
        end
    end
end

-- Collect scenario objectives
function addon:CollectScenarioObjectives(trackables)
    -- If we are using the Blizzard frame (which is the plan now), we don't need to manually collect items
    -- However, we still need to detect attendance so the core loop knows we have "scenarios" to trigger the layout logic.
    if not self:IsAnyScenarioTrackerActive() then
        return
    end
    
    -- Insert a placeholder item so the Scenario section activates. RenderScenario.lua
    -- draws the borrowed Blizzard frame, not this data.
    trackables[#trackables + 1] = {
        type = "scenario",
        id = 0,
        title = "Blizzard Scenario Frame",
        level = 0,
        zone = "Scenario",
        objectives = {},
        color = self.db.scenarioColor,
        isDummy = true,
    }
end

-- Profession tracking -----------------------------------------------------------

-- itemID -> item name, kept across passes (names never change).
local reagentNameCache = {}

local function GetReagentName(reagent)
    if reagent.name and reagent.name ~= "" then
        return reagent.name
    end
    if reagent.itemName and reagent.itemName ~= "" then
        return reagent.itemName
    end
    if reagent.slotText and reagent.slotText ~= "" then
        return reagent.slotText
    end

    local itemID = reagent.itemID
    if itemID then
        local cachedName = reagentNameCache[itemID]
        if cachedName then
            return cachedName
        end

        local itemName

        local getItemNameByID = C_Item and C_Item.GetItemNameByID
        if getItemNameByID then
            local ok, resolvedName = pcall(getItemNameByID, itemID)
            if ok and resolvedName and resolvedName ~= "" then
                itemName = resolvedName
            end
        end

        if not itemName then
            local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
            if getItemInfo then
                local ok, resolvedName = pcall(getItemInfo, itemID)
                if ok and resolvedName and resolvedName ~= "" then
                    itemName = resolvedName
                end
            end
        end

        if not itemName then
            local hyperlink = reagent.hyperlink or reagent.itemLink
            local linkName = hyperlink and hyperlink:match("%[(.+)%]")
            if linkName and linkName ~= "" then
                itemName = linkName
            end
        end

        if itemName then
            reagentNameCache[itemID] = itemName
            return itemName
        end

        -- Not loaded yet; GET_ITEM_INFO_RECEIVED re-collects professions when it is.
        if C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, itemID)
        end

        return "Item " .. tostring(itemID)
    end

    if reagent.currencyID and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(reagent.currencyID)
        if currencyInfo and currencyInfo.name and currencyInfo.name ~= "" then
            return currencyInfo.name
        end
        return "Currency " .. tostring(reagent.currencyID)
    end

    return nil
end

local function GetReagentOwnedCount(reagent)
    local itemID = reagent.itemID
    if itemID then
        local cItemGetItemCount = C_Item and C_Item.GetItemCount
        if cItemGetItemCount then
            -- Prefer the modern API, which can include Warbank counts. Total is
            -- bags + (bank - bags) + (warbank - bags), the combination other addons use.
            local okBag, bagQuantity = pcall(cItemGetItemCount, itemID, false, false, false, false)
            local okWarbank, bagAndWarbankQuantity = pcall(cItemGetItemCount, itemID, false, false, false, true)
            local okBank, bagAndBankQuantity = pcall(cItemGetItemCount, itemID, true, false, true, false)

            if okBag and okWarbank and okBank then
                bagQuantity = bagQuantity or 0
                local warbankQuantity = max(0, (bagAndWarbankQuantity or 0) - bagQuantity)
                local bankQuantity = max(0, (bagAndBankQuantity or 0) - bagQuantity)
                return bagQuantity + bankQuantity + warbankQuantity
            end
        end

        -- Fallback: a single full-include call, then the plain one. On current
        -- clients GetItemCount only exists under C_Item; older ones have the global.
        local getItemCount = cItemGetItemCount or GetItemCount
        if getItemCount then
            local okTotal, totalQuantity = pcall(getItemCount, itemID, true, false, true, true)
            if okTotal and totalQuantity then
                return totalQuantity
            end

            local okBasic, basicQuantity = pcall(getItemCount, itemID)
            if okBasic and basicQuantity then
                return basicQuantity
            end
        end

        return 0
    end

    if reagent.currencyID and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(reagent.currencyID)
        return (currencyInfo and currencyInfo.quantity) or 0
    end

    return 0
end

local function GetSlotQuantityRequired(reagentSlotSchematic, reagent)
    if reagentSlotSchematic.GetQuantityRequired then
        local ok, quantity = pcall(reagentSlotSchematic.GetQuantityRequired, reagentSlotSchematic, reagent)
        if ok and quantity then
            return quantity
        end
    end

    return reagentSlotSchematic.quantityRequired or 1
end

local function SortObjectivesByText(a, b)
    return (a.text or "") < (b.text or "")
end

local function BuildRecipeObjectives(schematic)
    local objectives = {}
    if not schematic.reagentSlotSchematics then
        return objectives
    end

    local reagentTotals = {}

    for _, reagentSlotSchematic in ipairs(schematic.reagentSlotSchematics) do
        if reagentSlotSchematic.required then
            local reagent = reagentSlotSchematic.reagents and reagentSlotSchematic.reagents[1]
            if reagent then
                local reagentName = GetReagentName(reagent)
                local quantityRequired = GetSlotQuantityRequired(reagentSlotSchematic, reagent)

                if reagentName and quantityRequired > 0 then
                    local reagentKey
                    if reagent.itemID then
                        reagentKey = "item:" .. reagent.itemID
                    elseif reagent.currencyID then
                        reagentKey = "currency:" .. reagent.currencyID
                    else
                        reagentKey = "name:" .. reagentName
                    end

                    local total = reagentTotals[reagentKey]
                    if not total then
                        total = { name = reagentName, required = 0, owned = GetReagentOwnedCount(reagent) }
                        reagentTotals[reagentKey] = total
                    end
                    total.required = total.required + quantityRequired
                end
            elseif reagentSlotSchematic.slotInfo and reagentSlotSchematic.slotInfo.slotText then
                objectives[#objectives + 1] = {
                    text = reagentSlotSchematic.slotInfo.slotText,
                    finished = false,
                    numFulfilled = 0,
                    numRequired = reagentSlotSchematic.quantityRequired or 1,
                }
            end
        end
    end

    for _, data in pairs(reagentTotals) do
        objectives[#objectives + 1] = {
            text = data.name,
            finished = data.owned >= data.required,
            numFulfilled = data.owned,
            numRequired = data.required,
        }
    end

    table.sort(objectives, SortObjectivesByText)

    return objectives
end

local function AddTrackedRecipes(trackables, isRecraft, color)
    for _, recipeID in ipairs(C_TradeSkillUI.GetRecipesTracked(isRecraft) or {}) do
        local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, isRecraft)
        if schematic then
            local professionInfo = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)

            trackables[#trackables + 1] = {
                type = "profession",
                id = recipeID,
                title = schematic.name,
                level = 0, -- Recipes don't really have levels like quests
                zone = professionInfo and professionInfo.professionName or "Professions",
                isRecraft = isRecraft,
                objectives = BuildRecipeObjectives(schematic),
                color = color,
            }
        end
    end
end

-- Collect profession tracking
function addon:CollectProfessionTracking(trackables)
    AddTrackedRecipes(trackables, false, self.db.professionColor)
    AddTrackedRecipes(trackables, true, self.db.professionColor)
end

-- Collect monthly activities (Trading Post / Traveler's Log)
--
-- Tracked activities live in C_PerksActivities, not C_PerksProgram. C_PerksProgram
-- is the vendor/shop side of the feature and has no GetTrackedPerksActivities or
-- GetPerksActivityInfo, so the old code silently collected nothing -- and would have
-- raised "attempt to call a nil value" on the first activity if the
-- C_ContentTracking fallback ever did return ids.
function addon:CollectMonthlyActivities(trackables)
    local activities = C_PerksActivities
    local getActivityInfo = activities and activities.GetPerksActivityInfo
    if not getActivityInfo then return end

    local trackedIDs
    if activities.GetTrackedPerksActivities then
        trackedIDs = activities.GetTrackedPerksActivities()
    elseif C_ContentTracking and C_ContentTracking.GetTrackedIDs and Enum and Enum.ContentTrackingType and Enum.ContentTrackingType.PerksActivity then
        trackedIDs = C_ContentTracking.GetTrackedIDs(Enum.ContentTrackingType.PerksActivity)
    end

    if not trackedIDs then return end

    for _, activityID in ipairs(trackedIDs) do
        local info = getActivityInfo(activityID)
        if info then
            local objectives = {}
            
            -- If not complete, show progress
            if not info.completed then
                objectives[1] = {
                    text = info.activityName,
                    finished = false,
                    numFulfilled = info.progress or 0,
                    numRequired = info.threshold or 1,
                }
            end
            
            trackables[#trackables + 1] = {
                type = "monthly",
                id = activityID,
                title = info.activityName,
                level = 0,
                zone = "Traveler's Log",
                isComplete = info.completed,
                objectives = objectives,
                color = self.db.monthlyColor,
            }
        end
    end
end

-- Collect Endeavors (Housing)
function addon:CollectEndeavors(trackables)
    if not (C_NeighborhoodInitiative and C_NeighborhoodInitiative.GetTrackedInitiativeTasks) then
        return
    end

    local trackerData = C_NeighborhoodInitiative.GetTrackedInitiativeTasks()
    local trackedIDs
    local cache = self.db.endeavorCache

    if trackerData and trackerData.trackedIDs and #trackerData.trackedIDs > 0 then
        -- Live data: remember it for next login.
        trackedIDs = trackerData.trackedIDs
        wipe(cache)
        for _, id in ipairs(trackedIDs) do
            cache[id] = true
        end
    else
        -- Live data is often missing on login; fall back to the last known set.
        trackedIDs = {}
        for id in pairs(cache) do
            trackedIDs[#trackedIDs + 1] = id
        end
    end

    for _, id in ipairs(trackedIDs) do
        local info = C_NeighborhoodInitiative.GetInitiativeTaskInfo(id)

        if info and not info.completed then
            local objectives = {}

            if info.requirementsList then
                for _, req in ipairs(info.requirementsList) do
                    local reqText = req.requirementText
                    if reqText and not req.completed then
                        -- Strip leading dashes (the tracker adds its own) and tighten " / ".
                        reqText = gsub(reqText, "^%s*-%s*", "")
                        reqText = gsub(reqText, " / ", "/")
                        objectives[#objectives + 1] = {
                            text = reqText,
                            finished = false,
                        }
                    end
                end
            end

            trackables[#trackables + 1] = {
                type = "endeavor",
                id = info.ID or id,
                title = info.taskName or ("Endeavor " .. id),
                level = 0,
                zone = "Housing",
                objectives = objectives,
                color = self.db.endeavorColor,
            }
        end
    end
end
