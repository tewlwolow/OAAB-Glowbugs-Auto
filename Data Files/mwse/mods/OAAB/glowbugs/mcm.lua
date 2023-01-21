local configPath = "OAAB:Glowbugs"
local config = require("OAAB.glowbugs.config")
local defaults = require("OAAB.glowbugs.defaults")

local function registerVariable(id)
    return mwse.mcm.createTableVariable{
        id = id,
        table = config
    }
end

local template = mwse.mcm.createTemplate{
    name="OAAB:Glowbugs",
    headerImagePath="\\Textures\\OAAB\\mcm\\glowbugs\\glowbugs_logo.dds"
}

---
local mainPage = template:createPage{label="Main Settings"}

mainPage:createCategory{
	label = "OAAB:Glowbugs by OAAB team.\nThis MWSE script controls spawn settings.\n\nSettings:",
}

mainPage:createSlider {
    label = string.format("Bug density (number of swarms) per cell.\nDefault - %s.\nBug density", defaults.bugDensity),
    min = 1,
    max = 20,
    step = 1,
    jump = 10,
    variable = registerVariable("bugDensity")
}

---
template:createExclusionsPage{
	label = "Green Glowbugs Regions",
	description = "Select which regions the green glowbugs will spawn in. Move regions to the left table to enable.",
	toggleText = "Toggle",
	leftListLabel = "Enabled regions",
	rightListLabel = "All regions",
	showAllBlocked = false,
	variable = registerVariable("greenBugsRegions"),
	filters = {

		{
			label = "Regions",
			callback = (
				function()
					local regionIDs = {}
					for region in tes3.iterate(tes3.dataHandler.nonDynamicData.regions) do
						table.insert(regionIDs, region.id)
					end
					return regionIDs
				end
			)
		},

	}
}

---
template:createExclusionsPage{
	label = "Blue Glowbugs Regions",
	description = "Select which regions the blue glowbugs will spawn in. Move regions to the left table to enable.",
	toggleText = "Toggle",
	leftListLabel = "Enabled regions",
	rightListLabel = "All regions",
	showAllBlocked = false,
	variable = registerVariable("blueBugsRegions"),
	filters = {

		{
			label = "Regions",
			callback = (
				function()
					local regionIDs = {}
					for region in tes3.iterate(tes3.dataHandler.nonDynamicData.regions) do
						table.insert(regionIDs, region.id)
					end
					return regionIDs
				end
			)
		},

	}
}

---
template:createExclusionsPage{
	label = "Red Glowbugs Regions",
	description = "Select which regions the red glowbugs will spawn in. Move regions to the left table to enable.",
	toggleText = "Toggle",
	leftListLabel = "Enabled regions",
	rightListLabel = "All regions",
	showAllBlocked = false,
	variable = registerVariable("redBugsRegion"),
	filters = {

		{
			label = "Regions",
			callback = (
				function()
					local regionIDs = {}
					for region in tes3.iterate(tes3.dataHandler.nonDynamicData.regions) do
						table.insert(regionIDs, region.id)
					end
					return regionIDs
				end
			)
		},

	}
}


template:saveOnClose(configPath, config)
mwse.mcm.register(template)
