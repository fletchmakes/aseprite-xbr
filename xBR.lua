-- MIT License

-- Copyright (c) 2022 David Fletcher

-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:

-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.

-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.


-- much of this was transposed from: https://github.com/carlosascari/2xBR-Filter/blob/master/xbr.js
-- I cannot take credit for the original algorithm OR this implementation
-- I simply re-wrote the JavaScript code in Lua
    

----------------
-- SETUP
----------------
-- establish constants and weights
local SCALE = 2

local REDMASK = 0x000000FF
local GREENMASK = 0x0000FF00
local BLUEMASK = 0x00FF0000
local ALPHAMASK = 0xFF000000

local Y_WEIGHT = 48
local U_WEIGHT = 7
local V_WEIGHT = 6

-- function to convert int32 to Pixel "object"
local function Pixel(value)
    local pixel = {}
    if (not value) or (value ~= value) then pixel.value = 0
    else pixel.value = value end
    pixel.red =    value & REDMASK
    pixel.green = (value & GREENMASK) >> 8
    pixel.blue =  (value & BLUEMASK)  >> 16
    pixel.alpha = (value & ALPHAMASK) >> 24

    return pixel
end

-- function to return the absolute value of a number
local function abs(x)
    local mask = x >> 31
    x = x ^ mask
    x = x - mask
    return x
end

-- function to calculate the weighted difference between two pixels
-- 
-- 3 steps:
-- -- 1. Finds absolute color diference between two pixels.
-- -- 2. Converts color difference into Y'UV, seperating color from light.
-- -- 3. Applies Y'UV thresholds, giving importance to luminance.
local function d(pixelA, pixelB)
    local r = math.abs(pixelA.red - pixelB.red)
    local g = math.abs(pixelA.green - pixelB.green)
    local b = math.abs(pixelA.blue - pixelB.blue)
    local y = r *  0.299000 + g *  0.587000 + b *  0.114000
    local u = r * -0.168736 + g * -0.331264 + b *  0.500000
    local v = r *  0.500000 + g * -0.418688 + b * -0.081312
    local weight = (y * Y_WEIGHT) + (u * U_WEIGHT ) + (v * V_WEIGHT)

    return weight
end

-- function to blend 2 pixels together
local function blend(pixelA, pixelB, alpha)
    local reverseAlpha = 1 - alpha
    local r = (alpha * pixelB.red)   + (reverseAlpha * pixelA.red)
    local g = (alpha * pixelB.green) + (reverseAlpha * pixelA.green)
	local b = (alpha * pixelB.blue)  + (reverseAlpha * pixelA.blue)
    local value = (r | g << 8 | b << 16 | -16777216)
    return Pixel(value)
end

-- applies the xBR filter
local function applyFilter(image, srcX, srcY, srcW, srcH)
    local scaledWidth = srcW * SCALE
    local scaledHeight = srcH * SCALE
    local scaledImage = Image(scaledWidth, scaledHeight)

    -- main loop
    for x=0,srcW do
        for y=0,srcH do
            -- Matrix: 11 is (0, 0) .. the current pixel
            -- 		     -2 | -1|  0| +1| +2 	(x)
            --    ______________________________
            --    -2 |      [ 1][ 2][ 3]
            --    -1 |	[ 4][ 5][ 6][ 7][ 8]
            --     0 |	[ 9][10][11][12][13]
            --    +1 |	[14][15][16][17][18]
            --    +2 |	    [19][20][21]
            --    (y)|
            local matrix = {}
            for i=1,21 do
                matrix[i] = { value = 0 }
            end
            matrix[ 1] = Pixel(image:getPixel(x-1, y-2))
			matrix[ 2] = Pixel(image:getPixel(  x, y-2))
			matrix[ 3] = Pixel(image:getPixel(x+1, y-2))
			matrix[ 4] = Pixel(image:getPixel(x-2, y-1))
			matrix[ 5] = Pixel(image:getPixel(x-1, y-1))
			matrix[ 6] = Pixel(image:getPixel(  x, y-1))
			matrix[ 7] = Pixel(image:getPixel(x+1, y-1))
			matrix[ 8] = Pixel(image:getPixel(x+2, y-1))
			matrix[ 9] = Pixel(image:getPixel(x-2,   y))
			matrix[10] = Pixel(image:getPixel(x-1,   y))
			matrix[11] = Pixel(image:getPixel(  x,   y))
			matrix[12] = Pixel(image:getPixel(x+1,   y))
			matrix[13] = Pixel(image:getPixel(x+2,   y))
			matrix[14] = Pixel(image:getPixel(x-2, y+1))
			matrix[15] = Pixel(image:getPixel(x-1, y+1))
			matrix[16] = Pixel(image:getPixel(  x, y+1))
			matrix[17] = Pixel(image:getPixel(x+1, y+1))
			matrix[18] = Pixel(image:getPixel(x+2, y+1))
			matrix[19] = Pixel(image:getPixel(x-1, y+2))
			matrix[20] = Pixel(image:getPixel(  x, y+2))
			matrix[21] = Pixel(image:getPixel(x+1, y+2))

            -- Calculate color weights using 2 points in the matrix
			local d_11_10 	= d(matrix[11], matrix[10])
			local d_11_6 	= d(matrix[11], matrix[6])
			local d_11_12  	= d(matrix[11], matrix[12])
			local d_11_16 	= d(matrix[11], matrix[16])
			local d_11_15 	= d(matrix[11], matrix[15])
			local d_11_7 	= d(matrix[11], matrix[7])
			local d_5_9 	= d(matrix[5],  matrix[9])
			local d_5_2 	= d(matrix[5],  matrix[2])
			local d_10_6 	= d(matrix[10], matrix[6])
			local d_10_16 	= d(matrix[10], matrix[16])
			local d_10_4 	= d(matrix[10], matrix[4])
			local d_6_12 	= d(matrix[6],  matrix[12])
			local d_6_1 	= d(matrix[6],  matrix[1])
			local d_11_5 	= d(matrix[11], matrix[5])
			local d_11_17 	= d(matrix[11], matrix[17])
			local d_7_13 	= d(matrix[7],  matrix[13])
			local d_7_2	    = d(matrix[7],  matrix[2])
			local d_12_16 	= d(matrix[12], matrix[16])
			local d_12_8 	= d(matrix[12], matrix[8])
			local d_6_3 	= d(matrix[6],  matrix[3])
			local d_15_9 	= d(matrix[15], matrix[9])
			local d_15_20 	= d(matrix[15], matrix[20])
			local d_16_19 	= d(matrix[16], matrix[19])
			local d_10_14 	= d(matrix[10], matrix[14])
			local d_17_13 	= d(matrix[17], matrix[13])
			local d_17_20 	= d(matrix[17], matrix[20])
			local d_16_21 	= d(matrix[16], matrix[21])
			local d_16_18 	= d(matrix[16], matrix[18])

            local new_pixel = 0
            local blended_pixel = 0

            -- Top Left Edge Detection Rule
			local a1 = (d_11_15 + d_11_7 + d_5_9  + d_5_2 + (4 * d_10_6))
			local b1 = (d_10_16 + d_10_4 + d_6_12 + d_6_1 + (4 * d_11_5))
			if (a1 < b1) then
                if (d_11_10 <= d_11_6) then new_pixel = matrix[10]
                else new_pixel = matrix[6] end

				blended_pixel = blend(new_pixel, matrix[11], 0.5)
				scaledImage:drawPixel(x * SCALE, y * SCALE, blended_pixel.value)
			else
				scaledImage:drawPixel(x * SCALE, y * SCALE, matrix[11].value)
            end

            -- Top Right Edge Detection Rule
            local a2 = (d_11_17 + d_11_5 + d_7_13 + d_7_2 + (4 * d_6_12))
            local b2 = (d_12_16 + d_12_8 + d_10_6 + d_6_3 + (4 * d_11_7))
            if (a2 < b2) then
                if (d_11_6 <= d_11_12) then new_pixel = matrix[6]
                else new_pixel = matrix[12] end

                blended_pixel = blend(new_pixel, matrix[11], 0.5)
                scaledImage:drawPixel(x * SCALE + 1, y * SCALE, blended_pixel.value)
            else
                scaledImage:drawPixel(x * SCALE + 1, y * SCALE, matrix[11].value)
            end

            -- Bottom Left Edge Detection Rule
            local a3 = (d_11_5 + d_11_17 +  d_15_9 + d_15_20 + (4 * d_10_16))
            local b3 = (d_10_6 + d_10_14 + d_12_16 + d_16_19 + (4 * d_11_15))
            if (a3 < b3) then
                if (d_11_10 <= d_11_16) then new_pixel = matrix[10]
                else new_pixel = matrix[16] end

                blended_pixel = blend(new_pixel, matrix[11], 0.5)
                scaledImage:drawPixel(x * SCALE, y * SCALE + 1, blended_pixel.value)
            else
                scaledImage:drawPixel(x * SCALE, y * SCALE + 1, matrix[11].value)
            end

            -- Bottom Right Edge Detection Rule
            local a4 = (d_11_7  + d_11_15 + d_17_13 + d_17_20 + (4 * d_12_16))
            local b4 = (d_10_16 + d_16_21 + d_16_18 + d_6_12  + (4 * d_11_17))
            if (a4 < b4) then
                if (d_11_12 <= d_11_16) then new_pixel = matrix[12]
                else new_pixel = matrix[16] end

                blended_pixel = blend(new_pixel, matrix[11], 0.5)
                scaledImage:drawPixel(x * SCALE + 1, y * SCALE + 1, blended_pixel.value)
            else
                scaledImage:drawPixel(x * SCALE + 1, y * SCALE + 1, matrix[11].value)
            end
        end
    end

    return scaledImage
end

----------------
-- MAIN LOGIC
----------------
local sourceSprite = app.activeSprite

-- grab the whole image by flattening, then undo the flattening
sourceSprite:flatten()
local sourceImage = app.activeImage:clone()
app.undo()

local scaledImage = applyFilter(sourceImage, 0, 0, sourceImage.width, sourceImage.height)
scaledImage:saveAs(sourceSprite.filename.."_SCALED.aseprite")

-- -- create a new sprite and scale
-- app.transaction( function() 

--     -- local scaledSprite = Sprite(sourceSprite.width * SCALE, sourceSprite.height * SCALE)

-- end )