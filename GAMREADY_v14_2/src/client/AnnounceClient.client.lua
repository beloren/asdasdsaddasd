--------------------------------------------------------------------------------
-- AnnounceClient
-- Показывает то, что решил разослать AnnounceService (сервер), как системное
-- сообщение в обычном чате — TextChatService требует, чтобы
-- DisplaySystemMessage вызывался именно с клиента, поэтому сервер шлёт уже
-- готовый (раскрашенный) текст, а этот скрипт просто выводит его.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local remote = ReplicatedStorage.Shared:WaitForChild("SystemAnnounce")
local channels = TextChatService:WaitForChild("TextChannels")
local generalChannel = channels:WaitForChild("RBXGeneral")

remote.OnClientEvent:Connect(function(formattedText)
	generalChannel:DisplaySystemMessage(formattedText)
end)
