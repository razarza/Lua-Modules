---
-- @Liquipedia
-- wiki=commons
-- page=Module:MatchTicker
--
-- Please see https://github.com/Liquipedia/Lua-Modules to contribute
--

--todo:
-- - display
--	--> if > 2 opponents or only TBD/Empty opponents display round instead (prep for battle royale)
-- - custom

local Array = require('Module:Array')
local Class = require('Module:Class')
local Lua = require('Module:Lua')
local Logic = require('Module:Logic')
local Table = require('Module:Table')
local Team = require('Module:Team')

local Opponent = require('Module:OpponentLibraries').Opponent

local Condition = require('Module:Condition')
local ConditionTree = Condition.Tree
local ConditionNode = Condition.Node
local Comparator = Condition.Comparator
local BooleanOperator = Condition.BooleanOperator
local ColumnName = Condition.ColumnName

local DEFAULT_LIMIT = 20
local LIMIT_INCREASE = 20
local DEFAULT_ODER = 'date asc, liquipediatier asc, tournament asc'
local DEFAULT_RECENT_ORDER = 'date desc, liquipediatier asc, tournament asc'
local DEFAULT_LIVE_HOURS = 3
local NOW = os.date('%Y-%m-%d %H:%M', os.time(os.date('!*t') --[[@as osdateparam]]))
local DEFAULT_QUERY_COLUMNS = {
	'match2opponents',
	'winner',
	'pagename',
	'tournament',
	'tickername',
	'icon',
	'icondark',
	'date',
	'liquipediatier',
	'liquipediatiertype',
	'publishertier',
	'vod',
	'stream',
	'extradata',
	'parent',
	'finished',
	'bestof',
	'match2id',
	'match2bracketdata',
}

---@enum tickerDisplayModes
local TICKER_DISPLAY_MODES = {
	player = 'participant',
	team = 'participant',
	participant = 'participant',
	tournament = 'tournament',
	plain = 'plain',
	default = 'plain',
}

---@class MatchTickerConfig
---@field tournaments string[]
---@field limit integer
---@field order string
---@field player string?
---@field team string?
---@field displayMode tickerDisplayModes
---@field maximumLiveHoursOfMatches integer
---@field queryColumns string[]
---@field additionalConditions string
---@field recent boolean
---@field upcoming boolean
---@field ongoing boolean
---@field onlyExact boolean
---@field hasOpponent boolean
---@field linkLeftOpponent boolean
---@field queryByParent boolean
---@field showAllTbdMatches boolean

---@class MatchTicker
---@field args table
---@field config MatchTickerConfig
local MatchTicker = Class.new(function(self, args) self:init(args) end)

MatchTicker.displayComponents = Lua.import('Module:MatchTicker/DisplayComponents', {requireDevIfEnabled = true})

---@param args any
---@return table
function MatchTicker:init(args)
	self.args = args

	local config = {
		tournaments = Array.extractValues(
			Table.filterByKey(args, function(key) return string.find(key, '^tournament%d-$') ~= nil end)
		),
		queryByParent = Logic.readBool(args.queryByParent),
		limit = tonumber(args.limit) or DEFAULT_LIMIT,
		order = args.order or (Logic.readBool(args.recent) and DEFAULT_RECENT_ORDER or DEFAULT_ODER),
		player = args.player and mw.ext.TeamLiquidIntegration.resolve_redirect(args.player) or nil,
		team = args.team,
		displayMode = TICKER_DISPLAY_MODES[args.displayMode] or TICKER_DISPLAY_MODES.default,
		maximumLiveHoursOfMatches = tonumber(args.maximumLiveHoursOfMatches) or DEFAULT_LIVE_HOURS,
		queryColumns = args.queryColumns or DEFAULT_QUERY_COLUMNS,
		additionalConditions = args.additionalConditions or '',
		recent = Logic.readsBool(args.recent),
		upcoming = Logic.readBool(args.upcoming),
		ongoing = Logic.readBool(args.upcoming),
		onlyExact = Logic.readBool(Logic.emptyOr(args.onlyExact, true)),
		hasOpponent = Logic.isNotEmpty(args.player or args.team),
		linkLeftOpponent = Logic.readBool(Logic.emptyOr(args.linkLeftOpponent, Logic.isEmpty(args.player or args.team))),
	}

	assert(config.recent or config.upcoming or config.ongoing and
		not (config.recent and config.upcoming and config.ongoing),
		'Invalid recent, upcoming, ongoing combination')

	config.showAllTbdMatches = Logic.readBool(Logic.nilOr(args.showAllTbdMatches,
		Table.isEmpty(config.tournaments)))

	self.config = config

	return self
end

---queries the matches and filters them for unwanted ones
---@return table[]
function MatchTicker:query()
	local matches = mw.ext.LiquipediaDB.lpdb('match2', {
		conditions = self:buildQueryConditions(),
		order = self.config.order,
		query = table.concat(self.config.queryColumns, ','),
		limit = self.config.limit + LIMIT_INCREASE,
	})

	if type(matches[1]) == 'table' then
		return Array.sub(MatchTicker:filterMatches(matches), 1, self.config.limit)
	end

	mw.logObject(matches)
	return {}
end

---@return string
function MatchTicker:buildQueryConditions()
	local config = self.config
	local conditions = ConditionTree(BooleanOperator.all)

	if Table.isNotEmpty(config.tournaments) then
		local tournamentConditions = ConditionTree(BooleanOperator.any)
		local lpdbField = config.queryByParent and 'parent' or 'pagename'

		Array.forEach(config.tournaments, function(tournament)
			tournamentConditions:add{{ConditionNode(ColumnName(lpdbField), Comparator.eq, tournament)}}
		end)

		conditions:add(tournamentConditions)
	end

	if config.player then
		local underScorePlayer = config.player:gsub(' ', '_')
		conditions:add(ConditionTree(BooleanOperator.any):add{
			ConditionNode(ColumnName('opponent'), Comparator.eq, config.player),
			ConditionNode(ColumnName('opponent'), Comparator.eq, underScorePlayer),
			ConditionNode(ColumnName('player'), Comparator.eq, config.player),
			ConditionNode(ColumnName('player'), Comparator.eq, underScorePlayer),
		})
	end

	local teamPages = config.team and Team.queryHistoricalNames(config.team)
	if teamPages then
		local teamConditions = ConditionTree(BooleanOperator.any)

		Array.forEach(teamConditions, function (team)
			local teamWithUnderScore = team:gsub(' ', '_')
			teamConditions:add{
				ConditionNode(ColumnName('opponent'), Comparator.eq, team),
				ConditionNode(ColumnName('opponent'), Comparator.eq, teamWithUnderScore),
			}
		end)

		conditions:add(teamConditions)
	end

	conditions:add(self:dateConditions())

	return conditions:toString() .. config.additionalConditions
end

---@return ConditionTree
function MatchTicker:dateConditions()
	local config = self.config

	local dateConditions = ConditionTree(BooleanOperator.all)

	if config.onlyExact then
		dateConditions:add{ConditionNode(ColumnName('dateexact'), Comparator.eq, 1)}
	end

	if config.recent then
		return dateConditions:add({
			ConditionNode(ColumnName('finished'), Comparator.eq, 1),
			ConditionNode(ColumnName('date'), Comparator.lt, NOW),
		})
	end

	dateConditions:add{ConditionNode(ColumnName('finished'), Comparator.eq, 0)}

	if config.ongoing then
		local secondsLive = config.maximumLiveHoursOfMatches * 3600
		local timeStamp = os.date('%Y-%m-%d %H:%M', os.time(os.date('!*t') --[[@as osdateparam]]) - secondsLive)

		dateConditions:add{ConditionNode(ColumnName('date'), Comparator.gt, timeStamp)}

		if config.upcoming then return dateConditions end

		return dateConditions:add{ConditionNode(ColumnName('date'), Comparator.lt, NOW)}
	end

	--case upcoming
	return dateConditions:add{ConditionNode(ColumnName('date'), Comparator.gt, NOW)}
end

---Overwritable per wiki decision
---@param matches table[]
---@return table[]
function MatchTicker:filterMatches(matches)
	--remove matches with empty/BYE opponents
	matches = Array.filter(matches, function(match)
		return Array.any(match.match2opponents, Opponent.isBye)
	end)

	if self.config.showAllTbdMatches then
		return matches
	end

	local previousMatchWasTbd
	Array.forEach(matches, function(match)
		local isTbdMatch = Array.all(match.match2opponents, function(opponent)
			return Opponent.isTbd(opponent) or Opponent.isEmpty(opponent)
		end)
		if isTbdMatch and previousMatchWasTbd then
			match.isTbdMatch = true
		elseif isTbdMatch then
			previousMatchWasTbd = true
		else
			previousMatchWasTbd = false
		end
	end)

	return Array.filter(matches, function(match) return not match.isTbdMatch end)
end

return MatchTicker
