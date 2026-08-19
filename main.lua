-- EXP Share Modes for Gen1Recomp.
-- Adds four configurable battle EXP distribution rules.
--
-- One battle.exp_award hook serves every generation the engine compiles: it is
-- raised with the same ctx on Red/Blue/Yellow (src/battle/BattleState.lua
-- awardExp) and on Gold/Silver/Crystal (src/battle/gen2/Battle.lua
-- awardExperience).  ctx.applyShare(mon, split) pays a single mon through the
-- engine's own award flow -- message, level-up stats window, move learning,
-- happiness, battle.exp_gained -- so the distribution rules below carry no
-- generation-specific internals.

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

  mod.log:info("EXP Share Modes loaded (default: Classic Even Split)")
end