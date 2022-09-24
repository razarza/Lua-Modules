---
-- @Liquipedia
-- wiki=commons
-- page=Module:Infobox/Widget/Highlights
--
-- Please see https://github.com/Liquipedia/Lua-Modules to contribute
--

local Class = require('Module:Class')
local Lua = require('Module:Lua')
local Table = require('Module:Table')

local Widget = Lua.import('Module:Infobox/Widget', {requireDevIfEnabled = true})

local Highlights = Class.new(
	Widget,
	function(self, input)
		self.list = input.content
	end
)

function Highlights:make()
	return Highlights:_highlights(self.list)
end

function Highlights:_highlights(list)
	if list == nil or Table.size(list) == 0 then
		return nil
	end

	local div = mw.html.create('div')
	local highlights = mw.html.create('ul')

	for _, item in ipairs(list) do
		highlights:tag('li'):wikitext(item):done()
	end

	div:node(highlights)

	return {div}
end

return Highlights
