local scriptPath = os.getenv("HOME") .. "/.hammerspoon/scripts/paste-clipboard-image-to-finder.sh"
local finderBundleID = "com.apple.finder"
local pasteKeyCode = hs.keycodes.map.v

finderPastePassthrough = finderPastePassthrough or false
finderPasteTask = finderPasteTask or nil

local function notify(message)
    if type(showStatusAlert) == "function" then
        showStatusAlert(message)
    else
        hs.alert.show(message)
    end
end

local function frontAppIsFinder()
    local app = hs.application.frontmostApplication()
    return app and app:bundleID() == finderBundleID
end

local function isPlainCommandV(event)
    local flags = event:getFlags()

    return event:getKeyCode() == pasteKeyCode
        and flags.cmd
        and not (flags.ctrl or flags.alt or flags.shift or flags.fn)
end

local function sendNativeFinderPaste()
    finderPastePassthrough = true
    hs.eventtap.keyStroke({"cmd"}, "v", 0)

    hs.timer.doAfter(0.25, function()
        finderPastePassthrough = false
    end)
end

local function finderTargetFolder()
    local ok, result = hs.osascript.applescript([[
        tell application "Finder"
            try
                set targetFolder to insertion location as alias
            on error
                if (count of Finder windows) > 0 then
                    set targetFolder to target of front Finder window as alias
                else
                    set targetFolder to path to desktop folder
                end if
            end try

            return POSIX path of targetFolder
        end tell
    ]])

    if ok and type(result) == "string" and result ~= "" then
        return result
    end

    return nil
end

local function pasteClipboardImageToFinder()
    if not hs.fs.attributes(scriptPath) then
        notify("이미지 붙여넣기 스크립트 없음")
        sendNativeFinderPaste()
        return
    end

    if finderPasteTask and finderPasteTask:isRunning() then
        return
    end

    local folder = finderTargetFolder()
    local taskArguments = {}
    if folder then
        taskArguments = {folder}
    end

    finderPasteTask = hs.task.new(scriptPath, function(exitCode, stdOut, stdErr)
        finderPasteTask = nil

        local output = (stdOut or "") .. (stdErr or "")

        if exitCode == 0 then
            notify("이미지 붙여넣기 완료")
            return
        end

        if string.find(output, "Clipboard does not contain an image", 1, true) then
            sendNativeFinderPaste()
            return
        end

        notify("이미지 붙여넣기 실패")
        hs.printf("Finder image paste failed: %s", output)
    end, taskArguments)

    finderPasteTask:start()
end

finderPasteWatcher = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
    if not isPlainCommandV(event) or not frontAppIsFinder() then
        return false
    end

    if finderPastePassthrough then
        finderPastePassthrough = false
        return false
    end

    pasteClipboardImageToFinder()
    return true
end):start()
