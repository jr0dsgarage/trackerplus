local addonName, addon = ...

-- Localize hot-path globals
local ipairs, pairs = ipairs, pairs
local max = math.max
local GetTime = GetTime

local AUTO_QUEST_POPUP_PREFIXES = {
    "WatchFrameAutoQuestPopUp",
    "WatchFrameAutoCompleteQuestPopUp",
    "AutoQuestPopUp",
    "AutoCompleteQuestPopUp",
}

local FindAutoQuestPopupFrame

local function IsLikelyAutoQuestPopupFrame(frame)
    if not frame then
        return false
    end

    local contents = frame.Contents
    if not contents then
        return false
    end

    return contents.QuestIconBg ~= nil
        or contents.QuestIconMark ~= nil
        or contents.QuestIconBadgeBorder ~= nil
end

local function CountVisibleChildren(frame)
    if not (frame and frame.GetChildren) then
        return 0
    end

    local count = 0
    for _, child in ipairs({ frame:GetChildren() }) do
        if child and child.IsShown and child:IsShown() then
            count = count + 1
        end
    end
    return count
end

local function IsLiveAutoQuestPopupFrame(frame)
    if not IsLikelyAutoQuestPopupFrame(frame) then
        return false
    end

    local contents = frame.Contents
    local frameShown = frame.IsShown and frame:IsShown() or false
    local contentsShown = contents and contents.IsShown and contents:IsShown() or false
    local visibleChildren = CountVisibleChildren(contents)
    local frameHeight = frame.GetHeight and (frame:GetHeight() or 0) or 0
    local contentsHeight = contents and contents.GetHeight and (contents:GetHeight() or 0) or 0

    return (frameShown or contentsShown or visibleChildren > 0)
        and (frameHeight > 1 or contentsHeight > 1)
end

local function CollectAnonymousAutoQuestPopups(found, seen)
    local questTracker = _G and _G["QuestObjectiveTracker"]
    local contentsFrame = questTracker and questTracker.ContentsFrame
    if not (contentsFrame and contentsFrame.GetChildren) then
        return
    end

    local children = { contentsFrame:GetChildren() }
    if addon.LogAt then
        addon:LogAt("trace", "[AQ-BORROW-SCAN] contentsFrame has %d children", #children)
    end

    for _, child in ipairs(children) do
        local childName = child.GetName and child:GetName() or "<unnamed>"
        local isShown = child.IsShown and child:IsShown() or false
        local hasContents = child.Contents ~= nil

        if child and not seen[child] and IsLiveAutoQuestPopupFrame(child) then
            if addon.LogAt then
                addon:LogAt("trace", "[AQ-BORROW-SCAN] MATCHED child=%s shown=%s contents=%s", childName, tostring(isShown), tostring(hasContents))
            end
            seen[child] = true
            found[#found + 1] = child
        elseif child and not seen[child] and addon.LogAt then
            addon:LogAt("trace", "[AQ-BORROW-SCAN] child=%s shown=%s hasContents=%s likelyPopup=%s", childName, tostring(isShown), tostring(hasContents), tostring(IsLikelyAutoQuestPopupFrame(child)))
        end
    end
end

local function FindAllAutoQuestPopupFrames(scanCount)
    local found = {}
    local seen = {}

    for i = 1, scanCount do
        local popup = FindAutoQuestPopupFrame(i)
        if popup and not seen[popup] then
            seen[popup] = true
            found[#found + 1] = popup
        end
    end

    CollectAnonymousAutoQuestPopups(found, seen)
    return found
end

local function IsRenderableBorrowedAutoQuestPopup(popup)
    if not (popup and IsLikelyAutoQuestPopupFrame(popup)) then
        return false
    end

    local contents = popup.Contents
    if not contents then
        return false
    end

    local popupShown = popup.IsShown and popup:IsShown() or false
    local contentsShown = contents.IsShown and contents:IsShown() or false
    local popupHeight = popup.GetHeight and (popup:GetHeight() or 0) or 0
    local contentsHeight = contents.GetHeight and (contents:GetHeight() or 0) or 0
    local contentsAlpha = contents.GetAlpha and (contents:GetAlpha() or 0) or 0
    local visibleChildren = CountVisibleChildren(contents)

    return popupHeight > 1
        and contentsHeight > 1
        and contentsAlpha > 0
        and (popupShown or contentsShown or visibleChildren > 0)
end

local function IsRecentlySeenPopup(popup, now)
    local lastSeen = popup and popup._trackerPlusLastAutoQuestSeenAt
    return lastSeen and now and (now - lastSeen) <= 3.0 or false
end

local function EnsureAutoQuestPopupVisible(popup)
    local function ensureFrame(frame, forceIgnoreParentAlpha)
        if not frame then
            return
        end
        if frame.Show then
            frame:Show()
        end
        if frame.SetAlpha then
            frame:SetAlpha(1)
        end
        if forceIgnoreParentAlpha and frame.SetIgnoreParentAlpha then
            frame:SetIgnoreParentAlpha(true)
        end
    end

    ensureFrame(popup, true)

    local contents = popup and popup.Contents
    ensureFrame(contents, true)

    if contents and contents.GetChildren then
        for _, child in ipairs({ contents:GetChildren() }) do
            ensureFrame(child, false)
        end
    end

    if popup and popup.GetChildren then
        for _, child in ipairs({ popup:GetChildren() }) do
            if child ~= contents then
                ensureFrame(child, false)
            end
        end
    end
end

local function CollectPersistedBorrowedPopups(owner, found, seen, allowRecent)
    local borrowed = owner and owner._borrowedAutoQuestPopups
    if not borrowed then
        return
    end

    local now = GetTime and GetTime() or 0
    for popup, _ in pairs(borrowed) do
        local renderable = IsRenderableBorrowedAutoQuestPopup(popup)
        local recent = allowRecent and IsRecentlySeenPopup(popup, now) or false

        if popup
            and not seen[popup]
            and popup:GetParent() == owner.completedQuestFrame
            and (renderable or recent)
        then
            seen[popup] = true
            found[#found + 1] = popup
            if addon.LogAt then
                local popupName = popup.GetName and popup:GetName() or "<unnamed>"
                addon:LogAt("trace", "[AQ-BORROW-PERSIST] keeping borrowed popup=%s parent=%s renderable=%s recent=%s", popupName, tostring(popup:GetParent()), tostring(renderable), tostring(recent))
            end
        end
    end
end

local function FindCandidateAutoQuestPopups(owner, scanCount, allowRecent)
    local found = FindAllAutoQuestPopupFrames(scanCount)
    local seen = {}

    for _, popup in ipairs(found) do
        seen[popup] = true
    end

    CollectPersistedBorrowedPopups(owner, found, seen, allowRecent)
    return found
end

FindAutoQuestPopupFrame = function(index)
    if not index then
        return nil
    end

    for _, prefix in ipairs(AUTO_QUEST_POPUP_PREFIXES) do
        local popup = _G and _G[prefix .. tostring(index)]
        if popup and IsLiveAutoQuestPopupFrame(popup) then
            return popup
        end
    end

    return nil
end

local function RestoreStaleBorrowedPopups(owner, keep)
    owner._borrowedAutoQuestPopups = owner._borrowedAutoQuestPopups or {}
    for popup, _ in pairs(owner._borrowedAutoQuestPopups) do
        if not keep or not keep[popup] then
            if popup._trackerPlusOriginalParent and not (popup.IsProtected and popup:IsProtected()) then
                popup:SetParent(popup._trackerPlusOriginalParent)
                popup:ClearAllPoints()

                local originalPoints = popup._trackerPlusOriginalPoints
                if originalPoints and #originalPoints > 0 then
                    for i = 1, #originalPoints do
                        local point = originalPoints[i]
                        if point then
                            popup:SetPoint(point.point, point.relativeTo, point.relativePoint, point.xOfs, point.yOfs)
                        end
                    end
                else
                    popup:SetPoint("TOPLEFT", popup._trackerPlusOriginalParent, "TOPLEFT", 0, 0)
                end

                if popup.SetIgnoreParentAlpha then
                    popup:SetIgnoreParentAlpha(false)
                end
                if popup.Contents and popup.Contents.SetIgnoreParentAlpha then
                    popup.Contents:SetIgnoreParentAlpha(false)
                end

                popup._trackerPlusOriginalParent = nil
                popup._trackerPlusOriginalPoints = nil
                popup._trackerPlusLastAutoQuestSeenAt = nil
            end
            owner._borrowedAutoQuestPopups[popup] = nil
        end
    end

    if owner._stolenPopups then
        wipe(owner._stolenPopups)
        owner._stolenPopups = nil
    end
end

local function HideLegacyCompletedQuestChildren(frame, keep)
    if not (frame and frame.GetChildren) then
        return
    end

    for _, child in ipairs({ frame:GetChildren() }) do
        if child and (not keep or not keep[child]) and not (child.IsProtected and child:IsProtected()) then
            pcall(function()
                child:Hide()
            end)
        end
    end
end

local function EnsureCompletedQuestFrameAnchor(owner)
    local completedQuestFrame = owner and owner.completedQuestFrame
    local scenarioFrame = owner and owner.scenarioFrame
    if not (completedQuestFrame and scenarioFrame) then
        return
    end

    local targetWidth = max(1, (scenarioFrame.GetWidth and scenarioFrame:GetWidth()) or completedQuestFrame:GetWidth() or 1)
    local anchorSig = tostring(scenarioFrame) .. "|" .. tostring(targetWidth)
    if completedQuestFrame._tpPopupAnchorSig ~= anchorSig then
        completedQuestFrame:ClearAllPoints()
        completedQuestFrame:SetPoint("TOPRIGHT", scenarioFrame, "TOPRIGHT", 0, 0)
        completedQuestFrame:SetWidth(targetWidth)
        completedQuestFrame:SetFrameLevel((scenarioFrame:GetFrameLevel() or 0) + 10)
        completedQuestFrame._tpPopupAnchorSig = anchorSig
    end
end

-------------------------------------------------------------------------------
-- RenderAutoQuestSection — borrows Blizzard auto-quest popups when possible
-------------------------------------------------------------------------------
function addon:RenderAutoQuestSection(autoQuests)
    local completedQuestFrame = self.completedQuestFrame
    local autoQuestFrame = self.autoQuestFrame

    autoQuestFrame:SetHeight(1)
    autoQuestFrame:Hide()

    if addon.db.minimized then
        RestoreStaleBorrowedPopups(self, nil)
        HideLegacyCompletedQuestChildren(completedQuestFrame, nil)
        self._autoQuestBorrowSessionUntil = nil
        completedQuestFrame:SetHeight(1)
        completedQuestFrame:Hide()
        return
    end

    local activeBorrowed = {}
    local borrowedCount = 0
    local yOff = 0
    local now = GetTime and GetTime() or 0
    EnsureCompletedQuestFrameAnchor(self)

    local scanCount = max(#autoQuests, 12)
    local allowRecent = now <= (self._autoQuestBorrowSessionUntil or 0)
    local popups = FindCandidateAutoQuestPopups(self, scanCount, allowRecent)

    if #popups > 0 then
        -- Keep a short session window so a single missed scan frame does not
        -- immediately restore/re-borrow the popup and cause position popping.
        self._autoQuestBorrowSessionUntil = now + 0.9
        allowRecent = true
    end

    for _, popup in ipairs(popups) do
        if popup and not (popup.IsProtected and popup:IsProtected()) then
            popup._trackerPlusLastAutoQuestSeenAt = now

            if not popup._trackerPlusOriginalParent then
                popup._trackerPlusOriginalParent = popup:GetParent()

                local points = {}
                local numPoints = popup.GetNumPoints and popup:GetNumPoints() or 0
                for i = 1, numPoints do
                    local point, relativeTo, relativePoint, xOfs, yOfs = popup:GetPoint(i)
                    points[#points + 1] = {
                        point = point,
                        relativeTo = relativeTo,
                        relativePoint = relativePoint,
                        xOfs = xOfs,
                        yOfs = yOfs,
                    }
                end
                popup._trackerPlusOriginalPoints = points
            end

            if popup:GetParent() ~= completedQuestFrame then
                popup:SetParent(completedQuestFrame)
            end

            popup:ClearAllPoints()
            popup:SetPoint("TOPRIGHT", completedQuestFrame, "TOPRIGHT", 0, -yOff)

            EnsureAutoQuestPopupVisible(popup)

            activeBorrowed[popup] = true
            self._borrowedAutoQuestPopups = self._borrowedAutoQuestPopups or {}
            self._borrowedAutoQuestPopups[popup] = true

            borrowedCount = borrowedCount + 1
            yOff = yOff + max(1, popup:GetHeight() or 0) + (self.db.spacingItemVertical or 4)
        end
    end

    if borrowedCount > 0 then
        self._autoQuestBorrowSessionUntil = now + 0.9
    end

    RestoreStaleBorrowedPopups(self, activeBorrowed)
    HideLegacyCompletedQuestChildren(completedQuestFrame, activeBorrowed)

    if addon.LogAt then
        addon:LogAt("trace", "[AQ-BORROW] candidates=%d borrowed=%d autoQuests=%d borrowedCount=%d yOff=%d", tonumber(#popups or 0), tonumber(borrowedCount or 0), tonumber(#autoQuests or 0), tonumber(borrowedCount or 0), tonumber(yOff or 0))

        if borrowedCount > 0 then
            for popup, _ in pairs(activeBorrowed) do
                local popupName = popup.GetName and popup:GetName() or "<unnamed>"
                local popupParent = popup:GetParent()
                local parentName = popupParent and (popupParent.GetName and popupParent:GetName() or "parent?") or "nil"
                local popupAlpha = popup:GetAlpha()
                local popupShown = popup:IsShown()
                local popupHeight = popup:GetHeight()
                local contents = popup.Contents
                local contentsShown = contents and contents.IsShown and contents:IsShown() or false
                local contentsAlpha = contents and contents.GetAlpha and (contents:GetAlpha() or 0) or 0
                local visibleChildren = CountVisibleChildren(contents)

                addon:LogAt("trace", "[AQ-STATE] popup=%s parent=%s alpha=%.2f shown=%s height=%.1f cShown=%s cAlpha=%.2f cKids=%d", popupName, parentName, popupAlpha, tostring(popupShown), popupHeight, tostring(contentsShown), contentsAlpha, visibleChildren)
            end
        end
    end

    if borrowedCount > 0 then
        local targetHeight = max(1, yOff + 2)
        EnsureCompletedQuestFrameAnchor(self)
        if addon.LogAt then
            addon:LogAt("trace", "[AQ-PATH] taking borrowed path, setting completedQuestFrame height to %d", tonumber(targetHeight or 0))
        end
        completedQuestFrame:SetHeight(targetHeight)
        if addon.LogAt then
            addon:LogAt("trace", "[AQ-POST-SET] height after SetHeight: target=%d actual=%.1f shown=%s", tonumber(targetHeight or 0), completedQuestFrame:GetHeight() or 0, tostring(completedQuestFrame:IsShown()))
        end
        completedQuestFrame:Show()
        return
    end

    if addon.LogAt then
        addon:LogAt("trace", "[AQ-PATH] no borrowed frames, hiding completedQuestFrame")
    end
    self._autoQuestBorrowSessionUntil = nil
    completedQuestFrame:SetHeight(1)
    completedQuestFrame:Hide()
end
