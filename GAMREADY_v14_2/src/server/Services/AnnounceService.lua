--------------------------------------------------------------------------------
-- AnnounceService
-- Утилита без зависимостей (как NotifyService, но не персональные тосты на
-- экране, а системные сообщения ВСЕМ игрокам прямо в чат) — редкие руды с
-- мутацией, найденная жеода, новый скин из жеоды и т.п.
--
-- Технически: TextChatService.TextChannels.RBXGeneral:DisplaySystemMessage(...)
-- нужно вызывать С КЛИЕНТА (см. AnnounceClient.client.lua) — сервер только
-- решает, ЧТО и КАКИМ цветом сказать, и рассылает готовый rich-text через
-- RemoteEvent. Цвет — тегом <font color="rgb(R,G,B)">...</font>, это то, что
-- реально поддерживает TextChatService для system-сообщений.
--------------------------------------------------------------------------------

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnnounceService = {}

local remote

function AnnounceService:Init(services)
	remote = ReplicatedStorage.Shared:FindFirstChild("SystemAnnounce")
	if not remote then
		remote = Instance.new("RemoteEvent")
		remote.Name = "SystemAnnounce"
		remote.Parent = ReplicatedStorage.Shared
	end
end

-- color — Color3, конвертируется в "R,G,B" сам. segments — необязательный
-- список {Text=, Color=Color3} для подсветки ТОЛЬКО части сообщения (имя
-- мутации/скина) другим цветом внутри общей белой фразы; если не передан,
-- красится вся строка text целиком.
function AnnounceService:Broadcast(text, color, segments)
	if not remote then return end
	local function wrap(fragment, fragmentColor)
		local c = fragmentColor or color or Color3.new(1, 1, 1)
		return ('<font color="rgb(%d,%d,%d)">%s</font>'):format(
			math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5), fragment
		)
	end
	local formatted
	if segments then
		local parts = {}
		for _, segment in segments do
			table.insert(parts, wrap(segment.Text, segment.Color))
		end
		formatted = table.concat(parts)
	else
		formatted = wrap(text)
	end
	remote:FireAllClients(formatted)
end

return AnnounceService
