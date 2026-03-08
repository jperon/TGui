-- SPDX-License-Identifier: MIT
-- Copyright (c) 2025 jperon

-- Localize standard library functions for minor performance gain and clarity
local concat = table.concat
local remove = table.remove
local insert = table.insert
local type = type
local select = select
local tostring = tostring
local pairs = pairs

-- HTML5 void elements (never need a closing tag)
local VOID = {
	area=true, base=true, br=true, col=true, embed=true, hr=true,
	img=true, input=true, link=true, meta=true, param=true,
	source=true, track=true, wbr=true,
}

local html = {
	__index = function(self, k)
		-- k is the HTML tag name (e.g., "div", "p")
		return function(...)
			local childrenContent = {}
			local attributeStrings = {}

			for i = 1, select('#', ...) do
				local arg = select(i, ...)
				local argType = type(arg)

				if argType == "table" then
					-- Array part of the table contains child elements/content.
					-- This loop consumes the array part of 'arg' by removing elements.
					while #arg > 0 do
						insert(childrenContent, remove(arg, 1))
					end
					-- Remaining key-value pairs in 'arg' are treated as attributes.
					for attrKey, attrValue in pairs(arg) do
						insert(attributeStrings, " " .. tostring(attrKey) .. "=\"" .. tostring(attrValue) .. "\"")
					end
				elseif argType == "function" then
					insert(childrenContent, arg()) -- Execute function and add its result as content
				elseif argType == "string" or argType == "number" then
					-- Add string or number directly as content.
					-- table.concat will handle converting numbers to strings later.
					insert(childrenContent, arg)
				-- Other types (boolean, nil, userdata, thread) passed as direct arguments are ignored.
				end
			end

			local attributesHtml = concat(attributeStrings) -- Joins attribute strings (e.g., " id='x'" .. " class='y'")

			if VOID[k] then
				-- True void elements: self-closing (no content, no closing tag)
				return "<" .. k .. attributesHtml .. "/>"
			else
				-- All other elements always use open+close tags, even when empty.
				-- (Self-closing syntax for non-void elements is invalid HTML5 and
				-- browsers treat it as an opening tag, making subsequent siblings children.)
				local contentHtml = concat(childrenContent, '\n')
				return "<" .. k .. attributesHtml .. ">" .. contentHtml .. "</" .. k .. ">"
			end
		end
	end
}
return setmetatable(html, html)
