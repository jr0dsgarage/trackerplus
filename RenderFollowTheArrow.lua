---@diagnostic disable: undefined-global
local addonName, addon = ...

-- Localize hot-path globals
local format = string.format
local max = math.max

-------------------------------------------------------------------------------
-- GetFTAData — safely extract current guide/step info from FollowTheArrow
-- Returns: data table or nil if FTA is not available/active
-- Requires FollowTheArrow's Init.lua to expose: FollowTheArrowAPI = FTA
-------------------------------------------------------------------------------
local function GetFTAData()
    if not FTACharDB then
        if addon.LogAt then addon:LogAt("info", "[FTA] FTACharDB is nil — FollowTheArrow not installed or not yet loaded") end
        return nil
    end
    if not FTACharDB.progress then
        if addon.LogAt then addon:LogAt("info", "[FTA] FTACharDB.progress is nil") end
        return nil
    end

    local api = FollowTheArrowAPI
    if not api then
        if addon.LogAt then addon:LogAt("info", "[FTA] FollowTheArrowAPI global is nil — FTA namespace not exposed") end
        return nil
    end
    if not api.Modules then
        if addon.LogAt then addon:LogAt("info", "[FTA] FollowTheArrowAPI.Modules is nil") end
        return nil
    end

    local moduleId = FTACharDB.progress.activeModuleId
    if not moduleId then
        if addon.LogAt then addon:LogAt("info", "[FTA] no activeModuleId in FTACharDB.progress") end
        return nil
    end

    local module = api.Modules[moduleId]
    if not module then
        if addon.LogAt then addon:LogAt("info", "[FTA] moduleId=%s not found in FollowTheArrowAPI.Modules", tostring(moduleId)) end
        return nil
    end

    local stepsByModule = FTACharDB.progress.stepIndexByModule
    local stepIndex = stepsByModule and stepsByModule[moduleId]
    if not stepIndex then
        if addon.LogAt then addon:LogAt("info", "[FTA] no stepIndex for moduleId=%s", tostring(moduleId)) end
        return nil
    end

    local steps = module.steps
    if not steps then
        if addon.LogAt then addon:LogAt("info", "[FTA] module.steps is nil for moduleId=%s", tostring(moduleId)) end
        return nil
    end
    if not steps[stepIndex] then
        if addon.LogAt then addon:LogAt("info", "[FTA] stepIndex=%d out of range (total=%d) for moduleId=%s", stepIndex, #steps, tostring(moduleId)) end
        return nil
    end

    local step = steps[stepIndex]
    local totalSteps = #steps

    -- Collect zone from module metadata
    local zone = module.zone or ""

    -- Use FTA's own display-segment resolver so visibility/satisfaction filtering matches FTA's UI
    local tasks = {}
    local notes = {}
    if api.Resolve and api.Resolve.GetDisplaySegmentsForStep then
        local displaySegs = api.Resolve:GetDisplaySegmentsForStep(step, moduleId, stepIndex)
        for _, seg in ipairs(displaySegs) do
            if seg.kind == "NOTE" then
                notes[#notes + 1] = seg.text or ""
            else
                -- Mirror FTA's BuildLine: substitute {progress} token, or strip it if no progress
                local text = seg.text or ""
                if seg.kind == "OBJECTIVE" then
                    local base = (text ~= "") and text or "Complete objective {progress}."
                    local prog = nil
                    if seg.showProgress ~= false and api.Resolve and api.Resolve.GetSegmentProgressText then
                        prog = api.Resolve:GetSegmentProgressText(seg)
                    end
                    if prog then
                        text = base:gsub("%{progress%}", (prog:gsub("%%", "%%%%")))
                    else
                        text = base:gsub("%{progress%}%s*", ""):gsub("%s+%.", ".")
                    end
                elseif seg.kind == "PICKUP" then
                    if text == "" and FollowTheArrowAPI.Text and FollowTheArrowAPI.Text.PickupLine then
                        text = FollowTheArrowAPI.Text:PickupLine(seg.questName)
                    end
                    if text == "" then text = "Pick up quest." end
                elseif seg.kind == "TURNIN" then
                    if text == "" and FollowTheArrowAPI.Text and FollowTheArrowAPI.Text.TurnInLine then
                        text = FollowTheArrowAPI.Text:TurnInLine(seg.questName)
                    end
                    if text == "" then text = "Turn in quest." end
                end
                if text ~= "" then
                    tasks[#tasks + 1] = text
                end
            end
        end
    else
        -- Fallback: raw segment dump (no filtering)
        if step.segments then
            for _, seg in ipairs(step.segments) do
                if seg.kind == "OBJECTIVE" or seg.kind == "PICKUP" then
                    tasks[#tasks + 1] = seg.text or ""
                elseif seg.kind == "NOTE" then
                    notes[#notes + 1] = seg.text or ""
                end
            end
        end
    end

    if addon.LogAt then
        addon:LogAt("info", "[FTA] module=%s step=%d/%d title=%s tasks=%d notes=%d",
            tostring(moduleId), stepIndex, totalSteps,
            tostring(step.title or step.name), #tasks, #notes)
    end

    return {
        zone      = zone,
        title     = step.title or step.name or ("Step " .. stepIndex),
        tasks     = tasks,
        notes     = notes,
        stepIndex = stepIndex,
        totalSteps = totalSteps,
        moduleId  = moduleId,
        module    = module,
    }
end

-------------------------------------------------------------------------------
-- ApplyFTATracking — super-track the current FTA step's quest or coordinate
-- Guard: only acts when the step actually changed, so setting a waypoint
-- (which fires SUPER_TRACKING_CHANGED → FTA:FullRefresh → FTA.UI:Refresh)
-- doesn't re-enter and create an infinite refresh loop.
-------------------------------------------------------------------------------
local _lastTrackedModule = nil
local _lastTrackedStep   = nil
local _lastTrackedMapID  = nil
local _lastTrackedX      = nil
local _lastTrackedY      = nil

local function ApplyFTATracking(force)
    local function log(fmt, ...) if addon.LogAt then addon:LogAt("info", "[FTA-TRACK] " .. fmt, ...) end end

    local api = FollowTheArrowAPI
    if not api then log("no FollowTheArrowAPI"); return end
    if not (FTACharDB and FTACharDB.progress) then log("no FTACharDB.progress"); return end

    local moduleId = FTACharDB.progress.activeModuleId
    if not moduleId then log("no activeModuleId"); return end
    local module = api.Modules and api.Modules[moduleId]
    if not module then log("module not found: %s", tostring(moduleId)); return end

    local stepsByModule = FTACharDB.progress.stepIndexByModule
    local stepIndex = stepsByModule and stepsByModule[moduleId]
    if not stepIndex then log("no stepIndex for module %s", tostring(moduleId)); return end

    -- Partial early-out: skip only if step AND target haven't changed
    -- (prevents waypoint-set → SUPER_TRACKING_CHANGED → refresh loop,
    --  but still updates when the arrow target moves within the same step)
    local stepSame = (moduleId == _lastTrackedModule and stepIndex == _lastTrackedStep)
    if not force and stepSame then
        -- Resolve the target now to compare coords before committing
        local earlyStep = module.steps and module.steps[stepIndex]
        local earlyTarget = earlyStep and api.Resolve and api.Resolve.GetCurrentTarget
            and api.Resolve:GetCurrentTarget(module, earlyStep)
        if earlyTarget
            and earlyTarget.mapID == _lastTrackedMapID
            and earlyTarget.x    == _lastTrackedX
            and earlyTarget.y    == _lastTrackedY then
            return
        end
    end
    _lastTrackedModule = moduleId
    _lastTrackedStep   = stepIndex

    local step = module.steps and module.steps[stepIndex]
    if not step then log("step %d not found", stepIndex); return end

    log("module=%s step=%d segments=%d", tostring(moduleId), stepIndex,
        step.segments and #step.segments or 0)

    -- Try to super-track the active segment's quest
    local questTracked = false
    if api.Resolve and api.Resolve.GetActiveSegment then
        local segIdx, seg = api.Resolve:GetActiveSegment(module, step, moduleId, stepIndex)
        if seg then
            log("active seg idx=%s kind=%s questIDs=%s",
                tostring(segIdx), tostring(seg.kind), tostring(seg.questIDs))
            local qid = type(seg.questIDs) == "number" and seg.questIDs
                     or (type(seg.questIDs) == "table" and seg.questIDs[1])
            if qid then
                local inLog = C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(qid)
                log("questID=%d inLog=%s", qid, tostring(inLog))
                if inLog then
                    if C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
                        C_SuperTrack.SetSuperTrackedQuestID(qid)
                        log("super-tracked questID=%d", qid)
                        questTracked = true
                    else
                        log("C_SuperTrack.SetSuperTrackedQuestID not available")
                    end
                end
            else
                log("seg has no usable questID (questIDs=%s)", tostring(seg.questIDs))
            end
        else
            log("GetActiveSegment returned nil seg")
        end
    else
        log("api.Resolve.GetActiveSegment not available")
    end

    -- Always try coordinate waypoint (whether or not a quest was tracked)
    -- so "Follow the Arrow" steps with no quest still get a map pin
    if not (api.Resolve and api.Resolve.GetCurrentTarget) then
        log("GetCurrentTarget not available"); return
    end
    local target = api.Resolve:GetCurrentTarget(module, step)
    if not target then
        log("GetCurrentTarget returned nil")
        return
    end
    log("target: mapID=%s x=%s y=%s", tostring(target.mapID), tostring(target.x), tostring(target.y))

    if not (target.mapID and target.x and target.y) then
        log("target missing mapID/x/y"); return
    end

    -- Record target so the guard can detect coordinate changes next call
    _lastTrackedMapID = target.mapID
    _lastTrackedX     = target.x
    _lastTrackedY     = target.y

    -- Build a descriptive name: prefer the active segment's text, fall back to step title
    local pinName = step.title or step.name or ("Step " .. stepIndex)
    if api.Resolve and api.Resolve.GetDisplaySegmentsForStep then
        local displaySegs = api.Resolve:GetDisplaySegmentsForStep(step, moduleId, stepIndex)
        for _, seg in ipairs(displaySegs) do
            if seg.kind ~= "NOTE" and (seg.text or "") ~= "" then
                pinName = seg.text
                -- Substitute {progress} token same as task rendering
                if seg.kind == "OBJECTIVE" and seg.showProgress ~= false
                    and api.Resolve and api.Resolve.GetSegmentProgressText then
                    local prog = api.Resolve:GetSegmentProgressText(seg)
                    if prog then
                        pinName = pinName:gsub("%{progress%}", (prog:gsub("%%", "%%%%")))
                    else
                        pinName = pinName:gsub("%{progress%}%s*", ""):gsub("%s+%.", ".")
                    end
                else
                    pinName = pinName:gsub("%{progress%}%s*", ""):gsub("%s+%.", ".")
                end
                break
            end
        end
    end

    log("WaypointUIAPI=%s", tostring(WaypointUIAPI ~= nil))

    -- Prefer WaypointUI's named navigation API so the pin gets a readable label
    -- WaypointUI expects coordinates in 0–100 scale; FTA provides 0–1 normalized
    if WaypointUIAPI and WaypointUIAPI.Navigation and WaypointUIAPI.Navigation.NewUserNavigation then
        local ok, err = pcall(function()
            WaypointUIAPI.Navigation.NewUserNavigation({
                name  = pinName,
                mapID = target.mapID,
                x     = target.x * 100,
                y     = target.y * 100,
            })
        end)
        if ok then
            log("WaypointUI nav set: mapID=%d x=%.4f y=%.4f name=%s", target.mapID, target.x, target.y, pinName)
        else
            log("WaypointUI NewUserNavigation failed: %s", tostring(err))
        end
        return
    end

    -- Fallback: raw Blizzard user waypoint (no custom name)
    log("UiMapPoint=%s C_Map.SetUserWaypoint=%s C_SuperTrack.SetSuperTrackedUserWaypoint=%s",
        tostring(UiMapPoint ~= nil),
        tostring(C_Map and C_Map.SetUserWaypoint ~= nil),
        tostring(C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint ~= nil))

    if UiMapPoint and C_Map and C_Map.SetUserWaypoint
        and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        local ok, err = pcall(function()
            local mapPoint = UiMapPoint.CreateFromCoordinates(target.mapID, target.x, target.y, 0)
            C_Map.SetUserWaypoint(mapPoint)
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end)
        if ok then
            log("waypoint set: mapID=%d x=%.4f y=%.4f", target.mapID, target.x, target.y)
        else
            log("SetUserWaypoint failed: %s", tostring(err))
        end
    else
        log("waypoint API not available — skipping map pin")
    end
end

-------------------------------------------------------------------------------
-- FTA UI refresh hook — ensures TrackerPlus re-renders whenever FTA refreshes
-- (covers FTA's own Prev/Next buttons, sync events, etc.)
-------------------------------------------------------------------------------
local _ftaRefreshHooked = false
local function EnsureFTARefreshHook()
    if _ftaRefreshHooked then return end
    local api = FollowTheArrowAPI
    if not (api and api.UI and type(api.UI.Refresh) == "function") then return end

    local orig = api.UI.Refresh
    api.UI.Refresh = function(self, ...)
        orig(self, ...)
        ApplyFTATracking(false)  -- guarded: no-ops if step hasn't changed
        addon:RequestUpdate()
    end
    _ftaRefreshHooked = true
end

-------------------------------------------------------------------------------
-- Navigation helpers
-------------------------------------------------------------------------------
local function NavigateFTA(delta)
    local api = FollowTheArrowAPI
    if not (api and api.StepEngine) then return end
    if delta < 0 then
        api.StepEngine:PrevStep()
    else
        api.StepEngine:NextStep()
    end
    ApplyFTATracking(true)  -- force: step just changed via our button
    addon:RequestUpdate()
end

local function ResetFTA()
    local api = FollowTheArrowAPI
    if not (api and api.StepEngine and api.StepEngine.SyncNow) then return end
    api.StepEngine:SyncNow(25)
    ApplyFTATracking(true)  -- force: step just changed via our button
    addon:RequestUpdate()
end

-------------------------------------------------------------------------------
-- RenderFollowTheArrowSection — FTA guide rendering in a dedicated pinned frame
-- Returns: ftaYOffset (total height consumed)
-------------------------------------------------------------------------------
function addon:RenderFollowTheArrowSection()
    local db = self.db
    local ftaFrame = self.ftaFrame
    local ftaYOffset = 0

    if not ftaFrame then return 0 end

    local shouldShow = db.includeFTAQuests
    if addon.LogAt then addon:LogAt("info", "[FTA] RenderFollowTheArrowSection called — includeFTAQuests=%s", tostring(shouldShow)) end

    if not shouldShow then
        ftaFrame:SetHeight(1)
        ftaFrame:Hide()
        return 0
    end

    local data = GetFTAData()
    if not data then
        if addon.LogAt then addon:LogAt("info", "[FTA] GetFTAData returned nil — hiding ftaFrame") end
        ftaFrame:SetHeight(1)
        ftaFrame:Hide()
        return 0
    end

    if addon.LogAt then addon:LogAt("info", "[FTA] rendering guide=%s step=%d/%d", tostring(data.moduleId), data.stepIndex, data.totalSteps) end

    EnsureFTARefreshHook()

    --------------------------------------------------------------------------
    -- Header row
    --------------------------------------------------------------------------
    local header = self:GetOrCreateButton(ftaFrame)
    header:SetPoint("TOPLEFT",  ftaFrame, "TOPLEFT",  0, 0)
    header:SetPoint("TOPRIGHT", ftaFrame, "TOPRIGHT", 0, 0)

    header.text:SetFont(db.headerFontFace, db.headerFontSize + 2, db.headerFontOutline)
    header.text:SetTextColor(1, 0.82, 0, 1) -- Gold
    header.text:SetText("Follow the Arrow")
    header.text:SetJustifyH("LEFT")
    header.text:ClearAllPoints()
    header.text:SetPoint("LEFT", 5, 0)
    header.text:SetPoint("RIGHT", -5, 0)

    -- Step counter: small, right-aligned, inside the header
    if not header._ftaCounter then
        header._ftaCounter = header:CreateFontString(nil, "OVERLAY")
    end
    header._ftaCounter:SetFont(db.fontFace, db.fontSize - 2, db.fontOutline)
    header._ftaCounter:SetTextColor(0.75, 0.75, 0.75, 1)
    header._ftaCounter:SetText(format("Steps %d/%d", data.stepIndex, data.totalSteps))
    header._ftaCounter:SetJustifyH("RIGHT")
    header._ftaCounter:ClearAllPoints()
    header._ftaCounter:SetPoint("RIGHT", header, "RIGHT", -6, 0)
    header._ftaCounter:Show()

    if header.expandBtn then header.expandBtn:Hide() end
    if header.poiButton  then header.poiButton:Hide()  end
    if header.itemButton then header.itemButton:Hide() end
    if header.icon       then header.icon:Hide()       end
    if header.objectives then for _, obj in ipairs(header.objectives) do obj:Hide() end end
    if header.objectiveProgresses then for _, obj in ipairs(header.objectiveProgresses) do obj:Hide() end end
    if header.progressBars then for _, bar in ipairs(header.progressBars) do bar:Hide() end end

    -- Styled backdrop
    if not header.styledBackdrop then
        header.styledBackdrop = CreateFrame("Frame", nil, header, "BackdropTemplate")
        if header:GetFrameLevel() > 1 then
            header.styledBackdrop:SetFrameLevel(header:GetFrameLevel() - 1)
        else
            header.styledBackdrop:SetFrameLevel(1)
            header:SetFrameLevel(2)
        end
        header.styledBackdrop:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 }
        })
        header.styledBackdrop:SetBackdropColor(0.2, 0.2, 0.2, 0.9)
        header.styledBackdrop:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end

    header.styledBackdrop:ClearAllPoints()
    header.styledBackdrop:SetPoint("TOPLEFT",  header, "TOPLEFT",  0, 0)
    header.styledBackdrop:SetPoint("TOPRIGHT", header, "TOPRIGHT", 0, 0)
    header.styledBackdrop:Show()
    header.bg:SetColorTexture(0, 0, 0, 0)

    header:SetHeight(30)
    header:Show()
    header._scriptMode = "ftaHeader"

    ftaYOffset = ftaYOffset + 30

    local indent = db.spacingMinorHeaderIndent + 10

    --------------------------------------------------------------------------
    -- Zone label (if non-empty)
    --------------------------------------------------------------------------
    if data.zone and data.zone ~= "" then
        if not ftaFrame._zoneLabel then
            ftaFrame._zoneLabel = ftaFrame:CreateFontString(nil, "OVERLAY")
        end
        local zl = ftaFrame._zoneLabel
        zl:SetFont(db.fontFace, db.fontSize, db.fontOutline)
        zl:SetTextColor(0.5, 0.8, 1, 1) -- Light blue zone color
        zl:SetText(data.zone)
        zl:SetJustifyH("LEFT")
        zl:ClearAllPoints()
        zl:SetPoint("TOPLEFT",  ftaFrame, "TOPLEFT",  indent, -ftaYOffset)
        zl:SetPoint("TOPRIGHT", ftaFrame, "TOPRIGHT", -5,     -ftaYOffset)
        zl:SetHeight(db.fontSize + 4)
        zl:Show()
        ftaYOffset = ftaYOffset + db.fontSize + 6
    else
        if ftaFrame._zoneLabel then ftaFrame._zoneLabel:Hide() end
    end

    --------------------------------------------------------------------------
    -- Step title
    --------------------------------------------------------------------------
    if not ftaFrame._titleLabel then
        ftaFrame._titleLabel = ftaFrame:CreateFontString(nil, "OVERLAY")
    end
    local tl = ftaFrame._titleLabel
    tl:SetFont(db.fontFace, db.fontSize, db.fontOutline)
    tl:SetTextColor(1, 1, 1, 1)
    tl:SetText(data.title)
    tl:SetJustifyH("LEFT")
    tl:SetWordWrap(true)
    tl:ClearAllPoints()
    tl:SetPoint("TOPLEFT",  ftaFrame, "TOPLEFT",  indent, -ftaYOffset)
    tl:SetPoint("TOPRIGHT", ftaFrame, "TOPRIGHT", -5,     -ftaYOffset)
    tl:SetHeight(0)
    tl:Show()
    -- Let height size to text
    local titleH = max(db.fontSize + 4, tl:GetStringHeight() + 2)
    tl:SetHeight(titleH)
    ftaYOffset = ftaYOffset + titleH + 4

    --------------------------------------------------------------------------
    -- Task list
    --------------------------------------------------------------------------
    -- Reuse or create task label pool on the frame
    ftaFrame._taskLabels = ftaFrame._taskLabels or {}
    local taskLabels = ftaFrame._taskLabels

    for i, taskText in ipairs(data.tasks) do
        if not taskLabels[i] then
            taskLabels[i] = ftaFrame:CreateFontString(nil, "OVERLAY")
        end
        local lbl = taskLabels[i]
        lbl:SetFont(db.fontFace, db.fontSize - 1, db.fontOutline)
        lbl:SetTextColor(db.objectiveColor.r, db.objectiveColor.g, db.objectiveColor.b, db.objectiveColor.a)
        lbl:SetText("• " .. taskText)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(true)
        lbl:ClearAllPoints()
        lbl:SetPoint("TOPLEFT",  ftaFrame, "TOPLEFT",  indent + 4, -ftaYOffset)
        lbl:SetPoint("TOPRIGHT", ftaFrame, "TOPRIGHT", -5,          -ftaYOffset)
        lbl:SetHeight(0)
        lbl:Show()
        local lblH = max(db.fontSize + 2, lbl:GetStringHeight() + 2)
        lbl:SetHeight(lblH)
        ftaYOffset = ftaYOffset + lblH + 2
    end
    -- Hide unused task labels
    for i = #data.tasks + 1, #taskLabels do
        taskLabels[i]:Hide()
    end

    --------------------------------------------------------------------------
    -- Notes
    --------------------------------------------------------------------------
    ftaFrame._noteLabels = ftaFrame._noteLabels or {}
    local noteLabels = ftaFrame._noteLabels

    if #data.notes > 0 then
        ftaYOffset = ftaYOffset + 4
    end
    for i, noteText in ipairs(data.notes) do
        if not noteLabels[i] then
            noteLabels[i] = ftaFrame:CreateFontString(nil, "OVERLAY")
        end
        local lbl = noteLabels[i]
        lbl:SetFont(db.fontFace, db.fontSize - 1, db.fontOutline)
        lbl:SetTextColor(0.8, 0.8, 0.6, 1) -- Slightly warm for notes
        lbl:SetText(noteText)
        lbl:SetJustifyH("LEFT")
        lbl:SetWordWrap(true)
        lbl:ClearAllPoints()
        lbl:SetPoint("TOPLEFT",  ftaFrame, "TOPLEFT",  indent + 4, -ftaYOffset)
        lbl:SetPoint("TOPRIGHT", ftaFrame, "TOPRIGHT", -5,          -ftaYOffset)
        lbl:SetHeight(0)
        lbl:Show()
        local lblH = max(db.fontSize + 2, lbl:GetStringHeight() + 2)
        lbl:SetHeight(lblH)
        ftaYOffset = ftaYOffset + lblH + 2
    end
    for i = #data.notes + 1, #noteLabels do
        noteLabels[i]:Hide()
    end

    --------------------------------------------------------------------------
    -- Navigation buttons: Prev | Next | 🔁 | FTA
    --------------------------------------------------------------------------
    ftaYOffset = ftaYOffset + 6

    if not ftaFrame._navRow then
        ftaFrame._navRow = CreateFrame("Frame", nil, ftaFrame)
        ftaFrame._navRow:SetHeight(22)

        local btnPrev = CreateFrame("Button", nil, ftaFrame._navRow, "UIPanelButtonTemplate")
        btnPrev:SetSize(50, 20)
        btnPrev:SetPoint("TOPLEFT", ftaFrame._navRow, "TOPLEFT", 0, -1)
        btnPrev:SetText("Prev")
        btnPrev:SetScript("OnClick", function() NavigateFTA(-1) end)
        ftaFrame._navRow.btnPrev = btnPrev

        local btnNext = CreateFrame("Button", nil, ftaFrame._navRow, "UIPanelButtonTemplate")
        btnNext:SetSize(50, 20)
        btnNext:SetPoint("TOPLEFT", btnPrev, "TOPRIGHT", 4, 0)
        btnNext:SetText("Next")
        btnNext:SetScript("OnClick", function() NavigateFTA(1) end)
        ftaFrame._navRow.btnNext = btnNext

        local btnReset = CreateFrame("Button", nil, ftaFrame._navRow, "UIPanelButtonTemplate")
        btnReset:SetSize(28, 20)
        btnReset:SetPoint("TOPLEFT", btnNext, "TOPRIGHT", 4, 0)
        btnReset:SetText("|TInterface\\Buttons\\UI-RefreshButton:14:14:0:0|t")
        btnReset:SetScript("OnClick", function() ResetFTA() end)
        btnReset:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText("Reset to current step", 1, 1, 1)
            GameTooltip:Show()
        end)
        btnReset:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ftaFrame._navRow.btnReset = btnReset

        local btnFTA = CreateFrame("Button", nil, ftaFrame._navRow, "UIPanelButtonTemplate")
        btnFTA:SetSize(40, 20)
        btnFTA:SetPoint("TOPRIGHT", ftaFrame._navRow, "TOPRIGHT", 0, -1)
        btnFTA:SetText("FTA")
        btnFTA:SetScript("OnClick", function()
            local api = FollowTheArrowAPI
            if api and api.UI and api.UI.ToggleMain then
                api.UI:ToggleMain()
            end
        end)
        ftaFrame._navRow.btnFTA = btnFTA
    end

    local navRow = ftaFrame._navRow
    navRow:ClearAllPoints()
    navRow:SetPoint("TOPLEFT",  ftaFrame, "TOPLEFT",  indent, -ftaYOffset)
    navRow:SetPoint("TOPRIGHT", ftaFrame, "TOPRIGHT", -5,     -ftaYOffset)
    navRow:Show()
    ftaYOffset = ftaYOffset + 22 + 6

    --------------------------------------------------------------------------
    -- Extend backdrop to cover all content
    --------------------------------------------------------------------------
    local backdropPadding = 8
    header.styledBackdrop:SetHeight(ftaYOffset + backdropPadding)
    ftaYOffset = ftaYOffset + backdropPadding

    --------------------------------------------------------------------------
    -- Size and show/hide the frame
    --------------------------------------------------------------------------
    ftaFrame:SetHeight(max(30, ftaYOffset))
    if addon.db.minimized then
        ftaFrame:Hide()
    else
        ftaFrame:Show()
    end

    return ftaYOffset
end
