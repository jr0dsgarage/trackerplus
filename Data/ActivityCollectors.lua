---@diagnostic disable: undefined-global
local _, addon = ...

-- Non-quest collectors: achievements, scenarios, professions, monthly activities, endeavors.

-- Localize hot-path globals to avoid repeated global lookups
local pairs = pairs
local ipairs = ipairs
local type = type
local tostring = tostring
local gsub = string.gsub
local max = math.max

-- Collect tracked achievements
function addon:CollectAchievements(trackables)
    local trackedAchievements = {}
    
    -- Try C_ContentTracking first (Modern API)
    if C_ContentTracking and C_ContentTracking.GetTrackedIDs then
        trackedAchievements = C_ContentTracking.GetTrackedIDs(Enum.ContentTrackingType.Achievement)
    elseif GetTrackedAchievements then
        trackedAchievements = {GetTrackedAchievements()}
    end
    
    -- Achievement details come from the global functions, not C_AchievementInfo.
    -- That namespace exists but only carries a handful of helpers
    -- (IsValidAchievement, GetRewardItemID, SetPortraitTexture and friends) -- it has
    -- no GetInfo/GetCategory/GetCategoryInfo/GetNumCriteria/GetCriteriaInfo, so the
    -- "modern API" branches that used to be here could never run.
    for _, achievementID in ipairs(trackedAchievements) do
        local id, name, description, points, completed, icon

        if GetAchievementInfo then
            local _
            id, name, points, completed, _, _, _, description, _, icon = GetAchievementInfo(achievementID)
        end

        if id then
            -- Determine Category (Minor Zone)
            local categoryName = "General"
            local categoryID
            if GetAchievementCategory then
                 categoryID = GetAchievementCategory(achievementID)
            end

            if categoryID and GetCategoryInfo then
                local catName = GetCategoryInfo(categoryID)
                if catName then categoryName = catName end
            end

            local achievementInfo = {
                type = "achievement",
                id = achievementID,
                title = name,
                description = description,
                isComplete = completed,
                icon = icon,
                points = points,
                objectives = {},
                zone = categoryName,
                color = self.db.achievementColor,
            }
            
            -- Get criteria
            local numCriteria = 0
            if GetAchievementNumCriteria then
                numCriteria = GetAchievementNumCriteria(achievementID) or 0
            end

            for i = 1, numCriteria do
                local criteriaString, criteriaCompleted, quantity, reqQuantity

                if GetAchievementCriteriaInfo then
                    local _
                    criteriaString, _, criteriaCompleted, quantity, reqQuantity = GetAchievementCriteriaInfo(achievementID, i)
                end

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
    
    -- Insert a dummy item so TrackerFrame knows to activate the Scenario section
    -- The actual rendering will now look for the Blizzard Frame instead of this data 
    -- (See TrackerFrame.lua changes)
    local scenarioInfo = {
            type = "scenario",
            id = 0,
            title = "Blizzard Scenario Frame",
            level = 0,
            zone = "Scenario",
            objectives = {},
            color = self.db.scenarioColor,
            isDummy = true
    }
    trackables[#trackables + 1] = scenarioInfo
end

-- Collect profession tracking
function addon:CollectProfessionTracking(trackables)
    self._professionReagentNameCache = self._professionReagentNameCache or {}
    local reagentNameCache = self._professionReagentNameCache
    local db = self.db

    local function GetReagentName(reagent)
        if not reagent then return nil end

        if reagent.name and reagent.name ~= "" then
            return reagent.name
        end
        if reagent.itemName and reagent.itemName ~= "" then
            return reagent.itemName
        end
        if reagent.slotText and reagent.slotText ~= "" then
            return reagent.slotText
        end

        if reagent.itemID then
            local cachedName = reagentNameCache[reagent.itemID]
            if cachedName and cachedName ~= "" then
                return cachedName
            end

            local itemName

            local getItemNameByID = C_Item and C_Item.GetItemNameByID
            if getItemNameByID then
                local ok, resolvedName = pcall(getItemNameByID, reagent.itemID)
                if ok and resolvedName and resolvedName ~= "" then
                    itemName = resolvedName
                end
            end

            if not itemName then
                local getItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
                if getItemInfo then
                    local ok, resolvedName = pcall(getItemInfo, reagent.itemID)
                    if ok and resolvedName and resolvedName ~= "" then
                        itemName = resolvedName
                    end
                end
            end

            if not itemName then
                local hyperlink = reagent.hyperlink or reagent.itemLink
                if hyperlink then
                    local linkName = hyperlink:match("%[(.+)%]")
                    if linkName and linkName ~= "" then
                        itemName = linkName
                    end
                end
            end

            if itemName and itemName ~= "" then
                reagentNameCache[reagent.itemID] = itemName
                return itemName
            end

            if C_Item and C_Item.RequestLoadItemDataByID then
                pcall(C_Item.RequestLoadItemDataByID, reagent.itemID)
            end

            return "Item " .. tostring(reagent.itemID)
        end

        if reagent.currencyID and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local currencyInfo = C_CurrencyInfo.GetCurrencyInfo(reagent.currencyID)
            if currencyInfo and currencyInfo.name and currencyInfo.name ~= "" then
                return currencyInfo.name
            end
            return "Currency " .. tostring(reagent.currencyID)
        end

        if reagent.name and reagent.name ~= "" then
            return reagent.name
        end

        return nil
    end

    local function GetReagentOwnedCount(reagent)
        if not reagent then return 0 end

        if reagent.itemID then
            local itemID = reagent.itemID

            -- Prefer modern API path which can include Warbank counts.
            if C_Item and C_Item.GetItemCount then
                -- Compute total from known-good combinations used by other addons:
                -- bags + (bank - bags) + (warbank - bags)
                local okBag, bagQuantity = pcall(C_Item.GetItemCount, itemID, false, false, false, false)
                local okWarbank, bagAndWarbankQuantity = pcall(C_Item.GetItemCount, itemID, false, false, false, true)
                local okBank, bagAndBankQuantity = pcall(C_Item.GetItemCount, itemID, true, false, true, false)

                if okBag and okWarbank and okBank then
                    bagQuantity = bagQuantity or 0
                    bagAndWarbankQuantity = bagAndWarbankQuantity or 0
                    bagAndBankQuantity = bagAndBankQuantity or 0

                    local warbankQuantity = max(0, bagAndWarbankQuantity - bagQuantity)
                    local bankQuantity = max(0, bagAndBankQuantity - bagQuantity)

                    return bagQuantity + bankQuantity + warbankQuantity
                end

                -- Fallback: try direct full include call where supported.
                local okTotal, totalQuantity = pcall(C_Item.GetItemCount, itemID, true, false, true, true)
                if okTotal and totalQuantity then
                    return totalQuantity
                end
            end

            -- Legacy fallback, for clients that still have the old global. On
            -- current clients GetItemCount only exists under C_Item, so calling the
            -- bare global would raise "attempt to call a nil value".
            local getItemCount = (C_Item and C_Item.GetItemCount) or GetItemCount
            if getItemCount then
                local okLegacy, legacyQuantity = pcall(getItemCount, itemID, true, false, true, true)
                if okLegacy and legacyQuantity then
                    return legacyQuantity
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
        if reagentSlotSchematic and reagentSlotSchematic.GetQuantityRequired and reagent then
            local ok, quantity = pcall(function()
                return reagentSlotSchematic:GetQuantityRequired(reagent)
            end)
            if ok and quantity then
                return quantity
            end
        end

        return (reagentSlotSchematic and reagentSlotSchematic.quantityRequired) or 1
    end

    local function BuildRecipeObjectives(schematic)
        local objectives = {}
        local reagentTotals = {}

        if not schematic or not schematic.reagentSlotSchematics then
            return objectives
        end

        for _, reagentSlotSchematic in ipairs(schematic.reagentSlotSchematics) do
            local isRequired = reagentSlotSchematic.required and true or false

            if isRequired and reagentSlotSchematic.reagents and #reagentSlotSchematic.reagents > 0 then
                local reagent = reagentSlotSchematic.reagents[1]
                local reagentName = GetReagentName(reagent)
                local quantityRequired = GetSlotQuantityRequired(reagentSlotSchematic, reagent)

                if reagentName and quantityRequired and quantityRequired > 0 then
                    local reagentKey
                    if reagent.itemID then
                        reagentKey = "item:" .. reagent.itemID
                    elseif reagent.currencyID then
                        reagentKey = "currency:" .. reagent.currencyID
                    else
                        reagentKey = "name:" .. reagentName
                    end

                    if not reagentTotals[reagentKey] then
                        reagentTotals[reagentKey] = {
                            name = reagentName,
                            required = 0,
                            owned = GetReagentOwnedCount(reagent),
                        }
                    end

                    reagentTotals[reagentKey].required = reagentTotals[reagentKey].required + quantityRequired
                end
            elseif isRequired and reagentSlotSchematic.slotInfo and reagentSlotSchematic.slotInfo.slotText then
                local slotText = reagentSlotSchematic.slotInfo.slotText
                local quantityRequired = reagentSlotSchematic.quantityRequired or 1
                objectives[#objectives + 1] = {
                    text = slotText,
                    finished = false,
                    numFulfilled = 0,
                    numRequired = quantityRequired,
                }
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

        table.sort(objectives, function(a, b)
            return (a.text or "") < (b.text or "")
        end)

        return objectives
    end

    -- Helper to add recipes
    local function AddRecipes(isRecraft)
        local trackedRecipes = C_TradeSkillUI.GetRecipesTracked(isRecraft) or {}
        
        for _, recipeID in ipairs(trackedRecipes) do
            local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, isRecraft)
            if schematic then
                local professionInfo = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
                local professionName = professionInfo and professionInfo.professionName or "Professions"
                local objectives = BuildRecipeObjectives(schematic)
                
                trackables[#trackables + 1] = {
                    type = "profession",
                    id = recipeID,
                    title = schematic.name,
                    level = 0, -- Recipes don't really have levels like quests
                    zone = professionName,
                    isRecraft = isRecraft,
                    objectives = objectives,
                    color = db.professionColor
                }
            end
        end
    end

    AddRecipes(false)
    AddRecipes(true)
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
            local isComplete = info.completed
            
            -- If not complete, show progress
            if not isComplete then
                local progress = info.progress or 0
                local required = info.threshold or 1
                
                objectives[#objectives + 1] = {
                    text = info.activityName,
                    finished = isComplete,
                    numFulfilled = progress,
                    numRequired = required,
                    flags = 0 -- Default
                }
            end
            
            trackables[#trackables + 1] = {
                type = "monthly",
                id = activityID,
                title = info.activityName,
                level = 0,
                zone = "Traveler's Log",
                isComplete = isComplete,
                objectives = objectives,
                color = self.db.monthlyColor -- Cyan-ish
            }
        end
    end
end

-- Collect Endeavors (Housing)
function addon:CollectEndeavors(trackables)
     -- C_NeighborhoodInitiative (Housing API)
     if C_NeighborhoodInitiative and C_NeighborhoodInitiative.GetTrackedInitiativeTasks then
          local trackerData = C_NeighborhoodInitiative.GetTrackedInitiativeTasks()
          local trackedIDs = {}
          local useCache = false
          
          -- Try to get live data
          if trackerData and trackerData.trackedIDs and #trackerData.trackedIDs > 0 then
               trackedIDs = trackerData.trackedIDs
               -- Update cache
               self.db.endeavorCache = {}
               for _, id in ipairs(trackedIDs) do
                   self.db.endeavorCache[id] = true
               end
          else
               -- Fallback to cache if live data missing (common on login)
               useCache = true
               if self.db.endeavorCache then
                   for id, _ in pairs(self.db.endeavorCache) do
                       trackedIDs[#trackedIDs + 1] = id
                   end
               end
          end
          
          for _, id in ipairs(trackedIDs) do
              local info = C_NeighborhoodInitiative.GetInitiativeTaskInfo(id)
              
              if info and not info.completed then
                  local objectives = {}
                  
                  if info.requirementsList then
                      for _, req in ipairs(info.requirementsList) do
                          local reqText = req.requirementText
                          if reqText then
                              -- Clean up text formatting
                              -- Remove leading dashes to prevent double dashes in tracker
                              reqText = reqText:gsub("^%s*-%s*", "")
                              reqText = gsub(reqText, " / ", "/") 
                              
                              local isFinished = req.completed
                              if not isFinished then
                                  objectives[#objectives + 1] = {
                                      text = reqText,
                                      finished = isFinished
                                  }
                              end
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
                       color = self.db.endeavorColor -- Warm Pink
                  }
              end
          end
     end
end
