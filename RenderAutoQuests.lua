local addonName, addon = ...

-- Localize hot-path globals
local ipairs, pairs, pcall = ipairs, pairs, pcall
local max = math.max

-------------------------------------------------------------------------------
-- RenderAutoQuestSection — Hijacks Blizzard auto-quest popups into our frame
-------------------------------------------------------------------------------
function addon:RenderAutoQuestSection(autoQuests)
    local completedQuestFrame = self.completedQuestFrame
    local autoQuestFrame = self.autoQuestFrame
    local autoQuestTracker = AutoQuestPopUpTracker
    local noHijackContext = addon.IsNoHijackContext and addon:IsNoHijackContext()

    -- We do not use the old autoQuestFrame logic anymore, but keep it hidden
    autoQuestFrame:SetHeight(1)
    autoQuestFrame:Hide()

    if noHijackContext then
        self._stolenPopups = self._stolenPopups or {}
        for popup, _ in pairs(self._stolenPopups) do
            pcall(function()
                if popup._trackerPlusOriginalParent then
                    popup:SetParent(popup._trackerPlusOriginalParent)
                    popup:ClearAllPoints()
                    popup:SetPoint("TOPLEFT", popup._trackerPlusOriginalParent, "TOPLEFT", 0, 0)
                    popup._trackerPlusOriginalParent = nil
                end
            end)
        end
        wipe(self._stolenPopups)
        completedQuestFrame:SetHeight(1)
        completedQuestFrame:Hide()
        return
    end

    local stolenPopups = {}

    -- Legacy support (BfA/Shadowlands) for AutoQuestPopUpTracker
    if autoQuestTracker and autoQuestTracker.ContentsFrame and #autoQuests > 0 then
        stolenPopups[#stolenPopups + 1] = autoQuestTracker.ContentsFrame
    end

    -- Modern support (Dragonflight / The War Within) for popups inside QuestObjectiveTracker
    if QuestObjectiveTracker and QuestObjectiveTracker.ContentsFrame and QuestObjectiveTracker.ContentsFrame.GetNumChildren then
        for _, child in ipairs({QuestObjectiveTracker.ContentsFrame:GetChildren()}) do
            if child and child.Contents and (child.Contents.QuestIconBg or child.Contents.QuestionMark or child.Contents.Exclamation) then
                if child:IsShown() and (child:GetHeight() or 0) > 1 then
                    stolenPopups[#stolenPopups + 1] = child.Contents
                end
            end
        end
    end

    self._stolenPopups = self._stolenPopups or {}

    -- Restore popups that are no longer active
    for stolenFrame, _ in pairs(self._stolenPopups) do
        local stillActive = false
        for _, activePopup in ipairs(stolenPopups) do
            if activePopup == stolenFrame then
                stillActive = true
                break
            end
        end
        if not stillActive then
            pcall(function()
                if stolenFrame._trackerPlusOriginalParent then
                    stolenFrame:SetParent(stolenFrame._trackerPlusOriginalParent)
                    stolenFrame:ClearAllPoints()
                    stolenFrame:SetPoint("TOPLEFT", stolenFrame._trackerPlusOriginalParent, "TOPLEFT", 0, 0)
                    stolenFrame._trackerPlusOriginalParent = nil
                elseif autoQuestTracker and stolenFrame == autoQuestTracker.ContentsFrame then
                    stolenFrame:SetParent(autoQuestTracker)
                    stolenFrame:ClearAllPoints()
                    stolenFrame:SetPoint("TOPLEFT", autoQuestTracker, "TOPLEFT", 0, 0)
                end
            end)
            self._stolenPopups[stolenFrame] = nil
        end
    end

    if #stolenPopups > 0 then
        local totalHeight = 0
        local yOff = -5
        local autoWidth = self.db.frameWidth - 10

        for _, popup in ipairs(stolenPopups) do
            pcall(function()
                if popup:GetParent() ~= completedQuestFrame then
                    -- Save original parent so we can restore it easily, handle both legacy and modern
                    popup._trackerPlusOriginalParent = popup._trackerPlusOriginalParent or popup:GetParent()
                    popup:SetParent(completedQuestFrame)
                    popup:SetFrameStrata("HIGH")
                    popup:SetFrameLevel(100)
                end

                popup:ClearAllPoints()
                popup:SetPoint("TOPLEFT", completedQuestFrame, "TOPLEFT", -10, yOff)
                popup:SetWidth(autoWidth)
                popup:Show()
                popup:SetAlpha(1)

                if popup.SetIgnoreParentAlpha then popup:SetIgnoreParentAlpha(true) end

                -- Create a transparent overlay button to catch and forward clicks to the hidden parent block
                if not popup._tplusClicker then
                    popup._tplusClicker = CreateFrame("Button", nil, popup)
                    popup._tplusClicker:SetAllPoints(popup)
                    popup._tplusClicker:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    popup._tplusClicker:SetScript("OnClick", function(self, btn)
                        local orig = popup._trackerPlusOriginalParent
                        if not orig then return end

                        -- The hidden container logic usually attaches scripts to `orig` or `orig:GetParent()`
                        local target = orig
                        if orig.Contents == popup then
                            target = orig
                        elseif orig:GetParent() and orig:GetParent().Contents == popup then
                            target = orig:GetParent()
                        end

                        -- Attempt direct API call using quest data from the frame hierarchy
                        local questID = target.questID or target.id
                        if not questID and target:GetParent() then
                            questID = target:GetParent().questID or target:GetParent().id
                        end

                        if questID then
                            if ShowQuestComplete and ShowQuestOffer then
                                local isComplete = target.popUpType == "COMPLETE" or (target:GetParent() and target:GetParent().popUpType == "COMPLETE") or C_QuestLog.IsComplete(questID)
                                if isComplete then
                                    ShowQuestComplete(questID)
                                else
                                    ShowQuestOffer(questID)
                                end
                            end
                            return
                        end

                        -- Script execution fallback
                        if target.Click then
                            target:Click(btn)
                        elseif target:HasScript("OnClick") and target:GetScript("OnClick") then
                            target:GetScript("OnClick")(target, btn)
                        elseif target:HasScript("OnMouseUp") and target:GetScript("OnMouseUp") then
                            target:GetScript("OnMouseUp")(target, btn)
                        else
                            -- Explore children for buried interactive buttons
                            if target.GetNumChildren then
                                for i, c in ipairs({target:GetChildren()}) do
                                    if c.GetScript and (c:GetScript("OnClick") or c:GetScript("OnMouseUp")) then
                                        if c:GetScript("OnClick") then c:GetScript("OnClick")(c, btn)
                                        elseif c:GetScript("OnMouseUp") then c:GetScript("OnMouseUp")(c, btn) end
                                        return
                                    end
                                end
                            end
                        end
                    end)
                    -- Optional: Provide hover highlighting to make it clear it's clickable
                    if popup._tplusClicker.SetHighlightTexture then
                        popup._tplusClicker:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight")
                        local hl = popup._tplusClicker:GetHighlightTexture()
                        if hl then
                            hl:SetBlendMode("ADD")
                            hl:SetAlpha(0.25)
                        end
                    end
                end
            end)
            self._stolenPopups[popup] = true

            local h = popup:GetHeight() or 0
            if h < 20 then h = 70 end
            totalHeight = totalHeight + h + 5
            yOff = yOff - h - 5
        end

        completedQuestFrame:SetHeight(totalHeight + 10)
        completedQuestFrame:Show()
    else
        -- If no popups, ensure we restore anything we had
        for popup, _ in pairs(self._stolenPopups) do
            pcall(function()
                if popup._trackerPlusOriginalParent then
                    popup:SetParent(popup._trackerPlusOriginalParent)
                    popup:ClearAllPoints()
                    popup:SetPoint("TOPLEFT", popup._trackerPlusOriginalParent, "TOPLEFT", 0, 0)
                    popup._trackerPlusOriginalParent = nil
                end
            end)
        end
        wipe(self._stolenPopups)

        self._autoQuestContentsAnchored = false
        self._autoQuestContentsWidth = nil
        completedQuestFrame:SetHeight(1)
        completedQuestFrame:Hide()
    end

    -- Legacy safety cleanup
    if QuestObjectiveTracker and QuestObjectiveTracker.ContentsFrame then
        local questContents = QuestObjectiveTracker.ContentsFrame
        if questContents:GetParent() == autoQuestFrame then
            pcall(function()
                questContents:SetParent(QuestObjectiveTracker)
                questContents:ClearAllPoints()
                questContents:SetPoint("TOPLEFT", QuestObjectiveTracker, "TOPLEFT", 0, 0)
            end)
        end
    end
end
