local scriptPath = os.getenv("HOME") .. "/.hammerspoon/scripts/paste-clipboard-image-to-finder.sh"
local finderBundleID = "com.apple.finder"
local pasteKeyCode = hs.keycodes.map.v
local filePasteboardTypes = {
    ["apple files promise pasteboard type"] = true,
    ["com.apple.finder.node"] = true,
    ["com.apple.pasteboard.promised-file-url"] = true,
    ["nsfilenamespboardtype"] = true,
    ["public.file-url"] = true,
}
local imagePasteboardTypes = {
    ["apple png pasteboard type"] = true,
    ["com.apple.icns"] = true,
    ["com.compuserve.gif"] = true,
    ["com.microsoft.bmp"] = true,
    ["next tiff v4.0 pasteboard type"] = true,
    ["public.bmp"] = true,
    ["public.gif"] = true,
    ["public.heic"] = true,
    ["public.heif"] = true,
    ["public.image"] = true,
    ["public.jpeg"] = true,
    ["public.jpeg-2000"] = true,
    ["public.png"] = true,
    ["public.tiff"] = true,
}

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

local function clipboardContentTypes()
    local contentTypesFn = hs.pasteboard.contentTypes or hs.pasteboard.allContentTypes
    if type(contentTypesFn) ~= "function" then
        return nil
    end

    local ok, types = pcall(contentTypesFn)
    if ok and type(types) == "table" then
        return types
    end

    return nil
end

local function clipboardTypesContain(types, candidates)
    for _, pasteboardType in pairs(types) do
        if type(pasteboardType) == "table" then
            if clipboardTypesContain(pasteboardType, candidates) then
                return true
            end
        else
            local normalizedType = string.lower(tostring(pasteboardType))
            if candidates[normalizedType] then
                return true
            end
        end
    end

    return false
end

local function clipboardContainsStandaloneImage()
    local types = clipboardContentTypes()
    if not types then
        return false
    end

    if clipboardTypesContain(types, filePasteboardTypes) then
        return false
    end

    return clipboardTypesContain(types, imagePasteboardTypes)
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

        if string.find(output, "Clipboard does not contain an image", 1, true)
            or string.find(output, "Clipboard contains file references", 1, true) then
            sendNativeFinderPaste()
            return
        end

        if string.find(output, "User cancelled filename prompt", 1, true) then
            return
        end

        if string.find(output, "Filename is empty", 1, true) then
            notify("파일 이름이 비어 있음")
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

    if not clipboardContainsStandaloneImage() then
        return false
    end

    pasteClipboardImageToFinder()
    return true
end):start()
