local API_BASE = "http://127.0.0.1:9090"

local activeProxy = ""
local finalMode = "direct"
local nodes = {}
local delays = {}
local hoveredNode = nil
local testing = false
local isOpen = false
local fetchGen = 0

local function cardFill()
  local op = noctalia.getSetting("shell.panel.card_opacity")
  if type(op) ~= "number" then
    op = 0.30
  end
  return "surface_container/" .. tostring(op)
end

local function render()
  if not isOpen then
    return
  end

  local fill = cardFill()
  local nodeRows = {}

  for _, name in ipairs(nodes) do
    local act = (name == activeProxy)
    local hov = (hoveredNode == name)
    local rowFill = act and "primary" or (hov and "hover/0.50" or fill)
    local fgColor = act and "on_primary" or (hov and "on_hover" or "on_surface")
    local delayColor = act and "on_primary" or "tertiary"
    local delay = delays[name]
    local delayText = (delay and delay > 0) and (tostring(delay) .. " ms") or "--"
    local nodeName = name

    table.insert(
      nodeRows,
      ui.row({
        key = "node:" .. nodeName,
        align = "center",
        gap = 8,
        paddingV = 8,
        paddingH = 12,
        minHeight = 32,
        fill = rowFill,
        radius = 999,
        onClick = function()
          selectProxy(nodeName)
        end,
        onHover = function(state)
          local entered = (state == true or state == "true")
          if entered then
            if hoveredNode ~= nodeName then
              hoveredNode = nodeName
              render()
            end
          elseif hoveredNode == nodeName then
            hoveredNode = nil
            render()
          end
        end,
      }, {
        ui.glyph({
          name = act and "shield-check" or "shield-lock",
          size = 16,
          color = fgColor,
        }),
        ui.label({
          text = nodeName,
          fontSize = 14,
          fontWeight = act and "bold" or "normal",
          color = fgColor,
          flexGrow = 1,
          maxLines = 1,
        }),
        ui.label({
          text = delayText,
          fontSize = 13,
          fontWeight = "medium",
          color = delayColor,
        }),
      })
    )
  end

  local statusCard = ui.column({
    align = "stretch",
    gap = 8,
    padding = 14,
    fill = fill,
    radius = 12,
  }, {
    ui.row({ align = "center", gap = 8, minHeight = 32 }, {
      ui.glyph({ name = "shield-check", size = 16, color = "primary" }),
      ui.label({ text = "Активный узел:", fontSize = 14, color = "on_surface_variant" }),
      ui.label({
        text = activeProxy ~= "" and activeProxy or "--",
        fontSize = 14,
        fontWeight = "bold",
        color = "primary",
        flexGrow = 1,
        maxLines = 1,
      }),
    }),
    ui.row({ align = "center", gap = 8, minHeight = 32 }, {
      ui.column({ align = "stretch", flexGrow = 1 }, {
        ui.label({
          text = "Весь остальной трафик",
          fontSize = 14,
          fontWeight = "bold",
          color = "on_surface",
        }),
        ui.label({
          text = finalMode == "proxy" and "Режим: proxy (через VPN)" or "Режим: direct (напрямую)",
          fontSize = 13,
          color = "on_surface_variant",
        }),
      }),
      ui.toggle({
        checked = (finalMode == "proxy"),
        onChange = function(val)
          setFinalRoute(val == true or val == "true")
        end,
      }),
    }),
  })

  local nodesCard = ui.column({
    align = "stretch",
    gap = 8,
    padding = 14,
    fill = fill,
    radius = 12,
  }, {
    ui.column({ align = "stretch", gap = 8 }, nodeRows),
    ui.row({ align = "center", justify = "end" }, {
      ui.button({
        text = testing and "Тестирование..." or "Пинг",
        variant = "default",
        controlSize = "sm",
        enabled = not testing and #nodes > 0,
        onClick = function()
          testAllLatencies()
        end,
      }),
    }),
  })

  panel.render(ui.column({ align = "stretch", gap = 12, flexGrow = 1 }, {
    ui.row({ align = "center", justify = "space_between" }, {
      ui.label({ text = "VPN", fontSize = 16, fontWeight = "bold", color = "primary" }),
      ui.button({
        glyph = "x",
        glyphSize = 14,
        variant = "ghost",
        controlSize = "sm",
        onClick = function()
          panel.close()
        end,
      }),
    }),
    ui.scroll({ flexGrow = 1, gap = 12 }, {
      statusCard,
      nodesCard,
    }),
  }))
end

function fetchProxies()
  fetchGen = fetchGen + 1
  local gen = fetchGen

  noctalia.http({ url = API_BASE .. "/proxies/proxy", method = "GET" }, function(res)
    if gen ~= fetchGen or not res or not res.ok or not res.body then
      return
    end
    local data = noctalia.json.decode(res.body)
    if type(data) == "table" then
      activeProxy = type(data.now) == "string" and data.now or ""
      local list = {}
      if type(data.all) == "table" then
        for _, item in ipairs(data.all) do
          if type(item) == "string" then
            table.insert(list, item)
          end
        end
      end
      nodes = list
      render()
    end
  end)

  noctalia.http({ url = API_BASE .. "/proxies/final-toggle", method = "GET" }, function(res)
    if gen ~= fetchGen or not res or not res.ok or not res.body then
      return
    end
    local data = noctalia.json.decode(res.body)
    if type(data) == "table" and type(data.now) == "string" then
      finalMode = data.now
      render()
    end
  end)
end

function selectProxy(name)
  local body = noctalia.json.encode({ name = name })
  if not body then
    return
  end
  noctalia.http({
    url = API_BASE .. "/proxies/proxy",
    method = "PUT",
    headers = { "Content-Type: application/json" },
    body = body,
  }, function(res)
    if res and res.ok then
      activeProxy = name
      render()
    end
  end)
end

function setFinalRoute(toProxy)
  local target = toProxy and "proxy" or "direct"
  local body = noctalia.json.encode({ name = target })
  if not body then
    return
  end
  noctalia.http({
    url = API_BASE .. "/proxies/final-toggle",
    method = "PUT",
    headers = { "Content-Type: application/json" },
    body = body,
  }, function(res)
    if res and res.ok then
      finalMode = target
      render()
    end
  end)
end

function testAllLatencies()
  if testing or #nodes == 0 then
    return
  end
  testing = true
  render()

  local pending = #nodes
  for _, name in ipairs(nodes) do
    local nodeName = name
    local encoded = noctalia.string.urlEncode(nodeName)
    local url = API_BASE .. "/proxies/" .. encoded .. "/delay?timeout=2500&url=http://www.gstatic.com/generate_204"
    noctalia.http({ url = url, method = "GET" }, function(res)
      local d = -1
      if res and res.ok and res.body then
        local parsed = noctalia.json.decode(res.body)
        if type(parsed) == "table" and type(parsed.delay) == "number" then
          d = math.floor(parsed.delay)
        end
      end
      delays[nodeName] = d
      pending = pending - 1
      if pending <= 0 then
        testing = false
      end
      render()
    end)
  end
end

function onOpen()
  isOpen = true
  hoveredNode = nil
  render()
  fetchProxies()
end

function onClose()
  isOpen = false
  hoveredNode = nil
end

function onConfigChanged()
  render()
end
