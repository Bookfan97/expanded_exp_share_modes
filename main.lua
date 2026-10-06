-- EXP Share Modes for Gen1Recomp.
-- Adds four configurable battle EXP distribution rules.
--
-- Gen 1 and Gen 2 share the battle.exp_award hook: it is raised with the same
-- ctx on Red/Blue/Yellow (src/battle/BattleState.lua awardExp) and on
-- Gold/Silver/Crystal (src/battle/gen2/Battle.lua awardExperience).
-- ctx.applyShare(mon, split) pays a single mon through the engine's own award
-- flow -- message, level-up stats window, move learning, happiness,
-- battle.exp_gained -- so the distribution rules carry no generation-specific
-- internals there.
--
-- Gen 3 (FireRed/LeafGreen/Ruby/Sapphire/Emerald) uses a per-recipient
-- exp.gain hook instead, so this mod wraps that hook on Gen 3 boots and
-- returns the adjusted amount for each eligible mon.

local function partyOf(battle)
  if battle.game and battle.game.save and battle.game.save.party then
    return battle.game.save.party
  end
  return battle.party or {}
end

local function livingParty(battle)
  local out = {}
  for _, mon in ipairs(partyOf(battle)) do
    if not mon.isEgg and (tonumber(mon.hp) or 0) > 0 then
      out[#out + 1] = mon
    end
  end
  return out
end

local function planFor(mode, ctx)
  local alive = {}
  for _, mon in ipairs(ctx.alive or {}) do alive[#alive + 1] = mon end
  local aliveSet = {}
  for _, mon in ipairs(alive) do aliveSet[mon] = true end

  local batch = {}
  local function pay(mon, split)
    batch[#batch + 1] = { mon, math.max(1, split or 1) }
  end

  if mode == "off" then
    -- only the mons that fought, split as vanilla does without EXP.ALL
    for _, mon in ipairs(alive) do pay(mon, ctx.participants) end
  elseif mode == "classic" then
    local living = livingParty(ctx.battle)
    for _, mon in ipairs(living) do pay(mon, #living) end
  elseif mode == "even" then
    for _, mon in ipairs(alive) do pay(mon, ctx.participants) end
    for _, mon in ipairs(livingParty(ctx.battle)) do
      if not aliveSet[mon] then pay(mon, 1) end
    end
  else -- "modern"
    for _, mon in ipairs(alive) do pay(mon, ctx.participants) end
    local bench = {}
    for _, mon in ipairs(livingParty(ctx.battle)) do
      if not aliveSet[mon] then bench[#bench + 1] = mon end
    end
    local split = #bench * 2 -- one separate 50% pool, divided evenly
    for _, mon in ipairs(bench) do pay(mon, split) end
  end

  return batch
end

-- Classic Even Split only: every living member gets the same share, so the
-- active battler (when it survived) keeps its own "gained" line and the
-- rest collapse into one summary.  even/modern pay fighters and bench
-- different amounts and keep the per-mon lines.
local function summaryLine(amount)
  return "The rest of your party each received "
    .. (tonumber(amount) or 0) .. " EXP. Points!"
end

local function expOf(mon, gen2)
  return gen2 and (mon.experience or 0) or (mon.exp or 0)
end

local function classicDistribute(ctx, applyShare, batch)
  local battle = ctx.battle
  local gen2 = not battle.game
  local active = battle.player and (battle.player.mon or battle.player)
  local split = #batch

  if gen2 then
    local activeIndex
    for index, candidate in ipairs(battle.party or {}) do
      if candidate == active then activeIndex = index break end
    end
    -- giveExperiencePass emits the "gained" text per mon with no kill
    -- switch, so prune every experience event we added except the active
    -- battler's and emit the summary message in its place.
    local prev = #battle.events
    local amount, activeEvent
    for _, share in ipairs(batch) do applyShare(share[1], split, true) end
    for i = prev + 1, #battle.events do
      local ev = battle.events[i]
      if ev.kind == "experience" then
        amount = amount or ev.amount
        if not activeEvent and activeIndex and ev.index == activeIndex then
          activeEvent = i
        end
      end
    end
    for i = #battle.events, prev + 1, -1 do
      local ev = battle.events[i]
      if ev.kind == "experience" and i ~= activeEvent then
        table.remove(battle.events, i)
      end
    end
    battle:emit({ kind = "message", text = summaryLine(amount) })
    return
  end

  local key = active
  local inBatch = false
  for _, share in ipairs(batch) do
    if share[1] == key then inBatch = true break end
  end
  if not inBatch then key = batch[1][1] end
  local before = expOf(key, false)
  for _, share in ipairs(batch) do
    applyShare(share[1], split, share[1] == active)
  end
  battle:sayNext(summaryLine(expOf(key, false) - before))
end

local function modeOf(mod)
  local mode = tostring(mod.options:get("mode") or "classic")
  if mode == "off" or mode == "classic" or mode == "modern" or mode == "even" then
    return mode
  end
  return "classic"
end

-- Gen 3 detection: the loader exposes the current generation on mod.generation.
local function isGen3(mod)
  return tonumber(mod.generation) == 3
end

-- Gen 2's ctx.applyShare bakes in `halved` (true whenever anyone holds
-- EXP.SHARE), so its pool is taxed before our split runs.  Pay through the
-- engine's own pass with halved=false so the item never alters the pool --
-- matching Gen 1, where our award simply never runs the EXP.ALL pass.
local function applyShareFor(ctx)
  local battle = ctx.battle
  if battle.game then return ctx.applyShare end

  local def = battle:speciesDef(ctx.loser)
  local party = battle.party
  return function(mon, split)
    for index, candidate in ipairs(party) do
      if candidate == mon then
        return battle:giveExperiencePass(ctx.loser, def, { index },
          math.max(1, split or 1), false)
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Gen 3 support (FireRed/LeafGreen/Ruby/Sapphire/Emerald)
-- Gen 3 raises exp.gain per eligible recipient instead of battle.exp_award.
-- The engine only calls the hook for participants and EXP.SHARE holders, so
-- modes apply within that set; the pool itself is not taxed by EXP.SHARE.
-- ---------------------------------------------------------------------------

local function livingPartyG3(battle)
  local out = {}
  local party = battle and battle.playerParty or {}
  for i = 1, 6 do
    local mon = party[i]
    if mon and not mon.isEgg and (tonumber(mon.hp) or 0) > 0 then
      out[#out + 1] = mon
    end
  end
  return out
end

local function partyIndexOfG3(battle, mon)
  local party = battle and battle.playerParty or {}
  for i = 1, 6 do
    if party[i] == mon then return i end
  end
  return nil
end

local function isParticipantG3(ctx)
  local parts = ctx.loser and ctx.loser.participants
  return type(parts) == "table" and parts[ctx.index] == true
end

local function fullPoolG3(ctx)
  local yield = tonumber(ctx.defeatedDef and ctx.defeatedDef.expYield) or 0
  local level = math.max(1, tonumber(ctx.level) or 1)
  return math.max(0, math.floor(yield * level / 7))
end

local function divideFloorPositive(num, denom)
  if num <= 0 then return 0 end
  denom = math.max(1, denom)
  return math.max(1, math.floor(num / denom))
end

local function baseAmountForModeG3(mode, ctx)
  local full = fullPoolG3(ctx)
  local participant = isParticipantG3(ctx)
  local participants = math.max(1, tonumber(ctx.participants) or 1)
  local living = livingPartyG3(ctx.battle)
  local livingCount = math.max(1, #living)

  local benchCount = 0
  for _, mon in ipairs(living) do
    local pi = partyIndexOfG3(ctx.battle, mon)
    local isPart = pi and ctx.loser and ctx.loser.participants and ctx.loser.participants[pi] == true
    if not isPart then benchCount = benchCount + 1 end
  end
  benchCount = math.max(1, benchCount)

  if mode == "off" then
    return participant and divideFloorPositive(full, participants) or 0
  elseif mode == "classic" then
    return divideFloorPositive(full, livingCount)
  elseif mode == "even" then
    return participant and divideFloorPositive(full, participants) or full
  else -- "modern"
    return participant and divideFloorPositive(full, participants)
      or divideFloorPositive(full, benchCount * 2)
  end
end

local function applyPerMonBoostsG3(amount, ctx)
  if amount <= 0 then return 0 end
  if ctx.luckyEgg then amount = math.floor(amount * 150 / 100) end
  if ctx.isTrainer then amount = math.floor(amount * 150 / 100) end
  if ctx.traded then amount = math.floor(amount * 150 / 100) end
  return math.max(1, amount)
end

local function amountForModeG3(mode, ctx)
  return applyPerMonBoostsG3(baseAmountForModeG3(mode, ctx), ctx)
end

return function(mod)
  mod.options:define({
    {
      key = "mode",
      label = "EXP SHARE MODE",
      type = "choice",
      default = "classic",
      choices = {
        { "OFF", "off" },
        { "CLASSIC EVEN SPLIT", "classic" },
        { "MODERN PROGRESSIVE", "modern" },
        { "EVEN SPLIT", "even" },
      },
    },
  })

  mod.hooks:wrap("battle.exp_award", function(next, ctx)
    if not (ctx and ctx.applyShare) then return next(ctx) end

    local mode = modeOf(mod)
    local ok, batch = pcall(planFor, mode, ctx)
    if not ok then
      -- pure failure: nothing was paid, fall back to vanilla without double-award
      mod.log:warn("EXP Share Modes plan failed (%s); using vanilla award",
        tostring(batch))
      return next(ctx)
    end

    local applyShare = applyShareFor(ctx)
    local applied = pcall(function()
      if mode == "classic" then
        classicDistribute(ctx, applyShare, batch)
        return
      end
      for _, share in ipairs(batch) do
        -- `true` announce: Gen 1's applyShare only prints the "gained N EXP.
        -- Points!" line when this is set; Gen 2 ignores it.
        applyShare(share[1], share[2], true)
      end
    end)
    if not applied then
      -- partial award is already made; never run vanilla on top of it
      mod.log:warn("EXP Share Modes award failed partway; leaving award as applied")
    end
  end)

  -- Gen 3 uses a per-recipient exp.gain hook.  Register it only on Gen 3
  -- boots so it does not double-award on Gen 1/2, where battle.exp_award
  -- already handles distribution.
  if isGen3(mod) then
    mod.hooks:wrap("exp.gain", function(next, ctx)
      if not (ctx and ctx.mon and ctx.index and ctx.battle) then
        return next(ctx)
      end

      local mode = modeOf(mod)
      local ok, amount = pcall(amountForModeG3, mode, ctx)
      if not ok then
        mod.log:warn("EXP Share Modes Gen 3 amount failed (%s); using vanilla amount",
          tostring(amount))
        return next(ctx)
      end
      return amount
    end)
  end

  mod.log:info("EXP Share Modes loaded (default: Classic Even Split)")
end
