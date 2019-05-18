local bit = require "bit"
local palette = { }

local function rgb2index(r, g, b)
    for i=0, #palette - 1 do
        local color = palette[i]
        if color[1] == r and color[2] == g and color[3] == b then
            return i
        end
    end
    error("Color {" .. r ..',' .. g .. ',' .. b .. " } doesn't match palette. Image may have been loaded improperly.")
end

--TODO: identify color depth and read the header properly.
-- Eg. it could not actually have a palette.
local function set_palette(data)
    local bin = data:read()
    local palette_hdr_pos = bin:find("PLTE")
    local palette_size = bin:byte(palette_hdr_pos - 1)
    local palette_start = palette_hdr_pos + 4
    for i=0, palette_size / 3 do -- 3 is bytes per color, could be different
        palette[i] = {
            bin:byte(palette_start + i * 3),
            bin:byte(palette_start + 1 + i * 3),
            bin:byte(palette_start + 2 + i * 3)
        }
    end
end

--in 2bpp a row contains 8 pixels, so this functions receives a table with 8 indices
local function convert_to_2bpp(row)
    local byte_h, byte_l = 0, 0
    for pos=0, 7, 1 do
        local lbit = bit.band(row[pos + 1], 0x01)                   -- index & 0b01
        local hbit = bit.rshift(bit.band(row[pos + 1], 0x02), 1)    -- (index & 0b10) << 1
        byte_h = bit.bor(byte_h, bit.lshift(hbit, 7 - pos))         --  v position --> 
        byte_l = bit.bor(byte_l, bit.lshift(lbit, 7 - pos))         -- [] [] [] [] [] [] [] [] | byte
    end
    return byte_l, byte_h
end

local function generate()
    local bin = imagedata:getString()
    local bits_per_pixel = 2
    local row_size = 8 --px
    local rows_per_sprite = 8
    local src_components = 4 --rgba
    local sheet_width, sheet_height = imagedata:getDimensions()
    local hor_tiles = sheet_width / row_size
    local vert_tiles = sheet_height / rows_per_sprite
    assert(((hor_tiles % 1) == 0.0) and ((vert_tiles % 1) == 0.0), "Please use an image with the correct dimensions for the sprite format.")

    local ffi = require "ffi"

    local out_data = love.data.newByteData((sheet_height * sheet_width * bits_per_pixel) / 8)
    local rows = ffi.cast("uint8_t*", out_data:getPointer())

    local row_counter = 0
    for y=0, vert_tiles - 1 do 
        for x = 0, hor_tiles - 1 do --iterate on tiles from left to right, top to bottom
            for ty=0, rows_per_sprite - 1 do
                local row = {}
                for tx=0, (row_size * src_components) - 1, src_components do
                    -- kinda stupid but had to multiply by 4 cause it was easier than rewriting the loop
                    local pixel_index = ((((y * rows_per_sprite) + ty) * sheet_width * 4) + (x * row_size * 4) + tx) + 1 
                    table.insert(row, rgb2index(bin:byte(pixel_index, pixel_index + 2))) --here we ignore alpha for obv reasons
                end
                assert(row_counter < out_data:getSize(), row_counter)
                rows[row_counter], rows[row_counter + 1] = convert_to_2bpp(row)
                row_counter = row_counter + 2
            end

        end
    end
    local success, message = love.filesystem.write( "imgdump-" .. love.math.random() .. ".bin", out_data )
    if not success then 
        love.window.showMessageBox("Failed to write file.", message, "error") 
    else
        love.system.openURL(love.filesystem.getSaveDirectory())
    end
end

local button
function love.load()
    print(love.filesystem.getSaveDirectory())
    local font = love.filesystem.getInfo("BitPotion.ttf") and love.graphics.newFont("BitPotion.ttf", 48) or love.graphics.newFont(40)
    instruction_text = love.graphics.newText(font, "Drag your image here.")
    generate_text = love.graphics.newText(font, "Generate")
    love.graphics.setDefaultFilter("nearest", "nearest")
    love.graphics.setBackgroundColor(0.14, 0.14, 0.14)
    love.window.setTitle("imgdump - convert png to (indexed) binary")

    button = {
        status = "idle",
        width = generate_text:getWidth() + 25,
        height = generate_text:getHeight() + 15,
        x = love.graphics.getWidth() / 2,
        y = (love.graphics.getHeight() / 2) + 70,
        text = generate_text
    }
end


local function drawButton(self)
    local x, y, width, height, status, text = self.x, self.y, self.width, self.height, self.status, self.text
    local text_x, text_y = x - (text:getWidth() / 2), y - (text:getHeight() / 2)
    if status == "idle" then
        love.graphics.setColor(0.95,0.95,0.95)
        love.graphics.rectangle('line', x - (width / 2), y - (height / 2), width, height)
        love.graphics.setColor(1.0,1.0,1.0)
        love.graphics.draw(generate_text, text_x, text_y)
    end
    if status == "hover" then
        local line_width = love.graphics.getLineWidth()
        love.graphics.setColor(0.95,0.95,0.95)
        love.graphics.rectangle('line', x - (width / 2), y - (height / 2), width, height)
        love.graphics.setColor(0.30,0.30,0.30)
        love.graphics.rectangle('fill', (x - (width / 2)) + line_width, (y - (height / 2)) + line_width, width - (line_width * 2), height - (line_width * 2))
        love.graphics.setColor(1.0,1.0,1.0)
        love.graphics.draw(generate_text, text_x, text_y)
    end
    if status == "down" then
        love.graphics.setColor(0.95,0.95,0.95)
        love.graphics.rectangle('fill', x - (width / 2), y - (height / 2), width, height)
        love.graphics.setColor(0.14,0.14,0.14)
        love.graphics.draw(generate_text, text_x, text_y)
        love.graphics.setColor(1.0,1.0,1.0)
    end
end

local img
function love.draw()
    local text_width, text_height = instruction_text:getDimensions()
    local screen_width, screen_height = love.graphics.getDimensions()
    love.graphics.draw(instruction_text, (screen_width / 2) - (text_width / 2), (screen_height / 2) - (text_height / 2))
    if img then
        love.graphics.draw(img, 0,0)
        for i=0, #palette - 1 do
            local color = palette[i]
            love.graphics.setColor(color[1] / 255, color[2] / 255, color[3] / 255)
            love.graphics.rectangle('fill', i * 20, screen_height - 20, 20, 20) 
            love.graphics.setColor(1.0, 1.0, 1.0)
        end
        drawButton(button)
    end
end

function love.mousereleased(x, y, mbutton)
    if mbutton == 1 and button.status == "down" then
        generate()
    end
end
function love.update(dt)
    local mx, my = love.mouse.getPosition()
    if  mx > (button.x - (button.width / 2)) and 
        my > (button.y - (button.height / 2)) and
        mx < (button.x + (button.width / 2)) and
        my < (button.y + (button.height / 2)) then

        if love.mouse.isDown(1) then
            button.status = "down"
        else
            button.status = "hover"
        end
    else
        button.status = "idle"
    end
end


function love.filedropped(file)
    set_palette(file) 
    imagedata = love.image.newImageData(file)
    img = love.graphics.newImage(imagedata)
end
