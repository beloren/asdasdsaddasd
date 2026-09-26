local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local CUTSCENE_SOUND_ID = "rbxassetid://79630404482015"
local LOGO_IMAGE_ID = "rbxassetid://113042882863397"
local LOGO_SOUND_ID = "rbxassetid://136181063165778"

if shared.MoonAnimationTestLoaded then
    warn("[MoonAnimationTest] Duplicate controller was blocked")
    return
end
shared.MoonAnimationTestLoaded = true

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local cutsceneFinished = ReplicatedStorage.Shared:WaitForChild("CutsceneFinished")

player:SetAttribute("IntroActive", true)
player:SetAttribute("IntroFailed", nil)
player:SetAttribute("CutsceneStarted", nil)

local disabledExamples = {
    PlayAnimation = true,
    ReplicateExample = true,
}

for _, container in {playerGui, player:WaitForChild("PlayerScripts")} do
    for _, descendant in container:GetDescendants() do
        if descendant:IsA("LocalScript") and disabledExamples[descendant.Name] then
            descendant.Disabled = true
        elseif descendant:IsA("LocalScript") and descendant.Name == "PlayScene" then
            descendant:Destroy()
        end
    end
end

local transitionGui = Instance.new("ScreenGui")
transitionGui.Name = "IntroTransition"
transitionGui.ResetOnSpawn = false
transitionGui.IgnoreGuiInset = true
transitionGui.DisplayOrder = 2000
transitionGui.ScreenInsets = Enum.ScreenInsets.None
transitionGui.ClipToDeviceSafeArea = false
transitionGui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.FullscreenExtension
transitionGui.Parent = playerGui

--------------------------------------------------------------------------------
-- КНОПКА SKIP
--
-- ЗАЧЕМ. Катсцена играет при КАЖДОМ заходе и всем подряд — а игрок, который
-- заходит по нескольку раз в день, смотрит её по нескольку раз в день. Для
-- возвращающегося игрока это чистый налог на вход: он уже знает, что там,
-- и всё, что он видит, — это препятствие между ним и игрой. Пропуск снимает
-- этот налог, ничего не отнимая у тех, кто видит сцену впервые.
--
-- ОФОРМЛЕНИЕ намеренно скромное: без подложки, белые буквы с чёрной
-- обводкой, слева снизу. Кнопка должна быть заметной ровно настолько, чтобы
-- её нашёл тот, кто её ИЩЕТ, и не перетягивала внимание у того, кто смотрит
-- сцену в первый раз.
--
-- МОБИЛЬНЫЕ. Это обычный TextButton, а не эмуляция клика по Frame, поэтому
-- MouseButton1Click срабатывает и от тапа по экрану, и от клика мышью, и от
-- геймпада — отдельной ветки под тач не требуется. Размер задан в Scale с
-- ограничителем по пикселям, чтобы на узком экране не превратиться в точку.
--------------------------------------------------------------------------------
local skipButton = Instance.new("TextButton")
skipButton.Name = "SkipButton"
skipButton.AnchorPoint = Vector2.new(0, 1)
skipButton.Position = UDim2.new(0, 24, 1, -24)
skipButton.Size = UDim2.fromScale(0.13, 0.055)
skipButton.BackgroundTransparency = 1
skipButton.AutoButtonColor = false
skipButton.Text = "SKIP"
skipButton.Font = Enum.Font.GothamBold
skipButton.TextColor3 = Color3.new(1, 1, 1)
skipButton.TextStrokeColor3 = Color3.new(0, 0, 0)
skipButton.TextStrokeTransparency = 0
skipButton.TextScaled = true
skipButton.TextXAlignment = Enum.TextXAlignment.Left
skipButton.TextTransparency = 1 -- проявляется вместе со стартом сцены
skipButton.Visible = false
skipButton.ZIndex = 50
skipButton.Parent = transitionGui

local skipSizeLimit = Instance.new("UISizeConstraint")
skipSizeLimit.MinSize = Vector2.new(64, 26)
skipSizeLimit.MaxSize = Vector2.new(150, 54)
skipSizeLimit.Parent = skipButton

local blackLayer = Instance.new("Frame")
blackLayer.Name = "BlackLayer"
blackLayer.AnchorPoint = Vector2.new(0.5, 0.5)
blackLayer.Position = UDim2.fromScale(0.5, 0.35)
blackLayer.Size = UDim2.new(1, 400, 1, 900)
blackLayer.BackgroundColor3 = Color3.new(0, 0, 0)
blackLayer.BackgroundTransparency = 1
blackLayer.BorderSizePixel = 0
blackLayer.ZIndex = 0
blackLayer.Parent = transitionGui

local transition = Instance.new("CanvasGroup")
transition.Name = "Transition"
transition.AnchorPoint = Vector2.new(0.5, 0.5)
transition.Position = UDim2.fromScale(0.5, 0.5)
transition.Size = UDim2.new(1, 400, 1, 400)
transition.BackgroundColor3 = Color3.new(0, 0, 0)
transition.BackgroundTransparency = 1
transition.BorderSizePixel = 0
transition.ZIndex = 1
transition.Parent = transitionGui

local logo = Instance.new("ImageLabel")
logo.Name = "Logo"
logo.AnchorPoint = Vector2.new(0.5, 0.5)
logo.Position = UDim2.fromScale(0.5, 0.5)
logo.Size = UDim2.fromScale(0.32, 0.32)
logo.BackgroundTransparency = 1
logo.Image = LOGO_IMAGE_ID
logo.ImageTransparency = 1
logo.ScaleType = Enum.ScaleType.Fit
logo.Parent = transition

local logoAspect = Instance.new("UIAspectRatioConstraint")
logoAspect.AspectRatio = 1
logoAspect.Parent = logo

local logoSize = Instance.new("UISizeConstraint")
logoSize.MinSize = Vector2.new(150, 150)
logoSize.MaxSize = Vector2.new(380, 380)
logoSize.Parent = logo

local logoScale = Instance.new("UIScale")
logoScale.Scale = 0.86
logoScale.Parent = logo

local activePlayer
local activeRigPlayer
local activeRigAnimation
local activeSound
local logoSound
local busy = false
local ending = false
local coverStarted = false
local coverComplete = false

local suppressedGuis = {}
local guiGuards = {}

-- НИКОГДА не глушим экранное управление. Это отдельный ScreenGui, который
-- PlayerModule создаёт в PlayerGui на тач-устройствах: "TouchGui" (джойстик +
-- кнопка прыжка) и "ControlGui" у старых сборок. Раньше он попадал под общую
-- зачистку интерфейса наравне с игровыми окнами — и на телефоне это стоило
-- игроку всего управления: suppressGui безусловно ставит gui.Enabled = false,
-- а сторожевой таймер (ниже) возвращал управление, НЕ разбирая подавление
-- обратно, так что заново созданный Controls:Enable()-ом TouchGui тут же
-- ловился ChildAdded и снова гасился — уже навсегда, без единого пути назад.
-- На ПК баг был не виден вообще: там управление не живёт в ScreenGui.
local CONTROL_GUI_NAMES = {
    TouchGui = true,
    ControlGui = true,
}

local function isControlGui(gui)
    return CONTROL_GUI_NAMES[gui.Name] == true
end

local function shouldSuppress(gui)
    return (gui:IsA("ScreenGui") or gui:IsA("BillboardGui") or gui:IsA("SurfaceGui"))
        and gui ~= transitionGui
        and gui.Name ~= "LoadingScreen"
        and gui.Name ~= "PreloadScreen"
        and not isControlGui(gui)
end

local function suppressGui(gui)
    if not shouldSuppress(gui) or suppressedGuis[gui] then
        return
    end

    suppressedGuis[gui] = {enabled = gui.Enabled}
    gui.Enabled = false
    guiGuards[gui] = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
        if player:GetAttribute("IntroActive") == true and gui.Enabled then
            gui.Enabled = false
        end
    end)
end

for _, child in playerGui:GetChildren() do
    suppressGui(child)
end
local guiAddedConnection = playerGui.ChildAdded:Connect(suppressGui)
for _, descendant in workspace:GetDescendants() do
    suppressGui(descendant)
end
local worldGuiAddedConnection = workspace.DescendantAdded:Connect(suppressGui)

local coreGuiStates = {}
for _, coreGuiType in Enum.CoreGuiType:GetEnumItems() do
    if coreGuiType ~= Enum.CoreGuiType.All then
        pcall(function()
            coreGuiStates[coreGuiType] = StarterGui:GetCoreGuiEnabled(coreGuiType)
        end)
    end
end
pcall(function()
    StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
end)

local controls
local function acquireControls()
	if controls then return controls end
	pcall(function()
		local playerScripts = player:FindFirstChild("PlayerScripts")
			or player:WaitForChild("PlayerScripts", 5)
		local playerModule = playerScripts and (playerScripts:FindFirstChild("PlayerModule")
			or playerScripts:WaitForChild("PlayerModule", 5))
		if playerModule then
			controls = require(playerModule):GetControls()
		end
	end)
	return controls
end

-- ПО ПРЯМОМУ ЗАПРОСУ: УПРАВЛЕНИЕ ВООБЩЕ НЕ ОТКЛЮЧАЕТСЯ.
--
-- Раньше здесь стояло:
--     acquireControls()
--     if controls then controls:Disable() end
-- то есть управление отключалось СРАЗУ при загрузке скрипта и включалось
-- обратно только в одном из выходов интро (finishIntro / failIntro /
-- сторожевой таймер). На это было навешано три отдельных слоя страховки —
-- сторожевой таймер с укороченным до 12с таймаутом, мгновенный выход по
-- нажатию клавиши движения, и отдельный сторонний скрипт
-- EnsureTouchControls.client.lua — и НИ ОДИН из них не убирал жалобы
-- полностью, особенно на мобильных: Controls:Disable() уничтожает TouchGui
-- (джойстик + кнопка прыжка) целиком, а пересоздание его обратно —
-- асинхронная операция с своими гонками.
--
-- Самая надёжная страховка — не создавать ситуацию, которую приходится
-- страховать. Да, теперь игрок технически МОЖЕТ походить в первые секунды
-- после захода, пока на экране логотип/чёрный экран поверх него
-- (transitionGui закрывает вид полностью, так что смысла в этом всё равно
-- нет) — это сознательный компромисс. Он несравнимо лучше прежнего
-- поведения, где отключение управления иногда не отменялось НИКОГДА.
-- Дойти пешком куда-то важное за эти секунды нельзя: сервер, как только
-- получит cutsceneFinished (штатно от клиента либо по своему собственному
-- таймауту CUTSCENE_SERVER_TIMEOUT в Main.server.lua), в любом случае
-- переставит персонажа на его личный участок — откуда бы игрок к тому
-- моменту ни ушёл.
--
-- PlayerModule создаёт TouchGui (джойстик + кнопка прыжка) при заходе один
-- раз и держит его включённым всю сессию — раз мы больше не трогаем
-- Controls:Disable(), нам и не нужно потом гоняться за пересозданием этого
-- GUI и его гонками, как раньше.
--
-- controls всё ещё достаётся (acquireControls) — он нужен как объект для
-- остальных вызовов Enable() ниже по файлу (finishIntro/failIntro и
-- сторожевой таймер всё ещё существуют как защита от ДРУГИХ багов, просто
-- теперь они безобидны: Enable() на уже включённом контроле не делает
-- ничего).
acquireControls()

-- Идемпотентно и безусловно возвращает управление. Вызывается из обоих
-- штатных путей И из сторожевого таймера ниже.
-- Идемпотентно и безусловно возвращает управление. Вызывается из обоих
-- штатных путей И из сторожевого таймера ниже.
--
-- На ТЕЛЕФОНЕ одного Controls:Enable() мало. Controls:Disable() убирает
-- TouchGui целиком, а Enable() создаёт его ЗАНОВО — новым объектом и не
-- мгновенно. Поэтому после Enable() отдельно дожидаемся появления TouchGui и
-- проверяем, что он действительно включён: если что-то (наш же ChildAdded,
-- чужой скрипт, гонка при респавне) успело его погасить — включаем руками.
-- Без этой проверки игрок на телефоне оставался стоять на месте без единой
-- кнопки на экране, и лечил это только ресет персонажа.
local function forceTouchControlsVisible()
    if not UserInputService.TouchEnabled then return end
    pcall(function()
        for _, gui in playerGui:GetChildren() do
            if gui:IsA("ScreenGui") and isControlGui(gui) and not gui.Enabled then
                gui.Enabled = true
            end
        end
    end)
end

-- controlsRestored начинается с TRUE: управление никогда не отключалось,
-- отключать/восстанавливать больше нечего. Переменная и restoreControls()
-- ниже оставлены НЕ ради самого включения (Enable() на уже включённом
-- контроле — no-op), а как страховка на случай, если что-то ДРУГОЕ, не
-- этот скрипт, вызовет Disable() (чужой билд, эксплойтер, будущая правка) —
-- тогда finishIntro/failIntro/сторожевой таймер всё ещё смогут его вернуть.
local controlsRestored = true
local controlsRestorePending = false
local function restoreControls()
	if controlsRestorePending then return end
	controlsRestorePending = true
	task.spawn(function()
		local deadline = os.clock() + 10
		local resolved
		repeat
			resolved = acquireControls()
			if resolved then break end
			task.wait(0.2)
		until os.clock() >= deadline
		if resolved then
			pcall(function() resolved:Enable() end)
			-- TouchGui создаётся асинхронно — проверяем несколько раз в
			-- течение пары секунд, а не однократно сразу после Enable().
			task.spawn(function()
				for _ = 1, 10 do
					forceTouchControlsVisible()
					task.wait(0.2)
				end
			end)
		else
			warn("[MoonAnimationTest] PlayerModule controls не загрузились - повторю восстановление при следующем запросе")
		end
		controlsRestorePending = false
	end)
end

-- introEnded — ОТДЕЛЬНЫЙ флаг от controlsRestored (см. подробный комментарий
-- там про то, почему controlsRestored теперь тривиально true с самого
-- начала). Этот означает «интро дошло до конца одним из трёх путей
-- (finishIntro / failIntro / сторожевой таймер) и вернуло остальной
-- интерфейс». Выставляется в начале restoreGameUi — общей точки всех трёх
-- путей — и именно по нему, а не по controlsRestored, синхронизируются
-- сторожевой таймер и мгновенный выход по нажатию клавиши ниже: иначе,
-- раз controlsRestored истинен с первой же секунды, оба эти механизма
-- решили бы, что интро уже закончилось, и не сделали бы свою РЕАЛЬНУЮ
-- работу — не сняли бы подавление остального интерфейса (HUD, квесты и
-- т.д.) и не сообщили бы серверу, что пора переставлять игрока на участок.
local introEnded = false

local function restoreGameUi()
    introEnded = true
    if guiAddedConnection then
        guiAddedConnection:Disconnect()
        guiAddedConnection = nil
    end
    if worldGuiAddedConnection then
        worldGuiAddedConnection:Disconnect()
        worldGuiAddedConnection = nil
    end
    for gui, connection in pairs(guiGuards) do
        connection:Disconnect()
        guiGuards[gui] = nil
    end
    for gui, state in pairs(suppressedGuis) do
        if gui.Parent then
            gui.Enabled = state.enabled
        end
    end
    table.clear(suppressedGuis)

    for coreGuiType, enabled in pairs(coreGuiStates) do
        pcall(function()
            StarterGui:SetCoreGuiEnabled(coreGuiType, enabled)
        end)
    end
    pcall(function()
        StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
    end)
    restoreControls()
end

-- СТОРОЖЕВОЙ ТАЙМЕР. Последняя линия обороны против "застрял на спавне":
-- что бы ни случилось с катсценой (ошибка, зависшее ожидание ассетов,
-- отсутствующий Moon Animator, порванная репликация), остальной интерфейс
-- (HUD, квесты и т.д.) будет возвращён принудительно, а сервер узнает, что
-- пора переставить игрока с точки высадки у банка на его участок. Ходить
-- игрок к этому моменту уже может — управление не отключается вовсе (см.
-- "УПРАВЛЕНИЕ ВООБЩЕ НЕ ОТКЛЮЧАЕТСЯ" выше), — но без этого таймера он
-- остался бы без остального интерфейса и на чужом месте. Интро при этом не
-- ломается: restoreGameUi идемпотентна, а пороги подобраны так, чтобы не
-- оборвать РАБОТАЮЩУЮ сцену.
--
-- Два разных порога — иначе никак: нормальное интро может стартовать не
-- сразу (ожидание AssetsLoaded до 20с), а сама сцена длиться заметное время.
--   NOT_STARTED_TIMEOUT — сцена так и не начала проигрываться. Значит она
--     уже не начнётся: что-то не доехало или упало.
--   ABSOLUTE_TIMEOUT — сцена стартовала, но по какой-то причине не
--     завершилась (Ended не сработал, зависла анимация). Порог с большим
--     запасом относительно любой разумной длины интро.
-- NOT_STARTED_TIMEOUT снижен с 45 до 12 секунд.
--
-- ПОЧЕМУ. Раньше этот же таймер несёт ещё и историю жалобы «иногда, когда
-- заходишь, ходить не можешь» — тогда управление отключалось сразу при
-- загрузке скрипта, и вернуть его в аварийном случае мог только он. 45
-- секунд неподвижности никто не ждал: игрок выходил и заходил заново
-- гораздо раньше, поэтому страховка де-факто никогда не срабатывала. Саму
-- причину бага убрали (управление больше не отключается), но короткий
-- порог остался — он куда быстрее возвращает остальной интерфейс и позицию
-- на участке, чем прежние 45с.
local NOT_STARTED_TIMEOUT = 12
local ABSOLUTE_TIMEOUT = 150
task.spawn(function()
    local startedAt = os.clock()
    while not introEnded do
        task.wait(2)
        if introEnded then return end
        local elapsed = os.clock() - startedAt
        local cutsceneRunning = player:GetAttribute("CutsceneStarted") == true
        local expired = (not cutsceneRunning and elapsed > NOT_STARTED_TIMEOUT)
            or elapsed > ABSOLUTE_TIMEOUT
        if expired then
            warn(("[MoonAnimationTest] Интро не завершилось за %.0f с (сцена %s) - принудительно возвращаю интерфейс и ставлю игрока на участок.")
                :format(elapsed, cutsceneRunning and "стартовала, но не завершилась" or "так и не стартовала"))
            -- ВАЖНО: именно restoreGameUi(), а не голый restoreControls().
            -- Раньше здесь стоял только restoreControls(), и подавление
            -- интерфейса оставалось ЖИВЫМ: guiAddedConnection продолжал
            -- висеть на playerGui.ChildAdded. На телефоне это означало, что
            -- заново созданный Controls:Enable()-ом TouchGui немедленно
            -- ловился этим коннектом и гасился (suppressGui выключает gui
            -- безусловно) — управление формально "включено", а кнопок на
            -- экране нет. restoreGameUi сначала отцепляет все коннекты и
            -- возвращает интерфейс, и только потом зовёт restoreControls.
            -- Функция идемпотентна, так что повторный вызов из штатного
            -- пути ничего не сломает.
            restoreGameUi()
            player:SetAttribute("IntroActive", false)
            -- ТА ЖЕ ПРИЧИНА, что и в failIntro() выше: без этого сигнала
            -- сервер никогда не переставит игрока с TeleportPart (точка у
            -- банка) на его участок — сторожевой таймер возвращал только
            -- управление, но не позицию.
            cutsceneFinished:FireServer()
            -- Снимаем и загрузочный экран: он ждёт CutsceneStarted либо
            -- IntroFailed, и без этого флага висел бы поверх игры бесконечно.
            if not cutsceneRunning then
                player:SetAttribute("IntroFailed", true)
            end
            return
        end
    end
end)

--------------------------------------------------------------------------------
-- НЕМЕДЛЕННЫЙ ВЫХОД ПО ПОПЫТКЕ ПОЙТИ.
--
-- Даже 12 секунд — это 12 секунд, в течение которых интерфейс (HUD, квесты
-- и т.д.) остаётся подавлен, а сервер не знает, что пора переставить игрока
-- на его участок. Ходить игрок технически уже может в любой момент (см.
-- "УПРАВЛЕНИЕ ВООБЩЕ НЕ ОТКЛЮЧАЕТСЯ" выше) — но если он идёт, значит
-- пытается играть, а не смотреть зависшую заставку, и ждать до 12-секундного
-- таймера незачем.
--
-- Порог в 3 секунды нужен, чтобы не оборвать нормальный запуск: в первые
-- мгновения после захода игрок вполне может машинально нажать W или
-- дёрнуть джойстик, пока честно идёт загрузка и сцена вот-вот стартует.
--
-- Проверяем именно CutsceneStarted, а не introEnded: если сцена ИДЁТ, то
-- нажатие «вперёд» — это не «я застрял», это просто нажатие во время
-- катсцены, и прерывать её незачем (для этого есть кнопка «пропустить»).
--
-- UserInputType.Touch намеренно НЕ слушаем: на телефоне любое касание
-- экрана (в том числе по кнопке «пропустить» или просто по воздуху)
-- считалось бы попыткой идти.
local MOVE_ESCAPE_GRACE = 3
local moveEscapeStartedAt = os.clock()
local MOVEMENT_KEYS = {
    [Enum.KeyCode.W] = true, [Enum.KeyCode.A] = true,
    [Enum.KeyCode.S] = true, [Enum.KeyCode.D] = true,
    [Enum.KeyCode.Up] = true, [Enum.KeyCode.Down] = true,
    [Enum.KeyCode.Left] = true, [Enum.KeyCode.Right] = true,
    [Enum.KeyCode.Space] = true,
    [Enum.KeyCode.Thumbstick1] = true,
}
UserInputService.InputBegan:Connect(function(input, processed)
    if processed or introEnded then return end
    if not MOVEMENT_KEYS[input.KeyCode] then return end
    if os.clock() - moveEscapeStartedAt < MOVE_ESCAPE_GRACE then return end
    if player:GetAttribute("CutsceneStarted") == true then return end
    warn("[MoonAnimationTest] Игрок пытается идти, а интро так и не стартовало - возвращаю управление немедленно.")
    -- Тот же полный путь, что и у сторожевого таймера ниже: одного
    -- restoreControls() мало, нужно ещё снять подавление интерфейса и
    -- сообщить серверу, что катсцена закончилась (иначе игрок останется
    -- стоять на точке высадки у банка вместо своего участка).
    restoreGameUi()
    player:SetAttribute("IntroActive", false)
    player:SetAttribute("IntroFailed", true)
    cutsceneFinished:FireServer()
end)

-- Ресет персонажа пересоздаёт управление сам, но атрибут IntroActive мог
-- остаться взведённым и продолжать гасить игровой интерфейс (см. suppressGui).
-- Если персонаж пересоздался, а интро давно закончилось — приводим состояние
-- в порядок.
player.CharacterAdded:Connect(function()
    if introEnded then
        player:SetAttribute("IntroActive", false)
        forceTouchControlsVisible()
    end
end)

-- ПОСЛЕДНЯЯ, НЕЗАВИСИМАЯ СТРАХОВКА ДЛЯ ТЕЛЕФОНА.
-- Всё выше — это пути ВНУТРИ логики интро. Здесь же стоит отдельный
-- наблюдатель, которому вообще всё равно, что произошло со сценой: он просто
-- следит, что как только интро перестало быть активным, экранное управление
-- на тач-устройстве действительно ВИДНО. Стоит копейки (проверка раз в
-- полсекунды в течение первой минуты после захода) и закрывает любые
-- сценарии, которые я мог не предусмотреть: чужой скрипт погасил TouchGui,
-- гонка при респавне ровно в момент финала сцены, падение самой сцены с
-- ошибкой в неожиданном месте.
-- На ПК цикл выходит сразу же на первой проверке TouchEnabled.
task.spawn(function()
    if not UserInputService.TouchEnabled then return end
    local deadline = os.clock() + 60
    while os.clock() < deadline do
        if player:GetAttribute("IntroActive") ~= true then
            forceTouchControlsVisible()
        end
        task.wait(0.5)
    end
end)

local function waitForSceneRig(timeout)
    local startedAt = os.clock()
    repeat
        local rig = workspace:FindFirstChild("HumanoidCameraRig")
        if rig and rig:FindFirstChild("Torso") then
            return true
        end
        task.wait(0.1)
    until os.clock() - startedAt >= timeout
    return false
end

local function cleanup()
    if activePlayer then
        pcall(function()
            activePlayer:Stop()
            activePlayer:Destroy()
        end)
        activePlayer = nil
    end
    if activeRigPlayer then
        pcall(function()
            activeRigPlayer:destroy()
        end)
        activeRigPlayer = nil
    end
    if activeRigAnimation then
        activeRigAnimation:Destroy()
        activeRigAnimation = nil
    end
    if activeSound then
        activeSound:Destroy()
        activeSound = nil
    end
    busy = false
end

local function failIntro()
    skipButton.Visible = false
    -- КРИТИЧНО: сообщаем серверу, что катсцена завершилась (пусть и
    -- неудачно), ПЕРВЫМ делом. Раньше cutsceneFinished:FireServer()
    -- вызывался ТОЛЬКО из finishIntro() (успешный путь) — то есть любой сбой
    -- катсцены (не загрузился ассет, не найден Moon Animator, порвалась
    -- репликация save-файла) возвращал игроку управление, но сервер так и
    -- не узнавал, что пора звать movePlayerToPlot. Игрок навсегда оставался
    -- там, где его высадил TeleportPart — точка интро-камеры у банка — и
    -- телепортировался туда же при каждом следующем респавне. Сервер сам
    -- по себе идемпотентен (см. Main.server.lua: cutsceneFinished.OnServerEvent
    -- проверяет атрибут и не делает ничего повторно), так что вызывать это
    -- здесь безопасно, даже если finishIntro каким-то образом тоже отработает.
    cutsceneFinished:FireServer()
    cleanup()
    if logoSound then
        logoSound:Destroy()
        logoSound = nil
    end
    restoreGameUi()
    player:SetAttribute("IntroActive", false)
    player:SetAttribute("IntroFailed", true)
    transitionGui:Destroy()
end

local hybridRigNames = {
    bacon = true,
    noob = true,
}

local function isHybridRig(item)
    local path = item and item.Path
    local names = path and path.InstanceNames
    return path and path.ItemType == "Rig" and names and hybridRigNames[names[#names]] == true
end

local function makePrimaryAnimation(animation, animationData)
    local filtered = animation:Clone()
    filtered.Name = animation.Name .. "_Primary"

    local keptItems = {}
    local indexMap = {}
    local nextIndex = 0

    for originalIndex, item in ipairs(animationData.Items or {}) do
        if not isHybridRig(item) then
            nextIndex += 1
            keptItems[nextIndex] = item
            indexMap[originalIndex] = nextIndex
        end
    end

    for _, child in filtered:GetChildren() do
        local originalIndex = tonumber(child.Name)
        if originalIndex and not indexMap[originalIndex] then
            child:Destroy()
        end
    end
    for _, child in filtered:GetChildren() do
        local originalIndex = tonumber(child.Name)
        local newIndex = originalIndex and indexMap[originalIndex]
        if newIndex then
            child.Name = tostring(newIndex)
        end
    end

    local filteredData = {}
    for key, value in pairs(animationData) do
        filteredData[key] = value
    end
    filteredData.Items = keptItems
    filtered.Value = HttpService:JSONEncode(filteredData)

    return filtered
end

local function rebaseLegacyBaconRoot(animation, animationData)
    for index, item in ipairs(animationData.Items or {}) do
        local names = item.Path and item.Path.InstanceNames
        if names and names[#names] == "bacon" then
            local animationLines = animation:FindFirstChild(tostring(index))
            local rigFolder = animationLines and animationLines:FindFirstChild("Rig")
            if rigFolder then
                for _, joint in rigFolder:GetChildren() do
                    local hierarchy = joint:FindFirstChild("_hier")
                    if hierarchy and hierarchy:IsA("StringValue") and hierarchy.Value == "Torso" then
                        local basePosition
                        local lowestFrame = math.huge
                        for _, descendant in joint:GetDescendants() do
                            if descendant:IsA("CFrameValue") then
                                local frame = tonumber(descendant.Name)
                                if frame and frame < lowestFrame then
                                    lowestFrame = frame
                                    basePosition = descendant.Value.Position
                                end
                            end
                        end

                        for _, descendant in joint:GetDescendants() do
                            if basePosition and descendant:IsA("CFrameValue") and tonumber(descendant.Name) then
                                local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = descendant.Value:GetComponents()
                                local position = Vector3.new(x, y, z) - basePosition
                                if basePosition.Magnitude > 0.001 then
                                    descendant.Value = CFrame.new(position.X, position.Y, position.Z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local function coverToBlack()
    if coverStarted then
        while not coverComplete do
            task.wait()
        end
        return
    end
    coverStarted = true
    local cover = TweenService:Create(
        transition,
        TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {BackgroundTransparency = 0}
    )
    local underCover = TweenService:Create(
        blackLayer,
        TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {BackgroundTransparency = 0}
    )
    cover:Play()
    underCover:Play()
    cover.Completed:Wait()

    transition.BackgroundTransparency = 1
    coverComplete = true
end

local function finishIntro()
    if ending then
        return
    end
    ending = true
    skipButton.Visible = false

    coverToBlack()

    cutsceneFinished:FireServer()
    cleanup()

    local teleportWaitStarted = os.clock()
    while player:GetAttribute("CutsceneFinished") ~= true
        and os.clock() - teleportWaitStarted < 2 do
        task.wait(0.05)
    end

    if logoSound then
        logoSound:Play()
    end
    local logoIn = TweenService:Create(
        logo,
        TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {ImageTransparency = 0}
    )
    local scaleIn = TweenService:Create(
        logoScale,
        TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
        {Scale = 1}
    )
    logoIn:Play()
    scaleIn:Play()
    logoIn.Completed:Wait()

    local float = TweenService:Create(
        logo,
        TweenInfo.new(1.15, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {Position = UDim2.fromScale(0.5, 0.47)}
    )
    float:Play()
    task.wait(2.2)

    restoreGameUi()
    player:SetAttribute("IntroActive", false)

    local exit = TweenService:Create(
        transition,
        TweenInfo.new(0.85, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
        {
            Position = UDim2.fromScale(0.5, 1.5),
            GroupTransparency = 1,
        }
    )
    local blackExit = TweenService:Create(
        blackLayer,
        TweenInfo.new(1.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        {
            BackgroundTransparency = 1,
        }
    )
    exit:Play()
    blackExit:Play()
    exit.Completed:Wait()
    float:Cancel()

    if logoSound then
        logoSound:Destroy()
        logoSound = nil
    end
    transitionGui:Destroy()
end

local function playAnimation()
    if busy then
        return
    end

    busy = true

    if not waitForSceneRig(30) then
        warn("[MoonAnimationTest] Workspace.HumanoidCameraRig.Torso is not available on the client")
        failIntro()
        return
    end

    local saveFolder = ReplicatedStorage:WaitForChild("MoonAnimator2Saves", 30)
    local animation = saveFolder and saveFolder:WaitForChild("scene", 30)
    if not animation then
        warn("[MoonAnimationTest] scene was not replicated to the client")
        failIntro()
        return
    end

    local animationData = HttpService:JSONDecode(animation.Value)

    local module = ReplicatedStorage:WaitForChild("MoonAnimatorPlayer_V2", 10)
    if not module then
        warn("[MoonAnimationTest] MoonAnimatorPlayer_V2 was not found in ReplicatedStorage")
        failIntro()
        return
    end

    local currentAnimation = animation
    local alternativeModule = ReplicatedStorage:FindFirstChild("Moon2Cutscene")
    local alternativePlayerModule
    local pendingRigPlayer
    if alternativeModule and alternativeModule:IsA("ModuleScript") then
        local ok, result = pcall(require, alternativeModule)
        if ok then
            alternativePlayerModule = result
        else
            warn("[MoonAnimationTest] Could not load Moon2Cutscene:", result)
        end
    end

    if alternativePlayerModule then
        local okRig, rigPlayer = pcall(function()
            local player = alternativePlayerModule.new(animation, nil, true)
            for index, item in ipairs(animationData.Items or {}) do
                if not isHybridRig(item) then
                    player:replace(index, nil)
                end
            end
            return player
        end)

        if okRig then
            pendingRigPlayer = rigPlayer
        else
            warn("[MoonAnimationTest] Could not create Moon2Cutscene rig player:", rigPlayer)
        end
    end

    if pendingRigPlayer then
        activeRigPlayer = pendingRigPlayer
        activeRigAnimation = makePrimaryAnimation(animation, animationData)
        currentAnimation = activeRigAnimation
    else
        rebaseLegacyBaconRoot(animation, animationData)
    end

    local ok, result = pcall(function()
        -- Use the FPS stored by Moon Animator in the exported animation.
        return require(module).new(currentAnimation)
    end)
    if not ok then
        warn("[MoonAnimationTest] Could not create player:", result)
        failIntro()
        return
    end

    activePlayer = result

    activeSound = Instance.new("Sound")
    activeSound.Name = "CutsceneSound"
    activeSound.SoundId = CUTSCENE_SOUND_ID
    activeSound.Parent = SoundService

    logoSound = Instance.new("Sound")
    logoSound.Name = "IntroLogoSound"
    logoSound.SoundId = LOGO_SOUND_ID
    logoSound.Parent = SoundService
    pcall(function()
        ContentProvider:PreloadAsync({activeSound, logoSound, logo})
    end)

    activePlayer.Ended:Connect(function()
        task.spawn(function()
            local finished, finishError = xpcall(finishIntro, debug.traceback)
            if not finished then
                warn("[MoonAnimationTest] Intro transition failed:", finishError)
                failIntro()
            end
        end)
    end)

    if pendingRigPlayer then
        activeRigPlayer:play(true)
    end

    activeSound:Play()
    activePlayer:Start()
    player:SetAttribute("CutsceneStarted", true)

    -- Показываем ТОЛЬКО после реального старта сцены: пока идёт короткое
    -- окно предзагрузки, нажимать ещё нечего — finishIntro в этот момент
    -- оборвал бы запуск на середине.
    skipButton.Visible = true
    TweenService:Create(skipButton, TweenInfo.new(0.4), {TextTransparency = 0.15}):Play()
    skipButton.MouseButton1Click:Connect(function()
        -- finishIntro — это ШТАТНЫЙ путь завершения (тот же, что по событию
        -- Ended): он закрывает экран, сообщает серверу, убирает плеер и
        -- возвращает управление. Свою "быструю" ветку писать нельзя — она
        -- разошлась бы с обычной при первой же правке концовки.
        skipButton.Visible = false
        task.spawn(function()
            local ok, err = xpcall(finishIntro, debug.traceback)
            if not ok then
                warn("[MoonAnimationTest] Skip failed:", err)
                failIntro()
            end
        end)
    end)

    local information = animationData.Information or {}
    local fps = tonumber(information.FPS) or 60
    local length = tonumber(information.Length)
    if length then
        task.delay(math.max(length / fps - 0.3, 0), function()
            if activePlayer and not ending then
                task.spawn(coverToBlack)
            end
        end)
    end
end

task.spawn(function()
    -- Ожидание БОЛЬШЕ НЕ бесконечное. Атрибут ставит LoadingScreen, и если
    -- тот упал с ошибкой до SetAttribute (его тело не в pcall), прежний
    -- `while ... do Wait() end` висел вечно — а управление к этому моменту
    -- уже было отключено выше. Отсюда и брался обездвиженный игрок.
    -- По истечении таймаута просто идём дальше: интро либо отработает, либо
    -- честно свалится в failIntro, и в обоих случаях управление вернётся.
    local ASSETS_WAIT_TIMEOUT = 20
    local waitStarted = os.clock()
    while player:GetAttribute("AssetsLoaded") ~= true
        and os.clock() - waitStarted < ASSETS_WAIT_TIMEOUT do
        task.wait(0.1)
    end
    if player:GetAttribute("AssetsLoaded") ~= true then
        warn(("[MoonAnimationTest] AssetsLoaded не выставлен за %d с - запускаю интро без него (проверь LoadingScreen)."):format(ASSETS_WAIT_TIMEOUT))
    end
    local ok, err = xpcall(playAnimation, debug.traceback)
    if not ok then
        warn("[MoonAnimationTest] Intro failed:", err)
        failIntro()
    end
end)
