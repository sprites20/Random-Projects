--local HTTP_SERVICE = game:GetService("HttpService")
--local RUN_SERVICE = game:GetService("RunService")

function CreateBitStream(data)
	local stream = {}

	stream.data = data
	stream.pos = 0

	local nextByte = 0
	local nextBit = 0

	function stream.ReadBit()
		if nextByte >= #stream.data then
			return -1
		end

		local index = bit32.rshift(stream.pos, 3) + 1

		local bit = bit32.band(bit32.rshift(stream.data[nextByte + 1], (7 - nextBit)), 1)
		nextBit = nextBit + 1

		if nextBit == 8 then
			nextBit = 0
			nextByte = nextByte + 1
		end

		return bit
	end

	function stream.ReadBits(length)
		local bits = 0

		for i = 1, length do
			local bit = stream.ReadBit()

			if bit == -1 then
				bits = -1
				break
			end

			bits = bit32.bor(bit32.lshift(bits, 1), bit)
		end

		return bits
	end

	function stream.Align()
		if nextByte >= #stream.data then
			return
		end

		if nextBit ~= 0 then
			nextBit = 0
			nextByte = nextByte + 1
		end
	end

	return stream
end
--local HUFFMAN_MODULE = require(script.HuffmanTable)
local function BitsFromLength(root, element, pos)
	if type(root) == "table" then
		if pos == 0 then
			if #root < 2 then
				table.insert(root, element)
				return true
			end

			return false
		end

		for i = 0, 1 do
			if #root == i then
				table.insert(root, {})
			end

			if BitsFromLength(root[i + 1], element, pos - 1) == true then
				return true
			end
		end
	end

	return false
end

function CreateHuffmanTable()
	local huff = {}

	huff.root = {}
	huff.symbols = {}

	return huff
end

function ConstructTree(huffmanTable, lengths, elements)
	huffmanTable.elements = elements
	local ii = 0

	for i = 1, #lengths do
		for j = 1, lengths[i] do
			BitsFromLength(huffmanTable.root, elements[ii + 1], i - 1)
			ii = ii + 1
		end
	end
end

function GetNextSymbolFromHuffmanTable(huffmanTable, bitStream)
	if huffmanTable == nil then
		error("HUFFMAN TABLE IS NIL.")
	end

	local r = huffmanTable.root

	local length = 0

	while type(r) == "table" do
		r = r[bitStream.ReadBit() + 1]
		length = length + 1
	end

	return r, length
end

function GetCode(huffmanTable, bitStream)
	while true do
		local result = GetNextSymbolFromHuffmanTable(huffmanTable, bitStream)

		if result == nil then
			return -1
		end

		return result
	end
end
--local BITSTREAM_MODULE = require(script.BitStream)

--local RUN_SERVICE = game:GetService("RunService")

local PREVENT_TIMEOUT_INTERVAL = 50



-- Supported modes
local supportedModes = { -- If a mode is not supported (set to false) then the module will simply return and say that the mode isn't supported, in short, it won't bother decoding it.
	[0xC0] = true,  -- "Start Of Frame 0"
	[0xC1] = true,  -- "Start Of Frame 1"
	[0xC2] = true,  -- "Start Of Frame 2"
	[0xC3] = false, -- "Start Of Frame 3"
	[0xC5] = false, -- "Start Of Frame 5"
	[0xC6] = false, -- "Start Of Frame 6"
	[0xC7] = false, -- "Start Of Frame 7"
	[0xC9] = false, -- "Start Of Frame 9"
	[0xCA] = false, -- "Start Of Frame 10"
	[0xCB] = false, -- "Start Of Frame 11"
	[0xCD] = false, -- "Start Of Frame 13"
	[0xCE] = false, -- "Start Of Frame 14"
	[0xCF] = false, -- "Start Of Frame 15"
}

-- Create idct LUT
local idctTable = {}

local function NormCoeff(n)
	if n == 0 then
		return math.sqrt(1 / 8)
	else
		return math.sqrt(2 / 8)
	end
end

for i = 0, 7 do
	for j = 0, 7 do
		local grid = {}

		for y = 0, 7 do
			for x = 0, 7 do
				local nn = NormCoeff(j) * math.cos(j * math.pi * (x + 0.5) / 8)
				local mm = NormCoeff(i) * math.cos(i * math.pi * (y + 0.5) / 8)

				grid[x * 8 + y + 1] = nn * mm
			end
		end

		idctTable[i * 8 + j + 1] = grid
	end
end

-- Zigzag LUTs
local zigzag1D = {
	1,  2,  9,  17, 10, 3,  4,  11,
	18, 25, 33, 26, 19, 12, 5,  6,
	13, 20,	27, 34, 41, 49, 42, 35,
	28, 21, 14, 7,  8,  15, 22, 29,
	36, 43, 50, 57, 58, 51, 44, 37,
	30, 23, 16, 24, 31, 38, 45, 52,
	59, 60, 53, 46, 39, 32, 40, 47,
	54, 61, 62, 55, 48, 56, 63, 64
}

local zigzag2D = {
	{ 1 , 2 , 6 , 7 , 15, 16, 28, 29 },
	{ 3 , 5 , 8 , 14, 17, 27, 30, 43 },
	{ 4 , 9 , 13, 18, 26, 31, 42, 44 },
	{ 10, 12, 19, 25, 32, 41, 45, 54 },
	{ 11, 20, 24, 33, 40, 47, 53, 55 },
	{ 21, 23, 34, 39, 47, 52, 56, 61 },
	{ 22, 35, 38, 48, 51, 57, 60, 62 },
	{ 36, 37, 49, 50, 58, 59, 63, 64 }
}

-- Useful functions
local function CombineTwoBytes(high, low)
	return bit32.lshift(high, 8) + low
end

local function DecodeNumber(code, bits)
	local l = math.pow(2, code - 1)

	if bits >= l then
		return bits
	else
		return bits - (2 * l - 1)
	end
end

local function BitwiseHandleOverflow(x)
	if x > 4000000000 then
		return x - 4294967296
	else
		return x
	end
end



function CreateJPEGfromBytes(rawInputBytes, printDebugInformation, printProgress, preventTimeouts)
	-- Verify it's a JPEG
	if not (rawInputBytes[1] == 0xFF and rawInputBytes[2] == 0xD8 and rawInputBytes[3] == 0xFF) then
		warn("Image is not a JPEG.")
		return nil
	end

	local jpeg = {}

	jpeg.ImageData = {}

	jpeg.QuantisationTables = {}
	jpeg.HuffmanDCTables = {}
	jpeg.HuffmanACTables = {}

	jpeg.ImageWidth = 0
	jpeg.ImageHeight = 0

	jpeg.MCUCountX = 0
	jpeg.MCUCountY = 0

	jpeg.MaxVerticalSampleFactor = 0
	jpeg.MaxHorizontalSampleFactor = 0

	jpeg.FrameType = 0 -- The marker from start of frame, e.g 0xC0 = SOF0 (baseline), 0xC2 = SOF2 (progressive)
	jpeg.RestartInterval = 0
	jpeg.Precision = 8

	jpeg.ComponentCount = 0
	jpeg.ColorComponents = {}

	local colorTransform = 0

	local mcus = {}
	local eobRun = 0
	local previousDCs = { 0, 0, 0, 0 }

	local addOneToSelector = false -- Prevents zero index because this is Lua

	-- 'pos' will index the first byte in 'bytes' after the length information

	local function APPn(marker, pos, bytes)
		local payloadLength = CombineTwoBytes(bytes[pos - 2], bytes[pos - 1])
		local markerString = "0xFF" .. string.upper(string.format("%x", marker))

		if printDebugInformation then
			print("                    ")
			print("--------------------")
			print("   APP" .. marker - 0xE0 .. " [" .. markerString .. "]") -- tostring incase nil
			print("   Payload Length: " .. payloadLength)
			print("--------------------")
		end

		if marker == 0xEE and payloadLength >= 12 then
			local i = pos
			local lastByte = 0

			if bytes[i] == 65 and bytes[i + 1] == 100 and bytes[i + 2] == 111 and bytes[i + 3] == 98 and bytes[i + 4] == 101 then
				colorTransform = bytes[i + 11]

				if printDebugInformation then
					if colorTransform == 0 then
						print("Color transform: 0 (Unknown, RGB or CMYK assumed)")
					elseif colorTransform == 1 then
						print("Color transform: 1 (YCbCr)")
					elseif colorTransform == 2 then
						print("Color transform: 2 (YCCK)")
					end
				end
			end
		end

		return payloadLength
	end

	local function COM(marker, pos, bytes)
		local payloadLength = CombineTwoBytes(bytes[pos - 2], bytes[pos - 1])

		if printDebugInformation then
			print("                    ")
			print("--------------------")
			print("   COM [0xFFFE]     ")
			print("   Payload Length: " .. payloadLength)
			print("--------------------")
		end

		return payloadLength
	end

	local function DQT(marker, pos, bytes)
		local payloadLength = CombineTwoBytes(bytes[pos - 2], bytes[pos - 1])

		if printDebugInformation then
			print("                    ")
			print("--------------------")
			print("   DQT [0xFFDB]     ")
			print("   Payload Length: " .. payloadLength)
			print("--------------------")
		end

		local i = 0
		while bytes[pos + i] ~= 0xFF do
			local precision = bit32.rshift(bytes[pos + i], 4)
			local identifier = bit32.band(bytes[pos + i], 0x0F)

			local quant = {}

			if precision == 1 then
				for j = 1, 64 do
					local highByte = bytes[pos + i + 1]
					local lowByte = bytes[pos + i + 2]

					local value = CombineTwoBytes(highByte, lowByte)
					table.insert(quant, value)

					i = i + 2
				end
			else
				for j = 1, 64 do
					i = i + 1
					table.insert(quant, bytes[pos + i])
				end
			end

			-- Print
			if printDebugInformation then
				if identifier == 0 then
					print("Destination: " .. identifier .. " [Luminance]")
				elseif identifier == 1 then
					print("Destination: " .. identifier .. " [Chrominance]")
				end

				for x = 0, 7 do
					local str = ""

					for y = 0, 7 do
						local index = y * 8 + x + 1

						local word = quant[zigzag2D[x + 1][y + 1]]
						local spaces = string.rep(" ", 4 - string.len(word))

						str = str .. word .. spaces
					end

					print("  Row " .. x .. ":  " .. str)
				end
			end

			-- Add it to the global variable
			jpeg.QuantisationTables[identifier + 1] = quant

			i = i + 1
		end

		return payloadLength
	end

	local function DHT(marker, pos, bytes)
		local payloadLength = CombineTwoBytes(bytes[pos - 2], bytes[pos - 1])

		if printDebugInformation then
			print("                    ")
			print("--------------------")
			print("   DHT [0xFFC4]     ")
			print("   Payload Length: " .. payloadLength)
		end

		-- Create huffman table
		local function GetCodesFromLengths(lengths) -- Creates the codes used to traverse the huffman tree given the lengths in the jpeg binary
			local codes = {}

			local codeCandidate = 0

			for bitLength = 1, #lengths do
				local length = lengths[bitLength]

				for i = 1, length do
					table.insert(codes, { codeCandidate, bitLength })

					codeCandidate = codeCandidate + 1
				end

				codeCandidate = bit32.lshift(codeCandidate, 1)
			end

			return codes
		end

		-- Extract class and destination
		local i = 0

		while i < payloadLength - 2 do -- Subtract 2 because payload length includes length information
			local classAndDestination = bytes[pos + i] -- This will be used to index jpeg.HuffmanTables

			local class = bit32.band(bit32.rshift(classAndDestination, 4), 0x0F) -- 0 = DC, 1 = AC
			local destination = bit32.band(classAndDestination, 0x0F)            -- 0 = Luminace, 1 = Chrominance

			-- Extract information
			local symbols = {}
			local lengths = {}
			local symbolsSorted = {}

			-- Extract lengths
			for j = 1, 16 do
				i = i + 1
				table.insert(lengths, bytes[pos + i])
			end

			-- Extract symbols
			for j, length in pairs(lengths) do
				symbolsSorted[j] = {}

				for k = 1, length do
					i = i + 1
					local symbol = bytes[pos + i]

					table.insert(symbols, symbol)
					symbolsSorted[j][k] = symbol
				end
			end

			i = i + 1

			-- Print
			if printDebugInformation then
				print("--------------------")
				print("Destination: " .. destination)
				print("Class: " .. class)

				for j = 1, #symbolsSorted do
					local str = string.format("  Codes of length %i bits (%i total): ", j, #symbolsSorted[j])

					for k = 1, #symbolsSorted[j] do
						local x = string.upper(string.format("%x", symbolsSorted[j][k]))

						if string.len(x) == 1 then
							x = "0" .. x
						end

						str = str .. x .. " "
					end

					print(str)
				end
			end

			if printDebugInformation then
				print("Symbols and their codes:")
			end

			local symbolsAndCodes = {}

			for i, info in pairs(GetCodesFromLengths(lengths)) do
				local code = info[1]
				local bitLength = info[2]

				local str = ""
				local c = code

				for i = 1, bitLength do
					local bit = bit32.band(c, 1)
					c = bit32.rshift(c, 1)

					str = str .. bit
				end

				if printDebugInformation then
					print("  " .. symbols[i] .. " = " .. string.reverse(str) .. " [" .. code .. "]")
				end

				symbolsAndCodes[i] = {
					symbols[i],
					code,
					bitLength
				}
			end

			local huffmanTable = CreateHuffmanTable()
			ConstructTree(huffmanTable, lengths, symbols)

			if class == 0 then -- DC
				jpeg.HuffmanDCTables[destination + 1] = huffmanTable
			elseif class == 1 then -- AC				
				jpeg.HuffmanACTables[destination + 1] = huffmanTable
			end
		end

		return payloadLength
	end

	local function DRI(marker, pos, bytes)
		local payloadLength = CombineTwoBytes(bytes[pos - 2], bytes[pos - 1])

		local interval = CombineTwoBytes(bytes[pos], bytes[pos + 1]) --CombineTwoBytes(bytes[2], bytes[3])

		if printDebugInformation then
			print("                    ")
			print("--------------------")
			print("   DRI [0xFFDD]    ")
			print("   Payload Length: " .. payloadLength)
			print("--------------------")
			print("Interval: " .. interval)
		end

		jpeg.RestartInterval = interval

		return payloadLength
	end

	local function SOFn(marker, pos, bytes)
		if not supportedModes[marker] then
			return "Not supported."
		end

		local payloadLength = CombineTwoBytes(bytes[pos - 2], bytes[pos - 1])

		local markerString = "0xFF" .. string.upper(string.format("%x", marker))

		if printDebugInformation then 
			print("                    ")
			print("--------------------")
			print("   SOF" .. marker - 0xC0 .. " [" .. markerString .. "]") -- tostring incase nil
			print("   Payload Length: " .. payloadLength)
			print("--------------------")
		end

		-- Read information
		local precision = bytes[pos]
		local lineNumber = CombineTwoBytes(bytes[pos + 1], bytes[pos + 2]) -- aka height
		local samplesPerLine = CombineTwoBytes(bytes[pos + 3], bytes[pos + 4]) -- aka width
		local componentCount = bytes[pos + 5]

		jpeg.ImageWidth = samplesPerLine
		jpeg.ImageHeight = lineNumber
		jpeg.Precision = precision
		jpeg.ComponentCount = componentCount
		jpeg.FrameType = marker

		jpeg.MCUCountX = math.floor((jpeg.ImageWidth - 1) / 8)
		jpeg.MCUCountY = math.floor((jpeg.ImageHeight - 1) / 8)

		-- Fill in image with blank data
		for x = 1, jpeg.ImageWidth do
			jpeg.ImageData[x] = {}

			for y = 1, jpeg.ImageHeight do
				jpeg.ImageData[x][y] = { 0, 0, 0 }
			end
		end

		-- Create mcus
		for x = 1, jpeg.MCUCountX + 8 do
			mcus[x] = {}
			for y = 1, jpeg.MCUCountY + 8 do
				mcus[x][y] = {}
				for i = 1, componentCount do
					mcus[x][y][i] = table.create(64, 0)
				end
			end
		end

		if printDebugInformation then
			print("Image Resolution: " .. jpeg.ImageWidth .. "x" .. jpeg.ImageHeight)
			print("Precision: " .. precision)
			print("Components: " .. componentCount)
		end

		for id = 0, componentCount - 1 do
			local componentId  = bytes[pos + 6 + (id * 3)]
			local sampleFactor = bytes[pos + 7 + (id * 3)]
			local quantTableId = bytes[pos + 8 + (id * 3)]

			if addOneToSelector then
				componentId = componentId + 1
			end			

			if componentId == 0 then
				addOneToSelector = true
				componentId = componentId + 1
			end

			local horizontalSample = bit32.band(bit32.rshift(sampleFactor, 4), 0x0F)
			local verticalSample = bit32.band(sampleFactor, 0x0F)

			jpeg.MaxHorizontalSampleFactor = math.max(jpeg.MaxHorizontalSampleFactor, horizontalSample)
			jpeg.MaxVerticalSampleFactor = math.max(jpeg.MaxVerticalSampleFactor, verticalSample)

			jpeg.ColorComponents[componentId] = {}
			jpeg.ColorComponents[componentId].ID = id + 1
			jpeg.ColorComponents[componentId].HorizontalSamplingFactor = horizontalSample
			jpeg.ColorComponents[componentId].VerticalSamplingFactor = verticalSample
			jpeg.ColorComponents[componentId].QuantSelection = quantTableId

			if printDebugInformation then
				print(string.format("  Component %i: [Selection: %i] [Sample Factor: %i] [Quant ID: %i]", id + 1, componentId, sampleFactor, quantTableId))
				print("   - X Sampling Factor: " .. horizontalSample)
				print("   - Y Sampling Factor: " .. verticalSample)
			end
		end

		return payloadLength
	end

	local function SOS(marker, pos, bytes)
		local payloadLength = CombineTwoBytes(bytes[pos - 2], bytes[pos - 1])

		local componentCount = bytes[pos]
		local offset = 1

		if printDebugInformation then
			print("                    ")
			print("--------------------")
			print("   SOS [0xFFDA]     ")
			print("   Payload Length: " .. payloadLength)
			print("--------------------")
			print("Component Count: " .. componentCount)
		end

		local loopComponents = {}

		for i = 0, componentCount - 1 do
			local selector = bytes[pos + offset]

			local huffmanId = bytes[pos + offset + 1]
			local DCTableID = bit32.band(bit32.rshift(huffmanId, 4), 0x0F)
			local ACTableID = bit32.band(huffmanId, 0x0F)

			if addOneToSelector then
				selector = selector + 1
			end

			local component = {}
			component.ID = selector
			component.HuffmanDCTableID = DCTableID + 1
			component.HuffmanACTableID = ACTableID + 1
			component.HorizontalSample = jpeg.ColorComponents[selector].HorizontalSamplingFactor
			component.VerticalSample = jpeg.ColorComponents[selector].VerticalSamplingFactor

			local quantSelection = jpeg.ColorComponents[selector].QuantSelection + 1
			component.QuantisationTable = jpeg.QuantisationTables[quantSelection]

			table.insert(loopComponents, component)

			if printDebugInformation then
				print(" Component[" .. i + 1 .. "]: selector=" .. selector .. ", table=" .. DCTableID .. "(DC)," .. ACTableID .. "(AC)")
			end

			offset = offset + 2
		end

		local successiveApproximation  = bytes[pos + offset + 2]
		local ss = bytes[pos + offset]     -- Spectral start
		local se = bytes[pos + offset + 1] -- Spectral end
		local ah = bit32.band(bit32.rshift(successiveApproximation, 4), 0x0F) -- Successive Approximation low part of byte
		local al = bit32.band(successiveApproximation, 0x0F) -- Successive Approximation low part of byte

		if printDebugInformation then
			print("Spectral Selection: " .. ss .. " .. " .. se)
			print("Successive Approximation: " .. successiveApproximation)

			print("Successive High Part: " .. ah)
			print("Successive Low Part: " .. al)
		end

		-- Create scan data by removing stuff bytes and restart markers from inside it
		local scanData = {}

		do
			local i = pos + offset + 2
			local bytesToSkip = 0

			while true do
				i = i + 1

				if bytesToSkip > 0 then
					bytesToSkip = bytesToSkip - 1
					continue
				end

				local byte = bytes[i]
				local nextByte = bytes[i + 1]

				if byte == 0xFF then
					if nextByte >= 0xD0 and nextByte <= 0xD7 then
						bytesToSkip = bytesToSkip + 1
						continue
					elseif nextByte == 0x00 then
						bytesToSkip = bytesToSkip + 1
						table.insert(scanData, byte)
						continue				
					else -- Probably another marker
						break
					end
				end

				table.insert(scanData, byte)

				if nextByte == nil then
					break
				end
			end
		end

		-- Make bit stream from scan data that will be used for huffman decoding
		local bitStream = CreateBitStream(scanData)

		local mcuCountX = math.floor((jpeg.ImageWidth - 1) / 8)
		local mcuCountY = math.floor((jpeg.ImageHeight - 1) / 8)

		local maxHorizontalSample = jpeg.MaxHorizontalSampleFactor
		local maxVerticalSample = jpeg.MaxVerticalSampleFactor

		local restartInterval = jpeg.RestartInterval
		local restartCount = restartInterval

		local decodedMCUCount = 0

		-- Function used for decoding individual MCUs in baseline mode
		local function BaselineDecodeMCUComponent(mcu, component)
			-- Decode DC component
			local code = GetCode(jpeg.HuffmanDCTables[component.HuffmanDCTableID], bitStream)

			local actualID = jpeg.ColorComponents[component.ID].ID
			local prevDC = previousDCs[actualID]

			if prevDC == nil then
				prevDC = 0
			end

			local bits = bitStream.ReadBits(code)
			local dccoeff = DecodeNumber(code, bits) + prevDC

			previousDCs[actualID] = dccoeff -- Set previous DC

			mcu[1] = dccoeff

			local huffmanTable = jpeg.HuffmanACTables[component.HuffmanACTableID]

			-- Decode AC components
			local i = 1
			while i < 64 do
				code = GetCode(huffmanTable, bitStream)

				if code == 0 then
					return
				end

				if code > 16 then -- AC table
					i = i + bit32.rshift(code, 4) -- Num zeros which we skip
					code = bit32.band(code, 0x0F)
				end

				bits = bitStream.ReadBits(code)

				if i < 64 then
					i = i + 1

					local accoeff = DecodeNumber(code, bits)
					mcu[i] = accoeff
				end
			end
		end

		-- Functions used for decoding parts of individual MCUs in progressive mode
		local function Extend(additional, magnitude)
			local vt = BitwiseHandleOverflow(bit32.lshift(1, magnitude - 1))

			if additional < vt then
				return additional + BitwiseHandleOverflow(bit32.lshift(-1, magnitude)) + 1
			else
				return additional
			end
		end

		local function RefineAC(coeff)
			if coeff > 0 then
				if bitStream.ReadBit() == 1 then
					return coeff + BitwiseHandleOverflow(bit32.lshift(1, al))
				end
			elseif coeff < 0 then
				if bitStream.ReadBit() == 1 then
					return coeff + BitwiseHandleOverflow(bit32.lshift(-1, al))
				end
			end

			return coeff
		end

		local function DecodeDCProgressiveFirstPerBlock(mcu, component)
			local size = GetCode(jpeg.HuffmanDCTables[component.HuffmanDCTableID], bitStream)
			local bits = bitStream.ReadBits(size)

			local dcValue = Extend(bits, size) + previousDCs[component.ID]
			previousDCs[component.ID] = dcValue -- Set previous DC

			mcu[1] = BitwiseHandleOverflow(bit32.lshift(dcValue, al))
		end

		local function DecodeDCProgressiveRefinePerBlock(mcu, component)
			local bit = bitStream.ReadBit()

			local leftShiftedBit = BitwiseHandleOverflow(bit32.lshift(bit, al))
			mcu[1] = BitwiseHandleOverflow(bit32.bor(mcu[1], leftShiftedBit))
		end

		local function DecodeACProgressiveFirstPerBlock(mcu, component)
			if eobRun > 0 then
				eobRun = eobRun - 1
				return
			end

			local huffmanTable = jpeg.HuffmanACTables[component.HuffmanACTableID]

			local i = ss 
			while i <= se do
				local symbol = GetCode(huffmanTable, bitStream)

				local runLength = bit32.rshift(symbol, 4)
				local size = bit32.band(symbol, 0x0F)

				if size == 0 then
					if runLength == 15 then
						i = i + 16
					else
						eobRun = bitStream.ReadBits(runLength) + math.pow(2, runLength) - 1
						return
					end
				else
					i = i + runLength + 1

					local bits = bitStream.ReadBits(size)

					local value = Extend(bits, size)
					value = bit32.lshift(value, al)
					value = BitwiseHandleOverflow(value)

					mcu[i] = value
				end
			end
		end

		local function DecodeACProgressiveRefinePerBlock(mcu, component)
			local i = ss

			if eobRun > 0 then
				while i <= se do
					if mcu[i + 1] ~= 0 then
						mcu[i + 1] = RefineAC(mcu[i + 1])
					end

					i = i + 1
				end

				eobRun = eobRun - 1
				return
			end

			local huffmanTable = jpeg.HuffmanACTables[component.HuffmanACTableID]

			while i <= se do
				local symbol = GetCode(huffmanTable, bitStream)

				local runLength = bit32.rshift(symbol, 4)
				local size = symbol % 16

				if size == 1 then
					local value = Extend(bitStream.ReadBits(size), size)
					value = BitwiseHandleOverflow(bit32.lshift(value, al))

					while (runLength > 0 or mcu[i + 1] ~= 0) and i < se do
						i = i + 1

						if mcu[i] ~= 0 then
							mcu[i] = RefineAC(mcu[i])
						else
							runLength = runLength - 1
						end
					end

					i = i + 1
					mcu[i] = value
				elseif size == 0 then
					if runLength < 15 then
						local newEOBrun = bitStream.ReadBits(runLength) + BitwiseHandleOverflow(bit32.lshift(1, runLength))

						while i <= se and i < se do
							i = i + 1

							if mcu[i] ~= 0 then
								mcu[i] = RefineAC(mcu[i])
							end
						end

						eobRun = newEOBrun - 1
						return
					else
						while runLength >= 0 and i < se do
							i = i + 1

							if mcu[i] ~= 0 then
								mcu[i] = RefineAC(mcu[i])
							else
								runLength = runLength - 1
							end
						end
					end
				else
					i = i + 1
				end
			end
		end

		-- Main progressive jpeg decoding functions
		local function DecodeDCProgressiveFirst()
			if componentCount > 1 then -- Interleaved
				for y = 0, mcuCountY, maxVerticalSample do
					for x = 0, mcuCountX, maxHorizontalSample do
						for _, component in pairs(loopComponents) do
							for v = 0, component.VerticalSample - 1 do
								for h = 0, component.HorizontalSample - 1 do
									local mcuX = x + h + 1
									local mcuY = y + v + 1

									DecodeDCProgressiveFirstPerBlock(mcus[mcuX][mcuY][component.ID], component)
								end
							end
						end
					end

					if preventTimeouts then
						if y % PREVENT_TIMEOUT_INTERVAL == 0 then
							wait(0)
						end
					end
				end
			else -- For non-interleaved (one component) we do this
				local component = loopComponents[1]

				for y = 0, mcuCountY, 3 - component.VerticalSample do
					for x = 0, mcuCountX, 3 - component.HorizontalSample do
						local mcuX = x + 1
						local mcuY = y + 1

						DecodeDCProgressiveFirstPerBlock(mcus[mcuX][mcuY][component.ID], component)
					end

					if preventTimeouts then
						if y % PREVENT_TIMEOUT_INTERVAL == 0 then
							wait(0)
						end
					end
				end
			end
		end

		local function DecodeDCProgressiveRefine()
			for y = 0, mcuCountY, maxVerticalSample do
				for x = 0, mcuCountX, maxHorizontalSample do
					for _, component in pairs(loopComponents) do
						local verticalSample = component.VerticalSample
						local horizontalSample = component.HorizontalSample

						for v = 0, verticalSample - 1 do
							for h = 0, horizontalSample - 1 do
								local mcuX = x + h + 1
								local mcuY = y + v + 1

								DecodeDCProgressiveRefinePerBlock(mcus[mcuX][mcuY][component.ID], component)
							end
						end
					end
				end

				if preventTimeouts then
					if y % PREVENT_TIMEOUT_INTERVAL == 0 then
						wait(0)
					end
				end
			end
		end

		local function DecodeACProgressiveFirst()
			local component = loopComponents[1]

			local subtractFromX = 2
			local subtractFromY = 2

			if maxHorizontalSample == 2 then subtractFromX = 3 end
			if maxVerticalSample == 2 then subtractFromY = 3 end

			for y = 0, mcuCountY, subtractFromY - component.VerticalSample do
				for x = 0, mcuCountX, subtractFromX - component.HorizontalSample do
					local mcuX = x + 1
					local mcuY = y + 1

					DecodeACProgressiveFirstPerBlock(mcus[mcuX][mcuY][component.ID], component)
				end

				if preventTimeouts then
					if y % PREVENT_TIMEOUT_INTERVAL == 0 then
						wait(0)
					end
				end
			end
		end

		local function DecodeACProgressiveRefine()
			local component = loopComponents[1]

			local subtractFromX = 2
			local subtractFromY = 2

			if maxHorizontalSample == 2 then subtractFromX = 3 end
			if maxVerticalSample == 2 then subtractFromY = 3 end

			for y = 0, mcuCountY, subtractFromY - component.VerticalSample do
				for x = 0, mcuCountX, subtractFromX - component.HorizontalSample do
					local mcuX = x + 1
					local mcuY = y + 1

					DecodeACProgressiveRefinePerBlock(mcus[mcuX][mcuY][component.ID], component)
				end

				if preventTimeouts then
					if y % PREVENT_TIMEOUT_INTERVAL == 0 then
						wait(0)
					end
				end
			end
		end

		-- Decode baseline jpegs
		if jpeg.FrameType == 0xC0 then
			for y = 0, mcuCountY, maxVerticalSample do
				for x = 0, mcuCountX, maxHorizontalSample do
					for i, component in pairs(loopComponents) do
						local componentId = i
						local quantisationTable = component.QuantisationTable
						local horizontalSample = component.HorizontalSample
						local verticalSample = component.VerticalSample

						for v = 0, verticalSample - 1 do
							for h = 0, horizontalSample - 1 do
								local mcuX = x + h + 1
								local mcuY = y + v + 1

								BaselineDecodeMCUComponent(
									mcus[mcuX][mcuY][componentId],
									component
								)
							end
						end

						decodedMCUCount = decodedMCUCount + (verticalSample * horizontalSample)
					end

					-- Restart Interval
					if restartInterval ~= 0 then
						restartCount = restartCount - 1

						if restartCount == 0 then
							restartCount = restartInterval

							previousDCs = { 0, 0, 0 }
							bitStream.Align()
						end
					end
				end

				if preventTimeouts then
					if y % PREVENT_TIMEOUT_INTERVAL == 0 then
						wait(0)
					end
				end
			end

			if printDebugInformation then
				print("Total MCUs decoded: " .. decodedMCUCount)
			end
		end

		-- Decode progressive jpegs
		if jpeg.FrameType == 0xC2 then
			-- Validation checks
			if ss == 0 and se ~= 0 then
				warn("Spectral selection start is zero and end is not zero.")
			end

			if se == 0 and ss ~= 0 then
				warn("Spectral selection end is zero and start is not zero.")
			end

			if ss > se then
				warn("Spectral selection start is greater than spectral selection end.")
			end

			if ss ~= 0 and #loopComponents > 1 then
				warn("Spectral selection start is not zero and loop components is greater than one.")
			end

			if ah > 13 then
				warn("Successive proximation high 4 bits is greater than 13.")
			end

			if al > 13 then
				warn("Successive proximation low 4 bits is greater than 13.")
			end

			if ah ~= 0 then
				if ah - al ~= 1 then
					warn("ah is not zero and ah - al ~= 1")
				end
			end

			-- Decode
			if ss == 0 and se == 0 then
				if ah == 0 then
					DecodeDCProgressiveFirst()
				else
					DecodeDCProgressiveRefine()
				end
			else
				if ah == 0 then
					DecodeACProgressiveFirst()
				else
					DecodeACProgressiveRefine()
				end
			end
		end
	end

	local markerProcedures = {
		[0xC0] = SOFn,    -- SOF0  [Baseline DCT]
		[0xC1] = SOFn,    -- SOF1  [Extended Sequential DCT]
		[0xC2] = SOFn,    -- SOF2  [Progressive DCT]
		[0xC3] = SOFn,    -- SOF3  [Lossless (sequential)]
		[0xC4] = DHT,     -- DHT   [Define Huffman Table]
		[0xC5] = SOFn,    -- SOF5  [Differential sequential DCT]
		[0xC6] = SOFn,    -- SOF6  [Differential progressive DCT]
		[0xC7] = SOFn,    -- SOF7  [Differential lossless (sequential)]
		[0xC8] = "Print", -- JPG   [Reserved for JPEG extensions]
		[0xC9] = SOFn,    -- SOF9  [Extended sequential DCT]
		[0xCA] = SOFn,    -- SOF10 [Progressive DCT]
		[0xCB] = SOFn,    -- SOF11 [Lossless (sequential)]
		[0xCC] = "Print", -- DAC   [Define arithmetic coding conditioning(s)]
		[0xCD] = SOFn,    -- SOF13 [Differential sequential DCT]
		[0xCE] = SOFn,    -- SOF14 [Differential progressive DCT]
		[0xCF] = SOFn,    -- SOF15 [Differential lossless (sequential)]
		[0xD0] = "Print", -- RSTm* [Restart with modulo 8 count "m"]
		[0xD1] = "Print", -- RSTm* [Restart with modulo 8 count "m"]
		[0xD2] = "Print", -- RSTm* [Restart with modulo 8 count "m"]
		[0xD3] = "Print", -- RSTm* [Restart with modulo 8 count "m"]
		[0xD4] = "Print", -- RSTm* [Restart with modulo 8 count "m"]
		[0xD5] = "Print", -- RSTm* [Restart with modulo 8 count "m"]
		[0xD6] = "Print", -- RSTm* [Restart with modulo 8 count "m"]
		[0xD7] = "Print", -- RSTm* [Restart with modulo 8 count "m"]
		[0xD8] = "Print", -- SOI  [Start of image]
		[0xD9] = "Print", -- EOI  [End of image]
		[0xDA] = SOS,     -- SOS   [Start of scan]
		[0xDB] = DQT,     -- DQT   [Define quantisation table(s)]
		[0xDC] = "Print", -- DNL   [Define number of lines]
		[0xDD] = DRI,     -- DRI   [Define restart interval]
		[0xDE] = "Print", -- DHP   [Define hierarchical progression]
		[0xDF] = "Print", -- EXP   [Expand reference components(s)]
		[0xE0] = APPn,    -- APP0  [Application segments 0xE0->0xEF]
		[0xE1] = APPn,    -- APP1
		[0xE2] = APPn,    -- APP2
		[0xE3] = APPn,    -- APP3
		[0xE4] = APPn,    -- APP4
		[0xE5] = APPn,    -- APP5
		[0xE6] = APPn,    -- APP6
		[0xE7] = APPn,    -- APP7
		[0xE8] = APPn,    -- APP8
		[0xE9] = APPn,    -- APP9
		[0xEA] = APPn,    -- APP10
		[0xEB] = APPn,    -- APP11
		[0xEC] = APPn,    -- APP12
		[0xED] = APPn,    -- APP13
		[0xEE] = APPn,    -- APP14
		[0xEF] = APPn,    -- APP15
		[0xF0] = "Print", -- JPG0  [JPG segments 0xF0->0xFD]
		[0xF1] = "Print", -- JPG1
		[0xF2] = "Print", -- JPG2
		[0xF3] = "Print", -- JPG3
		[0xF4] = "Print", -- JPG4
		[0xF5] = "Print", -- JPG5
		[0xF6] = "Print", -- JPG6
		[0xF7] = "Print", -- JPG7
		[0xF8] = "Print", -- JPG8
		[0xF9] = "Print", -- JPG9
		[0xFA] = "Print", -- JPG10
		[0xFB] = "Print", -- JPG11
		[0xFC] = "Print", -- JPG12
		[0xFD] = "Print", -- JPG13
		[0xFE] = COM      -- COM [Comment]
	}


	-- Decode
	local totalTimingStart = tick()
	local timingStart = tick()

	local bytes = rawInputBytes
	local skipCount = 0

	local scanCount = 0

	for pos = 1, #bytes - 1 do
		local byte = bytes[pos]
		local nextByte = bytes[pos + 1]

		if skipCount > 0 then
			skipCount = skipCount - 1
			continue
		end

		if byte ~= 0xFF then -- Skip unless there is a possible marker, scanning and stuff will be dealt with inside functions
			continue
		end

		if nextByte == 0x00 then
			continue
		end

		-- nextByte is the marker
		local procedure = markerProcedures[nextByte]

		if procedure == nil then
			continue
		elseif type(procedure) == "string" then
			continue
		end

		-- Procedure
		local returnValue = procedure(nextByte, pos + 4, bytes)

		if returnValue then
			-- Return incase jpeg is not supported
			if returnValue == "Not supported." then
				return "Not supported."
			elseif type(returnValue) == "number" then
				-- Skip bytes
				skipCount = skipCount + returnValue
			end
		end

		-- For debugging
		if nextByte == 0xDA then
			scanCount = scanCount + 1
		end

		if scanCount == 1000000 then
			break
		end
	end

	local timingEnd = tick()

	if printProgress then
		print("")
		print("DECODED IN: " .. timingEnd - timingStart .. "s")
	end

	-- Perform IDCT
	timingStart = tick()

	local iLimit = (8 * jpeg.MaxVerticalSampleFactor) - 1
	local jLimit = (8 * jpeg.MaxHorizontalSampleFactor) - 1

	local subtractFromX = 2
	local subtractFromY = 2

	if jpeg.MaxHorizontalSampleFactor == 2 then subtractFromX = 3 end
	if jpeg.MaxVerticalSampleFactor == 2 then subtractFromY = 3 end

	for component, _ in pairs(jpeg.ColorComponents) do
		local actualID = jpeg.ColorComponents[component].ID
		local componentHorizontalSample = jpeg.ColorComponents[component].HorizontalSamplingFactor
		local componentVerticalSample = jpeg.ColorComponents[component].VerticalSamplingFactor
		local quantSelection = jpeg.ColorComponents[component].QuantSelection
		local quantisationTable = jpeg.QuantisationTables[quantSelection + 1]

		for y = 0, jpeg.MCUCountY, jpeg.MaxVerticalSampleFactor do
			for x = 0, jpeg.MCUCountX, jpeg.MaxHorizontalSampleFactor do
				for v = 0, componentVerticalSample - 1 do
					for h = 0, componentHorizontalSample - 1 do
						local mcuX = x + h + 1
						local mcuY = y + v + 1

						-- IDCT
						local decodedMCU = table.create(64, 0)

						for i, influence in pairs(mcus[mcuX][mcuY][actualID]) do
							if influence == 0 then
								continue
							end

							if i > 64 then
								break
							end

							local zigzagIndex = zigzag1D[i]
							local quantisedInfluence = influence * quantisationTable[i]

							local idctLUT = idctTable[zigzagIndex]

							for j = 1, 64 do
								decodedMCU[j] = decodedMCU[j] + (idctLUT[j] * quantisedInfluence)
							end
						end

						-- Fill in pixel image
						for i = 0, iLimit do
							for j = 0, jLimit do
								local pixelX = (mcuX - 1) * 8 + j + 1
								local pixelY = (mcuY - 1) * 8 + i + 1

								if pixelX <= jpeg.ImageWidth and pixelY <= jpeg.ImageHeight then
									local ii = math.floor(i / (subtractFromY - componentVerticalSample))
									local jj = math.floor(j / (subtractFromX - componentHorizontalSample))

									local index = jj * 8 + ii + 1

									jpeg.ImageData[pixelX][pixelY][actualID] = decodedMCU[index]
								end
							end
						end
					end
				end
			end

			-- Stop script from timing out
			if preventTimeouts then
				if y % PREVENT_TIMEOUT_INTERVAL == 0 then
					wait(0)
				end
			end
		end
	end

	timingEnd = tick()

	if printProgress then
		print("PERFORMED IDCT IN: " .. timingEnd - timingStart .. "s")
	end

	-- Convert to RGB
	timingStart = tick()

	for x = 1, jpeg.ImageWidth do
		for y = 1, jpeg.ImageHeight do
			if jpeg.ComponentCount == 3 then
				local lum = jpeg.ImageData[x][y][1]
				local cb = jpeg.ImageData[x][y][2]
				local cr = jpeg.ImageData[x][y][3]

				local r = lum + 1.402 * cr + 128
				local g = lum - 0.34414 * cb - 0.71414 * cr + 128
				local b = lum + 1.772 * cb + 128

				r = math.clamp(r, 0, 255)
				g = math.clamp(g, 0, 255)
				b = math.clamp(b, 0, 255)

				jpeg.ImageData[x][y][1] = r
				jpeg.ImageData[x][y][2] = g
				jpeg.ImageData[x][y][3] = b
			elseif jpeg.ComponentCount == 4 then
				local c = jpeg.ImageData[x][y][1]
				local m = jpeg.ImageData[x][y][2]
				local Y = jpeg.ImageData[x][y][3]
				local k = jpeg.ImageData[x][y][4]

				local r, g, b

				if colorTransform == 2 or colorTransform == 1 then
					r = c + 1.402 * Y + 128
					g = c - 0.34414 * m - 0.71414 * Y + 128
					b = c + 1.772 * m + 128

					r = math.clamp(r, 0, 255)
					g = math.clamp(g, 0, 255)
					b = math.clamp(b, 0, 255)

					r = (255 - r) * ((k + 128) / 255)
					g = (255 - g) * ((k + 128) / 255)
					b = (255 - b) * ((k + 128) / 255)
				elseif colorTransform == 0 then
					r = (c + 128) * ((k + 128) / 255)
					g = (m + 128) * ((k + 128) / 255)
					b = (Y + 128) * ((k + 128) / 255)
				end

				jpeg.ImageData[x][y][1] = r
				jpeg.ImageData[x][y][2] = g
				jpeg.ImageData[x][y][3] = b
				jpeg.ImageData[x][y][4] = nil
			end
		end

		-- Stop script from timing out
		if preventTimeouts then
			if x % PREVENT_TIMEOUT_INTERVAL == 0 then
				wait(0)
			end
		end
	end

	timingEnd = tick()

	if printProgress then
		print("CONVERTED TO RGB: " .. timingEnd - timingStart .. "s")
	end

	local totalTimingEnd = tick()

	if printProgress then
		print("FINISHED DECODING JPEG IN: " .. totalTimingEnd - totalTimingStart .. "s")
	end

	-- Other API functions
	function jpeg.GetPixel(x, y)
		local r = jpeg.ImageData[x][y][1]
		local g = jpeg.ImageData[x][y][2]
		local b = jpeg.ImageData[x][y][3]

		return r, g, b
	end

	return jpeg
end


function RGBtoXYZ(c)
	c[1] = c[1] / 255
	c[2] = c[2] / 255
	c[3] = c[3] / 255

	for i = 1, 3 do
		if c[i] > 0.04045 then
			c[i] = math.pow((c[i] + 0.055) / 1.055, 2.4)
		else
			c[i] = c[i] / 12.92
		end
	end

	local x = c[1] * 0.4124 + c[2] * 0.3576 + c[3] * 0.1805
	local y = c[1] * 0.2126 + c[2] * 0.7152 + c[3] * 0.0722
	local z = c[1] * 0.0193 + c[2] * 0.1192 + c[3] * 0.9505

	return { x * 100, y * 100, z * 100 }
end

function XYZtoCIELAB(c)
	local xyz = {
		c[1] / 95.047,
		c[2] / 100,
		c[3] / 108.883
	}

	for i = 1, 3 do
		if xyz[i] > 0.008856 then
			xyz[i] = math.pow(xyz[i], 1 / 3)
		else
			xyz[i] = (7.787 * xyz[i]) + (16 / 116)
		end
	end

	local l = 116 * xyz[2] - 16
	local a = 500 * (xyz[1] - xyz[2])
	local b = 200 * (xyz[2] - xyz[3])

	return { l, a, b }
end


function CIELABtoXYZ(c)
	local y = (c[1] + 16) / 116
	local x = (c[2] / 500) + y
	local z = y - (c[3] / 200)

	local xyz = { x, y, z }

	for i = 1, 3 do
		if math.pow(xyz[i], 3) > 0.008856 then
			xyz[i] = math.pow(xyz[i], 3)
		else
			xyz[i] = (xyz[i] - (16 / 116)) / 7.787
		end
	end

	return {
		xyz[1] * 95.047,
		xyz[2] * 100,
		xyz[3] * 108.883
	}
end

function XYZtoRGB(c)
	local x = c[1] / 100
	local y = c[2] / 100
	local z = c[3] / 100

	local rgb = {
		x * 3.2406 + y * -1.5372 + z * -0.4986,
		x * -0.9689 + y * 1.8758 + z * 0.0415,
		x * 0.0557 + y * -0.2040 + z * 1.0570
	}

	for i = 1, 3 do
		if rgb[i] > 0.0031308 then
			rgb[i] = 1.055 * math.pow(rgb[i], 1 / 2.4) - 0.055
		else
			rgb[i] = 12.92 * rgb[i]
		end
	end

	return { rgb[1] * 255, rgb[2] * 255, rgb[3] * 255 }
end

function GetDeltaE(c1, c2)
	local xyz1 = RGBtoXYZ(c1)
	local xyz2 = RGBtoXYZ(c2)

	local lab1 = XYZtoCIELAB(xyz1)
	local lab2 = XYZtoCIELAB(xyz2)

	return math.sqrt(
		math.pow(lab1[1] - lab2[1], 2) + math.pow(lab1[2] - lab2[2], 2) + math.pow(lab1[3] - lab2[3], 2)
	)
end

-- Config

local preferredMaxPixels = 8192

compressionLevel = nil
url = nil
if compressionLevel == nil then
	compressionLevel = 5
end

local charstring = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local charmap = {}
local charmap2 = {}

for i=1, #charstring do
	charmap[i] = string.sub(charstring, i, i)
	charmap2[charmap[i]] = i
end

local function splitByChunk(text, chunkSize)
	local s = {}
	for i=1, #text, chunkSize do
		s[#s+1] = text:sub(i,i+chunkSize - 1)
	end
	return s
end

local function toBits(num,bits)
	-- returns a table of bits, most significant first.
	bits = bits or math.max(1, select(2, math.frexp(num)))
	local t = {} -- will contain the bits        
	for b = bits, 1, -1 do
		t[b] = math.fmod(num, 2)
		num = math.floor((num - t[b]) / 2)
	end
	local binary = ""
	for _,i in pairs(t) do
		binary = binary .. i
	end
	return binary
end

local function Base64ToByteArray(base64)
	local bin = ""
	local CurrentByte = 0
	local strlen = #base64
	for i=1, strlen do
		CurrentByte = charmap2[string.sub(base64, i,i)] - 1
		bin = bin .. toBits(CurrentByte,6)
		--print(toBits(CurrentByte,6))
	end

	local chunks = splitByChunk(bin, 8)
	local ByteArray = {}
	for i=1, #chunks do
		ByteArray[i] = tonumber(chunks[i], 2)
	end
	--print(string.format("%06x", hex))
	return ByteArray
end

--print(Base64ToByteArray("//////"))
-- Load JPEG
--local result = HTTP_SERVICE:GetAsync(url)
--Base64
local base64 = ""
-- Read bytes
local bytes = Base64ToByteArray(base64)

--[[
for i = 1, string.len(result) do
	bytes[i] = string.byte(string.sub(result, i, i))
end
--]]


local jpeg = CreateJPEGfromBytes(bytes, false, true, true)

if jpeg == "Not supported." then
	warn("JPEG type not supported.")
	return
end

local width = jpeg.ImageWidth
local height = jpeg.ImageHeight
local data = jpeg.ImageData

-- Downscale Image

local timingStart = tick()

local downscaleFactor = math.max(1, math.max(width, height) / preferredMaxPixels)

local adjustedWidth = math.floor(width / downscaleFactor)
local adjustedHeight = math.floor(height / downscaleFactor)

local downscaledImage = {}
downscaledImage.Width = adjustedWidth
downscaledImage.Height = adjustedHeight
downscaledImage.Data = {}

for x = 1, adjustedWidth do
	downscaledImage.Data[x] = table.create(adjustedHeight, {})

	for y = 1, adjustedHeight do
		local xx = math.floor(x * downscaleFactor)
		local yy = math.floor(y * downscaleFactor)

		local r, g, b = jpeg.GetPixel(xx, yy)

		downscaledImage.Data[x][y] = { r, g, b, 0, false }
	end
end

local timingEnd = tick()
print("DOWNSCALED IMAGE IN: " .. timingEnd - timingStart .. "s")

-- Compress Image

local timingStart = tick()

local compressedImage = {}

for x = 1, downscaledImage.Width do
	for y = 1, downscaledImage.Height do
		local pixel = downscaledImage.Data[x][y]

		if pixel[5] == true then -- Already visited
			continue
		end

		-- Explore
		local rangeX = 0
		local rangeY = 0

		local tryX = 0
		local tryY = 0

		local stop = false

		for i = 1, 40 do
			local startA = 0
			local startB = 0

			-- Expand range
			if tryX >= tryY then
				startB = tryY
				tryY = tryY + 1
			else
				startA = tryX
				tryX = tryX + 1
			end

			-- Check bounds
			if x + tryX > downscaledImage.Width or y + tryY > downscaledImage.Height then
				break
			end

			for a = startA, tryX do
				if stop then
					break
				end

				for b = startB, tryY do
					if a == 0 and b == 0 then
						continue
					end

					local near = downscaledImage.Data[x + a][y + b]

					-- Already visited
					if near[5] == true then
						stop = true
						break
					end

					-- Color delta
					local distance = GetDeltaE(
						{ pixel[1], pixel[2], pixel[3] },
						{ near[1], near[2], near[3] }
					)

					if distance > compressionLevel then
						stop = true
						break
					end
				end
			end

			if stop then
				break
			end

			rangeX = tryX
			rangeY = tryY
		end

		-- Merge
		for a = 0, rangeX do
			for b = 0, rangeY do
				local nX = x + a
				local nY = y + b

				if nX <= downscaledImage.Width and nY <= downscaledImage.Height then
					downscaledImage.Data[nX][nY][5] = true
				end
			end
		end

		-- Trim edge
		if x + rangeX > downscaledImage.Width or y + rangeY > downscaledImage.Height then
			local overflow = Vector2.new(x + rangeX + 1, y + rangeY + 1) - Vector2.new(downscaledImage.Width, downscaledImage.Height)

			overflow = Vector2.new(
				math.max(0, overflow.X),
				math.max(0, overflow.Y)
			)

			rangeX = rangeX - overflow.X
			rangeY = rangeY - overflow.Y
		end

		table.insert(
			compressedImage,
			{
				x, y, -- Position of pixel
				rangeX + 1, rangeY + 1, -- Size of pixel
				pixel[1], pixel[2], pixel[3], pixel[4] -- Color
			}
		)
	end

	if x % 40 == 0 then
		wait(0)
	end
end

local timingEnd = tick()
print("COMPRESSED IMAGE IN: " .. timingEnd - timingStart .. "s")

-- Display Image

local maxAxisSize = 0

if downscaledImage.Height > downscaledImage.Width then
	maxAxisSize = downscaledImage.Height
else
	maxAxisSize = downscaledImage.Width
end

local function CreatePart(x, y, width, height, color, transparency)
	local size = 30 / maxAxisSize

	local offsetX = width * 0.5 * size
	local offsetY = height * 0.5 * size

	local part = Instance.new("Part", workspace.Image)
	part.Anchored = true
	part.CanTouch = false
	part.CanCollide = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = false
	part.Size = Vector3.new(size, size * height, size * width)
	part.Color = color
	part.Material = Enum.Material.Neon

	part.Position = Vector3.new(
		0,
		(-y * size) + (size * 3.5) - offsetY + (downscaledImage.Height * size),
		(x * size) + (size * 1.5) + offsetX
	)

	return part
end

function to_color(hex)
	local r, g, b = hex:match("(%w%w)(%w%w)(%w%w)")
	r = (tonumber(r, 16) or 0)
	g = (tonumber(g, 16) or 0)
	b = (tonumber(b, 16) or 0)
	return Color3.fromRGB(r,g,b)
end

local function putPixel(x, y, color)
	x = math.floor(x)
	y = math.floor(y)
	
	if pcall(function()
		imagetodisplay[y][x] = to_color(color)
	end) then
	end
	--[[
	if((y < imageHeight and y > 0) and (x < imageWidth and x > 0) ) then
		
	end
	--]]
end

local timingStart = tick()

local function ConvertToNeonRGB(r, g, b)
	r = r / 255
	g = g / 255
	b = b / 255

	r = math.pow(r, 0.65) * 150
	g = math.pow(g, 0.65) * 150
	b = math.pow(b, 0.65) * 150

	r = r * 0.75
	g = g * 0.75
	b = b * 0.75

	r = r + 25
	g = g + 25
	b = b + 25

	return r, g, b
end

for i, pixel in pairs(compressedImage) do
	local r = pixel[5]
	local g = pixel[6]
	local b = pixel[7]

	r, g, b = ConvertToNeonRGB(r, g, b)
	
	--[[
	CreatePart(
		pixel[1], pixel[2], -- Position
		pixel[3], pixel[4], -- Size
		Color3.fromRGB(r, g, b), -- Color
		pixel[8] -- Transparency
	)
	--]]
	
	putPixel(pixel[1], pixel[2], Color3.fromRGB(r, g, b))

	if i % 2000 == 0 then
		wait(0)
	end
end

local timingEnd = tick()
print("DISPLAYED IMAGE IN: " .. timingEnd - timingStart .. "s")

-- Print stats

print("Stats:")
print(" - Original resolution: " .. jpeg.ImageWidth .. "x" .. jpeg.ImageHeight)
print(" - Downscaled resolution: " .. downscaledImage.Width .. "x" .. downscaledImage.Height)
print(" - Total pixels shown: " .. #compressedImage)
print(" - Compression ratio: " .. (downscaledImage.Width * downscaledImage.Height) / #compressedImage)
