local config = require("OAAB.glowbugs.config")
local util = require("OAAB.glowbugs.util")

local activeBugs, bugCells = {}, {}

local bugs, WtC

local allowedStrings = {
    "flora",
    "ab_f_"
}

local deniedStrings = {
    "kelp",
    "lilypad"
}

--- Detect when bug references are created, and start tracking them.
---
local function refCreated(e)
    if e.reference.sceneNode:hasStringDataWith("HasBugsRoot") then
        activeBugs[e.reference] = true
    end
end

--- Detect when bug references are deleted, and stop tracking them.
---
local function refDeleted(e)
    activeBugs[e.object] = nil
end

--- Toggle visibility for all currently active bugs references.
---
local function toggleBugsVisibility(state)
    local index = state and 1 or 0
    for ref in pairs(activeBugs) do
        if ref.sceneNode then
            local root = ref.sceneNode:getObjectByName("BugsRoot")
            if root.switchIndex ~= index then
                root.switchIndex = index
            end
        end
    end
end

--- Get the average Z pos in cell and offset it slightly up
---
local function getCellZPos(cell)
    local average = 0
	local denom = 0
    local offset = 50

	for stat in cell:iterateReferences() do
		average = average + stat.position.z
		denom = denom + 1
	end

	if average == 0 or denom == 0 then
		return offset
	else
		return (average / denom) + offset
	end
end

--- Decimate the table to hold random items clamped by max density
---
local function getTrimmedPositions(positions)
    local trimmedPositions = {}
    math.randomseed(os.time())
    local getRandomPos = util.nonRepeatTableRNG(positions)
    for i = 1, math.min(config.bugDensity, #positions) do
        local val = getRandomPos()
        table.insert(trimmedPositions, val)
    end
    return trimmedPositions
end

local function isIdAllowed(id)
    return string.multifind(id, allowedStrings)
end

local function isIdDenied(id)
    return string.multifind(id, deniedStrings)
end

local function iterObjects(positions, objectType, cell)
    for ref in cell:iterateReferences(objectType) do
        local id = ref.object.id:lower()
        local pos = ref.position:copy()
        if isIdAllowed(id) and not isIdDenied(id) and not table.find(positions, pos) then
            table.insert(positions, pos)
        end
	end
end

--- Scan cells for flora statics and containers and get a list of positions
---
local function getBugPositions(cell)
    local positions = {}
    iterObjects(positions, tes3.objectType.static, cell)
    iterObjects(positions, tes3.objectType.container, cell)
    return getTrimmedPositions(positions)
end

--- Create glowbugs refs
---
local function spawnBugs(availableBugs, cell)
    local positions = getBugPositions(cell)
    if table.empty(positions) then return end

    math.randomseed(os.time())
    local getRandomPos = util.nonRepeatTableRNG(positions)
    local z = getCellZPos(cell)
    local maxDensity = config.bugDensity / #availableBugs

    local density = 0
    local pos = getRandomPos()
    for _, bug in ipairs(availableBugs) do
        while density < maxDensity do
            tes3.createReference{
                object = bug,
                cell = cell,
                orientation = tes3vector3.new(),
                position = {pos.x, pos.y, z}
            }
            pos = getRandomPos()
            density = density + 1
        end
        density = 0
    end

    toggleBugsVisibility(true)
end

--- See if we are in a valid region
---
local function getAvailableBugs(regionID)
    local availableBugs = {}
    for _, glowbugType in pairs(bugs) do
        if glowbugType.regions[regionID] then
            table.insert(availableBugs, glowbugType.object)
        end
    end
    return availableBugs
end

local function cleanUpInactiveBugs(cell)
    for ref in cell:iterateReferences(tes3.objectType.container) do
        if ref.sceneNode then
            local root = ref.sceneNode:getObjectByName("BugsRoot")
            if root and root.switchIndex == false then
                ref:delete()
            end
        end
    end
end

--- Global manager for active bugs. Runs once per hour.
---
local bugsVisible = {}
local function conditionCheck()
    local cell = tes3.player.cell

    local isBugsVisible = true
    local availableBugs = {}

    if not (cell.isOrBehavesAsExterior) then
        -- global variable used for dialogue filtering
        tes3.setGlobal("AB_GlowbugsVisible", 0)
    else
        -- exterior cells require valid hours/weathers
        local wc = tes3.worldController

        local hour = wc.hour.value
        local day = wc.daysPassed.value
        local weather = wc.weatherController.currentWeather.index
        local regionID = tes3.getPlayerCell().region.id

        -- percentage chance to spawn on any given day
        -- is determined by the AB_GlowbugsChance global
        -- we only want to calculate this once per day!
        if bugsVisible[day] == nil then
            local roll = math.random(100)
            local glob = tes3.getGlobal("AB_GlowbugsChance")
            -- bugsVisible[day] = roll <= glob
            bugsVisible[day] = true
        end

        local isActiveHours = (hour <= WtC.sunriseHour + 1) or (hour >= WtC.sunsetHour + 1)
        local isValidWeather = weather < tes3.weather.rain
        local isValidDay = bugsVisible[day]
        local isWilderness = not cell.name
        availableBugs = getAvailableBugs(regionID)

        isBugsVisible = isActiveHours and isValidWeather and isValidDay and isWilderness and not (table.empty(availableBugs))

        -- global variable used for dialogue filtering
        tes3.setGlobal("AB_GlowbugsVisible", isBugsVisible and 1 or 0)
    end

    if not isBugsVisible then
        bugCells[cell] = nil
        toggleBugsVisibility(isBugsVisible)
        cleanUpInactiveBugs(cell)
    else
        if not (bugCells[cell]) then
            bugCells[cell] = true
            spawnBugs(availableBugs, cell)
        end
    end
end


--- Harvest a single bug. Called on "activate" event.
---
local function harvestBugs(e)
    if not activeBugs[e.target] then
        return
    end

    local rayHit = tes3.rayTest{
        position = tes3.getPlayerEyePosition(),
        direction = tes3.getPlayerEyeVector(),
        root = e.target.sceneNode,
    }
    if not (rayHit and rayHit.object) then
        return
    end

    -- hide the bug
    rayHit.object.parent.parent.parent.appCulled = true

    -- add the loot
    for _, stack in pairs(e.target.baseObject.inventory) do
        local item = stack.object
        if item.canCarry ~= false then
            if item.objectType == tes3.objectType.leveledItem then
                item = item:pickFrom()
            end
            if item then
                tes3.addItem{reference=e.activator, item=item}
                tes3.messageBox("You harvested %s %s.", stack.count, item.name)
            else
                tes3.playSound{reference=e.activator, sound="scribright"}
                tes3.messageBox("You failed to harvest anything of value.")
            end
        end
    end

    return false
end


--- Update bugs once per hour.
---
local function bugsTimer()
    timer.start{
        type = timer.game,
        iterations = -1,
        duration = 1,
        callback = function()
            timer.delayOneFrame(conditionCheck)
        end
    }
    conditionCheck()
end


event.register("initialized", function()
    if tes3.isModActive("OAAB_Data.esm") then
        event.register("referenceSceneNodeCreated", refCreated)
        event.register("objectInvalidated", refDeleted)
        event.register("cellChanged", conditionCheck)
        event.register("weatherTransitionFinished", conditionCheck)
        event.register("activate", harvestBugs, {priority = 600})
        event.register("loaded", bugsTimer)

        WtC = tes3.worldController.weatherController

        bugs = {
            green = {
                object = tes3.getObject("AB_r_GlowbugsLargeGreen"),
                regions = config.greenBugsRegions
            },
            blue = {
                object = tes3.getObject("AB_r_GlowbugsLargeBlue"),
                regions = config.blueBugsRegions
            },
            red = {
                object = tes3.getObject("AB_r_GlowbugsLargeRed"),
                regions = config.redBugsRegions
            }
        }

    end
end)

-- Registers MCM menu --
event.register("modConfigReady", function()
    dofile("Data Files\\MWSE\\mods\\OAAB\\glowbugs\\mcm.lua")
end)