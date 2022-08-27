local charstring = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local charmap = {}
local charmap2 = {}

for i=1, #charstring do
	charmap[i] = string.sub(charstring, i, i)
	charmap2[charmap[i]] = i
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

local function HexToBin(somestr)
	local bin = ""
	local ByteArray = {}
	local strlen = #somestr
	for i=1, strlen do
		ByteArray[i] = tonumber(string.sub(somestr, i,i), 16)
		bin = bin .. toBits(ByteArray[i], 4)
	end
	print(bin)
	return bin 
end

local function splitByChunk(text, chunkSize)
	local s = {}
	for i=1, #text, chunkSize do
		s[#s+1] = text:sub(i,i+chunkSize - 1)
	end
	return s
end

local function BinToBase64(bin)
	local chunks = splitByChunk(bin, 6)
	local CurrentByte = 0
	local base64 = ""
	for i,v in pairs(chunks) do
		CurrentByte = tonumber(v, 2)
		print(CurrentByte)
		base64 = base64 .. charmap[CurrentByte+1]
	end
	return base64
end

local function RGBHexToBase64(hex)
	return BinToBase64(HexToBin(hex))
end

print(RGBHexToBase64("ffffff"))

local function Base64ToRGBHex(base64)
	local bin = ""
	local CurrentByte = 0
	local strlen = #base64
	for i=1, strlen do
		CurrentByte = charmap2[string.sub(base64, i,i)] - 1
		bin = bin .. toBits(CurrentByte,6)
	end
	local hex = tonumber(bin, 2)
	--print(string.format("%06x", hex))
	return string.format("%06x", hex)
end

Base64ToRGBHex("////")
print(Base64ToRGBHex(RGBHexToBase64("000000")))
--print(charmap)