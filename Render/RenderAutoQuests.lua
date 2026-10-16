local addonName, addon = ...

-- Localize hot-path globals
local ipairs, pairs, select, tostring = ipairs, pairs, select, tostring
local max = math.max
local GetTime = GetTime
local hooksecurefunc = hooksecurefunc
local InCombatLockdown = InCombatLockdown

local COMPLETED_QUEST_POPUP_X = -20

local AUTO_QUEST_POPUP_PREFIXES = {
    "WatchFrameAutoQuestPopUp",
    "WatchFrameAutoCompleteQuestPopUp",
    "AutoQuestPopUp",
    "AutoCompleteQuestPopUp",
}

local FindAutoQuestPopupFrame

local function NormalizeCompletedQuestPopupAnchor(owner, popup)
    local completedQuestFrame = owner and owner.completedQuestFrame
    if not (completedQuestFrame and popup and popup._trackerPlusAnchorLockEnabled) then
        return
    end

    -- This runs both from the direct borrow path and reactively from the
    -- hooksecurefunc guards below (i.e. whenever Blizzard's own code calls
    -- SetPoint/ClearAllPoints on the popup, which can happen mid-combat).
    -- SetParent/ClearAllPoints/SetPoint on a Blizzard-owned frame must stay
    -- out-of-combat only, matching the pattern used in RenderScenario.lua.
    if InCombatLockdown() then
        return
    end

    local targetX = tonumber(popup._trackerPlusLockedAnchorX or COMPLETED_QUEST_POPUP_X) or COMPLETED_QUEST_POPUP_X
    local targetY = tonumber(popup._trackerPlusLockedAnchorY or 0) or 0

    if popup:GetParent() ~= completedQuestFrame then
        popup:SetParent(completedQuestFrame)
    end

    local point, relativeTo, relativePoint, xOfs, yOfs = popup:GetPoint(1)
    local numPoints = popup:GetNumPoints()
    local isDirty =
        numPoints ~= 1
        or point ~= "TOPRIGHT"
        or relativeTo ~= completedQuestFrame
        or relativePoint ~= "TOPRIGHT"
        or tonumber(xOfs or 0) ~= targetX
        or tonumber(yOfs or 0) ~= targetY

    if not isDirty then
        return
    end

    popup:ClearAllPoints()
    popup:SetPoint("TOPRIGHT", completedQuestFrame, "TOPRIGHT", targetX, targetY)

    addon:LogAt("trace", "[CQ-ANCHOR-FIX] normalize popup=%s points=%d p=%s rp=%s x=%.1f y=%.1f targetX=%.1f targetY=%.1f",
        popup:GetName() or "<unnamed>", numPoints, tostring(point), tostring(relativePoint),
        tonumber(xOfs or 0), tonumber(yOfs or 0), targetX, targetY)
end

local function InstallCompletedQuestPopupAnchorGuards(owner, popup)
    if popup._trackerPlusAnchorGuardsInstalled then
        return
    end

    popup._trackerPlusAnchorGuardsInstalled = true

    local function normalizeFromGuard(frame)
        if not (frame and frame._trackerPlusAnchorLockEnabled) then
            return
        end
        if frame._trackerPlusGuardApplying then
            return
        end

        frame._trackerPlusGuardApplying = true
        pcall(NormalizeCompletedQuestPopupAnchor, owner, frame)
        frame._trackerPlusGuardApplying = nil
    end

    hooksecurefunc(popup, "SetPoint", normalizeFromGuard)
    hooksecurefunc(popup, "ClearAllPoints", normalizeFromGuard)
end

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

local function CountShown(...)
    local count = 0
    for i = 1, select("#", ...) do
        if select(i, ...):IsShown() then
            count = count + 1
        end
    end
    return count
end

local function CountVisibleChildren(frame)
    if not frame then
        return 0
    end
    return CountShown(frame:GetChildren())
end

local function IsLiveAutoQuestPopupFrame(frame)
    if not IsLikelyAutoQuestPopupFrame(frame) then
        return false
    end

    local contents = frame.Contents
    return (frame:IsShown() or contents:IsShown() or CountVisibleChildren(contents) > 0)
        and ((frame:GetHeight() or 0) > 1 or (contents:GetHeight() or 0) > 1)
end

local function CollectAnonymousAutoQuestPopups(found, seen, trace)
    local questTracker = QuestObjectiveTracker
    local contentsFrame = questTracker and questTracker.ContentsFrame
    if not contentsFrame then
        return
    end

    local children = { contentsFrame:GetChildren() }
    if trace then
        addon:LogAt("trace", "[AQ-BORROW-SCAN] contentsFrame has %d children", #children)
    end

    for _, child in ipairs(children) do
        if not seen[child] then
            local matched = IsLiveAutoQuestPopupFrame(child)
            if matched then
                seen[child] = true
                found[#found + 1] = child
            end
            if trace then
                addon:LogAt("trace", "[AQ-BORROW-SCAN] %s child=%s shown=%s hasContents=%s likelyPopup=%s",
                    matched and "MATCHED" or "skipped", child:GetName() or "<unnamed>", tostring(child:IsShown()),
                    tostring(child.Contents ~= nil), tostring(IsLikelyAutoQuestPopupFrame(child)))
            end
        end
    end
end

-- Popups found by global name plus anonymous ones under the quest tracker; also
-- returns the set of what was found, for de-duplication.
local function FindAllAutoQuestPopupFrames(scanCount, trace)
    local found = {}
    local seen = {}

    for i = 1, scanCount do
        local popup = FindAutoQuestPopupFrame(i)
        if popup and not seen[popup] then
            seen[popup] = true
            found[#found + 1] = popup
        end
    end

    CollectAnonymousAutoQuestPopups(found, seen, trace)
    return found, seen
end

local function IsRenderableBorrowedAutoQuestPopup(popup)
    if not IsLikelyAutoQuestPopupFrame(popup) then
        return false
    end

    local contents = popup.Contents
    return (popup:GetHeight() or 0) > 1
        and (contents:GetHeight() or 0) > 1
        and (contents:GetAlpha() or 0) > 0
        and (popup:IsShown() or contents:IsShown() or CountVisibleChildren(contents) > 0)
end

local function IsRecentlySeenPopup(popup, now)
    local lastSeen = popup and popup._trackerPlusLastAutoQuestSeenAt
    return lastSeen and now and (now - lastSeen) <= 3.0 or false
end

local function EnsureFrameVisible(frame, ignoreParentAlpha)
    frame:Show()
    frame:SetAlpha(1)
    if ignoreParentAlpha and frame.SetIgnoreParentAlpha then
        frame:SetIgnoreParentAlpha(true)
    end
end

-- Shows each of the given frames at full alpha, skipping `except`.
local function EnsureChildrenVisible(except, ...)
    for i = 1, select("#", ...) do
        local child = select(i, ...)
        if child ~= except then
            EnsureFrameVisible(child, false)
        end
    end
end

local function EnsureAutoQuestPopupVisible(popup)
    EnsureFrameVisible(popup, true)

    local contents = popup.Contents
    EnsureFrameVisible(contents, true)
    EnsureChildrenVisible(nil, contents:GetChildren())
    EnsureChildrenVisible(contents, popup:GetChildren())
end

local function CollectPersistedBorrowedPopups(owner, found, seen, allowRecent, trace)
    local borrowed = owner._borrowedAutoQuestPopups
    if not borrowed then
        return
    end

    local now = GetTime()
    for popup in pairs(borrowed) do
        local renderable = IsRenderableBorrowedAutoQuestPopup(popup)
        local recent = allowRecent and IsRecentlySeenPopup(popup, now) or false

        if not seen[popup]
            and popup:GetParent() == owner.completedQuestFrame
            and (renderable or recent)
        then
            seen[popup] = true
            found[#found + 1] = popup
            if trace then
                addon:LogAt("trace", "[AQ-BORROW-PERSIST] keeping borrowed popup=%s parent=%s renderable=%s recent=%s",
                    popup:GetName() or "<unnamed>", tostring(popup:GetParent()), tostring(renderable), tostring(recent))
            end
        end
    end
end

local function FindCandidateAutoQuestPopups(owner, scanCount, allowRecent, trace)
    local found, seen = FindAllAutoQuestPopupFrames(scanCount, trace)
    CollectPersistedBorrowedPopups(owner, found, seen, allowRecent, trace)
    return found
end

FindAutoQuestPopupFrame = function(index)
    for _, prefix in ipairs(AUTO_QUEST_POPUP_PREFIXES) do
        local popup = _G[prefix .. index]
        if popup and IsLiveAutoQuestPopupFrame(popup) then
            return popup
        end
    end

    return nil
end

local function RestoreStaleBorrowedPopups(owner, keep)
    local borrowed = owner._borrowedAutoQuestPopups
    if not borrowed then
        return
    end
    for popup in pairs(borrowed) do
        if not keep or not keep[popup] then
            local restored = false

            if popup._trackerPlusOriginalParent
                and not (popup.IsProtected and popup:IsProtected())
                and not InCombatLockdown() then
                popup._trackerPlusAnchorLockEnabled = nil
                popup._trackerPlusLockedAnchorX = nil
                popup._trackerPlusLockedAnchorY = nil
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
                restored = true
            end

            -- Only stop tracking this popup once it has actually been handed back (or
            -- there was never anything to hand back). A popup that is currently
            -- protected or that we're in combat right now can't be restored yet; keep
            -- it tracked so a later call retries, instead of silently forgetting it
            -- while it's still reparented under completedQuestFrame with alpha/anchor
            -- overrides in effect and no way to ever clean it up again.
            if restored or not popup._trackerPlusOriginalParent then
                borrowed[popup] = nil
            end
        end
    end
end

-- Hides each of the given frames that isn't in `keep` (or protected).
local function HideChildrenExcept(keep, ...)
    for i = 1, select("#", ...) do
        local child = select(i, ...)
        if not (keep and keep[child]) and not child:IsProtected() then
            pcall(child.Hide, child)
        end
    end
end

-- Hides anything left parented to the completed-quest frame other than `keep`.
-- Runs on every render, so the usual empty case does no work at all.
local function HideLegacyCompletedQuestChildren(frame, keep)
    if frame:GetNumChildren() > 0 then
        HideChildrenExcept(keep, frame:GetChildren())
    end
end

local function EnsureCompletedQuestFrameAnchor(owner)
    -- Position is managed by UpdateLayoutAnchors (completedQuestFrame is in the topSections chain).
    -- This function only ensures the frame level is elevated so popups render above sibling sections.
    owner.completedQuestFrame:SetFrameLevel(owner.scenarioFrame:GetFrameLevel() + 2)
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

    -- If no auto quests are currently tracked, do not keep any persisted borrowed
    -- completion popup alive. This prevents stale frames from lingering after quest
    -- completion when Blizzard leaves a visible shell frame behind.
    if #autoQuests == 0 then
        RestoreStaleBorrowedPopups(self, nil)
        HideLegacyCompletedQuestChildren(completedQuestFrame, nil)
        self._autoQuestBorrowSessionUntil = nil
        completedQuestFrame:SetHeight(1)
        completedQuestFrame:Hide()
        self:LogAt("trace", "[AQ-PATH] no tracked autoQuests, force hiding completedQuestFrame")
        return
    end

    local trace = self:ShouldLog("trace")
    local activeBorrowed = {}
    local borrowedCount = 0
    local yOff = 0
    local now = GetTime()
    EnsureCompletedQuestFrameAnchor(self)

    local scanCount = max(#autoQuests, 12)
    local allowRecent = now <= (self._autoQuestBorrowSessionUntil or 0)
    local popups = FindCandidateAutoQuestPopups(self, scanCount, allowRecent, trace)

    if #popups > 0 then
        -- Keep a short session window so a single missed scan frame does not
        -- immediately restore/re-borrow the popup and cause position popping.
        self._autoQuestBorrowSessionUntil = now + 0.9
        allowRecent = true
    end

    for _, popup in ipairs(popups) do
        if not popup:IsProtected() then
            -- Only refresh grace timers for popups that currently have real content.
            -- If we refresh for non-renderable (empty/hidden) popups the session window
            -- and "recently seen" timers perpetually self-extend, keeping the frame alive
            -- forever after quest completion.
            if IsRenderableBorrowedAutoQuestPopup(popup) then
                popup._trackerPlusLastAutoQuestSeenAt = now
            end

            if not popup._trackerPlusOriginalParent then
                popup._trackerPlusOriginalParent = popup:GetParent()

                local points = {}
                for i = 1, popup:GetNumPoints() do
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

            if not InCombatLockdown() and popup:GetParent() ~= completedQuestFrame then
                popup:SetParent(completedQuestFrame)
            end

            popup._trackerPlusLockedAnchorX = COMPLETED_QUEST_POPUP_X
            popup._trackerPlusLockedAnchorY = -yOff
            InstallCompletedQuestPopupAnchorGuards(self, popup)
            popup._trackerPlusAnchorLockEnabled = true

            NormalizeCompletedQuestPopupAnchor(self, popup)

            EnsureAutoQuestPopupVisible(popup)

            activeBorrowed[popup] = true
            self._borrowedAutoQuestPopups = self._borrowedAutoQuestPopups or {}
            self._borrowedAutoQuestPopups[popup] = true

            borrowedCount = borrowedCount + 1
            yOff = yOff + max(1, popup:GetHeight() or 0) + (self.db.spacingItemVertical or 4)
        end
    end

    if borrowedCount > 0 then
        -- Only extend session window when we have popups with real content.
        -- Checking whether any active borrowed popup is actually renderable prevents
        -- the session from being extended indefinitely by empty/hidden leftover frames.
        local hasRenderable = false
        for popup, _ in pairs(activeBorrowed) do
            if IsRenderableBorrowedAutoQuestPopup(popup) then
                hasRenderable = true
                break
            end
        end
        if hasRenderable then
            self._autoQuestBorrowSessionUntil = now + 0.9
        end
    end

    RestoreStaleBorrowedPopups(self, activeBorrowed)
    HideLegacyCompletedQuestChildren(completedQuestFrame, activeBorrowed)

    if trace then
        self:LogAt("trace", "[AQ-BORROW] candidates=%d autoQuests=%d borrowedCount=%d yOff=%d", #popups, #autoQuests, borrowedCount, yOff)

        for popup in pairs(activeBorrowed) do
            local popupParent = popup:GetParent()
            local contents = popup.Contents
            self:LogAt("trace", "[AQ-STATE] popup=%s parent=%s alpha=%.2f shown=%s height=%.1f cShown=%s cAlpha=%.2f cKids=%d",
                popup:GetName() or "<unnamed>",
                popupParent and (popupParent:GetName() or "parent?") or "nil",
                popup:GetAlpha(), tostring(popup:IsShown()), popup:GetHeight(),
                tostring(contents:IsShown()), contents:GetAlpha() or 0, CountVisibleChildren(contents))
        end
    end

    if borrowedCount > 0 then
        local targetHeight = max(1, yOff + 2)
        EnsureCompletedQuestFrameAnchor(self)
        completedQuestFrame:SetHeight(targetHeight)
        if trace then
            self:LogAt("trace", "[AQ-PATH] borrowed path: completedQuestFrame height target=%d actual=%.1f shown=%s",
                targetHeight, completedQuestFrame:GetHeight() or 0, tostring(completedQuestFrame:IsShown()))
        end
        completedQuestFrame:Show()
        return
    end

    self:LogAt("trace", "[AQ-PATH] no borrowed frames, hiding completedQuestFrame")
    self._autoQuestBorrowSessionUntil = nil
    completedQuestFrame:SetHeight(1)
    completedQuestFrame:Hide()
end
