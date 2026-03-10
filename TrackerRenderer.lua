local addonName, addon = ...

-- Localize hot-path globals
local ipairs, tostring, tonumber = ipairs, tostring, tonumber
local format = string.format
local max = math.max
local C_SuperTrack = C_SuperTrack

-- Local aliases for addon utilities (available after RendererUtils.lua loads)
local ClearArray = function(t) return addon.ClearArray(t) end
local DebugLayout = function(...) return addon.DebugLayout(...) end

-------------------------------------------------------------------------------
-- UpdateTrackerDisplay — Main orchestrator
-- Categorises incoming trackables and delegates rendering to section files.
-------------------------------------------------------------------------------
function addon:UpdateTrackerDisplay(trackables)
    local trackerFrame = self.trackerFrame
    local contentFrame = self.contentFrame

    if not trackerFrame or not contentFrame then
        return
    end

    -- Invalidate layout signature so anchors are always recalculated this frame.
    self._layoutSignature = nil

    self:ResetButtonPool()

    local db = self.db
    local incomingCount = #trackables

    --------------------------------------------------------------------------
    -- Categorise trackables into temporary arrays
    --------------------------------------------------------------------------
    self._tmpScenarios            = self._tmpScenarios            or {}
    self._tmpAutoQuests           = self._tmpAutoQuests           or {}
    self._tmpSuperTrackedItems    = self._tmpSuperTrackedItems    or {}
    self._tmpCampaignItems        = self._tmpCampaignItems        or {}
    self._tmpBonusObjectives      = self._tmpBonusObjectives      or {}
    self._tmpWorldQuestItems      = self._tmpWorldQuestItems      or {}
    self._tmpRemainingTrackables  = self._tmpRemainingTrackables  or {}
    self._tmpQuestItemDataByID    = self._tmpQuestItemDataByID    or {}

    local scenarios          = self._tmpScenarios
    local autoQuests         = self._tmpAutoQuests
    local superTrackedItems  = self._tmpSuperTrackedItems
    local campaignItems      = self._tmpCampaignItems
    local bonusObjectives    = self._tmpBonusObjectives
    local worldQuestItems    = self._tmpWorldQuestItems
    local remainingTrackables = self._tmpRemainingTrackables
    local questItemDataByID  = self._tmpQuestItemDataByID

    ClearArray(scenarios)
    ClearArray(autoQuests)
    ClearArray(superTrackedItems)
    ClearArray(campaignItems)
    ClearArray(bonusObjectives)
    ClearArray(worldQuestItems)
    ClearArray(remainingTrackables)
    ClearArray(questItemDataByID)

    local superTrackedQuestID = (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID()) or 0
    self._cachedSuperTrackedQuestID = superTrackedQuestID

    for _, item in ipairs(trackables) do
        if item.id and item.item and (item.item.link or item.item.texture) then
            questItemDataByID[item.id] = item.item
        end

        if item.type == "scenario" then
            scenarios[#scenarios + 1] = item
        elseif item.type == "autoquest" then
            autoQuests[#autoQuests + 1] = item
        elseif item.type == "supertrack" then
            if superTrackedQuestID > 0
                and item.id
                and item.id == superTrackedQuestID
                and item.title
                and item.title ~= "" then
                superTrackedItems[#superTrackedItems + 1] = item
            end
        elseif item.type == "campaign" then
            campaignItems[#campaignItems + 1] = item
        elseif item.type == "bonus" then
            bonusObjectives[#bonusObjectives + 1] = item
        elseif item.type == "worldquest" then
            worldQuestItems[#worldQuestItems + 1] = item
        else
            remainingTrackables[#remainingTrackables + 1] = item
        end
    end

    -- Ensure super-tracked items have quest-item data if available
    if #superTrackedItems > 0 then
        for i = 1, #superTrackedItems do
            local item = superTrackedItems[i]
            if item and item.id and (not item.item or (not item.item.link and not item.item.texture)) then
                local sharedItemData = questItemDataByID[item.id]
                if sharedItemData then
                    item.item = sharedItemData
                end
            end
        end
    end

    self.currentScenarios = scenarios
    trackables = remainingTrackables

    -- Group trackables if needed
    if db.groupByZone or db.groupByCategory then
        trackables = self:OrganizeTrackables(trackables)
    end

    --------------------------------------------------------------------------
    -- Delegate to section renderers
    --------------------------------------------------------------------------

    -- Auto-quest popups (stolen from Blizzard frames)
    self:RenderAutoQuestSection(autoQuests)

    -- Scenario / Delve / Dungeon
    local scenarioYOffset = self:RenderScenarioSection()

    -- Active (super-tracked) quest
    local aqYOffset = self:RenderActiveQuestSection(superTrackedItems)

    -- Campaign quests (dedicated pinned section below Active Quest)
    local campaignYOffset = self:RenderCampaignSection(campaignItems)

    -- Bonus objectives
    local bonusYOffset = self:RenderBonusSection(bonusObjectives)

    -- World quests
    local wqYOffset = self:RenderWorldQuestSection(worldQuestItems)

    --------------------------------------------------------------------------
    -- Update Scenario Frame Height
    --------------------------------------------------------------------------
    if scenarioYOffset > 0 then
        self.scenarioFrame:SetHeight(scenarioYOffset)
        if addon.db.minimized then
            self.scenarioFrame:Hide()
        else
            self.scenarioFrame:Show()
        end
    else
        self.scenarioFrame:Hide()
    end

    --------------------------------------------------------------------------
    -- Update layout anchors (scenario, autoquest, scroll, bonus, wq)
    --------------------------------------------------------------------------
    self:UpdateLayoutAnchors()

    DebugLayout(self,
        "anchors scenY=%d aqY=%d campY=%d bonusY=%d wqY=%d autoQH=%.1f",
        tonumber(scenarioYOffset or 0),
        tonumber(aqYOffset or 0),
        tonumber(campaignYOffset or 0),
        tonumber(bonusYOffset or 0),
        tonumber(wqYOffset or 0),
        tonumber((self.autoQuestFrame and self.autoQuestFrame.GetHeight and self.autoQuestFrame:GetHeight()) or 0)
    )

    --------------------------------------------------------------------------
    -- Normal trackables (headers + quest items inside scroll content frame)
    --------------------------------------------------------------------------
    local renderedNormalItems, renderedHeaders, yOffset =
        self:RenderNormalTrackables(trackables, contentFrame)

    --------------------------------------------------------------------------
    -- Blank-body diagnostic logging
    --------------------------------------------------------------------------
    local bodyAppearsBlank = (renderedNormalItems == 0 and renderedHeaders == 0 and yOffset <= 7)
    if bodyAppearsBlank then
        local now = GetTime and GetTime() or 0
        if not self._lastBlankLayoutLogAt or (now - self._lastBlankLayoutLogAt) > 0.75 then
            self._lastBlankLayoutLogAt = now
            DebugLayout(self,
                "BLANK body incoming=%d organized=%d scenData=%d scenY=%d bonus=%d bonusY=%d wq=%d wqY=%d autoQ=%d scrollShown=%s contentH=%.1f",
                tonumber(incomingCount or 0),
                tonumber(#trackables or 0),
                tonumber((self.currentScenarios and #self.currentScenarios) or 0),
                tonumber(scenarioYOffset or 0),
                tonumber(#bonusObjectives or 0),
                tonumber(bonusYOffset or 0),
                tonumber(#worldQuestItems or 0),
                tonumber(wqYOffset or 0),
                tonumber(#autoQuests or 0),
                tostring(self.scrollFrame and self.scrollFrame:IsShown()),
                tonumber((contentFrame and contentFrame.GetHeight and contentFrame:GetHeight()) or 0)
            )
        end
    end

    --------------------------------------------------------------------------
    -- Finalize
    --------------------------------------------------------------------------
    contentFrame:SetHeight(max(yOffset, self.db.frameHeight))

    -- Update scroll shadow gradients based on new content size
    self:UpdateScrollShadows()

    -- Hide only unused pooled buttons after this frame has been fully rendered.
    self:FinalizeButtonPool()

    -- Update tracker frame appearance
    self:UpdateTrackerAppearance()

    -- Optional visual debug overlays for section layout troubleshooting
    self:UpdateSectionDebugBoxes()
end

-- Show trackable tooltip
function addon:ShowTrackableTooltip(button, trackable)
    if not trackable then return end

    local tooltip = addon:AcquireTooltip(button, "ANCHOR_RIGHT")

    if trackable.type == "quest" or trackable.type == "campaign" or trackable.type == "supertrack" or trackable.type == "worldquest" then
        tooltip:SetText(trackable.title or "Quest")

        if trackable.level then
            tooltip:AddLine(format("Level %d", trackable.level), 0.82, 0.82, 0.82)
        end

        if trackable.zone and trackable.zone ~= "" then
            tooltip:AddLine(trackable.zone, 0.5, 0.8, 1)
        end

        if trackable.objectives and #trackable.objectives > 0 then
            tooltip:AddLine(" ")
            for i, objective in ipairs(trackable.objectives) do
                if i > 8 then
                    break
                end
                local text = objective and objective.text
                if text and text ~= "" then
                    if objective.finished then
                        tooltip:AddLine("• " .. text, 0.5, 1, 0.5, true)
                    else
                        tooltip:AddLine("• " .. text, 1, 1, 1, true)
                    end
                end
            end
        end
    elseif trackable.type == "achievement" then
        tooltip:SetText(trackable.title)
        if trackable.description then
            tooltip:AddLine(trackable.description, 1, 1, 1, true)
        end
        tooltip:AddLine(" ")
        tooltip:AddLine(format("%d points", trackable.points or 0), 1, 0.82, 0)
    end

    tooltip:Show()
end
