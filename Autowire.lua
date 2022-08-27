--[[
local SpaceIn3D = {}

local Port = {
	--Position
	--Size
	--FaceNormal
}

local Destination = Vector3.new(x,y,z) --PortPosition + (FaceNormal * Size)
local Source = Vector3.new(x,y,z)

local ManhattanDistance = Vector3.new(x,y,z) -- Sum (x2-x1)

local Size = Vector3.new(x,y,z)
-- Initialize Array
local Normalized = Vector3.new(1/) -- 1/Size
local Size2 = Vector3.new(x,y,z) -- ManhattanDistance * Normalized * 10

-- Approach 2
-- Generate blocks until destination
local Port = {
	--Position
	--Size
	--FaceNormal
}

local Destination = Vector3.new(x,y,z) --PortPosition + (FaceNormal * Size)
local Source = Vector3.new(x,y,z)

local Blocks = {}

local Block = {
	--Position
	--Index
	--Size
	--FaceNormals
	["Block"] = {}
}
--]]
local function getMinAndMax(mintable)
	local XTable, YTable, ZTable = {}, {}, {}
	
	for k,v in pairs(mintable) do
		XTable[#XTable+1] = v.X
		YTable[#YTable+1] = v.Y
		ZTable[#YTable+1] = v.Z
	end
	
	table.sort(XTable)
	table.sort(YTable)
	table.sort(ZTable)
	
	local minVec = Vector3.new(XTable[#XTable], YTable[#YTable], ZTable[#ZTable])
	local maxVec =  Vector3.new(XTable[1], YTable[1], ZTable[1])
	
	return minVec, maxVec
end

--Approach 3
-- Generate ports then put on grids (snapped).

local SourceFaceNormal = Vector3.new(x,y,z)

local DestinationPorts = {}  --Vec3
local SourcePorts = {} -- Vec3

local Port = {
	["PortPosition"] = Vector3.new(0,0,0),
	["DestinationPorts"] = Vector3.new(0,0,0),
	["Size"] = Vector3.new(0,0,0),
}

local DestinationPortPositions = {} --DestinationPorts[i].PortPosition + DestinationPorts[i].FaceNormal * DestinationPorts[i].Size
local SourcePortsInitials = {} --SourcePorts[i].PortPosition + SourcePorts[i].FaceNormal * SourcePorts[i].Size

local Min, Max = getMinAndMax(mergedTable) -- Get Min and Max Vec3
local GridSize = nil --DestinationPorts[i].Size
local LocalEnvironment = {} --[x][y][z] Size: (Max - Min) * 1/GridSize, AnchorPoint [1][1][1] = Min
-- Some Function: Get Positions of Ports --arg = math.round(SourcePorts[i].PortPosition - Min / GridSize) + 1, value = i
local GlobalEnvironment = {} --[x][y][z] Size = LocalEnvironmentSize * SomeEvenNumber

-- Translate Local Environment to Environment. Transpose Anchor Point by math.floor(SomeEvenNumber/2) * LocalEnvironment.Size
-- Some Function: Get Positions of Ports -- Generate Local Environment to Global Environment added with AnchorPoint

local PairwiseTable = {} --Pairwise Relation of DestinationPos and SourceInit in terms of Position in Global Environment

--Rules: Empty means nil, 0 means occupied.

--Algorithm

-- Breadth First Search in 3d
-- Create copy of Global Environment
-- From SourcePort Initial. Check adjacent blocks if valid.
-- Store positions of those valid adjacent blocks. If invalid, Ignore.
-- Iterate until 1 block hits destination port.

-- Count Backwards Prioritizing Last Normal Direction and draw to global environment
-- Block each block 1 Chebyeshev distance apart, by setting nils to zeroes.

--Generate Ethernet Cables using Normal Directions

