-- 전역 변수 설정 (Local 문제 해결)
dragTimer = nil
isDragLocked = false
ignoreNextUp = false
releaseNextUp = false
keyBuffer = ""
dragAlertStyle = { textSize = 16, radius = 8 }

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

-- 1. 텍스트 대치:
--    - 'qst' 또는 'ㅂㄴㅅ' -> '?'
--    - 'trg' 또는 'ㅅㄱㅎ' -> '()'
--------------------------------------------------------------------------------
textWatcher = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
    local char = event:getCharacters()
    local flags = event:getFlags()

    -- Cmd, Ctrl, Alt가 눌리지 않은 상태만 체크
    if not (flags.cmd or flags.ctrl or flags.alt) and char then
        keyBuffer = keyBuffer .. char
        
        -- [수정됨] 한글 3글자(9바이트)를 담기 위해 버퍼 크기를 20바이트로 넉넉하게 늘림
        if #keyBuffer > 20 then 
            keyBuffer = string.sub(keyBuffer, -20) 
        end

        -- 'qst' 또는 'ㅂㄴㅅ' 감지
        if string.match(keyBuffer, "qst$") or string.match(keyBuffer, "ㅂㄴㅅ$") then
            -- 백스페이스 3번 빠르게 전송
            hs.eventtap.event.newKeyEvent({}, "delete", true):post()
            hs.eventtap.event.newKeyEvent({}, "delete", false):post()
            hs.eventtap.event.newKeyEvent({}, "delete", true):post()
            hs.eventtap.event.newKeyEvent({}, "delete", false):post()
            hs.eventtap.event.newKeyEvent({}, "delete", true):post()
            hs.eventtap.event.newKeyEvent({}, "delete", false):post()
            
            -- '?' 문자 자체를 입력
            hs.eventtap.keyStrokes("?")
            
            keyBuffer = ""
        end

        -- 'trg' 또는 'ㅅㄱㅎ' 감지
        if string.match(keyBuffer, "trg$") or string.match(keyBuffer, "ㅅㄱㅎ$") then
            -- 백스페이스 3번 빠르게 전송
            hs.eventtap.event.newKeyEvent({}, "delete", true):post()
            hs.eventtap.event.newKeyEvent({}, "delete", false):post()
            hs.eventtap.event.newKeyEvent({}, "delete", true):post()
            hs.eventtap.event.newKeyEvent({}, "delete", false):post()
            hs.eventtap.event.newKeyEvent({}, "delete", true):post()
            hs.eventtap.event.newKeyEvent({}, "delete", false):post()

            -- '()' 문자 자체를 입력
            hs.eventtap.keyStrokes("()")
            
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
            hs.alert.show("드래그 해제", 0.2, dragAlertStyle)
            return true -- 이번 하드웨어 클릭은 무시
        else
            -- 일반 클릭 -> 0.5초 타이머 시작
            dragTimer = hs.timer.doAfter(0.25, function()
                isDragLocked = true
                ignoreNextUp = true
                hs.alert.show("드래그 고정", 0.2, dragAlertStyle)
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
