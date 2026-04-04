-- 전역 변수 설정 (Local 문제 해결)
dragTimer = nil
isDragLocked = false
ignoreNextUp = false
releaseNextUp = false
dragFeatureEnabled = true
keyBuffer = ""
dragAlertStyle = { textSize = 16, radius = 8 }
karabinerChromeProfile = "chrome"
karabinerCliPath = "/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
karabinerConfigPath = os.getenv("HOME") .. "/.config/karabiner/karabiner.json"
karabinerPreviousProfile = nil
karabinerDidChangeProfile = false
remoteDesktopActive = false
copyKeyCode = hs.keycodes.map.c

function showStatusAlert(message)
    hs.alert.show(message, 0.2, dragAlertStyle)
end

function containsIgnoreCase(text, pattern)
    if not text or not pattern then return false end
    return string.find(string.lower(text), string.lower(pattern), 1, true) ~= nil
end

function getSelectedKarabinerProfile()
    if not hs.fs.attributes(karabinerConfigPath) then return nil end

    local karabinerConfig = hs.json.read(karabinerConfigPath)
    if not karabinerConfig or not karabinerConfig.profiles then return nil end

    for _, profile in ipairs(karabinerConfig.profiles) do
        if profile.selected then
            return profile.name
        end
    end

    return nil
end

function selectKarabinerProfile(profileName)
    if not profileName or not hs.fs.attributes(karabinerCliPath) then return end

    hs.task.new(karabinerCliPath, nil, {
        "--select-profile",
        profileName
    }):start()
end

function syncKarabinerProfile(isRemoteDesktopEnabled)
    local selectedProfile = getSelectedKarabinerProfile()

    if isRemoteDesktopEnabled then
        if selectedProfile and selectedProfile ~= karabinerChromeProfile then
            karabinerPreviousProfile = selectedProfile
            karabinerDidChangeProfile = true
        else
            karabinerPreviousProfile = nil
            karabinerDidChangeProfile = false
        end

        if selectedProfile ~= karabinerChromeProfile then
            selectKarabinerProfile(karabinerChromeProfile)
        end
        return
    end

    if karabinerDidChangeProfile
        and karabinerPreviousProfile
        and selectedProfile == karabinerChromeProfile then
        selectKarabinerProfile(karabinerPreviousProfile)
    end
    karabinerPreviousProfile = nil
    karabinerDidChangeProfile = false
end

function resetDragLockState()
    if dragTimer then
        dragTimer:stop()
        dragTimer = nil
    end

    local wasDragLocked = isDragLocked
    isDragLocked = false
    ignoreNextUp = false
    releaseNextUp = false

    if wasDragLocked then
        local pos = hs.mouse.absolutePosition()
        hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseUp, pos):post()
    end
end

function setDragFeatureEnabled(enabled)
    if dragFeatureEnabled == enabled then return end

    dragFeatureEnabled = enabled

    if enabled then
        mouseWatcher:start()
        return
    end

    resetDragLockState()
    mouseWatcher:stop()
end

function getFrontChromeURL()
    local ok, result = hs.osascript.applescript([[
        tell application "Google Chrome"
            if (count of windows) = 0 then return ""
            return URL of active tab of front window
        end tell
    ]])

    if ok and type(result) == "string" then
        return result
    end

    return ""
end

function isChromeRemoteDesktopActive()
    local frontApp = hs.application.frontmostApplication()
    if not frontApp then return false end

    local appName = frontApp:name() or ""
    local bundleID = frontApp:bundleID() or ""
    local frontWindow = hs.window.frontmostWindow()
    local windowTitle = frontWindow and frontWindow:title() or ""

    if containsIgnoreCase(appName, "Chrome Remote Desktop")
        or containsIgnoreCase(appName, "Chrome 원격 데스크톱")
        or containsIgnoreCase(bundleID, "chromoting") then
        return true
    end

    if appName ~= "Google Chrome" then
        return false
    end

    if containsIgnoreCase(windowTitle, "Chrome Remote Desktop")
        or containsIgnoreCase(windowTitle, "Chrome 원격 데스크톱") then
        return true
    end

    local currentURL = string.lower(getFrontChromeURL())
    return string.find(currentURL, "remotedesktop.google.com", 1, true) ~= nil
        or string.find(currentURL, "chromoting", 1, true) ~= nil
        or string.find(currentURL, "chrome%-remote%-desktop") ~= nil
end

function refreshRemoteDesktopState()
    local isActive = isChromeRemoteDesktopActive()
    if remoteDesktopActive == isActive then return end

    remoteDesktopActive = isActive
    syncKarabinerProfile(isActive)
    setDragFeatureEnabled(not isActive)
end

-- 설정 자동 리로드
hs.alert.show("Hammerspoon 설정 로드됨")
function reloadConfig(files)
    local doReload = false
    for _, file in pairs(files) do
        if file:sub(-4) == ".lua" then doReload = true end
    end
    if doReload then hs.reload() end
end
configWatcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", reloadConfig):start()

--------------------------------------------------------------------------------
-- 1. 텍스트 대치: 'qst'/'ㅂㄴㅅ' -> '?', 'trg'/'ㅅㄱㅎ' -> '()'
--------------------------------------------------------------------------------
textWatcher = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
    local char = event:getCharacters()
    local flags = event:getFlags()
    local isAutoRepeat = event:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) == 1

    if event:getKeyCode() == copyKeyCode
        and flags.cmd
        and not (flags.ctrl or flags.alt or flags.fn or flags.shift)
        and not isAutoRepeat then
        hs.timer.doAfter(0.05, function()
            showStatusAlert("복사 성공")
        end)
    end

    -- Cmd, Ctrl, Alt가 눌리지 않은 상태만 체크
    if not (flags.cmd or flags.ctrl or flags.alt) and char then
        keyBuffer = keyBuffer .. char
        
        -- [수정됨] 한글 3글자(9바이트)를 담기 위해 버퍼 크기를 20바이트로 넉넉하게 늘림
        if #keyBuffer > 20 then 
            keyBuffer = string.sub(keyBuffer, -20) 
        end

        -- 텍스트 대치 감지
        if string.match(keyBuffer, "qst$") or string.match(keyBuffer, "ㅂㄴㅅ$") then
            -- 백스페이스 3번 빠르게 전송
            hs.eventtap.event.newKeyEvent({}, "delete", true):post()
            hs.eventtap.event.newKeyEvent({}, "delete", false):post()
            hs.eventtap.event.newKeyEvent({}, "delete", true):post()
            hs.eventtap.event.newKeyEvent({}, "delete", false):post()
            hs.eventtap.event.newKeyEvent({}, "delete", true):post()
            hs.eventtap.event.newKeyEvent({}, "delete", false):post()

            -- '?' 입력
            hs.eventtap.event.newKeyEvent({"shift"}, "/", true):post()
            hs.eventtap.event.newKeyEvent({"shift"}, "/", false):post()

            keyBuffer = ""
        elseif string.match(keyBuffer, "trg$") or string.match(keyBuffer, "ㅅㄱㅎ$") then
            -- 백스페이스 3번 빠르게 전송
            hs.eventtap.event.newKeyEvent({}, "delete", true):post()
            hs.eventtap.event.newKeyEvent({}, "delete", false):post()
            hs.eventtap.event.newKeyEvent({}, "delete", true):post()
            hs.eventtap.event.newKeyEvent({}, "delete", false):post()
            hs.eventtap.event.newKeyEvent({}, "delete", true):post()
            hs.eventtap.event.newKeyEvent({}, "delete", false):post()

            -- '()' 입력
            hs.eventtap.event.newKeyEvent({"shift"}, "9", true):post()
            hs.eventtap.event.newKeyEvent({"shift"}, "9", false):post()
            hs.eventtap.event.newKeyEvent({"shift"}, "0", true):post()
            hs.eventtap.event.newKeyEvent({"shift"}, "0", false):post()
            -- 커서를 소괄호 안으로 이동
            hs.eventtap.event.newKeyEvent({}, "left", true):post()
            hs.eventtap.event.newKeyEvent({}, "left", false):post()

            keyBuffer = ""
        end
    end
    return false
end):start()

--------------------------------------------------------------------------------
-- 2. 마우스 드래그 락 (순간이동 해결 버전)
--------------------------------------------------------------------------------
mouseWatcher = hs.eventtap.new({
    hs.eventtap.event.types.leftMouseDown,
    hs.eventtap.event.types.leftMouseUp,
    hs.eventtap.event.types.mouseMoved
}, function(event)
    local type = event:getType()

    -- [1] 마우스 이동 감지 (MouseMoved)
    if type == hs.eventtap.event.types.mouseMoved then
        if isDragLocked then
            -- 물리 버튼은 떨어져 있지만(Moved), 시스템에는 드래그 중(Dragged)이라고 속여야 함
            -- 기존 이벤트를 차단하지 않고 '타입만 변경'하여 시스템 부하를 줄이고 반응속도 UP
            event:setType(hs.eventtap.event.types.leftMouseDragged)
            return false -- 변경된 이벤트(Dragged)를 시스템으로 통과시킴
        end
        return false -- 일반 이동은 그냥 통과

    -- [2] 마우스 누름 (MouseDown)
    elseif type == hs.eventtap.event.types.leftMouseDown then
        if isDragLocked then
            -- 이미 락 상태에서 클릭 -> 해제 로직
            isDragLocked = false
            releaseNextUp = true -- 해제를 위한 클릭의 Up 무시 플래그
            
            -- 강제로 마우스 업 이벤트를 발생시켜 드래그 종료 알림
            local pos = event:location()
            hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseUp, pos):post()
            showStatusAlert("드래그 해제")
            return true -- 이번 하드웨어 클릭은 무시
        else
            -- 일반 클릭 -> 0.5초 타이머 시작
            dragTimer = hs.timer.doAfter(0.25, function()
                isDragLocked = true
                ignoreNextUp = true
                showStatusAlert("드래그 고정")
            end)
            return false
        end

    -- [3] 마우스 뗌 (MouseUp)
    elseif type == hs.eventtap.event.types.leftMouseUp then
        if dragTimer then
            dragTimer:stop()
            dragTimer = nil
        end

        if ignoreNextUp then
            -- 드래그 락 시작 직후의 물리적 뗌 -> 무시 (시스템은 계속 눌린 것으로 인식)
            ignoreNextUp = false
            return true
        end

        if releaseNextUp then
            -- 해제 클릭의 물리적 뗌 -> 무시
            releaseNextUp = false
            return true
        end
        
        return false
    end
end):start()

remoteDesktopWatcher = hs.timer.doEvery(1, refreshRemoteDesktopState)
refreshRemoteDesktopState()
