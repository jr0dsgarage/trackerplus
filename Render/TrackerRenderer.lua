local addonName, addon = ...

-- Localize hot-path globals
local ipairs, type, tostring, tonumber = ipairs, type, tostring, tonumber
local wipe = wipe
local format = string.format
local max = math.max
local GetTime = GetTime
local C_SuperTrack = C_SuperTrack

local DebugLayout = addon.DebugLayout

-- Per-pass categorisation buckets, reused across renders.
local scenarios           = {}
local autoQuests          = {}
local superTrackedItems   = {}
local campaignItems       = {}
local bonusObjectives     = {}
local worldQuestItems     = {}
local remainingTrackables = {}
local questItemDataByID   = {} -- keyed by quest ID

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
    -- Diagnostics below only build their arguments when they will be logged.
    local layoutTrace = db.layoutDebug and self:ShouldLog("trace")

    --------------------------------------------------------------------------
    -- Categorise trackables
    --------------------------------------------------------------------------
    wipe(scenarios)
    wipe(autoQuests)
    wipe(superTrackedItems)
    wipe(campaignItems)
    wipe(bonusObjectives)
    wipe(worldQuestItems)
    wipe(remainingTrackables)
    wipe(questItemDataByID)

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
    for _, item in ipairs(superTrackedItems) do
        if not item.item or (not item.item.link and not item.item.texture) then
            local sharedItemData = questItemDataByID[item.id]
            if sharedItemData then
                item.item = sharedItemData
            end
        end
    end

    self.currentScenarios = scenarios
    trackables = remainingTrackables

    -- Carry the last pass's viewport width in before anything measures against the
    -- content frame, so text wrapping and row heights are computed at the width the
    -- rows will actually be drawn at.
    self:UpdateContentWidth()

    -- Group into major (type) and minor (zone/category) headers
    trackables = self:OrganizeTrackables(trackables)

    --------------------------------------------------------------------------
    -- Delegate to section renderers
    --------------------------------------------------------------------------

    -- Auto-quest popups (borrowed from Blizzard frames)
    self:RenderAutoQuestSection(autoQuests)

    -- Scenario / Delve / Dungeon
    local scenarioYOffset = self:RenderScenarioSection()

    -- Active (super-tracked) quest
    local aqYOffset = self:RenderActiveQuestSection(superTrackedItems)

    -- Follow the Arrow guide (between Active Quest and Campaign)
    self:RenderFollowTheArrowSection()

    -- Campaign quests (dedicated pinned section below Active Quest)
    local campaignYOffset = self:RenderCampaignSection(campaignItems)

    -- Bonus objectives
    local bonusYOffset = self:RenderBonusSection(bonusObjectives)

    -- World quests
    local wqYOffset = self:RenderWorldQuestSection(worldQuestItems)

    self:FinishPinnedSection(self.scenarioFrame, scenarioYOffset)

    --------------------------------------------------------------------------
    -- Update layout anchors (scenario, autoquest, scroll, bonus, wq)
    --------------------------------------------------------------------------
    self:UpdateLayoutAnchors()

    -- The anchors above are what set the scroll viewport's width, so the content it
    -- scrolls can only be matched to it afterwards. Headers and rows anchor to both
    -- edges of the content frame, so they pick the corrected width up immediately.
    self:UpdateContentWidth()

    if self:ShouldLog("trace") then
        self:LogAt("trace", "[AQ-POST-LAYOUT] height after UpdateLayoutAnchors: %.1f shown=%s", self.autoQuestFrame:GetHeight() or 0, tostring(self.autoQuestFrame:IsShown()))
        self:LogAt("trace", "[CQ-POST-LAYOUT] height after UpdateLayoutAnchors: %.1f shown=%s", self.completedQuestFrame:GetHeight() or 0, tostring(self.completedQuestFrame:IsShown()))
    end

    if layoutTrace then
        DebugLayout(self,
            "anchors scenY=%d aqY=%d campY=%d bonusY=%d wqY=%d autoQH=%.1f cqH=%.1f",
            scenarioYOffset, aqYOffset, campaignYOffset, bonusYOffset, wqYOffset,
            self.autoQuestFrame:GetHeight() or 0,
            self.completedQuestFrame:GetHeight() or 0
        )
    end

    --------------------------------------------------------------------------
    -- Normal trackables (headers + quest items inside scroll content frame)
    --------------------------------------------------------------------------
    local renderedNormalItems, renderedHeaders, yOffset =
        self:RenderNormalTrackables(trackables, contentFrame)

    --------------------------------------------------------------------------
    -- Blank-body diagnostic logging
    --------------------------------------------------------------------------
    local bodyAppearsBlank = (renderedNormalItems == 0 and renderedHeaders == 0 and yOffset <= 7)
    if bodyAppearsBlank and layoutTrace then
        local now = GetTime()
        if not self._lastBlankLayoutLogAt or (now - self._lastBlankLayoutLogAt) > 0.75 then
            self._lastBlankLayoutLogAt = now
            DebugLayout(self,
                "BLANK body incoming=%d organized=%d scenData=%d scenY=%d bonus=%d bonusY=%d wq=%d wqY=%d autoQ=%d scrollShown=%s contentH=%.1f",
                incomingCount, #trackables, #scenarios, scenarioYOffset,
                #bonusObjectives, bonusYOffset, #worldQuestItems, wqYOffset, #autoQuests,
                tostring(self.scrollFrame:IsShown()),
                contentFrame:GetHeight() or 0
            )
        end
    end

    --------------------------------------------------------------------------
    -- Finalize
    --------------------------------------------------------------------------
    -- Exactly the rendered height: the scroll viewport is shorter than frameHeight (the
    -- header and pinned sections take their share), so any padding here scrolls as blank space.
    contentFrame:SetHeight(max(yOffset, 1))

    -- Content can shrink while scrolled down; keep the view inside the new range.
    local scrollFrame = self.scrollFrame
    scrollFrame:UpdateScrollChildRect()
    local maxScroll = scrollFrame:GetVerticalScrollRange()
    if scrollFrame:GetVerticalScroll() > maxScroll then
        scrollFrame:SetVerticalScroll(maxScroll)
    end

    -- Update scroll shadow gradients based on new content size
    self:UpdateScrollShadows()

    -- Hide only unused pooled buttons after this frame has been fully rendered.
    self:FinalizeButtonPool()

    -- Update tracker frame appearance
    self:UpdateTrackerAppearance()

    -- Optional visual debug overlays for section layout troubleshooting
    self:UpdateSectionDebugBoxes()
end

local TOOLTIP_DONE_COLOR = { r = 0.5, g = 1, b = 0.5 }
local TOOLTIP_OPEN_COLOR = { r = 1, g = 1, b = 1 }

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

        -- Add quest objective summary — fetched fresh on each hover so it never goes stale
        local objectiveSummary = addon:GetQuestObjectiveText(trackable.id, trackable.logIndex)
        if objectiveSummary and objectiveSummary ~= "" then
            tooltip:AddLine(" ")
            tooltip:AddLine(objectiveSummary, 0.9, 0.9, 0.9, true)
        end

        if trackable.objectives and #trackable.objectives > 0 then
            local addedSpacer = false
            for i, objective in ipairs(trackable.objectives) do
                if i > 5 then
                    break
                end
                local text = objective and objective.text
                -- Quests without countable objectives show the summary as their
                -- only objective line; don't print it twice.
                if text and text ~= "" and text ~= objectiveSummary then
                    if not addedSpacer then
                        tooltip:AddLine(" ")
                        addedSpacer = true
                    end
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

        if trackable.objectives and #trackable.objectives > 0 then
            tooltip:AddLine(" ")
            for i, objective in ipairs(trackable.objectives) do
                if i > 8 then
                    break
                end

                local parsed = addon.ParseObjectiveDisplay(trackable, objective, i)
                local lineColor = objective.finished and TOOLTIP_DONE_COLOR or TOOLTIP_OPEN_COLOR
                local bodyText = parsed.bodyText
                local titleMatches = type(bodyText) == "string"
                    and type(trackable.title) == "string"
                    and bodyText == trackable.title
                if (type(bodyText) ~= "string" or bodyText:match("%S") == nil or titleMatches) and type(objective.text) == "string" and objective.text:match("%S") then
                    bodyText = objective.text
                end
                titleMatches = type(bodyText) == "string"
                    and type(trackable.title) == "string"
                    and bodyText == trackable.title
                if (type(bodyText) ~= "string" or bodyText:match("%S") == nil or titleMatches) and type(trackable.description) == "string" and trackable.description:match("%S") then
                    bodyText = trackable.description
                end
                if (type(bodyText) ~= "string" or bodyText:match("%S") == nil) and type(trackable.title) == "string" then
                    bodyText = trackable.title
                end

                local bodyDuplicatesDescription = type(bodyText) == "string"
                    and type(trackable.description) == "string"
                    and bodyText == trackable.description

                if bodyText and bodyText ~= "" and not bodyDuplicatesDescription then
                    tooltip:AddLine("• " .. bodyText, lineColor.r, lineColor.g, lineColor.b, true)
                end
                if parsed.prefixText and parsed.prefixText ~= "" then
                    tooltip:AddLine("  - " .. parsed.prefixText, lineColor.r, lineColor.g, lineColor.b, true)
                end
            end
        end

        tooltip:AddLine(" ")
        tooltip:AddLine(format("%d points", trackable.points or 0), 1, 0.82, 0)
    end

    tooltip:Show()
end
