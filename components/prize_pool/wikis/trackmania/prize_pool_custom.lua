---
-- @Liquipedia
-- wiki=trackmania
-- page=Module:PrizePool/Custom
--
-- Please see https://github.com/Liquipedia/Lua-Modules to contribute
--

local Arguments = require('Module:Arguments')
local Array = require('Module:Array')
local Class = require('Module:Class')
local Lua = require('Module:Lua')
local String = require('Module:StringUtils')
local Variables = require('Module:Variables')

local PrizePool = Lua.import('Module:PrizePool', {requireDevIfEnabled = true})

local LpdbInjector = Lua.import('Module:Lpdb/Injector', {requireDevIfEnabled = true})
local CustomLpdbInjector = Class.new(LpdbInjector)

local CustomPrizePool = {}

local PRIZE_TYPE_POINTS = 'POINTS'
local PRIZE_TITLE_WORLD_TOUR = 'WT'

local TIER_VALUE = {8, 4, 2}
local TYPE_MODIFIER = {Online = 0.65}

-- Template entry point
function CustomPrizePool.run(frame)
	local args = Arguments.getArgs(frame)

	args.syncPlayers = true

	local prizePool = PrizePool(args):create()

	prizePool:setLpdbInjector(CustomLpdbInjector())

	return prizePool:build()
end

function CustomLpdbInjector:adjust(lpdbData, placement, opponent)
	lpdbData.weight = CustomPrizePool.calculateWeight(
		lpdbData.prizemoney,
		Variables.varDefault('tournament_liquipediatier'),
		placement.placeStart,
		Variables.varDefault('tournament_type')
	)

	local worldTourPoints = Array.filter(placement.parent.prizes, function (prize)
		if prize.type == PRIZE_TYPE_POINTS and prize.data.title == PRIZE_TITLE_WORLD_TOUR then
			return true
		end
	end)[1]

	if worldTourPoints then
		lpdbData.extradata.prizepoints = placement:getPrizeRewardForOpponent(opponent, worldTourPoints.id)
		lpdbData.extradata.prizepointsTitle = 'wt_points'
	end

	Variables.varDefine(lpdbData.participant:lower() .. '_prizepoints', lpdbData.extradata.prizepoints)
	Variables.varDefine(lpdbData.participant:lower() .. '_prizepointsTitle', lpdbData.extradata.prizepointsTitle)

	return lpdbData
end

function CustomPrizePool.calculateWeight(prizeMoney, tier, place, type)
	if String.isEmpty(tier) then
		return 0
	end

	local tierValue = TIER_VALUE[tonumber(tier)] or 1

	return tierValue * (prizeMoney * 1000 + 1000 - place) / place * (TYPE_MODIFIER[type] or 1)
end

return CustomPrizePool
