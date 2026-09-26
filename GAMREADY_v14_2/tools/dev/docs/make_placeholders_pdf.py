# -*- coding: utf-8 -*-
"""Генератор PDF «Полный гайд по плейсхолдерам» (GAMREADY v20).
Списки берутся из выгрузки Config (cfg.json, cfgassets.txt) и Config.Sounds,
правила — из кода (PlaceholderFactory, сервисы, клиенты)."""
import json, re, os, sys
from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.lib.units import mm
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_LEFT, TA_CENTER
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, PageTemplate, Frame, Paragraph, Spacer, Table,
                                TableStyle, PageBreak, KeepTogether, Preformatted)
from reportlab.platypus.tableofcontents import TableOfContents

S = sys.argv[1]
REPO = sys.argv[2]
OUT = sys.argv[3]

FD = "/usr/share/fonts/truetype/dejavu/"
pdfmetrics.registerFont(TTFont("Sans", FD + "DejaVuSans.ttf"))
pdfmetrics.registerFont(TTFont("Sans-Bold", FD + "DejaVuSans-Bold.ttf"))
pdfmetrics.registerFont(TTFont("Mono", FD + "DejaVuSansMono.ttf"))
pdfmetrics.registerFont(TTFont("Mono-Bold", FD + "DejaVuSansMono-Bold.ttf"))
from reportlab.pdfbase.pdfmetrics import registerFontFamily
registerFontFamily("Sans", normal="Sans", bold="Sans-Bold", italic="Sans", boldItalic="Sans-Bold")
registerFontFamily("Mono", normal="Mono", bold="Mono-Bold", italic="Mono", boldItalic="Mono-Bold")

cfg = json.load(open(os.path.join(S, "cfg.json"), encoding="utf-8"))
cfgassets = [l.rstrip("\n") for l in open(os.path.join(S, "cfgassets.txt"), encoding="utf-8")]
config_src = open(os.path.join(REPO, "src/shared/Config.lua"), encoding="utf-8").read()

INK = colors.HexColor("#1B1F24")
MUTED = colors.HexColor("#5A6270")
ACCENT = colors.HexColor("#C0392B")
HEAD_BG = colors.HexColor("#2B2F36")
ZEBRA = colors.HexColor("#F3F4F6")
REQ = colors.HexColor("#FDECEA")
NOTE_BG = colors.HexColor("#FFF7E0")
TIP_BG = colors.HexColor("#E9F5EC")

st = {
    "title": ParagraphStyle("title", fontName="Sans-Bold", fontSize=26, leading=32, textColor=INK, spaceAfter=10),
    "subtitle": ParagraphStyle("subtitle", fontName="Sans", fontSize=12, leading=17, textColor=MUTED),
    "h1": ParagraphStyle("h1", fontName="Sans-Bold", fontSize=17, leading=22, textColor=INK, spaceBefore=6, spaceAfter=8),
    "h2": ParagraphStyle("h2", fontName="Sans-Bold", fontSize=12.5, leading=16, textColor=ACCENT, spaceBefore=10, spaceAfter=5),
    "h3": ParagraphStyle("h3", fontName="Sans-Bold", fontSize=10.5, leading=14, textColor=INK, spaceBefore=6, spaceAfter=3),
    "body": ParagraphStyle("body", fontName="Sans", fontSize=9, leading=13, textColor=INK, spaceAfter=4),
    "bullet": ParagraphStyle("bullet", fontName="Sans", fontSize=9, leading=13, textColor=INK, leftIndent=12, bulletIndent=2, spaceAfter=1.5),
    "cell": ParagraphStyle("cell", fontName="Sans", fontSize=7.8, leading=10, textColor=INK),
    "cellb": ParagraphStyle("cellb", fontName="Sans-Bold", fontSize=7.8, leading=10, textColor=colors.white),
    "code": ParagraphStyle("code", fontName="Mono", fontSize=7.8, leading=10.2, textColor=INK),
    "note": ParagraphStyle("note", fontName="Sans", fontSize=8.8, leading=12.5, textColor=INK),
    "toc1": ParagraphStyle("toc1", fontName="Sans-Bold", fontSize=10, leading=15, leftIndent=0),
    "toc2": ParagraphStyle("toc2", fontName="Sans", fontSize=8.8, leading=12.5, leftIndent=14, textColor=MUTED),
}


EMOJI_RE = re.compile("[\U0001F000-\U0001FFFF\u2600-\u27BF\u2B00-\u2BFF\uFE0F\u200D]")


def esc(s):
    s = EMOJI_RE.sub("", str(s))
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def c(s):
    """инлайн-код"""
    return '<font face="Mono" color="#8E2B20">%s</font>' % esc(s)


def md(text):
    """Мини-разметка: `код`, **жирный**."""
    out = esc(text)
    out = re.sub(r"`([^`]+)`", lambda m: '<font face="Mono" color="#8E2B20">%s</font>' % m.group(1), out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", out)
    return out


story = []


class Doc(BaseDocTemplate):
    def afterFlowable(self, flowable):
        if isinstance(flowable, Paragraph):
            name = flowable.style.name
            text = esc(flowable.getPlainText())
            if name == "h1":
                self.notify("TOCEntry", (0, text, self.page))
            elif name == "h2":
                self.notify("TOCEntry", (1, text, self.page))


def H1(t):
    story.append(Paragraph(esc(t), st["h1"]))


def H2(t):
    story.append(Paragraph(esc(t), st["h2"]))


def H3(t):
    story.append(Paragraph(md(t), st["h3"]))


def P(t):
    story.append(Paragraph(md(t), st["body"]))


def UL(items):
    for it in items:
        story.append(Paragraph(md(it), st["bullet"], bulletText="•"))
    story.append(Spacer(1, 3))


def box(text, bg=NOTE_BG, label="Важно"):
    p = Paragraph("<b>%s.</b> %s" % (label, md(text)), st["note"])
    t = Table([[p]], colWidths=[176 * mm])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), bg), ("BOX", (0, 0), (-1, -1), 0.4, colors.HexColor("#D9C58A") if bg == NOTE_BG else colors.HexColor("#9CC7A6")),
                           ("LEFTPADDING", (0, 0), (-1, -1), 7), ("RIGHTPADDING", (0, 0), (-1, -1), 7), ("TOPPADDING", (0, 0), (-1, -1), 5), ("BOTTOMPADDING", (0, 0), (-1, -1), 5)]))
    story.append(t)
    story.append(Spacer(1, 5))


def tip(text):
    box(text, TIP_BG, "Совет")


def TREE(text):
    t = Table([[Preformatted(text.strip("\n"), st["code"])]], colWidths=[176 * mm])
    t.setStyle(TableStyle([("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#F6F8FA")), ("BOX", (0, 0), (-1, -1), 0.4, colors.HexColor("#D0D7DE")),
                           ("LEFTPADDING", (0, 0), (-1, -1), 7), ("TOPPADDING", (0, 0), (-1, -1), 5), ("BOTTOMPADDING", (0, 0), (-1, -1), 5)]))
    story.append(t)
    story.append(Spacer(1, 5))


def TABLE(header, rows, widths, code_cols=(0,), req_col=None):
    total = sum(widths)
    widths = [w * 176.0 / total * mm for w in widths]
    data = [[Paragraph(esc(h), st["cellb"]) for h in header]]
    for r in rows:
        line = []
        for i, v in enumerate(r):
            if i in code_cols:
                line.append(Paragraph(md("`%s`" % v) if v and "`" not in str(v) else md(str(v)), st["cell"]))
            else:
                line.append(Paragraph(md(str(v)), st["cell"]))
        data.append(line)
    t = Table(data, colWidths=widths, repeatRows=1)
    style = [("BACKGROUND", (0, 0), (-1, 0), HEAD_BG), ("VALIGN", (0, 0), (-1, -1), "TOP"),
             ("GRID", (0, 0), (-1, -1), 0.3, colors.HexColor("#C9CED6")),
             ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4),
             ("TOPPADDING", (0, 0), (-1, -1), 2.5), ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5)]
    for i in range(1, len(data)):
        if i % 2 == 0:
            style.append(("BACKGROUND", (0, i), (-1, i), ZEBRA))
    if req_col is not None:
        for i, r in enumerate(rows, start=1):
            if str(r[req_col]).lower().startswith("да"):
                style.append(("BACKGROUND", (req_col, i), (req_col, i), REQ))
    t.setStyle(TableStyle(style))
    story.append(t)
    story.append(Spacer(1, 7))


def ordered(d):
    if isinstance(d, dict):
        try:
            return [d[k] for k in sorted(d, key=lambda x: int(x))]
        except ValueError:
            return list(d.values())
    return d or []


# ============================================================================
# ТИТУЛ
# ============================================================================
story.append(Spacer(1, 40 * mm))
story.append(Paragraph("Плейсхолдеры: полный гайд по замене", st["title"]))
story.append(Paragraph("GAMREADY v20 — модели, VFX, звуки, музыка, анимации, картинки и интерфейс. "
                       "Точные имена, где лежит, что должно быть внутри, что код делает сам.", st["subtitle"]))
story.append(Spacer(1, 10 * mm))
story.append(Paragraph(md("Источник истины — код: `src/shared/PlaceholderFactory.lua`, `PlaceableFactory.lua`, сервисы `src/server/Services`, "
                          "клиенты `src/client`, `src/shared/Config.lua`, `src/shared/UiTheme.lua`. Списки в таблицах выгружены прямо из "
                          "`Config.lua` этой версии (сентябрь 2026) — если добавишь новый предмет в конфиг, его ассет называется по тем же правилам."), st["body"]))
story.append(Spacer(1, 6 * mm))
legend = [["Обозначение", "Что значит"],
          ["Обяз.: да", "Без ассета функция не работает или предмет не выдаётся (например, скины)."],
          ["Обяз.: нет", "Есть кодовый плейсхолдер — игра работает, просто выглядит временно."],
          ["0 / \"\"", "В Config: 0 или пустая строка = картинка/звук не задан, работает заглушка (эмодзи, текст, цвет, тишина)."]]
TABLE(legend[0], legend[1:], [30, 146], code_cols=())
story.append(PageBreak())

toc = TableOfContents()
toc.levelStyles = [st["toc1"], st["toc2"]]
story.append(Paragraph("Содержание", st["h1"].clone("tochead")))
story.append(toc)
story.append(PageBreak())

# ============================================================================
# 1. ОБЩИЕ ПРАВИЛА
# ============================================================================
H1("1. Общие правила")
H2("1.1 Куда класть ассеты")
UL([
    "Все 3D-ассеты — в `ReplicatedStorage/Assets`. Поиск идёт сначала среди прямых детей, потом рекурсивно по подпапкам — так что раскладывать по папкам (`Assets/VFX/...`, `Assets/Skins/...`) **можно**.",
    "Исключения, где папка обязательна и имя папки фиксировано: сундуки `Assets/Chests/Chest_<Редкость>`, карточки мини-игры `Assets/MineRarityCards/<Редкость>`.",
    "Некоторые ассеты ищутся **только** среди прямых детей `Assets`: `Boulder_Tier<N>`, `Goblin_*`, `Totem_*`/`Decor_*`/`Relic_*`/`RelicPedestal`, `Chest` (сундук гоблина), `DailyRewardVFX`, `GeodeHammer`, `BookVFX`. Их держи прямо в `Assets`.",
    "Имена регистрозависимы: `Cart_Tier1` и `cart_tier1` — разные.",
    "`default.project.json` не синхронизирует `Assets`, `StarterGui` и постройки Studio. После работы **сохрани/опубликуй place** — иначе всё пропадёт.",
])
H2("1.2 Как собирать модели")
UL([
    "Составная модель: `Model` с назначенным `PrimaryPart`. Безопасный стандарт — прямой `BasePart` с именем `Root`, он же `PrimaryPart`.",
    "Скины: вместо `Root` — `SkinRoot` (или `Handle` у `Tool`).",
    "Движущиеся модели (тележки, кристаллы в тележке, физические жеоды, VFX на игроке): все декоративные части приварены к корню `WeldConstraint`, `Anchored = false`.",
    "Статичные модели (шахты, постройки, валуны, тотемы, трофеи, NPC-плейсхолдеры) код анкорит сам.",
    "Невидимые маркеры: `Transparency = 1`, `CanCollide = false`, `CanTouch = false`, `CanQuery = false`, `Massless = true`.",
    "`Script`/`LocalScript` внутри скинов, кирок, динамита, тотемов/декора удаляются при клонировании — логику туда не клади.",
])
H2("1.3 Безопасный порядок работы")
UL([
    "Останови Play Test, запусти Rojo, дождись `ReplicatedStorage/Shared` и скриптов.",
    "Если нужны стартовые заглушки — сначала запусти билдеры (`tools/*.lua`), и только потом заменяй модели: билдеры удаляют объекты с теми же именами.",
    "Перед повторным запуском любого билдера сделай дубликат своих объектов.",
    "Проверяй на свежем сервере (Stop → Play), а не Reset Character. Смотри Output: все проблемы с ассетами пишутся `warn` с точным именем.",
])
box("Если ассет не подошёл (нет `PrimaryPart`/`Root`, не тот класс, не хватает частей), код пишет `warn` в Output и берёт кодовый плейсхолдер — игра не падает. Всегда смотри Output после замены.")

# ============================================================================
# 2. ТИР-МОДЕЛИ
# ============================================================================
story.append(PageBreak())
H1("2. Шахты, тележки, кирки, кристаллы")
nMine, nCart, nPick = len(cfg["MineTiers"]), len(cfg["CartTiers"]), len(cfg["PickaxeTiers"])
TABLE(["Имя ассета", "Кол-во", "Класс", "Обяз.", "Что это"], [
    ["Mine_Tier1 … Mine_Tier%d" % nMine, str(nMine), "Model", "нет", "Шахта (пещера) на участке, по одной на тир пещеры"],
    ["Cart_Tier1 … Cart_Tier%d" % nCart, str(nCart), "Model", "нет", "Тележка каждого тира"],
    ["CartPackage_Tier1 … _Tier%d  /  CartPackage" % nCart, "%d + 1" % nCart, "Model / BasePart", "нет", "Упакованная тележка в рюкзаке/на земле (общий вид — CartPackage)"],
    ["Pickaxe_Tier1 … Pickaxe_Tier%d" % nPick, str(nPick), "Tool", "нет", "Кирка каждого тира"],
    ["Crystal_Tier1 … Crystal_Tier%d" % nMine, str(nMine), "Model / BasePart", "нет", "Общий кристалл тира (переноска в руках, превью коллекции, выбитые из тележки)"],
], [58, 14, 24, 12, 68], code_cols=(0,))

H2("2.1 Mine_Tier<N> — шахта")
TREE("""
Mine_Tier1 (Model, PrimaryPart назначен)
├─ BuildingParts...            статичная геометрия (анкорится)
├─ Zone            (BasePart)  ОБЯЗАТЕЛЬНО: парковка тележки / зона добычи
├─ OreDropPoint    (BasePart)  высота, с которой падает руда
├─ ENTRY / Entry   (BasePart)  вход: отсюда вылетает руда, центр шахты
├─ MineEntryPoint  (BasePart)  куда «заходит» камера/игрок в мини-игре
├─ MinerMarker     (BasePart)  где стоит NPC-шахтёр (иначе слева от Zone)
├─ MineFront       (BasePart)  лицевая сторона шахты
├─ MinePath1, MinePath2...     точки пути в шахту (по порядку)
├─ CameraMarker1 + CameraMarker1Look   камера мини-игры: где стоит / куда смотрит
├─ CameraMarker2 + CameraMarker2Look   ... сколько нужно, без пропусков номеров
└─ MineDoor        (BasePart)  ворота; внутри Attachment-ы VFX_<Редкость>
""")
UL([
    "Все маркеры ищутся рекурсивно, кроме `Zone` все необязательны (есть расчёт по `Zone`).",
    "Какой `CameraMarker` на какой стадии мини-игры — `Config.MineExpedition.CameraMarkerForStage`.",
    "**Ворота MineDoor**: при выбивании руды часть становится Neon цвета редкости (`Config.MineDoorRarityColor`), и включаются все `Attachment` внутри, чьё имя начинается с `VFX_<Редкость>` (`VFX_Common`, `VFX_Uncommon`, `VFX_Rare`, `VFX_Epic`, `VFX_Legendary`), остальные `VFX_*` выключаются. Эмиттеров на редкость — сколько угодно.",
])
H2("2.2 Cart_Tier<N> — тележка")
TREE("""
Cart_Tier1 (Model, PrimaryPart = Root)
├─ Root            (BasePart)  пол тележки, Anchored = false
├─ BodyParts...                приварены к Root (WeldConstraint)
├─ AttachPoint     (BasePart)  высота крепления к игроку
├─ FacingPoint     (BasePart)  какая сторона смотрит на держателя
├─ Hitbox          (BasePart)  объём, по которому бьёт кирка
├─ Bottom          (BasePart)  нижняя точка (ступеньки/подъёмы)
├─ SprintVFXPoint  (BasePart)  где эффект бега
├─ LeftHandGrip + RightHandGrip  точки рук (обе, иначе авто-raycast)
├─ ValueGui        (BillboardGui) → TextLabel   сумма в тележке
└─ ComboGui        (BillboardGui) → TextLabel   комбо (UIGradient = радуга)
""")
UL([
    "Сетка груза: 4 × 3 ячейки шаг `1.8` studs, слои вверх. Пол `Root` ≈ `7.2 × 5.4` studs. Проверка — `tools/BuildCartSizeGuides.lua`.",
    "Части с Boolean-атрибутом `DailyColorable = true` перекрашиваются наградой дня.",
    "Неполный `ValueGui`/`ComboGui` код удалит и заменит стандартным.",
])
H2("2.3 CartPackage — упакованная тележка")
P("`CartPackage_Tier<N>` (свой вид на тир) или общий `CartPackage`. `Model` с `PrimaryPart`/`Root` или один `BasePart`. Игрок держит её в руках и ставит на участок — после постановки появляется `Cart_Tier<N>`.")
H2("2.4 Pickaxe_Tier<N> — кирка")
TREE("""
Pickaxe_Tier1 (Tool)
├─ Handle (BasePart, прямой ребёнок)   хват настрой через Grip/ориентацию
└─ VisualParts...  приварены к Handle
""")
P("Код переименует Tool в `Pickaxe`, `CanBeDropped = false`, удалит скрипты.")
H2("2.5 Crystal_Tier<N> — кристалл тира")
TREE("""
Crystal_Tier1 (Model, PrimaryPart = Root)   или один BasePart
├─ Root (BasePart)
├─ Decoration...  приварены к Root
└─ PriceGui (BillboardGui, необяз.) → TextLabel (прямой ребёнок)
""")
UL([
    "Код сам ставит цену, цвет, атрибуты и случайный масштаб ±8%. Размер с разбросом должен быть **меньше ячейки тележки 1.8 × 1.8** studs.",
    "`ParticleEmitter` внутри кристаллов прореживаются в заполненной тележке.",
])

# ============================================================================
# 3. РУДА
# ============================================================================
H1("3. Руда, слитки, мусор")
ores = [o["Key"] for o in ordered(cfg["OreChain"])]
rar = {o["Key"]: o.get("Rarity", "") for o in ordered(cfg["OreChain"])}
P("Кристалл конкретной руды в тележке. Ищется сначала вариация, потом общий вид, потом цветной плейсхолдер:")
TREE("""
Crystal_<Руда>_V1 / _V2 / _V3   вариация I / II / III (размер 0.9 / 1.0 / 1.12)
Crystal_<Руда>                  общий вид руды (если вариаций нет)
Ingot_<Руда>  →  Ingot          переплавленный слиток (Smelter)
""")
P("Контракт — как у `Crystal_Tier<N>` (раздел 2.5). Все имена руды (%d). В колонке «Имя ассета» — ровно то, как называть модель в `ReplicatedStorage/Assets` (буква в букву, без скобок и пробелов). «Редкость» — только подсказка, в имя её **не** писать: это редкость руды в первой пещере, где она появляется (в следующих пещерах та же руда становится обычнее)." % len(ores))
rows = []
half = (len(ores) + 1) // 2
for i in range(half):
    left = ores[i]
    right = ores[i + half] if i + half < len(ores) else None
    rows.append(["Crystal_" + left, rar[left], ("Crystal_" + right) if right else "", rar[right] if right else ""])
TABLE(["Имя ассета", "Редкость", "Имя ассета", "Редкость"], rows, [34, 16, 34, 16], code_cols=(0, 2))
junk = [v.get("Key") for v in ordered(cfg["Junk"]["Items"])]
P("Мусор (выпадает вместо руды, `Config.Junk.Items`) — ассет с именем ключа, `Model` с `Root`/`PrimaryPart` или `BasePart`: " + ", ".join("`%s`" % k for k in junk) + ".")

# ============================================================================
# 4. МИР И УЧАСТОК
# ============================================================================
story.append(PageBreak())
H1("4. Мир, участок, постройки")
H2("4.1 PlotTemplate — шаблон участка")
TREE("""
PlotTemplate (Model, PrimaryPart = PlotPad)
├─ PlotPad              (BasePart)  ОБЯЗ. пол участка
├─ MineMarker           ОБЯЗ.  где шахта
├─ MineFacingMarker     куда смотрит шахта
├─ PillarMarker         ОБЯЗ.
├─ CartSpawnMarker      где появляется тележка (иначе 12 studs от шахты)
├─ PlayerSpawnMarker    ОБЯЗ.  спавн игрока
├─ RebirthMarker        ОБЯЗ.  мэр престижа + витрина престижа
├─ CartButtonMarker     кнопка тележки
├─ ShopMarker           магазин (без него ShopNPC на участке НЕ создаётся)
├─ LeaderboardMarker    доски лидеров
├─ GeodeBuildingMarker / GeodePodiumMarker / GeodeSafeMarker
├─ BoulderMarker1 … BoulderMarker8   личные валуны на базе (до 8)
├─ IslandAnvilMarker / IslandIncomeMarker / IslandSmelterMarker   острова
└─ декорации...         клонируются на каждый участок
""")
UL([
    "Любому маркеру можно добавить соседа `<Имя>Look` (`MineMarkerLook`) — направление к нему задаёт поворот.",
    "Ручная расстановка участков: `Workspace/PlotOrigins` → `Plot1`, `Plot1Look`, `Plot2`… Без папки — автоматически по кругу.",
])
H2("4.2 Прочие постройки мира")
TABLE(["Имя", "Класс", "Обяз.", "Что внутри / контракт"], [
    ["Bank", "Model", "нет", "`Building` (BasePart, не Model!), `SellZone` (BasePart — отдельная квадратная зона продажи, ~18×18) и `MerchantSpot` (невидимый BasePart справа от зоны, за её краем — там встаёт торговец, к нему можно подойти не продавая). Или своя модель прямо в Workspace с атрибутом `IsBank = true`."],
    ["LeaderboardBoards", "Model + PrimaryPart", "нет", "Рекурсивные BasePart `MoneyBoard`, `RebirthBoard`, `CartDamageBoard`. SurfaceGui код создаёт сам (см. LEADERBOARDS_GUIDE.md)."],
    ["RespawnButton", "BasePart / Model", "нет", "Корень (`PrimaryPart`/`Root`) получает ProximityPrompt, таймер и анимацию нажатия."],
    ["GeodeBuilding", "Model", "нет", "`PrimaryPart`/`Root` + рекурсивный BasePart `Crusher` (на нём промпт)."],
    ["GeodePodium", "BasePart / Model", "нет", "`Root` в центре платформы. Необяз. невидимый `OrePlacement` — точка, куда ставится камень."],
    ["GeodeSafe", "BasePart / Model", "нет", "Сейф пассивного дохода, промпт на корне."],
    ["PrestigeCase", "Model", "нет", "Витрина престижа рядом с мэром (`Config.Prestige.CaseModelName`). Анкорится кодом."],
    ["QuestMarker", "Model / BasePart", "нет", "Знак «!» над целью квеста (свой вид вместо кодового)."],
], [30, 26, 10, 110], code_cols=(0,))
H2("4.3 Точки в Workspace (не ассеты)")
UL([
    "`workspace.RubbleBoulderSpawnPoints` — папка с BasePart-точками для валунов мира; атрибут `Tier` (число) необязателен. Быстрый старт — `tools/BuildRubbleBoulderSpawnPoints.lua`.",
    "`workspace.PlotOrigins` — см. 4.1.",
])

# ============================================================================
# 5. NPC
# ============================================================================
H1("5. NPC")
TABLE(["Имя ассета", "Кто это", "Где стоит"], [
    ["ShopNPC", "Продавец магазина", "ShopMarker участка"],
    ["UpgradeShopNPC", "Прокачка (Upgrade Mole)", "маркер прокачки / участок"],
    ["RebirthNPC", "Мэр престижа (ребёрт)", "RebirthMarker"],
    ["MinerNPC", "Шахтёр у входа в шахту", "MinerMarker в шахте"],
    ["IslandKeeperNPC", "Хранитель островов", "рядом с островами"],
    [cfg["Merchant"].get("AssetName", "BankMerchant"), "Торговец у банка (Config.Merchant.AssetName). Над ним — табло `MerchantBoard` (название, курс руды, таймер товара); своё табло в модели — BillboardGui `MerchantBoard` с TextLabel `Market` и `Timer` (необяз. `Title`).", "`MerchantSpot` банка — справа ЗА зоной продажи"],
], [40, 70, 66], code_cols=(0,))
UL([
    "Класс: `Model` с назначенным `PrimaryPart` (имя любое). Необязательный `FacingPoint` задаёт перед NPC.",
    "**Свой ассет** код только ставит на маркер, подгоняет по высоте и добавляет `ProximityPrompt`. Части не анкорит, скрипты/аксессуары не трогает — можно анимировать своим скриптом (пример `tools/ExampleNpcStretchScript.lua`, атрибут `Talking`).",
    "Имя над головой: положи в модель `BillboardGui` с `TextLabel` **name** (+ необяз. **arrow**, **dialog**) — клиент сам приведёт их к единому стилю (шрифт денег, белый, стрелка-шеврон).",
])
TREE("""
NPC (Model)
└─ gui (BillboardGui)
   ├─ name   (TextLabel)   имя NPC
   ├─ arrow  (TextLabel)   стрелка под именем (текст можно оставить пустым)
   └─ dialog (TextLabel)   реплика (показывается при разговоре)
""")

# ============================================================================
# 6. ВАЛУНЫ И ГОБЛИНЫ
# ============================================================================
story.append(PageBreak())
H1("6. Валуны и гоблины")
H2("6.1 Boulder_Tier<N>")
nb = len(cfg["Boulders"]["RewardMoneyByTier"])
P("`Boulder_Tier1` … `Boulder_Tier%d` — прямо в `Assets`. `Model` с `PrimaryPart` или частью `Root`." % nb)
UL([
    "Код анкорит всё, выключает коллизию (удар считается по позиции `Root`), вешает полоску ХП, делает пружинную «тряску» при ударе.",
    "Элитный («золотой») валун — та же модель + `Highlight`, отдельную модель не делай.",
    "Нет ассета — цветной шар цвета тира.",
])
H2("6.2 Гоблины и лагерь (v20.44)")
gt = list(cfg["Goblins"]["Types"].keys())
P("По 1–3 скина на тип (случайный при спавне): " + ", ".join("`Goblin_%s` / `Goblin_%s_1.._3`" % (t, t) for t in gt) + ". Точные имена и внешний вид — раздел 16.3.")
TREE("""
Goblin_Warrior_1 (Model, R6-риг)
├─ HumanoidRootPart   ОБЯЗ. (станет невидимым)
├─ Torso, Head        ОБЯЗ.
├─ Left Arm, Right Arm, Left Leg, Right Leg   ОБЯЗ. (имена с пробелами!)
├─ Humanoid           (свой можно; нет — создастся)
├─ Motor6D: RootJoint, Neck, Left/Right Shoulder, Left/Right Hip
└─ Animations (Folder, необяз.) — СВОИ АНИМАЦИИ этого гоблина:
   ├─ Idle, Walk, Run          (Animation, зацикленные)
   ├─ Attack1, Attack2, Attack3 (по очереди; можно один Attack)
   ├─ Hit                      (получил удар)
   ├─ Stun                     (оглушён, зацикленная)
   └─ Death                    (держит последний кадр)
""")
P("Нет папки `Animations` или какой-то анимации в ней — берётся ID из `Config.Goblins.Animations` (Idle, Walk, Run, Attacks, Hit, Stun, Death; 0 = нет). Анимации играет клиент по атрибутам модели, ИИ считает сервер.")
TREE("""
Workspace/GoblinCamp            ЛАГЕРЬ ГОБЛИНОВ
├─ Zone      (Part, невидимый, CanCollide off)  границы лагеря; гоблины не выходят
├─ Spawns/   (Folder) Part'ы-точки появления, сколько угодно
└─ Marker    (Part, необяз.)  над ним табличка лагеря; нет — над центром Zone
""")
UL([
    "Волна раз в 5 минут (`Config.GoblinRaid.IntervalSeconds`), стоит, пока её не зачистят. Состав и дроп — `Config.GoblinRaid.Waves`.",
    "Земля внутри `Zone` сканируется один раз на старте: клетки 4 стада, нужна пустота 5 стадов над землёй. Не ставь в лагерь невидимые детали с коллизией — клетка станет «стеной».",
    "Табличку над лагерем, трейл пинка и звёзды оглушения код строит сам.",
])

# ============================================================================
# 7. ЖЕОДЫ
# ============================================================================
H1("7. Жеоды и коллекционная руда")
order = ordered(cfg["Geodes"]["Order"])
P("Физические жеоды (%d): " % len(order) + ", ".join("`Geode_%s`" % g for g in order) + ". `BasePart` или `Model` с `Root` = `PrimaryPart`; все части приварены к `Root` (в тележку приваривается только корень). Внутри можно положить `Attachment` `GeodeVFX_<Тип>` с эмиттерами.")
P("`GeodeHammer` — молот вскрытия в руке (`Tool`/`Model` с `Handle`), `Config.GeodeCutscene.HammerAsset`.")
H2("7.1 CollectionOre_<Id> — камни коллекции")
P("Показываются на подиуме, в руках при переноске и в книге коллекции. `BasePart` или `Model` с `Root`; код анкорит. Картинка камня — `ImageId` в `Config.Geodes.Ores.<Id>` (или `Config.Boulders.CustomOres.<Id>` для валунных).")
gtypes = cfg["Geodes"]["Types"]
rows = []
for g in order:
    ores_g = ordered(gtypes[g].get("Ores"))
    rows.append([g, ", ".join("`CollectionOre_%s`" % o for o in ores_g)])
rows.append(["Валуны", ", ".join("`CollectionOre_%s`" % o for o in cfg["Geodes"]["BoulderOreOrder"].values()) if isinstance(cfg["Geodes"].get("BoulderOreOrder"), dict) else ", ".join("`CollectionOre_%s`" % o for o in sorted(cfg["Boulders"]["CustomOres"].keys()))])
TABLE(["Жеода", "Точные имена ассетов"], rows, [22, 154], code_cols=(0,))
box("Не меняй ID руды после релиза (`GreenCrystal`, `SunOpal`…) — они в сохранениях. `DisplayName` менять можно.")

# ============================================================================
# 8. СУНДУКИ, ДИНАМИТ, ПРЕДМЕТЫ БАЗЫ
# ============================================================================
story.append(PageBreak())
H1("8. Сундуки, динамит, предметы базы")
H2("8.1 Сундуки")
TABLE(["Имя / путь", "Класс", "Что это"], [
    ["Assets/Chests/" + ", ".join(v["ModelName"] for v in cfg["Chests"]["Types"].values()), "Model / BasePart", "Сундук, поставленный игроком (с таймером). **Именно в папке `Assets/Chests`** (`Config.Chests.AssetFolderPath`). Этот же вид — у призрака установки."],
    ["Chest", "Model", "Сундук, который несёт/роняет гоблин (прямо в `Assets`)."],
    ["LootBox (или Box/box)", "Model / BasePart", "Коробка, вылетающая из валуна/сундука для наград без 3D-вида (скины). Размер подгоняется до 2 studs."],
], [70, 22, 84], code_cols=())
H2("8.2 Динамит")
P("Имена = ключи `Config.Dynamite.Types`: " + ", ".join("`%s`" % k for k in cfg["Dynamite"]["Types"].keys()) + ". `Model` (с `PrimaryPart`) или `BasePart`, можно в подпапке. Пивот ставится в низ габарита, части анкорятся, скрипты удаляются. Нет своей модели для Medium/Mega — берётся `Dynamite` и увеличивается/перекрашивается.")
DECOR_LOOK = {
    "Flowers1": "Грядка тюльпанов: низкий холмик земли ~2.6 стада и 6 цветков разных цветов (красный, розовый, жёлтый, фиолетовый, белый) высотой 1–1.5 стада.",
    "Flowers2": "Подсолнухи в глиняном горшке: терракотовый горшок ~1.6 стада, три стебля 2–2.8 стада с жёлтыми «тарелками» и коричневой серединкой.",
    "Bush1": "Круглый зелёный куст ~2.2 стада из нескольких шаров листвы (материал Grass).",
    "Bush2": "Ягодный куст: крупнее и темнее Bush1 (~2.6 стада), по листве рассыпаны красные ягоды.",
    "IronLantern": "Чугунный фонарь на столбе ~5.8 стада, тёплый огонь в стеклянной клетке.",
    "OreBarrel": "Деревянная бочка с железными обручами, сверху светящиеся куски руды.",
    "Bench": "Деревянная скамейка на чугунных боковинах ~5 × 1.8 стада, спинка сзади (+Z). **На неё садятся** — см. 8.5.",
    "OreJar": "Стеклянная банка ~2 стада на деревянной подставке, медная крышка. **Руда внутри крутится** — см. 8.5.",
    "CrystalLantern": "Каменная подставка со светящимся голубым кристаллом, искры.",
    "StorageChest": "Окованный деревянный сундук ~3.4 × 2.2 стада, полукруглая крышка, золотой замок спереди (-Z), из-под крышки голубой свет. **Хранилище руды** — см. 8.5.",
    "PlushMole": "Плюшевый крот: мягкие шары (Fabric), розовый нос, бантик.",
    "CrystalCluster": "Каменное основание и пучок фиолетово-голубых кристаллов, свет и искры.",
    "MinerStatue": "Каменная статуя шахтёра с киркой на постаменте.",
    "MoleStatue": "Золотая статуя крота на постаменте.",
}
H2("8.3 Тотемы, декор, трофеи (предметы базы)")
tt = cfg["Placeables"]["TotemTypes"]
ntier = len(cfg["Placeables"]["TierColors"])
TABLE(["Имя ассета", "Что это"], [
    ["Totem_<Тип>_T1 … _T%d" % ntier, "Тотем конкретного тира. Типы: " + ", ".join("`%s`" % k for k in tt.keys()) + " (для Prism — `Totem_Prism_T<N>`)."],
    ["Totem_<Тип>", "Общий вид тотема, если нет модели на тир."],
] + [[v["Asset"], "**%s** (%s). %s" % (v.get("DisplayName", k), v.get("Rarity", ""), DECOR_LOOK.get(k, "Декор."))] for k, v in sorted(cfg["Placeables"]["Decor"].items(), key=lambda kv: cfg["Placeables"]["DecorOrder"].index(kv[0]) if kv[0] in cfg["Placeables"]["DecorOrder"] else 99)]
  + [[v["Asset"], "Трофей (реликвия): " + k] for k, v in cfg["Relics"]["Types"].items()]
  + [["RelicPedestal", "Постамент под трофей; пивот у земли, трофей ставится на верх постамента."]],
  [48, 128], code_cols=(0,))
UL([
    "Класс: `Model` (с `PrimaryPart`/`Root`) или один `BasePart`. Пивот — центр нижней грани (код выставит сам).",
    "Код анкорит, выключает коллизию, удаляет скрипты. Подпись над предметом (имя, эффект, «found by») код создаёт сам — свою не нужно.",
    "Прямо в `Assets` (не в подпапке).",
])
H2("8.4 Престиж, острова, мини-игра")
shr = cfg["Prestige"]["Shrines"]["Types"]
TABLE(["Имя ассета", "Что это"], [
    [", ".join(v["Asset"] for v in shr.values()), "Святилища престижа (`Config.Prestige.Shrines.Types`)."],
    [", ".join(v["Model"] for v in cfg["Islands"]["Definitions"].values()), "Острова (`Config.Islands.Definitions.<Id>.Model`), встают на маркеры `Island<Id>Marker`."],
    ["Smelter_Level1 … _Level%d  /  Smelter" % len(cfg["Islands"]["Smelter"]["Levels"]), "Печь острова Smelter — свой вид на уровень или общий."],
    ["Assets/MineRarityCards/<Редкость>", "Карточки редкости в мини-игре шахты: Common, Uncommon, Rare, Epic, Legendary. `Model`/`BasePart`."],
], [70, 106], code_cols=())

H2("8.5 Рабочий декор: скамейка, сундук-хранилище, банка (v20.22)")
P("Покупаются у торговца, как обычный декор, ставятся из руки. У них основное действие на **E**, а «поднять» — вторая строка промпта на **R** (на телефоне — тап по второй строке). Всё настраивается в `Config.Placeables` (`Decor.<Id>.Function`, `Storage`, `Jar`).")
TREE("""
Decor_Bench (Model, PrimaryPart = Root)
├─ Root         (BasePart)  основание, пивот — низ
├─ ...          доски, ножки, спинка — сзади (+Z), сидящий смотрит в -Z
└─ Seat         (класс Seat!) там, где сидят: невидимая плита ~4.4 × 0.2 × 1.4,
                LookVector (-Z) — куда смотрит сидящий. Нет Seat — код создаст
                невидимый на 45% высоты модели.

Decor_StorageChest (Model, PrimaryPart = Root)
└─ Root + любые детали. Особых частей не нужно: промпт OPEN вешается на Root.

Decor_OreJar (Model, PrimaryPart = Root)
├─ Root         (BasePart)  подставка / дно
├─ стекло       Glass, Transparency 0.5–0.7 — руду должно быть видно
└─ OreSpot      (BasePart, невидимый, ~0.3)  ЦЕНТР, где крутится руда.
                Нет — берётся центр габарита модели.
""")
TABLE(["Предмет", "Как работает", "Что заменить / нарисовать"], [
    ["Decor_Bench", "Промпт **SIT** — садит на `Seat` (сесть может любой игрок, не только владелец). Прыжок — встать. Сам по касанию не садит.", "Своя модель скамейки + деталь класса `Seat` на сиденье. Анимация сидения — стандартная Roblox."],
    ["Decor_StorageChest", "Промпт **OPEN** (только владелец) открывает окно `StarterGui/DecorStorageUi`: 10 ячеек сундука и руда рюкзака. Клик — переложить стопку, `TAKE ALL` / `PUT ALL`. Руда в сундуке сохраняется и **не теряется при смерти**. Поднять можно только пустым.", "Модель сундука. Окно — правится в Studio после `BuildAllUI` (шаблон ячейки `Panel/Templates/Cell`). Число ячеек — `Config.Placeables.Storage.Slots`."],
    ["Decor_OreJar", "Держишь руду из хотбара → **PUT ORE**: кусок уходит в банку, уменьшенная копия крутится внутри (клиент `DecorJarSpin`), над банкой табличка: редкость (цветом) и название. **TAKE ORE** — вернуть в рюкзак. При подборе банки руда возвращается сама.", "Модель банки со стеклом и `OreSpot`. Размер руды внутри — `Config.Placeables.Jar.OreSize` (1.1 стада), скорость — `SpinSpeed`, покачивание — `BobHeight`."],
], [26, 80, 70], code_cols=(0,))

H2("8.6 Плавильня (остров Smelter)")
P("Остров плавильни покупается у Island Keeper и выезжает на маркер участка `IslandSmelterMarker`. На нём стоит печь: держишь руду из хотбара → жмёшь **SMELT ORE** (или кликаешь по печи) → через 3–5 минут (идёт и офлайн) из устья вылетает **слиток** той же руды с теми же мутациями, цена × %s. Число одновременных слотов растёт с уровнем печи." % cfg["Islands"]["Smelter"].get("ValueMultiplier", 20))
TREE("""
Island_Smelter (Model, PrimaryPart)         парящий остров
└─ StationMarker (BasePart на поверхности)  где встаёт печь; LookVector —
   └─ StationMarkerLook (необяз.)           куда смотрит устье (или точка-цель)

Smelter_Level1 … Smelter_Level4  (или общий Smelter)  — Model, PrimaryPart = Root
├─ Root              (BasePart) ОБЯЗ.  основание; пивот ставится в низ
├─ Body              (BasePart)  корпус: над ним табло SmelterBoard, по нему клик
├─ Mouth             (BasePart, невидимый) устье: промпт SMELT ORE, сюда летит
│                    руда, отсюда вылетают слитки. Нет — всё на Root
├─ furnace_inactive  (Model)  холодное тёмное устье — видно, пока печь пуста
├─ furnace_active    (Model)  раскалённое устье + огонь — видно, пока плавит;
│                    именно она «дышит» (анимация клиента FurnaceFX)
├─ FireLight         (PointLight)  свет печи (включается при плавке)
└─ Smoke             (ParticleEmitter)  дым из трубы (включается при плавке)
""")
lv = ordered(cfg["Islands"]["Smelter"]["Levels"])
SMELTER_LOOK = [
    "Низкая глиняная печь-купол рыже-коричневого цвета ~6 × 6 × 6 стадов, короткая труба, устье в деревянной рамке. Бедно, но уютно.",
    "Квадратная печь из красного кирпича ~7 стадов, железная заслонка на устье, одна высокая труба, кирпичный цоколь.",
    "Кузнечная печь из тёмного железа с заклёпками ~8 стадов, две трубы, мехи сбоку, рядом наковальня и ведро с водой.",
    "Массивная литейная из обсидиана ~10 стадов с оранжевыми магмовыми трещинами (Neon), три трубы, ковш с расплавленным металлом, лава капает из устья.",
]
TABLE(["Ассет", "Уровень", "Слоты", "Цена", "Примерный внешний вид"], [
    ["Smelter_Level%d" % i, lv[i - 1].get("Name", ""), str(lv[i - 1].get("Slots", "")), ("%s" % lv[i - 1].get("Cost")) if lv[i - 1].get("Cost") else "сразу", SMELTER_LOOK[i - 1] if i - 1 < len(SMELTER_LOOK) else ""]
    for i in range(1, len(lv) + 1)
], [32, 22, 12, 15, 95], code_cols=(0,))
UL([
    "**Как заменить:** положите модель `Smelter_Level<N>` прямо в `ReplicatedStorage/Assets`; назначьте `PrimaryPart` (или назовите основание `Root`). Нет модели на уровень — берётся общий `Smelter`, нет и его — кодовый плейсхолдер (свой вид на каждый уровень).",
    "Модели `furnace_active` и `furnace_inactive` — **по одной** внутри печи; код прячет одну и показывает другую (прозрачность 1 и выключенные эмиттеры/свет). Можно без них — тогда печь не меняет вид, «дышит» вся модель.",
    "Надпись над печью (уровень, «SMELTING… 2:31», «READY!») код строит сам — свою не нужно.",
    "Слиток: `Ingot_<Руда>` или общий `Ingot` (его код перекрасит в цвет руды; детали с атрибутом `KeepColor = true` не перекрашиваются).",
    "Улучшение печи (у Island Keeper) — старая модель сжимается, новая вырастает на том же месте (катсцена клиента).",
])

# ============================================================================
# 9. СКИНЫ
# ============================================================================
story.append(PageBreak())
H1("9. Скины")
P("У скинов **нет** кодового плейсхолдера: нет ассета — скин не выдаётся и не показывается. `Tool` с прямым `Handle` или `Model` с `SkinRoot` = `PrimaryPart`. Внутренние сварки не нужны — `SkinService` сам приваривает все части к корню, делает их неколлизионными/невесомыми и удаляет скрипты.")
TREE("""
Skin_Pickaxe_BigWooden (Tool)          или Model (PrimaryPart = SkinRoot)
├─ Handle (BasePart, прямой ребёнок)   ├─ SkinRoot (BasePart)
├─ VisualParts...                      ├─ VisualParts...
└─ ParticleEmitter / Trail / Beam      └─ эффекты
""")
sk = cfg["Skins"]["Definitions"]
rows = []
for sid, v in sorted(sk.items(), key=lambda x: (x[1].get("Kind", ""), x[0])):
    rows.append([v.get("AssetName", ""), v.get("Kind", ""), sid, v.get("DisplayName", ""), str(v.get("ImageId", "—"))])
TABLE(["AssetName (имя модели)", "Kind", "ID в сохранениях", "DisplayName", "ImageId"], rows, [50, 13, 38, 40, 35], code_cols=(0, 2))
UL([
    "Безопасно менять только `DisplayName`. Ключ (ID) — в сохранениях игроков. `AssetName` меняй только вместе с именем модели.",
    "Категории Cart/Ore в окне скинов сейчас `COMING SOON` (`Config.Skins.EnabledKinds`).",
    "`ImageId` — иконка скина в интерфейсе (число без `rbxassetid://`, 0 = 3D-превью/заглушка).",
])

# ============================================================================
# 10. VFX
# ============================================================================
story.append(PageBreak())
H1("10. VFX (эффекты)")
P("Где указано «Attachment»: подходит сам `Attachment` с эмиттерами, **или** Part/Model/Folder с `Attachment` внутри, **или** Part/Model просто с `ParticleEmitter`/`Beam`/`Light` — код сам соберёт их в Attachment.")
mut_vfx = [k for k, v in cfg["Mutations"].items() if isinstance(v, dict) and v.get("VfxName")]
TABLE(["Имя ассета", "Класс", "Где играет / контракт"], [
    ["swing", "Attachment", "Замах киркой, один выброс у HumanoidRootPart. Атрибут `EmitCount` (по умолч. 10)."],
    ["PickaxeHitVFX", "Attachment", "Попадание киркой."],
    ["BoulderBreakVFX", "Attachment", "Разрушение валуна (итоговый эффект). Свой на тир — `BoulderBreakVFX_<тир>` (`BoulderBreakVFX_5`), на золотой — `BoulderBreakVFX_Golden`. Свои эффекты не перекрашиваются."],
    ["Reveal_<Редкость>, Reveal_Mutation, RevealVFX", "Attachment / Part / Model / Folder", "Разовая вспышка при выпадении редкой руды (из валунов, золотого валуна, с мутацией) — вместо старого столба света. Эмиттеры стреляют один раз (атрибут `EmitCount`, по умолч. 20), Beam/Light горят `Duration` (0.6 с). Нет — плейсхолдер по редкости."],
    ["Reveal_Chest_<Редкость>", "как Reveal_*", "Открытие сундука (вместо столба света). Нет — берётся `Reveal_<Редкость>`, потом плейсхолдер."],
    ["PrestigeVFX", "Attachment / Part / Model / Folder", "Престиж: эффект на игроке (крепится к HumanoidRootPart, видят все). Нет — плейсхолдер «аура-корона»: вспышка у ног, золотая аура ~4 с, вращающаяся корона над головой."],
    ["SprintVFX", "BasePart / Model", "Бег с тележкой; корень приваривается к тележке в `SprintVFXPoint`. Эмиттеры могут быть в Attachment."],
    ["ShieldVfx, ShieldVfxVIP", "BasePart / Model", "Щит над головой игрока (обычный / VIP). Эмиттеры включает/выключает код."],
    ["BankSellVFX", "BasePart / Model", "Вспышка над тележкой при полной продаже (`Config.BankSellVfx`). Одноразовый: эмиттеры `Enabled = true` с `Rate`, `Emit()` не вызывается."],
    ["GeodeCartVFX", "BasePart / Model", "Жеода в тележке; burst, атрибут `EmitCount` (по умолч. 24)."],
    ["GeodeVFX_<Тип>", "Attachment внутри Geode_<Тип>", "Свечение физической жеоды."],
    ["GeodeDropVFX", "ParticleEmitter / контейнер", "Вспышка при выпадении из жеоды (экранная)."],
    ["DailyRewardVFX", "ParticleEmitter / контейнер", "Частицы у окна ежедневной награды."],
    ["BookVFX", "ParticleEmitter / BasePart / Model", "Эффект за кнопкой книги коллекции. Атрибуты: `ScreenOffset` (Vector2), `Depth` (12), `ReferenceViewportHeight` (1080)."],
    [", ".join("MutationVFX_" + k for k in mut_vfx), "Attachment", "Мутации руды с эффектом (`Config.Mutations.<Id>.VfxName`). Также ищется `MutationVfx_<Имя>` и просто `<Имя>`."],
    ["VFX_<Редкость> внутри MineDoor", "Attachment", "Ворота шахты по редкости выбитой руды (раздел 2.1)."],
], [48, 34, 94], code_cols=())
tip("Для одноразовых эффектов задавай `Lifetime` короче времени жизни эффекта, иначе частицы оборвутся. Для «выбросов» (swing, GeodeCartVFX) ставь `Rate = 0` и регулируй атрибутом `EmitCount`.")

H2("10.1 Погода (v20.26)")
evs = ordered(cfg["WeatherEvents"]["Events"])
P("Небо — **без картинок-скайбоксов**: градиент «горизонт → зенит» даёт `Atmosphere`, плюс цветокоррекция, Bloom, звёзды/луна/солнце у `Sky`. Всё плавно меняется за %s с. SunRays погода не трогает. Эффекты (дождь, светлячки, пепел…) идут **по всей карте**, а не только перед камерой." % cfg["WeatherEvents"].get("LookTweenSeconds", 6))
TREE("""
ReplicatedStorage/Assets
├─ Weather/                  СВОЙ ВИД НЕБА И СВЕТА (необяз.)
│  ├─ Clear/Look/            ясная погода
│  ├─ Rain/Look/             папка на погоду: Night, Rain, Thunderstorm, BloodMoon, SolarEclipse
│  │   ├─ Atmosphere         настроенный в Studio (Density, Offset, Color, Decay, Glare, Haze)
│  │   ├─ ColorCorrectionEffect   (TintColor, Saturation, Contrast, Brightness)
│  │   ├─ BloomEffect        (Intensity, Size, Threshold)
│  │   ├─ Clouds             (Cover, Density, Color) — если нужны свои облака
│  │   └─ Sky                (StarCount, размеры луны/солнца; с картинками — свой скайбокс)
└─ WeatherFX/                БИБЛИОТЕКА ЭФФЕКТОВ
   └─ <Имя>/  (Folder)       атрибуты Mode = Fall | Float | Ground, Height = число
       ├─ ParticleEmitter…   Rate = частиц/сек на ОДНУ клетку карты (64×64 стадов)
       └─ Sound…             фоновый звук эффекта (играет по кругу)
""")
UL([
    "**Какие эффекты в какую погоду** — `Config.WeatherEvents.Events[].Effects = { \"RainDrops\", \"RainSplashes\" }` и `ClearEffects` для ясной. Любой эффект можно подключить к любой погоде.",
    "Нет папки `Weather/<Id>/Look` — вид берётся из `Config.WeatherEvents.Events[].Look` / `ClearLook` (числа и цвета прямо в конфиге).",
    "**Mode = Fall** — эмиттер на плите высоко над землёй клетки (не ниже камеры + 30), сыплет вниз: дождь, пепел, снег. **Float** — объём от земли до Height: светлячки, искры, пыльца. **Ground** — точки на земле: брызги, туман.",
    "Частицы живут в мире: вблизи камеры полная плотность, к краю радиуса (`Fx.Radius`) — реже, дальше выключены. Наклон дождя — от `workspace.GlobalWind` (у эмиттеров `WindAffectsDrag`).",
    "Своя текстура капли-штриха — `Config.WeatherEvents.Fx.RainTexture`; гром — `Lightning.ThunderSoundIds`.",
])
TABLE(["Погода", "Эффекты (Config)", "Небо и свет (кратко)"], [
    ["Clear", ", ".join(cfg["WeatherEvents"].get("ClearEffects") or []) or "—", "Голубой зенит, тёплая светлая дымка, звёзды ночью"],
] + [[e["Id"], ", ".join(e.get("Effects") or []), {
    "Night": "Глубокий синий → фиолетовая дымка, звёзды, луна",
    "Rain": "Серо-голубое, плотная дымка, приглушённые цвета",
    "Thunderstorm": "Графитовое небо с зеленцой, контраст; молнии",
    "BloodMoon": "Бордовая дымка, большая луна, красноватый свет",
    "SolarEclipse": "Сумерки днём, тёмный зенит, золотое кольцо у горизонта",
}.get(e["Id"], "")] for e in evs], [24, 52, 100], code_cols=(0,))
H3("Встроенные эффекты (плейсхолдеры)")
P("`RainDrops`, `StormRain`, `BloodDrizzle` (Fall); `RainSplashes`, `Mist` (Ground); `Fireflies`, `StarDust`, `Embers`, `Ash`, `Pollen` (Float). Папка `Assets/WeatherFX/<то же имя>` заменяет встроенный целиком.")
H3("Гроза")
UL([
    "Молния — ломаная неоновая линия с ветками, вспышка неба (своя `LightningFlash` цветокоррекция) и свет в точке удара; гром с задержкой по расстоянию.",
    "Иногда (`Lightning.NearChance`) бьёт рядом с игроком: блоки травы разлетаются, падают, подпрыгивают и плавно исчезают; облако пыли, искры и лёгкая тряска камеры (`ShakeNear`).",
])

# ============================================================================
# 11. ЗВУКИ
# ============================================================================
story.append(PageBreak())
H1("11. Звуки")
P("Все звуки — в `Config.Sounds` (`src/shared/Config.lua`). Формат записи:")
TREE("""
Имя = { Id = "rbxassetid://123", Volume = 0.5 }
Имя = { Id = "rbxassetid://1", Variants = { "rbxassetid://2", "rbxassetid://3" }, Volume = 0.5 }
Имя = { Id = "", Volume = 0.5 }      -- пусто = звук пропускается (у взрыва тогда встроенный Explosion)
""")
UL([
    "`Variants` — случайный выбор без повтора подряд (при двух вариантах они чередуются).",
    "`CartRoll` — единственный зацикленный (loop): должен бесшовно зацикливаться; поддерживает `RollOffMinDistance/MaxDistance`.",
    "Громкость всех звуков регулируется группой `SoundService/SFX` (настройки игрока).",
    "Звуки должны быть доступны experience (свои или публичные), иначе Roblox их не проиграет.",
])
block = config_src[config_src.index("Config.Sounds = {"):]
block = block[:block.index("\n}\n")]
rows = []
empty = 0
for line in block.split("\n"):
    m = re.match(r'\s*(\w+)\s*=\s*\{\s*Id\s*=\s*("([^"]*)"|(\d+))(.*?)\},?\s*(--\s*(.*))?$', line)
    if not m:
        continue
    name = m.group(1)
    sid = m.group(3) if m.group(3) is not None else m.group(4)
    rest = m.group(5)
    vol = re.search(r"Volume\s*=\s*([0-9.]+)", rest)
    var = len(re.findall(r"rbxassetid://\d+", rest))
    comment = (m.group(7) or "").strip()
    if len(comment) > 90:
        comment = comment[:88] + "…"
    status = sid if sid not in ("", "0", "rbxassetid://0") else "**ПУСТО — нужен свой**"
    if status.startswith("**"):
        empty += 1
    rows.append([name, status + ((" +%d вар." % var) if var else ""), vol.group(1) if vol else "", comment])
P("Всего записей: **%d**, из них пустых (нужно заполнить): **%d**. Остальные уже стоят временными звуками — можно заменить на свои." % (len(rows), empty))
TABLE(["Ключ", "Сейчас (Id)", "Vol", "Где звучит / примечание"], rows, [34, 50, 9, 83], code_cols=(0,))

H2("11.1 Музыка")
mus = cfg.get("Music") if "Music" in cfg else None
tracks = [l.split(" = ")[1] for l in cfgassets if l.startswith("Config.Music.Tracks.")]
P("`Config.Music.Tracks` — список полных строк `rbxassetid://…`, играют по очереди. Сейчас треков: %d." % len(tracks))

# ============================================================================
# 12. АНИМАЦИИ
# ============================================================================
H1("12. Анимации")
P("Полные строки `rbxassetid://…` или 0/`rbxassetid://0` = не проигрывать. Анимации должны принадлежать владельцу experience/группе и подходить к ригу (R15/R6).")
arows = []
for l in cfgassets:
    k, v = l.split(" = ", 1)
    if ("Anim" in k.split(".")[-1] or k.startswith("Config.Animations.")) and not k.endswith("Blend") and "IconText" not in k:
        arows.append([k.replace("Config.", ""), v if v not in ("0", "rbxassetid://0") else "**0 — не задана**"])
TABLE(["Поле Config", "Сейчас"], arows, [100, 76], code_cols=(0,))

# ============================================================================
# 13. КАРТИНКИ
# ============================================================================
story.append(PageBreak())
H1("13. Картинки (ImageId)")
P("Числовые поля — **только число** без `rbxassetid://` (0 = заглушка: эмодзи, текст или цвет). Строковые (`UiTheme`) — полная строка `rbxassetid://…` или пусто.")
H2("13.1 UiTheme.Icons — иконки интерфейса")
icons = re.findall(r'^\s*(\w+)\s*=\s*"([^"]*)",?\s*(--\s*(.*))?$', open(os.path.join(REPO, "src/shared/UiTheme.lua"), encoding="utf-8").read().split("Theme.Icons = {")[1].split("\n}")[0], re.M)
ICON_DESC = {"Money": "значок денег (сейчас эмодзи-мешок)", "Prestige": "звезда престижа в HUD", "Shards": "кристаллы-осколки",
             "Gift": "подарок на кнопке подарка", "Lock": "замок (закрытые предметы)", "Shop": "кнопка магазина в HUD",
             "Quests": "кнопка квестов в HUD", "Settings": "кнопка настроек", "Inventory": "кнопка инвентаря", "Skins": "кнопка скинов",
             "Rewards": "кнопка наград", "Social": "кнопка «группа/лайк»", "Book": "кнопка книги коллекции",
             "QuestDiamond": "золотой ромб у квеста в трекере (пусто = рисованный ромб)", "Check": "галочка «получено» (пусто = рисованная галочка)"}
TABLE(["Ключ", "Сейчас", "Что это"], [[k, v or "пусто", ICON_DESC.get(k, (d or "").strip())] for k, v, _, d in icons], [30, 40, 106], code_cols=(0,))
H2("13.2 UiTheme.Skins — подложки окон и кнопок")
P("В `src/shared/UiTheme.lua`, таблица `Theme.Skins`: у каждой подложки поле `Image` (пусто = рисуется цветом). Для картинки задай `Slice = Rect.new(...)` (9-slice центр). После замены запусти `tools/ApplyUiSkins.lua` или пересобери UI (`BuildAllUI`).")
skins_keys = re.findall(r"^\s*(\w+)\s*=\s*\{\s*Image\s*=", open(os.path.join(REPO, "src/shared/UiTheme.lua"), encoding="utf-8").read(), re.M)
P("Ключи: " + ", ".join("`%s`" % k for k in skins_keys) + ".")
H2("13.3 Поля картинок в Config")
groups = {}
for l in cfgassets:
    k, v = l.split(" = ", 1)
    last = k.split(".")[-1]
    if not re.search(r"Image|IconId|Icon$|Texture", last) or last in ("IconText",):
        continue
    if not re.fullmatch(r"-?\d+", v) and not v.startswith("rbxasset"):
        continue
    parts = k.split(".")
    # группируем по пути без индекса/ключа элемента
    if len(parts) >= 4 and parts[-2] not in ("Icons", "Images", "Geodes", "Boulders", "Goblins", "QuickBar", "Shop", "UI", "Tutorial"):
        gkey = ".".join(parts[1:-2]) + ".<…>." + last
        item = parts[-2]
    else:
        gkey = ".".join(parts[1:])
        item = None
    groups.setdefault(gkey, []).append((item, v))
rows = []
for g in sorted(groups):
    vals = groups[g]
    if vals[0][0] is None:
        v = vals[0][1]
        rows.append([g, "1", "0 — не задано" if v == "0" else "задано"])
    else:
        zeros = [i for i, v in vals if v == "0"]
        filled = len(vals) - len(zeros)
        rows.append([g, str(len(vals)), ("задано %d; пусто: %s" % (filled, ", ".join(zeros))) if zeros else "все заданы"])
TABLE(["Поле (Config.)", "Кол.", "Состояние"], rows, [66, 10, 100], code_cols=(0,))

# ============================================================================
# 14. ИНТЕРФЕЙС
# ============================================================================
story.append(PageBreak())
H1("14. Интерфейс (StarterGui)")
UL([
    "Весь интерфейс собирает `tools/BuildAllUI.lua` (Studio → View → Command Bar, Edit Mode). Экраны появляются в `StarterGui` и дальше правятся руками.",
    "Пересобрать только часть: в начале файла `ONLY = { \"QuestUi\", \"GeodeUi\" }`. Не трогать существующие: `SKIP_EXISTING = true`.",
    "Если экран в StarterGui собран старой версией билдера — игра соберёт свежий кодом (warn в Output), но править его в Studio можно будет только после BuildAllUI.",
    "Шаблоны лежат в папках `Templates` внутри экранов и выключены (`Visible = false`) — это нормально, клиент включает клоны.",
    "Картинки подложек/иконок — раздел 13; шрифты и цвета — `src/shared/UiTheme.lua`. Подробно — `UI_V20_GUIDE.md`.",
])
reg = [l.strip().split("|", 1) for l in open(os.path.join(S, "uireg.txt"), encoding="utf-8") if "|" in l]
TABLE(["ScreenGui", "Что это"], reg, [50, 126], code_cols=(0,))
H2("14.1 Экран загрузки")
P("Создаёт `src/LoadingScreen.client.lua` (ReplicatedFirst) — картинки берёт из Config и предзагружает все `rbxassetid://` из конфига.")

# ============================================================================
# 15. ЧТО НОВОГО
# ============================================================================
story.append(PageBreak())
H1("15. Что нового (v20.9 – v20.45)")
H2("15.1 Банк: отдельная зона продажи")
TREE("""
Bank (Model)
├─ Building     (BasePart)  здание
├─ SellZone     (BasePart)  квадратная зона продажи (~18×18) — руда продаётся ТОЛЬКО здесь
│  └─ SellSign  (SurfaceGui, необяз.)  надпись «SELL ORE» на полу
├─ SellZoneEdge1..4  (декор, необяз.)  неоновая рамка
└─ MerchantSpot (BasePart, невидимый)  где встаёт торговец — справа ЗА краем зоны
""")
UL([
    "К торговцу можно подойти, не продавая руду: он стоит вне `SellZone`. Без `MerchantSpot` код сам ставит его справа за зоной.",
    "Курс руды «ORE PRICE x1.00» и таймер нового товара — только на табло над торговцем (`Config.Merchant.ShowBoard = true`). Плашка сверху экрана выключена (`ShowTicker = false`).",
])
H2("15.2 Надписи в мире — «таблички»")
TABLE(["Где", "Размер", "Как устроено"], [
    ["Над тотемами и трофеями", "7 стадов в ширину", "BillboardGui с размером в стадах (Scale) + TextScaled, шрифт денег; вплотную не раздувается (DistanceLowerLimit)."],
    ["Над плавильней (SmelterBoard)", "7 × 1.85 стадов", "То же, строки Title / Sub."],
    ["Над островами (IslandLabel)", "20 × 5 стадов", "То же; дальше 220 стадов перестаёт уменьшаться (DistanceUpperLimit) — остров видно издалека."],
    ["Над торговцем (MerchantBoard)", "14 × 5.2 стадов", "Три цветные строки: название, курс, таймер."],
], [40, 26, 110], code_cols=())
H2("15.3 Телефонная версия интерфейса")
UL([
    "Профиль устройства определяется один раз: Phone (сенсор без клавиатуры, короткая сторона ≤ 600), Tablet, Desktop. Проверка на ПК: `Config.UiLayout.ForceProfile = \"Phone\"`.",
    "Раскладка телефона — `Config.UiLayout.Overrides.Phone[\"Экран/Элемент\"] = { свойства }`; ключ `\"@Имя\"` ставит атрибут. Сейчас: квест — левый верх, статусы (погода/сейв-зона/баффы) — правый низ над прыжком, снаряжение — ряд над хотбаром, лента добычи — под деньгами.",
    "Атрибуты в Studio: `UiScale_Phone = 0.8` — своя база масштаба элемента на телефоне; `NoAutoFit = true` — не трогать.",
    "Масштабируются только верхние элементы без своего UIScale (свой — `PhoneFitScale`). Не вешайте на один объект два UIScale — Roblox их не складывает.",
])
H2("15.4 Новые кнопки и поведение")
TABLE(["Что", "Где", "Картинка / настройка"], [
    ["Кнопка магазина", "Топбар, первой (`StarterGui/TopbarDock/Row/ShopDockButton`)", "ImageLabel `Icon`: `UiTheme.Icons.Shop` или прямо в Studio (пусто — эмодзи)"],
    ["Кнопка рюкзака", "Последний слот хотбара (InventoryToggle)", "Открыть/закрыть инвентарь; на ПК ещё «~»"],
    ["Иконки кнопок", "Топбар, награды, ракета, перки", "Все — ImageLabel `Icon` (картинка из `UiTheme.Icons`, пусто — эмодзи-запаска)"],
    ["Поднять рабочий декор", "Скамейка, сундук, банка", "Вторая строка промпта, клавиша R"],
    ["Пункт QUESTS", "Меню-книга (CollectionMenu)", "`UiTheme.Icons.Quests`"],
    ["Навигация квеста", "Клик по квесту в трекере — вкл/выкл", "Шеврон у ног выключен: `Config.QuestMarker.ShowChevron`"],
    ["Подсказка предмета в руке", "Над хотбаром (GearUi/AimHint)", "Только текст, без подложки"],
    ["Плашка ХП валуна", "Над валуном", "Показывается только после первого удара"],
    ["Призрак сундука", "Установка сундука из руки", "Модель — `Assets/Chests/Chest_<Редкость>`"],
    ["Значки: галочка, крестик, стрелки, ромбы", "Везде в UI", "Рисуются фигурами (UiKit.Shape) — в шрифтах Roblox этих символов нет"],
], [36, 60, 80], code_cols=())
H2("15.5 Новый декор (v20.22)")
TABLE(["Ассет", "Название в игре", "Что делает"], [
    [cfg["Placeables"]["Decor"][k]["Asset"], cfg["Placeables"]["Decor"][k].get("DisplayName", k), {"Seat": "На неё можно сесть (SIT)", "Storage": "Хранилище руды на 10 ячеек (OPEN)", "Jar": "Витрина одной руды (PUT ORE / TAKE ORE)"}.get(cfg["Placeables"]["Decor"][k].get("Function"), "Просто украшение")]
    for k in ["Flowers1", "Flowers2", "Bush1", "Bush2", "Bench", "StorageChest", "OreJar"] if k in cfg["Placeables"]["Decor"]
], [40, 40, 96], code_cols=(0,))
P("Внешний вид и контракт моделей — разделы 8.3 и 8.5. Плавильни — 8.6.")
H2("15.6 Анимация шахты")
P("Растяжение/взрыв/«плевок» шахты проигрывает клиент (`client/MineScaleFX`), сервер только пишет атрибут `MineScaleAnim` на модель шахты. Своя модель `Mine_Tier<N>` работает как есть — все её BasePart масштабируются вокруг точки у земли под пивотом. Вернуть серверную анимацию: `Config.MineExpedition.ClientMineScale = false`.")

# ============================================================================
# 16. КАТАЛОГ: ТОЧНЫЕ ИМЕНА И ВНЕШНИЙ ВИД (v20.45)
# ============================================================================
story.append(PageBreak())
H1("16. Каталог предметов: точные имена и внешний вид")
P("Каждая строка — **точное имя** ассета в `ReplicatedStorage/Assets` (если не указан другой путь) и примерное описание, как он должен выглядеть. Нет ассета — игра рисует кодовый плейсхолдер, ничего не ломается.")

H2("16.1 Тотемы (12 штук: 4 типа × 3 тира)")
P("Тиры: **T1 = Early** (пещеры 1–5), **T2 = Mid** (6–10), **T3 = Late** (11–15). Чем выше тир, тем крупнее, богаче материал и сильнее свечение. Нет модели на тир — берётся общая `Totem_<Тип>`. Высота: T1 ~3.5, T2 ~4.5, T3 ~5.5 стада.")
TOTEM_LOOK = {
    "Fortune": ("удача", [
        "Деревянный столбик с вырезанным четырёхлистным клевером наверху, зелёная ленточка, пара листочков у основания.",
        "Замшелая каменная колонна, на ней нефритовый клевер в медной оправе, по колонне светятся зелёные руны.",
        "Золотой обелиск, наверху парит изумрудный клевер, вокруг кружат светящиеся листики, мягкое зелёное сияние.",
    ]),
    "Ember": ("доход с продажи", [
        "Каменная чаша-жаровня на короткой ножке, в ней тлеют угли и маленький огонёк.",
        "Чугунный тотем с прорезью-монетоприёмником, сверху уверенное пламя, на корпусе оранжевые прожилки.",
        "Золотой тотем с короной из огня, вокруг медленно кружат монеты, искры летят вверх.",
    ]),
    "Quake": ("валуны возвращаются быстрее", [
        "Пирамидка из трёх-четырёх сложенных камней (как туристический знак), трещинка на верхнем.",
        "Каменный столб с грубо вырезанным лицом голема, по граням светятся трещины, пара камешков парит рядом.",
        "Монолит из обсидиана с магмовыми трещинами (Neon), вокруг парят и вращаются обломки скалы.",
    ]),
    "Prism": ("шанс всех мутаций", [
        "Небольшой фиолетовый кристалл-осколок на деревянной подставке, слабое свечение.",
        "Пучок разноцветных кристаллов (фиолетовый, голубой, розовый) на каменном основании, искры.",
        "Большая радужная призма парит над постаментом и медленно вращается, от неё расходятся цветные лучи.",
    ]),
}
rows = []
for k in ["Fortune", "Ember", "Quake", "Prism"]:
    if k not in tt:
        continue
    what, looks = TOTEM_LOOK[k]
    vals = tt[k].get("Values") or {}
    vlist = [vals.get(str(i)) if isinstance(vals, dict) else None for i in (1, 2, 3)]
    for i in (1, 2, 3):
        v = vlist[i - 1]
        eff = ("%s: %s" % (what, ("×%.1f" % (1 + v)) if k == "Prism" else ("%d%%" % round(v * 100)))) if isinstance(v, (int, float)) else what
        rows.append(["Totem_%s_T%d" % (k, i), "%s (%s)" % (tt[k].get("DisplayName", k), ["Early", "Mid", "Late"][i - 1]), eff, looks[i - 1]])
    rows.append(["Totem_%s" % k, "общая", "—", "Запасная модель на все тиры (код подкрасит свет под тир)."])
TABLE(["Имя ассета", "В игре", "Эффект", "Внешний вид"], rows, [30, 30, 30, 86], code_cols=(0,))

H2("16.2 Святилища престижа (10 штук)")
SHRINE_LOOK = {
    "Frost": "Ледяная арка из голубых кристаллов льда, изморозь у основания, падают снежинки.",
    "Toxic": "Ржавый котёл на каменном постаменте, кипит ядовито-зелёная жижа, пузыри и зелёный пар.",
    "Molten": "Вулканический алтарь из базальта, в чаше плещется лава, оранжевые искры.",
    "Storm": "Металлический шпиль-громоотвод на камне, между рогами бегают голубые молнии.",
    "Void": "Чёрный обелиск с фиолетовой дырой-порталом внутри, частицы затягиваются внутрь.",
    "Golden": "Золотой алтарь с короной на подушке, блеск и золотые искры.",
    "Prismatic": "Круг из радужных кристаллов вокруг вращающейся призмы, радуга на земле.",
    "Celestial": "Мраморная беседка-купол, над ней кружат маленькие звёзды и планета.",
    "Fortune": "Идол-лепрекон из нефрита на горке монет, клевер в руках, зелёное сияние.",
    "Midas": "Золотая статуя руки, держащей монету, пьедестал с монетами, всё сверкает.",
}
sorder = cfg["Prestige"]["Shrines"]["Order"]
sorder = [sorder[k] for k in sorted(sorder, key=lambda x: int(x))] if isinstance(sorder, dict) else sorder
srows = []
for sid in sorder:
    d = shr.get(sid, {})
    eff = ("каждая 3-я руда: мутация %s" % d.get("Mutation")) if d.get("Kind") == "Mutation" else ("удача +%d%%" % round(d.get("Value", 0) * 100) if d.get("Kind") == "Luck" else "доход +%d%%" % round(d.get("Value", 0) * 100))
    srows.append([d.get("Asset", ""), d.get("DisplayName", sid), "%s · %s очк." % (eff, d.get("Cost", "")), SHRINE_LOOK.get(sid, "")])
TABLE(["Имя ассета", "В игре", "Эффект · цена", "Внешний вид"], srows, [32, 28, 40, 76], code_cols=(0,))

H2("16.3 Гоблины")
GOB_LOOK = {
    "Warrior": ("Goblin Warrior", "Невысокий зелёный гоблин в кожаной броне, деревянная дубина с гвоздями, злая ухмылка, большие уши."),
    "Thief": ("Goblin Thief", "Худой и сутулый, тёмный капюшон и маска, кинжал в руке, за спиной мешок с добычей, жёлтые глаза."),
    "Berserker": ("Goblin Barbarian", "Крупный и мускулистый (×1.1), рогатый шлем, двуручный топор, меховая накидка, боевая раскраска."),
    "King": ("Goblin King", "Самый крупный (×1.3), фиолетовая мантия, кривая корона, скипетр с черепом, золотые украшения."),
    "Golden": ("Golden Goblin King", "Как король, но весь золотой: золотая кожа и доспех, сияющая корона, блеск и искры."),
}
TABLE(["Имя ассета", "В игре", "Внешний вид"], [
    ["Goblin_%s (или _1, _2, _3)" % t, GOB_LOOK.get(t, (t, ""))[0], GOB_LOOK.get(t, (t, ""))[1]] for t in gt
], [48, 32, 96], code_cols=(0,))
waves = cfg.get("GoblinRaid", {}).get("Waves", {})
wlist = [waves[k] for k in sorted(waves, key=lambda x: int(x))] if isinstance(waves, dict) else waves
if wlist:
    wrows = []
    for w in wlist:
        units = w.get("Units", {})
        ul = [units[k] for k in sorted(units, key=lambda x: int(x))] if isinstance(units, dict) else units
        wrows.append([w.get("Title", ""), ", ".join("%s × %s" % (u.get("2", ""), u.get("1", "")) for u in ul if isinstance(u, dict)), "пещеры %s–%s" % (w.get("MinCave", ""), w.get("MaxCave", ""))])
    P("Волны лагеря (только эти модели):")
    TABLE(["Волна", "Состав", "Когда"], wrows, [44, 90, 42], code_cols=())

H2("16.4 Сундуки и динамит")
CHEST_LOOK = {
    "Common": "Простой деревянный сундук ~2.5 стада, железные уголки, серый замок.",
    "Rare": "Сундук с синими железными полосами, синий камень на замке, лёгкое голубое свечение из щели.",
    "Epic": "Фиолетовый сундук с золотой окантовкой и крупными самоцветами, фиолетовые искры.",
    "Legendary": "Золотой резной сундук, крышка с короной, яркий золотой свет из щели, блеск.",
}
TABLE(["Имя ассета", "В игре", "Внешний вид"], [
    ["Assets/Chests/" + cfg["Chests"]["Types"][k]["ModelName"], cfg["Chests"]["Types"][k].get("DisplayName", k), CHEST_LOOK.get(k, "")]
    for k in ordered(cfg["Chests"]["Order"]) if k in cfg["Chests"]["Types"]
] + [
    ["Chest", "Сундук гоблина", "Маленький потрёпанный пиратский сундучок, который несёт/роняет гоблин."],
    ["LootBox", "Коробка награды", "Картонная/деревянная коробка с бантом, вылетает для наград без своей модели (скины)."],
] + [
    [k, v.get("DisplayName", k), {"Dynamite": "Одна красная шашка с запалом, искрит.", "Dynamite_Medium": "Три шашки, перевязанные верёвкой, общий запал.", "Dynamite_Mega": "Большой бочонок TNT с надписью, толстый запал, чёрные обручи."}.get(k, "")]
    for k, v in cfg["Dynamite"]["Types"].items()
], [52, 30, 94], code_cols=(0,))

H2("16.5 Трофеи, валуны, острова, карточки")
RELIC_LOOK = {
    "CrownedMoleSkull": "Череп крота в маленькой короне на бархатной подушке.",
    "DragonEggFossil": "Окаменевшее яйцо дракона с трещинами, из которых пробивается огонь.",
    "GoldenPickaxeTrophy": "Золотая кирка на деревянной подставке с табличкой.",
    "HeartOfTheMountain": "Пульсирующий красный кристалл-сердце, окружённый камнем, яркое свечение.",
}
TABLE(["Имя ассета", "В игре", "Внешний вид"], [
    [v["Asset"], "%s (%s)" % (v.get("DisplayName", k), v.get("Rarity", "")), RELIC_LOOK.get(k, "")] for k, v in cfg["Relics"]["Types"].items()
] + [
    ["Boulder_Tier1 … Boulder_Tier%d" % nb, "Валуны", "Круглый камень ~5 стадов; с тиром крупнее и богаче: серый → мшистый → с прожилками руды → кристаллы → светящиеся жилы."],
    ["Island_Income, Island_Smelter, Island_Anvil", "Острова", "Парящие острова с травой и камнем снизу; на каждом деталь-маркер `StationMarker`, где встаёт постройка."],
    ["Assets/MineRarityCards/Common … Mythic", "Карточки мини-игры", "Плоская карточка-плитка цвета редкости с рамкой и значком руды (полоски за ней рисует код)."],
], [52, 34, 90], code_cols=(0,))

H2("16.6 Эффекты, которые можно заменить")
TABLE(["Имя / путь", "Где", "Внешний вид"], [
    ["ReplicatedStorage/stunvfx (Attachment)", "Над головой оглушённого гоблина **и игрока в рагдолле**", "Кружащие жёлтые звёздочки/птички. Нет — у игрока встроенные звёздочки."],
    ["Reveal_<Редкость>, Reveal_Mutation, RevealVFX", "Выпала редкая руда", "Вспышка цвета редкости, искры вверх, кольцо по земле."],
    ["Reveal_Chest_<Редкость>", "Открытие сундука", "Как Reveal_*, золотые искры."],
    ["BoulderBreakVFX, BoulderBreakVFX_<тир>, BoulderBreakVFX_Golden", "Разбит валун", "Каменные осколки и пыль, у золотого — золотые искры."],
    ["PrestigeVFX", "Престиж", "Золотая аура и корона над головой."],
], [60, 46, 70], code_cols=())
UL([
    "Трейл полёта «KICKED OUT», табличку лагеря гоблинов, метки баз с ником и полоски за карточками редкости код строит сам — ассет не нужен.",
    "Все остальные ассеты (шахта, тележка, кирки, NPC, погода, звуки, картинки) — в разделах 2–13.",
])

# ============================================================================
# 17. ЧЕК-ЛИСТ
# ============================================================================
H1("17. Финальный чек-лист")
UL([
    "Ассет в `ReplicatedStorage/Assets` (или в обязательной папке: `Chests`, `MineRarityCards`); имя побуквенно совпадает.",
    "Класс совпадает с таблицей; у `Model` назначен `PrimaryPart`; `Root`/`SkinRoot`/`Handle` — это `BasePart`.",
    "Движущиеся модели сварены и не заанкорены; маркеры невидимы и без коллизий.",
    "Звуки/картинки/анимации вписаны в `Config.lua`/`UiTheme.lua` и доступны experience.",
    "Билдеры больше не будут запускаться поверх готовых ассетов (или сделан дубликат).",
    "Свежий сервер: Output без `warn` про ассеты; проверены шахта, тележка, продажа, валуны всех тиров, гоблины, жеоды, сундуки, динамит, тотемы/трофеи, погода, скины, телефон.",
    "Новый декор: скамейка садит, сундук-хранилище открывает окно и хранит руду после перезахода, банка крутит руду и пишет редкость; все четыре уровня плавильни.",
    "Place сохранён/опубликован.",
])


def on_page(canv, doc):
    canv.saveState()
    canv.setFont("Sans", 7.5)
    canv.setFillColor(MUTED)
    if doc.page > 1:
        canv.drawString(17 * mm, 10 * mm, "GAMREADY v20 — гайд по плейсхолдерам")
        canv.drawRightString(193 * mm, 10 * mm, str(doc.page))
    canv.restoreState()


doc = Doc(OUT, pagesize=A4, leftMargin=17 * mm, rightMargin=17 * mm, topMargin=16 * mm, bottomMargin=16 * mm,
          title="Плейсхолдеры: полный гайд (GAMREADY v20)", author="GAMREADY")
frame = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="f")
doc.addPageTemplates([PageTemplate(id="p", frames=[frame], onPage=on_page)])
doc.multiBuild(story)
print("ok", OUT)
