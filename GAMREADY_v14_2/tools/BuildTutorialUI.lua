--------------------------------------------------------------------------------
-- BuildTutorialUI — ДИАЛОГОВОЕ ОКНО ОБУЧЕНИЯ (см. Config.Tutorial).
--
-- Собирает StarterGui/TutorialUi: рамку с плашкой имени, портретом и
-- посимвольно печатающимся текстом, плюс свёрнутую плашку-задание, в
-- которую окно превращается на время выполнения шага.
--
-- САМА ГЕОМЕТРИЯ ЛЕЖИТ НЕ ЗДЕСЬ, а в src/shared/TutorialUiBuilder.lua.
-- Причина: если этот билдер ни разу не запускали, обучение обязано
-- работать всё равно — иначе новичок на свежем месте не увидит ничего и
-- застрянет на первом шаге. Поэтому то же построение вызывает и
-- src/client/TutorialUI.client.lua, когда не находит готовый TutorialUi в
-- PlayerGui. Одна функция, две точки вызова — копиям разъехаться негде.
--
-- Что даёт запуск билдера по сравнению со сборкой на лету: окно можно
-- открыть в Studio и подвинуть/перекрасить руками, как остальной
-- интерфейс. Клиент уважает то, что лежит в StarterGui, и строит своё
-- только при отсутствии.
--
-- ЗАПУСК: Rojo-синк → Command Bar в Studio → вставить файл целиком → Enter.
-- Безопасно перезапускается, но пересоздаёт StarterGui/TutorialUi с нуля,
-- вместе с ручными правками.
--------------------------------------------------------------------------------

local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local existing = StarterGui:FindFirstChild("TutorialUi")
if existing then existing:Destroy() end

local TutorialUiBuilder = require(ReplicatedStorage.Shared.TutorialUiBuilder)

-- narrow = false: в StarterGui кладём настольный вариант. Клиент сам
-- пересчитает размеры под узкий экран при запуске и при смене размера окна
-- (см. подписку на ViewportSize в TutorialUI.client.lua), так что отдельная
-- мобильная сборка здесь не нужна.
local gui = TutorialUiBuilder.Build(false)
gui.Parent = StarterGui

print("[BuildTutorialUI] TutorialUi собран (диалоговое окно обучения v7).")
