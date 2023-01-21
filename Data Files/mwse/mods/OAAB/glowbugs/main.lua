-- OAAB Glowbugs MWSE spawn manager
-->>>---------------------------------------------------------------------------------------------<<<--


-->>>---------------------------------------------------------------------------------------------<<<--
-- Imports

local config = require("OAAB.glowbugs.config")
local util = require("OAAB.glowbugs.util")


-->>>---------------------------------------------------------------------------------------------<<<--
-- Variables

local activeBugs, bugCells, bugsVisible = {}, {}, {}

local glowbugs, WtC


-->>>---------------------------------------------------------------------------------------------<<<--
-- Constants

local DISTANCE_OFFSET = 2048
local ZPOS_OFFSET = 50

local ALLOWED_STRINGS = {
    "flora",
    "ab_f_"
}

local DENIED_STRINGS = {
    "kelp",
    "lilypad"
}


-->>>---------------------------------------------------------------------------------------------<<<--
-- Functions


--- Detect when bug references are created, and start tracking them.
---@param e referenceSceneNodeCreatedEventData
---@return nil
local function refCreated(e)
    local ref = e.reference
    if ref.sceneNode:hasStringDataWith("HasBugsRoot") then
        activeBugs[ref] = true
    end
end


--- Detect when bug references are deleted, and stop tracking them.
---@param e objectInvalidatedEventData
---@return nil
local function refDeleted(e)
    activeBugs[e.object] = nil
end


--- Toggle visibility for all currently active bugs references.
---@param state boolean|number
---@return nil
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


--- Get the average Z pos in a cell and offset it slightly up.
---@param cell tes3cell
---@return number
local function getCellZPos(cell)
    local average = 0
	local denom = 0

	for stat in cell:iterateReferences() do
		average = average + stat.position.z
		denom = denom + 1
	end

	if average == 0 or denom == 0 then
		return ZPOS_OFFSET
	else
		return (average / denom) + ZPOS_OFFSET
	end
end


--- Decimate the table to hold random items clamped by max density.
---@param t table
---@return table
local function getTrimmedPositions(t)
    local trimmedPositions = {}
    local getRandomPos = util.nonRepeatTableRNG(t)
    for i = 1, math.min(config.bugDensity, #t) do
        local val = getRandomPos()
        table.insert(trimmedPositions, val)
    end
    return trimmedPositions
end


--- Check if object id matches our whitelist.
---@param id string
---@return boolean|nil
local function isIdAllowed(id)
    return string.multifind(id, ALLOWED_STRINGS)
end


--- Check if object id matches our blacklist.
---@param id string
---@return boolean|nil
local function isIdDenied(id)
    return string.multifind(id, DENIED_STRINGS)
end


--- Iterate over objects of specific type in a cell and insert them into the table.
---@param t table
---@param objectType number
---@param cell tes3cell
---@param playerPos tes3vector3
---@return nil
local function iterObjects(t, objectType, cell, playerPos)
    for ref in cell:iterateReferences(objectType) do
        local id = ref.object.id:lower()
        local pos = ref.position:copy()
        if isIdAllowed(id) and not isIdDenied(id) and not table.find(t, pos) and playerPos:distance(pos) > DISTANCE_OFFSET then
            table.insert(t, pos)
        end
	end
end


--- Scan cells for flora statics and containers and get a list of their positions.
---@param cell tes3cell
---@return table
local function getBugPositions(cell)
    local positions = {}
    local playerPos = tes3.player.position:copy()
    iterObjects(positions, tes3.objectType.static, cell, playerPos)
    iterObjects(positions, tes3.objectType.container, cell, playerPos)
    return getTrimmedPositions(positions)
end


--- Create references for available glowbugs per cell.
---@param availableBugs table
---@param cell tes3cell
---@return nil
local function spawnBugs(availableBugs, cell)
    local positions = getBugPositions(cell)
    if table.empty(positions) then return end

    local getRandomPos = util.nonRepeatTableRNG(positions)
    local z = getCellZPos(cell)
    local maxDensity = math.floor(config.bugDensity / #availableBugs)

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


--- Return a table with available glowbug types given the region id.
---@param regionID string
---@return table
local function getAvailableBugs(regionID)
    local availableBugs = {}
    for _, glowbugType in pairs(glowbugs) do
        if glowbugType.regions[regionID] then
            table.insert(availableBugs, glowbugType.object)
        end
    end
    return availableBugs
end


--- Iterate over references in a cell and remove any glowbugs that have been switched off.
---@param cell tes3cell
---@return nil
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


--- Condition check for active bugs. Runs once per hour.
---@return nil
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
        if not regionID then return end

        -- percentage chance to spawn on any given day
        -- we only want to calculate this once per day!
        if bugsVisible[day] == nil then
            local roll = math.random(100)
            bugsVisible[day] = roll <= config.spawnChance
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
---@param e activateEventData
---@return boolean|nil
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


--- Start a time to update bugs once per hour.
---@return nil
local function startBugsTimer()
    timer.start{
        type = timer.game,
        iterations = -1,
        duration = 1,
        callback = function()
            timer.delayOneFrame(conditionCheck)
        end
    }
end

-->>>---------------------------------------------------------------------------------------------<<<--
-- Events

--- Register our events
event.register("initialized", function()
    if tes3.isModActive("OAAB_Data.esm") then
        event.register("referenceSceneNodeCreated", refCreated)
        event.register("objectInvalidated", refDeleted)
        event.register("cellChanged", conditionCheck)
        event.register("weatherTransitionFinished", conditionCheck)
        event.register("activate", harvestBugs, {priority = 600})
        event.register("loaded", startBugsTimer)

        WtC = tes3.worldController.weatherController

        glowbugs = {
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


--- Register MCM menu
event.register("modConfigReady", function()
    dofile("Data Files\\MWSE\\mods\\OAAB\\glowbugs\\mcm.lua")
end)
