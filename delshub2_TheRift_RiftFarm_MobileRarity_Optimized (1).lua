-- V58 MOBILE ULTRA CARRY + GENERAL GUARD GOD MODE REPAIR
-- VIP DELS HUB • V48 AUTO RETURN TO BASE
repeat task.wait() until game:IsLoaded()

-- ===================== IMPORTED FEATURE ENGINE =====================
-- Imported from STEAL AN EGG source; UI replaced by SAEGRR HUB UI.

-- 9  |  2026-09-13 06:09 UTC
--
-- GENERATED FILE - DO NOT EDIT.
-- Edit the modules in src/ and run: python tools/build.py
--
-- Modules in load order:
--   boot/00_runtime.lua                  177 lines
--   boot/01_log.lua                      204 lines
--   boot/02_scope.lua                    208 lines
--   boot/03_profile.lua                  190 lines
--   core/services.lua                     49 lines
--   core/net.lua                          74 lines
--   core/data.lua                        145 lines
--   core/profiles.lua                    401 lines
--   core/exec.lua                        330 lines
--   core/device.lua                      148 lines
--   core/character.lua                   105 lines
--   core/restore.lua                     158 lines
--   core/config.lua                       33 lines
--   core/state.lua                        19 lines
--   core/util.lua                         29 lines
--   ui/splash.lua                        600 lines
--   ui/stats.lua                        1084 lines
--   ui/window.lua                        262 lines
--   ui/tabs/home.lua                      67 lines
--   ui/tabs/main.lua                     359 lines
--   ui/tabs/farm.lua                     302 lines
--   ui/tabs/event.lua                    395 lines
--   ui/tabs/misc.lua                     137 lines
--   ui/tabs/config.lua                   201 lines
--   features/movement.lua                760 lines
--   features/humanoid.lua                251 lines
--   features/jump.lua                    127 lines
--   features/antideath.lua               171 lines
--   features/guard.lua                   287 lines
--   features/treadmill.lua               180 lines
--   features/farm/filter.lua             262 lines
--   features/farm/treadmill_on.lua       199 lines
--   features/farm/pets.lua                44 lines
--   features/esp/cards.lua               450 lines
--   features/esp/eggs.lua                175 lines
--   features/esp/plot.lua                257 lines
--   features/misc/servers.lua            308 lines
--   features/misc/webhook.lua            192 lines
--   features/misc/appearance.lua         349 lines
--   features/fps.lua                     394 lines
--   features/boss.lua                    332 lines
--   features/rift.lua                    789 lines
--   features/eggs.lua                    610 lines
--   features/grab.lua                    422 lines
--   features/instant.lua                 317 lines
--   features/plot.lua                    230 lines
--   features/regrab.lua                  196 lines
--   features/carry.lua                   216 lines
--   features/bait.lua                    364 lines
--   features/autosteal.lua              1010 lines
--   features/bossfight.lua              1187 lines
--   features/prewarm.lua                 139 lines
--   main.lua                             461 lines

local DELSHUB_VERSION = "4.2.0"
local DELSHUB_BUILD   = "MOBILE_DELTA_20260924_CLEAN_V60"


--[[ ==== boot/00_runtime.lua ========================================= ]]
-- =============================================================================
-- RUNTIME: module registry + single-instance guard
-- =============================================================================
--
-- Everything in this hub lives inside a module. A module is a NAME and a
-- FACTORY FUNCTION, and the factory does not run until something asks for the
-- module. Two things come out of that:
--
--   1. Every module body is its own function scope, so its locals are its own.
--      The old single-chunk build kept hitting Luau's ceiling -
--          Out of local registers ... exceeded 200
--      - and every new feature had to be contorted to avoid declaring a local.
--      That ceiling is per-scope, so it simply does not apply here.
--
--   2. A module that throws is caught by name. The failure names the module
--      instead of surfacing as a bare line number in an 18,000-line file.
--
-- Usage:
--     BX.module("core.util", function(BX)
--         local M = {}
--         function M.clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
--         return M
--     end)
--
--     local util = BX.require("core.util")

local env = (type(getgenv) == "function" and getgenv()) or _G

-- ONE INSTANCE AT A TIME.
--
-- Re-running the script (a second paste, a key-system loader firing twice, an
-- auto-exec on respawn) used to build a second copy of everything: another
-- window, another steal loop fighting the first for the character, and another
-- set of background loops. Doubled remote traffic and two movers arguing over
-- the same HumanoidRootPart - a good share of the old "it gets laggy after a
-- while" reports.
--
-- Each generation gets a number. Every loop checks its own generation and
-- returns the moment it is no longer current, so the previous copy unwinds
-- itself without needing to cooperate.
env.BlyxoGeneration = (env.BlyxoGeneration or 0) + 1

local BX = {
    generation  = env.BlyxoGeneration,
    version     = DELSHUB_VERSION,
    build       = DELSHUB_BUILD,
    _factories  = {},
    _loaded     = {},
    _loading    = {},
    _conns      = {},
}
env.BX = BX

-- True while this copy is still the newest one. Every long-running loop must
-- test this and return when it goes false.
function BX.alive()
    return env.BlyxoGeneration == BX.generation
end

function BX.module(name, factory)
    if BX._factories[name] then
        error(("duplicate module %q"):format(name), 2)
    end
    BX._factories[name] = factory
end

function BX.require(name)
    local cached = BX._loaded[name]
    if cached ~= nil then return cached end

    if BX._loading[name] then
        error(("circular dependency: %s"):format(name), 2)
    end
    local factory = BX._factories[name]
    if not factory then
        error(("no such module: %s"):format(name), 2)
    end

    BX._loading[name] = true
    local ok, result = pcall(factory, BX)
    BX._loading[name] = nil

    if not ok then
        -- Raised, not swallowed. A module that cannot build is a broken build,
        -- and the caller decides whether that is fatal. The name is in the
        -- message, which is the entire point of loading modules by name.
        error(("module %q failed to load: %s"):format(name, tostring(result)), 2)
    end
    if result == nil then
        error(("module %q returned nil (forgot to return M?)"):format(name), 2)
    end

    BX._loaded[name] = result
    return result
end

-- Connection bookkeeping. The old build leaked every Heartbeat/RenderStepped
-- handler it ever opened: re-executing left the previous copy's handlers
-- running every frame, holding all of its tables alive. Memory climbed with
-- each re-run. Anything connected through here is disconnected on teardown.
function BX.connect(signal, fn)
    local c = signal:Connect(fn)
    BX._conns[#BX._conns + 1] = c
    return c
end

-- RUN THIS SOMEWHERE ELSE, THEN COME BACK.
--
-- Roblox capability sandbox NARROWS a thread when it calls into game script
-- code, and the narrowing PERSISTS after the call returns. Once narrowed, the
-- thread can no longer touch Instances:
--
--     The current thread cannot access Instance (lacking capability Plugin)
--
-- So reading egg data (which requires and calls the game own modules) and then
-- writing to a UI element on the same thread throws - the read poisons the
-- thread for the write. V3.1 hit this exactly here, on dropdown Refresh.
--
-- coroutine.resume does NOT confine the narrowing; task.spawn does, because the
-- scheduler runs the closure as a genuinely separate thread we never resume
-- ourselves. So the game-code call happens over there and the caller thread
-- stays clean for the Instance write.
--
-- This YIELDS, so it must not be called from anywhere that cannot wait.
function BX.offthread(fn, timeout)
    local done, result = false, nil
    task.spawn(function()
        local ok, r = pcall(fn)
        if ok then result = r end
        done = true
    end)

    -- COUNT REAL SECONDS, NOT TICKS. V3.1 added 0.03 per iteration and compared
    -- that to the timeout as though task.wait(0.03) always took 0.03. It takes
    -- at least one frame, so on a phone at 15fps a "5 second" timeout ran 166
    -- iterations at 0.067s - eleven seconds of the main thread doing nothing.
    -- The slower the client, the longer it hangs, which is the wrong way round.
    local startedAt = os.clock()
    timeout = timeout or 5
    while not done and (os.clock() - startedAt) < timeout do
        task.wait(0.03)
    end
    return result, done
end

function BX.teardown()
    -- THE TAIL OF THE LOG, BEFORE ANYTHING ELSE IS DROPPED.
    --
    -- The trace file is written by a background flusher now rather than by every
    -- log line, so the last second of a retired copy is still only in memory.
    -- Writing it here is what keeps "what was it doing when I re-executed" in
    -- the file - and it has to happen before BX._loaded is cleared, because that
    -- is what the logger lives in.
    pcall(function()
        local lg = BX._loaded["boot.log"]
        if lg and lg.flushNow then lg.flushNow() end
    end)

    -- Scopes first: they own most of what the hub creates, and a scope's
    -- destroy cancels threads that would otherwise still be mid-loop while the
    -- rest of teardown runs.
    if BX.destroyAllScopes then pcall(BX.destroyAllScopes) end
    for _, c in ipairs(BX._conns) do
        pcall(function() c:Disconnect() end)
    end
    BX._conns = {}
    -- Drop the module instances too. Without this a retired copy of the hub
    -- keeps every table, cache and captured Instance its modules ever built,
    -- which is the "memory climbs with each re-execute" case.
    BX._loaded = {}
end

-- Retire whatever the previous copy left connected.
if type(env.BlyxoTeardown) == "function" then
    pcall(env.BlyxoTeardown)
end
env.BlyxoTeardown = BX.teardown

--[[ ==== boot/01_log.lua ============================================= ]]
-- =============================================================================
-- LOG: levels, module tags, and the replacement for silent pcall
-- =============================================================================
--
-- The V3.1 build had 478 pcall sites and 329 of them discarded the error
-- completely - bare `pcall(f)` with no `ok, err`. Those are where bugs went to
-- hide: a call would fail every frame and nothing anywhere said so.
--
-- BX.try is the fix. Same protection, but the failure is recorded with the
-- label of whatever was being attempted:
--
--     BX.try("carry.pickup", function() ... end)
--
-- and it is recorded ONCE per label per session, not once per frame - a
-- failure inside a Heartbeat handler would otherwise bury the log in seconds.
-- The repeat count is kept and reported at teardown.

BX.module("boot.log", function(BX)
    local M = {}

    local TRACE_FILE  = "BlyxoHub_trace.txt"
    local FLUSH_GAP   = 1.0   -- seconds between disk writes
    local RING        = 500   -- lines kept in memory

    local canWrite  = (type(writefile) == "function")
    local debugOn   = function()
        local env = (type(getgenv) == "function" and getgenv()) or _G
        return env.BlyxoDebug == true
    end

    local ring, ringN, ringHead = {}, 0, 0
    local flushAt     = 0
    local seen, seenN = {}, 0   -- label -> repeat count, for BX.try
    local SEEN_MAX    = 400     -- distinct labels before we stop adding new ones

    M.LEVELS = { TRACE = 1, INFO = 2, WARN = 3, ERROR = 4 }
    M.level  = M.LEVELS.INFO

    local function stamp()
        return ("%7.2f"):format(os.clock())
    end

    -- THE OLD BUILD'S WORST PERFORMANCE BUG LIVED HERE.
    --
    -- It concatenated the whole buffer and writefile'd it on EVERY trace call.
    -- A busy second meant dozens of full-log disk writes, each rebuilding a
    -- string of several kilobytes, on the same thread as the steal loop.
    --
    -- Writes are timed now. At worst the last second is missing after a kick,
    -- and session markers and errors flush immediately, so the head of a run
    -- and every failure are always on disk.
    --
    -- AND THE TIMED WRITE NO LONGER HAPPENS ON THE CALLER'S THREAD.
    --
    -- Measured on the live client: one writefile of the 7.7KB trace costs
    -- 1.5-2.6ms. Because emit() called flush() directly, whichever unlucky log
    -- line first crossed the one-second gap PAID for it - and on a UI callback
    -- that is 1.5-2.6ms added to a click for nothing the user asked for. Worse,
    -- every WARN forced a write with no gap at all, so a handler warning in a
    -- burst rewrote the whole buffer once per warning.
    --
    -- An INFO/TRACE/WARN line now only marks the buffer dirty and the flusher
    -- thread below does the write on its own time. ERROR and session markers
    -- still write through immediately, because those are precisely the lines
    -- that have to survive a crash one instant later.
    local dirty = false

    local function writeNow()
        if not canWrite then return end
        flushAt = os.clock()
        dirty = false
        -- Oldest first. The buffer is circular, so the read starts just past
        -- the write head once it has wrapped.
        local out, n = {}, 0
        local start = (ringN < RING) and 1 or (ringHead % RING) + 1
        for i = 0, ringN - 1 do
            n = n + 1
            out[n] = ring[((start - 1 + i) % RING) + 1]
        end
        pcall(writefile, TRACE_FILE, table.concat(out, "\n", 1, n))
    end

    -- force: write through now (ERROR, session markers).
    -- otherwise: mark it dirty and let the flusher thread deal with it.
    local function flush(force)
        if not canWrite then return end
        if force then return writeNow() end
        dirty = true
    end

    -- ONE THREAD FOR THE SESSION, AND IT YIELDS UNCONDITIONALLY.
    --
    -- Deliberately not a scope: the logger is infrastructure that outlives every
    -- feature and has to still be writing while a teardown is being logged.
    -- BX.alive() retires it when this copy of the hub is replaced, and the last
    -- buffer goes out on the way past so a re-execute never loses the tail.
    if canWrite then
        task.spawn(function()
            while BX.alive() do
                task.wait(FLUSH_GAP)
                if dirty then pcall(writeNow) end
            end
            if dirty then pcall(writeNow) end
        end)
    end

    -- For teardown, and for anyone who wants the file current right now.
    function M.flushNow() pcall(writeNow) end

    -- Written once, not rebuilt per call. The old version indexed a fresh
    -- {"TRACE","INFO",...} table literal on EVERY log line - a throwaway
    -- four-element table for each one.
    local TAGS = { "TRACE", "INFO", "WARN", "ERROR" }

    local function emit(level, mod, msg)
        if level < M.level then return end
        local line = ("[%s] %-5s %-16s %s"):format(stamp(), TAGS[level], mod, msg)

        -- CIRCULAR, NOT A SHIFTING ARRAY.
        --
        -- This was table.remove(ring, 1) once the buffer was full, which shifts
        -- all 500 elements down by one FOR EVERY LINE LOGGED. Over a long
        -- session that is the logger quietly becoming one of the more expensive
        -- things the hub does. A write index wrapping round costs nothing.
        ringHead = (ringHead % RING) + 1
        ring[ringHead] = line
        if ringN < RING then ringN = ringN + 1 end

        if debugOn() or level >= M.LEVELS.WARN then
            print("[DELSHUB] " .. line)
        end
        -- ERROR ONLY. A WARN used to force the whole buffer to disk on the
        -- calling thread, which is 1.5-2.6ms charged to whatever was running.
        flush(level >= M.LEVELS.ERROR)
    end

    -- A logger bound to one module name, so call sites stay short and every
    -- line says where it came from without the caller repeating itself.
    function M.for_module(name)
        return {
            trace = function(m, ...) emit(1, name, select("#", ...) > 0 and m:format(...) or m) end,
            info  = function(m, ...) emit(2, name, select("#", ...) > 0 and m:format(...) or m) end,
            warn  = function(m, ...) emit(3, name, select("#", ...) > 0 and m:format(...) or m) end,
            error = function(m, ...) emit(4, name, select("#", ...) > 0 and m:format(...) or m) end,
        }
    end

    function M.session(msg)
        emit(2, "session", "=== " .. msg .. " ===")
        flush(true)
    end

    function M.repeats()
        local out = {}
        for label, n in pairs(seen) do
            if n > 1 then out[#out + 1] = ("%s x%d"):format(label, n) end
        end
        table.sort(out)
        return out
    end

    -- BX.try - the replacement for bare pcall.
    --
    -- Protects the call the same way, but a failure is LOGGED against `label`
    -- rather than vanishing. Logged once; later failures of the same label
    -- only bump a counter, so a handler failing every frame costs one line.
    --
    -- Returns ok, result - so it substitutes directly for pcall at a call site
    -- that already checked the first return.
    function BX.try(label, fn, ...)
        local ok, result = pcall(fn, ...)
        if not ok then
            -- A label built from a changing value (an egg uid, a player name)
            -- would otherwise grow this table without limit for the whole
            -- session. Past the cap, new labels collapse into one bucket.
            if seen[label] == nil then
                if seenN >= SEEN_MAX then
                    label = "(other)"
                else
                    seenN = seenN + 1
                end
            end
            local n = (seen[label] or 0) + 1
            seen[label] = n
            if n == 1 then
                emit(4, "try", ("%s: %s"):format(label, tostring(result)))
            elseif n == 10 or n == 100 or n == 1000 then
                emit(3, "try", ("%s: still failing (x%d)"):format(label, n))
            end
        end
        return ok, result
    end

    -- Wrap a signal handler once; every invocation is protected and labelled.
    function BX.guard(label, fn)
        return function(...)
            return select(2, BX.try(label, fn, ...))
        end
    end

    M._emit = emit
    M._seen = seen
    return M
end)

--[[ ==== boot/02_scope.lua =========================================== ]]
-- =============================================================================
-- SCOPE: per-feature lifetime. Everything a feature creates, cleaned up.
-- =============================================================================
--
-- This is the answer to every leak class at once. A feature never connects,
-- spawns or creates directly; it does all of it through a scope, and when the
-- feature is switched off, the player respawns, or the script is re-executed,
-- ONE call takes the whole thing down.
--
--     local sc = BX.scope("features.autosteal")
--
--     sc:connect(RunService.Heartbeat, fn)   -- disconnected on destroy
--     sc:own(Instance.new("Highlight"))      -- destroyed on destroy
--     sc:spawn("label", fn)                  -- thread cancelled on destroy
--     sc:loop("label", 0.5, fn)              -- loop exits on destroy
--     sc:delay("label", 2, fn)               -- never fires after destroy
--     sc:tween(obj, 0.3, {...})              -- cancelled on destroy
--
--     sc:destroy()                           -- all of the above, gone
--
-- WHY THIS EXISTS. V3.1 had 59 :Connect calls and 26 :Disconnect calls. The
-- 33-connection gap is not a rounding error - those handlers ran for the rest
-- of the session, and every closure they held kept its tables alive. It had 17
-- `while true` loops, most with no exit condition beyond a generation check
-- that had to be remembered and written by hand at each site. Forgetting one
-- was invisible until the frame rate told you.
--
-- The rule for every module from here on: if it connects, spawns, loops,
-- delays, tweens or creates an Instance, it does so through its scope. A
-- module that does not touch a scope has nothing to leak.

BX._scopes = {}

function BX.scope(name)
    -- Re-entering a scope name always retires the previous one first. This is
    -- what makes a toggle safe to flip repeatedly and a feature safe to rebuild
    -- on respawn: there can never be two live copies of the same scope.
    local existing = BX._scopes[name]
    if existing and not existing.dead then existing:destroy() end

    local sc = {
        name    = name,
        dead    = false,
        conns   = {},
        insts   = {},
        threads = {},
        tweens  = {},
        gen     = BX.generation,
    }

    -- True while this scope AND this copy of the hub are both current. Every
    -- loop body should test it; sc:loop does that for you.
    function sc:alive()
        return (not self.dead) and BX.alive()
    end

    function sc:connect(signal, fn)
        if self.dead then return nil end
        local c = signal:Connect(fn)
        self.conns[#self.conns + 1] = c
        return c
    end

    function sc:own(inst)
        if self.dead then
            -- Created after the scope died: destroy it now rather than leak it.
            pcall(function() inst:Destroy() end)
            return inst
        end
        self.insts[#self.insts + 1] = inst
        return inst
    end

    -- A thread that is cancelled on destroy. The label is what shows up in the
    -- log if the body throws, so make it say which job this is.
    function sc:spawn(label, fn, ...)
        if self.dead then return nil end
        local th
        th = task.spawn(function(...)
            BX.try(self.name .. "/" .. label, fn, ...)
            -- Finished on its own: stop holding the thread reference so the
            -- closure and everything it captured can be collected.
            for i, t in ipairs(self.threads) do
                if t == th then table.remove(self.threads, i) break end
            end
        end, ...)
        self.threads[#self.threads + 1] = th
        return th
    end

    -- THE REPLACEMENT FOR `while true do ... end`.
    --
    -- Exits on its own when the scope dies or the hub is retired, so a disabled
    -- feature cannot keep a loop running and a re-execute cannot leave two of
    -- them fighting. A body that throws is logged once against its label and
    -- the loop keeps its cadence instead of dying silently.
    function sc:loop(label, interval, fn)
        return self:spawn(label .. "/loop", function()
            while self:alive() do
                BX.try(self.name .. "/" .. label, fn)
                if not self:alive() then return end
                task.wait(interval)
            end
        end)
    end

    -- A per-frame job. Same contract as :connect, but saying so at the call
    -- site is what lets the profiler time it: every handler registered here is
    -- measured and attributed by name, so the frame budget is known rather
    -- than argued about. See BX.profile.report().
    function sc:onFrame(label, signal, fn)
        local tag = self.name .. "/" .. label
        local guarded = BX.guard(tag, fn)
        local timed = BX.profile and BX.profile.wrap(tag, guarded) or guarded
        return self:connect(signal, timed)
    end

    function sc:delay(label, seconds, fn)
        if self.dead then return end
        task.delay(seconds, function()
            -- Checked at FIRE time, not at schedule time. A delay set up before
            -- a teardown must not fire into a destroyed feature - that is the
            -- "half of a feature still running" case.
            if not self:alive() then return end
            BX.try(self.name .. "/" .. label, fn)
        end)
    end

    function sc:tween(obj, t, props, style, dir)
        if self.dead then return nil end
        local tween
        BX.try(self.name .. "/tween", function()
            tween = BX.require("core.services").TweenService:Create(obj,
                TweenInfo.new(t, style or Enum.EasingStyle.Quint,
                    dir or Enum.EasingDirection.Out), props)
            tween:Play()
        end)
        if tween then self.tweens[#self.tweens + 1] = tween end
        return tween
    end

    function sc:destroy()
        if self.dead then return end
        self.dead = true

        for _, c in ipairs(self.conns) do pcall(function() c:Disconnect() end) end
        for _, t in ipairs(self.tweens) do pcall(function() t:Cancel() end) end
        for _, i in ipairs(self.insts) do pcall(function() i:Destroy() end) end
        -- NEVER CANCEL THE THREAD WE ARE STANDING ON.
        --
        -- A scope is very often destroyed from inside one of its own threads -
        -- a ticker that notices the feature was switched off and tears itself
        -- down. Cancelling the running thread there stops destroy() dead,
        -- half-done: connections dropped, Instances never destroyed. That is
        -- precisely the "one error leaves half a feature running" case, except
        -- it is not even an error.
        --
        -- The running thread is left alone. It is already unwinding, and
        -- self.dead is set, so any loop it is in exits at its next check.
        local me = coroutine.running()
        for _, th in ipairs(self.threads) do
            -- A thread blocked in task.wait is not reachable by its loop
            -- condition until it wakes; cancelling ends it now.
            if th ~= me then pcall(task.cancel, th) end
        end

        -- Drop every reference. Without this the scope table itself keeps the
        -- destroyed Instances, the dead threads and everything their closures
        -- captured alive for as long as the hub runs.
        self.conns, self.insts, self.threads, self.tweens = {}, {}, {}, {}

        if BX._scopes[self.name] == self then BX._scopes[self.name] = nil end
    end

    -- What the profiler and the audit command report on.
    function sc:counts()
        return {
            conns   = #self.conns,
            insts   = #self.insts,
            threads = #self.threads,
            tweens  = #self.tweens,
        }
    end

    BX._scopes[name] = sc
    return sc
end

-- Every live scope, smallest surface for "what is this hub currently holding".
function BX.scopeReport()
    local out = {}
    for name, sc in pairs(BX._scopes) do
        if not sc.dead then
            local c = sc:counts()
            out[#out + 1] = ("%-24s conns=%-3d insts=%-4d threads=%-3d tweens=%d")
                :format(name, c.conns, c.insts, c.threads, c.tweens)
        end
    end
    table.sort(out)
    return out
end

function BX.destroyAllScopes()
    for _, sc in pairs(BX._scopes) do
        pcall(function() sc:destroy() end)
    end
    BX._scopes = {}
end

--[[ ==== boot/03_profile.lua ========================================= ]]
-- =============================================================================
-- PROFILE: measure it, do not guess at it
-- =============================================================================
--
-- Every per-frame job registered through sc:onFrame is timed automatically, so
-- the frame budget is attributed to the feature that actually spends it rather
-- than argued about. Nothing here needs to be wired up by hand.
--
--     BX.profile.report()        -- one line per per-frame job, worst first
--     BX.profile.health()        -- memory, fps, scopes, connections, threads
--
-- THE LONG-SESSION CHECK. The sampler writes a health line into the trace file
-- every 60 seconds: memory, frame rate, live scope count, total connections and
-- total threads. On a healthy build those five numbers are flat across hours.
-- A leak shows up as a slow climb in connections or threads long before anyone
-- notices the frame rate, so the trace file answers "is it getting worse?"
-- without anybody having to sit and watch it.
--
-- Cost of the instrumentation itself: two os.clock() calls per handler per
-- frame. Set BX.profile.enabled = false to drop even that.

BX.profile = {
    enabled = true,
    _stats  = {},    -- label -> { n, total, max, last }
    _mem0   = nil,
    _t0     = os.clock(),
}

local P = BX.profile

-- WHAT WE OWN, TRACKED SEPARATELY FROM ROBLOX'S TOTAL.
--
-- Total process memory is mostly the game, and it oscillates by hundreds of MB
-- as the GC works - it can neither prove nor disprove a leak in the hub. A
-- module registers its caches here and the health line reports their sizes, so
-- "does anything grow with each steal or respawn" is answered by a number we
-- actually control rather than inferred from Roblox's heap.
--
--     BX.profile.watch("eggs.cache", function() return #list end)
P._watch = {}
function P.watch(name, fn) P._watch[name] = fn end
function P.watched()
    local out = {}
    for name, fn in pairs(P._watch) do
        local ok, n = pcall(fn)
        out[#out + 1] = ("%s=%s"):format(name, ok and tostring(n) or "?")
    end
    table.sort(out)
    return out
end

-- THE LIFE TIMELINE.
--
-- Marks are stamped at the points a cycle can die, each with the character's
-- health and humanoid state at that moment. When a run dies, the trace shows
-- WHICH mark it died after instead of leaving us to guess between the bait,
-- the anchor, the unanchor and the teleport.
P._marks = {}

function P.mark(name)
    local ok, health, state, swapped = pcall(function()
        local plr = game:GetService("Players").LocalPlayer
        local char = plr and plr.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum then return -1, "no-humanoid", false end
        return hum.Health, tostring(hum:GetState()):gsub("Enum.HumanoidStateType.", ""),
               hum:GetAttribute("BlyxoStealHum") == true
    end)
    local row = {
        name = name, at = os.clock(),
        health = ok and health or -1,
        state = ok and state or "?",
        swapped = ok and swapped or false,
    }
    P._marks[#P._marks + 1] = row
    if #P._marks > 200 then table.remove(P._marks, 1) end
    return row
end

function P.marksSince(t)
    local out = {}
    for _, r in ipairs(P._marks) do
        if r.at >= (t or 0) then
            out[#out + 1] = ("%s@%.2f hp=%.0f %s%s"):format(
                r.name, r.at - (t or 0), r.health, r.state, r.swapped and " swapped" or "")
        end
    end
    return out
end

function P.wrap(label, fn)
    local s = P._stats[label]
    if not s then
        s = { n = 0, total = 0, max = 0, last = 0 }
        P._stats[label] = s
    end
    return function(...)
        if not P.enabled then return fn(...) end
        local t0 = os.clock()
        fn(...)
        local dt = os.clock() - t0
        s.n = s.n + 1
        s.total = s.total + dt
        s.last = dt
        if dt > s.max then s.max = dt end
    end
end

-- Worst first, in milliseconds. `avg` is the number that matters for a smooth
-- frame; `max` catches the one-off spike that shows up as a stutter.
function P.report()
    local rows = {}
    for label, s in pairs(P._stats) do
        if s.n > 0 then
            rows[#rows + 1] = {
                label = label,
                avg   = (s.total / s.n) * 1000,
                max   = s.max * 1000,
                total = s.total,
                n     = s.n,
            }
        end
    end
    table.sort(rows, function(a, b) return a.total > b.total end)

    local out = { ("%-34s %8s %8s %9s %8s"):format("per-frame job", "avg ms", "max ms", "total s", "calls") }
    for _, r in ipairs(rows) do
        out[#out + 1] = ("%-34s %8.3f %8.3f %9.2f %8d")
            :format(r.label, r.avg, r.max, r.total, r.n)
    end
    return out
end

local function memMb()
    local ok, v = pcall(function()
        return game:GetService("Stats"):GetTotalMemoryUsageMb()
    end)
    if ok and type(v) == "number" then return v end
    ok, v = pcall(gcinfo)
    return (ok and type(v) == "number") and (v / 1024) or 0
end

function P.health()
    local conns, threads, scopes, insts = 0, 0, 0, 0
    for _, sc in pairs(BX._scopes or {}) do
        if not sc.dead then
            scopes = scopes + 1
            local c = sc:counts()
            conns   = conns + c.conns
            insts   = insts + c.insts
            threads = threads + c.threads
        end
    end
    local mem = memMb()
    P._mem0 = P._mem0 or mem
    return {
        uptime  = os.clock() - P._t0,
        mem     = mem,
        memGrow = mem - P._mem0,
        scopes  = scopes,
        conns   = conns,
        insts   = insts,
        threads = threads,
        loaded  = (function() local n = 0 for _ in pairs(BX._loaded) do n = n + 1 end return n end)(),
    }
end

function P.start()
    local sc  = BX.scope("boot.profile")
    local log = BX.require("boot.log").for_module("profile")
    local fps, frames, last = 0, 0, os.clock()

    sc:connect(BX.require("core.services").RunService.Heartbeat, function()
        frames = frames + 1
    end)

    sc:loop("health", 60, function()
        local now = os.clock()
        fps, frames, last = frames / math.max(now - last, 0.001), 0, now
        local h = P.health()
        -- One line, parseable, in the trace file. Flat numbers across a long
        -- session mean a clean build; a climb in conns or threads is a leak.
        local w = P.watched()
        log.info("health up=%.0fs fps=%.0f mem=%.0fMB (%+.0f) scopes=%d conns=%d insts=%d threads=%d%s",
            h.uptime, fps, h.mem, h.memGrow, h.scopes, h.conns, h.insts, h.threads,
            #w > 0 and (" | " .. table.concat(w, " ")) or "")
    end)

    return sc
end

--[[ ==== core/services.lua =========================================== ]]
-- Cached game services. Resolved once, in one place.
--
-- The old build called game:GetService in dozens of scattered spots, including
-- inside per-frame loops. GetService is cheap but not free, and more to the
-- point it meant no single place to see what the hub actually touches.
BX.module("core.services", function(BX)
    local log = BX.require("boot.log").for_module("services")
    local M = {}

    local WANTED = {
        "Players", "ReplicatedStorage", "RunService", "TweenService",
        "UserInputService", "Lighting", "Workspace", "HttpService",
        "CoreGui", "TextService", "Stats",
        -- Missing from this list until 2026-09-12: features/misc/servers.lua
        -- called svc.TeleportService:TeleportToPlaceInstance inside a pcall,
        -- so every server hop threw "attempt to index nil" and was logged as
        -- "teleport refused" - the buttons never worked on any build.
        "TeleportService",
    }

    for _, name in ipairs(WANTED) do
        local ok, svc = pcall(game.GetService, game, name)
        if ok and svc then
            M[name] = svc
        else
            -- Missing service is a real, reportable condition - not something
            -- to discover later as a nil index deep inside a feature.
            log.error("service unavailable: %s", name)
        end
    end

    -- WAIT FOR THE PLAYER, BOUNDED. An executor that runs auto-execute
    -- scripts before the client has finished joining sees Players.LocalPlayer
    -- as nil, and every module that captures svc.LocalPlayer at load then
    -- holds nil for the session - remotes, the character, ESP, all of it.
    -- Ten seconds is far more than a join takes; a genuine nil after that is
    -- reported by the services stage as the required failure it is.
    if M.Players and not M.Players.LocalPlayer then
        local deadline = os.clock() + 10
        while not M.Players.LocalPlayer and os.clock() < deadline do task.wait(0.1) end
        if M.Players.LocalPlayer then
            log.info("LocalPlayer arrived late (%.1fs) - waited for it", 10 - (deadline - os.clock()))
        else
            log.error("Players.LocalPlayer is still nil after 10s")
        end
    end
    M.LocalPlayer = M.Players and M.Players.LocalPlayer
    return M
end)

--[[ ==== core/net.lua ================================================ ]]
-- =============================================================================
-- CORE.NET: the game's own remotes, called safely
-- =============================================================================
--
--     local net = BX.require("core.net")
--     local ok, msg = net.call("RF/Treadmill/AskDoff")
--     local rf      = net.find("RF/Rift/AskState")
--
-- Every remote in this game lives in ReplicatedStorage.Packages.Networking with
-- its full name as the Instance name - "RF/Treadmill/AskDoff", not a nested
-- folder path. That container is resolved once and held.
--
-- WHY THIS IS ITS OWN MODULE NOW.
--
-- features/treadmill.lua carried this privately with a note saying "kept local
-- because this is currently the only caller; it moves to core/ the moment a
-- second feature needs it". Farm needs it twice - the treadmill hold and Equip
-- Best Pets - so it moves, rather than being copied a third time.
--
-- A MISSING REMOTE IS A RESULT, NOT AN ERROR.
--
-- The game renames and removes endpoints between updates. Every call returns
-- false plus a reason instead of throwing, so a feature built on an endpoint
-- that has gone away degrades to "refused" and says which name it wanted -
-- which is the difference between a legible failure and a silent one.

BX.module("core.net", function(BX)
    local svc = BX.require("core.services")
    local log = BX.require("boot.log").for_module("net")

    local M = {}

    local container, containerAt = nil, 0
    local CONTAINER_TTL = 30

    local function networking()
        local now = os.clock()
        if container and container.Parent and (now - containerAt) < CONTAINER_TTL then
            return container
        end
        local pkgs = svc.ReplicatedStorage:FindFirstChild("Packages")
        local net = pkgs and pkgs:FindFirstChild("Networking")
        container, containerAt = net, now
        return net
    end

    -- The remote Instance, or nil. Callers that need to connect to a RemoteEvent
    -- want this; callers that just want an answer want call().
    function M.find(name)
        local net = networking()
        return net and net:FindFirstChild(name) or nil
    end

    -- Returns the remote's own first return value, or false plus a reason. A
    -- refusal from the server and a missing endpoint are both "false, why".
    function M.call(name, ...)
        local rf = M.find(name)
        if not rf then return false, "remote not found: " .. tostring(name) end
        local ok, a, b = pcall(function(...) return rf:InvokeServer(...) end, ...)
        if not ok then return false, tostring(a) end
        return a, b
    end

    -- Fire-and-forget for a RemoteEvent.
    function M.fire(name, ...)
        local re = M.find(name)
        if not re then return false, "remote not found: " .. tostring(name) end
        local ok, err = pcall(function(...) re:FireServer(...) end, ...)
        if not ok then return false, tostring(err) end
        return true
    end

    return M
end)

--[[ ==== core/data.lua =============================================== ]]
-- =============================================================================
-- CORE.DATA: the game's own data modules, resolved once and correctly
-- =============================================================================
--
--     local data = BX.require("core.data")
--     data.assets()        -- Data.Assets   .Directory keyed by AssetCategory
--     data.areas()         -- Data.Areas    .Directory keyed by area id
--     data.eggState()      -- Client.EggState
--     data.assetEarnings() -- Shared.Util.AssetEarnings
--     data.plotState()     -- PlotState
--
-- WHY THIS EXISTS, AND IT IS NOT TIDINESS.
--
-- Three modules had their own private copy of:
--
--     local found = ReplicatedStorage:FindFirstChild(name, true)
--     return found and found:IsA("ModuleScript") and require(found) or nil
--
-- and for one name that is silently wrong. There is a FOLDER called
-- ReplicatedStorage.Assets and a MODULESCRIPT called ReplicatedStorage.Data.Assets.
-- A recursive FindFirstChild returns the folder - it is a direct child, so it is
-- reached first - the IsA check then fails, and the function returns nil without
-- ever looking further.
--
-- Measured on the live game before this fix, on every egg in the field:
--
--     Red Panda        rarity=?  kg=0  value=1607568  area=Cherry Blossom
--     Cyclops Gorilla  rarity=?  kg=0  value=1480986  area=Cosmic
--     Blade Head       rarity=?  kg=0  value=605224   area=Titan Temple
--
-- So egg RARITY and WEIGHT have never worked in this rebuild. Values and names
-- come from elsewhere and were fine, which is exactly why it went unnoticed:
-- nothing on screen depended on rarity until the Farm tab's filters.
--
-- V3.1 does not have this bug because it looks up a PATH - needModule(RS, "Data",
-- "Assets") - rather than a bare name.
--
-- THE RULE HERE: PATH FIRST, THEN A SEARCH THAT KEEPS LOOKING.
--
-- Each accessor names the path it expects. If the path moves, the fallback walks
-- the descendants for a ModuleScript of that name and, crucially, does not stop
-- at the first Instance that merely shares the name. Resolved once and held;
-- a miss is logged once, loudly, rather than becoming a "?" on screen.

BX.module("core.data", function(BX)
    local svc  = BX.require("core.services")
    local exec = BX.require("core.exec")
    local log  = BX.require("boot.log").for_module("data")

    local M = {}

    local cache = {}      -- key -> { mod = <required value> } or { missing = true }

    local function atPath(...)
        local node = svc.ReplicatedStorage
        for _, part in ipairs({ ... }) do
            if not node then return nil end
            node = node:FindFirstChild(part)
        end
        return node
    end

    -- A ModuleScript of this name ANYWHERE, ignoring same-named folders.
    local function searchModule(name)
        for _, d in ipairs(svc.ReplicatedStorage:GetDescendants()) do
            if d:IsA("ModuleScript") and d.Name == name then return d end
        end
        return nil
    end

    -- key: what to remember it as. path: where it is expected to be.
    local function resolve(key, path)
        local held = cache[key]
        if held then return held.mod end

        -- NO require() ON THIS EXECUTOR = NO WALK. Probed once by core.exec;
        -- without it there is nothing a descendants search could change, so
        -- the miss is recorded once, with the executor's own error.
        if not exec.can.gameRequire then
            log.error("cannot require game modules on this executor (%s) - %s unavailable",
                tostring(exec.gameRequireWhy), path[#path])
            cache[key] = { missing = true }
            return nil
        end

        local name = path[#path]
        local inst = atPath(table.unpack(path))
        if not (inst and inst:IsA("ModuleScript")) then
            inst = searchModule(name)
            if inst then
                log.warn("%s was not at %s - found it at %s",
                    name, table.concat(path, "."), inst:GetFullName())
            end
        end

        if not inst then
            cache[key] = { missing = true }
            log.error("could not resolve the game module %s (expected %s)",
                name, table.concat(path, "."))
            return nil
        end

        local mod
        local ok = BX.try("data.require." .. key, function() mod = require(inst) end)
        if not ok or type(mod) ~= "table" then
            cache[key] = { missing = true }
            log.error("%s could not be required", inst:GetFullName())
            return nil
        end

        cache[key] = { mod = mod }
        return mod
    end

    function M.assets()        return resolve("assets", { "Data", "Assets" }) end
    function M.areas()         return resolve("areas", { "Data", "Areas" }) end
    function M.eggState()      return resolve("eggState", { "Client", "EggState" }) end
    function M.assetEarnings() return resolve("assetEarnings", { "Shared", "Util", "AssetEarnings" }) end
    function M.plotState()     return resolve("plotState", { "Client", "PlotState" }) end
    function M.slotIdentity()  return resolve("slotIdentity", { "Shared", "Util", "AreaEggSlotIdentity" }) end

    -- .Directory is the shape both Assets and Areas share; nil when the module
    -- is missing, so callers degrade rather than throw.
    function M.assetsDir()
        local a = M.assets()
        return a and a.Directory or nil
    end

    function M.areasDir()
        local a = M.areas()
        return a and a.Directory or nil
    end

    -- What resolved and what did not, for the audit.
    function M.report()
        local out = {}
        for key, held in pairs(cache) do
            out[#out + 1] = key .. (held.missing and "=MISSING" or "=ok")
        end
        table.sort(out)
        return out
    end

    return M
end)

--[[ ==== core/exec.lua =============================================== ]]
-- =============================================================================
-- CORE.EXEC: what this executor can actually do
-- =============================================================================
--
-- Every executor-specific function is probed ONCE, here, and reached through a
-- wrapper that has a fallback or a clean "no". Nothing else in the hub calls
-- writefile, getcustomasset, setclipboard, getgc or request directly.
--
--     local exec = BX.require("core.exec")
--
--     if exec.can.files then ... end          -- capability flags
--     exec.writeFile(path, data)              -- false when unsupported
--     exec.readFile(path)                     -- nil when unsupported
--     exec.clipboard(text)                    -- tries four spellings
--     exec.httpRequest{ Url = ..., ... }      -- nil when unsupported
--     exec.gcScan()                           -- {} when unsupported
--
-- WHY THIS EXISTS AT ALL.
--
-- "It works on mine" is the single most expensive assumption in a script like
-- this. Executors disagree about which of these exist, what they are called,
-- what they return and whether they throw. V3.1 called them inline, in dozens
-- of places, each with its own ad-hoc pcall - so a missing function did not
-- disable one feature, it produced a different failure every place it was
-- touched, and mobile executors (which support the least) got the worst of it.
--
-- The rule: a missing capability disables THAT capability, never the hub.
--
-- Nothing here throws. Every function returns a value the caller can carry on
-- from, and the one-time report in the log says what this machine actually has,
-- which is the first thing worth knowing about any bug report.

BX.module("core.exec", function(BX)
    local log = BX.require("boot.log").for_module("exec")

    local M = {}

    -- SIMULATED DENIES, FOR TESTING THE DEGRADED PATHS ON A FULL EXECUTOR.
    --
    --     getgenv().BLYXO_CAPS_DENY = { prompts = true, files = true }
    --
    -- before executing makes those capabilities probe as missing, so "what
    -- does the hub do on an executor without fireproximityprompt" can be
    -- answered here instead of guessed. Reported in the diag line so a trace
    -- from a simulated run can never be mistaken for a real one.
    local env = (type(getgenv) == "function" and getgenv()) or _G
    local deny = type(env.BLYXO_CAPS_DENY) == "table" and env.BLYXO_CAPS_DENY or {}
    M.simulatedDenies = deny

    -- WHERE EXECUTOR GLOBALS ACTUALLY LIVE, AND WHY FOUR LOOKUPS.
    --
    -- The first cut read getfenv()[name], then _G[name], then rawget on
    -- getfenv(0). On an executor where getfenv is sandboxed or absent that is
    -- three misses in a row - executor functions are not in _G, and rawget
    -- skips the __index chain they are reached through - so EVERY capability
    -- probed as missing: files, request, prompts, clipboard. The hub then
    -- said "Config saving is not supported", sent no webhooks, refused
    -- server hops and refused prompt steals on a machine that had all of
    -- them. getgenv() is the executor's own global table and is the first
    -- place to look; a compiled `return <name>` is the last, because
    -- loadstring resolves the name exactly the way the executor's own
    -- scripts do.
    local function fn(name)
        if deny[name] then return nil end
        local ok, v
        ok, v = pcall(function() return type(getgenv) == "function" and getgenv()[name] or nil end)
        if not ok or type(v) ~= "function" then
            ok, v = pcall(function() return getfenv and getfenv()[name] or nil end)
        end
        if not ok or type(v) ~= "function" then
            ok, v = pcall(function() return (_G and _G[name]) end)
        end
        if not ok or type(v) ~= "function" then
            ok, v = pcall(function()
                local chunk = loadstring and loadstring("return " .. name)
                return chunk and chunk() or nil
            end)
        end
        return (ok and type(v) == "function") and v or nil
    end

    -- Resolved once. Names vary between executors, so each is a list of
    -- spellings in preference order.
    local function first(...)
        for _, name in ipairs({ ... }) do
            local f = fn(name)
            if f then return f, name end
        end
        return nil, nil
    end

    local f_writefile   = first("writefile")
    local f_readfile    = first("readfile")
    local f_isfile      = first("isfile")
    local f_delfile     = first("delfile")
    local f_isfolder    = first("isfolder")
    local f_makefolder  = first("makefolder")
    local f_listfiles   = first("listfiles")
    local f_customasset = first("getcustomasset", "getsynasset")
    local f_gethui      = first("gethui")
    local f_getgc       = first("getgc")
    local f_getconns    = first("getconnections")
    local f_hookfn      = first("hookfunction", "replaceclosure")
    local f_getrawmeta  = first("getrawmetatable")
    local f_queueport   = first("queue_on_teleport", "queueonteleport")
    local f_identify    = first("identifyexecutor", "getexecutorname")
    local f_fireprompt  = first("fireproximityprompt")

    local f_clip, clipName = first("setclipboard", "toclipboard", "set_clipboard", "setrbxclipboard")

    -- CAN THIS EXECUTOR require() THE GAME'S OWN ModuleScripts?
    --
    -- Everything that names an egg, prices it, or reads the field goes
    -- through require(ReplicatedStorage.<...>). Some executors refuse that
    -- outright, some only for non-public modules, and core.data used to
    -- discover it one module at a time with a descendants walk per miss.
    -- Probed once, on the first ModuleScript ReplicatedStorage has, so the
    -- answer is known before any feature asks.
    local canRequire, requireWhy = false, "no ModuleScript to probe"
    do
        local ok, err = pcall(function()
            local RS = game:GetService("ReplicatedStorage")
            local probe = RS:FindFirstChildWhichIsA("ModuleScript", true)
            if not probe then return end
            local r = require(probe)
            canRequire, requireWhy = true, probe:GetFullName()
        end)
        if not ok then requireWhy = tostring(err) end
        if deny.gameRequire then canRequire, requireWhy = false, "simulated deny" end
    end

    -- syn.request lives on a table rather than as a global, so it is probed
    -- separately before the plain spellings.
    local f_request, requestName
    do
        local ok, v = pcall(function() return syn and syn.request end)
        if ok and type(v) == "function" then
            f_request, requestName = v, "syn.request"
        else
            ok, v = pcall(function() return http and http.request end)
            if ok and type(v) == "function" then
                f_request, requestName = v, "http.request"
            else
                f_request, requestName = first("request", "http_request", "httprequest")
            end
        end
    end

    -- Files need the whole set, not just writefile: a partial implementation
    -- (write but no read, or no isfile) is worse than none, because caching
    -- logic then cannot tell a cached file from a missing one.
    M.can = {
        files      = (f_writefile and f_readfile and f_isfile) and true or false,
        folders    = (f_isfolder and f_makefolder) and true or false,
        listFiles  = f_listfiles and true or false,
        customAsset = f_customasset and true or false,
        hiddenUi   = f_gethui and true or false,
        gc         = f_getgc and true or false,
        connections = f_getconns and true or false,
        hooking    = (f_hookfn and f_getrawmeta) and true or false,
        clipboard  = f_clip and true or false,
        request    = f_request and true or false,
        teleportQueue = f_queueport and true or false,
        -- The prompt steal. fireproximityprompt is the fast path; without it
        -- the prompt is held through ProximityPrompt:InputHoldBegin/End,
        -- which is Roblox's own client API and exists everywhere. So this is
        -- true on every executor - `promptVia` says which path.
        prompts    = true,
        gameRequire = canRequire,
    }
    M.promptVia = f_fireprompt and "fireproximityprompt" or "InputHoldBegin"
    M.gameRequireWhy = requireWhy

    M.name = "unknown"
    if f_identify then
        local ok, n = pcall(f_identify)
        if ok and type(n) == "string" and #n > 0 then M.name = n end
    end

    ---------- wrappers ----------
    -- Every one of these is safe to call unconditionally.

    function M.hiddenParent()
        if f_gethui then
            local ok, ui = pcall(f_gethui)
            if ok and ui then return ui end
        end
        return BX.require("core.services").CoreGui
    end

    function M.writeFile(path, data)
        if not f_writefile then return false end
        return (BX.try("exec.writeFile", f_writefile, path, data))
    end

    function M.readFile(path)
        if not f_readfile then return nil end
        local ok, data = BX.try("exec.readFile", f_readfile, path)
        return ok and data or nil
    end

    function M.isFile(path)
        if not f_isfile then return false end
        local ok, yes = pcall(f_isfile, path)
        return ok and yes or false
    end

    -- nil when the executor cannot list a folder (some have files but no
    -- listfiles); an empty table when it can and the folder is empty.
    function M.listFiles(path)
        if not f_listfiles then return nil end
        local ok, files = BX.try("exec.listFiles", f_listfiles, path)
        if not ok or type(files) ~= "table" then return nil end
        return files
    end

    function M.deleteFile(path)
        if not f_delfile then return false end
        return (BX.try("exec.deleteFile", f_delfile, path))
    end

    -- Creates every level, because not all executors create parents for you.
    function M.ensureFolder(path)
        if not M.can.folders then return false end
        local built = ""
        for part in tostring(path):gmatch("[^/]+") do
            built = (built == "") and part or (built .. "/" .. part)
            local ok, exists = pcall(f_isfolder, built)
            if ok and not exists then
                if not BX.try("exec.makeFolder", f_makefolder, built) then return false end
            end
        end
        return true
    end

    function M.customAsset(path)
        if not f_customasset then return nil end
        local ok, id = BX.try("exec.customAsset", f_customasset, path)
        return ok and id or nil
    end

    -- Tries every spelling, not just the one this executor advertises: some
    -- expose the name but throw, which is only discoverable by calling it.
    function M.clipboard(text)
        for _, name in ipairs({ "setclipboard", "toclipboard", "set_clipboard", "setrbxclipboard" }) do
            local f = fn(name)
            if f and pcall(f, text) then return true end
        end
        return false
    end

    function M.httpRequest(opts)
        if not f_request then return nil end
        local ok, res = BX.try("exec.httpRequest", f_request, opts)
        return ok and res or nil
    end

    -- THE EXPENSIVE ONE. A getgc(true) sweep walks every live object - V3.1
    -- measured ~196,000 objects and 43ms on a desktop, and a phone is far
    -- worse. It is never called casually: callers must cache the result and
    -- re-sweep only when something has actually invalidated it.
    function M.gcScan(tablesOnly)
        if not f_getgc then return {} end
        local t0 = os.clock()
        local ok, objs = BX.try("exec.gcScan", f_getgc, tablesOnly and true or false)
        if not ok or type(objs) ~= "table" then return {} end
        local ms = (os.clock() - t0) * 1000
        M.lastGcMs = ms
        -- Loud on purpose. If this shows up often in a trace, something is
        -- sweeping the heap in a loop and that is always a bug.
        log.warn("gc sweep: %d objects in %.0fms", #objs, ms)
        return objs
    end

    -- The steal path. V3.1 called fireproximityprompt inline, so an executor
    -- without it produced a different failure at each call site instead of one
    -- clear "this executor cannot do prompt steals".
    function M.firePrompt(prompt, holdDuration)
        if f_fireprompt then
            return (BX.try("exec.firePrompt", f_fireprompt, prompt, holdDuration or 0))
        end
        -- THE FALLBACK IS THE ENGINE'S OWN API. InputHoldBegin starts the
        -- hold exactly as a key press does; after HoldDuration the prompt
        -- fires Triggered and InputHoldEnd releases it. Yields for the hold,
        -- which the callers already allow for (they pass the duration).
        return (BX.try("exec.firePrompt.hold", function()
            prompt:InputHoldBegin()
            local hold = tonumber(holdDuration)
            if hold == nil then hold = tonumber(prompt.HoldDuration) or 0 end
            if hold > 0 then task.wait(hold + 0.05) end
            prompt:InputHoldEnd()
        end))
    end

    function M.report()
        local have, missing = {}, {}
        for k, v in pairs(M.can) do
            table.insert(v and have or missing, k)
        end
        table.sort(have); table.sort(missing)
        local denied = {}
        for k in pairs(deny) do denied[#denied + 1] = tostring(k) end
        table.sort(denied)
        return {
            executor = M.name,
            have = have,
            missing = missing,
            denied = denied,
            promptVia = M.promptVia,
            gameRequireWhy = requireWhy,
        }
    end

    local r = M.report()
    log.info("executor=%s clipboard=%s request=%s prompts=%s gameRequire=%s (%s)",
        M.name, tostring(clipName), tostring(requestName), M.promptVia,
        tostring(canRequire), tostring(requireWhy))
    if #r.denied > 0 then
        log.warn("SIMULATED capability denies active: %s", table.concat(r.denied, ", "))
    end
    log.info("supported: %s", #r.have > 0 and table.concat(r.have, ", ") or "(none)")
    if #r.missing > 0 then
        -- Not an error. It is the single most useful line in a bug report from
        -- a machine that is not yours.
        log.warn("unsupported here: %s", table.concat(r.missing, ", "))
    end

    return M
end)

--[[ ==== core/device.lua ============================================= ]]
-- =============================================================================
-- CORE.DEVICE: what this machine can afford
-- =============================================================================
--
--     local dev = BX.require("core.device")
--
--     dev.tier          -- "low" | "mid" | "high", updated live
--     dev.isTouch       -- phone or tablet
--     dev.scale(0.25)   -- an interval, stretched for weaker machines
--     dev.budget(12)    -- a per-pass work allowance, cut for weaker machines
--     dev.onTier(sc, fn)-- called when the tier changes
--
-- WHY A TIER AND NOT A CONSTANT.
--
-- A loop tuned on a 144fps desktop is a different loop on a phone. V3.1 has
-- the scars: a mover that discarded any frame longer than 50ms silently halved
-- travel speed at 10fps, and a steal loop that never yielded froze phones and
-- emulators hardest. Numbers picked on one machine are not portable.
--
-- The tier is measured, not assumed - a "desktop" running at 22fps under a
-- recording program is a low-tier machine that day, and a modern tablet is not
-- a phone just because it has a touchscreen.
--
-- It is also HYSTERETIC and slow to move, for the same reason the stats colours
-- are: a tier that flips every few seconds would have features rebuilding
-- themselves constantly, which is itself a cost.

BX.module("core.device", function(BX)
    local svc = BX.require("core.services")
    local cfg = BX.require("core.config")
    local log = BX.require("boot.log").for_module("device")

    local M = {}

    M.isTouch = svc.UserInputService.TouchEnabled

    -- Screen size separates a phone from a tablet. A tablet is a PC-sized
    -- screen and generally a PC-sized budget; treating every touch device as a
    -- phone is what made V3.1's UI look wrong on iPads.
    local function shortSide()
        local cam = workspace.CurrentCamera
        local vp = cam and cam.ViewportSize
        if not vp or vp.Y < 10 then return 1080 end
        return math.min(vp.X, vp.Y)
    end
    M.smallScreen = shortSide() < 700

    -- Starting guess, replaced by measurement within a few seconds. A phone
    -- starts pessimistic so the first seconds of load are not the heaviest.
    M.tier = (M.isTouch and M.smallScreen) and "low" or "mid"
    M.fps = nil

    local MULT = { low = 2.2, mid = 1.35, high = 1.0 }

    -- An interval in seconds, stretched on weaker machines. A scan that is
    -- reasonable four times a second on a desktop is not on a phone, and the
    -- phone is exactly where the extra work turns into a stutter.
    function M.scale(seconds)
        return seconds * (MULT[M.tier] or 1.35)
    end

    -- A per-pass work allowance (how many things to build/check this pass),
    -- cut on weaker machines. Never returns less than 1: a budget of zero is a
    -- feature that silently does nothing.
    function M.budget(n)
        local share = (M.tier == "low" and 0.35) or (M.tier == "mid" and 0.7) or 1
        return math.max(1, math.floor(n * share + 0.5))
    end

    -- True when the machine is struggling badly enough that optional work
    -- should be skipped entirely this pass.
    function M.lite()
        return M.tier == "low"
    end

    local listeners = {}
    function M.onTier(sc, label, fn)
        listeners[#listeners + 1] = { scope = sc, label = label, fn = fn }
    end

    local function setTier(t)
        if M.tier == t then return end
        local was = M.tier
        M.tier = t
        log.info("tier %s -> %s (fps %.0f, touch=%s, short=%d)",
            was, t, M.fps or -1, tostring(M.isTouch), shortSide())
        for i = #listeners, 1, -1 do
            local L = listeners[i]
            if not L.scope or L.scope.dead then
                table.remove(listeners, i)
            else
                BX.try("device/" .. L.label, L.fn, t, was)
            end
        end
    end

    -- MEASURED, WITH HYSTERESIS AND A HOLD.
    --
    -- Same reasoning as the stats colours: one threshold means a machine
    -- sitting on it changes tier constantly. A tier also has to hold its new
    -- reading for two consecutive samples before it is adopted, so a single
    -- bad stretch (an asset load, a teleport) does not re-tier the hub.
    local sc = BX.scope("core.device")
    local frames = 0
    sc:connect(svc.RunService.Heartbeat, function() frames = frames + 1 end)

    local pending, pendingCount = nil, 0
    sc:loop("measure", 5, function()
        local fps = frames / 5
        frames = 0
        M.fps = M.fps and (M.fps + (fps - M.fps) * 0.4) or fps

        local want = M.tier
        if M.tier == "high" then
            if M.fps < 45 then want = "mid" end
        elseif M.tier == "mid" then
            if M.fps < cfg.LITE_FPS then want = "low"
            elseif M.fps > 75 then want = "high" end
        else
            if M.fps > 40 then want = "mid" end
        end

        -- A phone is never promoted to high, whatever it momentarily reports.
        -- A 120Hz phone can post excellent numbers while idle and still stall
        -- the moment real work starts.
        if want == "high" and M.isTouch and M.smallScreen then want = "mid" end

        if want == M.tier then
            pending, pendingCount = nil, 0
            return
        end
        if pending == want then
            pendingCount = pendingCount + 1
        else
            pending, pendingCount = want, 1
        end
        if pendingCount >= 2 then
            setTier(want)
            pending, pendingCount = nil, 0
        end
    end)

    log.info("start tier=%s touch=%s smallScreen=%s", M.tier,
        tostring(M.isTouch), tostring(M.smallScreen))

    -- MOBILE/DELTA PERFORMANCE CONTRACT:
    -- Touch + small screen clients never run the hub's cosmetic work at the
    -- display refresh rate. Gameplay movement/egg logic remains untouched;
    -- only visual animation cadence is reduced. The tier can still adapt to
    -- measured FPS, so a slow Android device gets the low profile automatically.
    function M.visualInterval(base)
        base = tonumber(base) or 0.05
        if M.tier == "low" then return math.max(base, 0.10) end
        if M.tier == "mid" then return math.max(base, 0.066) end
        return base
    end

    return M
end)

--[[ ==== core/character.lua ========================================== ]]
-- =============================================================================
-- CORE.CHARACTER: one place that knows about the character
-- =============================================================================
--
-- Respawning is where duplicate state comes from. Every feature that cared
-- about the character used to connect its own CharacterAdded handler, and each
-- respawn added another one - so after five deaths, five handlers rebuilt five
-- copies of the same thing, and every one of them held a reference to a
-- character that no longer existed.
--
-- There is one CharacterAdded connection in the hub, and it lives here.
--
--     local ch = BX.require("core.character")
--
--     ch.get()                        -- current character, or nil
--     ch.root()                       -- HumanoidRootPart, or nil
--     ch.humanoid()                   -- Humanoid, or nil
--     ch.onSpawn(sc, "label", fn)     -- fn(character) now and on every respawn
--
-- onSpawn takes the SCOPE that owns the callback, so a feature switched off
-- stops being called back - without that, a disabled feature quietly wakes up
-- again on the next respawn.

BX.module("core.character", function(BX)
    local svc = BX.require("core.services")
    local log = BX.require("boot.log").for_module("character")

    local M = {}
    local plr = svc.LocalPlayer

    -- Weak values: when the character is destroyed, nothing here is the reason
    -- it stays in memory. A strong reference to an old character (and through
    -- it, every part, every Animator, every track) is one of the largest single
    -- leaks a hub of this kind can have.
    local current = setmetatable({}, { __mode = "v" })

    local listeners = {}   -- { scope = sc, label = str, fn = fn }

    function M.get()
        local c = current.char
        -- A character removed from the DataModel is as good as gone, even if
        -- something else is still holding it.
        if c and c.Parent then return c end
        return plr and plr.Character
    end

    function M.root()
        local c = M.get()
        return c and c:FindFirstChild("HumanoidRootPart")
    end

    function M.humanoid()
        local c = M.get()
        return c and c:FindFirstChildOfClass("Humanoid")
    end

    local function fire(char)
        current.char = char
        -- Backwards over the list, so a listener whose scope died can be
        -- dropped as we go without disturbing the iteration.
        for i = #listeners, 1, -1 do
            local L = listeners[i]
            if not L.scope or L.scope.dead then
                table.remove(listeners, i)
            else
                BX.try(("character/%s"):format(L.label), L.fn, char)
            end
        end
    end

    function M.onSpawn(sc, label, fn)
        listeners[#listeners + 1] = { scope = sc, label = label, fn = fn }
        -- Already alive: call it now, so a feature enabled mid-life does not
        -- sit idle until the next death.
        local c = M.get()
        if c then BX.try(("character/%s"):format(label), fn, c) end
    end

    -- THE ONE CONNECTION. Owned by a scope of its own so a re-execute retires
    -- it along with everything else.
    local sc = BX.scope("core.character")
    if plr then
        sc:connect(plr.CharacterAdded, function(char)
            log.trace("respawn")
            -- Wait for the root part before telling anyone: a feature that
            -- starts moving a character with no HumanoidRootPart throws, and
            -- that throw used to take the rest of the respawn handling with it.
            task.spawn(function()
                BX.try("character/wait", function()
                    char:WaitForChild("HumanoidRootPart", 10)
                end)
                if BX.alive() then fire(char) end
            end)
        end)
        sc:connect(plr.CharacterRemoving, function()
            current.char = nil
        end)
        current.char = plr.Character
    else
        log.error("no LocalPlayer - character tracking unavailable")
    end

    M._listenerCount = function() return #listeners end
    return M
end)

--[[ ==== core/restore.lua ============================================ ]]
-- =============================================================================
-- CORE.RESTORE: whatever you change, register how to change it back
-- =============================================================================
--
--     local rs = BX.require("core.restore")
--
--     rs.remember("movement.walkspeed",
--         function() return hum.WalkSpeed end,          -- read
--         function(v) hum.WalkSpeed = v end)            -- write
--     hum.WalkSpeed = 1620                              -- now modify freely
--
--     rs.restoreAll()      -- every terminal path calls this. Idempotent.
--     rs.audit()           -- what is STILL different from what we captured
--
-- WHY A REGISTRY AND NOT "EACH FEATURE REMEMBERS".
--
-- Each feature remembering is what we had, and it failed in the most ordinary
-- way: movement.reset() put WalkSpeed back to a HARDCODED 16 because there was
-- no anticheat adapter to ask for the real value. Measured on a live character
-- whose actual WalkSpeed was 209.8, so every run left the player crawling.
-- That is the "my character is so slow now" report, and no amount of care at
-- the call site would have caught it - the call site did not know the original.
--
-- Here the original is captured at the moment of the FIRST change, by the code
-- that is about to make it, and nothing else ever has to know what it was.
--
-- CAPTURED ONCE PER KEY. A second remember() for a key already held is
-- ignored, so a value modified repeatedly during a run still restores to what
-- it was before the run - not to what it was halfway through.
--
-- TIED TO THE CHARACTER. A respawn replaces the Humanoid, so values captured
-- against the old one are meaningless and are dropped rather than written back
-- onto a new character that never had them.

BX.module("core.restore", function(BX)
    local ch  = BX.require("core.character")
    local log = BX.require("boot.log").for_module("restore")

    local M = {}

    local entries = {}     -- key -> { read, write, original, char, at }
    local order = {}       -- keys, in the order they were first captured

    BX.profile.watch("restore.pending", function() return #order end)

    -- Capture the current value under `key`, if it is not already held.
    function M.remember(key, read, write)
        if entries[key] then return false end
        local ok, value = pcall(read)
        if not ok then
            log.warn("could not read %s to remember it: %s", key, tostring(value))
            return false
        end
        entries[key] = {
            read = read, write = write, original = value,
            char = ch.get(), at = os.clock(),
        }
        order[#order + 1] = key
        return true
    end

    -- For things with no single property to read back - a destroyed instance, a
    -- patched function - register an undo directly.
    function M.onRestore(key, undo)
        if entries[key] then return false end
        entries[key] = { undo = undo, char = ch.get(), at = os.clock() }
        order[#order + 1] = key
        return true
    end

    -- Something we changed that CANNOT be undone. Recorded so the audit can
    -- report it honestly rather than the cleanup silently passing.
    function M.permanent(key, why)
        if entries[key] then return false end
        entries[key] = { permanent = why or "not reversible", char = ch.get() }
        order[#order + 1] = key
        return true
    end

    -- IDEMPOTENT. Calling it twice is harmless: each entry is removed as it is
    -- restored, so the second call has nothing left to do.
    function M.restoreAll()
        local restored, skipped, failed = 0, 0, 0
        local liveChar = ch.get()

        for i = #order, 1, -1 do
            local key = order[i]
            local e = entries[key]
            if e then
                if e.permanent then
                    skipped = skipped + 1
                elseif e.char and e.char ~= liveChar then
                    -- Captured against a character that no longer exists. The
                    -- new one never had this value; writing it back would be
                    -- inventing state, not restoring it.
                    skipped = skipped + 1
                else
                    local ok, err = pcall(function()
                        if e.undo then e.undo() else e.write(e.original) end
                    end)
                    if ok then
                        restored = restored + 1
                    else
                        failed = failed + 1
                        log.error("restoring %s failed: %s", key, tostring(err))
                    end
                end
                entries[key] = nil
            end
            table.remove(order, i)
        end

        return restored, skipped, failed
    end

    -- What is still different from what we captured. Called AFTER restoreAll,
    -- it should come back empty - that is the cleanup PASS.
    function M.audit()
        local diffs = {}
        for _, key in ipairs(order) do
            local e = entries[key]
            if e and e.read then
                local ok, now = pcall(e.read)
                if ok and tostring(now) ~= tostring(e.original) then
                    diffs[#diffs + 1] = ("%s: %s (was %s)")
                        :format(key, tostring(now), tostring(e.original))
                end
            elseif e and e.permanent then
                diffs[#diffs + 1] = ("%s: %s"):format(key, e.permanent)
            end
        end
        return diffs
    end

    function M.pending()
        return #order
    end

    -- A respawn invalidates anything captured against the old character.
    local sc = BX.scope("core.restore")
    ch.onSpawn(sc, "restore.respawn", function(char)
        local dropped = 0
        for i = #order, 1, -1 do
            local key = order[i]
            local e = entries[key]
            if e and e.char and e.char ~= char then
                entries[key] = nil
                table.remove(order, i)
                dropped = dropped + 1
            end
        end
        if dropped > 0 then
            log.trace("dropped %d entries captured against the old character", dropped)
        end
    end)

    return M
end)

--[[ ==== core/config.lua ============================================= ]]
-- Tunable constants. One table, one place to change behaviour.
--
-- Anything a human might want to adjust belongs here rather than as a literal
-- buried in a feature. Values carry the reasoning that produced them, because
-- several of these were measured against the live game and guessing at them
-- again would undo that work.
BX.module("core.config", function(BX)
    return {
        -- Travel. 500 studs/s is the measured ceiling the server accepts on a
        -- carry leg; above it the server voids the egg ("carry: 590 studs/s
        -- VOIDED by the server"). Do not raise without re-measuring.
        CARRY_SPEED        = 500,
        OUTBOUND_SPEED_MIN = 500,
        OUTBOUND_SPEED_MAX = 1800,

        -- Below this frame rate the client is weak (phones, old laptops) and
        -- the expensive passes thin themselves out rather than stutter.
        LITE_FPS           = 25,

        -- Stats/FPS counter refresh. Four times a second reads as live without
        -- costing a per-frame string build.
        STATS_HZ           = 4,

        -- Logging verbosity at startup: TRACE=1 INFO=2 WARN=3 ERROR=4
        LOG_LEVEL          = 2,

        -- The menu's background image, applied at startup without anyone
        -- typing it in. A saved profile with its own background overrides it;
        -- Clear Background in Config removes it for the session. Empty string
        -- for no default.
        DEFAULT_BACKGROUND = "108858454360177",
    }
end)

--[[ ==== core/state.lua ============================================== ]]
-- Shared mutable state.
--
-- Deliberately small and deliberately explicit. The old build let features
-- reach into each other's upvalues, which is exactly why a change in one
-- corner broke something unrelated. Anything crossing a module boundary is
-- declared here, with a comment saying who writes it.
BX.module("core.state", function(BX)
    return {
        heldEggUid   = nil,    -- written by: features.autosteal
        autoStealOn  = false,  -- written by: ui.window toggle
        -- written by: features.farm.treadmill_on, read by: features.treadmill.
        -- While true the Anti Treadmill poll stands down instead of doffing the
        -- player the Farm tab just deliberately parked on the belt.
        stayOnTreadmill = false,
        lastFps      = 0,      -- written by: ui.stats
        startedAt    = os.clock(),
    }
end)

--[[ ==== core/util.lua =============================================== ]]
-- Small helpers with no dependencies of their own.
BX.module("core.util", function(BX)
    local M = {}

    function M.clamp(v, lo, hi)
        return math.max(lo, math.min(hi, v))
    end

    function M.round(v, places)
        local m = 10 ^ (places or 0)
        return math.floor(v * m + 0.5) / m
    end

    -- Wait that respects the generation guard: returns false the moment this
    -- copy of the hub is retired, so callers can bail out of a loop.
    function M.wait(seconds)
        task.wait(seconds)
        return BX.alive()
    end

    -- Format a count the way the stats panel wants it (1234 -> "1.2k").
    function M.short(n)
        if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
        if n >= 1e3 then return ("%.1fk"):format(n / 1e3) end
        return tostring(math.floor(n))
    end

    return M
end)

--[[ ==== features/movement.lua ======================================= ]]
-- =============================================================================
-- FEATURES.MOVEMENT: get the character from here to there
-- =============================================================================
--
--     local move = BX.require("features.movement")
--
--     local ok, info = move.travel{
--         to       = Vector3,      -- where
--         speed    = 500,          -- studs/sec cruise
--         arrive   = 5,            -- close enough, in studs
--         carrying = false,        -- CALLER states this; movement never reads egg state
--         cancel   = function() end,  -- caller's abort predicate, polled per frame
--         tag      = "carry home", -- appears in every log line for this leg
--     }
--
--     move.descend("land")         -- straight down onto the ground
--     move.noclip(true/false)
--     move.setAnticheat(adapter)   -- optional; see ANTICHEAT SEAM below
--     move.stats()                 -- diagnostics
--
-- RESPONSIBILITY. This module moves a character and nothing else. It does not
-- know what an egg is, it does not decide where to go, and it does not read
-- anyone else's state. Whether we are carrying is an ARGUMENT, because that
-- changes how the leg is flown - not something it reaches into another module
-- to discover.
--
-- WHAT IS CARRIED OVER UNCHANGED FROM V3.1, AND WHY
--
-- These three were measured against the live game. They are not rewritten.
--
--   1. SUB-STEPPING (v186). Frame time is not discarded. The old mover clamped
--      dt to 0.05s and threw the rest away, so a low frame rate silently
--      scaled travel speed down with it:
--          20 fps -> 430 studs/s (100% of target)
--          15 fps -> 322        ( 75%)
--          10 fps -> 215        ( 50%)
--      The carry took twice as long as planned, the guard caught up, and the
--      egg went back to its nest. The clamp is KEPT for what it was actually
--      for - no single PivotTo may jump a large distance, because that climbs
--      geometry and flings you - but the full frame is now spent as several
--      small writes instead of one big one.
--
--   2. BANKED FRAME TIME (v210). A one-off hitch longer than MAX_FRAME still
--      had its excess thrown away, and every discarded millisecond makes the
--      trip longer in real time. On the longest carry that decides the run:
--          Titan Temple   4293 studs   8.6s at 500 studs/s
--          Cherry Blossom 3522         7.0s
--          everything else <= 1777     <= 3.6s
--      Titan is the only leg long enough for accumulated stalls to matter,
--      which is exactly why it was the only area failing on laggy clients and
--      passing on fast ones. Excess is banked and repaid over following
--      frames, still capped per frame so nothing teleports.
--      Measured result: Titan carry on a stuttering client 23.1s -> 9.5s.
--
--   3. THE OUTBOUND BRACKET (v212). Clients that cannot arm the spoof were
--      pinned at 500 studs/s outbound forever with a downward-only backoff.
--      It brackets toward the spoofed speed instead - double while legs come
--      back clean, halve the gap when the server pushes back, converging in
--      about three legs either way. Titan outbound 8.6s -> 3.6s.
--
-- ANTICHEAT SEAM. V3.1's mover called into the anticheat directly (BX.acPush,
-- BX.spoofAc, BX.relocAt, BX.legalWalkSpeed). That is the coupling we are not
-- repeating. Movement takes an OPTIONAL adapter and works without one:
--
--     move.setAnticheat{
--         push            = function(hrp, hum, velocity) end,
--         spoof           = function(claimedWalkSpeed, velocity) end,
--         legalWalkSpeed  = function() return n end,
--         lastRelocateAt  = function() return os.clock() or nil end,
--         allowance       = function() return studsPerSecond or nil end,
--         relocateCount   = function() return n end,
--     }
--
-- With no adapter the mover runs unspoofed and stays at NOSPOOF_FLOOR..500
-- outbound, which is the speed V3.1 measured as safe without a spoof. It does
-- NOT bracket upward blind: the bracket is judged on relocates, and with no
-- adapter there is nothing to judge.

    BX.module("features.movement", function(BX)
        local svc = BX.require("core.services")
        local ch  = BX.require("core.character")
        local dev = BX.require("core.device")
        local rs  = BX.require("core.restore")
        local log = BX.require("boot.log").for_module("movement")

        local RunService, Players = svc.RunService, svc.Players
        local M = {}

        -- Movement's own tuning. Owned here, not in a shared table every module
        -- writes to - that shared K table is how V3.1 ended up with constants
        -- nobody could trace the owner of.
        local K = {
            GROUND_OFFSET     = 3,
            CRUISE_UP         = 18,    -- studs above the higher end to cruise at
            RAMP_FRAC         = 0.12,  -- share of flat distance spent climbing/diving
            RAMP_MAX          = 220,
            RAMP_MIN          = 40,    -- less than this and the climb is a vertical jerk
            START_SPEED       = 0.45,  -- fraction of cruise we leave the ground at
            SPEED_RAMP_FRAC   = 0.28,
            SLOW_RADIUS       = 50,    -- careful approach inside this
            SLOW_SPEED        = 260,
            ARRIVE            = 5,
            MAX_DT            = 0.05,  -- longest SINGLE write, in seconds
            MAX_FRAME         = 0.25,  -- most travel repaid in one frame
            MAX_DEBT          = 2.0,   -- most unspent time carried forward
            MAX_STEP          = 20,    -- ceiling on one write's displacement
            SPEED             = 2400,  -- ultra-fast outbound cruise ceiling
            SPEED_NOSPOOF     = 800,   -- faster no-spoof outbound fallback
            NOSPOOF_FLOOR     = 300,
            NOSPOOF_CONVERGE  = 40,
            DROP_SPEED        = 400,
            SPOOF_HEADROOM    = 1.35,  -- claimed WalkSpeed = speed * this
            WS_MAX            = 4000,
            WALKSPEED_SANE_MIN = 40,
            RELOC_CLAMP_FOR   = 6,
            RELOC_CLAMP_RATIO = 1.04,
            -- Teleport. TP_LANDED is how close counts as accepted;
            -- TP_SETTLE is the wait before measuring, because a refusal
            -- arrives as a relocate about 170ms later.
            TP_SETTLE         = 0.35,
            TP_LANDED         = 30,
        }
        M.K = K

        ---------- the anticheat seam ----------

        local ac = nil
        function M.setAnticheat(adapter) ac = adapter end
        local function acGet(name)
            local f = ac and ac[name]
            return type(f) == "function" and f or nil
        end

        ---------- ground ----------

        -- CACHED RAYCAST PARAMS.
        --
        -- V3.1 built a fresh RaycastParams and walked Players:GetPlayers() on every
        -- single call, and this is called on both ends of every leg plus the final
        -- ground snap. The filter only changes when the player list or our own
        -- character does, so it is rebuilt on those events rather than per call.
        local groundParams = RaycastParams.new()
        groundParams.FilterType = Enum.RaycastFilterType.Exclude
        groundParams.IgnoreWater = true

        local filterDirty = true
        local scratchIgnore = {}   -- reused; never reallocated per call

        local function rebuildFilter()
            -- EVERY player character, not just ours: other people's torsos and
            -- hats are CanCollide, so they read as solid ground. That is what
            -- stranded a carry 49 studs short of the plot for ten seconds.
            local n = 0
            for i = #scratchIgnore, 1, -1 do scratchIgnore[i] = nil end
            for _, pl in ipairs(Players:GetPlayers()) do
                if pl.Character then
                    n = n + 1
                    scratchIgnore[n] = pl.Character
                end
            end
            groundParams.FilterDescendantsInstances = scratchIgnore
            filterDirty = false
        end

        local function solidGroundY(pos)
            if filterDirty then rebuildFilter() end
            local origin = pos + Vector3.new(0, 80, 0)
            local dir = Vector3.new(0, -700, 0)
            -- A plain downward ray hits non-collidable markers first - Areas.Ground,
            -- GuardAreas.*.Bounds, Center, and worst of all "mainsky" - so it walks
            -- down through them until it finds something genuinely collidable.
            local extra = nil
            for _ = 1, 15 do
                local r = workspace:Raycast(origin, dir, groundParams)
                if not r then break end
                if r.Instance.CanCollide then
                    if extra then groundParams.FilterDescendantsInstances = scratchIgnore end
                    return r.Position.Y + K.GROUND_OFFSET
                end
                -- Non-collidable marker: exclude it and look again. Built on a
                -- copy so the shared scratch list is not permanently polluted.
                extra = extra or table.clone(scratchIgnore)
                extra[#extra + 1] = r.Instance
                groundParams.FilterDescendantsInstances = extra
            end
            if extra then groundParams.FilterDescendantsInstances = scratchIgnore end
            return nil
        end

        local function groundOr(pos, fallback)
            return solidGroundY(pos) or fallback
        end

        M.groundY = solidGroundY

        ---------- noclip ----------

        -- V3.1 kept `noclipOriginal` keyed by BasePart for the whole session and
        -- never cleared it, so every part of every character the player ever had
        -- stayed strongly referenced - a table that only grows, holding dead
        -- characters alive. The snapshot is per-enable and dropped on disable.
        local noclipSc, noclipWas, noclipParts, noclipFor = nil, nil, nil, nil

        local function noclipStep()
            local char = ch.get()
            if not char then return end
            if noclipFor ~= char or not noclipParts then
                -- Rebuilt only when the character changes. V3.1 walked
                -- GetDescendants on every physics step before this was cached.
                noclipParts, noclipFor, noclipWas = {}, char, {}
                for _, p in ipairs(char:GetDescendants()) do
                    if p:IsA("BasePart") then
                        noclipParts[#noclipParts + 1] = p
                        noclipWas[p] = p.CanCollide
                    end
                end
            end
            for i = 1, #noclipParts do
                local p = noclipParts[i]
                if p.Parent and p.CanCollide then p.CanCollide = false end
            end
        end

        function M.noclip(on)
            if on then
                if noclipSc then return end
                -- Registered so a terminal path restores collisions even if
                -- noclip(false) is never reached.
                rs.onRestore("movement.noclip", function() M.noclip(false) end)
                noclipSc = BX.scope("features.movement.noclip")
                noclipSc:onFrame("noclip", RunService.Stepped, noclipStep)
            else
                if not noclipSc then return end
                noclipSc:destroy()
                noclipSc = nil
                -- Disconnecting alone left every part CanCollide = false, so the
                -- character stayed non-collidable afterwards: it floats, and that
                -- is an obvious persistent tell.
                if noclipWas then
                    for part, was in pairs(noclipWas) do
                        if part.Parent then pcall(function() part.CanCollide = was end) end
                    end
                end
                noclipParts, noclipWas, noclipFor = nil, nil, nil
            end
        end

        ---------- the outbound speed bracket (v212) ----------

        local brk = { low = nil, high = nil, speed = nil, legSpeed = nil, legRelocs = nil }

        -- V3.1 runs the outbound leg at K.SPEED (1200) - arcTweenTo(eggPos,
        -- K.ARC_SPEED, "outbound", 4) - and gets there on the WalkSpeed claim
        -- alone, which needs nothing from an executor. So 1200 is the normal
        -- answer, not an optimistic one.
        --
        -- The bracket below is only for a leg that genuinely cannot spoof (one
        -- flown while carrying), and it still refuses to climb blind: with no way
        -- to tell a clean leg from a relocated one, it stays at the measured-safe
        -- 500 rather than guessing upward.
        function M.outboundSpeed()
            return K.SPEED
        end

        function M.carrySpeedCap()
            if not acGet("relocateCount") then return K.SPEED_NOSPOOF end
            return brk.speed or K.SPEED_NOSPOOF
        end

        local function bracketAfterLeg()
            local count = acGet("relocateCount")
            if not count or not brk.legSpeed then return end

            local used = brk.legSpeed
            local hadRelocs = count() > (brk.legRelocs or 0)

            -- BISECT, DO NOT CRAWL. A 100-a-leg climb takes eight trips to reach
            -- parity with a spoofed client - minutes of being slower for no reason.
            if hadRelocs then
                brk.high = used                                   -- too fast
            else
                brk.low = math.max(brk.low or K.SPEED_NOSPOOF, used)
            end

            local low = brk.low or K.SPEED_NOSPOOF
            local nextSpeed
            if brk.high then
                if (brk.high - low) <= K.NOSPOOF_CONVERGE then
                    nextSpeed = low                               -- settled at the safe max
                else
                    nextSpeed = math.floor((low + brk.high) / 2)
                end
            else
                nextSpeed = math.min(K.SPEED, low * 2)
            end

            nextSpeed = math.clamp(nextSpeed, K.NOSPOOF_FLOOR, K.SPEED)
            if nextSpeed ~= (brk.speed or K.SPEED_NOSPOOF) then
                log.info("travel: %s at %d - next leg %d studs/s (bracket %d..%s)",
                    hadRelocs and "relocated" or "clean", used, nextSpeed,
                    low, tostring(brk.high or "-"))
            end
            brk.speed = nextSpeed
            brk.legSpeed = nil
        end

        -- DECLARED ABOVE ITS FIRST USE, DELIBERATELY.
        --
        -- This sat below M.teleport, and a local referenced above its declaration
        -- is not an error in Lua - the name silently resolves to a global instead.
        -- Roblox happens to have a legacy global called `stats`, so the teleport
        -- path indexed a function and threw "attempt to index function with
        -- 'teleports'" the first time it ran. Nothing structural catches this.
        local stats = { legs = 0, cancelled = 0, respawned = 0, timedOut = 0, arrived = 0,
                        teleports = 0, tpLanded = 0, tpRefused = 0 }
        function M.stats() return table.clone(stats) end

        ---------- instant teleport ----------

        -- THE TRANSITION TO THE SELECTED TARGET IS A TELEPORT, NOT A TWEEN.
        --
        -- This is deliberate V3.1 behaviour and it is not cosmetic. Measured on
        -- this client: tweening 3029 studs to the target takes 6.0s at 500 studs/s,
        -- and the character DIED partway through it - six seconds crossing a field
        -- full of guards is the exposure the teleport exists to remove. The jump
        -- puts us on the nest in one frame.
        --
        -- It is only ever used EMPTY-HANDED. The carry-void rule that reverts a
        -- fast-moving egg cannot apply to a hand with no egg in it, which is why
        -- the outbound leg is the one place a jump has a chance at all. The carry
        -- home stays a tween.
        --
        -- THE SERVER DOES NOT ALWAYS ACCEPT IT. V3.1 measured five Prehistoric
        -- trips: one landed, one landed then was relocated 0.1s later, three were
        -- refused outright. So this never assumes - it jumps, settles, and MEASURES
        -- the gap. The caller falls back to the tween when it was refused.
        function M.teleport(pos, tag)
            local char, hrp = ch.get(), ch.root()
            if not char or not hrp then return false, math.huge end

            local gy = solidGroundY(pos)
            local dest = Vector3.new(pos.X, gy or pos.Y, pos.Z)
            local from = hrp.Position

            local ok = pcall(function() char:PivotTo(CFrame.new(dest)) end)
            if ok then
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
            end

            -- Settle before measuring. A relocate arrives about 170ms after a bare
            -- PivotTo, so reading the position immediately would call a refused
            -- jump a success.
            task.wait(dev.scale(K.TP_SETTLE))

            local h2 = ch.root()
            local gap = h2 and (h2.Position - dest).Magnitude or math.huge
            local landed = gap <= K.TP_LANDED

            stats.teleports = stats.teleports + 1
            if landed then
                stats.tpLanded = stats.tpLanded + 1
            else
                stats.tpRefused = stats.tpRefused + 1
            end

            log.info("tp %s: %.0f studs -> %s (%.0f off, tier=%s)",
                tostring(tag), (dest - from).Magnitude,
                landed and "landed" or "REFUSED", gap, dev.tier)

            return landed, gap
        end

        ---------- travel ----------

        -- Hoisted out of the per-sub-step loop. V3.1 built a fresh closure for
        -- every sub-step of every frame here - at 60fps with up to five sub-steps
        -- that is hundreds of throwaway closures a second, inside the hottest loop
        -- in the hub, which is exactly where allocations turn into GC pauses.
        local function writeStep(char, hum, hrp, dest, look)
            if hum then hum:Move(Vector3.zero, false) end
            char:PivotTo(CFrame.lookAt(dest, dest + look))
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end


        function M.travel(opts)
            local pos      = opts.to
            local tag      = opts.tag or "leg"
            local arrive   = opts.arrive or K.ARRIVE
            local carrying = opts.carrying and true or false
            local cancel   = opts.cancel
            -- Optional airborne destination support (used by Dr. Scramble).
            -- Normal Auto Steal keeps the old ground-settle behaviour.
            local keepY    = opts.keepY == true

            -- Carry legs need a stricter transport profile than empty-handed
            -- movement.  A long render/heartbeat hitch must never be repaid as
            -- one large PivotTo burst while the server is holding an egg.
            -- MobileFastCarry deliberately gets a larger transport window.
            -- The old hard caps (28 / 0.12 / 0.24) silently overrode the
            -- caller's mobile profile and made the carry path slow even when
            -- transportSpeed was high.  Normal carry keeps the conservative caps.
            local mobileFastCarry = opts.mobileFast == true
            -- PHONE STABILITY: the previous 110-stud write was too large on
            -- 15-30 FPS touch clients.  It could place the character inside
            -- map geometry and then the server corrected it back to the wall.
            -- A 55-stud ceiling is still enough to sustain ~1000 studs/s at
            -- normal mobile frame rates while keeping each PivotTo bounded.
            local carryStepCap = mobileFastCarry and 55 or 28
            local carryFrameCap = mobileFastCarry and 0.16 or 0.12
            local carryDebtCap = mobileFastCarry and 0.32 or 0.24
            local carryMaxStep = carrying and math.min(tonumber(opts.maxStep) or 24, carryStepCap) or K.MAX_STEP
            local carryMaxFrame = carrying and math.min(tonumber(opts.maxFrame) or 0.10, carryFrameCap) or K.MAX_FRAME
            local carryMaxDebt = carrying and math.min(tonumber(opts.maxDebt) or 0.22, carryDebtCap) or K.MAX_DEBT

            local char = ch.get()
            local hrp  = ch.root()
            local hum  = ch.humanoid()
            if not char or not hrp then
                log.warn("%s: no character to move", tag)
                return false, { reason = "no-character" }
            end

            local speed = math.max(opts.speed or K.SPEED_NOSPOOF, 40)
            -- Per-leg mobile stall state is kept local. Shared module fields can
            -- leak state if another travel leg starts during a respawn/cancel.

            local start = hrp.Position
            local flatTotal = Vector3.new(pos.X - start.X, 0, pos.Z - start.Z).Magnitude
            if flatTotal < 1 then return true, { reason = "already-there", distance = 0 } end

            -- Cruise altitude: above whichever end sits higher, so the flat middle
            -- clears the ground between them.
            local startGround = groundOr(start, start.Y)
            local endGround   = groundOr(pos, pos.Y)
            local landY   = keepY and pos.Y or endGround
            -- PHONE PATH CLEARANCE: small screens commonly run at lower FPS,
            -- so a large single-frame displacement is more likely to intersect
            -- a tall wall/roof.  Cruise higher on touch clients while carrying.
            -- The final descend still returns to the target ground height.
            local cruiseExtra = (carrying and mobileFastCarry and dev.isTouch) and 42 or K.CRUISE_UP
            local baseCruiseY = math.max(startGround, endGround, start.Y, pos.Y) + cruiseExtra
            local cruiseY = baseCruiseY

            -- PHONE PATH REPAIR V2: do not assume that a fixed +42 studs is
            -- enough to clear the map.  The recorded phone run repeatedly put
            -- the character beside/inside the tall lava-map structures.  Before
            -- the first long carry write, scan the straight XZ corridor at the
            -- intended cruise height.  If a collidable roof/pillar crosses it,
            -- lift the cruise above that part instead of repeatedly writing the
            -- character back into the same obstruction and waiting for server
            -- correction.  This is only used for carried mobile legs.
            if carrying and mobileFastCarry and dev.isTouch and workspace and workspace.Raycast then
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Exclude
                rp.FilterDescendantsInstances = {char}
                rp.IgnoreWater = true

                local scanY = cruiseY
                local origin = Vector3.new(start.X, scanY, start.Z)
                local target = Vector3.new(pos.X, scanY, pos.Z)
                local delta = target - origin
                local dist = delta.Magnitude
                if dist > 4 then
                    local ignored = {char}
                    for _ = 1, 8 do
                        rp.FilterDescendantsInstances = ignored
                        local hit = workspace:Raycast(origin, delta, rp)
                        if not hit then break end

                        local inst = hit.Instance
                        local collidable = false
                        pcall(function() collidable = inst:IsA("BasePart") and inst.CanCollide end)
                        if not collidable then
                            ignored[#ignored + 1] = inst
                        else
                            local topY = hit.Position.Y
                            pcall(function()
                                if inst:IsA("BasePart") then
                                    topY = inst.Position.Y + inst.Size.Y * 0.5
                                end
                            end)
                            local clearanceY = topY + 12
                            cruiseY = math.max(cruiseY, math.min(clearanceY, baseCruiseY + 120))
                            log.trace("mobile carry obstacle clearance: %.0f -> %.0f (%s)",
                                baseCruiseY, cruiseY, tostring(inst.Name))
                            break
                        end
                    end
                end
            end

            -- On a short hop there is not room for a full climb and dive, so they
            -- share the distance rather than overlapping.
            local ramp = math.clamp(flatTotal * K.RAMP_FRAC, K.RAMP_MIN, K.RAMP_MAX)
            if ramp * 2 > flatTotal * 0.9 then ramp = flatTotal * 0.45 end
            if flatTotal < K.RAMP_MIN * 2 then cruiseY = math.max(start.Y, pos.Y) end

            local wasPS = hum and hum.PlatformStand or false
            if hum then
                -- Captured ONCE per run, before anything touches it, so a cancelled
                -- or respawned leg still restores what the player actually had.
                rs.remember("movement.platformStand",
                    function() return hum.PlatformStand end,
                    function(v) hum.PlatformStand = v end)
                hum.PlatformStand = true
            end

            -- SPOOF WHENEVER WE ARE EMPTY-HANDED. NO ADAPTER REQUIRED.
            --
            -- V3.1 line 5687 is  spoof = BX.arcSpoof and hum and (heldEggUid == nil)
            -- with BX.arcSpoof = true, so the spoof is ON for every empty-handed
            -- leg, unconditionally. An earlier version of this module required an
            -- anticheat adapter to exist before spoofing, which inverted that
            -- default: with no adapter the outbound ran at the 500 no-spoof floor
            -- instead of 1200, and a 4200-stud leg took 8.4s instead of 3.5s. That
            -- is the "it visibly travels across the map" difference.
            --
            -- The spoof that actually works is the WalkSpeed claim below. The
            -- adapter's push/spoof are optional enrichment on top of it, NOT a
            -- precondition - see the note on the dead anticheat path in
            -- docs/ANTICHEAT-LEGACY.md.
            local push, spoofFn = acGet("push"), acGet("spoof")
            local spoof = (not carrying) and hum and true or false
            local claimWS, savedWS = nil, nil
            if spoof then
                rs.remember("movement.walkSpeed",
                    function() return hum.WalkSpeed end,
                    function(v) hum.WalkSpeed = v end)
                savedWS = hum.WalkSpeed
                claimWS = math.clamp(speed * K.SPOOF_HEADROOM, 16, K.WS_MAX)
                hum.WalkSpeed = claimWS
            end

            -- Record what this leg ran at, for the bracket to judge afterwards.
            if not carrying and not spoof then
                brk.legSpeed = speed
                local count = acGet("relocateCount")
                brk.legRelocs = count and count() or 0
            end

            local legAt = os.clock()
            local t0 = legAt
            local mobileCarryProgress = 0
            local mobileCarryStallAt = carrying and mobileFastCarry and dev.isTouch and legAt or nil
            local deadline = t0 + math.max(flatTotal / speed, 0.3) * 3 + 6
            local lastT = t0
            local arcDebt = 0
            local ok, reason = false, "timeout"
            local frames, subStepTotal, maxFrameSeen = 0, 0, 0

            log.trace("%s: begin %.0f studs at %.0f studs/s (carrying=%s spoof=%s tier=%s)",
                tag, flatTotal, speed, tostring(carrying), tostring(spoof), dev.tier)

            while os.clock() < deadline do
                if cancel and cancel() then reason = "cancelled" break end

                -- RE-RESOLVE THE CHARACTER EVERY FRAME.
                --
                -- V3.1 captured char and hum once and only re-read the root part.
                -- A respawn mid-leg left it writing PivotTo to a destroyed model
                -- inside a pcall that swallowed the error, so it span until the
                -- deadline - seconds of doing nothing - and then reported failure
                -- with no indication why. A changed character ends the leg at once
                -- and says so.
                local liveChar = ch.get()
                if liveChar ~= char then
                    reason = "respawned"
                    break
                end
                local hh = ch.root()
                if not hh then reason = "lost-root" break end

                local now = os.clock()
                local raw = now - lastT
                lastT = now

                -- Sub-stepping (v186) + banked frame time (v210). See the header.
                -- IMPORTANT FOR CARRY: if the client stalls for a large frame,
                -- discard the accumulated travel debt instead of compensating
                -- for the stall with a large server-visible jump.  That jump is
                -- what makes otherwise healthy Auto Farm deliveries get dropped.
                local frameDt
                -- Mobile devices frequently produce 100-180ms Heartbeat gaps.
                -- V57 treated anything over 100ms as zero movement, which made
                -- a lag spike turn the whole carry into a crawl. Only discard a
                -- genuinely huge stall; otherwise bank and repay the frame time.
                if carrying and raw > 0.24 then
                    arcDebt = 0
                    frameDt = 0
                else
                    arcDebt = math.min(arcDebt + raw, carrying and carryMaxDebt or K.MAX_DEBT)
                    frameDt = math.min(arcDebt, carrying and carryMaxFrame or K.MAX_FRAME)
                    arcDebt = arcDebt - frameDt
                end
                if raw > maxFrameSeen then maxFrameSeen = raw end

                local subSteps = math.max(1, math.ceil(frameDt / K.MAX_DT))
                local dt = frameDt / subSteps
                frames = frames + 1
                subStepTotal = subStepTotal + subSteps

                local flat = Vector3.new(pos.X - hh.Position.X, 0, pos.Z - hh.Position.Z)
                local rem = flat.Magnitude
                if rem <= arrive then ok, reason = true, "arrived" break end

                local done = math.max(flatTotal - rem, 0)

                -- SPEED: ramp up over the first stretch, hold, ramp down over the
                -- last, then crawl the final approach.
                local want
                local speedRamp = math.max(ramp * K.SPEED_RAMP_FRAC, 1)
                if rem <= K.SLOW_RADIUS then
                    want = math.min(K.SLOW_SPEED, speed)
                elseif rem < ramp then
                    local f = rem / ramp
                    want = math.max(speed * f, math.min(K.SLOW_SPEED, speed))
                elseif done < speedRamp then
                    want = speed * (K.START_SPEED + (1 - K.START_SPEED) * (done / speedRamp))
                else
                    want = speed
                end

                -- WHILE IT IS RELOCATING US, MOVE AT THE SPEED IT ALLOWS.
                --
                -- Travelling at the permitted speed is FASTER than being dragged
                -- back five times a second: V3.1 measured 1363 studs taking 9.41s
                -- and still finishing 417 short while being relocated ninety times.
                -- A client where the spoof holds never reaches this.
                --
                -- A carry only answers to relocates that happened DURING the carry.
                -- A relocate on the empty-handed hop out used to leave the whole
                -- trip home crawling at the ~216 allowance - below most guards'
                -- starting speed - which was "it goes slow the moment it steals".
                local lastReloc = acGet("lastRelocateAt")
                local relocAt = lastReloc and lastReloc() or nil
                if relocAt and (not carrying or relocAt >= legAt)
                and (os.clock() - relocAt) < K.RELOC_CLAMP_FOR then
                    local allowFn = acGet("allowance")
                    local allow = allowFn and allowFn() or nil
                    if not allow and hum and hum.WalkSpeed > K.WALKSPEED_SANE_MIN then
                        allow = hum.WalkSpeed * K.RELOC_CLAMP_RATIO
                    end
                    if allow and allow > 0 and want > allow then
                        want = allow
                    end
                end

                -- MOBILE STALL RECOVERY: if the character has made almost no
                -- horizontal progress for several heartbeats while the egg is
                -- held, raise the temporary cruise altitude. This handles the
                -- common phone case where a lower-FPS PivotTo intersects a wall
                -- and the server immediately corrects the character back.
                -- It is bounded and only changes the temporary Y of the arc.
                if carrying and mobileFastCarry and dev.isTouch then
                    local progress = flatTotal - rem
                    local lastProgress = mobileCarryProgress or progress
                    local nowStall = os.clock()
                    if progress > lastProgress + 1 then
                        mobileCarryProgress = progress
                        mobileCarryStallAt = nowStall
                    elseif not mobileCarryStallAt then
                        mobileCarryStallAt = nowStall
                    elseif nowStall - mobileCarryStallAt > 0.45 then
                        local ceiling = math.max(startGround, endGround, start.Y, pos.Y) + 180
                        local nextY = math.min(cruiseY + 30, ceiling)

                        -- Re-scan the remaining corridor after a stall. This is
                        -- important when the first scan started before the player
                        -- reached a tall tower/bridge.
                        if workspace and workspace.Raycast then
                            local rp2 = RaycastParams.new()
                            rp2.FilterType = Enum.RaycastFilterType.Exclude
                            rp2.FilterDescendantsInstances = {char}
                            rp2.IgnoreWater = true
                            local org2 = Vector3.new(hh.Position.X, nextY, hh.Position.Z)
                            local tar2 = Vector3.new(pos.X, nextY, pos.Z)
                            local d2 = tar2 - org2
                            if d2.Magnitude > 4 then
                                for _ = 1, 6 do
                                    local hit2 = workspace:Raycast(org2, d2, rp2)
                                    if not hit2 then break end
                                    local inst2 = hit2.Instance
                                    local c2 = false
                                    pcall(function() c2 = inst2:IsA("BasePart") and inst2.CanCollide end)
                                    if not c2 then
                                        rp2.FilterDescendantsInstances = {char, inst2}
                                    else
                                        local top2 = hit2.Position.Y
                                        pcall(function() if inst2:IsA("BasePart") then top2 = inst2.Position.Y + inst2.Size.Y * 0.5 end end)
                                        nextY = math.min(math.max(nextY, top2 + 12), ceiling)
                                        break
                                    end
                                end
                            end
                        end

                        cruiseY = nextY
                        mobileCarryStallAt = nowStall
                        log.trace("mobile carry stall recovery: cruise %.0f", cruiseY)
                    end
                end

                -- HEIGHT: climb over the first ramp, hold, dive over the last onto
                -- the target's own Y rather than the cruise.
                local wantY
                if done < ramp then
                    wantY = start.Y + (cruiseY - start.Y) * (done / ramp)
                elseif rem < ramp then
                    wantY = landY + (cruiseY - landY) * (rem / ramp)
                else
                    wantY = cruiseY
                end

                -- One frame's travel, as `subSteps` writes of the size the desktop
                -- path has always used.
                local arrived = false
                for _ = 1, subSteps do
                    local hp = hh.Position
                    local f2 = Vector3.new(pos.X - hp.X, 0, pos.Z - hp.Z)
                    local rem2 = f2.Magnitude
                    if rem2 <= arrive then arrived = true break end

                    local step = math.min(rem2, want * dt, carryMaxStep)
                    local unit = f2.Unit
                    local nxt = hp + unit * step
                    pcall(writeStep, char, hum, hh,
                        Vector3.new(nxt.X, wantY, nxt.Z), unit)
                end
                if arrived then ok, reason = true, "arrived" break end

                if spoof then
                    -- RE-ASSERT THE CLAIM EVERY FRAME. Setting WalkSpeed once is
                    -- not enough: the game's governor writes it back about once a
                    -- second, and the moment it lands we are travelling at cruise
                    -- with a legal WalkSpeed behind us - the contradiction the
                    -- validator relocates for.
                    if hum.WalkSpeed < claimWS - 1 then hum.WalkSpeed = claimWS end
                    -- Optional enrichment only. Both are no-ops on the current
                    -- game version (the anticheat state table it edited no longer
                    -- exists), so the claim above is what carries the leg.
                    if push or spoofFn then
                        local told = flat.Unit * math.min(want, claimWS)
                        if push then push(hh, hum, told) else spoofFn(claimWS, told) end
                    end
                    pcall(function() hh.AssemblyLinearVelocity = Vector3.zero end)
                end

                -- YIELD. THIS LINE IS THE WHOLE "IT FREEZES MY GAME". Without it
                -- there is no frame boundary, so dt is ~0, step is ~0, the distance
                -- never falls, and it spins until the deadline with the client
                -- locked solid.
                RunService.Heartbeat:Wait()
            end

            ---------- settle ----------

            local hz = ch.root()
            local liveChar = ch.get()
            if hz and liveChar == char and not keepY then
                local gy = solidGroundY(hz.Position)
                if gy and math.abs(hz.Position.Y - gy) > 1 then
                    pcall(function() char:PivotTo(CFrame.new(hz.Position.X, gy, hz.Position.Z)) end)
                end
            end

            if spoof and hum and hum.Parent then
                -- Leaving an inflated WalkSpeed behind is what voids the next
                -- delivery. Always restored, on every exit path including the
                -- cancelled and respawned ones.
                local legalFn = acGet("legalWalkSpeed")
                local legal = legalFn and legalFn() or savedWS or 16
                pcall(function() hum.WalkSpeed = math.max(legal, 16) end)
            end
            if hum and hum.Parent then
                hum.PlatformStand = wasPS
                local hstate = hum:GetState()
                if hstate == Enum.HumanoidStateType.Freefall
                or hstate == Enum.HumanoidStateType.PlatformStanding
                or hstate == Enum.HumanoidStateType.Physics then
                    pcall(function() hum:ChangeState(Enum.HumanoidStateType.Landed) end)
                end
            end
            mobileCarryProgress = nil
            mobileCarryStallAt = nil
            if hz then
                hz.AssemblyLinearVelocity = Vector3.zero
                hz.AssemblyAngularVelocity = Vector3.zero
            end

            if not carrying and not spoof then bracketAfterLeg() end

            local gap = hz and Vector3.new(pos.X - hz.Position.X, 0, pos.Z - hz.Position.Z).Magnitude
                or math.huge
            local elapsed = os.clock() - t0
            local settled = ok or gap <= arrive + 4

            stats.legs = stats.legs + 1
            stats[settled and "arrived" or (reason == "cancelled" and "cancelled")
                or (reason == "respawned" and "respawned") or "timedOut"] =
                (stats[settled and "arrived" or (reason == "cancelled" and "cancelled")
                or (reason == "respawned" and "respawned") or "timedOut"] or 0) + 1

            -- ONE LINE THAT ANSWERS "WHY DID IT FAIL".
            --
            -- Distance, wall time, the speed asked for, how short it finished, why
            -- it stopped, the frame rate it actually got and the worst single
            -- frame. "Auto Steal froze while carrying" is answerable from this
            -- without guessing: a respawned reason, a timeout with a large gap, or
            -- a maxFrame of 0.8s each point somewhere different.
            local level = settled and log.trace or log.warn
            level("%s: %s %.0f studs in %.2fs (want %.0f/s, %.0f/s actual, %.1f short) "
                .. "reason=%s frames=%d sub=%.1f worstFrame=%.0fms tier=%s",
                tag, settled and "ok" or "FAILED", flatTotal, elapsed, speed,
                flatTotal / math.max(elapsed, 0.001), gap, reason, frames,
                frames > 0 and (subStepTotal / frames) or 0,
                maxFrameSeen * 1000, dev.tier)

            return settled, {
                reason = reason, distance = flatTotal, elapsed = elapsed,
                gap = gap, frames = frames, worstFrameMs = maxFrameSeen * 1000,
            }
        end

        ---------- descend ----------

        -- Straight down onto the ground where we are standing: the last step of the
        -- cycle, over the middle of the pen and then down to ground level.
        function M.descend(tag)
            tag = tag or "land"
            local char, h = ch.get(), ch.root()
            if not char or not h then return false end
            local hum = ch.humanoid()

            local gy = solidGroundY(h.Position)
            if not gy then
                -- Nothing under us to land on: give physics it back and fall.
                if hum then hum.PlatformStand = false end
                log.trace("%s: no ground below - falling", tag)
                return false
            end

            local x, z = h.Position.X, h.Position.Z
            local from = h.Position.Y
            if from - gy <= 2 then
                if hum then hum.PlatformStand = false end
                return true
            end

            if hum then hum.PlatformStand = true end
            local t0 = os.clock()
            local dur = math.clamp((from - gy) / math.max(K.DROP_SPEED, 50), 0.05, 1.2)
            while os.clock() - t0 < dur do
                if ch.get() ~= char then break end
                local hh = ch.root()
                if not hh then break end
                local f = (os.clock() - t0) / dur
                local y = from + (gy - from) * f
                pcall(function()
                    char:PivotTo(CFrame.new(x, y, z) * (hh.CFrame - hh.CFrame.Position))
                    hh.AssemblyLinearVelocity = Vector3.zero
                end)
                RunService.Heartbeat:Wait()
            end

            if ch.get() == char then
                pcall(function() char:PivotTo(CFrame.new(x, gy, z)) end)
            end
            if hum and hum.Parent then
                hum.PlatformStand = false
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.Landed) end)
            end
            log.trace("%s: descended %.0f studs to ground", tag, from - gy)
            return true
        end

        ---------- lifecycle ----------

        -- The filter is rebuilt on player churn rather than on every raycast.
        local sc = BX.scope("features.movement")
        sc:connect(Players.PlayerAdded, function() filterDirty = true end)
        sc:connect(Players.PlayerRemoving, function() filterDirty = true end)
        ch.onSpawn(sc, "movement.respawn", function()
            filterDirty = true
            -- The old character's parts are gone; drop the noclip snapshot so it
            -- is rebuilt rather than held.
            noclipParts, noclipWas, noclipFor = nil, nil, nil
        end)

        -- Movement must never be left mid-leg with PlatformStand on and an
        -- inflated WalkSpeed. Callers cancel their own legs; this is the backstop
        -- for a re-execute or an unload.
        -- NEVER GUESS A WALKSPEED.
        --
        -- This used to end with
        --     hum.WalkSpeed = math.max(legalFn and legalFn() or 16, 16)
        -- and with no anticheat adapter legalFn is nil, so every run finished by
        -- setting WalkSpeed to 16. Measured on a live character whose real value
        -- was 209.8 - that is the "my character is so slow now" report, and it was
        -- the cleanup causing it.
        --
        -- Restoration is core.restore's job now: it holds the value captured
        -- before the first change. This only undoes what has no single property to
        -- read back.
        function M.reset()
            M.noclip(false)
        end

        return M
    end)

--[[ ==== features/humanoid.lua ======================================= ]]
-- =============================================================================
-- FEATURES.HUMANOID: swap the Humanoid the anticheat is holding
-- =============================================================================
--
--     local hsw = BX.require("features.humanoid")
--     hsw.arm()      -- swap now, and on every respawn
--     hsw.disarm()
--     hsw.isSwapped()
--
-- THIS IS WHY V3.1 SURVIVES THE TELEPORT AND AN UNPORTED BUILD DOES NOT.
--
-- V3.1's own note, above BX.swapHumanoid:
--
--     Players.<you>.PlayerScripts.Game.ObbyAntiTPClient caches the Humanoid
--     ONCE, at CharacterAdded (its line 470), into an upvalue it later uses
--     in punish().
--
-- So the anticheat holds a direct reference to the Humanoid it saw when the
-- character spawned, and punishes through it. Replace that Humanoid with a
-- clone and destroy the original, and the reference the anticheat is holding
-- points at a destroyed object - punish() has nothing to act on. We never touch
-- the anticheat script itself, so there is nothing for it to detect.
--
-- Without this, an instant teleport is punished and the character dies a second
-- or two later. That is exactly what a port missing this looks like: the bait
-- lands, the teleport lands, and then the run dies for no visible reason.
--
-- WHAT THE CLONE CHANGES
--
--   * Dead, FallingDown and Ragdoll states disabled
--   * Health restored to MaxHealth
--   * an Animator is guaranteed, or animations silently stop
--   * the Health SCRIPT is destroyed first - it re-asserts server health onto
--     the humanoid, which would undo the above
--
-- THIS IS NOT REVERSIBLE, AND THAT IS HONEST RATHER THAN HIDDEN.
--
-- The original Humanoid is destroyed; there is nothing to put back. disarm()
-- therefore only stops us re-applying on the next respawn - the current
-- character keeps the swapped Humanoid until it next respawns naturally, at
-- which point the game builds a normal one. V3.1 behaves the same way.

BX.module("features.humanoid", function(BX)
    local svc = BX.require("core.services")
    local ch  = BX.require("core.character")
    local rs  = BX.require("core.restore")
    local log = BX.require("boot.log").for_module("humanoid")

    local M = {}

    local SWAP_ATTR = "BlyxoStealHum"
    M.SWAP_ATTR = SWAP_ATTR

    local sc = nil
    -- The originals captured at the FIRST swap of this character, so disarm can
    -- put them back without going through the restore ledger.
    local swapPrior = nil
    local stats = { swaps = 0, alreadySwapped = 0, failures = 0 }
    function M.stats() return table.clone(stats) end

    function M.isSwapped()
        local hum = ch.humanoid()
        return hum ~= nil and hum:GetAttribute(SWAP_ATTR) == true
    end

    -- THE STATES THE SWAP TURNS OFF ARE THE ONES THAT HAVE TO COME BACK.
    --
    -- The swap disables Dead, FallingDown and Ragdoll on the clone, and clears
    -- BreakJointsOnDeath, so the character cannot die during a run - which is
    -- the point, because the bait deliberately takes a guard hit. None of it was
    -- ever restored, and the clone outlives the run: after one Auto Steal the
    -- character was left permanently unkillable.
    --
    -- THIS IS WHY JUMPING STAYS BROKEN, and it is entirely our own state.
    --
    -- A character that cannot die cannot respawn, and a respawn is what gives
    -- the player a normal Humanoid again - the one the game's own controls are
    -- given at CharacterAdded. Leaving Dead disabled removes the player's only
    -- route back to a working jump and takes reset-character away with it.
    -- Putting these four values back does not touch the game's code, its
    -- security, or anything Roblox owns; it restores what the hub changed and
    -- lets the normal respawn path work again.
    --
    -- Written to whatever Humanoid is live AT RESTORE TIME, and only while it is
    -- still one of ours: a natural respawn has already produced a clean Humanoid
    -- and must not be written to on the strength of a value read from a
    -- character two lives ago.
    local function applyStates(prior)
        local hum = ch.humanoid()
        if not hum or hum:GetAttribute(SWAP_ATTR) ~= true then return end
        hum:SetStateEnabled(Enum.HumanoidStateType.Dead, prior.dead)
        hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, prior.fallingDown)
        hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, prior.ragdoll)
        hum.BreakJointsOnDeath = prior.breakJoints
    end

    local function rememberStates(prior)
        -- read returns the captured originals rather than reading the clone,
        -- which by this point already has our values on it.
        rs.remember("humanoid.states",
            function() return prior end,
            function(v) applyStates(v) end)
    end

    -- Returns true when the character ends up with a swapped Humanoid.
    function M.swap(char)
        char = char or ch.get()
        if not char then return false end

        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then return false end

        if hum:GetAttribute(SWAP_ATTR) == true then
            stats.alreadySwapped = stats.alreadySwapped + 1
            return true
        end

        -- CAPTURED BEFORE ANYTHING IS CHANGED, read off the ORIGINAL.
        --
        -- Everything below this line is a value the hub sets and used to keep
        -- forever. The clone inherits them, the clone outlives the run, and
        -- nothing ever put them back - so a character that had been through one
        -- Auto Steal stayed unable to die for the rest of the session. See
        -- restoreStates() for why that is the jump report.
        local prior = {
            dead        = hum:GetStateEnabled(Enum.HumanoidStateType.Dead),
            fallingDown = hum:GetStateEnabled(Enum.HumanoidStateType.FallingDown),
            ragdoll     = hum:GetStateEnabled(Enum.HumanoidStateType.Ragdoll),
            breakJoints = hum.BreakJointsOnDeath,
        }

        local ok = BX.try("humanoid.swap", function()
            -- The Health script re-asserts server health onto the humanoid, so
            -- it has to go before the clone, or it simply undoes the swap.
            local healthScript = char:FindFirstChild("Health")
            if healthScript then healthScript:Destroy() end

            hum.BreakJointsOnDeath = false
            hum.Archivable = true

            local clone = hum:Clone()
            if not clone then error("clone failed") end
            clone.Name = "Humanoid"
            clone:SetAttribute(SWAP_ATTR, true)
            clone:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
            clone:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
            clone:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            clone.Health = hum.MaxHealth

            -- An Animator must exist or animations silently stop.
            if not clone:FindFirstChildOfClass("Animator") then
                Instance.new("Animator").Parent = clone
            end

            -- The destroy is the whole point: this is the object the anticheat
            -- cached at CharacterAdded.
            hum:Destroy()
            clone.Parent = char

            if workspace.CurrentCamera then
                workspace.CurrentCamera.CameraSubject = clone
            end

            -- Re-seat the Animate script against the new humanoid.
            local animate = char:FindFirstChild("Animate")
            if animate then
                local ac = animate:Clone()
                animate:Destroy()
                ac.Parent = char
                ac.Disabled = false
            end

            -- Keep the joints alive.
            for _, d in ipairs(char:GetDescendants()) do
                if d:IsA("Motor6D") then d.Enabled = true end
            end
        end)

        if ok then
            -- Declared, not hidden: the original Humanoid and the Health script
            -- are destroyed, so the audit should say so rather than report a
            -- clean pass over a character that is permanently altered.
            rs.permanent("humanoid.swap",
                "Humanoid replaced and Health script destroyed - undone by respawn")

            -- WHAT *CAN* BE PUT BACK, IS PUT BACK. Registered with the same
            -- restore ledger as every other captured value, so restoreAll() and
            -- audit() cover it instead of it living only in disarm().
            swapPrior = prior
            rememberStates(prior)
            stats.swaps = stats.swaps + 1
            log.info("swapped (anticheat now holds a destroyed Humanoid)")
        else
            stats.failures = stats.failures + 1
            log.error("swap FAILED - teleports will be punished")
        end
        return ok and true or false
    end

    function M.isArmed() return sc ~= nil end

    function M.arm()
        if sc then return true end
        sc = BX.scope("features.humanoid")

        M.swap()

        -- UNCONDITIONALLY ON EVERY RESPAWN. A new character gets a fresh
        -- Humanoid and the anticheat caches THAT one at CharacterAdded, so a
        -- swap that happened once protects exactly one life. V3.1 re-applies
        -- on every spawn for this reason and says so at its respawn handler:
        -- "apply unconditionally, the reference build does this on every spawn".
        ch.onSpawn(sc, "humanoid.reswap", function(char)
            -- The new character's Humanoid is the game's own, and the values
            -- read off the previous one do not describe it. core.restore drops
            -- its entry on the same event for the same reason.
            swapPrior = nil
            M.swap(char)
        end)

        return true
    end

    function M.disarm()
        -- BEFORE the armed check, and unconditionally: the states outlive the
        -- run whether or not this module is still holding a scope, and a
        -- character left unable to die is the thing being undone here.
        --
        -- The Humanoid itself cannot be put back - that stays declared as
        -- permanent. Every VALUE we set on it can be, and core.restore's own
        -- restoreAll() will ask for the same thing again during the run's
        -- cleanup; applyStates is idempotent, so both paths are safe.
        if swapPrior then
            BX.try("humanoid.restoreStates", function()
                applyStates(swapPrior)
                log.info("death states restored (dead=%s fallingDown=%s "
                    .. "ragdoll=%s breakJoints=%s) - the character can respawn "
                    .. "normally again",
                    tostring(swapPrior.dead), tostring(swapPrior.fallingDown),
                    tostring(swapPrior.ragdoll), tostring(swapPrior.breakJoints))
            end)
        end

        if not sc then return end
        sc:destroy()
        sc = nil
        log.info("disarmed (%d swaps this session)", stats.swaps)
    end

    return M
end)

--[[ ==== features/antideath.lua ====================================== ]]
-- =============================================================================
-- FEATURES.ANTIDEATH: survive the guard
-- =============================================================================
--
--     local ad = BX.require("features.antideath")
--     ad.arm()      -- hold the character alive
--     ad.disarm()   -- put every original value back
--
-- Ported from V3.1 (LennonHub Proto 61). It does four things, and each one is
-- needed for a different reason:
--
--   * BreakJointsOnDeath = false     the body does not come apart
--   * Dead state disabled            the humanoid cannot enter Dead at all
--   * HealthChanged -> restore       damage that reaches zero is undone
--   * StateChanged -> GettingUp      a Dead transition is turned round
--
-- EVERY ORIGINAL VALUE IS RECORDED AND RESTORED. Leaving BreakJointsOnDeath
-- off and the Dead state disabled is a permanent, obvious modification to the
-- character - it is not something to leave behind when Auto Steal stops.
--
-- WHY THIS IS ARMED FOR THE CYCLE AND NOT ALWAYS.
--
-- In V3.1 this sits behind a flag that defaults to OFF, and that default is
-- why the port died: measured on this client, the character was alive right
-- after the bait hit and then died six seconds into the 3029-stud crossing to
-- the target. The instant teleport removes most of that exposure, but a guard
-- can still land a blow on arrival, so the cycle arms this for its duration
-- and disarms it on the way out.
--
-- RE-ARMED ON RESPAWN. A new character is a new Humanoid with none of these
-- settings, so arming once and walking away protects exactly one life.

BX.module("features.antideath", function(BX)
    local ch  = BX.require("core.character")
    local svc = BX.require("core.services")
    local rs  = BX.require("core.restore")
    local log = BX.require("boot.log").for_module("antideath")

    local M = {}

    local sc = nil
    local saved = nil        -- the values we must put back
    local armedFor = nil     -- which Humanoid the current arming belongs to

    local stats = { arms = 0, deathsBlocked = 0, restores = 0 }
    function M.stats() return table.clone(stats) end

    local function applyTo(char)
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum then return false end
        if armedFor == hum then return true end

        -- Record BEFORE changing anything, and only once per Humanoid.
        saved = {
            humanoid = hum,
            breakJoints = hum.BreakJointsOnDeath,
            deadEnabled = hum:GetStateEnabled(Enum.HumanoidStateType.Dead),
        }
        armedFor = hum

        BX.try("antideath.apply", function()
            rs.remember("antideath.breakJoints",
                function() return hum.BreakJointsOnDeath end,
                function(v) hum.BreakJointsOnDeath = v end)
            rs.remember("antideath.state.Dead",
                function() return hum:GetStateEnabled(Enum.HumanoidStateType.Dead) end,
                function(v) hum:SetStateEnabled(Enum.HumanoidStateType.Dead, v) end)
            hum.BreakJointsOnDeath = false
            hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
        end)

        -- Both handlers go on the scope, so disarming or a re-execute drops
        -- them. V3.1 kept them in a bare table and disconnected by hand.
        sc:connect(hum.HealthChanged, function(hp)
            if hp <= 0 and hum.Parent then
                stats.deathsBlocked = stats.deathsBlocked + 1
                hum.Health = hum.MaxHealth
            end
        end)

        sc:connect(hum.StateChanged, function(_, new)
            if new == Enum.HumanoidStateType.Dead and hum.Parent then
                stats.deathsBlocked = stats.deathsBlocked + 1
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                hum.Health = hum.MaxHealth
            end
        end)

        -- ARRIVING AT ZERO HEALTH IS NOT A HEALTH *CHANGE*.
        --
        -- The two handlers above are the only things that revive us, and both
        -- are event-driven - so a character that was ALREADY on 0 health when
        -- anti-death armed never gets revived. With Dead disabled it also
        -- cannot die properly, so it does not respawn either: the player is
        -- left as a zombie on 0 HP indefinitely.
        --
        -- Seen in a 17-minute soak: every cycle logged "hp=0 Running swapped"
        -- and the character never recovered. A humanoid in that state behaves
        -- badly in ways that look like "can't jump" and "my character is
        -- broken" rather than like death.
        --
        -- So check the CURRENT value on arming, not only later changes.
        if hum.Health <= 0 then
            stats.deathsBlocked = stats.deathsBlocked + 1
            log.warn("armed on a humanoid already at 0 health - reviving it")
            hum.Health = hum.MaxHealth
        end

        stats.arms = stats.arms + 1
        log.trace("armed on humanoid (health %.0f/%.0f)", hum.Health, hum.MaxHealth)
        return true
    end

    local function restore()
        local s = saved
        saved, armedFor = nil, nil
        if not s or not s.humanoid or not s.humanoid.Parent then return end
        stats.restores = stats.restores + 1
        BX.try("antideath.restore", function()
            s.humanoid.BreakJointsOnDeath = s.breakJoints
            s.humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, s.deadEnabled)
        end)
    end

    function M.isArmed() return sc ~= nil end

    function M.arm()
        if sc then return true end
        sc = BX.scope("features.antideath")

        local ok = applyTo(ch.get())

        -- A NEW CHARACTER IS A NEW HUMANOID. Arming once protects one life;
        -- V3.1 re-ran setupAntiDeath from the steal loop for this reason, and
        -- doing it on the respawn signal instead means it cannot be forgotten.
        ch.onSpawn(sc, "antideath.rearm", function(char)
            -- The previous Humanoid is gone with its character, so there is
            -- nothing to restore - just re-apply to the new one.
            saved, armedFor = nil, nil
            applyTo(char)
        end)

        log.info("armed (%s)", ok and "ok" or "no humanoid yet")
        return true
    end

    function M.disarm()
        if not sc then return end
        sc:destroy()
        sc = nil

        -- NEVER HAND BACK A ZOMBIE.
        --
        -- restore() re-enables the Dead state. Doing that while the humanoid
        -- sits on 0 health would kill the player the instant we let go, which
        -- is a worse exit than the one we were preventing. Revive first, then
        -- give the states back.
        BX.try("antideath.reviveOnDisarm", function()
            local hum = ch.humanoid()
            if hum and hum.Parent and hum.Health <= 0 then
                log.warn("disarming on 0 health - reviving before restoring states")
                hum.Health = hum.MaxHealth
            end
        end)

        restore()
        log.info("disarmed (blocked %d deaths this session)", stats.deathsBlocked)
    end

    return M
end)

--[[ ==== features/guard.lua ========================================== ]]
-- =============================================================================
-- FEATURES.GUARD: survive the guard, keep the egg
-- =============================================================================
--
--     local guard = BX.require("features.guard")
--     guard.arm()                  -- anti-hit + anti-ragdoll + drop block
--     guard.disarm()
--     guard.isRagdolled()
--     guard.waitForRecovery(sec)
--     guard.allowDrops(bool)
--
-- These are V3.1's three guard-sequence dependencies. They were armed from the
-- steal loop and from inside primeFirstArea, and the port not having them is
-- why the first full-cycle test died.
--
-- THE GAME RAGDOLLS WITH THE *PHYSICS* STATE, NOT Ragdoll.
--
-- V3.1 learned this the expensive way: an earlier version tested for Ragdoll
-- and FallingDown, which this game NEVER enters, so everything built on it was
-- dead - the ragdoll wait returned instantly and anti-hit never saw a hit to
-- react to. PlatformStand counts too, because Ragdoll.NpcRagdoll sets it.
--
-- WHAT ANTI-DEATH IS NOT. V3.1 ships antiDeathEnabled = false. Anti-death was
-- never its protection against the guard - these three are.

BX.module("features.guard", function(BX)
    local svc = BX.require("core.services")
    local data = BX.require("core.data")
    local ch  = BX.require("core.character")
    local rs  = BX.require("core.restore")
    local log = BX.require("boot.log").for_module("guard")

    local RunService = svc.RunService
    local M = {}

    local K = {
        RISE      = 150,   -- upward studs/s no legal jump can produce
        FLAT_MULT = 2.5,   -- flat speed over WalkSpeed * this is not our doing
        FLAT_MIN  = 150,   -- ...but never react below this, whatever WalkSpeed is
        JOINT_GAP = 0.25,  -- seconds between Motor6D sweeps; they are not free
        HOLD_MAX  = 2.75,  -- longest we wait out the server knockdown
        HOLD_GRACE = 0.25, -- covers the release round trip
    }
    M.K = K

    local sc = nil
    local stats = { launchesCancelled = 0, standUps = 0, dropsRefused = 0 }
    function M.stats() return table.clone(stats) end

    ---------- ragdoll state ----------

    function M.isRagdolled()
        local hum = ch.humanoid()
        if not hum then return false end
        if hum.PlatformStand then return true end
        local s = hum:GetState()
        return s == Enum.HumanoidStateType.Physics
            or s == Enum.HumanoidStateType.Ragdoll
            or s == Enum.HumanoidStateType.FallingDown
    end

    function M.waitForRecovery(seconds)
        local deadline = os.clock() + (seconds or 4)
        while os.clock() < deadline do
            if not M.isRagdolled() then return true end
            RunService.Heartbeat:Wait()
        end
        return false
    end

    ---------- anti-ragdoll ----------

    -- Re-applied on respawn: a new character is a new Humanoid with none of
    -- this set, so applying once protects exactly one life.
    local function applyAntiRagdoll(char)
        char = char or ch.get()
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hum then return false end
        BX.try("guard.antiRagdoll", function()
            -- These were disabled and never put back, so a character stayed
            -- unable to ragdoll or fall for the rest of the session.
            rs.remember("guard.state.Ragdoll",
                function() return hum:GetStateEnabled(Enum.HumanoidStateType.Ragdoll) end,
                function(v) hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, v) end)
            rs.remember("guard.state.FallingDown",
                function() return hum:GetStateEnabled(Enum.HumanoidStateType.FallingDown) end,
                function(v) hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, v) end)
            rs.remember("guard.state.Physics",
                function() return hum:GetStateEnabled(Enum.HumanoidStateType.Physics) end,
                function(v) hum:SetStateEnabled(Enum.HumanoidStateType.Physics, v) end)
            rs.remember("guard.state.PlatformStanding",
                function() return hum:GetStateEnabled(Enum.HumanoidStateType.PlatformStanding) end,
                function(v) hum:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, v) end)
            hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)
            hum:SetStateEnabled(Enum.HumanoidStateType.PlatformStanding, false)
            for _, d in ipairs(char:GetDescendants()) do
                if d:IsA("Motor6D") then d.Enabled = true end
            end
        end)
        return true
    end

    ---------- drop block ----------

    -- The guard's hit makes the client drop what it is carrying.
    --
    -- RESTORED ON DISARM. V3.1 patched EggState.DropFieldEgg and never put it
    -- back, so a wrapped DropFieldEgg stayed installed for the rest of the
    -- session even with Auto Steal switched off.
    local dropOriginal, dropInstalled, eggStateRef = nil, false, nil
    local dropAllowed = false

    local function installDropBlock()
        if dropInstalled then return true end
        eggStateRef = eggStateRef or data.eggState()
        if not eggStateRef or type(eggStateRef.DropFieldEgg) ~= "function" then
            log.warn("cannot block egg drops - EggState.DropFieldEgg missing")
            return false
        end

        dropOriginal = eggStateRef.DropFieldEgg
        eggStateRef.DropFieldEgg = function(reason, ...)
            if not dropAllowed then
                stats.dropsRefused = stats.dropsRefused + 1
                log.trace("drop refused: %s", tostring(reason))
                return
            end
            return dropOriginal(reason, ...)
        end
        dropInstalled = true
        log.info("egg-drop block installed")
        return true
    end

    local function removeDropBlock()
        if not dropInstalled then return end
        BX.try("guard.restoreDrop", function()
            if eggStateRef and dropOriginal then
                eggStateRef.DropFieldEgg = dropOriginal
            end
        end)
        dropInstalled, dropOriginal = false, nil
    end

    -- For a drop we actually want, such as handing the bait egg over.
    function M.allowDrops(on) dropAllowed = on and true or false end

    ---------- anti-hit ----------

    local blocked, ups, jointAt = 0, 0, 0

    local function antiHitStep()
        local hum, hrp = ch.humanoid(), ch.root()
        if not hum or not hrp then return end

        local st = hum:GetState()
        -- A jump we made ourselves is not a launch.
        if st == Enum.HumanoidStateType.Jumping then return end

        -- CANCEL THE LAUNCH. The ragdoll payload carries an impulse - V3.1
        -- measured one at Y = +791 - and the server applies it. Only the part
        -- we cannot account for is removed: zeroing everything froze ordinary
        -- walking as well as the fling.
        local v = hrp.AssemblyLinearVelocity
        local flat = (v * Vector3.new(1, 0, 1)).Magnitude
        local flatCap = math.max((hum.WalkSpeed or 16) * K.FLAT_MULT, K.FLAT_MIN)
        if v.Y > K.RISE or flat > flatCap then
            local keep = Vector3.zero
            if flat > 0.001 then
                keep = (v * Vector3.new(1, 0, 1)).Unit * math.min(flat, hum.WalkSpeed or 16)
            end
            hrp.AssemblyLinearVelocity = Vector3.new(keep.X, math.min(v.Y, 0), keep.Z)
            hrp.AssemblyAngularVelocity = Vector3.zero
            blocked = blocked + 1
            stats.launchesCancelled = blocked
        end

        -- STAND BACK UP. Physics is the state this game uses.
        if hum.PlatformStand or hum.Sit
           or st == Enum.HumanoidStateType.Physics
           or st == Enum.HumanoidStateType.Ragdoll
           or st == Enum.HumanoidStateType.FallingDown
           or st == Enum.HumanoidStateType.PlatformStanding then
            pcall(function()
                hum.PlatformStand = false
                hum.Sit = false
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            end)
            ups = ups + 1
            stats.standUps = ups

            -- A ragdoll unbinds the rig's joints; without re-enabling them the
            -- character stays a heap on the floor whatever state we ask for.
            -- Rate-limited, because a full descendants walk is not free.
            local now = os.clock()
            if now - jointAt > K.JOINT_GAP then
                jointAt = now
                local char = ch.get()
                if char then
                    for _, d in ipairs(char:GetDescendants()) do
                        if d:IsA("Motor6D") and not d.Enabled then d.Enabled = true end
                    end
                end
            end
        end
    end

    -- HOW LONG THE SERVER STILL CONSIDERS US KNOCKED DOWN.
    --
    -- This is the missing piece that made the instant steal fail. The server
    -- refuses CarryFieldEgg outright while its own RagdollEndTime is in the
    -- future, and says so: "Cannot carry eggs while downed". It publishes that
    -- as an attribute on the player, on the SERVER clock:
    --     u4:SetAttribute("RagdollEndTime", workspace:GetServerTimeNow() + dur)
    --
    -- V3.1 notes this is a no-op on a normal tweened steal, because the trip is
    -- long enough to outlast the ~2.5s knockdown. With an instant teleport we
    -- arrive INSIDE that window every single time, so it stops being an edge
    -- case and becomes the thing that decides the cycle.
    function M.ragdollRemaining()
        local left = 0
        BX.try("guard.ragdollRemaining", function()
            local plr = svc.LocalPlayer
            local t = plr and plr:GetAttribute("RagdollEndTime")
            if type(t) == "number" then
                left = math.max(left, t - workspace:GetServerTimeNow())
            end
        end)
        return math.max(0, left)
    end

    -- Wait it out, bounded. Returns how long we actually waited.
    --
    -- THE COUNTDOWN ENDS BEFORE THE SERVER DOES. ragdollRemaining reaches zero
    -- the instant the deadline passes, but the server still has to process the
    -- release and send it. V3.1 measured that gap costing an egg:
    --     17.37 fired prompt -> true      <- we thought we were free
    --     17.43 ragdoll END after 2.4s    <- server released 60ms later
    -- so a short grace covers the round trip.
    function M.waitForServerRelease(cancel)
        local held = M.ragdollRemaining()
        if held <= 0 then return 0 end

        local t0 = os.clock()
        local deadline = os.clock() + math.min(held, K.HOLD_MAX)
        while os.clock() < deadline do
            if cancel and cancel() then break end
            task.wait(0.05)
            if M.ragdollRemaining() <= 0 then break end
        end
        task.wait(K.HOLD_GRACE)
        local waited = os.clock() - t0
        log.trace("server held us %.2fs - waited %.2fs", held, waited)
        return waited
    end

    ---------- lifecycle ----------

    function M.isArmed() return sc ~= nil end

    function M.arm()
        if sc then return true end
        sc = BX.scope("features.guard")
        blocked, ups, jointAt = 0, 0, 0
        dropAllowed = false

        applyAntiRagdoll()
        installDropBlock()

        -- Registered through onFrame so its per-frame cost is profiled by name
        -- rather than hiding inside "Auto Steal".
        sc:onFrame("antihit", RunService.Heartbeat, antiHitStep)

        ch.onSpawn(sc, "guard.respawn", function(char)
            applyAntiRagdoll(char)
        end)

        log.info("armed (anti-hit + anti-ragdoll + drop block)")
        return true
    end

    function M.disarm()
        if not sc then return end
        sc:destroy()
        sc = nil
        dropAllowed = true
        removeDropBlock()
        log.info("disarmed (%d launches cancelled, %d stand-ups, %d drops refused)",
            stats.launchesCancelled, stats.standUps, stats.dropsRefused)
    end

    -- GENERAL GOD MODE STATE / CHARACTER LIFECYCLE SAFETY
    -- Preserves the original Guard API while avoiding per-frame Health/CFrame
    -- writes. Real invulnerability for an experience you control belongs in
    -- the server-side damage system.
    local guardGodSc = nil
    local guardGodOn = false
    local guardGodGeneration = 0

    local function applyGuardGod(char)
        if not guardGodSc or not guardGodOn or not char then return end
        pcall(function() char:SetAttribute("YOKUDO_GodMode", true) end)
    end

    function M.setGodMode(on)
        on = on == true
        if on == guardGodOn and ((on and guardGodSc) or not on) then return true end
        guardGodOn = on
        guardGodGeneration = guardGodGeneration + 1
        if guardGodSc then guardGodSc:destroy(); guardGodSc = nil end
        local char = ch.get()
        if not on then
            if char then pcall(function() char:SetAttribute("YOKUDO_GodMode", false) end) end
            return true
        end
        local generation = guardGodGeneration
        guardGodSc = BX.scope("features.guard.god")
        ch.onSpawn(guardGodSc, "godmode.rearm", function(newChar)
            if generation ~= guardGodGeneration or not guardGodOn then return end
            task.defer(function()
                if generation == guardGodGeneration and guardGodOn then applyGuardGod(newChar) end
            end)
        end)
        applyGuardGod(char)
        return true
    end

    function M.isGodMode() return guardGodOn end

    -- ANTI GUARD KNOCKBACK / COLLISION SHIELD
    --
    -- This is based on the requested Heartbeat guard from the source version:
    -- sample at most every 0.05s, ignore it while Auto Steal owns the
    -- character, detect a large velocity delta, then clear linear/angular
    -- velocity.  It is intentionally separate from the normal anti-hit loop
    -- because the latter also runs during Auto Steal and must not fight the
    -- carry mover.
    local antiGuardKnockbackSc = nil
    local antiGuardKnockback = false
    local antiGuardStealing = false
    local antiGuardLast = 0
    local antiGuardPreviousVelocity = Vector3.zero

    -- Character collision group used by the game for guard avoidance.  Keep a
    -- backup so turning Anti Guard OFF restores the exact previous groups.
    local antiGuardCollisionOld = setmetatable({}, {__mode = "k"})
    local antiGuardCollisionGroup = "GuardsNoCollide"

    local function setCharacterGuardCollision(char, on)
        if not char then return end
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") then
                if on then
                    if antiGuardCollisionOld[d] == nil then
                        local ok, group = pcall(function() return d.CollisionGroup end)
                        antiGuardCollisionOld[d] = ok and group or "Default"
                    end
                    pcall(function() d.CollisionGroup = antiGuardCollisionGroup end)
                else
                    local old = antiGuardCollisionOld[d]
                    if old ~= nil then
                        pcall(function() d.CollisionGroup = old end)
                    end
                    antiGuardCollisionOld[d] = nil
                end
            end
        end
    end

    local function restoreCharacterGuardCollision()
        for obj, old in pairs(antiGuardCollisionOld) do
            if obj and obj.Parent then
                pcall(function() obj.CollisionGroup = old end)
            end
            antiGuardCollisionOld[obj] = nil
        end
    end

    local function antiGuardHeartbeat()
        if not antiGuardKnockback or antiGuardStealing then
            return
        end

        local now = os.clock()
        if now - antiGuardLast < 0.05 then
            return
        end
        antiGuardLast = now

        local character = svc.LocalPlayer and svc.LocalPlayer.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if not hrp then
            antiGuardPreviousVelocity = Vector3.zero
            return
        end

        local hum = character:FindFirstChildOfClass("Humanoid")
        local walkSpeed = hum and hum.WalkSpeed or 16
        local velocity = hrp.AssemblyLinearVelocity

        -- f16() in the source implementation is the dynamic movement-speed
        -- allowance.  This hub already has the same safety inputs locally, so
        -- use the current WalkSpeed as the dynamic floor and retain the source
        -- minimum of 100 studs/s.
        local velocityThreshold = math.max(walkSpeed * 1.5, 100)
        local deltaMagnitude = (velocity - antiGuardPreviousVelocity).Magnitude

        if velocity.Magnitude > velocityThreshold and deltaMagnitude > 40 then
            pcall(function()
                hrp.AssemblyLinearVelocity = Vector3.zero
                hrp.AssemblyAngularVelocity = Vector3.zero
            end)
            velocity = Vector3.zero
        end

        antiGuardPreviousVelocity = velocity
    end

    local function setAntiGuardKnockback(on)
        on = on == true
        if on == antiGuardKnockback and ((on and antiGuardKnockbackSc) or not on) then
            return true
        end

        antiGuardKnockback = on
        antiGuardLast = 0
        antiGuardPreviousVelocity = Vector3.zero

        if antiGuardKnockbackSc then
            antiGuardKnockbackSc:destroy()
            antiGuardKnockbackSc = nil
        end

        if not on then
            restoreCharacterGuardCollision()
            return true
        end

        antiGuardKnockbackSc = BX.scope("features.guard.anti_guard_knockback")
        local character = svc.LocalPlayer and svc.LocalPlayer.Character
        if character then
            setCharacterGuardCollision(character, true)
        end

        antiGuardKnockbackSc:onFrame("knockback_guard", RunService.Heartbeat, antiGuardHeartbeat)

        antiGuardKnockbackSc:connect(svc.LocalPlayer.CharacterAdded, function(character)
            antiGuardPreviousVelocity = Vector3.zero
            task.defer(function()
                if antiGuardKnockback then
                    local hum = character:WaitForChild("Humanoid", 5)
                    if hum then setCharacterGuardCollision(character, true) end
                end
            end)

            antiGuardKnockbackSc:connect(character.DescendantAdded, function(descendant)
                if not antiGuardKnockback or not descendant:IsA("BasePart") then return end
                if antiGuardCollisionOld[descendant] == nil then
                    local ok, group = pcall(function() return descendant.CollisionGroup end)
                    antiGuardCollisionOld[descendant] = ok and group or "Default"
                end
                pcall(function() descendant.CollisionGroup = antiGuardCollisionGroup end)
            end)
        end)

        -- Also catch parts added to the current character after arming.
        if character then
            antiGuardKnockbackSc:connect(character.DescendantAdded, function(descendant)
                if not antiGuardKnockback or not descendant:IsA("BasePart") then return end
                if antiGuardCollisionOld[descendant] == nil then
                    local ok, group = pcall(function() return descendant.CollisionGroup end)
                    antiGuardCollisionOld[descendant] = ok and group or "Default"
                end
                pcall(function() descendant.CollisionGroup = antiGuardCollisionGroup end)
            end)
        end

        return true
    end

    -- Auto Steal tells this lightweight shield when it owns the character.
    -- During a steal the existing guard anti-hit/carry protection remains in
    -- charge; this shield stands down exactly like the supplied source logic.
    function M.setStealing(on)
        antiGuardStealing = on == true
        if antiGuardStealing then
            antiGuardPreviousVelocity = Vector3.zero
        end
    end

    function M.setAntiGuardKnockback(on)
        return setAntiGuardKnockback(on)
    end

    -- Optional client-side Guard visual suppression. This does NOT delete server
    -- NPCs; it only hides common guard models locally and makes their hitbox less
    -- intrusive on mobile. Auto Farm's existing anti-hit remains authoritative
    -- for the local character.
    local antiGuardVisualSc = nil
    local antiGuardHidden = setmetatable({}, {__mode = "k"})

    local function looksLikeGuard(inst)
        if not inst or not inst:IsA("Model") then return false end
        local n = tostring(inst.Name or ""):lower()
        if n:find("guard", 1, true) or n:find("security", 1, true)
            or n:find("police", 1, true) then
            return true
        end
        -- Current game also exposes live guards as _Guards/<AreaId> and
        -- GuardAreas/<AreaId>/Guard. Name-only matching missed those models.
        local parent = inst.Parent
        while parent and parent ~= workspace do
            local pn = tostring(parent.Name or ""):lower()
            if pn == "_guards" or pn == "guardareas" then return true end
            parent = parent.Parent
        end
        return inst:FindFirstChildOfClass("Humanoid") ~= nil
            and (inst:GetAttribute("AreaId") ~= nil or inst:GetAttribute("DELL_GuardArea") ~= nil)
    end

    local function hideGuardModel(model)
        if not model or not model:IsA("Model") or not looksLikeGuard(model) then return end
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then
                if antiGuardHidden[d] == nil then
                    antiGuardHidden[d] = {t = d.Transparency, c = d.CanCollide, q = d.CanQuery, touch = d.CanTouch}
                end
                pcall(function() d.LocalTransparencyModifier = 1 end)
                pcall(function() d.CanQuery = false end)
                pcall(function() d.CanTouch = false end)
                pcall(function() d.CanCollide = false end)
            elseif d:IsA("Decal") or d:IsA("Texture") then
                if antiGuardHidden[d] == nil then antiGuardHidden[d] = {t = d.Transparency} end
                pcall(function() d.Transparency = 1 end)
            end
        end
    end

    local function restoreGuardVisuals()
        for obj, old in pairs(antiGuardHidden) do
            if obj and obj.Parent and old then
                if obj:IsA("BasePart") then
                    pcall(function() obj.LocalTransparencyModifier = 0 end)
                    if old.c ~= nil then pcall(function() obj.CanCollide = old.c end) end
                    if old.q ~= nil then pcall(function() obj.CanQuery = old.q end) end
                    if old.touch ~= nil then pcall(function() obj.CanTouch = old.touch end) end
                elseif obj:IsA("Decal") or obj:IsA("Texture") then
                    if old.t ~= nil then pcall(function() obj.Transparency = old.t end) end
                end
            end
            antiGuardHidden[obj] = nil
        end
    end

    function M.setAntiGuard(on)
        on = on and true or false
        setAntiGuardKnockback(on)
        if on then
            if antiGuardVisualSc then return true end
            antiGuardVisualSc = BX.scope("features.guard.anti_guard")
            local function scan()
                local count = 0
                for _, d in ipairs(workspace:GetDescendants()) do
                    if d:IsA("Model") and looksLikeGuard(d) then hideGuardModel(d); count += 1 end
                end
                log.info("anti-guard visual scan: %d model(s)", count)
            end
            antiGuardVisualSc:spawn("initial_scan", scan)
            antiGuardVisualSc:connect(workspace.DescendantAdded, function(d)
                if d:IsA("Model") then task.defer(hideGuardModel, d) end
            end)
            return true
        end
        if antiGuardVisualSc then antiGuardVisualSc:destroy(); antiGuardVisualSc = nil end
        restoreGuardVisuals()
        return true
    end

    function M.antiGuardOn() return antiGuardVisualSc ~= nil end

    return M
end)

--[[ ==== features/farm/filter.lua ==================================== ]]
-- =============================================================================
-- FEATURES.FARM.FILTER: what Farm is allowed to take, and which one first
-- =============================================================================
--
--     local filter = BX.require("features.farm.filter")
--     filter.areaOptions()      -- { {id=, label=}, ... } for the dropdown
--     filter.rarityOptions()    -- weakest first, the way the game orders them
--     filter.setAreas{ "Forest" }
--     filter.setRarities{ "Legendary" }
--     filter.setTargetBy("Weight")
--     filter.pick()             -- the egg to go for now, or nil
--     filter.describe()         -- one short line for the log
--
-- IT HOLDS A SELECTION. IT DOES NOT STEAL, MOVE OR SCAN.
--
-- pick() reads features.eggs' ALREADY CACHED list and filters it in memory.
-- There is no second field read, no Workspace walk and no cache of its own, so
-- changing a dropdown costs nothing and cannot start, stop or disturb a run.
--
-- TARGET BY IS EXACTLY TWO MODES, traced from V3.1 rather than guessed:
--
--     FarmTab:CreateDropdown{ name = "Target By", options = { "Income", "Weight" } }
--
-- and V3.1 says why both exist: "The scale roll is per egg, so the same pet
-- turns up at 7.3kg and 20.4kg on the same map. Income cannot see that
-- difference at all - both rows said the same number - so weight is a genuinely
-- different target, not a reordering of the same one." Nothing else was offered,
-- so nothing else is invented here.
--
-- STABLE IDS, FRIENDLY LABELS.
--
-- Areas are matched on Data.Areas.Directory keys, which are the entry's own
-- `_id`, and an egg record's AreaId is that same string - measured on the live
-- game: Directory keys and live AreaId values are both exactly
-- { Abyss Ocean, Cherry Blossom, Cosmic, Desert, Forest, Jungle, Lake,
--   Prehistoric, Snow, Titan Temple, Volcano }.
-- They happen to read the same as the DisplayName today; they are kept as
-- separate fields anyway so a future display rename cannot silently empty
-- somebody's saved selection.
--
-- AN EMPTY SELECTION MEANS "ANY", NOT "NONE".
--
-- No areas picked = the whole map; no rarities picked = any rarity. That is
-- V3.1's behaviour and it is the only sane reading of an empty filter - the
-- alternative is a farm that silently does nothing.

BX.module("features.farm.filter", function(BX)
    local data = BX.require("core.data")
    local eggs = BX.require("features.eggs")
    local log  = BX.require("boot.log").for_module("farm.filter")

    local M = {}

    ---------- the game's own directories, read once ----------

    -- core.data resolves these by PATH. A bare recursive name search finds the
    -- FOLDER ReplicatedStorage.Assets instead of the ModuleScript at
    -- ReplicatedStorage.Data.Assets, which is what left every egg's rarity as
    -- "?" and every weight at 0. See core/data.lua.
    local function AreasDir() return data.areasDir() end
    local function AssetsDir() return data.assetsDir() end

    ---------- the selection ----------

    local areas    = {}          -- set of areaId -> true; empty = any
    local rarities = {}          -- set of rarityId -> true; empty = any
    local targetBy = "Income"    -- "Income" | "Weight"

    local function count(set)
        local n = 0
        for _ in pairs(set) do n = n + 1 end
        return n
    end

    local function toSet(list)
        local set = {}
        if type(list) == "table" then
            for _, v in pairs(list) do
                if v ~= nil and v ~= "" then set[tostring(v)] = true end
            end
        elseif type(list) == "string" and list ~= "" then
            set[list] = true
        end
        return set
    end

    ---------- what the dropdowns offer ----------

    -- Sorted alphabetically: the game's Directory is a hash, so without this the
    -- list order changes between sessions and the dropdown looks shuffled.
    function M.areaOptions()
        local out = {}
        for id, entry in pairs(AreasDir() or {}) do
            out[#out + 1] = {
                id = tostring(id),
                label = tostring((type(entry) == "table" and entry.DisplayName) or id),
            }
        end
        table.sort(out, function(a, b) return a.label < b.label end)
        return out
    end

    -- Weakest first, by Rarity.RarityNumber (1..10), exactly as V3.1 ordered it.
    function M.rarityOptions()
        local seen, rows = {}, {}
        for _, entry in pairs(AssetsDir() or {}) do
            local r = type(entry) == "table" and entry.Rarity or nil
            if type(r) == "table" then
                local id = tostring(r._id or r.DisplayName or "")
                if id ~= "" and not seen[id] then
                    seen[id] = true
                    rows[#rows + 1] = {
                        id = id,
                        label = tostring(r.DisplayName or id),
                        num = tonumber(r.RarityNumber) or 0,
                    }
                end
            end
        end
        table.sort(rows, function(a, b)
            if a.num ~= b.num then return a.num < b.num end
            return a.label < b.label
        end)
        return rows
    end

    function M.targetByOptions() return { "Income", "Weight" } end

    ---------- setting it ----------

    function M.setAreas(list)
        areas = toSet(list)
        log.info("areas: %s", count(areas) == 0 and "any" or tostring(count(areas)))
    end

    function M.setRarities(list)
        rarities = toSet(list)
        log.info("rarities: %s", count(rarities) == 0 and "any" or tostring(count(rarities)))
    end

    function M.setTargetBy(v)
        targetBy = (v == "Weight") and "Weight" or "Income"
        log.info("target by: %s", targetBy)
    end

    function M.selection()
        return { areas = areas, rarities = rarities, targetBy = targetBy }
    end

    function M.describe()
        return ("%s areas, %s rarities, by %s"):format(
            count(areas) == 0 and "all" or tostring(count(areas)),
            count(rarities) == 0 and "any" or tostring(count(rarities)),
            targetBy)
    end

    ---------- choosing a target ----------

    local function rarityOk(e)
        if count(rarities) == 0 then return true end
        -- Records carry both the rarity's _id and its display name; options carry
        -- the _id. They are the same string in this game, and matching either way
        -- keeps a mismatch from emptying the filter silently.
        local id = tostring(e.rarityId or e.rarity or "")
        local label = tostring(e.rarity or "")
        return rarities[id] == true or rarities[label] == true
    end

    local function wanted(e)
        if count(areas) > 0 and not areas[tostring(e.areaId)] then return false end
        return rarityOk(e)
    end

    -- THE ONE THE RUN SHOULD GO FOR, chosen fresh every cycle.
    --
    -- Handed to features.autosteal as a closure, so the steal engine never
    -- learns what a rarity or an area is - it asks for a target and gets one.
    -- Returns the egg, or nil plus a REASON that names the stage which emptied
    -- the list. "pick() returned nil" is not actionable; "field=51 area=0" is.
    -- The last answer, for the Farm tab's status line. Written by pick()
    -- and matchCount(), read on a timer; never computed by the reader.
    local last = { text = "waiting for the first pass", n = 0, field = 0, degraded = nil }
    function M.status() return last end

    -- DEGRADED EGG DATA IS A DIFFERENT FAILURE FROM AN EMPTY FILTER.
    --
    -- On an executor where the game's data modules cannot be read, features/
    -- eggs falls back to slot attributes: records with a uid and a position
    -- and nothing else - no AreaId, rarity "?", weight 0. Main still works
    -- (it steals by uid and position), but ANY area or rarity filter matches
    -- nothing, forever, and the switch looks broken. That is the report:
    -- "Main works, Farm does nothing". Detected here and named, so the tab
    -- can say "clear the filter" instead of "0 match".
    local function degradedFor(list)
        local anyArea, anyRarity = false, false
        for _, e in ipairs(list) do
            if e.areaId ~= nil then anyArea = true end
            if e.rarity and e.rarity ~= "?" then anyRarity = true end
            if anyArea and anyRarity then return nil end
        end
        if count(areas) > 0 and not anyArea then
            return "eggs carry no area on this executor - clear the Areas filter"
        end
        if count(rarities) > 0 and not anyRarity then
            return "eggs carry no rarity on this executor - clear the Rarities filter"
        end
        return nil
    end

    function M.pick()
        local list = eggs.list()          -- cached; no rescan, no force
        local field = list and #list or 0
        if field == 0 then
            last = { text = "no takeable eggs on the field", n = 0, field = 0 }
            return nil, "field=0 (no takeable eggs listed)"
        end

        local afterArea, afterRarity = 0, 0
        local best, bestKey
        for _, e in ipairs(list) do
            local areaOk = (count(areas) == 0) or areas[tostring(e.areaId)] == true
            if areaOk then
                afterArea = afterArea + 1
                if rarityOk(e) then
                    afterRarity = afterRarity + 1
                    local key = (targetBy == "Weight") and (tonumber(e.kg) or 0)
                                                       or (tonumber(e.value) or 0)
                    if not best or key > bestKey then best, bestKey = e, key end
                end
            end
        end

        if best then
            last = { text = ("%d of %d eggs match  \u{B7}  next: %s"):format(afterRarity, field, tostring(best.name)),
                     n = afterRarity, field = field }
            return best
        end

        local degraded = degradedFor(list)
        local why = ("all eggs discovered=%d area-matched=%d rarity-matched=%d target candidates=%d final eligible=0 (%s)")
            :format(field, afterArea, afterRarity, afterRarity, M.describe())
        if degraded then why = why .. " - " .. degraded end
        last = {
            text = degraded or ("0 of %d eggs match your filters  \u{B7}  waiting"):format(field),
            n = 0, field = field, degraded = degraded,
        }
        return nil, why
    end

    -- How many of the current field pass the filter. For the UI's own label, not
    -- for the steal path.
    function M.matchCount()
        local list = eggs.list()
        local n = 0
        for _, e in ipairs(list or {}) do
            if wanted(e) then n = n + 1 end
        end
        return n
    end

    return M
end)

--[[ ==== features/farm/treadmill_on.lua ============================== ]]
-- =============================================================================
-- FEATURES.FARM.TREADMILL_ON: park on the belt and stay there
-- =============================================================================
--
--     local hold = BX.require("features.farm.treadmill_on")
--     hold.setEnabled(true)
--     hold.isOn()
--
-- THE OPPOSITE OF features/treadmill.lua, ON PURPOSE.
--
--     Anti Treadmill (Main)      keeps a run from being caught by the belt
--     Stay On Treadmill (Farm)   deliberately parks you on it to farm AFK
--
-- They cannot both act. state.stayOnTreadmill is written here and read there:
-- while this is on, the Anti Treadmill poll stands down instead of doffing the
-- player every 1.5s. That flag is the entire interaction between them - no
-- cross-module calls, no ordering to remember.
--
-- THERE IS NOTHING TO FIRE TO GET ON THE BELT.
--
-- Read out of the game's own PlayerScripts.Game.Plots.TreadmillStaticController:
--
--     RunService.Heartbeat:Connect(tryEnterStaticTreadmill)
--
-- and tryEnterStaticTreadmill raycasts 8 studs DOWN from the HumanoidRootPart,
-- filtered to your own treadmill render and its belt part. If it hits, the GAME
-- calls Treadmill.AskWearStill itself. So this toggle only has to put the
-- character over the belt; the game does the mounting, every frame, for free.
--
-- GETTING OFF DOES TAKE A REMOTE, AND THAT IS THE HALF THAT USED TO BE MISSING.
--
-- Switching the hold off only stops us putting you back - you are still wearing
-- the belt, and stepping off puts you straight back on at the next Heartbeat.
-- RF/Treadmill/AskDoff is the other half of the pair: ask, then step clear so
-- the game's own check does not immediately re-wear you.
--
-- ONE THING DRIVES THE CHARACTER AT A TIME.
--
-- Auto Steal flies the character across the map; a hold pulling it back to the
-- plot mid-carry is how eggs get dropped. Enabling this during a run is refused,
-- and if a run somehow starts while it is on, the hold pauses rather than fights.
--
-- THE SPOT IS RESOLVED FRESH, NOT CACHED.
--
-- The client rebuilds TreadmillRender_<slot> on every treadmill upgrade, so a
-- cached part reference goes stale the moment the player upgrades. It is two
-- FindFirstChild calls against a known path - cheaper than the bug.

BX.module("features.farm.treadmill_on", function(BX)
    local svc = BX.require("core.services")
    local data = BX.require("core.data")
    local ch  = BX.require("core.character")
    local dev = BX.require("core.device")
    local net = BX.require("core.net")
    local st  = BX.require("core.state")
    local log = BX.require("boot.log").for_module("farm.treadmill")

    local M = {}

    local K = {
        POLL     = 1.0,    -- how often to check we are still on the spot
        DRIFT    = 6,      -- studs away from the spot before nudging back
        STEP_OFF = 14,     -- how far clear to stand when releasing
    }
    M.K = K

    -- THROUGH core.data. A private FindFirstChild + require here bypassed
    -- the one place that knows whether this executor can require game
    -- modules at all, and cached a miss forever. core.data probes once,
    -- lets a miss expire, and backs off - see core/data.lua.
    local PlotState = data.plotState()

    local sc = nil
    local enabled = false
    local stats = { nudges = 0, paused = 0, doffed = 0, noSpot = 0 }
    function M.stats() return table.clone(stats) end
    function M.isOn() return enabled end

    -- Where our own belt is. V3.1 BX.treadmillSpot, same two sources in the
    -- same order: the client render's Root, then the plot's TreadmillBottom
    -- (measured 0.001 studs thick and ~4 studs under Root, so stand above it).
    function M.spot()
        local slot
        BX.try("farm.treadmill.slot", function()
            slot = PlotState and PlotState.ResolveLocalSlot and PlotState.ResolveLocalSlot()
        end)
        if not slot then return nil end

        local pos
        BX.try("farm.treadmill.spot", function()
            local folder = workspace:FindFirstChild("__ClientTreadmillRenders")
            local render = folder and folder:FindFirstChild("TreadmillRender_" .. tostring(slot))
            local root = render and render:FindFirstChild("Root")
            if root and root:IsA("BasePart") then
                pos = root.Position
                return
            end
            local plots = workspace:FindFirstChild("Plots")
            local plot = plots and plots:FindFirstChild(tostring(slot))
            local bottom = plot and plot:FindFirstChild("TreadmillBottom")
            if bottom and bottom:IsA("BasePart") then
                pos = bottom.Position + Vector3.new(0, 4, 0)
            end
        end)
        return pos
    end

    local function place(pos)
        local hrp = ch.root()
        if not hrp or not pos then return false end
        local ok = BX.try("farm.treadmill.place", function()
            hrp.CFrame = CFrame.new(pos)
        end)
        return ok and true or false
    end

    local function step()
        if not enabled then return end

        -- A run owns the character: stand down for its duration rather than
        -- pulling it back to the plot mid-carry.
        if st.autoStealOn then
            stats.paused = stats.paused + 1
            return
        end

        local pos = M.spot()
        if not pos then
            stats.noSpot = stats.noSpot + 1
            return
        end

        local hrp = ch.root()
        if not hrp then return end
        if (hrp.Position - pos).Magnitude > K.DRIFT then
            if place(pos) then
                stats.nudges = stats.nudges + 1
                log.trace("nudged back onto the belt")
            end
        end
    end

    function M.setEnabled(on)
        on = on and true or false
        if on == enabled then return true end

        if on then
            -- Refused rather than silently queued: the caller flips its toggle
            -- back so the UI never claims something that is not happening.
            if st.autoStealOn then
                log.warn("refused - Auto Steal is running")
                return false, "Turn Auto Steal off first"
            end

            local pos = M.spot()
            if not pos then
                log.warn("refused - could not resolve your treadmill")
                return false, "Could not find your treadmill"
            end

            enabled = true
            st.stayOnTreadmill = true          -- Anti Treadmill stands down
            place(pos)

            sc = BX.scope("features.farm.treadmill_on")
            sc:loop("hold", dev.scale(K.POLL), step)
            -- A respawn puts the character back at the plot spawn, not on the
            -- belt, so walk it back on rather than waiting for a drift check.
            ch.onSpawn(sc, "farm.treadmill.respawn", function()
                if enabled and not st.autoStealOn then place(M.spot()) end
            end)

            log.info("holding on the belt (poll %.1fs)", dev.scale(K.POLL))
            return true
        end

        -- Releasing. Order matters: stop holding, ASK to be let off, then step
        -- clear - otherwise the game's Heartbeat check re-wears us immediately.
        enabled = false
        st.stayOnTreadmill = false
        if sc then sc:destroy() sc = nil end

        local ok, msg = net.call("RF/Treadmill/AskDoff")
        if ok == true then
            stats.doffed = stats.doffed + 1
        else
            log.warn("AskDoff refused: %s %s", tostring(ok), tostring(msg or ""))
        end

        local pos = M.spot()
        if pos then place(pos + Vector3.new(0, 3, K.STEP_OFF)) end

        log.info("released (%d nudges, %d paused for a run)", stats.nudges, stats.paused)
        return true
    end

    return M
end)

--[[ ==== features/esp/cards.lua ====================================== ]]
-- =============================================================================
-- FEATURES.ESP.CARDS: V3.1's ESP card, in the BlyxoHub tag's visual language
-- =============================================================================
--
--     local h = cards.open("eggs")
--     h:show(i, { pos=, title=, sub=, accent=, icon=, lines=, scale=, target= })
--     h:shown(n)     -- everything past slot n is hidden
--     h:close()
--
-- THE STRUCTURE IS V3.1'S, TRACED, NOT REDESIGNED.
--
--   anchor Part 0.2 studs, anchored, CanCollide/CanQuery/CanTouch/CastShadow off
--   BillboardGui  AlwaysOnTop, LightInfluence 0, MaxDistance 1e6, Active false,
--                 Adornee = anchor, PARENT = anchor (not a ScreenGui: a
--                 billboard in a protected container never renders)
--   frame 190x40, UICorner 8, ClipsDescendants, one UIScale
--   accent  2px wide, (1,-8) tall, at (3,4)     <- the rarity colour
--   icon    24x24 at (9,8)                      <- the pet's icon
--   title   (38,3)  (1,-44)x15  GothamBold 12
--   sub     (38,18) (1,-44)x20  Gotham 10, RichText
--
-- A POOL INDEXED BY SLOT, exactly as V3.1 does it: "built once, then reused for
-- whatever egg lands in this slot". Cards are never keyed by uid, so a field
-- that churns uids does not churn Instances.
--
-- AND CONSTRUCTION NEVER HAPPENS ON THE CALLER'S FRAME.
--
-- A card is 13 Instances and costs about 0.78ms to build. The first Egg ESP pass
-- wants 32 of them, and because that pass ran inside the toggle's own callback
-- the switch cost 19-42ms and dropped a frame EVERY time it went on - measured
-- on the live client. show() now queues a slot it has no card for, and the frame
-- handler builds K.BUILD_PER_FRAME of them per frame, so the full set is up in
-- about a fifth of a second and no frame pays for more than three.
--
-- The consequence to remember: the pool can briefly have HOLES, so nothing here
-- may use `#pool`. `pool.n` counts what exists and `pool.high` bounds the walk.
--
-- THE LOOK IS THE DELSHUB TAG'S.
--
-- Traced from V3.1's player tag: a vertical UIGradient from bgTop to bgBottom,
-- a UIStroke in Border mode carrying its OWN gradient from accent to element,
-- GothamBold for the name and Gotham for the detail. The tag is a pill because
-- it holds one word; a card holds three lines, so it keeps the tag's gradient,
-- stroke and type and takes the card's radius. They read as one hub.
--
-- ONE RenderStepped FOR EVERY CARD OF EVERY FEATURE, throttled to K.VIS_HZ,
-- doing exactly what V3.1's espVis does:
--
--   * enable/disable by distance, written only on change
--   * size follows distance through BlyxoEspScale, applied to the UIScale AND
--     the billboard together so the card grows as a whole
--   * opacity fades over the last K.FADE_BAND studs so edge cards dissolve
--     instead of popping
--   * every write guarded by a changed-by-more-than check
--
-- Nothing here allocates per frame: no tables are built in the loop.

BX.module("features.esp.cards", function(BX)
    local svc = BX.require("core.services")
    local dev = BX.require("core.device")
    local log = BX.require("boot.log").for_module("esp.cards")

    local M = {}

    local K = {
        W = 190, H = 40,
        VIS_HZ = 12,          -- V3.1 K.ESP_VIS_HZ cadence for the size follow
        MAX_DIST = 2200,      -- V3.1 K.ESP_MAX_DIST
        FADE_BAND = 260,      -- V3.1 K.ESP_FADE_BAND
        BASE_ALPHA = 0.42,    -- V3.1 frame.BackgroundTransparency
        BASE_STROKE = 0.55,
        -- CARDS PER FRAME, NOT CARDS PER PASS.
        --
        -- A card is 13 Instances. Measured on the live client: building one
        -- costs ~0.78ms, so the 32 cards the first Egg ESP pass asks for were
        -- 416 Instances and 19-42ms of work inside the toggle's own callback -
        -- one dropped frame every single time the switch went on. The pass now
        -- QUEUES what it wants and the frame handler builds a few per frame, so
        -- the cards still appear in about a fifth of a second and no single
        -- frame pays for more than three of them.
        BUILD_PER_FRAME = 3,
    }
    M.K = K

    -- The tag's palette, from V3.1 makeTag.
    local C = {
        bgTop   = Color3.fromRGB(26, 26, 30),
        bgBot   = Color3.fromRGB(14, 14, 17),
        accent  = Color3.fromRGB(206, 206, 212),
        element = Color3.fromRGB(41, 41, 48),
        title   = Color3.fromRGB(246, 242, 234),
        sub     = Color3.fromRGB(168, 158, 144),
    }

    -- THE ESP CARD'S TYPE AND INLINE PALETTE, shared by every card feature so
    -- Egg ESP and Plot ESP read as one hub. One constant table, handed to
    -- show() as `style`, applied once per card (compared by identity).
    --
    --     Pet Name                          GothamBold 13, the tag's ivory
    --     12.5M/s  ·  Divine  ·  8.42kg     Gotham 10: green, rarity, neutral
    --     Mutation                          amber
    --
    -- Colours are the hub's own: the splash's ONLINE green for income and
    -- READY, its WHITE for the weight, the stats overlay's WARN amber for a
    -- mutation, the splash's GREY for a countdown. The rarity keeps the
    -- game's colour for it.
    M.STYLE = {
        titleFont = Enum.Font.GothamBold, titleSize = 13,
        subFont   = Enum.Font.Gotham,     subSize   = 10,
    }
    M.COL = {
        income = "57F287", neutral = "F0F0F6", mutation = "F0BE5A",
        dim = "8A8A92", ready = "57F287",
    }
    M.SEP = "  \u{B7}  "

    function M.tint(col, text)
        return ('<font color="#%s">%s</font>'):format(col, text)
    end

    function M.hex(c)
        return ("%02X%02X%02X"):format(
            math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5),
            math.floor(c.B * 255 + 0.5))
    end

    -- V3.1 BlyxoEspScale, unchanged.
    local function scaleFor(dist)
        return math.clamp(1.25 - (tonumber(dist) or 0) / 800, 0.6, 1.25)
    end

    local sc, folder, handles = nil, nil, 0
    local pools = {}      -- handle name -> { cards }

    -- FORWARD-DECLARED, because the frame handler inside ensure() drains the
    -- build queue and therefore calls both - and a `local function` declared
    -- further down is not in scope up here, it compiles to a nil global.
    local build, apply

    local function ensure()
        if sc then return end
        sc = BX.scope("features.esp.cards")
        folder = Instance.new("Folder")
        folder.Name = "BlyxoESP"
        sc:own(folder)
        folder.Parent = workspace

        local acc, step = 0, 1 / K.VIS_HZ
        local mobileAcc = 0
        sc:onFrame("vis", svc.RunService.RenderStepped, function(dt)
            mobileAcc = mobileAcc + (dt or 0)
            if dev.lite() and mobileAcc < 0.10 then return end
            if dev.lite() then mobileAcc = 0 end

            -- DRAIN THE BUILD QUEUE FIRST, AND EVERY FRAME.
            --
            -- Above the throttle on purpose: the visibility pass only needs to
            -- run at K.VIS_HZ, but a queued card should appear as soon as the
            -- budget allows rather than waiting out a twelfth of a second. A few
            -- per frame is what keeps the enable off the caller's frame - see
            -- K.BUILD_PER_FRAME.
            local budget = dev.budget(K.BUILD_PER_FRAME)
            for _, pool in pairs(pools) do
                if budget <= 0 then break end
                for i, d in pairs(pool.pending) do
                    if budget <= 0 then break end
                    local c = build()
                    pool[i] = c
                    pool.n = pool.n + 1
                    if i > pool.high then pool.high = i end
                    apply(c, d)
                    pool.pending[i] = nil
                    budget = budget - 1
                end
            end

            acc = acc + (dt or 0)
            if acc < step then return end
            acc = 0
            local cam = workspace.CurrentCamera
            if not cam then return end
            local eye = cam.CFrame.Position

            for _, pool in pairs(pools) do
                for i = 1, pool.shown do
                    local c = pool[i]
                    if c and c.anchor.Parent then
                        local d = (c.pos - eye).Magnitude
                        local show = d <= K.MAX_DIST
                        if c.bb.Enabled ~= show then c.bb.Enabled = show end
                        if show then
                            local s = scaleFor(d)
                            if math.abs(c.lastScale - s) > 0.01 or c.lastH ~= c.baseH then
                                c.lastScale, c.lastH = s, c.baseH
                                c.scale.Scale = s
                                c.bb.Size = UDim2.fromOffset(K.W * s, c.baseH * s)
                            end
                            local fade = math.clamp((K.MAX_DIST - d) / K.FADE_BAND, 0, 1)
                            if math.abs(c.lastFade - fade) > 0.02 then
                                c.lastFade = fade
                                c.frame.BackgroundTransparency = 1 - (1 - K.BASE_ALPHA) * fade
                                c.title.TextTransparency = 1 - fade
                                c.sub.TextTransparency = 1 - fade
                                c.icon.ImageTransparency = 1 - fade
                                c.stroke.Transparency = 1 - (1 - K.BASE_STROKE) * fade
                            end
                        end
                    end
                end
            end
        end)
    end

    function build()
        local anchor = Instance.new("Part")
        anchor.Name = "EggAnchor"
        anchor.Anchored = true
        anchor.CanCollide = false
        anchor.CanQuery = false
        anchor.CanTouch = false
        anchor.CastShadow = false
        anchor.Transparency = 1
        anchor.Size = Vector3.new(0.2, 0.2, 0.2)
        anchor.Parent = folder

        local bb = Instance.new("BillboardGui")
        bb.Name = "EggCard"
        bb.AlwaysOnTop = true
        bb.LightInfluence = 0
        bb.MaxDistance = 1e6          -- not math.huge: some clients reject inf
        bb.Size = UDim2.fromOffset(K.W, K.H)
        bb.StudsOffset = Vector3.new(0, 3, 0)
        bb.Active = false
        bb.Adornee = anchor
        bb.Enabled = false
        bb.Parent = anchor

        local frame = Instance.new("Frame")
        frame.Size = UDim2.fromOffset(K.W, K.H)
        frame.BackgroundColor3 = Color3.new(1, 1, 1)
        frame.BackgroundTransparency = K.BASE_ALPHA
        frame.BorderSizePixel = 0
        frame.ClipsDescendants = true
        frame.Parent = bb
        Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

        -- The tag's vertical gradient.
        local grad = Instance.new("UIGradient", frame)
        grad.Color = ColorSequence.new(C.bgTop, C.bgBot)
        grad.Rotation = 90

        local scaleObj = Instance.new("UIScale")
        scaleObj.Scale = 1
        scaleObj.Parent = frame

        -- The tag's bordered stroke, with its own gradient.
        local stroke = Instance.new("UIStroke", frame)
        stroke.Color = Color3.new(1, 1, 1)
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Thickness = 1
        stroke.Transparency = K.BASE_STROKE
        local sg = Instance.new("UIGradient", stroke)
        sg.Color = ColorSequence.new(C.accent, C.element)
        sg.Rotation = 90

        local accent = Instance.new("Frame")
        accent.Name = "Accent"
        accent.Position = UDim2.fromOffset(3, 4)
        accent.Size = UDim2.new(0, 2, 1, -8)
        accent.BorderSizePixel = 0
        accent.BackgroundColor3 = Color3.fromRGB(194, 142, 54)
        accent.Parent = frame
        Instance.new("UICorner", accent).CornerRadius = UDim.new(1, 0)

        local icon = Instance.new("ImageLabel")
        icon.Name = "Icon"
        icon.Position = UDim2.fromOffset(9, 8)
        icon.Size = UDim2.fromOffset(24, 24)
        icon.BackgroundTransparency = 1
        icon.ScaleType = Enum.ScaleType.Fit
        icon.Image = ""
        icon.Parent = frame

        local title = Instance.new("TextLabel")
        title.Name = "Title"
        title.Position = UDim2.fromOffset(38, 3)
        title.Size = UDim2.new(1, -44, 0, 15)
        title.BackgroundTransparency = 1
        title.Font = Enum.Font.GothamBold
        title.TextSize = 12
        title.TextColor3 = C.title
        title.TextXAlignment = Enum.TextXAlignment.Left
        title.TextTruncate = Enum.TextTruncate.AtEnd
        title.Text = ""
        title.Parent = frame

        local sub = Instance.new("TextLabel")
        sub.Name = "Sub"
        sub.Position = UDim2.fromOffset(38, 18)
        sub.Size = UDim2.new(1, -44, 0, 20)
        sub.BackgroundTransparency = 1
        sub.Font = Enum.Font.Gotham
        sub.TextSize = 10
        sub.TextColor3 = C.sub
        sub.TextXAlignment = Enum.TextXAlignment.Left
        sub.TextYAlignment = Enum.TextYAlignment.Top
        sub.RichText = true          -- the rarity is coloured inline, as in V3.1
        sub.Text = ""
        sub.Parent = frame

        return {
            anchor = anchor, bb = bb, frame = frame, stroke = stroke,
            accent = accent, icon = icon, title = title, sub = sub,
            scale = scaleObj, pos = Vector3.zero, baseH = K.H,
            lastScale = -1, lastFade = -1, lastH = -1,
            lastTitle = nil, lastSub = nil, lastIcon = nil, lastStyle = nil,
        }
    end

    -- Writes one card's fields. Every write is guarded, so an unchanged card
    -- costs nothing. Shared by the live path and the deferred builder, so a card
    -- that was queued last frame is filled by exactly the same code.
    function apply(c, d)
        if c.pos ~= d.pos then
            c.pos = d.pos
            c.anchor.CFrame = CFrame.new(d.pos)
        end

        -- Mutations get their own line and the card grows to fit, as in V3.1.
        local h = (d.lines and d.lines > 1) and (K.H + 12) or K.H
        if c.baseH ~= h then
            c.baseH = h
            c.frame.Size = UDim2.fromOffset(K.W, h)
            c.sub.Size = UDim2.new(1, -44, 0, h - 20)
        end

        local titleText = (d.target and "\u{25B8} " or "") .. tostring(d.title or "")
        if titleText ~= c.lastTitle then
            c.lastTitle = titleText
            c.title.Text = titleText
        end
        if d.sub ~= c.lastSub then
            c.lastSub = d.sub
            c.sub.Text = tostring(d.sub or "")
        end
        if d.icon ~= c.lastIcon then
            c.lastIcon = d.icon
            c.icon.Image = tostring(d.icon or "")
        end
        if d.accent then c.accent.BackgroundColor3 = d.accent end

        -- OPTIONAL TYPE OVERRIDE, per feature. A pool belongs to one feature,
        -- so a card only ever sees its owner's style; a feature that passes
        -- none keeps the V3.1 defaults built above. Compared by identity: the
        -- caller hands in one constant table, so this write happens once per
        -- card, not per pass.
        local st = d.style
        if st ~= c.lastStyle then
            c.lastStyle = st
            c.title.Font = (st and st.titleFont) or Enum.Font.GothamBold
            c.title.TextSize = (st and st.titleSize) or 12
            c.sub.Font = (st and st.subFont) or Enum.Font.Gotham
            c.sub.TextSize = (st and st.subSize) or 10
        end
    end

    local Handle = {}
    Handle.__index = Handle

    -- Fills slot `i`, or QUEUES it when that slot has no card yet.
    --
    -- THE CALLER NEVER PAYS FOR CONSTRUCTION. Building a card is 13 Instances,
    -- and a first pass asking for 32 of them inside a toggle callback is the
    -- 19-42ms hitch that was measured every time Egg ESP went on. The queue is
    -- drained a few cards per frame by the handler in ensure(), so the cost is
    -- spread over a fifth of a second instead of landing in one frame.
    function Handle:show(i, d)
        local pool = pools[self.name]
        local c = pool[i]
        if not c then
            pool.pending[i] = d
            return
        end
        apply(c, d)
    end

    -- Everything past slot n is hidden, not destroyed: the pool is the point.
    --
    -- Bounded by `high` rather than `#pool`: deferred construction means the
    -- pool can briefly have holes, and `#` on a table with holes is undefined -
    -- it would leave a card past the cut still drawn.
    function Handle:shown(n)
        local pool = pools[self.name]
        pool.shown = n
        for i = n + 1, pool.high do
            local c = pool[i]
            if c and c.bb.Enabled then c.bb.Enabled = false end
        end
        -- A slot past the cut is no longer wanted: drop its queued request
        -- rather than building a card that is about to be hidden.
        for i in pairs(pool.pending) do
            if i > n then pool.pending[i] = nil end
        end
    end

    function Handle:count()
        local pool = pools[self.name]
        return pool.n, pool.shown
    end

    function Handle:close()
        local pool = pools[self.name]
        for i = 1, pool.high do
            local c = pool[i]
            if c then pcall(function() c.anchor:Destroy() end) end
        end
        pools[self.name] = nil
        handles = handles - 1
        if handles <= 0 then
            handles = 0
            if sc then sc:destroy() sc = nil end
            folder, pools = nil, {}
            log.info("released")
        end
    end

    function M.open(name)
        ensure()
        handles = handles + 1
        pools[name] = { shown = 0, pending = {}, n = 0, high = 0 }
        return setmetatable({ name = name }, Handle)
    end

    function M.liveCount()
        local n = 0
        for _, pool in pairs(pools) do n = n + pool.n end
        return n
    end

    -- How many cards are still queued, across every pool. Watched so a queue
    -- that stops draining is visible in the health line rather than showing up
    -- as "the ESP only draws half the eggs".
    function M.pendingCount()
        local n = 0
        for _, pool in pairs(pools) do
            for _ in pairs(pool.pending) do n = n + 1 end
        end
        return n
    end

    BX.profile.watch("esp.cards", M.liveCount)
    BX.profile.watch("esp.cards.queued", M.pendingCount)

    return M
end)

--[[ ==== features/fps.lua ============================================ ]]
-- =============================================================================
-- FEATURES.FPS: render cheaper, change nothing that matters, put it all back
-- =============================================================================
--
--     BX.require("features.fps").arm()          -- default ON, deferred
--     BX.require("features.fps").setEnabled(on)
--     BX.require("features.fps").stats()
--
-- NOTHING IS DESTROYED. EVERY CHANGE IS A PROPERTY, AND EVERY PROPERTY IS
-- WRITTEN DOWN BEFORE IT IS TOUCHED.
--
-- That is not fastidiousness, it is a hard requirement in this script. The steal
-- path reads egg models, nest markers and prompt parts straight out of the
-- workspace, and the usual "delete every decal and particle" boost takes those
-- with it and breaks the thing you are here to run. One list of
-- { object, property, previous value } is the whole design; OFF walks it
-- backwards and the world is exactly as it was.
--
-- MEASURED ON THE LIVE GAME, which is what the set below is chosen from:
--
--     44,148 workspace descendants, 14.7ms to walk once
--     403 enabled effects   259 ParticleEmitter, 133 Beam, 11 Trail
--     0 Smoke, 0 Fire, 0 Sparkles   (handled anyway; other builds have them)
--     SunRaysEffect enabled, 2 DepthOfFieldEffect already off
--     GlobalShadows true, Technology ShadowMap
--     QualityLevel Automatic
--
-- WHAT V3.1 DID THAT IS NOT WORTH DOING.
--
--   * Terrain.Decoration - NOT A PROPERTY OF Terrain ON THIS BUILD. V3.1 wrapped
--     its terrain block in one pcall, so the write threw on the first line and
--     silently took WaterWaveSize and WaterReflectance down with it. Every
--     property here is written through its own guard for exactly that reason.
--
--   * Lighting.FogEnd = 1e6 - FogEnd is ALREADY 100,000 in this place. Raising
--     it further buys no frames and is a visible change to the sky for nothing,
--     so it is dropped.
--
--   * Lighting.Brightness - V3.1 saved it and then never changed it. Saving a
--     property you do not write is how a restore list grows entries that mean
--     nothing.
--
-- AND ONE THING THIS TRIED AND GAVE UP ON.
--
-- EnvironmentDiffuseScale / EnvironmentSpecularScale were in the set and are not
-- any more. Measured: the apply wrote both to 0 and recorded them, and eight
-- seconds later they read 0.75 and 0.7 again - the game re-applies its own
-- lighting shortly after a join, which is exactly the window the deferred apply
-- lands in. Set by hand later they stay put, so this is a race with the game and
-- not a permissions problem.
--
-- Winning it would mean a PropertyChangedSignal re-asserting both forever. For
-- two cosmetic scalars that is not a trade worth making, and a restore list that
-- claims to own a property the game overwrites is worse than not listing it:
-- switching the boost off would then write a stale value back over whatever the
-- game had decided. Dropped, on purpose.
--
-- AND WHAT IT DID NOT DO AT ALL: survive a re-execute. V3.1 held its record in a
-- module local, so re-running the script left the previous copy's changes applied
-- with nothing left that knew about them - shadows off, 400 emitters off, and no
-- way back short of rejoining. The record lives in the shared environment here,
-- so a new copy finds the old one's work and undoes it before doing its own.
--
-- THE SWEEP HAPPENS ONCE, OFF THE CALLER'S FRAME, IN CHUNKS, AND POST-
-- PROCESSING GOES FIRST.
--
-- One GetDescendants is unavoidable to find the 403 effects already in the world
-- and it costs 14.7ms. It runs on its own thread, so the toggle callback returns
-- immediately, and the iteration is chunked with a yield between chunks so the
-- only cost charged to a single frame is that one walk. After that there is NO
-- LOOP: new effects arrive through DescendantAdded, which is one hash lookup per
-- added instance.
--
-- WHAT IS DELIBERATELY LEFT ALONE:
--
--     our own BlyxoESP folder        the cards are the feature, not a cost
--     the local character            visibility and gameplay cues stay
--     anything not in EFFECTS        no geometry, no decals, no prompts, no UI
--
-- TRACKING IS BOUNDED AND SELF-CLEANING. K.MAX_TRACKED is a hard ceiling, and a
-- slow prune drops entries whose Instance has been destroyed - both so the list
-- cannot grow for the rest of a session just because the game keeps spawning
-- effects, and so a destroyed emitter is not held alive by our own restore list.

BX.module("features.fps", function(BX)
    local svc = BX.require("core.services")
    local log = BX.require("boot.log").for_module("fps")

    local M = {}

    local K = {
        MAX_TRACKED = 4000,   -- ceiling on remembered effects (403 live today)
        CHUNK       = 1200,   -- descendants examined between yields
        PRUNE_EVERY = 30,     -- seconds between destroyed-instance sweeps
        DEFER       = 2.0,    -- seconds after startup before the first apply
    }
    M.K = K

    -- Exact ClassNames, looked up in one hash instead of a chain of IsA calls.
    -- DescendantAdded fires for every one of 44k instances on join and for every
    -- egg afterwards, so the cost of the test matters more than its elegance.
    -- All six are concrete classes, so ClassName equality is the right test.
    local EFFECTS = {
        ParticleEmitter = true, Trail = true, Beam = true,
        Smoke = true, Fire = true, Sparkles = true,
        Texture = true, Decal = true,
    }

    -- EXTREME mode also reduces expensive per-part rendering without deleting
    -- geometry. CastShadow is disabled and MeshPart RenderFidelity is lowered
    -- to Performance. Both properties are tracked and restored on OFF.

    -- PostEffect is abstract; these are its concrete subclasses. Listed rather
    -- than IsA-tested for the same reason.
    local POST = {
        BloomEffect = true, BlurEffect = true, ColorCorrectionEffect = true,
        SunRaysEffect = true, DepthOfFieldEffect = true,
    }

    ---------- the restore record, shared across generations ----------

    local env = (type(getgenv) == "function" and getgenv()) or _G
    local ENV_KEY = "__BLYXO_FPS"

    -- ONE SHAPE FOR EVERYTHING: { obj, key, was }. Lighting, Terrain, the render
    -- settings and 400 emitters all restore through the same loop, so there is
    -- no second code path that can be forgotten.
    local function newRecord()
        return { props = {}, n = 0 }
    end

    local function restoreRecord(rec, why)
        if type(rec) ~= "table" or type(rec.props) ~= "table" then return 0 end
        local put = 0
        for i = #rec.props, 1, -1 do
            local e = rec.props[i]
            -- Guarded one at a time. A single unsupported property must not
            -- abandon the rest of the restore - that is the Terrain.Decoration
            -- lesson, and on the way back it would leave the world changed.
            if e and e.obj then
                local ok = pcall(function() e.obj[e.key] = e.was end)
                if ok then put = put + 1 end
            end
            rec.props[i] = nil
        end
        rec.n = 0
        log.info("restored %d properties (%s)", put, tostring(why))
        return put
    end

    -- A PREVIOUS COPY'S WORK, UNDONE BEFORE OURS BEGINS.
    --
    -- Runs when this module is first required, which is after BX.teardown has
    -- retired the old generation's scopes - so the old DescendantAdded handlers
    -- are already gone and nothing is racing this.
    if type(env[ENV_KEY]) == "table" then
        local stale = env[ENV_KEY]
        env[ENV_KEY] = nil
        BX.try("fps.restoreStale", function()
            restoreRecord(stale, "previous copy, before re-applying")
        end)
    end

    ---------- state ----------

    local sc, rec, enabled, sweeping = nil, nil, false, false
    local stats = { effects = 0, props = 0, added = 0, pruned = 0, refused = 0,
                    sweepMs = 0 }

    function M.isOn() return enabled end
    function M.stats()
        local s = table.clone(stats)
        s.tracked = rec and rec.n or 0
        return s
    end

    BX.profile.watch("fps.tracked", function() return rec and rec.n or 0 end)

    ---------- writing a property down, then changing it ----------

    local function remember(obj, key, value)
        if not rec then return false end
        if rec.n >= K.MAX_TRACKED then
            -- A CEILING, NOT A CRASH. Past the cap a new effect is simply left
            -- alone rather than tracked, so the list is bounded by construction
            -- and the worst case is a particle we did not turn off.
            stats.refused = stats.refused + 1
            if stats.refused == 1 then
                log.warn("tracking ceiling of %d reached - further effects left as they are",
                    K.MAX_TRACKED)
            end
            return false
        end
        local was
        if not pcall(function() was = obj[key] end) then return false end
        if was == value then return false end      -- nothing to change, nothing to remember
        if not pcall(function() obj[key] = value end) then return false end
        rec.n = rec.n + 1
        rec.props[rec.n] = { obj = obj, key = key, was = was }
        return true
    end

    ---------- what not to touch ----------

    -- Our own cards, and the player. Cheap: two ancestor tests, and only ever on
    -- an instance that already matched EFFECTS.
    local function offLimits(d)
        local espRoot = workspace:FindFirstChild("BlyxoESP")
        if espRoot and d:IsDescendantOf(espRoot) then return true end
        local char = svc.Players.LocalPlayer and svc.Players.LocalPlayer.Character
        if char and d:IsDescendantOf(char) then return true end
        return false
    end

    local function handle(d)
        local cls = d.ClassName
        local isGeometry = false
        local okGeometry = pcall(function() isGeometry = d:IsA("BasePart") end)

        if not (EFFECTS[cls] or POST[cls] or (okGeometry and isGeometry)) then
            return false
        end
        if offLimits(d) then return false end

        local changed = false

        if EFFECTS[cls] or POST[cls] then
            if cls == "Texture" or cls == "Decal" then
                -- Hiding textures/decals is reversible and avoids the permanent
                -- Destroy() problem of simple FPS scripts.
                if remember(d, "Transparency", 1) then
                    stats.effects = stats.effects + 1
                    changed = true
                end
            elseif remember(d, "Enabled", false) then
                stats.effects = stats.effects + 1
                changed = true
            end
        end

        -- Lights: disabling shadows removes a surprisingly expensive shadow
        -- pass while keeping the light itself available to gameplay.
        if cls == "PointLight" or cls == "SpotLight" or cls == "SurfaceLight" then
            if remember(d, "Shadows", false) then
                stats.effects = stats.effects + 1
                changed = true
            end
        end

        -- Extreme FPS mode: keep the actual instances alive because the game
        -- may use them for gameplay/target detection, but make their rendering
        -- cheaper. MeshPart RenderFidelity is optional and guarded because some
        -- executors/game builds expose different property support.
        if okGeometry and isGeometry then
            if remember(d, "CastShadow", false) then
                stats.effects = stats.effects + 1
                changed = true
            end
            -- Plastic is cheaper than many physical materials on low-end mobile
            -- renderers. It is reversible through the same restore record.
            if remember(d, "Material", Enum.Material.Plastic) then
                stats.effects = stats.effects + 1
                changed = true
            end
            if cls == "MeshPart" then
                pcall(function()
                    if remember(d, "RenderFidelity", Enum.RenderFidelity.Performance) then
                        stats.effects = stats.effects + 1
                        changed = true
                    end
                end)
            end
        end

        return changed
    end

    ---------- the one-time sweep ----------

    local function sweep()
        if sweeping then return end
        sweeping = true
        local t0 = os.clock()

        -- POST-PROCESSING FIRST, AND THE ORDER IS THE POINT.
        --
        -- It is three instances under Lighting and the single biggest saving on a
        -- weak client. This ran AFTER the chunked workspace walk, so it landed
        -- roughly a second behind the enable: measured, SunRaysEffect still read
        -- Enabled=true at +0.2s and only went off somewhere before +3s. Three
        -- writes have no business queueing behind forty-four thousand reads.
        for _, d in ipairs(svc.Lighting:GetDescendants()) do
            BX.try("fps.sweepPost", handle, d)
        end

        -- The one unavoidable 14.7ms frame. On this thread, never the caller's.
        local desc = workspace:GetDescendants()
        local total = #desc
        local i = 1
        while i <= total do
            local stop = math.min(i + K.CHUNK - 1, total)
            for j = i, stop do
                local d = desc[j]
                if d then BX.try("fps.sweepOne", handle, d) end
            end
            i = stop + 1
            -- UNCONDITIONAL, at the body's own level: the yield is not behind
            -- the loop's progress, so a chunk that does nothing still yields.
            svc.RunService.Heartbeat:Wait()
            if not enabled or not (sc and sc:alive()) then break end
        end

        stats.sweepMs = (os.clock() - t0) * 1000
        sweeping = false
        log.info("sweep: %d descendants, %d effects off, %.1fms",
            total, stats.effects, stats.sweepMs)
    end

    ---------- the cheap, non-effect settings ----------

    local function applyGlobals()
        -- Each through its own remember(), each independently guarded.
        -- GlobalShadows is the one real Lighting win here and it STAYS written:
        -- verified false eight seconds after the apply and again later.
        remember(svc.Lighting, "GlobalShadows", false)

        local ter = workspace:FindFirstChildOfClass("Terrain")
        if ter then
            -- Decoration is absent on this build; remember() returns false on a
            -- property it cannot read and moves on, so the two that DO exist are
            -- still applied. That is the whole point of per-property guarding.
            remember(ter, "Decoration", false)
            remember(ter, "WaterWaveSize", 0)
            remember(ter, "WaterWaveSpeed", 0)
            remember(ter, "WaterReflectance", 0)
        end

        -- Blocked on some executors, so it is asked for rather than assumed.
        BX.try("fps.quality", function()
            local r = settings().Rendering
            remember(r, "QualityLevel", Enum.QualityLevel.Level01)
        end)
        stats.props = rec and rec.n or 0
    end

    ---------- on / off ----------

    function M.setEnabled(on)
        on = on and true or false
        if on == enabled then return true end
        enabled = on

        if not on then
            -- The scope first: its DescendantAdded handlers must stop before the
            -- restore walks the list, or one firing mid-restore would re-disable
            -- something we have just put back.
            if sc then sc:destroy() sc = nil end
            local put = restoreRecord(rec, "toggled off")
            rec = nil
            env[ENV_KEY] = nil
            stats.effects, stats.props = 0, 0
            log.info("off (%d properties restored)", put)
            return true
        end

        rec = newRecord()
        -- PUBLISHED IMMEDIATELY, not at the end. If this copy is replaced while
        -- the sweep is still running, whatever it has changed so far is already
        -- findable by the next one.
        env[ENV_KEY] = rec

        sc = BX.scope("features.fps")
        applyGlobals()
        sc:spawn("sweep", sweep)

        -- EVENT-DRIVEN FROM HERE, NO POLLING.
        --
        -- One hash lookup per added instance. Both signals are on the scope, so
        -- OFF and re-exec take them with it and a second enable cannot leave two.
        sc:connect(workspace.DescendantAdded, BX.guard("fps.added", function(d)
            if not enabled then return end
            if handle(d) then stats.added = stats.added + 1 end
        end))
        sc:connect(svc.Lighting.DescendantAdded, BX.guard("fps.addedPost", function(d)
            if not enabled then return end
            if handle(d) then stats.added = stats.added + 1 end
        end))

        -- DESTROYED INSTANCES LET GO OF.
        --
        -- Our own list holds a strong reference, so an emitter that is destroyed
        -- stays alive as long as we remember it. Compacted in place on a slow
        -- timer: the entry is worthless anyway, since restoring a property on a
        -- destroyed instance does nothing.
        sc:loop("prune", K.PRUNE_EVERY, function()
            if not rec then return end
            local props, keep = rec.props, 0
            local dropped = 0
            for i = 1, rec.n do
                local e = props[i]
                local gone = false
                if e and e.obj then
                    -- Only Instances can be destroyed; the settings objects and
                    -- Lighting are permanent and have no meaningful Parent test.
                    if typeof(e.obj) == "Instance" and e.obj.Parent == nil then
                        gone = true
                    end
                else
                    gone = true
                end
                if gone then
                    dropped = dropped + 1
                else
                    keep = keep + 1
                    props[keep] = e
                end
            end
            for i = keep + 1, rec.n do props[i] = nil end
            rec.n = keep
            if dropped > 0 then
                stats.pruned = stats.pruned + dropped
                log.trace("pruned %d destroyed effects (%d tracked)", dropped, keep)
            end
        end)

        log.info("on")
        return true
    end

    -- ON BY DEFAULT, BUT NOT DURING THE LOAD ITSELF.
    --
    -- The sweep's one GetDescendants is 14.7ms and startup is already the most
    -- expensive moment in the session. Deferring it puts the menu up first and
    -- drops the walk somewhere nobody is looking. Guarded so a second arm() is a
    -- no-op, and so an arm that lands after the user has already switched the
    -- toggle off does not switch it back on.
    local armed = false
    function M.arm()
        if armed then return false end
        armed = true
        task.delay(K.DEFER, function()
            if not BX.alive() then return end
            if enabled then return end
            if M.userTurnedOff then return end
            BX.try("fps.armApply", function() M.setEnabled(true) end)
        end)
        return true
    end

    return M
end)

--[[ ==== features/boss.lua =========================================== ]]
-- =============================================================================
-- FEATURES.BOSS: is the boss world open, get in, claim what is owed
-- =============================================================================
--
--     local boss = BX.require("features.boss")
--     boss.setEnabled(true)     -- start watching; nothing runs before this
--     boss.status()             -- { title =, body = } for the Event tab
--     boss.enter()              -- RF/BossEvent/AskEnter
--     boss.setAutoEnter(true)   -- join as soon as it opens
--     boss.claimMilestones()    -- every mastery milestone we have earned
--     boss.onChange(fn)
--
-- WHAT THIS IS A PORT OF.
--
-- V3.1's Event tab Boss section, minus the fight. Its four controls were:
--     "Abyss Overlord" status line, "Enter the boss world",
--     "Auto enter", "Claim mastery rewards"
-- and all four dependencies are still live on the current game - verified, see
-- the port table in ui/tabs/event.lua.
--
-- THE FIGHT IS NOT HERE, AND THAT IS DELIBERATE.
--
-- V3.1's "Auto fight" is roughly 1,500 lines - BX.startBossMover (200 lines on
-- its own), startBossDodge, startVoidWatch, crystal reach and swing-gap tuning
-- measured against the tool's 0.6s debounce. It is a second character-owning
-- automation the size of Auto Steal, and nothing in V4 currently arbitrates two
-- of those against each other. It is left out until that is asked for
-- explicitly rather than half-ported.
--
-- EVENT-DRIVEN, WHERE V3.1 POLLED.
--
-- V3.1 ran a permanent thread at K.BOSS_POLL_FAST = 1s while the window was
-- open and K.BOSS_POLL_IDLE = 10s otherwise, invoking RF/BossEvent/AskSnapshot
-- on every tick for the whole session. The current game publishes
-- RE/BossEvent/StateShifted, so the open/closed transition tells us and the
-- snapshot is only re-read when it changes.
--
-- The countdown still needs a clock, but a countdown is arithmetic on a
-- timestamp we already hold - OpensAt and ClosesAt are absolute server times -
-- so the TAB asks for a formatted string when it repaints. Nothing polls the
-- server to move a number we can compute.
--
-- NOTHING EXISTS WHILE IT IS OFF. No scope, no connection, no snapshot.

BX.module("features.boss", function(BX)
    local svc = BX.require("core.services")
    local dev = BX.require("core.device")
    local net = BX.require("core.net")
    local log = BX.require("boot.log").for_module("boss")

    local M = {}

    local K = {
        -- A held snapshot is good for this long. V3.1's fast poll was 1s; this
        -- is only a floor on how often an explicit ask can hit the server.
        SNAP_TTL  = 5,
        -- The backstop. StateShifted is the real signal; this covers a missed
        -- one. V3.1's idle poll was 10s and ran forever - this runs only while
        -- the section is enabled and does nothing when nothing changed.
        BACKSTOP  = 30,
        -- How long after "it opened" we wait before asking to go in, so the
        -- server has finished setting the world up.
        ENTER_GAP = 1.0,
        -- After a FAILED read: retry this soon, then the next, then hand
        -- over to the backstop. Bounded.
        RETRY     = { 5, 10, 20 },
    }
    M.K = K

    local sc, enabled = nil, false
    local snap, snapAt = nil, 0
    local retryN, retryArmed = 0, false
    local autoEnter = false
    local stats = { asks = 0, enters = 0, entersRefused = 0, claims = 0,
                    stateEvents = 0, autoEntered = 0 }

    function M.stats() return table.clone(stats) end
    function M.isOn() return enabled end
    function M.autoEnterOn() return autoEnter end

    local listeners = {}
    function M.onChange(fn) listeners[#listeners + 1] = fn end
    local function fireChange()
        for _, fn in ipairs(listeners) do
            task.spawn(function() BX.try("boss.onChange", fn) end)
        end
    end

    ---------- the snapshot ----------

    -- RF/BossEvent/AskSnapshot. Verified live; returns
    --     { Open = boolean, OpensAt = number, ClosesAt = number }
    -- with OpensAt/ClosesAt as absolute server times.
    function M.snapshot(force)
        if not enabled then return nil end
        local now = os.clock()
        if not force and snap and (now - snapAt) < K.SNAP_TTL then return snap end
        stats.asks = stats.asks + 1
        local st = net.call("RF/BossEvent/AskSnapshot")
        snapAt = now
        if type(st) == "table" then snap = st end
        return snap
    end

    function M.isOpen()
        local s = M.snapshot()
        return (s and s.Open == true) or false
    end

    -- The held snapshot, no read. For status lines painted on a timer.
    function M.held() return snap end

    ---------- the status line ----------

    local function clock(seconds)
        seconds = math.max(0, math.floor(seconds or 0))
        local h = math.floor(seconds / 3600)
        local m = math.floor(seconds / 60) % 60
        if h > 0 then return ("%dh %02dm"):format(h, m) end
        if m > 0 then return ("%dm %02ds"):format(m, seconds % 60) end
        return ("%ds"):format(seconds)
    end

    -- V3.1's line was titled "Abyss Overlord" and read "Reading..." until it
    -- had an answer. Same shape: a title and one line of body.
    --
    -- HELD DATA ONLY: the Event tab's painter calls this once a second for
    -- the countdown, and the countdown is arithmetic on OpensAt/ClosesAt -
    -- absolute server times - so nothing here may invoke the remote. The
    -- backstop, StateShifted and the retry own every read.
    function M.status()
        if not enabled then return { title = "Abyss Overlord", body = "off" } end
        local s = snap
        if not s then
            return { title = "Abyss Overlord", body = (stats.asks > 0)
                and "Unavailable  \u{B7}  retrying"
                or "Reading..." }
        end

        -- Server time, because OpensAt/ClosesAt are server timestamps.
        local nowSrv = workspace:GetServerTimeNow()
        if s.Open == true then
            local left = (tonumber(s.ClosesAt) or 0) - nowSrv
            return { title = "Abyss Overlord",
                     body = ("OPEN  \u{B7}  closes in %s"):format(clock(left)) }
        end
        local until_ = (tonumber(s.OpensAt) or 0) - nowSrv
        if until_ > 0 then
            return { title = "Abyss Overlord",
                     body = ("Closed  \u{B7}  opens in %s"):format(clock(until_)) }
        end
        return { title = "Abyss Overlord", body = "Closed" }
    end

    -- A forced re-read plus a repaint, off the caller's thread. The Event
    -- tab's Refresh button.
    function M.refresh()
        if not enabled then return false end
        task.spawn(function()
            BX.try("boss.refresh", function()
                M.snapshot(true)
                fireChange()
            end)
        end)
        return true
    end

    -- A FAILED READ IS NOT THE END. V3.1's poll simply asked again next tick;
    -- this asks again at 5s, 10s, 20s and then leaves it to the backstop. One
    -- retry armed at a time.
    local function readOrRetry()
        local st = M.snapshot(true)
        if st then
            retryN = 0
            return st
        end
        if retryArmed or not sc then return nil end
        local wait = K.RETRY[retryN + 1]
        if not wait then return nil end
        retryArmed = true
        log.warn("boss read failed - retrying in %ds", wait)
        sc:delay("retry", dev.scale(wait), function()
            retryArmed = false
            retryN = retryN + 1
            if readOrRetry() then fireChange() end
        end)
        return nil
    end

    ---------- entering ----------

    -- Returns ok, message. V3.1 distinguished three answers and so does this:
    -- accepted, "already defeated" (wait for the next window), and a refusal.
    function M.enter()
        stats.enters = stats.enters + 1
        local accepted, msg = net.call("RF/BossEvent/AskEnter")
        log.info("AskEnter -> accepted=%s msg=%s", tostring(accepted), tostring(msg))
        if accepted == true then
            return true, "Entering the boss world"
        end
        stats.entersRefused = stats.entersRefused + 1
        if msg and tostring(msg):find("defeated") then
            return false, "Boss already defeated - waiting for the next one"
        end
        return false, tostring(msg or "Refused")
    end

    function M.setAutoEnter(on)
        autoEnter = on and true or false
        log.info("auto enter %s", autoEnter and "ON" or "OFF")
        -- If it is already open, act now rather than waiting for the next
        -- StateShifted - which may be half an hour away.
        if autoEnter and enabled and M.isOpen() then
            task.spawn(function()
                BX.try("boss.autoEnterNow", function()
                    local ok, why = M.enter()
                    if ok then stats.autoEntered = stats.autoEntered + 1 end
                    log.info("auto enter (already open) -> %s %s", tostring(ok), tostring(why))
                end)
            end)
        end
        return true
    end

    ---------- mastery ----------

    -- V3.1 BX.claimBossMilestones, traced rather than reinvented: it reads
    -- every milestone id out of Data.BossMastery, adds InfiniteMilestoneId, and
    -- asks for each one, treating "Not enough" as the ordinary not-yet-earned
    -- answer rather than an error. Returns how many were actually claimed.
    function M.claimMilestones()
        local BM
        local okReq = BX.try("boss.requireMastery", function()
            local mod = svc.ReplicatedStorage:FindFirstChild("Data")
            mod = mod and mod:FindFirstChild("BossMastery")
            if mod and mod:IsA("ModuleScript") then BM = require(mod) end
        end)
        if not okReq or type(BM) ~= "table" then
            log.warn("Data.BossMastery unavailable - cannot claim")
            return 0, "Could not read the mastery list"
        end

        local ids = {}
        for _, m in pairs(BM.Milestones or {}) do
            if type(m) == "table" and m.Id then ids[#ids + 1] = tostring(m.Id) end
        end
        if BM.InfiniteMilestoneId then ids[#ids + 1] = tostring(BM.InfiniteMilestoneId) end

        local claimed = 0
        for _, id in ipairs(ids) do
            local got, msg = net.call("RF/BossMastery/AskClaimMilestone", id)
            if got == true then
                claimed = claimed + 1
                log.info("claimed milestone %s", id)
            elseif msg and not tostring(msg):find("Not enough") then
                log.trace("milestone %s -> %s", id, tostring(msg))
            end
            -- V3.1's 0.15s gap: this is a loop of remote calls and it must not
            -- become a burst. Yields unconditionally.
            task.wait(0.15)
        end
        stats.claims = stats.claims + claimed
        return claimed, claimed > 0 and ("Claimed " .. claimed) or "Nothing to claim yet"
    end

    ---------- on / off ----------

    function M.setEnabled(on)
        on = on and true or false
        if on == enabled then return true end

        if not on then
            enabled = false
            autoEnter = false
            if sc then sc:destroy() sc = nil end
            snap, snapAt = nil, 0
            retryN, retryArmed = 0, false
            log.info("off (%d snapshot reads this session)", stats.asks)
            fireChange()
            return true
        end

        sc = BX.scope("features.boss")
        enabled = true

        -- THE OPEN/CLOSE TRANSITION, FROM THE GAME'S OWN EVENT. This is what
        -- replaces V3.1's permanent 1s/10s poll.
        BX.try("boss.watchState", function()
            local re = net.find("RE/BossEvent/StateShifted")
            if not re then
                log.warn("RE/BossEvent/StateShifted not found - running on the backstop")
                return
            end
            sc:connect(re.OnClientEvent, function()
                stats.stateEvents = stats.stateEvents + 1
                task.spawn(function()
                    BX.try("boss.stateShifted", function()
                        local was = snap and snap.Open
                        M.snapshot(true)
                        local isOpen = snap and snap.Open
                        log.info("state shifted: open %s -> %s",
                            tostring(was), tostring(isOpen))
                        fireChange()
                        -- Newly open, and the user asked to be let in.
                        if autoEnter and isOpen == true and was ~= true then
                            task.wait(K.ENTER_GAP)
                            local ok, why = M.enter()
                            if ok then stats.autoEntered = stats.autoEntered + 1 end
                            log.info("auto enter on open -> %s %s",
                                tostring(ok), tostring(why))
                        end
                    end)
                end)
            end)
        end)

        -- THE FIRST READ AND THE BACKSTOP ARE ONE LOOP. sc:loop runs its body
        -- before its first wait, so the t=0 tick is the initial read, on the
        -- loop's own thread - never the caller's, which may be the UI build.
        -- A separate "first" spawn used to double the startup AskSnapshot.
        sc:loop("backstop", dev.scale(K.BACKSTOP), function()
            local had, was = snap ~= nil, snap and snap.Open
            readOrRetry()
            if not had or (snap and snap.Open) ~= was then fireChange() end
        end)

        log.info("on (StateShifted event + %.0fs backstop)", dev.scale(K.BACKSTOP))
        return true
    end

    return M
end)

--[[ ==== features/rift.lua =========================================== ]]
-- =============================================================================
-- FEATURES.RIFT: what the rift wants, and which of it is stealable now
-- =============================================================================
--
--     local rift = BX.require("features.rift")
--     rift.setEnabled(true)
--     rift.status()        -- { title =, body = }  for the Event tab
--     rift.onField()       -- wanted pet ids that are on the field right now
--     rift.options()       -- dropdown labels, newest read
--     rift.setPick(id)
--     rift.eligible()      -- for the coordinator
--     rift.pickTarget()    -- for the steal worker's own `pick`
--     rift.onChange(fn)    -- repaint hook; fires when the answer changed
--
-- READ-ONLY BY DEFAULT; THE TRADE-IN IS A SEPARATE, OPT-IN SWITCH.
--
-- V3_RELEASE's note above this feature: "No trade button, no auto anything: the
-- trade eats three pets and only you know whether that is a good swap for a 45%
-- Rift Eye." The later V3.1 monolith added "Auto trade-in" (X.riftTryTrade),
-- off by default, and that is ported here as setAutoTrade - see its section.
-- RF/Rift/AskRefresh is still never called: the Refresh button on the tab
-- re-reads what we display; it does not spend a rift refresh.
--
-- WHAT IT SHOWS (V3.1's behaviour, preserved):
--
--     title   banner name + how many of the required pets you own   "Riftborn 2/3"
--     body    which needed pet is stealable RIGHT NOW, and the countdown
--     list    the required pets that are actually on the field, by DisplayName
--
-- THE RIFT SPEAKS IN IDS, EVERYTHING ELSE SPEAKS IN NAMES.
--
-- Straight from V3.1, because it is a trap worth inheriting: Requirements come
-- back as Data.Assets.Directory KEYS - "Mantis", "Galaxy Gecko" - and those are
-- not always the word the game shows you:
--
--     Directory["Mantis"].DisplayName        = "Mantaris"
--     Directory["Galaxy Gecko"].DisplayName  = "Cosmic Gecko"
--
-- so a tab that prints ids names pets that appear nowhere else in the hub. Ids
-- stay the matching key - they are what the egg records carry - and nothing is
-- ever shown to the user as an id.
--
-- ---------------------------------------------------------------------------
-- WHAT IS DIFFERENT FROM V3.1, AND WHY
-- ---------------------------------------------------------------------------
--
-- 1. EVENT-DRIVEN ROTATION, NOT A 2.5s POLL.
--
--    V3.1 ran `while true do task.wait(K.RIFT_POLL)` for the whole session and
--    invoked RF/Rift/AskState every 2.5 seconds, forever, whether or not the
--    tab was open or the rift had changed. The live game publishes
--    RE/Rift/BannerRotated - verified present - so a rotation tells us. The
--    only timer left is a slow stale backstop.
--
-- 2. IT READS THE HUB'S OWN EGG CACHE, NOT THE FIELD AGAIN.
--
--    V3.1 called its own snapshot(true) on every repaint because its egg cache
--    was only rebuilt by the steal loop. features/eggs.lua is event-invalidated
--    now, so eggs.list() is both fresher and free. That matters more than it
--    looks: EggState.ReadFieldEggs() deep-copies every record through
--    TableUtil.Copy on each call, so the old path paid for ~55 deep table
--    copies every 2.5 seconds for the whole session.
--
-- 3. NOTHING EXISTS WHILE IT IS OFF.
--
--    No scope, no connections, no snapshot, no cache, no thread. setEnabled(false)
--    destroys the scope and drops every table. A disabled Rift costs one
--    boolean. The Event tab switches it on when it is built - V3.1's rift
--    thread started at load and the line filled itself in, and a tab that
--    says "reading..." until a button is pressed is not that.
--
-- 3b. status() IS PURE. It formats the held snapshot and nothing else, so the
--    tab can call it on a timer for the countdown without a remote call, a
--    game-module require or a field read behind it. A failed read shows
--    "Unavailable - retrying" and retries on a bounded backoff (K.RETRY) until
--    the backstop takes over; it never leaves the line stuck.
--
-- 4. THE STEAL WORKER IS THE EXISTING ONE.
--
--    Rift does not steal. It answers "is there a rift pet worth taking" and
--    "which egg", and features.coordinator hands those to the one
--    features.autosteal worker as its eligibility probe and its target picker.
--    There is no second engine and no second loop.

BX.module("features.rift", function(BX)
    local svc  = BX.require("core.services")
    local dev  = BX.require("core.device")
    local data = BX.require("core.data")
    local net  = BX.require("core.net")
    local movement = BX.require("features.movement")
    local eggs = BX.require("features.eggs")
    local log  = BX.require("boot.log").for_module("rift")

    local M = {}

    local K = {
        -- The stale backstop. V3.1 polled at 2.5s; this is only for a change
        -- that arrived with no signal behind it, so it is far slower.
        BACKSTOP    = 30,
        -- A read is good for this long. Anything asking inside the window gets
        -- the held snapshot rather than another InvokeServer.
        SNAP_TTL    = 5,
        -- V3.1 K.RIFT_STALE_MAX. How long a FAILED read may keep showing the
        -- last good answer before we admit we do not know. Its note: without
        -- this the dropdown went on advertising a pet gone for minutes.
        STALE_MAX   = 8,
        -- Field signals arrive in bursts; one repaint, not fifty.
        DEBOUNCE    = 0.35,
        -- After a FAILED read: retry this soon, then the next, then hand
        -- over to the backstop. Bounded - nothing keeps doubling forever.
        RETRY       = { 5, 10, 20 },
        NONE_LABEL  = "No pets spawned",
    }
    M.K = K

    local sc        = nil
    local enabled   = false
    local snap, snapAt, snapOkAt = nil, 0, 0
    local retryN, retryArmed = 0, false
    local fieldIds  = nil      -- wanted ids currently on the field
    local ownedHave, ownedMiss = nil, nil
    local ownedDetails = nil   -- live backpack rows: count / eligible / uids
    local ownedFingerprint = nil
    local pick      = nil      -- the user's chosen pet id, or nil for "any"
    local labelToId = {}
    local dirty     = false

    local stats = {
        askState = 0, askFailed = 0, repaints = 0, coalesced = 0,
        rotations = 0, pickCleared = 0,
    }
    function M.stats() return table.clone(stats) end
    function M.isOn() return enabled end

    ---------- change notification ----------

    local listeners = {}
    function M.onChange(fn) listeners[#listeners + 1] = fn end

    local function fireChange()
        stats.repaints = stats.repaints + 1
        for _, fn in ipairs(listeners) do
            task.spawn(function() BX.try("rift.onChange", fn) end)
        end
    end

    ---------- names ----------

    -- Directory id -> the word the game shows. See the header.
    function M.petName(id)
        local dir = data.assetsDir()
        local cfg = dir and dir[id]
        return (cfg and cfg.DisplayName and tostring(cfg.DisplayName)) or tostring(id)
    end

    local function petNames(ids)
        local out = {}
        for _, id in ipairs(ids or {}) do out[#out + 1] = M.petName(id) end
        return out
    end

    ---------- the rift state ----------

    -- RF/Rift/AskState, held for SNAP_TTL. A failed read keeps the last good
    -- answer for STALE_MAX and then gives up rather than lying.
    function M.state(force)
        if not enabled then return nil end
        local now = os.clock()
        if not force and snap and (now - snapAt) < K.SNAP_TTL then
            return snap
        end

        stats.askState = stats.askState + 1
        local st = net.call("RF/Rift/AskState")
        snapAt = now

        if type(st) == "table" then
            snap, snapOkAt = st, now
            return snap
        end

        stats.askFailed = stats.askFailed + 1
        if (now - snapOkAt) > K.STALE_MAX then
            -- V3.1's lesson: admit it rather than advertise a stale rift.
            snap = nil
        end
        return snap
    end

    function M.requirements()
        local st = M.state()
        local reqs = st and st.Requirements
        if type(reqs) ~= "table" then return {} end
        return reqs
    end

    ---------- what we own ----------

    -- HOW MANY OF THE REQUIRED PETS ARE IN THE INVENTORY.
    --
    -- V3.1 got this wrong three times over and wrote down why: it scanned for
    -- `v.AssetCategory`, which owned pets do not have (field eggs do), and it
    -- read a roster that only carries pets PLACED IN THE PEN. The right source
    -- is the save profile, verified live: Shared.Save.Get(player).Inventory is
    -- 123 rows shaped
    --     { Category = "Dodo", Scale = ..., Gender = ..., Mutations = {...} }
    -- so the key is `row.Category`.
    --
    -- Recomputed only when something says it changed, never per frame.
    local function computeOwned()
        local reqs = M.requirements()
        if #reqs == 0 then
            ownedHave, ownedMiss, ownedDetails, ownedFingerprint = nil, nil, nil, nil
            return false
        end

        local result = nil
        BX.try("rift.readInventory", function()
            local Save = svc.ReplicatedStorage:FindFirstChild("Save", true)
            if not (Save and Save:IsA("ModuleScript")) then return end
            local mod = require(Save)
            if type(mod) ~= "table" or type(mod.Get) ~= "function" then return end
            local profile = mod.Get(svc.LocalPlayer)
            local inv = profile and profile.Inventory
            if type(inv) ~= "table" then return end

            local FuseKernel, AssetItems
            pcall(function() FuseKernel = require(svc.ReplicatedStorage.Shared.Util.FuseKernel) end)
            pcall(function() AssetItems = require(svc.ReplicatedStorage.Shared.Util.AssetItems) end)

            local equipped = {}
            for _, u in pairs(profile.EquippedAssets or {}) do equipped[tostring(u)] = true end

            result = {}
            for _, id in ipairs(reqs) do
                result[id] = {count = 0, eligible = 0, uids = {}, samples = {}}
            end

            local weight = {}
            for uid, row in pairs(inv) do
                if type(row) == "table" then
                    local cat = row.Category or (row.ItemData and row.ItemData.Category)
                    local slot = cat and result[cat]
                    if slot then
                        uid = tostring(uid)
                        slot.count = slot.count + 1
                        local may = not equipped[uid]
                        if may and FuseKernel and FuseKernel.MayEnterRift then
                            local ok, r = pcall(FuseKernel.MayEnterRift, uid, row)
                            may = ok and r == true
                        end
                        if may then
                            slot.eligible = slot.eligible + 1
                            slot.uids[#slot.uids + 1] = uid
                        end
                        if #slot.samples < 4 then
                            local sample = {
                                uid = uid,
                                equipped = equipped[uid] == true,
                                eligible = may,
                                scale = row.Scale,
                                mutations = row.Mutations,
                            }
                            if AssetItems then
                                pcall(function()
                                    local decoded = AssetItems.Decode(row)
                                    sample.weight = AssetItems.WeightKg(decoded)
                                end)
                            end
                            slot.samples[#slot.samples + 1] = sample
                        end
                    end
                end
            end

            for _, slot in pairs(result) do
                table.sort(slot.uids)
                table.sort(slot.samples, function(a, b)
                    return (a.weight or math.huge) < (b.weight or math.huge)
                end)
            end
        end)

        if not result then
            ownedHave, ownedMiss, ownedDetails = nil, nil, nil
            return false
        end

        local have, missing = 0, {}
        local fingerprintParts = {}
        for _, id in ipairs(reqs) do
            local slot = result[id]
            local count = slot and slot.count or 0
            local eligible = slot and slot.eligible or 0
            -- A Rift requirement is only READY when at least one pet can
            -- actually enter the Rift. Merely owning an equipped/blocked pet
            -- must not suppress the farm target.
            if eligible > 0 then
                have = have + 1
            else
                missing[#missing + 1] = id
            end
            fingerprintParts[#fingerprintParts + 1] = tostring(id) .. ":" .. tostring(count) .. ":" .. tostring(eligible)
        end
        local fp = table.concat(fingerprintParts, "|")
        local changed = fp ~= ownedFingerprint
        ownedHave, ownedMiss, ownedDetails, ownedFingerprint = have, missing, result, fp
        return changed
    end

    function M.owned()
        if ownedHave == nil and ownedMiss == nil then computeOwned() end
        return ownedHave, ownedMiss
    end

    -- Live backpack view used by the Rift tab. This is the player's actual
    -- Inventory profile, not the pen/field roster. The feature loop refreshes
    -- it independently so the UI can show changes immediately after a hatch,
    -- steal, equip/unequip or trade-in.
    function M.inventorySnapshot(force)
        if force or ownedDetails == nil then computeOwned() end
        return ownedDetails, ownedHave, ownedMiss
    end

    function M.eggsForPet(id)
        local out = {}
        if not id then return out end
        for _, e in ipairs(eggs.list() or {}) do
            if e.assetCategory == id and typeof(e.pos) == "Vector3" then
                out[#out + 1] = e
            end
        end
        table.sort(out, function(a, b) return (a.value or 0) > (b.value or 0) end)
        return out
    end

    -- One-shot movement to a live matching egg, using the same movement engine
    -- as Auto Farm instead of creating a second teleport implementation.
    function M.goToEgg(uid)
        if not uid then return false, "egg uid missing" end
        local egg = eggs.get(uid)
        if not egg or typeof(egg.pos) ~= "Vector3" then
            return false, "egg is no longer available"
        end
        local ok, info = movement.travel{
            to = egg.pos + Vector3.new(0, 3, 0),
            speed = 1400,
            arrive = 7,
            carrying = false,
            keepY = true,
            tag = "rift go to " .. tostring(egg.name),
            cancel = function() return not BX.alive() end,
        }
        if not ok then
            return false, info and info.reason or "movement failed"
        end
        return true, egg.name
    end

    ---------- what is on the field ----------

    -- The required pets that are actually stealable right now.
    --
    -- READS features/eggs' CACHE. It is event-invalidated and already built, so
    -- this is a walk of ~55 in-memory records with no remote call, no deep copy
    -- and no Workspace touch. See point 2 in the header.
    local function computeField()
        local reqs = M.requirements()
        if #reqs == 0 then
            fieldIds = nil
            return
        end
        local want = {}
        for _, id in ipairs(reqs) do want[id] = true end

        local list = eggs.list()
        if not list then
            fieldIds = nil
            return
        end

        local seen, out = {}, {}
        for _, e in ipairs(list) do
            local cat = e.assetCategory
            if cat and want[cat] and not seen[cat] then
                seen[cat] = true
                out[#out + 1] = cat
            end
        end
        fieldIds = out
    end

    function M.onField()
        if not enabled then return {} end
        if not fieldIds then computeField() end
        return fieldIds or {}
    end

    function M.petIsOut(id)
        if not id then return false end
        for _, out in ipairs(M.onField()) do
            if out == id then return true end
        end
        return false
    end

    ---------- the dropdown ----------

    -- Held data only, like status(): the tab's painter calls this.
    function M.options()
        local out = {}
        labelToId = {}
        for _, id in ipairs(fieldIds or {}) do
            local label = M.petName(id)
            labelToId[label] = id
            out[#out + 1] = label
        end
        if #out == 0 then out[1] = K.NONE_LABEL end
        return out
    end

    function M.idForLabel(label)
        if type(label) ~= "string" or label == K.NONE_LABEL then return nil end
        return labelToId[label] or label
    end

    function M.pick() return pick end

    function M.setPick(id)
        pick = id
        if id then
            log.info("targeting %s", M.petName(id))
        else
            log.info("targeting any required rift pet")
        end
    end

    -- A PICK WHOSE PET HAS LEFT THE FIELD IS DROPPED, BUT ONLY THEN.
    --
    -- V3.1's protection, and the reason it exists is worth repeating: its pet
    -- list refreshed every few seconds and Refresh/Set re-ran the dropdown
    -- callback through the library's dispatcher, so a BACKGROUND refresh
    -- silently re-aimed the run -
    --     35.09 rift: taking Orca
    --     35.94 rift: targeting Penguin      <- nobody touched the UI
    -- The tab guards the callback (see ui/tabs/event.lua and its suppress
    -- counter); this half makes sure we only ever drop a pick for a real
    -- reason, which is the pet genuinely no longer being out.
    local function prunePick()
        if not pick then return false end
        if M.petIsOut(pick) then return false end
        stats.pickCleared = stats.pickCleared + 1
        log.info("%s is no longer out - clearing the pick", M.petName(pick))
        pick = nil
        return true
    end

    ---------- the status line ----------

    -- Returns { title =, body = }. Never throws; a failed read is a sentence.
    --
    -- HELD DATA ONLY. This is what the Event tab's painter calls once a
    -- second, so it must not invoke the remote, require a game module or read
    -- the field - recompute() does all of that on the feature's own threads
    -- and leaves the answer here. The countdown is the last read's
    -- SecondsUntilRotation aged by the clock, which is how it ticks without a
    -- server call.
    function M.status()
        if not enabled then return { title = "Rift", body = "off" } end

        local st = snap
        if not st then
            return { title = "Rift", body = (stats.askState > 0)
                and "Unavailable  \u{B7}  retrying"
                or "Reading..." }
        end

        if st.Unlocked == false then
            local need = tonumber(st.UnlockSpeedPower)
            return {
                title = "Rift",
                body = need
                    and ("Unlocks at " .. eggs.formatRate(need) .. " speed")
                    or "Locked",
            }
        end

        local reqs = st.Requirements or {}
        local have, missing = ownedHave, ownedMiss
        local banner = tostring(st.BannerDisplayName or st.BannerId or "Rift")
        local secs = (tonumber(st.SecondsUntilRotation) or 0) - (os.clock() - snapOkAt)
        local mins = math.max(0, math.floor(secs / 60))

        -- nil have means the inventory could not be read; drop the score
        -- rather than print a wrong one.
        local title = have and ("%s  %d/%d"):format(banner, have, #reqs) or banner

        local extras = {}
        local pity, pityMax = tonumber(st.PityCount), tonumber(st.PityThreshold)
        if pity and pityMax then
            extras[#extras + 1] = ("pity %d/%d"):format(pity, pityMax)
        end
        local free = tonumber(st.FreeRefreshesRemaining)
        if free then extras[#extras + 1] = ("%d free"):format(free) end
        local tail = ("%dm"):format(mins)
        if #extras > 0 then tail = tail .. "  \u{B7}  " .. table.concat(extras, "  \u{B7}  ") end

        if have and #reqs > 0 and have >= #reqs then
            return { title = title, body = ("All pets ready  \u{B7}  new rift in %s"):format(tail) }
        end

        local want = (missing and #missing > 0) and missing or reqs
        if #want == 0 then
            return { title = title, body = ("New rift in %s"):format(tail) }
        end

        local outSet = {}
        for _, id in ipairs(fieldIds or {}) do outSet[id] = true end

        local ready = {}
        for _, id in ipairs(want) do
            if outSet[id] then ready[#ready + 1] = M.petName(id) end
        end

        local body
        if #ready > 0 then
            body = ("Steal %s now"):format(table.concat(ready, ", "))
        elseif #want == 1 then
            body = ("Need %s  \u{B7}  not spawned"):format(M.petName(want[1]))
        else
            body = ("Need %d: %s  \u{B7}  none spawned")
                :format(#want, table.concat(petNames(want), ", "))
        end

        return { title = title, body = ("%s  \u{B7}  %s"):format(body, tail) }
    end

    ---------- what the coordinator and the steal worker ask ----------

    -- Is there anything worth stealing for the rift right now? The
    -- coordinator's eligibility probe. Cheap: a cached list and a loop.
    function M.eligible()
        if not enabled then return false end
        local have, missing = M.owned()
        -- Everything already owned: nothing to steal for the rift.
        if have and #M.requirements() > 0 and have >= #M.requirements() then
            return false
        end
        local need = {}
        for _, id in ipairs((missing and #missing > 0) and missing or M.requirements()) do
            need[id] = true
        end
        if pick then return M.petIsOut(pick) and need[pick] ~= nil end
        for _, id in ipairs(M.onField()) do
            if need[id] then return true end
        end
        return false
    end

    -- The egg for features.autosteal to go and take. Handed in as its `pick`,
    -- so the steal engine stays ignorant of what a rift is - exactly how the
    -- Farm filter is wired.
    function M.pickTarget()
        if not enabled then return nil, "rift is off" end

        local have, missing = M.owned()
        local reqs = M.requirements()
        if #reqs == 0 then return nil, "rift has no requirements" end
        if have and have >= #reqs then return nil, "all rift pets owned" end

        local need = {}
        for _, id in ipairs((missing and #missing > 0) and missing or reqs) do
            need[id] = true
        end

        local list = eggs.list()
        if not list then return nil, "no egg list" end

        -- The chosen pet if it is out, otherwise the most valuable needed one.
        -- eggs.list is already sorted by value, so the first match wins.
        for _, e in ipairs(list) do
            local cat = e.assetCategory
            if cat and need[cat] then
                if pick then
                    if cat == pick then return e end
                else
                    return e
                end
            end
        end

        return nil, pick
            and ("%s is not on the field"):format(M.petName(pick))
            or "no required rift pet is on the field"
    end

    ---------- auto trade-in (V3.1 monolith X.riftTryTrade, opt-in) ----------

    -- PUT THE PETS IN THE RIFT - the same call the game's trade-in window
    -- makes. Decompiled from PlayerScripts.GUI.RiftTradeIn: slot i takes a pet
    -- whose Category is Requirements[i], the three inventory uids go to
    --     RF/Rift/AskTradeIn:InvokeServer({ uid1, uid2, uid3 })
    -- and on `true` the window plays its reveal and calls
    -- RF/Rift/AskFinishReveal, which hands over the Rift Egg. A pending reward
    -- from an earlier trade is finished the same way.
    --
    -- OPT-IN ONLY: it destroys three pets. It takes the lightest eligible pet
    -- of each kind - the one the game lists first - never an equipped one, and
    -- only a pet FuseKernel.MayEnterRift accepts. Does nothing until all three
    -- are hatched pets. Every 5s while the toggle is on, silent until something
    -- happens. This was NOT in V3_RELEASE (which V4's rift was traced from);
    -- it arrived in the later V3.1 monolith.

    local tradeSc, tradeOn, trading = nil, false, false
    local mark          -- defined below with recompute; tryTrade calls it
    function M.autoTradeOn() return tradeOn end

    -- Which required pets we hold as HATCHED pets, with the uids we may trade.
    -- Save.Get(player).Inventory rows are { Category, Scale, Mutations, ... }
    -- keyed by uid; EquippedAssets is a list of uids.
    local function riftHave(reqs)
        if type(reqs) ~= "table" or #reqs == 0 then return nil end
        local out, okAny = {}, false
        for _, r in ipairs(reqs) do out[r] = out[r] or { owned = 0, uids = {} } end
        BX.try("rift.tradeInventory", function()
            local Save = svc.ReplicatedStorage:FindFirstChild("Save", true)
            if not (Save and Save:IsA("ModuleScript")) then return end
            local mod = require(Save)
            local prof = type(mod) == "table" and mod.Get and mod.Get(svc.LocalPlayer)
            local inv = prof and prof.Inventory
            if type(inv) ~= "table" then return end
            okAny = true
            local FuseKernel, AssetItems
            pcall(function() FuseKernel = require(svc.ReplicatedStorage.Shared.Util.FuseKernel) end)
            pcall(function() AssetItems = require(svc.ReplicatedStorage.Shared.Util.AssetItems) end)
            local equipped = {}
            for _, u in pairs(prof.EquippedAssets or {}) do equipped[u] = true end
            local weight = {}
            for uid, row in pairs(inv) do
                local cat = type(row) == "table" and (row.Category or (row.ItemData and row.ItemData.Category))
                local slot = cat and out[cat]
                if slot then
                    slot.owned = slot.owned + 1
                    local may = not equipped[uid]
                    if may and FuseKernel and FuseKernel.MayEnterRift then
                        local ok, r = pcall(FuseKernel.MayEnterRift, uid, row)
                        may = ok and r == true
                    end
                    if may then
                        local w = math.huge
                        if AssetItems then
                            pcall(function() w = AssetItems.WeightKg(AssetItems.Decode(row)) end)
                        end
                        weight[uid] = w
                        slot.uids[#slot.uids + 1] = uid
                    end
                end
            end
            for _, slot in pairs(out) do
                table.sort(slot.uids, function(a, b) return (weight[a] or 0) < (weight[b] or 0) end)
            end
        end)
        return okAny and out or nil
    end

    -- Returns "traded" | "revealed" | "refused: why" | nil (nothing to do).
    local function tryTrade()
        if trading then return nil end
        trading = true
        local result = nil
        BX.try("rift.tryTrade", function()
            local st = M.state(true)
            if type(st) ~= "table" then return end
            if st.PendingReward then
                net.call("RF/Rift/AskFinishReveal")
                result = "revealed"
                return
            end
            local reqs = st.Requirements
            if type(reqs) ~= "table" or #reqs < 3 then return end
            local have = riftHave(reqs)
            if not have then return end
            local uids, used = {}, {}
            for i = 1, 3 do
                local slot = have[reqs[i]]
                for _, u in ipairs(slot and slot.uids or {}) do
                    if not used[u] then uids[i] = u used[u] = true break end
                end
                if not uids[i] then return end      -- not ready yet
            end
            local res, msg = net.call("RF/Rift/AskTradeIn", uids)
            if res ~= true then
                result = "refused: " .. tostring(msg or res)
                return
            end
            task.wait(1)
            net.call("RF/Rift/AskFinishReveal")
            result = "traded"
        end)
        trading = false
        if result then
            -- The inventory just changed: score and field are stale.
            ownedHave, ownedMiss, ownedDetails, ownedFingerprint = nil, nil, nil, nil
            mark("traded")
        end
        return result
    end

    local tradeListeners = {}
    function M.onTrade(fn) tradeListeners[#tradeListeners + 1] = fn end

    function M.tradePreview()
        local st = M.state()
        if type(st) ~= "table" then return nil, "rift state unavailable" end
        local reqs = st.Requirements
        if type(reqs) ~= "table" or #reqs < 3 then return nil, "three requirements are not available" end
        local details = ownedDetails
        if not details then computeOwned(); details = ownedDetails end
        if not details then return nil, "backpack inventory unavailable" end
        local preview, used = {}, {}
        for i = 1, 3 do
            local id = reqs[i]
            local slot = details[id]
            local uid
            for _, u in ipairs(slot and slot.uids or {}) do
                if not used[u] then uid = u; used[u] = true; break end
            end
            preview[i] = {id = id, name = M.petName(id), uid = uid, ready = uid ~= nil}
        end
        return preview
    end

    function M.tradeNow()
        if not enabled then return false, "rift is off" end
        local preview, why = M.tradePreview()
        if not preview then return false, why end
        for _, slot in ipairs(preview) do
            if not slot.ready then
                return false, "missing eligible pet: " .. tostring(slot.name)
            end
        end
        local r = tryTrade()
        if r == "traded" or r == "revealed" then return true, r end
        return false, tostring(r or "trade-in was refused")
    end

    function M.setAutoTrade(on)
        on = on and true or false
        if on == tradeOn then return true end
        tradeOn = on
        if not on then
            if tradeSc then tradeSc:destroy() tradeSc = nil end
            log.info("auto trade-in OFF")
            return true
        end
        if not enabled then M.setEnabled(true) end
        tradeSc = BX.scope("features.rift.trade")
        -- V3.1: "at most every 5s, on its own thread, silent until something
        -- actually happens". Its own scope so switching it off cannot touch
        -- the watcher, and the watcher going off takes it down too.
        tradeSc:loop("trade", dev.scale(5), function()
            local r = tryTrade()
            if r == "traded" then
                log.info("traded the 3 pets in - Rift Egg claimed")
            elseif r == "revealed" then
                log.info("finished a pending reveal")
            elseif r then
                log.warn("trade-in %s", tostring(r))
            end
            if r then
                for _, fn in ipairs(tradeListeners) do
                    task.spawn(function() BX.try("rift.onTrade", fn, r) end)
                end
            end
        end)
        log.info("auto trade-in ON (every 5s, lightest eligible pet of each kind, never equipped)")
        return true
    end

    ---------- recompute, coalesced ----------

    local scheduleRetry

    local function recompute(why, full)
        dirty = false
        if full then
            snapAt = 0            -- force the next state() to re-read
            local st = M.state(true)
            if st then
                retryN = 0
            else
                scheduleRetry()
            end
        end
        -- The score follows the inventory: the Save handler drops it to nil
        -- and the next recompute of any kind rebuilds it. status() never
        -- computes anything itself.
        if full or (ownedHave == nil and ownedMiss == nil) then computeOwned() end
        computeField()
        prunePick()
        log.trace("recomputed (%s)", tostring(why))
        fireChange()
    end

    -- A FAILED READ IS NOT THE END. V3.1's 2.5s poll simply tried again on
    -- the next tick; this tries again at 5s, 10s, 20s and then leaves it to
    -- the 30s backstop. One retry armed at a time, so a burst of failures
    -- cannot queue a burst of remote calls.
    scheduleRetry = function()
        if retryArmed or not sc then return end
        local wait = K.RETRY[retryN + 1]
        if not wait then return end
        retryArmed = true
        log.warn("rift read failed - retrying in %ds", wait)
        sc:delay("retry", dev.scale(wait), function()
            retryArmed = false
            retryN = retryN + 1
            recompute("retry " .. retryN, true)
        end)
    end

    -- UI helpers: expose the held snapshot without forcing another remote.
    function M.snapshot(force)
        if force then M.state(true) end
        return snap
    end

    function M.reroll()
        if not enabled then return false, "rift is off" end
        local st = M.state(true)
        if type(st) ~= "table" then return false, "rift state unavailable" end
        local free = tonumber(st.FreeRefreshesRemaining) or 0
        if free <= 0 then return false, "no free rerolls remaining" end
        local res, msg = net.call("RF/Rift/AskRefresh")
        if res ~= true then
            return false, tostring(msg or res or "reroll refused")
        end
        task.spawn(function()
            BX.try("rift.rerollRefresh", function()
                recompute("manual reroll", true)
            end)
        end)
        return true, "rerolled"
    end

    M.refresh = function(why)
        -- The tab's Refresh button. Re-reads what we DISPLAY. It does not call
        -- RF/Rift/AskRefresh and does not spend a free refresh.
        if not enabled then return false end
        eggs.invalidate("rift refresh")
        recompute(why or "manual refresh", true)
        return true
    end

    mark = function(why)
        if dirty then
            stats.coalesced = stats.coalesced + 1
            return
        end
        dirty = true
        if not sc then return end
        sc:delay("recompute", K.DEBOUNCE, function()
            if dirty then recompute(why, false) end
        end)
    end

    ---------- on / off ----------

    function M.setEnabled(on)
        on = on and true or false
        if on == enabled then return true end

        if not on then
            enabled = false
            if sc then sc:destroy() sc = nil end
            -- EVERY TABLE DROPPED. A disabled Rift holds nothing.
            snap, snapAt, snapOkAt = nil, 0, 0
            fieldIds, ownedHave, ownedMiss, ownedDetails, ownedFingerprint = nil, nil, nil, nil, nil
            labelToId, dirty = {}, false
            retryN, retryArmed = 0, false
            pick = nil
            log.info("off (%d state reads, %d repaints this session)",
                stats.askState, stats.repaints)
            fireChange()
            return true
        end

        sc = BX.scope("features.rift")
        enabled = true

        -- ROTATION, FROM THE GAME'S OWN EVENT. This is what replaces V3.1's
        -- permanent 2.5s poll.
        BX.try("rift.watchRotation", function()
            local re = net.find("RE/Rift/BannerRotated")
            if not re then
                log.warn("RE/Rift/BannerRotated not found - running on the backstop")
                return
            end
            sc:connect(re.OnClientEvent, function()
                stats.rotations = stats.rotations + 1
                log.info("banner rotated - re-reading")
                -- A rotation changes the requirements, so this is a FULL
                -- recompute, on its own thread because it invokes a remote.
                task.spawn(function()
                    BX.try("rift.rotated", function() recompute("banner rotated", true) end)
                end)
            end)
        end)

        -- THE FIELD CHANGING CHANGES WHICH PETS ARE STEALABLE. Coalesced, and
        -- it recomputes from the egg cache only - no remote, no deep copy.
        BX.try("rift.watchField", function()
            local ES = data.eggState()
            if not ES then return end
            for _, name in ipairs({ "FieldRefreshed", "FieldGone", "FieldShifted" }) do
                local sig = ES[name]
                if sig and type(sig) == "table" and type(sig.Connect) == "function" then
                    sc:connect(sig, function() mark("field " .. name) end)
                end
            end
        end)

        -- THE INVENTORY CHANGING CHANGES THE SCORE. Event-driven where the game
        -- offers it; the backstop covers it otherwise.
        BX.try("rift.watchSave", function()
            local Save = svc.ReplicatedStorage:FindFirstChild("Save", true)
            if not (Save and Save:IsA("ModuleScript")) then return end
            local mod = require(Save)
            local sig = type(mod) == "table" and mod.FieldChanged or nil
            if sig and type(sig) == "table" and type(sig.Connect) == "function" then
                sc:connect(sig, function(field)
                    if field == nil or field == "Inventory" then
                        ownedHave, ownedMiss, ownedDetails, ownedFingerprint = nil, nil, nil, nil
                        mark("inventory changed")
                    end
                end)
            end
        end)

        -- LIVE BACKPACK WATCHER. The Save signal handles instant invalidation;
        -- this light backstop also catches inventory systems that do not emit
        -- FieldChanged. It compares only requirement counts, so unchanged
        -- inventories do not repaint the tab.
        sc:loop("inventoryLive", dev.scale(0.75), function()
            local changed = computeOwned()
            if changed then fireChange() end
        end)

        -- THE FIRST READ AND THE BACKSTOP ARE ONE LOOP. sc:loop runs its body
        -- before its first wait, so the tick at t=0 IS the initial read - on
        -- the loop's own thread, never the caller's, because state() invokes
        -- a remote and the caller may be the UI build. A separate "first"
        -- spawn here used to double the startup AskState.
        sc:loop("backstop", dev.scale(K.BACKSTOP), function()
            recompute(snap and "backstop" or "first read", true)
        end)

        log.info("on (rotation event + field signals, backstop %.0fs)",
            dev.scale(K.BACKSTOP))
        return true
    end

    return M
end)

--[[ ==== features/eggs.lua =========================================== ]]
-- =============================================================================
-- FEATURES.EGGS: what is out there, and which one to take
-- =============================================================================
--
--     local eggs = BX.require("features.eggs")
--
--     eggs.list()               -- every valid egg right now (cached)
--     eggs.best(filter)         -- the one to go for, or nil
--     eggs.get(uid)             -- a fresh record for one uid, or nil
--     eggs.invalidate(reason)   -- next read re-reads the field
--     eggs.markStolen(uid)      -- stop offering it while the server catches up
--     eggs.stats()
--
-- RESPONSIBILITY. It answers "what eggs exist and what are they worth". It does
-- not move, grab, carry or decide when to do any of those.
--
-- WHERE THE DATA COMES FROM, AND WHY IT IS NOT A MAP SCAN.
--
-- The field is read from EggState.ReadFieldEggs(), a replicated module table.
-- That is a table read, not a workspace walk - so "scan the whole map" is not
-- what this costs, and the caching below exists to avoid re-deriving VALUES,
-- not to avoid a scan. The Workspace fallback (AreaEggSlotsClient) is only for
-- a fresh join before EggState has synced, and it is rate-limited hard because
-- it IS a descendants walk.
--
-- THE FIELD ARRIVES IN TWO HALVES, AND ACTING ON THE FIRST ONE IS WRONG.
--
-- Your own Forest nests resolve the instant your profile loads; the other fifty
-- eggs are shared state that has to replicate, and ReadFieldEggs returns
-- whatever has arrived so far. V3.1's log caught twelve seconds of it:
--
--     [851.36] eggs: 5 stealable, best Bear 262/s
--              ... 25 passes, still 5 ...
--     [863.56] eggs: 55 stealable, best Snowy Owl 104544933/s
--
-- Auto Steal started in that window picks a 240/s Bear as "best" off a map that
-- is 9% loaded, and a Titan steal in it cannot work because Titan is not in the
-- list yet. So once the full field has been seen, a snapshot that collapses to
-- a handful is replication catching up, not the map emptying: the last good
-- list is kept and we look again shortly. That guard is carried over as-is.

BX.module("features.eggs", function(BX)
    local svc = BX.require("core.services")
    local dev = BX.require("core.device")
    local data = BX.require("core.data")
    local log = BX.require("boot.log").for_module("eggs")

    local M = {}

    local K = {
        CACHE_TTL       = 0.05,  -- rarity farming must see field changes almost immediately
        MIN_REBUILD     = 0.025, -- signal bursts collapse into one rebuild per frame window
        RAW_TTL         = 0.025, -- realtime replicated EggState snapshot window
        FALLBACK_TTL    = 5.0,   -- the Workspace walk: rarely, and never in a loop
        STOLEN_FOR      = 120,   -- keep a stolen uid suppressed this long
        UNREACHABLE_FOR = 45,    -- V3.1 K.UNREACHABLE_COOLDOWN
        PARTIAL_FLOOR   = 8,     -- <= this many records after a full field = replication lag
        FULL_FIELD_MIN  = 10,    -- > this many records means we have seen the real field
        VALUE_CACHE_MAX = 600,   -- hard ceiling; the field is ~55, so this is generous
    }
    M.K = K

    ---------- game modules ----------

    -- THROUGH core.data, NOT A BARE NAME SEARCH.
    --
    -- This used to do FindFirstChild("Assets", true) and check IsA("ModuleScript").
    -- There is a FOLDER called ReplicatedStorage.Assets as well as the
    -- ModuleScript at ReplicatedStorage.Data.Assets, the folder is found first,
    -- the IsA check fails, and AssetsDir was left nil - so every egg reported
    -- rarity="?" and kg=0 for the whole life of this rebuild. Measured on the
    -- live field before the fix. core/data.lua resolves the PATH and explains
    -- the trap in full.
    local EggState, AssetEarnings, AssetsDir
    BX.try("eggs.resolveModules", function()
        EggState = data.eggState()
        AssetEarnings = data.assetEarnings()
        -- Data.Assets.Directory. This is what turns an AssetCategory into the
        -- PET NAME the player recognises - the thing inside the egg, not the
        -- egg model. V3.1 getEggDisplayName reads exactly this.
        AssetsDir = data.assetsDir()
    end)
    M.ready = (EggState ~= nil)
    if not M.ready then
        log.error("EggState not found - is this Steal An Egg?")
    end

    ---------- caches ----------

    local rawSnap, rawSnapAt = nil, 0
    local dirty, dirtyReason = false, nil
    local list, listAt       = nil, 0
    local fallbackAt         = 0
    local sawFullField       = false
    local saidPartial        = false
    local stolen             = {}   -- uid -> os.clock() when we took it
    local unreachable        = {}   -- uid -> os.clock() when it beat us
    local valueCache         = {}   -- uid -> income/sec
    local valueCacheN        = 0

    local stats = {
        scans = 0, cacheHits = 0, partialHeld = 0, fallbacks = 0,
        signals = 0, dirtyRebuilds = 0,
        lastScanMs = 0, lastConsidered = 0, lastKept = 0,
    }

    -- Registered so the health line reports OUR growth rather than Roblox's.
    -- Any of these climbing steadily across a long session is a leak we own.
    BX.profile.watch("eggs.list", function() return list and #list or 0 end)
    BX.profile.watch("eggs.values", function() return valueCacheN end)
    BX.profile.watch("eggs.unreachable", function()
        local n = 0
        for _ in pairs(unreachable) do n = n + 1 end
        return n
    end)
    BX.profile.watch("eggs.stolen", function()
        local n = 0
        for _ in pairs(stolen) do n = n + 1 end
        return n
    end)

    function M.invalidate(reason)
        list, listAt = nil, 0
        rawSnap, rawSnapAt = nil, 0
        dirty = false
        if reason then log.trace("invalidated: %s", reason) end
    end

    -- MARK, DO NOT REBUILD.
    --
    -- These signals can fire in bursts - a field shift moves many eggs at once.
    -- Rebuilding on each one would turn event-driven invalidation into
    -- something more expensive than the polling it replaced. The flag says
    -- "the next read must not trust the cache"; MIN_REBUILD keeps a burst from
    -- costing more than one rebuild.
    function M.markDirty(reason)
        dirty = true
        dirtyReason = reason
        stats.signals = (stats.signals or 0) + 1
    end

    function M.markStolen(uid)
        if uid then stolen[tostring(uid)] = os.clock() end
    end

    -- A grab marks the uid immediately so replication lag cannot make the same
    -- egg appear twice.  That suppression must NOT survive a failed carry: if
    -- the authoritative field puts the egg back into Slot/Dropped, it is live
    -- again and must return to the list immediately.
    function M.clearStolen(uid)
        if uid then stolen[tostring(uid)] = nil end
    end

    -- SOMETHING ABOUT THIS EGG IS NOT WORKING RIGHT NOW.
    --
    -- V3.1 marks a target unreachable when the grab finally fails and skips it
    -- for UNREACHABLE_COOLDOWN. Without it the ranking hands back the same
    -- highest-value egg every cycle and the run bangs on it forever - which is
    -- exactly what three consecutive cycles against the same Rhino looked like.
    function M.markUnreachable(uid)
        if uid then unreachable[tostring(uid)] = os.clock() end
    end

    function M.clearUnreachable(uid)
        if uid then unreachable[tostring(uid)] = nil end
    end

    -- Walked by ITSELF, not by the record list. V3.1's first version only
    -- expired an entry if that uid still appeared in the current snapshot, so
    -- an egg we stole that then despawned was never visited again and stayed
    -- suppressed for the rest of the session - a table that only grows.
    local function pruneStolen()
        local now = os.clock()
        for uid, at in pairs(stolen) do
            if (now - at) > K.STOLEN_FOR then stolen[uid] = nil end
        end
        for uid, at in pairs(unreachable) do
            if (now - at) > K.UNREACHABLE_FOR then unreachable[uid] = nil end
        end
    end

    ---------- value ----------

    local function calcValue(rec)
        local uid = rec.Uid
        local hit = valueCache[uid]
        if hit then return hit end

        local item = {
            Category  = rec.AssetCategory,
            Scale     = tonumber(rec.AssetScale) or 1,
            Mutations = rec.Mutations or {},
        }

        local v = 0
        if AssetEarnings then
            local ok, rate = pcall(AssetEarnings.LiveRatePerSecond, item, nil, nil, svc.LocalPlayer)
            if ok and type(rate) == "number" then
                v = rate
            else
                -- LiveRatePerSecond needs a player; this one does not.
                ok, rate = pcall(AssetEarnings.MutationOnlyRatePerSecond, item)
                if ok and type(rate) == "number" then v = rate end
            end
        end

        -- BOUNDED. V3.1 used a double-buffered valueCache/valueCacheNext pair
        -- rebuilt every pass, which was self-bounding but meant re-deriving
        -- every value on every pass that missed. A single cache with a ceiling
        -- keeps the values and cannot grow without limit; at ~55 field eggs the
        -- ceiling is never reached in practice, and if it ever is, dropping the
        -- lot costs one pass of recalculation.
        if valueCacheN >= K.VALUE_CACHE_MAX then
            log.warn("value cache hit %d entries - clearing", valueCacheN)
            valueCache, valueCacheN = {}, 0
        end
        valueCache[uid] = v
        valueCacheN = valueCacheN + 1
        return v
    end

    M.value = calcValue

    -- THE PET INSIDE, NOT THE EGG MODEL.
    --
    -- AssetCategory is an internal id; DisplayName is what the game shows and
    -- what a player can pick out of a list.
    local function displayName(rec)
        local dir = AssetsDir and AssetsDir[rec.AssetCategory]
        -- No data module = no pet name; a short uid still lets the user tell
        -- two eggs apart in the list and steal one by position.
        return (dir and dir.DisplayName) or rec.AssetCategory
            or ("Egg " .. tostring(rec.Uid or "?"):sub(1, 6))
    end

    -- The rarity's STABLE id, which is what a saved filter selection matches on.
    -- _id and DisplayName are the same string for all ten rarities today
    -- (Common..Divine, RarityNumber 1..10), so this exists to keep a future
    -- display rename from silently emptying somebody's Farm selection.
    local function rarityIdOf(rec)
        local dir = AssetsDir and AssetsDir[rec.AssetCategory]
        if dir and dir.Rarity then
            return dir.Rarity._id or dir.Rarity.DisplayName or "?"
        end
        return "?"
    end

    local function rarityOf(rec)
        local dir = AssetsDir and AssetsDir[rec.AssetCategory]
        if dir and dir.Rarity then
            return dir.Rarity.DisplayName or dir.Rarity._id or "?"
        end
        return "?"
    end

    -- The number on the egg in game: the pet base weight stretched by the
    -- egg own AssetScale. V3.1 uses it to tell two otherwise identical
    -- entries apart - Dodo 7.3kg and Dodo 20.4kg are the same pet and the
    -- same income.
    local function weightOf(rec)
        local dir = AssetsDir and AssetsDir[rec.AssetCategory]
        local base = dir and dir.Egg and tonumber(dir.Egg.WeightKg)
        if not base then return 0 end
        return base * (tonumber(rec.AssetScale) or 1)
    end

    -- Adaptive precision: two decimals under 10 of a unit, one above, so a
    -- list reads 6.78M and 15.8M rather than 6.8M and 15.8M.
    function M.formatRate(n)
        n = tonumber(n) or 0
        for _, u in ipairs({ { 1e12, "T" }, { 1e9, "B" }, { 1e6, "M" }, { 1e3, "K" } }) do
            if n >= u[1] then
                local v = n / u[1]
                local txt = (v < 10) and string.format("%.2f", v) or string.format("%.1f", v)
                return (txt:gsub("%.?0+$", "")) .. u[2]
            end
        end
        return tostring(math.floor(n))
    end

    ---------- raw snapshot ----------

    local function readField()
        local records = nil
        BX.try("eggs.readField", function()
            local data = EggState and EggState.ReadFieldEggs and EggState.ReadFieldEggs()
            if type(data) == "table" and type(data.Records) == "table" then
                records = data.Records
            end
        end)
        return records
    end

    -- Only when EggState has nothing - a fresh join before its background sync
    -- lands. This IS a descendants walk, so it is rate-limited to once every
    -- FALLBACK_TTL seconds and never runs while EggState is answering.
    local function readFallback()
        local now = os.clock()
        if (now - fallbackAt) < K.FALLBACK_TTL then return nil end
        fallbackAt = now
        stats.fallbacks = stats.fallbacks + 1

        local records = {}
        BX.try("eggs.fallback", function()
            local slots = workspace:FindFirstChild("AreaEggSlotsClient")
            if not slots then return end
            -- THE SLOT MODELS ARE NAMED BY UID. Measured on the live game:
            -- AreaEggSlotsClient holds one Model per field egg, named with the
            -- egg's uid ("fb48c510..." or "FirstAreaEgg_<owner>_<n>_Forest:
            -- Slot_002"), each with a Hitbox part - and NO Uid/EggUid
            -- attribute anywhere (0 of 527 descendants). The attribute read
            -- this used to do found nothing, so an executor without game-
            -- module require() had no eggs at all. Children only: one folder,
            -- ~60 models, no descendants walk.
            for _, m in ipairs(slots:GetChildren()) do
                if m:IsA("Model") then
                    local uid = m:GetAttribute("Uid") or m:GetAttribute("EggUid") or m.Name
                    local cf
                    local hit = m:FindFirstChild("Hitbox")
                    if hit and hit:IsA("BasePart") then cf = hit.CFrame else cf = m:GetPivot() end
                    if uid and cf then
                        -- A CFrame, deliberately - NOT the Instance. Holding
                        -- the part would keep a despawned egg's model alive in
                        -- the cache for as long as the cache lived.
                        records[#records + 1] = {
                            Uid = tostring(uid), BoundsCFrame = cf, State = "Slot",
                        }
                    end
                end
            end
        end)
        log.info("fallback scan: %d records from AreaEggSlotsClient (no EggState - names and values unavailable)", #records)
        return #records > 0 and records or nil
    end

    local function snapshot(force)
        local now = os.clock()
        if not force and rawSnap and (now - rawSnapAt) < dev.scale(K.RAW_TTL) then
            return rawSnap
        end
        local records = readField()
        if not records or #records == 0 then
            records = readFallback() or records
        end
        if records then
            rawSnap, rawSnapAt = records, now
        end
        return rawSnap
    end

    ---------- the list ----------

    -- opts.state    : which States count as takeable (default Slot + Dropped)
    -- opts.minValue : skip anything below this income/sec
    -- opts.filter   : function(rec, value) -> boolean, the caller's own rule
    function M.list(opts, force)
        opts = opts or {}
        local now = os.clock()

        local fresh = (now - listAt) < dev.scale(K.CACHE_TTL)
        local mayRebuild = (now - listAt) >= K.MIN_REBUILD
        if not force and list and fresh and not (dirty and mayRebuild) then
            stats.cacheHits = stats.cacheHits + 1
            return list
        end
        if dirty and mayRebuild then
            stats.dirtyRebuilds = (stats.dirtyRebuilds or 0) + 1
            dirty = false
        end

        local t0 = os.clock()
        local records = snapshot(force)

        -- The partial-snapshot guard. See the header.
        local n = records and #records or 0
        if n > K.FULL_FIELD_MIN then sawFullField = true end
        if sawFullField and n > 0 and n <= K.PARTIAL_FLOOR and list and #list > 0 then
            if not saidPartial then
                saidPartial = true
                stats.partialHeld = stats.partialHeld + 1
                log.info("only %d records replicated - field still loading, keeping the last %d",
                    n, #list)
            end
            return list
        end
        saidPartial = false

        if not records then
            list = list or {}
            listAt = now
            return list
        end

        pruneStolen()

        local TAKEABLE = opts.state or { Slot = true, Dropped = true }
        local out, seen = {}, {}
        local considered, dupes = 0, 0

        for _, rec in ipairs(records) do
            considered = considered + 1
            local uid = rec.Uid and tostring(rec.Uid)

            -- DEDUPED BY UID.
            --
            -- V3.1 built the list straight from Records with no uniqueness
            -- check. A uid appearing twice in a snapshot - which happens while
            -- the field is shifting - produced two entries for one egg, so the
            -- same egg could be picked, reported and counted twice. That is
            -- the duplicate-label problem.
            if uid and not seen[uid] then
                seen[uid] = true

                if not TAKEABLE[rec.State] then
                    -- not takeable right now
                elseif stolen[uid] and rec.State ~= "Slot" and rec.State ~= "Dropped" then
                    -- ours already, or genuinely still being carried
                elseif unreachable[uid] then
                    -- beat us recently; give it a rest rather than loop on it
                else
                    -- If the authoritative record is back in Slot/Dropped,
                    -- clear any stale post-grab suppression before rebuilding.
                    if stolen[uid] and (rec.State == "Slot" or rec.State == "Dropped") then
                        stolen[uid] = nil
                    end
                    local value = calcValue(rec)
                    local pos = rec.BoundsCFrame and rec.BoundsCFrame.Position
                    if pos and (not opts.minValue or value >= opts.minValue)
                       and (not opts.filter or opts.filter(rec, value)) then
                        out[#out + 1] = {
                            uid   = uid,
                            state = rec.State,
                            pos   = pos,          -- Vector3, not an Instance
                            value = value,
                            name  = displayName(rec),
                            rarity = rarityOf(rec),
                            rarityId = rarityIdOf(rec),
                            -- The ESP needs it for the pet's icon and rarity
                            -- colour, both of which live in Data.Assets.
                            assetCategory = rec.AssetCategory,
                            -- The ESP lifts its card by the egg's size roll and
                            -- shows mutations on their own line, both V3.1.
                            assetScale = rec.AssetScale,
                            mutations = rec.Mutations,
                            kg    = weightOf(rec),
                            guardHeld = (rec.State == "GuardCarried"),
                            dropped   = (rec.State == "Dropped"),
                            -- Needed to build a FirstAreaSlotKey. Without it
                            -- the server refuses the carry outright for
                            -- first-area eggs.
                            areaId = rec.AreaId,
                            nestId = rec.NestId,
                        }
                    end
                end
            elseif uid then
                dupes = dupes + 1
            end
        end

        table.sort(out, function(a, b) return a.value > b.value end)

        -- KEEP THE VALUE CACHE NEAR THE SIZE OF THE FIELD.
        --
        -- Entries are only ever added, so as eggs are taken and respawn with
        -- new uids the cache drifts above the live field: measured at 110
        -- entries against a 55-egg field in one session. The 600 ceiling means
        -- it is bounded rather than leaking, but letting it drift to the cap
        -- and then dropping everything is a worse trade than pruning what is
        -- demonstrably gone.
        --
        -- Only runs when it has actually drifted, and only walks the cache -
        -- it is a hash of uid -> number, so this is cheap and rare.
        if valueCacheN > (#out * 2 + 50) then
            local keep, kept = {}, 0
            for _, e in ipairs(out) do
                local v = valueCache[e.uid]
                if v ~= nil then
                    keep[e.uid] = v
                    kept = kept + 1
                end
            end
            log.trace("value cache pruned %d -> %d (field %d)", valueCacheN, kept, #out)
            valueCache, valueCacheN = keep, kept
        end

        list, listAt = out, now
        stats.scans = stats.scans + 1
        stats.lastScanMs = (os.clock() - t0) * 1000
        stats.lastConsidered = considered
        stats.lastKept = #out

        -- ONE SUMMARY PER SCAN, not per frame. Everything needed to explain a
        -- bad pick: how long it took, how many records existed, how many
        -- survived the filter, how many were duplicates, and what won.
        log.trace("scan: %d records -> %d takeable (%d dupes) in %.1fms, best %s %s/s",
            considered, #out, dupes, stats.lastScanMs,
            out[1] and out[1].name or "-",
            out[1] and string.format("%.0f", out[1].value) or "-")

        return list
    end

    function M.best(opts)
        local l = M.list(opts)
        return l and l[1] or nil
    end

    -- A fresh read for ONE uid, straight past the cache. Used when the caller
    -- needs to know the current truth about a specific egg (has it moved, has
    -- someone else taken it) rather than what the last scan said.
    function M.get(uid)
        if not uid then return nil end
        local rec
        BX.try("eggs.get", function()
            rec = EggState and EggState.ReadFieldEgg and EggState.ReadFieldEgg(uid)
        end)
        if not rec then return nil end
        if (rec.State == "Slot" or rec.State == "Dropped") and stolen[tostring(uid)] then
            stolen[tostring(uid)] = nil
        end
        return {
            uid   = tostring(uid),
            state = rec.State,
            pos   = rec.BoundsCFrame and rec.BoundsCFrame.Position,
            value = calcValue(rec),
            name  = displayName(rec),
            rarity = rarityOf(rec),
            rarityId = rarityIdOf(rec),
            assetCategory = rec.AssetCategory,
            assetScale = rec.AssetScale,
            mutations = rec.Mutations,
            kg    = weightOf(rec),
            areaId = rec.AreaId,
            nestId = rec.NestId,
        }
    end

    -- WHAT ARE WE HOLDING RIGHT NOW, ACCORDING TO THE GAME.
    --
    -- Not a local flag. V3.1 learned this the hard way: heldEggUid is set by
    -- the callers of the carry, never by the carry itself, so there is a window
    -- where the game has handed us an egg and our own flag says otherwise.
    -- EggState is the authority.
    function M.carryingUid()
        local found
        BX.try("eggs.carryingUid", function()
            local data = EggState and EggState.ReadFieldEggs and EggState.ReadFieldEggs()
            for _, r in pairs(data and data.Records or {}) do
                if r.State == "Carried" then
                    found = tostring(r.Uid)
                    break
                end
            end
        end)
        return found
    end

    -- Still a valid thing to go and take?
    function M.stillTakeable(uid, states)
        local r = M.get(uid)
        if not r then return false, "gone" end
        local ok = (states or { Slot = true, Dropped = true })[r.state]
        return ok and true or false, r.state
    end

    function M.stats()
        local s = table.clone(stats)
        s.listSize = list and #list or 0
        s.valueCache = valueCacheN
        s.sawFullField = sawFullField
        return s
    end

    ---------- invalidation ----------

    -- EVENT-DRIVEN, NOT POLLED.
    --
    -- V3.1 leaned on a TTL and cleared BX.eggCache by hand from four different
    -- places. The field tells us when it changed, so the cache is dropped on
    -- the signal and the TTL is only a backstop for signals we do not get.
    -- THE SIGNALS ARE NOT RBXScriptSignals.
    --
    -- Read live off ReplicatedStorage.Client.EggState: every one of these is a
    -- TABLE with a Connect method, not a Roblox signal. An earlier version of
    -- this module tested typeof(sig) == "RBXScriptSignal" and therefore
    -- connected to NOTHING - the scope reported conns=0 and the cache was
    -- quietly running on its TTL alone. Two of the names were wrong as well
    -- (FieldEggShifted / FieldEggsChanged do not exist). Verified names below.
    --
    -- They return a connection with :Disconnect(), so the scope retires them
    -- the same as any other.
    local WATCH = {
        "CarryChanged",      -- an egg changed hands
        "FieldShifted",      -- the field moved
        "FieldRefreshed",    -- bulk refresh
        "FieldGone",         -- an egg left the field
        "FieldClaimed",      -- someone claimed one
        "SnapshotRefreshed", -- the underlying snapshot re-synced
    }

    local sc = BX.scope("features.eggs")
    local watched = 0
    if EggState then
        for _, name in ipairs(WATCH) do
            BX.try("eggs.watch." .. name, function()
                local sig = EggState[name]
                if sig and type(sig) == "table" and type(sig.Connect) == "function" then
                    sc:connect(sig, function() M.markDirty(name) end)
                    watched = watched + 1
                end
            end)
        end
    end
    log.info("watching %d/%d EggState signals", watched, #WATCH)

    -- A respawn does not change the field, but it does end any approach in
    -- progress, so the next read should be honest rather than half a second
    -- stale.
    BX.require("core.character").onSpawn(sc, "eggs.respawn", function()
        M.invalidate("respawn")
    end)

    return M
end)

--[[ ==== features/grab.lua =========================================== ]]
-- =============================================================================
-- FEATURES.GRAB: take the egg off the nest
-- =============================================================================
--
--     local grab = BX.require("features.grab")
--
--     local ok, info = grab.take(uid, {
--         pos    = Vector3,            -- where the egg is
--         cancel = function() end,     -- polled; true means stop now
--         tries  = 3,
--     })
--
--     grab.confirm(uid)   -- (bool, witness) - is this egg in our hands?
--
-- RESPONSIBILITY. It fires the prompt and decides whether we got the egg. It
-- does not travel to the egg, choose it, or carry it home.
--
-- WHY A PROMPT AND NOT THE REMOTE. The game's own steal goes through a
-- ProximityPrompt; invoking the remote directly produces a call shape the
-- legitimate client never makes.
--
-- THE PROMPTS ARE POOLED, NOT PER-EGG. Every steal prompt is
--     CarryAreaEgg[ProximityPrompt] < SmartPromptPart[Part] < Workspace
-- and there are ~54 SmartPromptParts directly under Workspace. The game MOVES
-- one to whichever egg you are standing at. They are not owned by an egg.
--
-- We arrive fast, so the game has often not handed a prompt to OUR egg yet.
-- V3.1's first version fired whichever enabled prompt was nearest to US, which
-- in that window is a stale one parked at a different nest: it fires, returns
-- true, and nothing is stolen. So we aim at the EGG, not at ourselves, and wait
-- briefly for a prompt to arrive rather than burning every attempt in half a
-- second.
--
-- CONFIRMATION IS ONE FUNCTION, ON PURPOSE.
--
-- In V3.1 the question "did we get it" was answered in several places that had
-- drifted apart - the grab checked one thing, the loop checked another, and
-- carryingUid() a third. This is the single ladder, ordered fastest-witness
-- first, and it is the only thing that decides.

BX.module("features.grab", function(BX)
    local svc  = BX.require("core.services")
    local data = BX.require("core.data")
    local exec = BX.require("core.exec")
    local ch   = BX.require("core.character")
    local dev  = BX.require("core.device")
    local eggs = BX.require("features.eggs")
    local log  = BX.require("boot.log").for_module("grab")

    local RunService = svc.RunService
    local M = {}

    local K = {
        PROMPT_CACHE   = 30,    -- how long the prompt list stays good; they do not move
        PROMPT_NEAR    = 14,    -- a prompt this close to the egg belongs to it
        PROMPT_WAIT    = 0.6,   -- wait for the game to hand a prompt over
        STEP_INSIDE    = 3,     -- studs inside MaxActivationDistance to stand
        CONFIRM_WINDOW = 1.2,   -- how long to wait for a witness after firing
        TRIES          = 3,
        RETRY_GAP      = 0.15,  -- never zero: a retry without a yield is a spin
        TP_PROMPT_WAIT = 1.2,   -- after a teleport, how long to wait for a prompt
    }
    M.K = K

    -- THROUGH core.data. A private FindFirstChild + require here bypassed
    -- the one place that knows whether this executor can require game
    -- modules at all, and cached a miss forever. core.data probes once,
    -- lets a miss expire, and backs off - see core/data.lua.
    local EggState = data.eggState()

    ---------- prompt cache ----------

    -- 38,016 DESCENDANTS, 12 MILLISECONDS, THREE TIMES PER GRAB.
    --
    -- Measured on a live server: Workspace:GetDescendants() returns 38k
    -- instances and takes 12.1ms to walk. V3.1's first version ran it once per
    -- grab ATTEMPT, so a three-attempt grab spent ~36ms blocking the main
    -- thread - while standing on a nest, which is both a visible hitch and time
    -- the guard uses to reach us.
    --
    -- There are only 61 ProximityPrompts in the place and the steal ones do not
    -- move, so the list is cached. No CollectionService tag exists for them
    -- (CarryAreaEgg / AreaEgg / CarryPrompt all checked, all empty), so the
    -- walk still has to happen - once every PROMPT_CACHE seconds rather than
    -- three times a second.
    local prompts, promptsAt = nil, 0

    -- INSTANT GRAB EGG
    -- When Auto Steal is running, force every ProximityPrompt HoldDuration to 0
    -- and keep doing the same for prompts created later. This removes the local
    -- hold delay before fireproximityprompt/InputHoldBegin is attempted.
    -- Original values are remembered so turning Auto Steal off restores the
    -- prompts instead of leaving shared game instances modified.
    local instantGrabActive = false
    local instantGrabConnection = nil
    local instantGrabOriginals = setmetatable({}, { __mode = "k" })

    local function forceInstantPrompt(desc)
        if not desc or not desc:IsA("ProximityPrompt") then return end
        if instantGrabOriginals[desc] == nil then
            instantGrabOriginals[desc] = desc.HoldDuration
        end
        pcall(function() desc.HoldDuration = 0 end)
    end

    local function restoreInstantPrompts()
        for prompt, original in pairs(instantGrabOriginals) do
            if prompt and prompt.Parent then
                pcall(function() prompt.HoldDuration = original end)
            end
            instantGrabOriginals[prompt] = nil
        end
    end

    function M.setInstantGrab(on)
        on = on and true or false
        if on == instantGrabActive then return end
        instantGrabActive = on

        if instantGrabConnection then
            pcall(function() instantGrabConnection:Disconnect() end)
            instantGrabConnection = nil
        end

        if not on then
            restoreInstantPrompts()
            return
        end

        -- New prompts are made instant automatically.
        instantGrabConnection = workspace.DescendantAdded:Connect(function(desc)
            if instantGrabActive and desc:IsA("ProximityPrompt") then
                forceInstantPrompt(desc)
            end
        end)

        -- Existing prompts become instant immediately.
        local descendants = workspace:GetDescendants()
        for i = 1, #descendants do
            local desc = descendants[i]
            if desc:IsA("ProximityPrompt") then
                forceInstantPrompt(desc)
            end
        end
    end

    function M.instantGrabActive()
        return instantGrabActive
    end

    BX.profile.watch("grab.instantPrompt", function() return instantGrabActive end)

    BX.profile.watch("grab.prompts", function() return prompts and #prompts or 0 end)

    local function promptList()
        local now = os.clock()
        if prompts and (now - promptsAt) < K.PROMPT_CACHE then
            return prompts
        end
        local t0 = os.clock()
        local found = {}
        for _, d in ipairs(workspace:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                local txt = string.lower(tostring(d.ActionText) .. " "
                    .. tostring(d.ObjectText) .. " " .. d.Name)
                if txt:find("steal") or txt:find("carry") then
                    found[#found + 1] = d
                end
            end
        end
        prompts, promptsAt = found, now
        log.trace("prompt cache rebuilt: %d prompts in %.1fms", #found, (os.clock() - t0) * 1000)
        return prompts
    end

    local function promptPos(p)
        local parent = p.Parent
        if not parent then return nil end
        if parent:IsA("BasePart") then return parent.Position end
        if parent:IsA("Model") then return parent:GetPivot().Position end
        return nil
    end

    -- Wait for the game to hand a steal prompt to THIS egg.
    --
    -- Public because the teleport path needs it before the grab does: landing
    -- on a nest in one frame gets us there long before the game has moved a
    -- pooled prompt onto our egg, and firing into that gap does nothing three
    -- times over. Polls the cache we already keep - prompts are reassigned by
    -- changing their Parent, which is re-read every pass, so no rebuild is
    -- needed. Bounded, and it exits the moment one appears.
    function M.waitForPrompt(targetPos, cancel, seconds)
        if typeof(targetPos) ~= "Vector3" then return false end
        local listed = promptList()
        local t0 = os.clock()
        local until_ = t0 + dev.scale(seconds or K.TP_PROMPT_WAIT)
        repeat
            if cancel and cancel() then return false end
            for _, d in ipairs(listed) do
                if d.Parent and d.Enabled then
                    local pos = promptPos(d)
                    if pos and (pos - targetPos).Magnitude <= K.PROMPT_NEAR then
                        log.trace("prompt arrived after %.2fs", os.clock() - t0)
                        return true
                    end
                end
            end
            task.wait(0.05)
        until os.clock() > until_
        log.trace("prompt never showed after %.2fs", os.clock() - t0)
        return false
    end

    ---------- confirmation ----------

    -- Ordered fastest-witness first. Each returns a name, so the log says WHICH
    -- witness answered - and when a grab is wrongly confirmed, that name is the
    -- first clue.
    function M.confirm(uid, baseWalkSpeed, carrySignal)
        if carrySignal then return true, "CarryChanged" end

        -- The server drops WalkSpeed the moment it grants a carry.
        local hum = ch.humanoid()
        if hum and baseWalkSpeed and hum.WalkSpeed and hum.WalkSpeed < (baseWalkSpeed - 1) then
            return true, "walkspeed drop"
        end

        -- THE EGG IN YOUR HAND - BUT IT HAS TO BE THIS EGG.
        --
        -- V3.1's first version accepted any Tool with ItemType == "AssetEgg".
        -- Caught live: a leftover "Spideron Egg" tool was sitting in the
        -- character with a uid that was neither a field egg nor an owned one.
        -- Any grab made while that was in hand confirmed instantly without
        -- having picked anything up, and the loop flew home empty. The UID
        -- attribute must match, or the witness is worthless.
        local char = ch.get()
        if char then
            for _, c in ipairs(char:GetChildren()) do
                if c:IsA("Tool") and c:GetAttribute("ItemType") == "AssetEgg"
                   and tostring(c:GetAttribute("UID")) == tostring(uid) then
                    return true, "egg tool in hand"
                end
            end
        end

        local rec = eggs.get(uid)
        if rec and rec.state == "Carried" then return true, "ReadFieldEgg" end

        -- The whole-table read, which in V3.1's trace is what finally noticed
        -- while the single-uid read still said "Slot". Measured at 0.0001s, so
        -- it is a second opinion rather than a last resort.
        local any
        BX.try("grab.confirmAll", function()
            local data = EggState and EggState.ReadFieldEggs and EggState.ReadFieldEggs()
            for _, r in pairs(data and data.Records or {}) do
                if r.State == "Carried" and tostring(r.Uid) == tostring(uid) then
                    any = true
                    break
                end
            end
        end)
        if any then return true, "ReadFieldEggs" end

        return false, rec and rec.state or "unknown"
    end

    ---------- firing ----------

    local function fireAt(targetPos, cancel)
        if not exec.can.prompts then
            return false, "executor has no fireproximityprompt"
        end
        local hrp = ch.root()
        if not hrp then return false, "no root" end

        local listed = promptList()

        -- BUILD FIRST, POLL SECOND. V3.1 had these the other way round: it
        -- polled the cache for PROMPT_WAIT and on every miss set the cache
        -- timestamp to 0 to "force a rebuild" - but the rebuild is the block
        -- above, which had already run and would not run again until the call
        -- returned. So the wait polled an unchanged list a dozen times and on
        -- the first grab of a session polled an empty table. That is "it
        -- arrives and just goes home again", worst at low frame rates, which is
        -- exactly when the prompt has not been handed over yet.
        if typeof(targetPos) == "Vector3" then
            M.waitForPrompt(targetPos, cancel, K.PROMPT_WAIT)
            if cancel and cancel() then return false, "cancelled" end
        end

        local best, bestDist = nil, math.huge
        for _, d in ipairs(listed) do
            -- Enabled is re-checked live; only the SEARCH is cached.
            if d.Parent and d.Enabled then
                local pos = promptPos(d)
                if pos then
                    -- Must belong to the egg we came for. Without this we
                    -- happily fire a pooled prompt still parked at another nest.
                    local onTarget = (typeof(targetPos) ~= "Vector3")
                        or ((pos - targetPos).Magnitude <= K.PROMPT_NEAR)
                    local dist = (hrp.Position - pos).Magnitude
                    if onTarget and dist <= (d.MaxActivationDistance + 8) and dist < bestDist then
                        best, bestDist = d, dist
                    end
                end
            end
        end

        if not best then
            -- Pooled prompts normally reuse the same instances, but streaming
            -- or respawn can briefly leave the cached list stale. Rebuild once
            -- at the miss rather than firing a stale prompt.
            prompts, promptsAt = nil, 0
            listed = promptList()
            hrp = ch.root()
            if not hrp then return false, "no root" end

            for _, d in ipairs(listed) do
                if d.Parent and d.Enabled then
                    local pos = promptPos(d)
                    if pos then
                        local onTarget = (typeof(targetPos) ~= "Vector3")
                            or ((pos - targetPos).Magnitude <= K.PROMPT_NEAR)
                        local dist = (hrp.Position - pos).Magnitude
                        if onTarget and dist <= ((d.MaxActivationDistance or 8) + 4)
                            and dist < bestDist then
                            best, bestDist = d, dist
                        end
                    end
                end
            end
        end

        if not best then return false, "no prompt for this egg" end

        -- GET INSIDE THE RANGE THE SERVER CHECKS, NOT THE ONE WE CHECK.
        --
        -- This is "sometimes it just flies away without taking the egg", and it
        -- was a lie our own log told us. The search accepts a prompt up to
        -- MaxActivationDistance + 8 away - 16 studs - and fireproximityprompt
        -- returns true from all 16, because it is a local call. The SERVER
        -- re-checks against MaxActivationDistance (8, measured on every steal
        -- prompt here) and silently drops anything further. So the trace read
        -- "fired prompt at 12.4 studs -> true" three times, all three
        -- "succeeded", and no egg was ever handed over.
        local pos = promptPos(best)
        local limit = (best.MaxActivationDistance or 8) - K.STEP_INSIDE
        if pos and bestDist > limit then
            local from = hrp.Position
            local step = pos - from
            local want = pos - (step.Magnitude > 0.1 and step.Unit or Vector3.new(0, 0, 1))
                * math.max(limit * 0.5, 2)
            pcall(function()
                hrp.CFrame = CFrame.new(Vector3.new(want.X, from.Y, want.Z))
                hrp.AssemblyLinearVelocity = Vector3.zero
            end)
            RunService.Heartbeat:Wait()
            local h2 = ch.root()
            if h2 then bestDist = (h2.Position - pos).Magnitude end
        end

        -- RESTORED AFTERWARDS.
        --
        -- V3.1 set HoldDuration = 0 and RequiresLineOfSight = false and left
        -- them that way. These are POOLED objects the game reuses for every
        -- player-facing steal, so the edit persists on a shared instance for
        -- the rest of the session - a standing modification to game state that
        -- nothing ever undoes.
        local wasHold, wasLoS = best.HoldDuration, best.RequiresLineOfSight
        pcall(function()
            best.HoldDuration = 0
            best.RequiresLineOfSight = false
        end)
        local fired = exec.firePrompt(best, 0)
        if fired then exec.firePrompt(best) end
        pcall(function()
            best.HoldDuration = wasHold
            best.RequiresLineOfSight = wasLoS
        end)

        return fired and true or false,
            fired and ("fired at %.1f studs"):format(bestDist)
            or "fireproximityprompt failed",
            bestDist
    end

    ---------- take ----------

    local stats = { attempts = 0, taken = 0, failed = 0, cancelled = 0 }
    function M.stats() return table.clone(stats) end

    function M.take(uid, opts)
        opts = opts or {}
        local cancel = opts.cancel
        local tries  = opts.tries or K.TRIES
        local targetPos = opts.pos

        stats.attempts = stats.attempts + 1
        local t0 = os.clock()

        local hum0 = ch.humanoid()
        local baseWS = (hum0 and hum0.WalkSpeed and hum0.WalkSpeed > 0) and hum0.WalkSpeed or nil

        -- One connection, on a scope, dropped on every exit path. V3.1 built
        -- this connection inside a pcall and disconnected it in one place; an
        -- early return past that point leaked it, once per grab.
        local sc = BX.scope("features.grab.attempt")
        local carrySignal = false
        if EggState and EggState.CarryChanged then
            BX.try("grab.watchCarry", function()
                sc:connect(EggState.CarryChanged, function(info)
                    if type(info) ~= "table" or info.Uid == nil
                       or tostring(info.Uid) == tostring(uid) then
                        carrySignal = true
                    end
                end)
            end)
        end

        local function finish(ok, reason, attempt, fireDist)
            sc:destroy()
            local ms = (os.clock() - t0) * 1000
            if ok then
                stats.taken = stats.taken + 1
                eggs.markStolen(uid)
            elseif reason == "cancelled" then
                stats.cancelled = stats.cancelled + 1
            else
                stats.failed = stats.failed + 1
            end
            -- ONE LINE PER GRAB. Result, which witness confirmed it, how many
            -- attempts it took, how far from the prompt we fired, how long the
            -- whole thing took, and the device tier.
            local level = ok and log.info or log.warn
            level("%s uid=%s after %d/%d tries in %.0fms (witness=%s dist=%s tier=%s)",
                ok and "TAKEN" or ("FAILED: " .. tostring(reason)),
                tostring(uid), attempt or 0, tries, ms, tostring(reason),
                fireDist and string.format("%.1f", fireDist) or "-", dev.tier)
            return ok, {
                reason = reason, attempts = attempt or 0,
                ms = ms, distance = fireDist,
            }
        end

        -- Already holding it (a retry after a lost confirmation, say).
        local have, witness = M.confirm(uid, baseWS, carrySignal)
        if have then return finish(true, witness, 0) end

        for attempt = 1, tries do
            if cancel and cancel() then return finish(false, "cancelled", attempt) end
            if not ch.root() then return finish(false, "no character", attempt) end

            -- The egg may have gone while we were approaching. Checking here
            -- rather than firing blind is what stops us burning three attempts
            -- on something another player already took.
            local ok, state = eggs.stillTakeable(uid)
            if not ok and not carrySignal then
                return finish(false, "egg " .. tostring(state), attempt)
            end

            local fired, why, dist = fireAt(targetPos, cancel)
            if why == "cancelled" then return finish(false, "cancelled", attempt) end

            if fired then
                -- Wait for a witness rather than assuming. The server's grant
                -- and EggState's replication are a round trip apart.
                local until_ = os.clock() + dev.scale(K.CONFIRM_WINDOW)
                repeat
                    if cancel and cancel() then return finish(false, "cancelled", attempt, dist) end
                    local got, w = M.confirm(uid, baseWS, carrySignal)
                    if got then return finish(true, w, attempt, dist) end
                    RunService.Heartbeat:Wait()
                until os.clock() > until_
            end

            -- NEVER RETRY WITHOUT YIELDING. A failed attempt going straight
            -- round again is a hot loop hammering the prompt, which is both a
            -- frame cost and the shape of traffic that gets noticed.
            if attempt < tries then task.wait(dev.scale(K.RETRY_GAP)) end
        end

        local got, w = M.confirm(uid, baseWS, carrySignal)
        if got then return finish(true, w, tries) end
        return finish(false, "no confirmation", tries)
    end

    -- The prompt cache holds Instances, but they are the game's pooled prompts:
    -- long-lived, never per-egg, and re-checked for .Parent on every use, so a
    -- destroyed one is skipped rather than resurrected. It needs no scope of
    -- its own - BX.teardown clears BX._loaded, which takes this module and its
    -- cache with it.
    -- WARM IT BEFORE THE FIRST STEAL NEEDS IT.
    --
    -- The walk below is the one measured at 38,016 descendants / 12.1ms, and
    -- until something calls it the cache is empty - `grab.prompts=0` in the
    -- startup health line. That meant the FIRST steal always paid for it, in the
    -- middle of a cycle, while standing on a nest. It is a pure read, so it can
    -- just as well happen while the loading card is still up.
    --
    -- Returns the cost so the prewarm log can state it rather than claim it.
    function M.warmPrompts()
        local t0 = os.clock()
        local n = #promptList()
        return (os.clock() - t0) * 1000, n
    end

    function M.clearCache()
        prompts, promptsAt = nil, 0
    end

    return M
end)

--[[ ==== features/instant.lua ======================================== ]]
-- =============================================================================
-- FEATURES.INSTANT: teleport onto the egg and race the server for it
-- =============================================================================
--
--     local instant = BX.require("features.instant")
--     local ok, info = instant.take(uid, eggPos, { cancel = fn })
--
-- THIS IS V3.1's INSTANT STEAL. It is not "teleport, then check whether the
-- teleport was allowed" - that question is never asked, because the answer does
-- not matter.
--
-- HOW IT ACTUALLY WORKS. Measured on the live server by V3.1:
--
--     CarryFieldEgg is a BLOCKING RemoteFunction    ~160ms round trip
--     a bare PivotTo is relocated by the server     ~170ms later
--
-- So the server WILL pull us back - continuously, about six times a second.
-- That is fine. What matters is only where the character is at the instant the
-- server processes CarryFieldEgg. So:
--
--   1. A HOLD THREAD re-asserts PivotTo onto the egg every Heartbeat (~16ms),
--      which is ten times faster than the relocate can undo it.
--   2. THREE STAGGERED INVOKERS each call CarryFieldEgg in a loop, 0.05s apart,
--      so there is always a call in flight rather than a 160ms gap between them.
--   3. The first one to come back true wins and everything stops.
--
-- A PREVIOUS VERSION OF THIS PORT GOT IT WRONG, and the mistake is worth
-- recording: it teleported, waited K.TP_SETTLE (0.35s), measured the distance
-- to the egg and declared the teleport "refused" when it had been pulled back.
-- The relocate arrives at ~170ms, so waiting 350ms measured a guaranteed
-- failure every time - it reported "server refused" on a path V3.1 uses
-- successfully. The settle-and-verify step does not exist in V3.1 and is gone.
--
-- WHY THE HOLD THREAD MUST BE ABLE TO DIE WITHOUT US. V3.1 hit a case where the
-- flag that stops the hold never ran, so the hold thread kept re-asserting
-- position while the server relocated, several times a second, with nothing
-- left to stop it. The generation check and the scope below both exist for
-- that: the thread tests a generation number it captured, and the scope cancels
-- it outright on any exit path.

BX.module("features.instant", function(BX)
    local svc  = BX.require("core.services")
    local data = BX.require("core.data")
    local ch   = BX.require("core.character")
    local dev  = BX.require("core.device")
    local eggs  = BX.require("features.eggs")
    local guard = BX.require("features.guard")
    local log  = BX.require("boot.log").for_module("instant")

    local RunService = svc.RunService
    local M = {}

    local K = {
        -- The log shows ~2.6-2.7s spent in the instant stage on every miss.
        -- Shorten the first race so a refused target reaches normal fallback sooner.
        TIMEOUT       = 1.0,
        RACE_THREADS  = 3,     -- K.CARRY_RACE_THREADS
        RACE_STAGGER  = 0.05,  -- K.CARRY_RACE_STAGGER
        LIFT          = 2,     -- stand this far above the egg record
        TARGET_REFRESH = 0.06, -- live egg-position refresh
        REANCHOR       = 0.20, -- live re-anchor window
        STUCK_WINDOW   = 0.28, -- stuck recovery window
        -- Further than this from the egg when the race ends means the
        -- server had us somewhere else - a pull-back, not a near miss.
        PULLBACK_GAP  = 25,
        -- A REFUSAL THAT KEEPS COMING BACK IS AN ANSWER, NOT A RACE.
        --
        -- Measured on a failing recovery: 274 calls in 6.6s - about 41 remote
        -- invocations a second, sustained, all returning the same message, and
        -- the client dropped to tier=low under it. The race is meant to beat a
        -- ~170ms relocate, not to hammer a settled "no".
        --
        -- The first few calls stay flat out, because that is the window a real
        -- win happens in. After that, repeats of the SAME message slow down,
        -- and enough of them ends the attempt - the outer retry can re-read the
        -- record and try again from a fresh position.
        FREE_CALLS    = 10,    -- enough fast calls to catch the normal success window
        SAME_MSG_GAP  = 0.08,   -- faster retry cadence after an identical refusal
        SAME_MSG_STOP = 20,     -- fail sooner when the server keeps saying the same thing
    }
    M.K = K

    -- THROUGH core.data. A private FindFirstChild + require here bypassed
    -- the one place that knows whether this executor can require game
    -- modules at all, and cached a miss forever. core.data probes once,
    -- lets a miss expire, and backs off - see core/data.lua.
    local EggState, SlotIdentity = data.eggState(), data.slotIdentity()

    -- Re-asked at use, not only at load: on a slow join the module can
    -- arrive after the hub did. core.data makes the re-ask cheap.
    local function ensureModules()
        if not EggState then EggState = data.eggState() end
        if not SlotIdentity then SlotIdentity = data.slotIdentity() end
        M.ready = (EggState ~= nil and type(EggState.CarryFieldEgg) == "function")
        return M.ready
    end
    ensureModules()
    if not M.ready then
        log.warn("EggState.CarryFieldEgg unavailable - instant steal disabled until it resolves")
    end

    local holdGen = 0
    local stats = { runs = 0, won = 0, lost = 0, cancelled = 0, calls = 0 }
    function M.stats() return table.clone(stats) end

    -- The slot key first-area eggs need, or nil. Without it the server refuses
    -- the carry outright for those.
    local function slotKeyFor(uid, areaId, nestId)
        local key = nil
        BX.try("instant.slotKey", function()
            if SlotIdentity and SlotIdentity.LooksLikeFirstAreaUid
               and SlotIdentity.LooksLikeFirstAreaUid(uid) then
                key = SlotIdentity.SlotKey(areaId, nestId)
            end
        end)
        return key
    end

    -- uid      the egg
    -- eggPos   Vector3 of its record
    -- opts     { cancel = fn, areaId = , nestId = , timeout = }
    function M.take(uid, eggPos, opts)
        opts = opts or {}
        local cancel = opts.cancel or function() return false end

        -- Delivery transport (especially RIDE_GUARD) must never leave the
        -- pickup character in a seated/physics state.  The guard is only a
        -- delivery transport, so pickup always starts from a clean humanoid
        -- state.  This is deliberately local/client-side and does not alter
        -- the game's carry state.
        if tostring(opts.method or ""):upper() == "RIDE_GUARD" then
            local hum = ch.humanoid()
            if hum then
                pcall(function()
                    hum.Sit = false
                    hum.PlatformStand = false
                    hum.AutoRotate = true
                    hum:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
                    hum:SetStateEnabled(Enum.HumanoidStateType.Running, true)
                end)
            end
            local root = ch.root()
            if root then
                pcall(function()
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                end)
            end
        end
        if not M.ready and not ensureModules() then return false, { reason = "no CarryFieldEgg" } end
        if typeof(eggPos) ~= "Vector3" then return false, { reason = "no egg position" } end

        local char = ch.get()
        if not char then return false, { reason = "no character" } end

        stats.runs = stats.runs + 1
        local t0 = os.clock()

        -- The egg can move between the cached scan and the actual pickup
        -- (guard carry-back, replication delay, server correction). Keep a
        -- mutable target instead of holding one stale CFrame for the whole
        -- race.
        local targetPos = eggPos
        local function targetCFrame(pos)
            return CFrame.new(pos.X, pos.Y + K.LIFT, pos.Z)
        end
        local target = targetCFrame(targetPos)
        local slotKey = slotKeyFor(uid, opts.areaId, opts.nestId)
        -- Scaled: a weak client gets fewer frames, so it needs longer to land
        -- the same number of attempts.
        local deadline = os.clock() + dev.scale(opts.timeout or K.TIMEOUT)

        -- Everything below lives on this scope, so a cancel, a respawn or a
        -- re-execute takes the hold thread and every invoker with it.
        local sc = BX.scope("features.instant.race")
        holdGen = holdGen + 1
        local myGen = holdGen
        local won, tries, lastMsg = false, 0, nil
        local sameMsg, sameCount = nil, 0
        local bailed = false
        local lastRefresh = 0
        local lastReanchor = 0
        local lastProgress = os.clock()
        local bestGap = math.huge

        BX.profile.mark("target_tp")

        -- SERVER-VISIBLE APPROACH:
        -- CarryFieldEgg validates the character position on the server. A pure
        -- client PivotTo can show a close local gap while the server still sees
        -- the previous position and replies "Get closer to the egg". Make one
        -- short normal movement pass before the instant race.
        do
            local h = ch.root()
            if h and (h.Position - targetPos).Magnitude > 3 then
                pcall(function()
                    move.travel{
                        to = targetPos, speed = 900, arrive = 2.5,
                        carrying = false, cancel = cancel,
                        tag = "instant server-visible approach",
                    }
                end)
                RunService.Heartbeat:Wait()
                local fresh = eggs.get(uid)
                if fresh and fresh.pos and (fresh.state == "Slot" or fresh.state == "Dropped") then
                    targetPos = fresh.pos
                    target = targetCFrame(targetPos)
                end
            end
        end

        -- (1) THE HOLD. Re-assert position every frame, faster than the server
        --     can undo it.
        sc:spawn("hold", function()
            while not won and holdGen == myGen and os.clock() < deadline and sc:alive() do
                local now = os.clock()

                -- Refresh the authoritative egg record while the pickup race is
                -- running. This fixes the common case where the cached position
                -- is already stale when the server processes CarryFieldEgg.
                if now - lastRefresh >= K.TARGET_REFRESH then
                    lastRefresh = now
                    local rec = eggs.get(uid)
                    if rec and (rec.state == "Slot" or rec.state == "Dropped") and rec.pos then
                        if (rec.pos - targetPos).Magnitude > 1.5 then
                            targetPos = rec.pos
                            target = targetCFrame(targetPos)
                        end
                    elseif rec and rec.state == "Carried" then
                        won = true
                        return
                    end
                end

                local c = ch.get()
                local h = ch.root()
                if c and h then
                    local gap = (h.Position - targetPos).Magnitude
                    if gap + 2 < bestGap then
                        bestGap = gap
                        lastProgress = now
                    end

                    -- The server can snap the character away from the egg.
                    -- Heartbeat anchoring normally handles it, but if the gap
                    -- stays bad for a short window, force a fresh anchor to the
                    -- newest server-reported egg position.
                    if now - lastProgress >= K.STUCK_WINDOW
                       or now - lastReanchor >= K.REANCHOR then
                        lastReanchor = now
                        pcall(function() c:PivotTo(target) end)
                        bestGap = (h.Position - targetPos).Magnitude
                        lastProgress = now
                    else
                        pcall(function() c:PivotTo(target) end)
                    end

                    h.AssemblyLinearVelocity = Vector3.zero
                    h.AssemblyAngularVelocity = Vector3.zero
                end
                RunService.Heartbeat:Wait()
            end
        end)

        -- WAIT OUT THE SERVER KNOCKDOWN *HERE*, NOT BEFORE LEAVING.
        --
        -- V3.1 is explicit about this, at the point the wait would otherwise go
        -- (line 5395):
        --     "NO WAITING HERE. Prime, take the hit, LEAVE. I put a knockdown
        --      wait in this spot and it was wrong. The travel is what covers
        --      the knockdown."
        -- Its own knockdown wait lives inside carryEgg - i.e. AT THE EGG, after
        -- arriving - not between the hit and the departure.
        --
        -- An earlier version of this module had it before the teleport, which
        -- put 2.4 seconds of standing next to the Forest guard into every
        -- cycle: measured hit_detected@1.66 -> target_tp@4.04. The hold thread
        -- above is already running, so the wait now happens pinned to the
        -- target egg instead of parked beside the guard that just hit us.
        local heldFor = guard.waitForServerRelease(cancel)
        if cancel() then
            holdGen = holdGen + 1
            sc:destroy()
            stats.cancelled = stats.cancelled + 1
            return false, { reason = "cancelled", ms = (os.clock() - t0) * 1000 }
        end

        -- RIDE_GUARD is a delivery transport only.  Before firing the carry
        -- remote, refresh the egg position and do one final anchor.  This
        -- removes a common stuck-pickup case where the previous delivery's
        -- guard/saddle was just destroyed while the server was still reporting
        -- the character at the old position.
        if tostring(opts.method or ""):upper() == "RIDE_GUARD" then
            local fresh = eggs.get(uid)
            if fresh and fresh.pos and (fresh.state == "Slot" or fresh.state == "Dropped") then
                targetPos = fresh.pos
                target = targetCFrame(targetPos)
                local c = ch.get()
                local h = ch.root()
                if c and h then
                    pcall(function() c:PivotTo(target) end)
                    h.AssemblyLinearVelocity = Vector3.zero
                    h.AssemblyAngularVelocity = Vector3.zero
                end
            end
        end

        -- (2) THE INVOKERS, staggered so a call is always in flight.
        for i = 1, K.RACE_THREADS do
            sc:spawn("invoke" .. i, function()
                task.wait((i - 1) * K.RACE_STAGGER)
                while not won and not bailed and os.clock() < deadline and sc:alive() do
                    if cancel() then return end
                    tries = tries + 1
                    stats.calls = stats.calls + 1
                    local ok, res, msg = pcall(function()
                        return EggState.CarryFieldEgg(uid, slotKey)
                    end)
                    if msg ~= nil then lastMsg = tostring(msg) end

                    -- This is a state gate, not a pickup race. Hammering the
                    -- remote while the character is outside the gameplay area
                    -- only burns calls and produces the repeated LOST spam seen
                    -- in the trace. Abort this attempt immediately and let the
                    -- outer AutoSteal recovery decide when to retry.
                    if type(msg) == "string"
                       and msg:lower():find("enter the gameplay area first", 1, true) then
                        -- Server-side area gate. Do not burn the remaining race
                        -- on identical calls. Return the gate to runCycle so it
                        -- can physically re-anchor/approach the target and then
                        -- use the normal prompt pickup path.
                        lastMsg = msg
                        bailed = true
                        return
                    end

                    -- A REFUSAL WE ALREADY KNOW THE ANSWER TO IS NOT AN
                    -- ATTEMPT. If the server says we are still downed, more
                    -- calls cannot help - wait for the clock.
                    if type(msg) == "string"
                       and msg:lower():find("get closer to the egg", 1, true) then
                        -- This refusal is server-distance based. Re-approach
                        -- through normal movement once so the server receives a
                        -- real position update, then resume the existing race.
                        local fresh = eggs.get(uid)
                        if fresh and fresh.pos and (fresh.state == "Slot" or fresh.state == "Dropped") then
                            targetPos = fresh.pos
                            target = targetCFrame(targetPos)
                        end
                        pcall(function()
                            move.travel{
                                to = targetPos, speed = 900, arrive = 2.0,
                                carrying = false, cancel = cancel,
                                tag = "instant closer reapproach",
                            }
                        end)
                        RunService.Heartbeat:Wait()
                        sameMsg = nil
                        sameCount = 0
                    end

                    if type(msg) == "string" and msg:lower():find("downed") then
                        local left = guard.ragdollRemaining()
                        if left > 0 then task.wait(math.min(left, 0.25)) end
                    end

                    -- THROTTLE A REPEATING ANSWER.
                    if not won and type(msg) == "string" then
                        if msg == sameMsg then
                            sameCount = sameCount + 1
                        else
                            sameMsg, sameCount = msg, 1
                        end
                        if sameCount >= K.SAME_MSG_STOP then
                            bailed = true
                            return
                        end
                        if tries > K.FREE_CALLS and sameCount > 1 then
                            task.wait(K.SAME_MSG_GAP)
                        end
                    end
                    -- Re-checked AFTER the call returns: two can be in flight
                    -- at once and only the first winner may claim the carry.
                    if ok and res == true and not won then
                        won = true
                        return
                    end
                    if won then return end

                    -- EVERY PASS YIELDS. NO EXCEPTIONS.
                    --
                    -- This is the freeze, and it is the same class of bug V3.1
                    -- documents in its steal loop. Every task.wait above is
                    -- CONDITIONAL on msg being a string. When CarryFieldEgg
                    -- errors synchronously - pcall returns false and msg is nil
                    -- - none of them run, the remote never yields either, and
                    -- all three threads spin flat out until the deadline.
                    --
                    -- Three threads x 3s of a Luau loop that never yields locks
                    -- the client solid, and through regrab that is 4 attempts
                    -- per recovery and 2 recoveries per steal.
                    --
                    -- One Heartbeat costs ~16ms against a remote round trip
                    -- measured at 70-160ms, so the race is not meaningfully
                    -- slowed - and it can no longer become a freeze whatever
                    -- the remote does.
                    RunService.Heartbeat:Wait()
                end
            end)
        end

        -- (3) Wait for a winner.
        local cancelled = false
        while not won and not bailed and os.clock() < deadline do
            if cancel() then cancelled = true break end
            RunService.Heartbeat:Wait()
        end

        -- Stops the hold immediately; the scope then cancels every thread.
        holdGen = holdGen + 1
        sc:destroy()

        local ms = (os.clock() - t0) * 1000
        local gap = (function()
            local h = ch.root()
            return h and (h.Position - targetPos).Magnitude or -1
        end)()

        if cancelled then
            stats.cancelled = stats.cancelled + 1
            log.info("cancelled after %d calls in %.0fms", tries, ms)
            return false, { reason = "cancelled", calls = tries, ms = ms }
        end

        BX.profile.mark(won and "target_landed" or "target_lost")

        if won then
            stats.won = stats.won + 1
            eggs.markStolen(uid)
            log.info("WON uid=%s after %d calls in %.0fms (%d threads, gap %.1f, tier=%s)",
                tostring(uid), tries, ms, K.RACE_THREADS, gap, dev.tier)
            return true, { reason = "instant", calls = tries, ms = ms,
                           gap = gap, heldFor = heldFor }
        end

        stats.lost = stats.lost + 1

        if type(lastMsg) == "string"
           and lastMsg:lower():find("enter the gameplay area first", 1, true) then
            log.warn("pickup refused: %s", lastMsg)
            return false, {
                reason = lastMsg,
                calls = tries,
                ms = ms,
                serverGate = true,
            }
        end

        -- WHY IT FAILED, NOT JUST THAT IT DID.
        --
        -- "Get closer to the egg" alone cannot be acted on. These four answer
        -- the question it raises - was our LOCAL position fine while the
        -- server had us somewhere else, or did the egg itself move or go?
        local rec = eggs.get(uid)
        local pulledBack = gap > K.PULLBACK_GAP
        local diag = ("localGap=%.1f eggState=%s eggMoved=%s pulledBack=%s%s"):format(
            gap,
            rec and tostring(rec.state) or "gone",
            rec and rec.pos and tostring((rec.pos - eggPos).Magnitude > 5) or "?",
            tostring(pulledBack),
            bailed and (" bailed after %d identical refusals"):format(sameCount) or "")

        log.warn("LOST uid=%s after %d calls in %.0fms (%s, last: %s, tier=%s)",
            tostring(uid), tries, ms, diag, tostring(lastMsg), dev.tier)

        return false, {
            reason = lastMsg or "no accept",
            calls = tries, ms = ms, gap = gap,
            pulledBack = pulledBack,
            eggState = rec and rec.state or "gone",
            eggGone = rec == nil,
            heldFor = heldFor,
        }
    end

    return M
end)

--[[ ==== features/plot.lua =========================================== ]]
-- =============================================================================
-- FEATURES.PLOT: where home is, and when the egg is actually ours
-- =============================================================================
--
--     local plot = BX.require("features.plot")
--
--     plot.home()          -- Vector3 to carry to, or nil with a reason
--     plot.claimedSince(t) -- has the server claimed an egg since t?
--     plot.onClaim(sc, label, fn)
--
-- THE HARDCODED FALLBACK IS DELIBERATELY NOT PORTED.
--
-- V3.1 ended its resolution ladder with
--     local SAFE_POS_FALLBACK = Vector3.new(512, 68, -362)
-- which is a literal measured on ONE account. Its own comment says what that
-- cost: when PlotState.FindRespawnCFrame returns nothing on somebody else's
-- client - and it does, it is the first thing to resolve after a join and the
-- last to recover after a hop - the carry was flown to that account's plot
-- instead of theirs. The trip works perfectly, the egg is never voided, and
-- the claim simply never fires because they are standing on a stranger's base.
--
-- That is the mobile report exactly: the egg survives four thousand studs
-- through every zone and dies at the destination with "Delivery failed! The
-- egg was returned to its nest". Nothing about the journey was wrong. The
-- address was.
--
-- So the ladder ends in nil, and a nil home REFUSES the delivery rather than
-- flying somewhere plausible. Failing to start is recoverable; carrying an egg
-- to a stranger's plot is not.

BX.module("features.plot", function(BX)
    local svc = BX.require("core.services")
    local data = BX.require("core.data")
    local log = BX.require("boot.log").for_module("plot")

    local M = {}

    local K = {
        HOME_TTL = 30,      -- slots can change while connected, so re-resolve
        ARRIVE   = 18,      -- close enough to the plot middle
    }
    M.K = K

    -- THROUGH core.data. A private FindFirstChild + require here bypassed
    -- the one place that knows whether this executor can require game
    -- modules at all, and cached a miss forever. core.data probes once,
    -- lets a miss expire, and backs off - see core/data.lua.
    local PlotState = data.plotState()

    local cached, cachedAt, cachedVia = nil, 0, nil

    -- Every rung is about THIS player: the game's own respawn point, their
    -- plot model, then this server's spawn. None of them is a literal.
    local function resolve()
        local pos, via

        if PlotState then
            BX.try("plot.findRespawn", function()
                local cf = PlotState.FindRespawnCFrame and PlotState.FindRespawnCFrame()
                if typeof(cf) == "CFrame" then pos, via = cf.Position, "PlotState.FindRespawnCFrame" end
            end)
        end

        if not pos and PlotState then
            BX.try("plot.resolveSlot", function()
                local slot = PlotState.ResolveLocalSlot and PlotState.ResolveLocalSlot()
                local plots = slot and workspace:FindFirstChild("Plots")
                local mine = plots and plots:FindFirstChild(tostring(slot))
                if mine then
                    local cf = mine:GetPivot()
                    if typeof(cf) == "CFrame" then pos, via = cf.Position, "plot " .. tostring(slot) end
                end
            end)
        end

        if not pos then
            BX.try("plot.spawnLocation", function()
                local sl = workspace:FindFirstChildOfClass("SpawnLocation")
                if sl and sl:IsA("BasePart") then
                    pos, via = sl.Position + Vector3.new(0, 4, 0), "SpawnLocation"
                end
            end)
        end

        if not pos then
            BX.try("plot.spawnTarget", function()
                local st = workspace:FindFirstChild("SpawnTarget", true)
                if st and st:IsA("BasePart") then
                    pos, via = st.Position + Vector3.new(0, 4, 0), "SpawnTarget"
                end
            end)
        end

        return pos, via
    end

    -- Returns pos, via  -- or nil, reason
    function M.home()
        local now = os.clock()
        if cached and (now - cachedAt) < K.HOME_TTL then
            return cached, cachedVia
        end
        local pos, via = resolve()
        if not pos then
            -- Loud, and it stops the cycle. See the header.
            log.error("cannot resolve this player's plot - refusing to deliver "
                .. "(PlotState=%s)", tostring(PlotState ~= nil))
            return nil, "no plot resolved"
        end
        if via ~= cachedVia then
            log.info("home resolved via %s at %s", via, tostring(pos))
        end
        cached, cachedAt, cachedVia = pos, now, via
        return cached, cachedVia
    end

    function M.forget()
        cached, cachedAt = nil, 0
    end


    ---------- the safe zone: where a carried egg is delivered ----------

    -- NOT THE PLOT. V3.1 BX.safeZonePos, resolved in this order:
    --     1. workspace SpawnLocation   + 4 studs up
    --     2. workspace SpawnTarget     + 4 studs up
    --     3. the plot                  (fallback only)
    --
    -- An earlier version of this port carried to the plot centre because
    -- delivery eventually involves your own area. That is not where V3.1 goes
    -- and not where the claim happens - the egg has to reach the safe zone.
    --
    -- The hardcoded Vector3 that ends V3.1 ladder is deliberately still not
    -- ported; see the header.
    local szCache, szAt, szVia = nil, 0, nil

    function M.safeZone()
        local now = os.clock()
        if szCache and (now - szAt) < K.HOME_TTL then
            return szCache, szVia
        end

        local pos, via

        BX.try("plot.spawnLocationZone", function()
            local sl = workspace:FindFirstChildOfClass("SpawnLocation")
            if sl and sl:IsA("BasePart") then
                pos, via = sl.Position + Vector3.new(0, 4, 0), "SpawnLocation"
            end
        end)

        if not pos then
            BX.try("plot.spawnTargetZone", function()
                local st = workspace:FindFirstChild("SpawnTarget", true)
                if st and st:IsA("BasePart") then
                    pos, via = st.Position + Vector3.new(0, 4, 0), "SpawnTarget"
                end
            end)
        end

        if not pos then
            -- Fallback only, and it is the players OWN plot - resolved
            -- dynamically, never a literal.
            local p, pvia = M.home()
            if p then pos, via = p, "plot fallback (" .. tostring(pvia) .. ")" end
        end

        if not pos then
            log.error("cannot resolve a safe zone - refusing to deliver")
            return nil, "unresolved"
        end

        if via ~= szVia then
            log.info("safe zone resolved via %s at %s", via, tostring(pos))
        end
        szCache, szAt, szVia = pos, now, via
        return szCache, szVia
    end

    function M.forgetSafeZone()
        szCache, szAt = nil, 0
    end

    ---------- Forest handoff zone (Help Friends) ----------
    -- Help Friends deliberately does NOT use the Safe Zone claim path.
    -- Resolve a real Forest location from the live game instead of a hardcoded
    -- coordinate. Prefer a live Forest egg as an area anchor, then the streamed
    -- GuardAreas/Forest Bounds, then an exact Workspace object named Forest.
    local forestCache, forestAt, forestVia = nil, 0, nil

    function M.forestZone()
        local now = os.clock()
        if forestCache and (now - forestAt) < K.HOME_TTL then
            return forestCache, forestVia
        end

        local pos, via

        BX.try("plot.forest.liveEgg", function()
            local eggFeature = BX.require("features.eggs")
            for _, egg in ipairs(eggFeature.list() or {}) do
                if tostring(egg.areaId or ""):lower() == "forest"
                    and typeof(egg.pos) == "Vector3" then
                    pos, via = egg.pos + Vector3.new(0, 3, 0), "live Forest egg"
                    break
                end
            end
        end)

        if not pos then
            BX.try("plot.forest.guardBounds", function()
                local areas = workspace:FindFirstChild("GuardAreas", true)
                local forest = areas and areas:FindFirstChild("Forest")
                local bounds = forest and forest:FindFirstChild("Bounds")
                if bounds and bounds:IsA("BasePart") then
                    pos, via = bounds.Position + Vector3.new(0, 3, 0), "GuardAreas.Forest.Bounds"
                end
            end)
        end

        if not pos then
            BX.try("plot.forest.workspace", function()
                for _, inst in ipairs(workspace:GetDescendants()) do
                    if tostring(inst.Name):lower() == "forest" then
                        local candidate
                        if inst:IsA("BasePart") then
                            candidate = inst.Position
                        elseif inst:IsA("Model") then
                            local cf = inst:GetPivot()
                            if typeof(cf) == "CFrame" then candidate = cf.Position end
                        end
                        if candidate then
                            pos, via = candidate + Vector3.new(0, 3, 0), "Workspace.Forest"
                            break
                        end
                    end
                end
            end)
        end

        if not pos then
            log.warn("cannot resolve Forest Help Friends destination")
            return nil, "Forest destination unresolved"
        end

        forestCache, forestAt, forestVia = pos, now, via
        log.info("Forest Help Friends destination resolved via %s at %s", tostring(via), tostring(pos))
        return forestCache, forestVia
    end

    function M.forgetForestZone()
        forestCache, forestAt = nil, 0
    end

    ---------- claim ----------

    -- The server telling us the egg is ours. This is the ONLY authority on a
    -- successful delivery - arriving at the plot is not delivery, and V3.1's
    -- own logs are full of perfect arrivals that were never claimed.
    local lastClaimAt, lastClaimName, lastClaimUid = 0, nil, nil
    local listeners = {}

    function M.claimedSince(t, uid)
        if lastClaimAt <= (t or 0) then
            return false, lastClaimName, lastClaimUid
        end
        if uid ~= nil and lastClaimUid ~= nil
            and tostring(lastClaimUid) ~= tostring(uid) then
            return false, lastClaimName, lastClaimUid
        end
        return true, lastClaimName, lastClaimUid
    end

    function M.onClaim(sc, label, fn)
        listeners[#listeners + 1] = { scope = sc, label = label, fn = fn }
    end

    local sc = BX.scope("features.plot")
    local EggState
    BX.try("plot.resolveEggState", function()
        local found = svc.ReplicatedStorage:FindFirstChild("EggState", true)
        if found and found:IsA("ModuleScript") then EggState = require(found) end
    end)

    if EggState and EggState.FieldClaimed then
        BX.try("plot.armClaimWatch", function()
            sc:connect(EggState.FieldClaimed, function(info)
                lastClaimAt = os.clock()
                lastClaimName = (type(info) == "table"
                    and (info.DisplayName or info.AssetCategory)) or "egg"
                lastClaimUid = type(info) == "table"
                    and (info.Uid or info.UID or info.EggUid or info.EggUID)
                    or nil
                log.info("CLAIM: server claimed egg -> %s uid=%s",
                    tostring(lastClaimName), tostring(lastClaimUid or "?"))
                for i = #listeners, 1, -1 do
                    local L = listeners[i]
                    if not L.scope or L.scope.dead then
                        table.remove(listeners, i)
                    else
                        BX.try("plot/" .. L.label, L.fn, lastClaimName)
                    end
                end
            end)
        end)
    else
        log.warn("EggState.FieldClaimed unavailable - deliveries cannot be confirmed")
    end

    M._listeners = function() return #listeners end
    return M
end)

--[[ ==== features/regrab.lua ========================================= ]]
-- =============================================================================
-- FEATURES.REGRAB: go back for an egg the guard knocked out of our hands
-- =============================================================================
--
--     local regrab = BX.require("features.regrab")
--     local ok, info = regrab.recover(uid, { cancel = fn })
--
-- THE RECOVERY IS NOT A BAIT RESTART.
--
-- This is V3.1 BX.regrabEgg, and the important part is what it does NOT do: it
-- never goes back to the Forest guard to run the bait cycle again. It goes back
-- for THE EGG. Restarting at the guard means a full cross-map trip, a second
-- knockdown and a fresh prime, to end up chasing the same egg anyway.
--
-- CHASE IT, DO NOT AIM AT WHERE IT WAS.
--
-- V3.1 note, and it is the whole reason this re-reads the record on every
-- attempt: a dropped egg does not stay put. A guard picks it up and walks it
-- back to its nest, so a position read once before travelling is wrong by the
-- time we arrive and the carry is refused for range forever. That is "it goes
-- for the dropped egg and never picks it up".
--
-- WAIT FOR THREE THINGS BEFORE ASKING, IN THIS ORDER
--
--   1. The settle. The drop and the ragdoll arrive a frame apart (V3.1
--      measured the drop at 14.44 and BeginRagdoll at 14.50), so checking in
--      between sees a character that is not down yet and waits for nothing.
--   2. The server knockdown. "Cannot carry eggs while downed" is its own
--      refusal text, so there is no point asking until RagdollEndTime passes.
--   3. The egg itself. Straight after a drop the record is stale, and while a
--      guard is walking it back it reads GuardCarried. Claimed means it
--      actually banked; a missing record means it is gone.
--
-- BOUNDED, ALWAYS. Two recoveries per steal (V3.1 midCarryRegrabs < 2) and
-- REGRAB_TRIES attempts inside each, so a repeatedly-dropped egg cannot turn
-- into a fast restart loop. The budget is reset by the caller on a fresh steal.

BX.module("features.regrab", function(BX)
    local svc     = BX.require("core.services")
    local eggs    = BX.require("features.eggs")
    local instant = BX.require("features.instant")
    local move    = BX.require("features.movement")
    local guard   = BX.require("features.guard")
    local ch      = BX.require("core.character")
    local dev     = BX.require("core.device")
    local log     = BX.require("boot.log").for_module("regrab")

    local RunService = svc.RunService
    local M = {}

    local K = {
        SETTLE      = 0.02,   -- faster recovery settle; state is checked immediately
        WAIT        = 2.75,   -- short settle window; do not park recovery for 8s
        POLL        = 0.05,
        TRIES       = 5,      -- 5/5 recovery attempts
        MAX_PER_STEAL = 5,    -- allow the full 5/5 recovery budget per delivery
    }
    M.K = K

    local stats = { runs = 0, recovered = 0, banked = 0, gone = 0, failed = 0, cancelled = 0 }
    function M.stats() return table.clone(stats) end

    -- Takeable again? Returns pos, state.
    local function settledPos(uid)
        local r = eggs.get(uid)
        if not r then return nil, nil end
        return r.pos, r.state
    end

    -- uid    the egg we just lost
    -- opts   { cancel = fn, attempt = n }  attempt is the caller budget counter
    function M.recover(uid, opts)
        opts = opts or {}
        local cancel = opts.cancel or function() return false end
        stats.runs = stats.runs + 1
        local t0 = os.clock()

        -- 1. Let the knockdown register before testing for it.
        task.wait(K.SETTLE)
        if cancel() then
            stats.cancelled = stats.cancelled + 1
            return false, { reason = "cancelled", recovery = "cancelled" }
        end

        -- 2. The server hold. Asking inside it only collects refusals.
        local heldFor = guard.waitForServerRelease(cancel)
        if cancel() then
            stats.cancelled = stats.cancelled + 1
            return false, { reason = "cancelled", recovery = "cancelled" }
        end

        -- 3. Wait for the egg to be takeable again.
        local deadline = os.clock() + dev.scale(K.WAIT)
        local pos, state, said
        repeat
            if cancel() then
                stats.cancelled = stats.cancelled + 1
                return false, { reason = "cancelled", recovery = "cancelled" }
            end
            pos, state = settledPos(uid)
            if state == "Claimed" then
                -- Not a failure: it banked. Somebody got it, possibly us.
                stats.banked = stats.banked + 1
                log.info("drop_recovery=banked uid=%s (the egg was claimed)", tostring(uid))
                return false, { reason = "claimed", recovery = "banked" }
            end
            if state == nil then
                -- EggState can briefly return no record while a dropped egg is
                -- being re-parented/replicated. Do not declare it gone on the
                -- first empty read; give replication a short grace window.
                local graceUntil = os.clock() + dev.scale(1.25)
                local recoveredState
                repeat
                    if cancel() then
                        stats.cancelled = stats.cancelled + 1
                        return false, { reason = "cancelled", recovery = "cancelled" }
                    end
                    task.wait(K.POLL)
                    local gp, gs = settledPos(uid)
                    if gs then
                        pos, state = gp, gs
                        recoveredState = gs
                        break
                    end
                until os.clock() >= graceUntil

                if not recoveredState then
                    stats.gone = stats.gone + 1
                    log.warn("drop_recovery=failed uid=%s (record gone after grace)", tostring(uid))
                    return false, { reason = "gone", recovery = "failed" }
                end
            end
            if state == "Slot" or state == "Dropped" then break end
            if state ~= said then
                said = state
                log.trace("egg is %s - waiting for it to settle", tostring(state))
            end
            task.wait(K.POLL)
        until os.clock() > deadline

        if state ~= "Slot" and state ~= "Dropped" then
            stats.failed = stats.failed + 1
            log.warn("drop_recovery=failed uid=%s (still %s after %.1fs)",
                tostring(uid), tostring(state), os.clock() - t0)
            return false, { reason = "never settled (" .. tostring(state) .. ")",
                            recovery = "failed" }
        end

        -- 4. Go and get it. INSTANT, not a cross-map tween.
        --
        -- instant.take teleports onto the egg, holds position against the
        -- server relocate and races CarryFieldEgg - the same path that already
        -- works for the outbound target. A tween back is what gets stuck in
        -- snapbacks, and it is slower into the bargain.
        for attempt = 1, K.TRIES do
            if cancel() then
                stats.cancelled = stats.cancelled + 1
                return false, { reason = "cancelled", recovery = "cancelled" }
            end

            -- RE-READ EVERY ATTEMPT. The guard is walking it back.
            local pNow, sNow = settledPos(uid)
            if sNow == "Claimed" then
                stats.banked = stats.banked + 1
                log.info("drop_recovery=banked uid=%s (claimed on the way)", tostring(uid))
                return false, { reason = "claimed", recovery = "banked" }
            end
            if not pNow then
                -- Same short replication grace during the chase.
                local graceUntil = os.clock() + dev.scale(0.80)
                repeat
                    if cancel() then
                        stats.cancelled = stats.cancelled + 1
                        return false, { reason = "cancelled", recovery = "cancelled" }
                    end
                    task.wait(K.POLL)
                    pNow, sNow = settledPos(uid)
                    if sNow == "Claimed" then
                        stats.banked = stats.banked + 1
                        log.info("drop_recovery=banked uid=%s (claimed during grace)", tostring(uid))
                        return false, { reason = "claimed", recovery = "banked" }
                    end
                until pNow or os.clock() >= graceUntil

                if not pNow then
                    stats.gone = stats.gone + 1
                    log.warn("drop_recovery=failed uid=%s (record gone on the way after grace)", tostring(uid))
                    return false, { reason = "gone", recovery = "failed" }
                end
            end

            local hrp = ch.root()
            local gapBefore = hrp and (pNow - hrp.Position).Magnitude or -1

            -- Server-visible re-approach. Instant Pick can be locally on top
            -- of the egg while the server still has the character at the old
            -- position. A short normal movement leg re-anchors the server before
            -- the Instant Pick race.
            if hrp and gapBefore > 12 then
                pcall(function()
                    move.travel{
                        to = pNow,
                        speed = 1100,
                        arrive = 2,
                        carrying = false,
                        cancel = cancel,
                        tag = "regrab server-visible approach",
                    }
                end)
                RunService.Heartbeat:Wait()
                local freshPos, freshState = settledPos(uid)
                if freshPos and (freshState == "Slot" or freshState == "Dropped") then
                    pNow, sNow = freshPos, freshState
                end
            end

            local got, info = instant.take(uid, pNow, {
                cancel = cancel,
                areaId = opts.areaId, nestId = opts.nestId,
            })

            if got then
                stats.recovered = stats.recovered + 1
                log.info("drop_recovery=tp uid=%s attempt %d/%d in %.2fs "
                    .. "(was %.0f studs out, %d calls)",
                    tostring(uid), attempt, K.TRIES, os.clock() - t0,
                    gapBefore, info and info.calls or -1)
                return true, { recovery = "tp", attempts = attempt,
                               ms = (os.clock() - t0) * 1000 }
            end

            -- THE TELEPORT ITSELF WAS REFUSED, which is a different failure
            -- from the egg being unavailable - and it is the one that used to
            -- disappear into a long tween.
            if info and info.pulledBack then
                log.warn("drop_recovery=tp_refused uid=%s attempt %d/%d "
                    .. "(landed %.0f studs off, reason=%s)",
                    tostring(uid), attempt, K.TRIES,
                    info.gap or -1, tostring(info.reason))
            else
                log.trace("attempt %d/%d: %s (egg %s, %.0f studs)",
                    attempt, K.TRIES, tostring(info and info.reason),
                    tostring(sNow), gapBefore)
            end

            -- A server "Get closer to the egg" refusal is not retried by
            -- hammering the same Instant Pick call. Re-anchor with ordinary
            -- movement first, then give the Instant Pick path one clean retry.
            if info and type(info.reason) == "string"
               and info.reason:lower():find("get closer to the egg", 1, true) then
                local latestPos = select(1, settledPos(uid))
                if latestPos then
                    pcall(function()
                        move.travel{
                            to = latestPos,
                            speed = 1100,
                            arrive = 1.5,
                            carrying = false,
                            cancel = cancel,
                            tag = "regrab closer retry",
                        }
                    end)
                    RunService.Heartbeat:Wait()
                end
            end

            -- Never round again without yielding.
            task.wait(dev.scale(K.POLL))
        end

        stats.failed = stats.failed + 1
        log.warn("drop_recovery=failed uid=%s after %d attempts in %.2fs",
            tostring(uid), K.TRIES, os.clock() - t0)
        return false, { reason = "no regrab", recovery = "failed" }
    end

    return M
end)

--[[ ==== features/carry.lua ========================================== ]]
-- =============================================================================
-- FEATURES.CARRY: get the egg to the safe zone and get it claimed
-- V65 SAFE-ZONE CLAIM/DOOR REPAIR
-- =============================================================================
--
--     local carry = BX.require("features.carry")
--     local ok, info = carry.home(uid, { cancel = fn })
--
-- THE DESTINATION IS THE SAFE ZONE, NOT THE PLOT.
--
-- V3.1 line 9487:  local DELIVER_POS = SAFE_POS
--                  local okD, dp, how = pcall(BX.safeZonePos)
--                  if okD and typeof(dp) == "Vector3" then DELIVER_POS = dp end
--
-- and BX.safeZonePos resolves, in this order:
--     1. workspace SpawnLocation      + 4 studs up
--     2. workspace SpawnTarget        + 4 studs up
--     3. the plot                     (fallback only)
--
-- An earlier version of this module carried to the plot centre, because
-- delivery eventually involves your own area. That is not where V3.1 goes and
-- it is not where the claim happens.
--
-- The hardcoded Vector3 that ends V3.1's ladder is still NOT ported - see
-- features/plot.lua for why (it was one account's coordinates, and everyone
-- else inherited them).
--
-- THE ROUTE IS ONE ARC, NOT A CLIMB AND A CROSSING.
--
-- V3.1 line 9590:
--     BX.arcTweenTo(DELIVER_POS, carrySpeed, "carry home", 5,
--         function() return heldEggUid == nil end)
--     if heldEggUid == nil then droppedMidTween = true
--     else BX.arcDescend("deliver") end
--
-- One call. The height is the arc mover's own K.ARC_CRUISE_UP - 18 studs above
-- the higher end - and nothing else. An earlier version here lifted 120 studs
-- straight up first and then crossed, which is a route V3.1 never flies.
--
-- THE CANCEL PREDICATE IS THE DROPPED-EGG HANDLING.
--
-- `heldEggUid == nil` is passed INTO the mover, so the moment the egg leaves
-- our hands the leg stops where it is. Without it we fly the remaining three
-- thousand studs empty-handed and only notice on arrival - which is what
-- "lost the egg in transit" looked like, several seconds after the fact.
--
-- WHY THE CARRY LEG IS NOT CLAMPED TO THE ANTICHEAT ALLOWANCE. V3.1 tried it
-- and reverted it: the carry runs unspoofed at ~499 while the allowance is
-- ~230, and Titan at 4293 studs is where the snap-back happens. But holding the
-- carry at 230 hands the guard the trip - chase speeds are base * 4, so
-- Prehistoric 608, Cosmic 800, Cherry Blossom 888, Titan 918. At 230 they all
-- catch you, everywhere.
--
-- ARRIVING IS NOT DELIVERING. The only authority is the server's FieldClaimed
-- signal. V3.1's logs are full of perfect arrivals that were never claimed.

BX.module("features.carry", function(BX)
    local svc  = BX.require("core.services")
    local move = BX.require("features.movement")
    local plot = BX.require("features.plot")
    local eggs = BX.require("features.eggs")
    local guard = BX.require("features.guard")
    local ch   = BX.require("core.character")
    local dev  = BX.require("core.device")
    local log  = BX.require("boot.log").for_module("carry")

    local M = {}

    local K = {
        SPEED      = 1050,  -- default Delivery speed; configurable up to 3000
        ARRIVE     = 5,      -- keep the proven arrival tolerance
        CLAIM_WAIT = 0.5,    -- primary claim confirmation window (GUI adjustable)
        CLAIM_RETRY_WAIT = 0.5, -- retry claim window after a re-descent (GUI adjustable)
        CLAIM_SETTLE = 0.0,    -- descend -> wait claim window
        -- Independent Delivery Egg -> Safe Zone speeds.
        DELIVERY_SPEEDS = {
            GLIDE         = 1050,
            FLY           = 1050,
            WALK          = 1050,
            RIDE_GUARD    = 1050,
            BETA_REVERSE  = 1000, -- stable experimental reverse-route delivery
        },
    }
    M.K = K

    local function deliverySpeed(opts)
        opts = opts or {}
        local method = tostring(opts.method or "GLIDE"):upper()
        local explicit = tonumber(opts.deliverySpeed)
        local maxSpeed = 3000
        if explicit then
            return math.clamp(explicit, 40, maxSpeed), method
        end
        return math.clamp(tonumber(K.DELIVERY_SPEEDS[method]) or K.SPEED, 40, maxSpeed), method
    end

    function M.deliverySpeed(method)
        return tonumber(K.DELIVERY_SPEEDS[tostring(method or "GLIDE"):upper()]) or K.SPEED
    end

    function M.setDeliverySpeed(method, speed)
        method = tostring(method or "GLIDE"):upper()
        if K.DELIVERY_SPEEDS[method] == nil then return false, "Unknown delivery method: " .. method end
        speed = tonumber(speed)
        if not speed then return false, "Speed must be numeric" end
        local maxSpeed = 3000
        K.DELIVERY_SPEEDS[method] = math.clamp(speed, 40, maxSpeed)
        return true, K.DELIVERY_SPEEDS[method]
    end

    local stats = { runs = 0, delivered = 0, failed = 0, cancelled = 0, lost = 0 }
    function M.stats() return table.clone(stats) end

    -- Cheap, and the reason a lost egg is noticed at a stage boundary rather
    -- than after a four-thousand-stud flight.
    local function holding(uid)
        local r = eggs.get(uid)
        if not r then return false, "gone" end
        return r.state == "Carried", r.state
    end

    function M.home(uid, opts)
        opts = opts or {}
        local outerCancel = opts.cancel
        stats.runs = stats.runs + 1

        local t0 = os.clock()
        local stages = {}
        local function stage(name, fn)
            local s0 = os.clock()
            local ok, info = fn()
            stages[#stages + 1] = {
                name = name, ms = (os.clock() - s0) * 1000, ok = ok and true or false,
            }
            return ok, info
        end

        local function report()
            local parts = {}
            for _, s in ipairs(stages) do
                parts[#parts + 1] = ("%s=%.0fms%s"):format(s.name, s.ms, s.ok and "" or "!")
            end
            return table.concat(parts, " ")
        end

        local function fail(why)
            stats.failed = stats.failed + 1
            log.warn("FAILED %s uid=%s after %.2fs [%s] tier=%s",
                why, tostring(uid), os.clock() - t0, report(), dev.tier)
            return false, { reason = why, stages = stages, elapsed = os.clock() - t0 }
        end

        local rideSession = nil
        local rideApi = nil

        -- RIDE_GUARD delivery is intentionally an additive transport mode:
        -- the existing Ride Guard mount is enabled for the carry leg, while
        -- the same proven carry mover handles the actual route and server
        -- delivery/claim. No hidden anti-cheat state is touched.
        if tostring(opts.method or ""):upper() == "RIDE_GUARD" then
            -- ONLY FOR AUTO GRAB EGG BY RARITY + RIDE GUARD:
            -- resolve the guard from the egg's CURRENT authoritative AreaId.
            -- The cached rarity record can be older than the server's carry
            -- record after a regrab, so always prefer the live egg here.
            local dynamicGuardArea = nil
            do
                local liveEgg = eggs.get(uid)
                dynamicGuardArea = liveEgg and liveEgg.areaId or opts.areaId
            end

            local env = _G
            if type(getgenv) == "function" then
                local ok, e = pcall(getgenv)
                if ok and type(e) == "table" then env = e end
            end
            rideApi = env.__DELL_RIDE_GUARD_API
            if not rideApi or type(rideApi.beginDelivery) ~= "function" then
                return fail("Ride Guard delivery is not ready")
            end

            local okRide, sessionOrWhy = rideApi.beginDelivery(dynamicGuardArea, {
                onlyForRarity = true,
                eggUid = uid,
            })
            if not okRide then
                return fail("Ride Guard: " .. tostring(sessionOrWhy))
            end
            rideSession = sessionOrWhy
            log.info("Ride Guard delivery mounted: %s (egg area=%s)",
                tostring(rideSession and rideSession.guard or "-"),
                tostring(dynamicGuardArea or "?"))
        end

        local function finishRideGuard()
            if rideApi and rideSession and type(rideApi.endDelivery) == "function" then
                pcall(function() rideApi.endDelivery(rideSession) end)
                rideSession = nil
                -- Let the RenderStepped cleanup finish before Auto Steal starts
                -- its next pickup. Without this one-frame handoff, the next
                -- instant pickup can race the old Ride Guard saddle/connection
                -- and appear to be stuck at the egg.
                pcall(function()
                    if svc and svc.RunService then
                        svc.RunService.Heartbeat:Wait()
                    else
                        task.wait()
                    end
                end)
            end
        end

        -- Terminal delivery modes:
        --   normal            -> Safe Zone claim
        --   Auto Return Base  -> Safe Zone -> Base -> AskPlaceEgg
        --   Help Friends      -> Forest -> intentional DropFieldEgg
        -- Help Friends is intentionally a terminal DROP, not a claim.
        local returnToBase = opts.returnToBase == true
        local helpFriends = opts.helpFriends == true
        local dest, via
        if helpFriends then
            dest, via = plot.forestZone()
            if not dest then
                finishRideGuard()
                return fail("no Forest destination resolved for Help Friends")
            end
            log.info("Help Friends: route=egg -> Forest -> DropFieldEgg")
        else
            -- Safe Zone remains the default destination. Auto Return To Base
            -- adds a second transport leg from Safe Zone to the player's base.
            dest, via = plot.safeZone()
            if not dest then
                finishRideGuard()
                return fail("no safe zone resolved")
            end
            if returnToBase then
                log.info("Auto Return To Base: route=egg -> safe zone -> base -> AskPlaceEgg")
            end
        end

        if not ch.root() then
            finishRideGuard()
            return fail("no character")
        end

        -- THE CANCEL THE MOVER ACTUALLY GETS.
        --
        -- Two reasons to stop: the caller asked, or the egg is no longer ours.
        -- The second is V3.1's `function() return heldEggUid == nil end`, and it
        -- is checked against the game rather than a local flag so a server-side
        -- drop is seen the same frame.
        --
        -- The egg check is rate-limited: this predicate is polled every frame
        -- by the mover, and eggs.get is a module call per invocation. Four
        -- times a second is fast enough to stop a leg and cheap enough not to
        -- matter.
        local lastCheck, lastHeld = 0, true
        local function carryCancel()
            if outerCancel and outerCancel() then return true end
            local now = os.clock()
            -- Always Carry mode watches more frequently so a transient state
            -- change is detected quickly; the mover still yields every frame.
            local poll = (opts.alwaysCarry and 0.08) or (opts.fastMode and 0.10 or 0.25)
            if (now - lastCheck) >= poll then
                lastCheck = now
                lastHeld = holding(uid)
            end
            return not lastHeld
        end

        local before = ch.root().Position
        local distance = (Vector3.new(dest.X, 0, dest.Z)
            - Vector3.new(before.X, 0, before.Z)).Magnitude
        local carrySpeed, deliveryMethod = deliverySpeed(opts)
        -- Mobile/Delta can lose wall time to rendering hitches. The old fixed
        -- 850 cap made long carries visibly slow on phones. Keep the proven
        -- server-safe movement logic, but use an adaptive mobile carry target
        -- when Mobile Fast Carry is enabled; the movement module still applies
        -- its relocation clamp when the server reports one.
        local mobileFast = opts.mobileFastCarry == true
        -- MOBILE STABILITY PROFILE. Keep the desktop profile untouched. On
        -- phones, a slightly lower cruise speed with smaller PivotTo steps is
        -- materially more reliable than trying to compensate for FPS with huge
        -- per-frame jumps.
        local transportCap = mobileFast and 1100 or 850
        -- V58 MOBILE ULTRA CARRY: the old 24-stud cap was still the real
        -- bottleneck. At 20 FPS that cap alone limits a 1500 studs/s target to
        -- about 480 studs/s. Use an adaptive target + step derived from the
        -- actual render/heartbeat rate. This keeps the mover frame-yielded and
        -- does not use a CFrame lock or a position correction loop.
        if dev.isTouch and mobileFast then
            local f = math.max(tonumber(dev.fps) or 30, 8)
            if f < 15 then
                transportCap = 800
            elseif f < 22 then
                transportCap = 950
            else
                transportCap = 1100
            end
        end
        local transportSpeed = math.min(carrySpeed, transportCap)
        local mobileStep = 7
        local mobileFrame = 0.075
        local mobileDebt = 0.12
        if dev.isTouch and mobileFast then
            local f = math.max(tonumber(dev.fps) or 30, 8)
            -- Enough displacement per Heartbeat to keep the requested cruise
            -- speed even on 15-30 FPS devices, while keeping one write bounded.
            mobileStep = math.clamp((transportSpeed / f) * 0.92, 24, 48)
            mobileFrame = 0.14
            mobileDebt = 0.28
        end

        log.info("carrying %s to %s via %s at %.0f studs/s (%.0f studs, tier=%s)",
            tostring(uid), helpFriends and "Forest" or (returnToBase and "base" or "safe zone"), tostring(deliveryMethod),
            transportSpeed, distance, dev.tier)
        if dev.isTouch then
            log.info("MOBILE CARRY PROFILE fps=%.1f cap=%.0f step=%.0f frame=%.2f debt=%.2f",
                tonumber(dev.fps) or -1, transportSpeed, mobileStep, mobileFrame, mobileDebt)
        end

        -- HELP FRIENDS: same user-selected transport method, but the terminal
        -- point is Forest. Stop there and intentionally release the egg so a
        -- friend can take it. No Safe Zone claim and no AskPlaceEgg.
        if helpFriends then
            local forestArrived, forestInfo = stage("arc_forest", function()
                return move.travel{
                    to = dest, speed = transportSpeed, arrive = K.ARRIVE,
                    carrying = true, cancel = carryCancel,
                    maxStep = mobileFast and mobileStep or 7, maxFrame = mobileFast and mobileFrame or 0.075, maxDebt = mobileFast and mobileDebt or 0.12, mobileFast = mobileFast,
                    tag = "help friends Forest " .. deliveryMethod,
                }
            end)

            local stillHeld, forestState = holding(uid)
            if not stillHeld then
                finishRideGuard()
                return fail("egg lost before Forest drop (" .. tostring(forestState) .. ")")
            end
            if not forestArrived then
                finishRideGuard()
                return fail("could not reach Forest (" .. tostring(forestInfo and forestInfo.reason) .. ")")
            end

            -- Pause briefly at the Forest destination so the final position is
            -- stable before the intentional drop.
            pcall(function() task.wait(0.20) end)

            local dropFn = nil
            local guardAllow = nil
            pcall(function()
                local eggState = BX.require("core.data").eggState()
                if eggState and type(eggState.DropFieldEgg) == "function" then
                    dropFn = eggState.DropFieldEgg
                end
            end)
            pcall(function()
                if guard and type(guard.allowDrops) == "function" then
                    guardAllow = guard.allowDrops
                    guardAllow(true)
                end
            end)

            local dropOk, dropResult = false, nil
            if dropFn then
                dropOk, dropResult = pcall(function()
                    return dropFn("HelpFriends")
                end)
            end

            pcall(function()
                if guardAllow then guardAllow(false) end
            end)

            if not dropFn then
                finishRideGuard()
                return fail("DropFieldEgg unavailable for Help Friends")
            end
            if not dropOk then
                finishRideGuard()
                return fail("Forest DropFieldEgg failed: " .. tostring(dropResult))
            end

            local dropped = false
            local dropUntil = os.clock() + 1.25
            while os.clock() < dropUntil do
                local state = nil
                pcall(function()
                    local rec = eggs.get(uid)
                    state = rec and rec.state
                end)
                if state == "Dropped" or state == "Slot" or state == "Claimed" or state == nil then
                    dropped = true
                    break
                end
                task.wait(0.10)
            end

            finishRideGuard()
            if not dropped then
                return fail("Forest drop not confirmed; egg still carried")
            end

            stats.delivered = stats.delivered + 1
            log.info("HELP FRIENDS DROP uid=%s at Forest via %s in %.2fs [%s] tier=%s",
                tostring(uid), tostring(via), os.clock() - t0, report(), dev.tier)
            return true, {
                reason = "dropped in Forest for Help Friends", stages = stages,
                elapsed = os.clock() - t0, destination = "forest",
                helpFriends = true, via = via,
            }
        end

        -- IMPORTANT DELIVERY CONTRACT:
        -- The user-selected transport method is NEVER replaced by a teleport
        -- when Auto Return To Base is enabled. The selected method (GLIDE / FLY
        -- / WALK / RIDE GUARD) performs the normal egg -> Safe Zone leg first.
        -- If Auto Return To Base is ON, the SAME method then performs a second
        -- Safe Zone -> Base leg, and only after reaching the base do we call
        -- AskPlaceEgg. This preserves the proven delivery movement and changes
        -- only the final destination/placement behavior.
        local safePos, safeVia = plot.safeZone()
        if not safePos then
            finishRideGuard()
            return fail("no safe zone resolved")
        end

        -- LEG 1: always deliver the carried egg to Safe Zone using the user's
        -- selected method. This is identical whether Auto Return To Base is ON
        -- or OFF.
        local arrived, moveInfo = stage("arc_safezone", function()
            return move.travel{
                to = safePos, speed = transportSpeed, arrive = K.ARRIVE,
                carrying = true, cancel = carryCancel,
                maxStep = mobileFast and mobileStep or 7, maxFrame = mobileFast and mobileFrame or 0.075, maxDebt = mobileFast and mobileDebt or 0.12, mobileFast = mobileFast,
                keepY = true,
                tag = "carry safe zone " .. deliveryMethod,
            }
        end)

        if arrived and returnToBase then
            -- LEG 2: Auto Return To Base uses THE SAME selected transport
            -- method. No CFrame/PivotTo teleport and no special replacement
            -- movement. Safe Zone remains the intermediate stop.
            local basePos, baseVia = plot.home()
            if not basePos then
                finishRideGuard()
                return fail("no base resolved for Auto Return To Base")
            end

            local baseArrived, baseInfo = stage("return_base", function()
                return move.travel{
                    to = basePos, speed = transportSpeed, arrive = K.ARRIVE,
                    carrying = true, cancel = carryCancel,
                    maxStep = mobileFast and mobileStep or 7, maxFrame = mobileFast and mobileFrame or 0.075, maxDebt = mobileFast and mobileDebt or 0.12, mobileFast = mobileFast,
                    tag = "carry base " .. deliveryMethod,
                }
            end)
            if not baseArrived then
                arrived, moveInfo = false, baseInfo
            else
                arrived, moveInfo = true, {
                    reason = "safe zone -> base reached",
                    safeZone = safeVia,
                    base = baseVia,
                }
            end
        end

        -- Dropped mid-route: the mover stopped where it was, which is the point.
        local stillOurs, state = holding(uid)
        if not stillOurs then
            stats.lost = stats.lost + 1
            local gone = ch.root()
            local travelled = gone and (gone.Position - before).Magnitude or -1
            -- Where it happened, not just that it did.
            log.warn("carry ended mid-route: egg is %s after %.0f/%.0f studs (%.2fs)",
                tostring(state), travelled, distance, os.clock() - t0)
            finishRideGuard()
            return false, {
                reason = "dropped in transit (" .. tostring(state) .. ")",
                stages = stages, droppedAt = travelled, distance = distance,
                recoverable = true,
            }
        end

        if outerCancel and outerCancel() then
            stats.cancelled = stats.cancelled + 1
            finishRideGuard()
            return false, { reason = "cancelled", stages = stages }
        end
        if not arrived then
            finishRideGuard()
            return fail("could not reach the " .. (returnToBase and "base" or "safe zone") .. " ("
                .. tostring(moveInfo and moveInfo.reason) .. ")")
        end

        -- Then down, exactly as the proven delivery path does after the arc.
        -- Re-read the authoritative egg record first; a stale local frame must
        -- not make us descend with an egg the server has already released.
        local heldBeforeDescend = holding(uid)
        if not heldBeforeDescend then
            finishRideGuard()
            return fail("lost before descend")
        end
        pcall(function() svc.RunService.Heartbeat:Wait() end)
        local heldAfterSettle = holding(uid)
        if not heldAfterSettle then
            finishRideGuard()
            return fail("lost during delivery settle")
        end

        if not returnToBase then
            -- V65 SAFE-ZONE DOOR REPAIR:
            -- Probe the arrival position before lowering to ground. Some server
            -- builds claim inside the Safe Zone/door volume; the old order could
            -- lower the character first and the egg then returned to Slot before
            -- the claim watcher observed FieldClaimed.
            local preClaimed = false
            local preClaimFrom = os.clock() - 0.20
            local preClaimUntil = os.clock() + (dev.isTouch and 0.35 or 0.20)
            local lastPreState = 0
            while os.clock() <= preClaimUntil do
                if outerCancel and outerCancel() then
                    finishRideGuard()
                    return false, { reason = "cancelled" }
                end

                local got = plot.claimedSince(preClaimFrom, uid)
                if got then
                    preClaimed = true
                    break
                end

                local now = os.clock()
                if now - lastPreState >= 0.05 then
                    lastPreState = now
                    local rec = eggs.get(uid)
                    if rec and rec.state == "Claimed" then
                        preClaimed = true
                        break
                    end
                    if not rec or rec.state ~= "Carried" then
                        finishRideGuard()
                        return fail("lost at safe-zone door before claim ("
                            .. tostring(rec and rec.state or "gone") .. ")")
                    end
                end
                svc.RunService.Heartbeat:Wait()
            end

            if preClaimed then
                finishRideGuard()
                stats.delivered = stats.delivered + 1
                log.info("DELIVERED uid=%s via Safe Zone pre-descend claim in %.2fs [%s] tier=%s",
                    tostring(uid), os.clock() - t0, report(), dev.tier)
                return true, {
                    reason = "delivered", stages = stages, elapsed = os.clock() - t0,
                    claimPhase = "pre-descend",
                }
            end

            stage("descend", function()
                return move.descend("deliver"), nil
            end)
        end

        -- ARRIVING IS NOT DELIVERING.
        -- Keep the requested short primary/retry windows, but do NOT change
        -- the carry/recovery engine around them. The previous V9 recovery
        -- timing change was unrelated to the carry leg and could make a
        -- failed delivery re-enter too quickly.
        pcall(function() task.wait(dev.scale(K.CLAIM_SETTLE)) end)

        if returnToBase then
            -- The base route does not wait for Safe Zone/FieldClaimed. The egg
            -- is explicitly placed by the game's EggWorld endpoint instead.
            local rs = svc.ReplicatedStorage
            local pkgs = rs and rs:FindFirstChild("Packages")
            local networking = pkgs and pkgs:FindFirstChild("Networking")
            local askPlaceEgg = networking and networking:FindFirstChild("RF/EggWorld/AskPlaceEgg")
            if not askPlaceEgg then
                finishRideGuard()
                return fail("AskPlaceEgg remote not found")
            end

            local placeOk, placeResult = pcall(function()
                return askPlaceEgg:InvokeServer({
                    LocalCFrame = CFrame.new(0, 0, 0),
                    Uid = uid,
                })
            end)
            task.wait(0.3)

            if not placeOk then
                finishRideGuard()
                return fail("AskPlaceEgg invoke failed: " .. tostring(placeResult))
            end
            if placeResult == false then
                finishRideGuard()
                return fail("AskPlaceEgg refused placement")
            end

            -- The official endpoint can return nil/table on success depending
            -- on the current game build. Only an explicit false is rejection.
            -- Give EggState one short replication window to confirm that the
            -- carried record is no longer Carried before completing the cycle.
            local placedConfirmed = false
            local confirmUntil = os.clock() + 1.25
            while os.clock() < confirmUntil do
                local state = nil
                pcall(function()
                    local rec = eggs.get(uid)
                    state = rec and rec.state
                end)
                if state ~= "Carried" then
                    placedConfirmed = true
                    break
                end
                task.wait(0.10)
            end
            if not placedConfirmed then
                finishRideGuard()
                return fail("AskPlaceEgg returned without placement confirmation")
            end

            finishRideGuard()
            stats.delivered = stats.delivered + 1
            log.info("PLACED AT BASE uid=%s via %s in %.2fs [%s] tier=%s",
                tostring(uid), tostring(via), os.clock() - t0, report(), dev.tier)
            return true, {
                reason = "placed at base", stages = stages, elapsed = os.clock() - t0,
                returnToBase = true, destination = "base", safeZone = via,
            }
        end

        local function waitForClaim(window, label)
            local claimFrom = os.clock() - 0.20
            local windowSeconds = dev.scale(window)
            if dev.isTouch then windowSeconds = math.max(windowSeconds, 0.75) end
            local until_ = os.clock() + windowSeconds
            local lastStateCheck = 0
            while os.clock() <= until_ do
                if outerCancel and outerCancel() then
                    return false, "cancelled"
                end
                local got = plot.claimedSince(claimFrom, uid)
                if got then
                    log.info("claim confirmed uid=%s via FieldClaimed (%s)", tostring(uid), tostring(label))
                    return true, "field-claimed"
                end
                local now = os.clock()
                if now - lastStateCheck >= 0.10 then
                    lastStateCheck = now
                    local rec = eggs.get(uid)
                    if rec and rec.state == "Claimed" then
                        log.info("claim confirmed uid=%s via EggState (%s)", tostring(uid), tostring(label))
                        return true, "egg-state-claimed"
                    end
                end
                svc.RunService.Heartbeat:Wait()
            end
            return false, "no claim"
        end

        local claimed = stage("claim", function()
            return waitForClaim(K.CLAIM_WAIT, "primary")
        end)

        if not claimed then
            local have = holding(uid)
            if have and not (outerCancel and outerCancel()) then
                claimed = stage("claim_retry", function()
                    pcall(function() move.descend("deliver-claim-retry") end)
                    return waitForClaim(K.CLAIM_RETRY_WAIT, "retry")
                end)
            end
        end

        if not claimed then
            -- Distinguish the two: an egg still in hand that was never claimed
            -- is a different problem from one taken off us at the door.
            local have, st = holding(uid)
            finishRideGuard()
            return fail(have and "arrived but never claimed"
                or ("lost at the door (" .. tostring(st) .. ")"))
        end

        finishRideGuard()
        stats.delivered = stats.delivered + 1
        log.info("DELIVERED uid=%s in %.2fs via %s [%s] tier=%s",
            tostring(uid), os.clock() - t0, tostring(via), report(), dev.tier)
        return true, { reason = "delivered", stages = stages, elapsed = os.clock() - t0 }
    end

    return M
end)

--[[ ==== features/bait.lua =========================================== ]]
-- =============================================================================
-- FEATURES.BAIT: the Forest prime - pick one up, let the guard take it
-- =============================================================================
--
--     local bait = BX.require("features.bait")
--     local ok, info = bait.prime({ cancel = fn })
--
-- WHY THIS STAGE EXISTS AT ALL.
--
-- Dropping an egg by hand is not the same event as losing one to a guard, and
-- that difference is what decides whether the REAL steal delivers. The prime
-- takes a throwaway egg in the first area, stands in that guard's reach, and
-- lets the hit land - which puts the guard/knockdown sequence into the state
-- the real steal needs.
--
-- THE FIRST AREA, DELIBERATELY. From the game's own guard directory:
--     Forest  WalkSpeed 16  HitDistance 2.5  FlatRadius 20
-- It is the slowest guard in the game and it sits next to the safe zone, so
-- taking a hit here costs nothing. Taking one at Titan Temple (WalkSpeed 229.5,
-- HitDistance 7) is what loses the real egg.
--
-- The area is resolved from the map - leftmost guard area by bounds - so a
-- renamed or reordered area cannot break it.

BX.module("features.bait", function(BX)
    local svc  = BX.require("core.services")
    local data = BX.require("core.data")
    local move = BX.require("features.movement")
    local ch   = BX.require("core.character")
    local dev  = BX.require("core.device")
    local log  = BX.require("boot.log").for_module("bait")

    local RunService = svc.RunService
    local M = {}

    local K = {
        AREA_WAIT    = 5,     -- how long to wait for GuardAreas to stream in
        APPROACH     = 1800,  -- requested approach speed to the bait egg
        ARRIVE       = 4,
        PICKUP_WAIT  = 3,     -- how long to keep asking for the carry
        REHOPS       = 2,     -- server pull-backs we will answer before giving up
        HIT_WAIT     = 4.0,   -- how long to stand in reach waiting for the hit
        WITNESS_HOLD = 0.35,  -- stay anchored this long after a witness fires
    }
    M.K = K

    -- THROUGH core.data. A private FindFirstChild + require here bypassed
    -- the one place that knows whether this executor can require game
    -- modules at all, and cached a miss forever. core.data probes once,
    -- lets a miss expire, and backs off - see core/data.lua.
    local EggState, SlotIdentity = data.eggState(), data.slotIdentity()

    ---------- the first area ----------

    local areaCached = nil
    local guardAreasCached = nil

    -- Resolve GuardAreas without assuming the private Workspace.__OBJECTS tree.
    -- The previous build indexed workspace.__OBJECTS directly; when that
    -- container is absent (or not streamed yet), Luau throws before BX.try can
    -- recover. This resolver only uses safe FindFirstChild/GetDescendants and
    -- accepts the game's current public/streamed hierarchy.
    local function resolveGuardAreas(waitFor)
        if guardAreasCached and guardAreasCached.Parent then
            return guardAreasCached
        end

        local deadline = os.clock() + (tonumber(waitFor) or 0)
        repeat
            local found = nil
            pcall(function()
                -- Fast path: recursive lookup works whether GuardAreas is
                -- directly under Workspace or nested several folders deep.
                found = workspace:FindFirstChild("GuardAreas", true)
            end)

            if not found then
                pcall(function()
                    for _, d in ipairs(workspace:GetDescendants()) do
                        if d.Name == "GuardAreas" and (d:IsA("Folder") or d:IsA("Model")) then
                            found = d
                            break
                        end
                    end
                end)
            end

            if found then
                guardAreasCached = found
                return found
            end

            if os.clock() >= deadline then break end
            task.wait(0.2)
        until false

        return nil
    end

    -- WHY THE FOREST STEP WAS SKIPPED ON A FRESH JOIN.
    --
    -- The old implementation hard-indexed Workspace.__OBJECTS.Areas.GuardAreas.
    -- That hierarchy is not guaranteed to exist in every streamed session.
    -- Resolve the actual GuardAreas container first, then choose the leftmost
    -- area with a Bounds part. The returned area name is still the same logical
    -- AreaId used by the existing bait/guard code.
    function M.firstAreaId(waitFor)
        if areaCached then return areaCached end

        local areas = resolveGuardAreas(waitFor or 0)
        if not areas then
            log.warn("guard areas have not streamed in - no bait area")
            return nil
        end

        local best, bestX
        BX.try("bait.resolveArea", function()
            for _, a in ipairs(areas:GetChildren()) do
                local b = a:FindFirstChild("Bounds")
                if b and b:IsA("BasePart") then
                    local x = b.Position.X - b.Size.X * 0.5
                    if not best or x < bestX then
                        best, bestX = a.Name, x
                    end
                end
            end
        end)
        if best then
            areaCached = best
            log.info("first area resolved: %s (leftmost at x=%.0f)", best, bestX)
        else
            log.warn("GuardAreas found but no streamed area Bounds yet")
        end
        return areaCached
    end

    -- Enter the gameplay area WITHOUT stealing the bait egg. CarryFieldEgg is
    -- server-gated until the character has entered a gameplay area.
    function M.enterFirstArea(opts)
        opts = opts or {}
        local cancel = opts.cancel or function() return false end
        local areas = resolveGuardAreas(opts.waitFor or K.AREA_WAIT)
        local areaId = M.firstAreaId(0)
        if not areas or not areaId then
            return false, { reason = "no gameplay area" }
        end

        local bounds
        BX.try("bait.firstAreaBounds", function()
            local a = areas:FindFirstChild(areaId)
            local b = a and a:FindFirstChild("Bounds")
            if b and b:IsA("BasePart") then bounds = b end
        end)
        if not bounds then
            return false, { reason = "gameplay area bounds unavailable" }
        end

        local pos = bounds.Position + Vector3.new(0, 3, 0)
        local ok, travelResult = pcall(function()
            return move.travel{
                to = pos, speed = opts.speed or K.APPROACH, arrive = opts.arrive or K.ARRIVE,
                carrying = false, cancel = cancel, tag = "enter gameplay area",
            }
        end)
        if cancel() then return false, { reason = "cancelled" } end
        if not ok then
            return false, { reason = "gameplay area travel failed", detail = tostring(travelResult) }
        end
        RunService.Heartbeat:Wait()
        return true, { areaId = areaId, pos = pos }
    end

    local function findGuard(areaId)
        if not areaId then return nil end
        local live = workspace:FindFirstChild("_Guards")
        if live then
            for _, g in ipairs(live:GetChildren()) do
                if g.Name == areaId or g:GetAttribute("AreaId") == areaId then return g end
            end
        end

        local areas = resolveGuardAreas(0)
        local a
        if areas then
            pcall(function() a = areas:FindFirstChild(areaId) end)
        end
        return a and a:FindFirstChild("Guard") or nil
    end

    local function guardPart(guard)
        if not guard then return nil end
        local root = guard:FindFirstChild("HumanoidRootPart")
            or guard:FindFirstChild("Collider")
            or guard:FindFirstChild("Head")
        if root and root:IsA("BasePart") then return root end
        local best
        for _, d in ipairs(guard:GetDescendants()) do
            if d:IsA("BasePart") then
                local v = d.Size.X * d.Size.Y * d.Size.Z
                if not best or v > best.v then best = { p = d, v = v } end
            end
        end
        return best and best.p or nil
    end

    ---------- the prime ----------

    local stats = { runs = 0, hits = 0, noEgg = 0, noPickup = 0, noHit = 0, cancelled = 0 }
    function M.stats() return table.clone(stats) end

    function M.prime(opts)
        opts = opts or {}
        local cancel = opts.cancel
        stats.runs = stats.runs + 1
        local t0 = os.clock()

        local areaId = M.firstAreaId(K.AREA_WAIT)
        if not areaId then
            return false, { reason = "no bait area" }
        end
        -- Late arrival: re-ask core.data (cheap, rate-limited) rather than
        -- carry a nil for the session. No EggState = no bait egg = an
        -- unprimed cycle, which V3.1 also allows.
        if not EggState then EggState = data.eggState() SlotIdentity = SlotIdentity or data.slotIdentity() end
        if not EggState then
            stats.noEgg = stats.noEgg + 1
            return false, { reason = "no EggState on this executor" }
        end

        -- A Slot egg in the first area. Read straight from the field rather
        -- than through the cached list: this is one specific area and we want
        -- current truth, not a half-second-old ranking.
        local rec
        BX.try("bait.findEgg", function()
            for _, r in pairs(EggState.ReadFieldEggs().Records) do
                if r.AreaId == areaId and r.State == "Slot" and r.BoundsCFrame then
                    rec = r
                    break
                end
            end
        end)
        if not rec then
            stats.noEgg = stats.noEgg + 1
            log.trace("no egg available in %s", tostring(areaId))
            return false, { reason = "no bait egg" }
        end

        local pos = rec.BoundsCFrame.Position

        -- Same mover as every other leg. The pickup needs us inside the
        -- server's range or it answers "Get closer to the egg" - measured at
        -- 769 studs out, CarryFieldEgg with the correct slot key still refused
        -- for range alone.
        move.travel{ to = pos, speed = K.APPROACH, arrive = K.ARRIVE,
                     carrying = false, cancel = cancel, tag = "bait approach" }
        if cancel and cancel() then
            stats.cancelled = stats.cancelled + 1
            return false, { reason = "cancelled" }
        end

        -- First-area eggs need a FirstAreaSlotKey or the server refuses outright.
        local slotKey = nil
        BX.try("bait.slotKey", function()
            if SlotIdentity and SlotIdentity.LooksLikeFirstAreaUid
               and SlotIdentity.LooksLikeFirstAreaUid(rec.Uid) then
                slotKey = SlotIdentity.SlotKey(rec.AreaId, rec.NestId)
            end
        end)

        -- PULLED BACK MID-GRAB: GO STRAIGHT BACK.
        --
        -- The first hop of a cycle sometimes gets a server Relocate ~0.2s after
        -- it lands, putting us back at spawn. V3.1's loop then spent the whole
        -- timeout asking to pick up an egg 90 studs away, gave up, and the
        -- retry a second later worked - that is "the first steal never picks
        -- up, the second one does".
        local got = false
        local deadline = os.clock() + dev.scale(K.PICKUP_WAIT)
        local rehops, tries = 0, 0
        local startPos = ch.root() and ch.root().Position

        while os.clock() < deadline and not got do
            if cancel and cancel() then
                stats.cancelled = stats.cancelled + 1
                return false, { reason = "cancelled" }
            end
            local here = ch.root()
            if not here then return false, { reason = "no character" } end

            -- Detected by distance rather than by an anticheat hook, so it
            -- works with no adapter armed.
            if startPos and (here.Position - pos).Magnitude > 60 and rehops < K.REHOPS then
                rehops = rehops + 1
                log.trace("server pulled us back - hopping again (%d/%d)", rehops, K.REHOPS)
                move.travel{ to = pos, speed = K.APPROACH, arrive = K.ARRIVE,
                             carrying = false, cancel = cancel, tag = "bait rehop" }
                deadline = os.clock() + dev.scale(K.PICKUP_WAIT)
            end

            tries = tries + 1

            -- The Forest bait egg can move/replicate between the initial field
            -- read and CarryFieldEgg. Refresh its authoritative position and
            -- re-enter the server's pickup radius instead of hammering the old
            -- position for the whole pickup window.
            if tries == 1 or (tries % 8) == 0 then
                local okFresh, freshRows = pcall(EggState.ReadFieldEggs)
                if okFresh and type(freshRows) == "table" and type(freshRows.Records) == "table" then
                    for _, rr in pairs(freshRows.Records) do
                        if tostring(rr.Uid) == tostring(rec.Uid) and rr.BoundsCFrame then
                            rec = rr
                            pos = rr.BoundsCFrame.Position
                            break
                        end
                    end
                end
            end

            local here2 = ch.root()
            if here2 and (here2.Position - pos).Magnitude > 10 then
                move.travel{ to = pos, speed = K.APPROACH, arrive = K.ARRIVE,
                    carrying = false, cancel = cancel, tag = "bait reanchor" }
                RunService.Heartbeat:Wait()
            end

            local ok, res = pcall(function() return EggState.CarryFieldEgg(rec.Uid, slotKey) end)
            if ok and res == true then got = true break end
            RunService.Heartbeat:Wait()
        end

        if got then BX.profile.mark("bait_grab") end
        if not got then
            stats.noPickup = stats.noPickup + 1
            log.warn("could not pick up in %s after %d tries, %d rehops (%.2fs)",
                tostring(areaId), tries, rehops, os.clock() - t0)
            return false, { reason = "no pickup", tries = tries, rehops = rehops }
        end

        ---------- take the hit ----------

        BX.profile.mark("guard_contact")
        local guard = findGuard(areaId)
        local gpart = guardPart(guard)
        if gpart then
            -- It is asleep until the steal wakes it, and at WalkSpeed 16 it
            -- will not reach us in any useful time, so we go to it.
            local hh = ch.root()
            local char = ch.get()
            if hh and char then
                local gy = move.groundY(gpart.Position) or hh.Position.Y
                pcall(function()
                    char:PivotTo(CFrame.new(gpart.Position.X, gy, gpart.Position.Z))
                end)
            end
        else
            log.warn("no guard found in %s", tostring(areaId))
        end

        -- ANCHOR THROUGH THE HIT. NO FLING, NO GETTING UP.
        local hrp = ch.root()
        local anchorCF = hrp and hrp.CFrame
        if hrp then pcall(function() hrp.Anchored = true end) end

        local hitAt, witnessAt = nil, nil
        local dl = os.clock() + dev.scale(K.HIT_WAIT)

        while os.clock() < dl do
            if cancel and cancel() then break end
            local hh = ch.root()
            if not hh then break end

            hh.AssemblyLinearVelocity = Vector3.zero
            hh.AssemblyAngularVelocity = Vector3.zero
            if anchorCF then pcall(function() hh.CFrame = anchorCF end) end

            -- MORE THAN ONE WITNESS.
            --
            -- V3.1's first version read the hit only off the RigSync event. On
            -- executors where that never arrives (Delta reports), every prime
            -- read as "no hit", was retried, and the whole cycle was skipped -
            -- a new chicken egg every few seconds, a hundred times, never the
            -- target. These witnesses need nothing but the game's own state.
            local witnessed = false

            local hum = ch.humanoid()
            if hum and hum:GetState() == Enum.HumanoidStateType.Physics then
                witnessed = true   -- knocked down
            end
            if not witnessed then
                -- The egg's record went loose. NOT "Slot": ReadFieldEgg lags
                -- and still says Slot for a moment after a successful pickup,
                -- which would fake a hit and send the real steal out unprimed.
                local okR, r = pcall(EggState.ReadFieldEgg, rec.Uid)
                local st = okR and type(r) == "table" and r.State or nil
                witnessed = (st == "Dropped" or st == "GuardCarried")
            end

            -- A WITNESS IS AN EVENT. ONCE IT HAS FIRED, IT HAS FIRED.
            --
            -- The hold check used to sit INSIDE this `if witnessed then`, so it
            -- was only ever re-evaluated while the witness was STILL true. Every
            -- witness here is transient by nature - the Humanoid is in Physics
            -- for a moment, or the egg record reads Dropped/GuardCarried for a
            -- moment - and features/guard's own anti-ragdoll stands us back up
            -- within a frame or two, which is exactly what clears it. So the
            -- 0.35s hold was frequently never satisfied: witnessAt stayed set,
            -- hitAt stayed nil, the loop ran to the FULL HIT_WAIT and reported
            -- "no hit" having plainly seen one.
            --
            -- Measured on a live cycle before the fix, from the profile marks:
            --     guard_contact@0.25 ... unanchor@5.65     (no hit_detected)
            --     no hit in Forest after 5.65s (witness=yes)
            -- - the log line says witness=yes and no hit in the same breath, and
            -- HIT_WAIT is 4.0 scaled by the device, so that is 5.4s at mid tier
            -- and 8.8s at low tier of standing next to a guard that has already
            -- hit us.
            --
            -- The fix is not a shorter timeout. It is remembering the event: the
            -- stamp is taken the first time the witness is seen, and the hold is
            -- then counted on EVERY pass whether or not the witness is still
            -- true. Nothing else about the prime changes.
            if witnessed and not witnessAt then
                witnessAt = os.clock()
                log.info("witness seen @%.3f (+%.3fs into the prime)",
                    witnessAt, witnessAt - t0)
            end

            -- LET THE KNOCKDOWN LAND BEFORE LEAVING. These see the hit a
            -- few hundredths before the server's ragdoll arrives, and
            -- leaving on them sent the knockdown into the next teleport -
            -- measured: witness 7.50, TP 7.51, ragdoll 7.53, "landed 28
            -- studs from the egg", no pickup. That is what the hold is for,
            -- and it is why this is a hold rather than an immediate break.
            if witnessAt and (os.clock() - witnessAt) >= K.WITNESS_HOLD then
                BX.profile.mark("hit_detected")
                hitAt = os.clock()
                log.info("HIT CONFIRMED @%.3f (+%.3fs into the prime, hold=%.3fs)",
                    hitAt, hitAt - t0, hitAt - witnessAt)
                break
            end
            RunService.Heartbeat:Wait()
        end

        -- ALWAYS UNANCHOR, on every path out of the loop.
        do
            local hh = ch.root()
            if hh then pcall(function() hh.Anchored = false end) end
            BX.profile.mark("unanchor")
        end

        local took = hitAt ~= nil
        if took then stats.hits = stats.hits + 1 else stats.noHit = stats.noHit + 1 end

        log.info("%s in %s after %.2fs (tries=%d rehops=%d witness=%s tier=%s)",
            took and "HIT TAKEN" or "no hit", tostring(areaId), os.clock() - t0,
            tries, rehops, witnessAt and "yes" or "no", dev.tier)

        return took, {
            reason = took and "hit" or "no hit",
            areaId = areaId, tries = tries, rehops = rehops,
            elapsed = os.clock() - t0,
        }
    end

    return M
end)

--[[ ==== features/autosteal.lua ====================================== ]]
-- =============================================================================
-- FEATURES.AUTOSTEAL: the run lifecycle
-- =============================================================================
--
--     local auto = BX.require("features.autosteal")
--     auto.setEnabled(true)     -- start, or do nothing if already running
--     auto.setEnabled(false)    -- stop and clean up completely
--     auto.isRunning()
--
-- THIS FILE IS THE LIFECYCLE, NOT THE STEAL.
--
-- The V3.1 steal method is being ported onto this spine stage by stage. What
-- is here is the part that has to be right BEFORE any of that lands, because
-- every one of V3.1's worst Auto Steal symptoms is a lifecycle failure rather
-- than a mistake in the steal itself:
--
--   "it gets laggy after a while"      two runs, or two movers, both live
--   "the game freezes when I turn it on"  a pass that never yielded
--   "it stops working after I die"     state captured from a dead character
--   "memory climbs"                    loops and connections from old runs
--
-- ONE RUN. EVER.
--
-- Two independent guarantees, because one is not enough:
--
--   1. A run token. Every run takes the next number and every loop checks that
--      it still holds the current one. A stale run returns on its next pass
--      even if something else forgot to stop it.
--   2. A scope. BX.scope("features.autosteal") retires any previous scope of
--      the same name before returning a new one, so starting a second run
--      cannot leave the first one's connections, threads or Instances behind.
--
-- Turning it off, dying, re-executing and unloading the menu all end in the
-- same place: stop(), which destroys the scope. There is no other cleanup path
-- to forget.
--
-- FAILURE DOES NOT MEAN RETRY IMMEDIATELY.
--
-- A failed egg used to send the loop straight round again. When the failure
-- was persistent - an egg that could not be picked up, a delivery the server
-- would not accept - that became a hot loop hammering remotes and burning
-- frames. Consecutive failures now back off, and a success resets it.

BX.module("features.autosteal", function(BX)
    local svc   = BX.require("core.services")
    local dev   = BX.require("core.device")
    local ch    = BX.require("core.character")
    local st    = BX.require("core.state")
    local eggs  = BX.require("features.eggs")
    local grab  = BX.require("features.grab")
    local move  = BX.require("features.movement")
    local carry = BX.require("features.carry")
    local bait  = BX.require("features.bait")
    local plot  = BX.require("features.plot")
    local adeath = BX.require("features.antideath")
    local guard  = BX.require("features.guard")
    local rs     = BX.require("core.restore")
    local instant = BX.require("features.instant")
    local regrab = BX.require("features.regrab")
    local hswap  = BX.require("features.humanoid")
    local log   = BX.require("boot.log").for_module("autosteal")

    local M = {}

    -- Backoff after consecutive failures: 1s, 2s, 4s, 8s, capped. Scaled for
    -- the device, because a weak machine needs more room between attempts, not
    -- less. A success puts it straight back to zero.
    -- Faster recovery after transient delivery/claim failures.
    -- Keep a bounded backoff so persistent refusals do not become a hot loop.
    local BACKOFF_BASE = 0.25
    local BACKOFF_CAP  = 2.0

    -- Nothing to steal is NOT a failure. V3.1 switched Auto Steal off after
    -- eight idle cycles, which could not tell a broken loop apart from the
    -- ordinary case of everything matching your filter having just been taken.
    -- Idle waits, and keeps waiting.
    local IDLE_WAIT = 0.12

    -- THE STAGES A CYCLE MOVES THROUGH.
    --
    -- Named so a failure can invalidate only what actually needs repeating. A
    -- failed target grab used to send the whole run back to the Forest guard
    -- for a fresh bait, and V3.1 added an at-target retry specifically to stop
    -- that: its own trace shows a cycle thrown away for a pull-back, and the
    -- NEXT cycle - a fresh prime and a second guard hit later - taking the very
    -- same egg.
    M.STATE = {
        -- PREPARATION IS NOT COMPLETION.
        --
        -- A run that starts with an egg already in our hands has to get rid of
        -- it before it can steal anything - the server refuses every later
        -- pickup with "Already carrying an egg". That trip goes to the safe
        -- zone and it looks exactly like a delivery, which is precisely why it
        -- was being counted as one: enabling Auto Steal at the plot flew to the
        -- safe zone, dropped the egg we happened to be holding, reported
        -- DELIVERED and switched itself off before the SELECTED egg had been
        -- touched. The user then had to toggle it again to get a real steal.
        --
        -- So preparation has its own name and its own terminal flag.
        PREP_DELIVER_HELD = "PREP_DELIVER_HELD",
        READY_TO_STEAL    = "READY_TO_STEAL",
        BAIT_NOT_DONE     = "BAIT_NOT_DONE",
        BAIT_DONE         = "BAIT_DONE",
        AT_TARGET         = "AT_TARGET",
        TARGET_GRAB_RETRY = "TARGET_GRAB_RETRY",
        CARRYING          = "CARRYING",
        RETURNING         = "RETURNING",
        DELIVERED         = "DELIVERED",
    }

    -- THE RUN'S OWN TRAIL, not the cycle's.
    --
    -- One line per phase change for the whole run, so "it stopped at the safe
    -- zone" can be read back as a sequence rather than guessed at:
    --
    --     run 1: START -> PREP_DELIVER_HELD -> READY_TO_STEAL -> BAIT_DONE
    --            -> AT_TARGET -> CARRYING -> RETURNING -> DELIVERED -> STOP
    --
    -- Kept on the module so a test can assert the order.
    local phases = {}
    local phaseRun = 0

    local function phase(token, name, detail)
        if token ~= phaseRun then
            phases, phaseRun = {}, token
        end
        phases[#phases + 1] = name
        log.info("run %d: phase %s%s", token, name,
            detail and (" (" .. tostring(detail) .. ")") or "")
    end

    function M.phases() return table.clone(phases) end

    -- PICKUP RELIABILITY:
    -- A rarity worker can see a fresh egg disappear/move between the live scan
    -- and the server pickup check. Keep retries at the TARGET instead of
    -- restarting bait/guard, and re-anchor to the newest authoritative record.
    local TARGET_RETRIES = 4
    local TARGET_RETRY_GAP = 0.08

    -- Anyone who needs to know the run ended - the UI toggle, mainly. Fired on
    -- a fresh thread because a listener will want to write to an Instance, and
    -- the thread that ran the cycle has called into game code and is narrowed.
    local stopListeners = {}

    function M.onStop(fn)
        stopListeners[#stopListeners + 1] = fn
    end

    -- CONFIRMED DELIVERIES ONLY, and it cannot affect the run.
    --
    -- Fired where a cycle reaches DELIVERED - after the server has claimed the
    -- egg - with the egg record the cycle already holds, so a listener needs no
    -- second field read. Each listener runs on its OWN thread inside BX.try: a
    -- webhook that hangs, throws or gets rate-limited cannot delay or stop the
    -- steal loop, which is the whole point of not calling them inline.
    local deliveredListeners = {}

    function M.onDelivered(fn)
        deliveredListeners[#deliveredListeners + 1] = fn
    end

    local function fireDelivered(target)
        if not target then return end
        for _, fn in ipairs(deliveredListeners) do
            task.spawn(function() BX.try("autosteal.onDelivered", fn, target) end)
        end
    end

    local runToken = 0
    local running  = false
    local cycles   = 0
    local sc       = nil
    local failures = 0

    -- CONTINUOUS ALL HUB NOTIFIER
    --
    -- This is deliberately independent from the steal/delivery loop.
    -- Previously the rarity picker scanned only when it was asked for a target,
    -- so during bait/grab/carry/delivery the egg list could become stale.
    -- The scanner below keeps a fresh field snapshot in the background for the
    -- entire rarity run, including while the character is moving or carrying.
    local liveEggScan = {
        list = {},
        at = 0,
        seq = 0,
        errors = 0,
    }

    local LIVE_SCAN_INTERVAL = 0.05 -- ~20 realtime field scans/sec

    function M.liveEggSnapshot()
        return liveEggScan.list, liveEggScan.at, liveEggScan.seq
    end

    -- ================================================================
    -- NIGHT-ONLY GATE FOR AUTO STEAL BY RARITY
    --
    -- The supplied NightEggTimeSkipAnimation source shows that the game's
    -- authoritative egg cycle is based on AreaEggCycle + server time:
    --   _nightStartsAt, _dayStartsAt, AreaEggCycle.PeriodIndexAt(...)
    --   and Workspace:GetServerTimeNow().
    --
    -- Manual Auto Steal remains 24/7. Automatic farm modes (`farm`, `rarity`,
    -- and the Beta/Combo hand-off) wait at the next cycle boundary during Day.
    -- A run already carrying an egg is never cancelled just because Day begins;
    -- it is allowed to finish, then the next cycle waits for Night.
    -- ================================================================
    local nightCycle = {
        module = nil,
        loaded = false,
        lastState = nil,
        lastSource = nil,
    }

    local function loadAreaEggCycle()
        if nightCycle.loaded then return nightCycle.module end
        nightCycle.loaded = true
        local ok, mod = pcall(function()
            return require(game:GetService("ReplicatedStorage").Shared.Util.AreaEggCycle)
        end)
        if ok and type(mod) == "table" then
            nightCycle.module = mod
        end
        return nightCycle.module
    end

    local function boolFromTable(t)
        if type(t) ~= "table" then return nil end
        for _, key in ipairs({
            "IsNight", "isNight", "Night", "night",
            "IsNightTime", "isNightTime", "NightTime", "nightTime"
        }) do
            if type(t[key]) == "boolean" then return t[key] end
        end
        for _, key in ipairs({
            "IsDay", "isDay", "Day", "day",
            "IsDayTime", "isDayTime", "DayTime", "dayTime"
        }) do
            if type(t[key]) == "boolean" then return not t[key] end
        end
        return nil
    end

    local function callNightBool(mod, name, now)
        local fn = mod and mod[name]
        if type(fn) ~= "function" then return nil end
        local ok, value = pcall(fn, now)
        if ok and type(value) == "boolean" then return value end
        return nil
    end

    local function readNightState()
        local now = workspace:GetServerTimeNow()
        local mod = loadAreaEggCycle()

        -- Prefer an explicit phase API if the current game build exposes one.
        if mod then
            for _, name in ipairs({
                "IsNight", "IsNightAt", "GetIsNight", "IsNightTime", "IsNightTimeAt"
            }) do
                local v = callNightBool(mod, name, now)
                if v ~= nil then
                    return v, "AreaEggCycle." .. name
                end
            end

            -- Some builds expose a state/cycle object rather than a boolean.
            for _, name in ipairs({ "StateAt", "GetStateAt", "CycleAt", "GetCycleAt", "GetState" }) do
                local fn = mod[name]
                if type(fn) == "function" then
                    local ok, state = pcall(fn, now)
                    if ok then
                        local v = boolFromTable(state)
                        if v ~= nil then
                            return v, "AreaEggCycle." .. name
                        end
                    end
                end
            end

            -- If the module exposes explicit night/day boundaries, use the
            -- same server-time model shown in NightEggTimeSkipAnimation.
            local periodFn = mod.PeriodIndexAt
            if type(periodFn) == "function" then
                local okPeriod, period = pcall(periodFn, now)
                if okPeriod and period ~= nil then
                    local nightStart, dayStart
                    for _, name in ipairs({ "NightStartsAt", "NightStartAt", "GetNightStartsAt", "NightStart" }) do
                        local fn = mod[name]
                        if type(fn) == "function" then
                            local ok, value = pcall(fn, period)
                            if ok and tonumber(value) then nightStart = tonumber(value) break end
                        end
                    end
                    for _, name in ipairs({ "DayStartsAt", "DayStartAt", "GetDayStartsAt", "DayStart" }) do
                        local fn = mod[name]
                        if type(fn) == "function" then
                            local ok, value = pcall(fn, period)
                            if ok and tonumber(value) then dayStart = tonumber(value) break end
                        end
                    end
                    if nightStart and dayStart then
                        -- Normal cycle: night begins at nightStart and ends at
                        -- dayStart. Handles a midnight-crossing interval too.
                        local isNight
                        if nightStart <= dayStart then
                            isNight = now >= nightStart and now < dayStart
                        else
                            isNight = now >= nightStart or now < dayStart
                        end
                        return isNight, "AreaEggCycle.boundaries"
                    end
                end
            end
        end

        -- Last-resort client-clock fallback. This is deliberately below the
        -- game cycle readers because the supplied source proves the egg system
        -- uses server timestamps. 18:00-06:00 is only a fallback when the
        -- current build exposes no readable AreaEggCycle phase API.
        local lighting = game:GetService("Lighting")
        local clock = tonumber(lighting.ClockTime)
        if clock then
            return clock >= 18 or clock < 6, "Lighting.ClockTime fallback"
        end

        return nil, "Night state unavailable"
    end

    -- Public phase reader used by the GUI notifier. It intentionally reuses
    -- the same server-time/AreaEggCycle resolver as the farm gate, so the
    -- notification and the worker can never disagree about Day vs Night.
    function M.getNightState()
        local ok, isNight, source = pcall(readNightState)
        if not ok then
            return nil, "Night state error"
        end
        return isNight, source
    end

    local function waitForNightIfAutoFarm(token)
        -- Manual Auto Steal remains 24/7. All automatic farm modes that use
        -- the field scanner are synchronized to the game's Night phase.
        -- Combo/Beta both hand off to the rarity worker, so they are covered.
        if owner ~= "rarity" and owner ~= "rarity_mobile" and owner ~= "farm" and owner ~= "beta" then return true end

        while running and token == runToken and BX.alive() do
            local isNight, source = readNightState()
            if isNight == true then
                if nightCycle.lastState ~= true or nightCycle.lastSource ~= source then
                    log.info("rarity worker: NIGHT detected (%s) - stealing enabled", source)
                    nightCycle.lastState = true
                    nightCycle.lastSource = source
                end
                return true
            end

            if nightCycle.lastState ~= false or nightCycle.lastSource ~= source then
                log.info("rarity worker: DAY detected (%s) - waiting for NIGHT", source)
                nightCycle.lastState = false
                nightCycle.lastSource = source
            end

            task.wait(1)
        end

        return false
    end

    -- ONE ENGINE, TWO CALLERS, AND THE FILTER BELONGS TO THE CALLER.
    --
    -- Main starts a run for ONE egg the user named and stops on delivery. Farm
    -- starts a run for a DESCRIPTION - areas, rarities, ordering - and keeps
    -- going. Same bait, same grab, same carry, same cleanup; only the options
    -- differ, and the options belong to whichever tab started the run.
    --
    -- V3.1 learned this the hard way and says so at BX.farmWanted (line 1670):
    -- "It used to be global, and that is the bug: pick Abyss Ocean on Farm, turn
    -- Farm's Auto Steal off, start Main's instead, and Main quietly kept stealing
    -- from Abyss Ocean. Nothing on Main said a filter existed, so there was no
    -- way to work out why it was ignoring the rest of the map."
    --
    -- So options are stored PER SOURCE and the live run reads only the source
    -- that started it. Changing Farm's dropdowns while Main is running cannot
    -- reach Main's run, and vice versa.
    local opts     = {}       -- the live run's options
    local optsFor  = {}       -- source -> that tab's options
    local owner    = nil      -- which source started the live run

    ---------- the systems this orchestrates ----------
    --
    --   features.bait      the Forest prime and the guard hit
    --   features.eggs      what exists and what it is worth
    --   features.movement  every leg, spoofed or not
    --   features.grab      the prompt fire and the confirmation
    --   features.carry     up, across, down, and the claim
    --   features.plot      where home is, and who says the egg is ours
    --
    -- This file owns the ORDER and the run's lifetime. It holds no movement,
    -- egg or carry state of its own, which is the whole reason it can stop
    -- cleanly: there is nothing here to leave behind.
    --
    -- NOT YET PORTED, and therefore not yet part of a cycle: the anticheat
    -- hold (movement runs unspoofed, so the outbound bracket stays at the
    -- measured-safe 500) and anti-hit on the real carry leg.

    ---------- resource snapshot ----------

    -- Taken before and after every cycle. Anything here that climbs with each
    -- steal is a leak the cycle owns, and unlike total process memory these are
    -- numbers we control.
    local function snapshot()
        local h = BX.profile.health()
        local e = eggs.stats()
        return {
            scopes = h.scopes, conns = h.conns, insts = h.insts, threads = h.threads,
            eggList = e.listSize, eggValues = e.valueCache,
        }
    end

    local SNAP_KEYS = { "scopes", "conns", "insts", "threads", "eggList", "eggValues" }

    local function diff(a, b)
        local out = {}
        for _, k in ipairs(SNAP_KEYS) do
            local d = (b[k] or 0) - (a[k] or 0)
            if d ~= 0 then out[#out + 1] = ("%s %+d"):format(k, d) end
        end
        return #out > 0 and table.concat(out, " ") or "no change"
    end

    -- NO RECOVERY STAGE HERE, DELIBERATELY.
    --
    -- An earlier version of this port added one. V3.1 does not have it, and
    -- says why at the point it would go (line 5395):
    --     "NO WAITING HERE. Prime, take the hit, LEAVE. I put a knockdown wait
    --      in this spot and it was wrong. The travel is what covers the
    --      knockdown, and on a normal trip it covers all of it."
    --
    -- The stage was invented to work around deaths that were really caused by
    -- two other things: the outbound running at 500 instead of 1200, and
    -- features.guard not being armed at all. Both are fixed, so the workaround
    -- goes rather than being kept "just in case" - it would only mask the next
    -- real failure.

    ---------- the cycle ----------

    -- V3.1 cycle, stage by stage:
    --     bait -> take the hit -> target -> grab -> up -> home -> down -> claimed
    --
    -- Every stage is timed separately, because "Auto Steal is laggy" is not
    -- actionable and "cross took 9.4s on a tier=low client" is.
    local function runCycle(token, cancel)
        -- Keep the previous delivery result visible until a new egg is actually
        -- grabbed. The next showAllHubDeliveryTarget() replaces it.
        local cycle = { t0 = os.clock(), stages = {} }
        BX.profile.mark("cycle_start")

        local function stage(name, fn)
            if cancel() then return false, { reason = "cancelled" } end
            local s0 = os.clock()
            local ok, info = fn()
            cycle.stages[#cycle.stages + 1] = {
                name = name, ms = (os.clock() - s0) * 1000, ok = ok and true or false,
            }
            return ok, info
        end

        -- ALREADY HOLDING ONE? DELIVER THAT FIRST.
        --
        -- A run that ended while carrying - toggled off mid-carry, a failed
        -- delivery, an error - leaves the egg in our hands. Every later attempt
        -- is then refused by the server with "Already carrying an egg", and the
        -- bait fails too, so the whole run spins without ever picking anything
        -- up. That is the "it does not pick the egg at the 2nd try" report,
        -- measured here as three consecutive cycles failing that way.
        --
        -- V3.1 checks the same thing at the top of its loop and says so:
        -- "still carrying ... - going home before anything else". The authority
        -- is the game, not our own flag.
        local held = eggs.carryingUid()
        if held then
            -- IS THIS THE JOB, OR IS IT PREPARATION?
            --
            -- Holding the egg the user actually asked for means the job is one
            -- delivery away and finishing it IS the run. Holding anything else
            -- - whatever was in our hands when Auto Steal was switched on -
            -- means this trip only clears our hands so a steal can start.
            --
            -- Both fly to the safe zone and look identical on screen. Only the
            -- first one is allowed to end the run.
            local isObjective = (opts.uid ~= nil) and (held == opts.uid)
            cycle.prep = not isObjective
            cycle.state = isObjective and M.STATE.RETURNING
                or M.STATE.PREP_DELIVER_HELD
            phase(token, cycle.state, "holding " .. tostring(held))
            cycle.recovered = held
            log.info("already carrying %s - %s", held,
                isObjective and "this is the selected egg, delivering to finish"
                or "not the selected egg, clearing our hands first")
            local ok2, info2 = stage("carry held", function()
                return carry.home(held, {
                    cancel = cancel, method = opts.method, deliverySpeed = opts.deliverySpeed,
                    areaId = (eggs.get(held) and eggs.get(held).areaId),
                    returnToBase = opts.returnToBase == true,
                    helpFriends = opts.helpFriends == true,
                })
            end)
            if ok2 then
                cycle.target = { name = isObjective and "selected egg" or "held egg",
                                 uid = held }
                if isObjective then
                    cycle.state = M.STATE.DELIVERED
                    cycle.terminal = true
                    phase(token, cycle.state, held)
                    return true, "delivered", cycle
                end
                -- Hands clear. The SAME run carries straight on into the steal.
                cycle.state = M.STATE.READY_TO_STEAL
                cycle.terminal = false
                phase(token, cycle.state, "hands clear after prep")
                return true, "prep: held egg delivered", cycle
            end
            -- Could not deliver it either. Say so and let the backoff apply,
            -- rather than starting a bait that cannot work while it is held.
            return false, "held egg: " .. tostring(info2 and info2.reason), cycle
        end

        -- Hands clear from the start: this cycle is the steal itself.
        if cycle.state == nil then
            cycle.state = M.STATE.READY_TO_STEAL
            phase(token, cycle.state)
        end

        -- 0. NOTHING TO GO FOR = NO BAIT. Farm only (opts.pick).
        --
        -- The bait ran BEFORE the target was chosen (V3.1's order, kept below
        -- for the real steal), so a filter that matched nothing still primed
        -- the bait every cycle: the character walked the Forest, picked up,
        -- dropped, came back, learned there was no target, backed off, and did
        -- it again. On a phone that reads as "Auto Steal jitters at the base
        -- with Drop flashing and never goes anywhere" - the Farm report. The
        -- pick is a walk of the cached list, so asking first costs nothing,
        -- and the answer is an idle wait (not a failure, not a backoff).
        local preTarget = nil
        if opts.pick and not opts.uid then
            local okPre, pre, whyPre = pcall(opts.pick)
            if not okPre then
                return false, "target picker failed: " .. tostring(pre), cycle
            end
            if not pre then
                return false, "nothing to steal"
                    .. (whyPre and (" (" .. tostring(whyPre) .. ")") or ""), cycle
            end
            preTarget = pre
        end

        -- 0b. A TARGET IN THE BAIT AREA IS NOT BAITED FOR. V3.1, verbatim:
        --
        --     if BX.primeEnabled and not heldEggUid
        --        and target.AreaId ~= BX.firstAreaId() then <prime>
        --
        -- The prime takes a Forest egg and walks into the Forest guard on
        -- purpose, which leaves that guard chasing. Priming and then
        -- teleporting to a FOREST target lands you next to the guard you just
        -- woke: caught, no pickup, "teleports to the egg but doesn't pick it
        -- up". Main rarely picks a Forest egg by name; Farm's picker does
        -- whenever the best income is there - which is the whole regression.
        -- Same rule for both owners, so Main with a Forest target is fixed too.
        local firstArea = bait.firstAreaId(0)
        local inBaitArea = nil
        if opts.uid then
            local want = eggs.get(opts.uid)
            inBaitArea = want and firstArea and want.areaId == firstArea or false
        elseif preTarget then
            inBaitArea = firstArea ~= nil and preTarget.areaId == firstArea
        end

        -- 1. THE BAIT. A failed prime is NOT a failed cycle: a missing bait egg
        --    is an ordinary state of the field, and V3.1 carries on without it
        --    rather than refusing to steal.
        local primed = false
        if inBaitArea then
            log.info("target is in the bait area (%s) - not priming, going straight for it (V3.1 rule)",
                tostring(firstArea))
            cycle.baitSkipped = true
        else
            primed = stage("bait", function()
                return bait.prime({ cancel = cancel })
            end)
        end
        cycle.primed = primed and true or false
        if cancel() then return false, "cancelled", cycle end

        -- 2. THE TARGET, chosen AFTER the bait. The bait takes seconds and the
        --    best egg may well have been taken in that time.
        -- A CHOSEN EGG IS A CHOSEN EGG.
        --
        -- When the user has picked one, we target THAT and wait for it rather
        -- than quietly stealing something else - a run that silently retargets
        -- is indistinguishable from one that ignored the dropdown. It is only
        -- abandoned when the egg is genuinely gone.
        local target
        if opts.uid then
            local want = eggs.get(opts.uid)
            if not want then
                return false, "selected egg is gone", cycle
            end
            local takeable = (want.state == "Slot" or want.state == "Dropped")
            if not takeable or not want.pos then
                -- Mid-cycle somewhere (carried, guard-held). Wait for it.
                return false, "waiting for the selected egg (" .. tostring(want.state) .. ")", cycle
            end
            target = want
        elseif opts.pick then
            -- A DESCRIPTION, NOT A NAME. Farm hands in a closure and this file
            -- stays ignorant of what an area or a rarity is: it asks for a
            -- target and gets one, chosen fresh every cycle from the egg list
            -- that is already cached. Re-picking per cycle is the whole point -
            -- holding one selection is what left V3.1 sitting on a chicken nest
            -- while a secret was up somewhere else.
            --
            -- Unless the bait was skipped FOR this target: no time has passed,
            -- and re-picking could swap a Forest target for a non-Forest one we
            -- then steal unprimed. The pre-pick is the pick.
            local ok2, want, why2 = true, preTarget, nil
            if not (cycle.baitSkipped and preTarget) then
                ok2, want, why2 = pcall(opts.pick)
            end
            if not ok2 then
                return false, "target picker failed: " .. tostring(want), cycle
            end
            target = want
            -- The picker's own reckoning, so "it picked nothing" is answerable
            -- without guessing which stage of the filter emptied the list.
            if not target then
                return false, "nothing matches the filter"
                    .. (why2 and (" (" .. tostring(why2) .. ")") or ""), cycle
            end
        else
            target = eggs.best()
        end
        if not target then return false, "nothing to steal", cycle end
        cycle.target = target

        local here = ch.root()
        cycle.distance = here and (target.pos - here.Position).Magnitude or -1

        -- 3+4. INSTANT STEAL: teleport onto the egg and race the server.
        --
        -- This is one stage, not two, because V3.1 does not separate them. It
        -- does NOT verify that the teleport was accepted - the server pulls us
        -- back about six times a second and that is expected. A hold thread
        -- re-asserts position every frame while three staggered threads hammer
        -- CarryFieldEgg; whoever is first to come back true wins.
        --
        -- See features/instant.lua for the measured timings.
        cycle.state = M.STATE.BAIT_DONE
        phase(token, cycle.state, cycle.primed and "primed"
            or (cycle.baitSkipped and "bait skipped: target in the bait area" or "no bait egg"))
        -- The trace the report asked for, in one line per cycle.
        log.info("target uid=%s name=%s area=%s rarity=%s state=%s dist=%.0f primed=%s",
            tostring(target.uid), tostring(target.name), tostring(target.areaId),
            tostring(target.rarity), tostring(target.state), cycle.distance or -1,
            tostring(cycle.primed))

        local took, inInfo
        local retries = 0
        for attempt = 0, TARGET_RETRIES do
            if cancel() then return false, "cancelled", cycle end

            -- FINAL AUTHORITATIVE CHECK BEFORE EVERY PICKUP.
            -- The rarity scanner is intentionally fast, but the field can change
            -- between scan -> movement -> pickup. Never fire at a stale position.
            local fresh = eggs.get(target.uid)
            if fresh then
                if fresh.state == "Carried" then
                    took = true
                    inInfo = { reason = "already carrying", carried = true }
                    break
                end
                if (fresh.state ~= "Slot" and fresh.state ~= "Dropped") or not fresh.pos then
                    inInfo = { reason = "egg no longer pickable", eggState = fresh.state }
                    break
                end
                target.pos = fresh.pos
                target.areaId = fresh.areaId or target.areaId
                target.nestId = fresh.nestId or target.nestId
                target.rarity = fresh.rarity or target.rarity
                target.value = fresh.value or target.value
            else
                inInfo = { reason = "egg disappeared", eggGone = true }
                break
            end

            cycle.state = (attempt == 0) and M.STATE.AT_TARGET or M.STATE.TARGET_GRAB_RETRY
            phase(token, cycle.state, target.name)

            -- A server "Enter the gameplay area first" is not a pickup failure:
            -- it means the teleport race reached the egg before the server's
            -- gameplay-area gate did. On the next attempt, physically enter the
            -- target area first instead of repeating the same teleport refusal.
            if attempt > 0 and inInfo and inInfo.serverGate then
                local freshGate = eggs.get(target.uid)
                if freshGate and freshGate.pos then
                    target.pos = freshGate.pos
                    pcall(function()
                        move.travel{
                            to = target.pos, speed = 900, arrive = 6,
                            carrying = false, cancel = cancel,
                            tag = "gameplay-area reanchor " .. tostring(target.name),
                        }
                    end)
                    RunService.Heartbeat:Wait()
                end
            end

            took, inInfo = stage(attempt == 0 and "instant" or ("regrab" .. attempt), function()
                return instant.take(target.uid, target.pos, {
                    cancel = cancel,
                    areaId = target.areaId, nestId = target.nestId,
                    method = opts.method,
                    timeout = 2.8,
                })
            end)
            if took or cancel() then break end

            local st = inInfo and inInfo.eggState
            local retryable = inInfo and (
                inInfo.pulledBack
                or st == "Slot"
                or st == "Dropped"
                or inInfo.reason == "no accept"
                or inInfo.reason == "no confirmation"
                or inInfo.serverGate == true
            )
            if not retryable or attempt == TARGET_RETRIES then break end

            retries = retries + 1
            task.wait(TARGET_RETRY_GAP)

            -- Re-anchor once before the next server race. This is deliberately
            -- one target-local correction, not a full Forest/guard restart.
            local latest = eggs.get(target.uid)
            if not latest or not latest.pos then break end
            if latest.state ~= "Slot" and latest.state ~= "Dropped" then break end
            target.pos = latest.pos
            target.areaId = latest.areaId or target.areaId
            target.nestId = latest.nestId or target.nestId

            log.info("target retry %d/%d (reason=%s state=%s pulledBack=%s)",
                retries, TARGET_RETRIES,
                tostring(inInfo and inInfo.reason), tostring(st),
                tostring(inInfo and inInfo.pulledBack))
        end
        cycle.grabRetries = retries

        -- PROMPT FALLBACK FOR THE RARE CASE WHERE THE INSTANT RACE LOSES BUT
        -- THE EGG IS STILL VALID. This is the final pickup path before the cycle
        -- is allowed to fail; it prevents rarity mode from "missing" an egg just
        -- because the server rejected a teleport race.
        if not took and not cancel() then
            local fresh = eggs.get(target.uid)
            if fresh and (fresh.state == "Slot" or fresh.state == "Dropped") and fresh.pos then
                target.pos = fresh.pos
                local reached, moveInfo = stage("pickup reanchor", function()
                    local tpOk = move.teleport(target.pos, "rarity pickup reanchor")
                    if tpOk then return true, { reason = "teleported-to-target" } end
                    return move.travel{
                        to = target.pos,
                        speed = math.max(move.outboundSpeed(), 1800),
                        arrive = 4,
                        carrying = false,
                        cancel = cancel,
                        tag = "rarity-pickup-reanchor",
                    }
                end)
                if reached and not cancel() then
                    local grabbed, grabInfo = stage("prompt fallback", function()
                        return grab.take(target.uid, {
                            pos = target.pos,
                            cancel = cancel,
                            tries = 4,
                        })
                    end)
                    if grabbed then
                        took = true
                        inInfo = grabInfo or { reason = "prompt fallback" }
                    else
                        inInfo = grabInfo or { reason = "prompt fallback failed" }
                    end
                else
                    inInfo = moveInfo or { reason = "pickup reanchor failed" }
                end
            end
        end

        if cancel() then return false, "cancelled", cycle end

        if took then
            cycle.state = M.STATE.CARRYING
            phase(token, cycle.state, "instant")
            cycle.transition = "tp"
            cycle.calls = inInfo and inInfo.calls
            cycle.tpGap = inInfo and inInfo.gap
        else
            -- THE FALLBACK, and only now. The race ran for its full timeout
            -- and the server never accepted, so travel there properly and use
            -- the prompt path instead. At 1200 studs/s with the WalkSpeed
            -- claim, exactly as V3.1 flies it.
            cycle.transition = "arc_fallback"
            cycle.instantFail = inInfo and inInfo.reason
            cycle.instantDiag = inInfo

            -- Refresh once more before the fallback. The target may have moved
            -- while the instant race was running. A short direct re-anchor also
            -- prevents the normal travel leg from appearing stuck on a stale
            -- nest position.
            local latest = eggs.get(target.uid)
            if latest and latest.pos and (latest.state == "Slot" or latest.state == "Dropped") then
                target.pos = latest.pos
            end

            local reached, moveInfo = stage("approach", function()
                local tpOk = move.teleport(target.pos, "pickup reanchor")
                if tpOk then
                    return true, { reason = "teleported-to-target" }
                end
                return move.travel{
                    to = target.pos, speed = math.max(move.outboundSpeed(), 1800),
                    arrive = 4, carrying = false, cancel = cancel, tag = "approach",
                }
            end)
            if cancel() then return false, "cancelled", cycle end
            if not reached then
                return false, "approach: " .. tostring(moveInfo and moveInfo.reason), cycle
            end

            local grabbed, grabInfo = stage("grab", function()
                return grab.take(target.uid, { pos = target.pos, cancel = cancel })
            end)
            if cancel() then return false, "cancelled", cycle end
            if not grabbed then
                -- Give it a rest rather than handing the same egg straight back
                -- on the next pass and repeating the whole bait for it.
                eggs.markUnreachable(target.uid)
                return false, "grab: " .. tostring(grabInfo and grabInfo.reason), cycle
            end
            cycle.state = M.STATE.CARRYING
            phase(token, cycle.state, "prompt")
        end

        -- 5. CARRY HOME: up, across, down, and wait to be claimed.
        -- Only now is the egg actually grabbed; show the target card during
        -- the delivery-to-Safe-Zone phase, not while merely selecting a target.
        showAllHubDeliveryTarget(target, opts.returnToBase == true
            and "GRAB ✓ • RETURN TO BASE"
            or "GRAB ✓ • DELIVERY TO SAFE ZONE")
        cycle.state = M.STATE.RETURNING
        phase(token, cycle.state, target.name)
        local delivered, carryInfo = stage("carry", function()
            return carry.home(target.uid, {
                cancel = cancel, method = opts.method, deliverySpeed = opts.deliverySpeed,
                areaId = target.areaId, returnToBase = opts.returnToBase == true,
                helpFriends = opts.helpFriends == true,
            })
        end)

        -- DELIVERY AUTO-RECOVERY:
        -- If the egg leaves our hands during the carry ARC, at the delivery
        -- door, or arrives but is not claimed, do not abandon this cycle.
        -- Recover the SAME uid, grab it again, and run the delivery again.
        --
        -- This deliberately does not restart bait/targeting. A recovery is:
        --     recover dropped egg -> grab/confirm -> carry -> descend -> claim
        -- and the cycle only becomes DELIVERED after the server confirms claim.
        -- The retry is bounded so a server-side refusal cannot become a hot loop.
        local recoveries = 0
        local maxRecoveries = math.max(1, tonumber(regrab.K.MAX_PER_STEAL) or 5)

        local function deliveryNeedsRecovery(info)
            local reason = tostring(info and info.reason or "")
            return reason:find("dropped in transit", 1, true)
                or reason:find("lost at the door", 1, true)
                or reason:find("arrived but never claimed", 1, true)
        end

        while not delivered and not cancel()
              and carryInfo and deliveryNeedsRecovery(carryInfo)
              and recoveries < maxRecoveries do

            svc.RunService.Heartbeat:Wait()

            recoveries = recoveries + 1
            cycle.recoveries = recoveries
            cycle.state = M.STATE.TARGET_GRAB_RETRY
            phase(token, cycle.state, ("delivery recovery %d/%d"):format(
                recoveries, maxRecoveries))

            local reasonBefore = tostring(carryInfo and carryInfo.reason or "?")
            local stillHeld = false
            do
                local okHeld, held = pcall(function()
                    return eggs.carryingUid()
                end)
                stillHeld = okHeld and tostring(held or "") == tostring(target.uid)
            end

            -- If the egg is still in our hands (for example "arrived but
            -- never claimed"), skip the field regrab and immediately deliver
            -- it again. Otherwise chase the dropped egg and grab it again.
            local back, rinfo
            if stillHeld then
                back = true
                rinfo = { recovery = "held-retry", reason = "still carrying" }
            else
                back, rinfo = stage("recover" .. recoveries, function()
                    return regrab.recover(target.uid, {
                        cancel = cancel,
                        areaId = target.areaId, nestId = target.nestId,
                    })
                end)
            end
            cycle.dropRecovery = rinfo and rinfo.recovery or "?"

            if not back then
                pcall(function() eggs.clearStolen(target.uid) end)
                finishAllHubTargetNotifier(target, "DELIVERY FAILED ✕ • " .. tostring(rinfo and rinfo.reason), "failed")
                return false, "delivery recovery: " .. tostring(rinfo and rinfo.reason), cycle
            end

            -- EXTRA GRAB CONFIRMATION. regrab.recover normally performs the
            -- instant grab itself. If the server accepted the recovery but the
            -- local carrying witness is not present yet, perform one normal
            -- grab attempt against the egg's fresh position before giving up.
            local carryingNow = false
            do
                local okHeld, held = pcall(function()
                    return eggs.carryingUid()
                end)
                carryingNow = okHeld and tostring(held or "") == tostring(target.uid)
            end

            if not carryingNow then
                local fresh = eggs.get(target.uid)
                if not fresh or not fresh.pos then
                    finishAllHubTargetNotifier(target, "DELIVERY FAILED ✕ • EGG POSITION LOST", "failed")
                    return false, "delivery recovery: egg position unavailable after " .. reasonBefore, cycle
                end

                local grabbed, grabInfo = stage("regrab_confirm" .. recoveries, function()
                    return grab.take(target.uid, {
                        pos = fresh.pos,
                        cancel = cancel,
                        tries = 5,
                    })
                end)
                if not grabbed then
                    finishAllHubTargetNotifier(target, "DELIVERY FAILED ✕ • RECOVERY GRAB", "failed")
                    return false, "delivery recovery grab: "
                        .. tostring(grabInfo and grabInfo.reason), cycle
                end
            end

            -- GOT THE EGG AGAIN. Carry + descend + server claim are repeated
            -- as one complete delivery, rather than only moving back to the
            -- destination and hoping the previous claim eventually fires.
            cycle.state = M.STATE.CARRYING
            phase(token, cycle.state, ("recovered egg %d/%d"):format(
                recoveries, maxRecoveries))

            cycle.state = M.STATE.RETURNING
            showAllHubDeliveryTarget(target, (opts.returnToBase == true
                and "RECOVERED %d/%d • RETURN TO BASE"
                or "RECOVERED %d/%d • DELIVERY TO SAFE ZONE"):format(recoveries, maxRecoveries))
            delivered, carryInfo = stage("carry" .. recoveries, function()
                return carry.home(target.uid, {
                    cancel = cancel,
                    method = opts.method,
                    deliverySpeed = opts.deliverySpeed,
                    areaId = target.areaId,
                    returnToBase = opts.returnToBase == true,
                    helpFriends = opts.helpFriends == true,
                })
            end)
        end

        if cancel() then
            finishAllHubTargetNotifier(target, "DELIVERY CANCELLED", "cancelled")
            return false, "cancelled", cycle
        end
        if not delivered then
            -- IMPORTANT: markStolen() happens at pickup time, not delivery time.
            -- If delivery failed, the egg can still exist in Slot/Dropped.
            -- Remove the temporary suppression so the next farm pass can see it
            -- immediately instead of waiting for STOLEN_FOR to expire.
            pcall(function() eggs.clearStolen(target.uid) end)
            finishAllHubTargetNotifier(target, "DELIVERY FAILED ✕ • " .. tostring(carryInfo and carryInfo.reason), "failed")
            return false, "carry: " .. tostring(carryInfo and carryInfo.reason), cycle
        end

        -- THE ONE TERMINAL SUCCESS: keep the result card visible instead of
        -- hiding it immediately when the egg reaches the Safe Zone.
        finishAllHubTargetNotifier(target, opts.returnToBase == true
            and "DELIVERED ✓ • BASE"
            or "DELIVERED ✓ • SAFE ZONE", "success")
        cycle.state = M.STATE.DELIVERED
        cycle.terminal = true
        phase(token, cycle.state, target.name)
        fireDelivered(target)
        return true, "delivered", cycle
    end

    local function reportCycle(ok, why, cycle, before, after)
        local parts = {}
        for _, s in ipairs(cycle.stages) do
            parts[#parts + 1] = ("%s=%.0fms%s"):format(s.name, s.ms, s.ok and "" or "!")
        end
        -- On a failure, print where the character actually was at each mark.
        -- "it died somewhere in the cycle" is not actionable; a health of 0 at
        -- unanchor and 100 at target_tp is.
        if not ok then
            local marks = BX.profile.marksSince(cycle.t0)
            if #marks > 0 then
                log.warn("timeline: %s", table.concat(marks, " | "))
            end
        end

        local level = ok and log.info or log.warn
        level("cycle %s in %.2fs [%s] target=%s dist=%.0f %s | %s",
            ok and "DELIVERED" or ("FAILED " .. tostring(why)),
            os.clock() - cycle.t0, table.concat(parts, " "),
            cycle.target and cycle.target.name or "-",
            cycle.distance or -1,
            ("state=%s transition=%s calls=%s retries=%d recoveries=%d%s primed=%s%s"):format(
                cycle.state or "?", cycle.transition or "?",
                tostring(cycle.calls or "-"), cycle.grabRetries or 0,
                cycle.recoveries or 0,
                cycle.dropRecovery and (" drop_recovery=" .. cycle.dropRecovery) or "",
                tostring(cycle.primed),
                cycle.instantFail and (" instantFail=" .. tostring(cycle.instantFail)
                    .. " pulledBack=" .. tostring(cycle.instantDiag and cycle.instantDiag.pulledBack)
                    .. " eggState=" .. tostring(cycle.instantDiag and cycle.instantDiag.eggState)) or ""),
            diff(before, after))
    end

    ---------- the loop ----------

    -- A run that only ever "prepares" is not progressing. Three hand-clearing
    -- trips is already generous: it takes one.
    local MAX_PREPS = 3
    local lastIdleWhy = nil

    local function runLoop(token)
        log.info("run %d: begin (tier=%s)", token, dev.tier)
        phase(token, "START", "tier=" .. tostring(dev.tier))
        local preps = 0

        while running and token == runToken and BX.alive() do
            -- EVERY PASS YIELDS AT LEAST ONE FRAME. NO EXCEPTIONS.
            --
            -- This is not a nicety. V3.1 caught a live case where a carried
            -- egg would not deliver, the return found itself already home and
            -- returned instantly, and the loop went round again - hundreds of
            -- passes inside 0.03s, never yielding. A Luau loop that never
            -- yields freezes the whole client, and it hits phones and
            -- emulators hardest. One Heartbeat per pass costs nothing next to
            -- a steal and makes a spin of that kind impossible, whatever the
            -- cause turns out to be.
            if opts.fastMode then
                -- One scheduler yield is enough; the rarity picker performs a
                -- forced EggState read every cycle.
                task.wait(0.01)
            else
                svc.RunService.Heartbeat:Wait()
            end
            if not running or token ~= runToken then break end

            local isCancelled = function()
                return (not running) or token ~= runToken or (not BX.alive())
            end

            -- All automatic egg-farm modes are Night-aware. Manual Auto Steal
            -- remains 24/7 and is intentionally not gated.
            if owner == "rarity" or owner == "rarity_mobile" or owner == "farm" or owner == "beta" then
                if not waitForNightIfAutoFarm(token) then break end
                if not running or token ~= runToken then break end

                -- STAY SAFE ZONE:
                -- After every successful delivery the character is already at
                -- the safe zone. Do not start bait/movement until a matching
                -- rarity egg actually exists. This is a live poll, so an egg
                -- that appears after the field was empty is picked up on the
                -- next poll without requiring the toggle to be restarted.
                local waitingAnnounced = false
                while running and token == runToken and BX.alive() do
                    local okPick, waitingTarget = pcall(opts.pick)
                    if okPick and waitingTarget then
                        if waitingAnnounced then
                            log.info("safe-zone wait ended -> target=%s rarity=%s value=%s",
                                tostring(waitingTarget.name),
                                tostring(waitingTarget.rarity),
                                tostring(waitingTarget.value))
                        end
                        break
                    end

                    if not waitingAnnounced then
                        waitingAnnounced = true
                        phase(token, "SAFE_ZONE_WAIT", "waiting for rarity egg")
                        log.info("safe-zone: waiting for selected rarity egg")
                    end

                    -- Short yield keeps this realtime without a busy loop.
                    task.wait(0.05)

                    if not waitForNightIfAutoFarm(token) then break end
                end

                if not running or token ~= runToken then break end
            end

            local before = snapshot()
            local ok, why, cycle = runCycle(token, isCancelled)
            local after = snapshot()

            -- AN IDLE PASS IS NOT A FAILED CYCLE. "nothing to steal" comes back
            -- twice a second while a Farm filter matches nothing; reporting
            -- each one as "cycle FAILED" filled the 400-line trace with the
            -- same sentence and buried the one line that explains it. Logged
            -- once per distinct reason instead.
            local idle = type(why) == "string"
                and (why:find("^nothing to steal") or why:find("^nothing matches the filter")) or false
            if idle then
                if why ~= lastIdleWhy then
                    lastIdleWhy = why
                    log.info("idle: %s", why)
                end
            else
                lastIdleWhy = nil
                if cycle then reportCycle(ok, why, cycle, before, after) end
            end

            if why == "cancelled" then break end

            if ok and not (cycle and cycle.terminal) then
                -- A SUCCESSFUL PASS THAT WAS NOT THE JOB.
                --
                -- Right now this is only ever the held-egg hand-clearing trip.
                -- It succeeded, so the backoff resets - but it is preparation,
                -- the run stays alive, the toggle stays on, and the next pass
                -- is the steal the user actually asked for.
                --
                -- Bounded: if we keep "preparing" we are not making progress,
                -- and something is handing us an egg we cannot get rid of.
                failures = 0
                preps = preps + 1
                if preps > MAX_PREPS then
                    log.warn("%d preparation passes without a steal - stopping",
                        preps)
                    return "ended"
                end
                log.info("preparation complete (%s) - continuing the same run",
                    tostring(why))
            elseif ok and opts.continuous then
                -- FARM: A DELIVERY IS THE END OF A CYCLE, NOT OF THE JOB.
                --
                -- The same terminal delivery that stops Main keeps Farm going.
                -- The next pass re-picks from the filter, so the run follows the
                -- field instead of holding a stale choice, and it only ends when
                -- the user turns it off. No second loop, no second worker - this
                -- is the one run, going round again.
                failures = 0
                cycles = cycles + 1
                log.info("delivered (%d this run) - continuing", cycles)
                -- User-controlled delay between completed steals. Lower = faster.
                local cycleDelay = tonumber(opts.cycleDelay) or 0
                if cycleDelay > 0 then
                    task.wait(math.clamp(cycleDelay, opts.fastMode and 0.02 or 0.05, 5.0))
                end
            elseif ok then
                failures = 0
                cycles = cycles + 1
                -- THE RUN IS FINISHED.
                --
                -- A confirmed delivery is the end of the job, not the start of
                -- the next one. Picking a fresh target and going back to the
                -- Forest guard on its own is not what "steal this egg" means,
                -- and it is how a run that was doing exactly what was asked
                -- ends up looking like it ignored the dropdown.
                --
                -- ONLY the selected egg reaching the safe zone gets here. The
                -- preparation trip above goes to the same place and is not a
                -- completion; conflating the two is what switched Auto Steal
                -- off before it had stolen anything.
                log.info("delivered - run complete")
                return "delivered"
            elseif type(why) == "string" and why:find("Ride Guard: No Ride Guard available", 1, true) then
                -- Missing Ride Guard is a transient streaming/configuration state,
                -- not a carry failure. Avoid the 0.2s -> 0.4s hot retry loop.
                task.wait(dev.scale(opts.fastMode and 0.45 or 0.80))
            elseif (type(why) == "string" and why:find("^nothing to steal"))
                or why == "nothing matches the filter"
                or (type(why) == "string" and why:find("^nothing matches the filter"))
                or why == "selected egg is gone"
                or (type(why) == "string" and why:find("waiting for the selected egg", 1, true)) then
                -- NOT a failure. Everything matching the filter has just been
                -- taken and has not respawned; waiting is correct and it must
                -- not feed the backoff.
                local idleWait = opts.fastMode and 0.12 or IDLE_WAIT
                task.wait(dev.scale(idleWait))
            else
                failures = failures + 1
                local wait = math.min(BACKOFF_BASE * (2 ^ (failures - 1)), BACKOFF_CAP)
                wait = dev.scale(wait)
                log.warn("backing off %.1fs (failure %d)", wait, failures)
                task.wait(wait)
            end
        end

        log.info("run %d: ended", token)
        return "ended"
    end

    ---------- start / stop ----------

    local function stop(reason)
        if not running then return end
        running = false
        -- Disable the instant GRAB EGG prompt manager first. This restores every
        -- ProximityPrompt HoldDuration changed by Auto Steal, including prompts
        -- that were created dynamically during the run.
        BX.try("autosteal.instantGrabOff", function() grab.setInstantGrab(false) end)

        -- Bumping the token retires any loop that is mid-pass, even one that
        -- is blocked in a wait and cannot see `running` yet.
        runToken = runToken + 1
        st.autoStealOn = false
        BX.try("autosteal.guardStealingOff", function()
            local guardFeature = BX.require("features.guard")
            if guardFeature and type(guardFeature.setStealing) == "function" then
                guardFeature.setStealing(false)
            end
        end)

        if sc then
            -- Everything the run created: connections, threads, movers,
            -- Instances, tweens. One call, no list to keep in sync.
            sc:destroy()
            sc = nil
        end
        failures = 0
        liveEggScan.list = {}
        liveEggScan.at = 0
        liveEggScan.seq = 0
        liveEggScan.errors = 0
        nightCycle.lastState = nil
        nightCycle.lastSource = nil
        -- Captured before clearing: a stop listener needs to know WHICH tab's
        -- run ended, or every tab resets its toggle on every stop.
        local whose = owner
        owner = nil
        opts = {}
        -- A run cancelled mid-leg can leave PlatformStand on, an inflated
        -- WalkSpeed, noclip active or the character anchored. None of those
        -- belong to a scope, so they are undone explicitly.
        BX.try("autosteal.antideath", adeath.disarm)
        BX.try("autosteal.humanoid", hswap.disarm)
        BX.try("autosteal.guard", guard.disarm)
        BX.try("autosteal.resetMovement", move.reset)
        BX.try("autosteal.unanchor", function()
            local hrp = ch.root()
            if hrp and hrp.Anchored then hrp.Anchored = false end
        end)

        -- ONE CLEANUP PATH, AND IT IS IDEMPOTENT.
        --
        -- Every terminal path - delivered, toggled off, failed grab, dropped
        -- egg, recovery failure, death, target gone, re-execute, an error -
        -- arrives here. The features above disarm themselves; core.restore then
        -- puts back every character value that was captured before it was
        -- changed, using the value it actually had rather than a guess.
        --
        -- restoreAll is safe to call twice. audit() reports anything still
        -- differing - a clean run prints PASS, and anything else names exactly
        -- what was left behind. That is the difference between cleanup that
        -- works and cleanup that is believed to work.
        local restored, skipped, failed = 0, 0, 0
        BX.try("autosteal.restore", function()
            restored, skipped, failed = rs.restoreAll()
        end)

        local leftovers = {}
        BX.try("autosteal.audit", function() leftovers = rs.audit() end)

        if #leftovers == 0 and failed == 0 then
            log.info("autosteal cleanup: PASS (%d restored, %d skipped)",
                restored, skipped)
        else
            log.warn("autosteal cleanup: %d restored, %d skipped, %d FAILED%s",
                restored, skipped, failed,
                #leftovers > 0
                    and (" | still modified: " .. table.concat(leftovers, "; ")) or "")
        end

        log.info("stopped (%s) after %d cycles", reason or "requested", cycles)
        phase(phaseRun, "STOP", reason or "requested")
        log.info("run %d trail: %s", phaseRun, table.concat(phases, " -> "))

        -- On its own thread: a listener writes to a UI Instance, and this
        -- thread has been through game code and cannot touch one.
        local why = reason or "requested"
        for _, fn in ipairs(stopListeners) do
            task.spawn(function() BX.try("autosteal.onStop", fn, why, whose) end)
        end
    end

    -- WHAT THIS EXECUTOR CAN STEAL WITH, SAID ONCE, BEFORE THE RUN.
    --
    -- The pickup has two paths: the instant race (EggState.CarryFieldEgg,
    -- which needs require() on the game's modules) and the prompt grab
    -- (fireproximityprompt, or the InputHoldBegin fallback). An executor with
    -- neither has no steal, and the run used to discover that one cycle at a
    -- time as "no CarryFieldEgg" then "no prompt", then back off, forever -
    -- a switch that stayed on and did nothing. Refused up front instead, with
    -- the reason in the log and returned to the tab.
    function M.capability()
        local exec = BX.require("core.exec")
        local paths = {}
        if instant.ready then paths[#paths + 1] = "instant (CarryFieldEgg)" end
        if exec.can.prompts then paths[#paths + 1] = "prompt (" .. tostring(exec.promptVia) .. ")" end
        if #paths == 0 then
            return false, "Auto Steal cannot run on this executor: no game-module require ("
                .. tostring(exec.gameRequireWhy) .. ") and no proximity prompt path"
        end
        return true, table.concat(paths, " + ")
    end

    local function start(src)
        if running then return end
        local okCap, capWhy = M.capability()
        if not okCap then
            log.error("%s", capWhy)
            return false, capWhy
        end
        owner = tostring(src or "main")
        opts = optsFor[owner] or {}
        nightCycle.lastState = nil
        nightCycle.lastSource = nil
        log.info("run starting for %s - pickup via %s (method=%s)",
            owner, capWhy, tostring(opts.method or "24/7"))
        -- Stop first even though `running` is false: a previous scope can
        -- outlive its run if something went wrong, and this is the one place
        -- that guarantees it does not.
        if sc then sc:destroy() end

        runToken = runToken + 1
        running  = true
        liveEggScan.list = {}
        liveEggScan.at = 0
        liveEggScan.seq = 0
        liveEggScan.errors = 0
        st.autoStealOn = true
        BX.try("autosteal.guardStealingOn", function()
            local guardFeature = BX.require("features.guard")
            if guardFeature and type(guardFeature.setStealing) == "function" then
                guardFeature.setStealing(true)
            end
        end)

        -- Instant GRAB EGG: remove ProximityPrompt hold delay for the whole
        -- Auto Steal run, including prompts that appear after teleport/respawn.
        BX.try("autosteal.instantGrab", function() grab.setInstantGrab(true) end)

        sc = BX.scope("features.autosteal")

        local token = runToken

        -- Rarity/Beta own a scanner that NEVER waits for the current steal
        -- stage. It keeps reading the field while we are:
        --   SAFE ZONE WAIT / bait / teleport / grab / carrying / delivery.
        -- The scope is destroyed by stop(), so the scanner cannot leak into a
        -- later run.
        if owner == "rarity" or owner == "rarity_mobile" or owner == "beta" then
            sc:spawn("egg-live-scan", function()
                local nextScan = 0
                while running and token == runToken do
                    local now = os.clock()
                    if now >= nextScan then
                        local ok, result = pcall(function()
                            return eggs.list({}, true)
                        end)

                        if ok and type(result) == "table" then
                            liveEggScan.list = result
                            liveEggScan.at = os.clock()
                            liveEggScan.seq = liveEggScan.seq + 1
                        else
                            liveEggScan.errors = liveEggScan.errors + 1
                        end

                        -- Phone profile intentionally scans less often than the
                        -- desktop rarity worker. It still uses the same live egg
                        -- cache, but avoids ~20 full field scans/sec on Android.
                        local scanInterval = (owner == "rarity_mobile") and 0.22 or LIVE_SCAN_INTERVAL
                        nextScan = now + scanInterval
                    end

                    -- Heartbeat keeps the scanner responsive without creating
                    -- a tight Lua loop.
                    svc.RunService.Heartbeat:Wait()
                end
            end)
        end

        -- A respawn does not restart the run; it resets what the run knows
        -- about the character. Rebuilding here is what produced duplicate
        -- workers in V3.1 - five deaths, five loops.
        ch.onSpawn(sc, "autosteal.respawn", function()
            if not running or token ~= runToken then return end
            failures = 0
            log.trace("respawn: run %d continues", token)
        end)

        -- Armed for the run. The bait deliberately takes a hit and a guard
        -- can land another on arrival; without this the character dies and the
        -- cycle is over. Disarmed in stop(), which restores every original
        -- Humanoid value.
        -- ORDER MATTERS. V3.1 swaps the Humanoid FIRST, at the top of
        -- stealLoop, before anything else is armed - the anticheat caches
        -- its reference at CharacterAdded and everything after this point
        -- depends on that reference being dead.
        -- CONTAINED, AND THE WORKER SPAWNS WHATEVER HAPPENS.
        --
        -- These three were called bare. `running` and st.autoStealOn are already
        -- true by this point, so a throw in any of them left the hub in the worst
        -- possible state: isRunning() true, the toggle on, and NO WORKER THREAD -
        -- a run that reports itself as live and never moves the character. The
        -- toggle callback is invoked through the UI library, which swallows the
        -- error, so nothing said so either.
        --
        -- A failed arm is not a reason to refuse to steal. hswap failing means
        -- teleports get punished and the guard failing means a hit can land -
        -- both already log loudly on their own - so they are recorded here and
        -- the run goes ahead rather than dying silently.
        local armed = {}
        for _, a in ipairs({ { "humanoid", hswap.arm }, { "guard", guard.arm },
                             { "antideath", adeath.arm } }) do
            local ok = BX.try("autosteal.arm." .. a[1], a[2])
            armed[#armed + 1] = a[1] .. (ok and "=ok" or "=FAILED")
        end
        log.info("run %d: armed %s", token, table.concat(armed, " "))

        sc:spawn("loop", function()
            log.info("run %d: worker thread started (owner=%s, options: %s)",
                token, tostring(owner),
                opts.uid and ("uid=" .. tostring(opts.uid))
                    or (opts.pick and ("picker" .. (opts.continuous and ", continuous" or ""))
                        or "best value"))
            local reason = runLoop(token)
            -- Through stop(), never a bare break: that is the one path that
            -- destroys the scope, disarms guard/antideath/humanoid and resets
            -- movement. Guarded on the token so a run that was already
            -- replaced cannot stop its successor.
            -- EVERY EXIT GOES THROUGH stop(), NOT JUST A DELIVERY.
            --
            -- This used to fire only for "delivered", so any other way out of
            -- runLoop left `running` and st.autoStealOn true with no worker
            -- thread behind them: the toggle stayed on, isRunning() lied, and the
            -- character never moved again. The MAX_PREPS exit hits exactly that -
            -- reachable in normal play when the egg inventory is full, because the
            -- hand-clearing delivery keeps being refused.
            --
            -- stop() is idempotent, so the ordinary path (the loop ending because
            -- stop() already ran) costs nothing here.
            if token == runToken then
                if reason == "delivered" then
                    stop("delivered")
                elseif running then
                    stop(reason or "ended")
                end
            end
        end)
    end

    -- setOptions("farm", { ... }). A table as the first argument is treated as
    -- Main's, so the original one-argument call still means what it did.
    function M.setOptions(src, o)
        if type(src) == "table" or src == nil then src, o = "main", src end
        src = tostring(src)
        optsFor[src] = o or {}
        -- Live update, but only for the tab that owns the run.
        if running and owner == src then
            opts = optsFor[src]
            log.info("%s updated its options mid-run", src)
        end
    end

    function M.setEnabled(on, src)
        src = tostring(src or "main")
        if on then
            local okStart, why = start(src)
            if okStart == false then return false, why end
        else
            -- A tab may only stop the run it started. Without this, flipping
            -- Farm's toggle off would kill a run Main had started.
            if running and owner ~= nil and owner ~= src then
                log.info("%s asked to stop, but %s owns this run - ignored", src, owner)
                return false
            end
            stop("toggled off")
        end
        return true
    end

    function M.owner() return owner end

    function M.isRunning()
        return running
    end

    function M.runOnce(cancelFn)
        -- One cycle, for testing and for a manual single steal. Uses the same
        -- code path as the loop so a test cannot pass against a different
        -- implementation from the one that ships.
        local before = snapshot()
        local ok, why, cycle = runCycle(runToken, cancelFn or function() return false end)
        local after = snapshot()
        if cycle then reportCycle(ok, why, cycle, before, after) end
        return ok, why, cycle, before, after
    end

    function M.status()
        return {
            running  = running,
            token    = runToken,
            cycles   = cycles,
            failures = failures,
            nightOnly = owner == "rarity" or owner == "rarity_mobile" or owner == "farm" or owner == "beta",
            nightState = nightCycle.lastState,
            nightStateSource = nightCycle.lastSource,
            tier     = dev.tier,
            scope    = sc and sc:counts() or nil,
        }
    end

    -- Unloading the menu, or a re-execute retiring this generation, must take
    -- the run with it rather than leave it going with no way to reach it.
    M.stop = stop

    return M
end)

--[[ ==== features/bossfight.lua ====================================== ]]
-- =============================================================================
-- FEATURES.BOSSFIGHT: V3.1's Auto fight - crystals first, then the hands
-- =============================================================================
--
--     local fight = BX.require("features.bossfight")
--     fight.setEnabled(true)     -- the user's wish; it waits until it can act
--     fight.status()             -- { title =, body = } for the Event tab
--     fight.isOn()
--
-- WHAT THIS IS A PORT OF, LINE FOR LINE WHERE IT MATTERS.
--
-- V3.1 "Auto fight" was four pieces, all started by the toggle and all reading
-- BX.autoBossFight + BX.inBossArena() before doing anything:
--
--     BX.startBossMover     Heartbeat: ONE writer of the character's CFrame.
--                           Walks to BX.bossGoal (or BX.bossDodge), probes for
--                           floor every step, follows the rim of the pit,
--                           sidesteps scenery, cancels flings, lifts us back
--                           onto the floor if noclip let us sink.
--     the fight tick        every K.BOSS_TICK (0.12s): equips the bat, picks
--                           the target (nearest live crystal, then the nearest
--                           reachable hand), hands the mover a goal, faces the
--                           target when in range, swings every 0.65s.
--     BX.startBossDodge     0.08s: publishes an escape when standing in a
--                           hazard. SHIPPED DISABLED (BX.bossDodgeEnabled =
--                           false - "do not run from the thing that chases
--                           you"), so inAnyHazard answered nil and this loop
--                           did nothing. Kept, still off, behind K.DODGE.
--     BX.startVoidWatch     0.2s: pulls us back onto the last solid ground if
--                           the floor probe fails three times AND we are well
--                           below where we stood. Arena half only; the steal
--                           half belongs to the steal.
--
-- Every constant below is V3.1's, with its reasoning kept. Nothing about how
-- the fight chooses, moves or swings is new.
--
-- TRACED FROM THE ROOT V3.1 MONOLITH, NOT V3_RELEASE. The first cut of this
-- file came from V3_RELEASE and missed what V3.1 fixed after the game made
-- the bat a gear item: the IsBat attribute, Humanoid:EquipTool (reparenting
-- never fires Equipped for the bat controller, so bat:Activate() is refused),
-- the swing fired straight at RE/BatSwing/Trigger with the controller's own
-- payload, CooldownActive, and "no bat must not mean no movement". That was
-- the "Auto fight does nothing" of the second cut.
--
-- WHAT IS DIFFERENT, AND WHY.
--
-- 1. ONE SCOPE. V3.1 had a Heartbeat connection, three threads and a
--    session-long tick that all read a global to know whether to stop. Here
--    setEnabled(false) destroys the scope and everything in it. Re-executing
--    does the same through BX.teardown. Nothing here can outlive the switch.
--
-- 2. ON MEANS "WANTED", NOT "RUNNING". The toggle is the user's preference
--    and stays up. Whether we can actually fight is a separate question -
--    are we in the arena, is the boss there - and status() says which, so the
--    switch never snaps back and never lies. That is the whole bug this file
--    exists to fix: V4 shipped the control with a callback that turned itself
--    off and logged "not ported".
--
-- 3. NOCLIP ONLY INSIDE THE ARENA. V3.1 switched collision off the moment the
--    toggle went on, even standing on the main map with the boss closed. The
--    reason for noclip is the arena's 195 collidable parts; it goes on when
--    the InBossArena attribute does and comes back off when we leave. The
--    steal's own noclip is left alone: features.movement owns it, and it is
--    only released here when Auto Steal is not running.
--
-- 4. AUTO STEAL IS NEVER FOUGHT OVER THE CHARACTER. While autosteal.isRunning()
--    the tick and the mover stand down. In practice you cannot be in the arena
--    and mid-steal at once, so this is a guard, not a policy.

BX.module("features.bossfight", function(BX)
    local svc  = BX.require("core.services")
    local dev  = BX.require("core.device")
    local ch   = BX.require("core.character")
    local net  = BX.require("core.net")
    local boss = BX.require("features.boss")
    local mov  = BX.require("features.movement")
    local auto = BX.require("features.autosteal")
    local log  = BX.require("boot.log").for_module("bossfight")

    local M = {}

    local K = {
        -- THE FIGHT TICK IS NOT THE SWING TICK. V3.1: these were one number
        -- (0.65s) and the character moved for 0.4s then froze for 0.25s.
        TICK            = 0.12,
        -- SWING GAP MUST CLEAR THE TOOL'S OWN 0.6s DEBOUNCE. It was 0.35 and
        -- every other Activate was swallowed before a packet went out.
        SWING_GAP       = 0.65,
        REACH           = 9,
        -- A tool parented this frame has not fired Equipped; the controller
        -- still says _isEquipped = false and swallows the swing.
        EQUIP_SETTLE    = 0.25,
        -- LET A FRESH CHARACTER SETTLE BEFORE THE MOVER TOUCHES IT.
        --
        -- On the arena-entry edge - the enter teleport AND every respawn -
        -- the server is still asserting the character's position for a beat.
        -- If the Heartbeat mover starts writing CFrame on frame 1 of the new
        -- character it fights that assertion: the server Relocates, the mover
        -- writes again, and the crystal is never reached - the "smooth before
        -- death, snapback loop after respawn" report. The first entry looked
        -- fine only because the enter teleport had already placed us; a
        -- respawn has not. Holding the mover for this long lets the new root
        -- settle, exactly as the first entry was already settled.
        RESPAWN_SETTLE  = 0.6,
        -- How far above us a hand may be and still be swung at / walked to.
        HAND_REACH_Y    = 30,
        HAND_CHASE_Y    = 90,
        HAND_RISE_EPS   = 2,      -- upward studs per tick = "this arm is retracting"
        HAND_COMMIT     = 1.5,    -- seconds we stay on a chosen hand
        -- STAND OUTSIDE THE THING. A crystal Hitbox is 55^3; reach is
        -- max(REACH, half + this), i.e. just clear of the surface.
        SURFACE_MARGIN  = -20,
        -- The mover. 420 with a 14-stud frame cap: Relocate is the limit.
        STEP_SPEED      = 420,
        MAX_STEP        = 14,
        MAX_DT          = 0.05,
        SINK_MAX        = 6,      -- below the last real floor = fell through
        Y_TAU           = 0.12,   -- seconds to close ~63% of a height change
        STUCK_TIME      = 2.5,
        RIM_SWEEP       = { 25, 50, 75, 100, 125, 150 },
        RIM_LOOKAHEAD   = 6,
        MOVE_ARRIVE     = 1.5,
        SWING_SLACK     = 4,      -- must exceed MOVE_ARRIVE or they deadlock
        AIM_COS         = 0.906,  -- cos 25 deg
        AIM_EASE        = 0.35,
        TRACK_TAU       = 0.18,   -- low-pass on a hand's jittering position
        TRACK_JUMP      = 60,
        WAIT_MAX        = 2.5,    -- longest we hold for a hazard to clear
        -- Anti-fling: cancel what our own walk could not have produced.
        FLING_UP        = 60,
        FLING_MULT      = 2.0,
        -- Floor probe.
        GROUND_BAND     = 25,
        PROBE_UP        = 40,
        PROBE_DOWN      = 220,
        SOLID_STEPS     = 8,
        IGNORE_TTL      = 0.5,    -- the raycast ignore list is rebuilt this often
        -- Rim walking.
        RING_STEP_DEG   = 22,
        RING_RADII      = { 1.0, 0.85, 1.15, 0.7, 1.3 },
        AROUND_ANGLES   = { 25, 45, 70, 95, 120, 145 },
        AROUND_FRAC     = 0.55,
        AROUND_MIN_R    = 90,
        -- Hazards.
        HAZARD_CACHE    = 0.1,
        HAZARD_CLEAR    = 6,
        SLAM_CLEAR      = 12,
        RING_CLEAR      = 2,      -- the red rings are 2 studs wide, not walls
        HOLE_CLEAR      = 6,
        DODGE_GAP       = 0.08,
        DODGE_POINTS    = 16,
        DODGE           = false,  -- V3.1 BX.bossDodgeEnabled. Shipped off.
        ORBIT_TRIGGER   = 34,
        ORBIT_STEP      = 0.55,
        -- Void watch (arena half).
        VOID_GAP        = 0.2,
        VOID_MISSES     = 3,
        VOID_DROP_PROOF = 25,
        MAX_RISE        = 8,
        HAND_BONES      = { "UpperHand1.R", "UpperHand1.L", "LowerHand1.R", "LowerHand1.L" },
    }
    M.K = K

    local sc, enabled = nil, false
    local stats = { swings = 0, dodges = 0, flings = 0, voidSaves = 0, rescues = 0, kills = 0 }
    function M.stats() return table.clone(stats) end
    function M.isOn() return enabled end

    -- Everything V3.1 kept as BX.* globals, in one table that setEnabled(false)
    -- drops. Names match V3.1's so the two can be read side by side.
    local S = nil
    local function fresh()
        return {
            goal = nil, dodge = nil, aim = nil, trackPos = nil,
            handY = {}, handPick = nil, handPickAt = 0,
            lastSolid = nil, arenaFloorY = nil,
            stuckBest = nil, stuckSince = nil, stuckFlip = false, rimSide = 1,
            lastSwingAt = 0, batFor = nil, waitAt = nil, idlePhase = false,
            arena = nil, hazards = nil, hazardsAt = 0,
            ignore = nil, ignoreAt = 0,
            inArena = false, noclipped = false, left = false,
            settleUntil = 0, batAskedAt = 0,
            voidAnchor = nil, voidMisses = 0,
            lastLog = {},
            phase = nil, kind = nil,
        }
    end

    -- Rate-limited trace lines, keyed, so the log reads like V3.1's.
    local function every(key, secs, fmt, ...)
        local now = os.clock()
        if now - (S.lastLog[key] or 0) < secs then return end
        S.lastLog[key] = now
        log.info(fmt, ...)
    end

    ---------- the arena ----------

    local function inArena()
        return svc.LocalPlayer:GetAttribute("InBossArena") == true
    end
    M.inArena = inArena

    -- Cached: a recursive FindFirstChild walks 38k instances and the tick
    -- asks eight times a second.
    local function arena()
        local a = S.arena
        if a and a.Parent then return a end
        a = workspace:FindFirstChild("BossArena") or workspace:FindFirstChild("BossArena", true)
        S.arena = a
        return a
    end

    local function arenaFloor()
        local a = arena()
        local f = a and a:FindFirstChild("Floor", true)
        if f and f:IsA("BasePart") then return f end
        return nil
    end

    local function arenaCentre()
        local f = arenaFloor()
        if f then return f.Position end
        local a = arena()
        if a and a.PrimaryPart then return a.PrimaryPart.Position end
        return nil
    end

    local function bossModel()
        local a = arena()
        if not a then return nil end
        local b = a:FindFirstChild("Boss", true)
        if b and b:IsA("Model") then return b end
        return nil
    end

    -- nil while the boss is still arriving, "crystals" or "hands" otherwise.
    local function phase()
        local b = bossModel()
        if not b then return nil end
        if b:GetAttribute("Spawning") then return nil end
        if b:GetAttribute("PhaseTwoAt") ~= nil then return "hands" end
        return "crystals"
    end

    ---------- the floor ----------

    -- IS THERE ACTUALLY GROUND THERE. V3.1 probed the floor on a 13x13 grid:
    -- 51 of 169 cells had nothing under them, the centre included - the Floor
    -- part's box says "floor" for a pit. A downward ray is the only thing that
    -- knows the difference. Crystal towers, the boss and the hazards are
    -- ignored so a ray beside a tower does not report its top as ground.
    local probeParams = RaycastParams.new()
    probeParams.FilterType = Enum.RaycastFilterType.Exclude
    probeParams.IgnoreWater = true

    local function refreshIgnore()
        local now = os.clock()
        if S.ignore and (now - S.ignoreAt) < K.IGNORE_TTL then return end
        local ignore = {}
        for _, pl in ipairs(svc.Players:GetPlayers()) do
            if pl.Character then ignore[#ignore + 1] = pl.Character end
        end
        local a = arena()
        if a then
            for _, nm in ipairs({ "CrystalTowers", "Boss", "SlamIndicator",
                                  "SlamArmHitbox", "SlamRestHitbox" }) do
                local d = a:FindFirstChild(nm, true)
                if d then ignore[#ignore + 1] = d end
            end
        end
        for _, nm in ipairs({ "BossHazards", "BossBlackHole" }) do
            local d = workspace:FindFirstChild(nm)
            if d then ignore[#ignore + 1] = d end
        end
        probeParams.FilterDescendantsInstances = ignore
        S.ignore, S.ignoreAt = ignore, now
    end

    local function groundAt(pos)
        refreshIgnore()
        -- Anchored to the arena floor, not to us: once we are falling a ray
        -- from above our head starts under the floor and never answers.
        local top = pos.Y + K.PROBE_UP
        local f = arenaFloor()
        if f then top = math.max(top, f.Position.Y + K.PROBE_UP) end
        local reach = math.max(K.PROBE_DOWN, (top - pos.Y) + K.PROBE_DOWN)
        local r = workspace:Raycast(Vector3.new(pos.X, top, pos.Z),
                                    Vector3.new(0, -reach, 0), probeParams)
        if not r then return nil end
        if f and (r.Position.Y - f.Position.Y) > K.GROUND_BAND then return nil end
        return r.Position.Y
    end

    local function onFloor(pos) return groundAt(pos) ~= nil end

    local function lastSolidToward(from, to)
        local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
        local dist = flat.Magnitude
        if dist < 1 then return nil end
        local dir = flat.Unit
        local best
        -- At most SOLID_STEPS probes, by construction: a bounded for, not a
        -- while, so a bad step size can never spin.
        local step = math.max(dist / K.SOLID_STEPS, 20)
        for i = 1, K.SOLID_STEPS do
            local d = step * i
            if d > dist then break end
            local p = from + dir * d
            local gy = groundAt(Vector3.new(p.X, from.Y, p.Z))
            if not gy then break end
            best = Vector3.new(p.X, gy, p.Z)
        end
        return best
    end

    local function clearLine(a, b)
        local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
        local dist = flat.Magnitude
        if dist < 1 then return true end
        local dir = flat.Unit
        local step = math.max(dist / K.SOLID_STEPS, 20)
        for i = 1, K.SOLID_STEPS do
            local d = step * i
            if d >= dist then break end
            local p = a + dir * d
            if not groundAt(Vector3.new(p.X, a.Y, p.Z)) then return false end
        end
        return true
    end

    -- WALK THE RING. The floor is an annulus; step our bearing round the
    -- centre toward the target's bearing, holding our radius.
    local function ringWaypoint(from, to)
        local mid = arenaCentre()
        if not mid then return nil end
        local a = Vector3.new(from.X - mid.X, 0, from.Z - mid.Z)
        local b = Vector3.new(to.X - mid.X, 0, to.Z - mid.Z)
        if a.Magnitude < 20 or b.Magnitude < 20 then return nil end
        local ang1, ang2 = math.atan2(a.Z, a.X), math.atan2(b.Z, b.X)
        local diff = ang2 - ang1
        while diff > math.pi do diff = diff - 2 * math.pi end
        while diff < -math.pi do diff = diff + 2 * math.pi end
        local step = math.min(math.abs(diff), math.rad(K.RING_STEP_DEG))
        if diff < 0 then step = -step end
        local want = ang1 + step
        for _, mul in ipairs(K.RING_RADII) do
            local r = a.Magnitude * mul
            local p = Vector3.new(mid.X + math.cos(want) * r, from.Y, mid.Z + math.sin(want) * r)
            local gy = groundAt(p)
            if gy then
                local wp = Vector3.new(p.X, gy, p.Z)
                if clearLine(from, wp) then return wp, math.deg(step) end
            end
        end
        return nil
    end

    local function rotated(dir, a)
        return Vector3.new(dir.X * math.cos(a) - dir.Z * math.sin(a), 0,
                           dir.X * math.sin(a) + dir.Z * math.cos(a))
    end

    local function detourAround(from, to)
        if clearLine(from, to) then return nil end
        local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
        local dist = flat.Magnitude
        if dist < 1 then return nil end
        local dir = flat.Unit
        local r = math.max(dist * K.AROUND_FRAC, K.AROUND_MIN_R)
        for _, deg in ipairs(K.AROUND_ANGLES) do
            for _, sign in ipairs({ 1, -1 }) do
                local wp = from + rotated(dir, math.rad(deg) * sign) * r
                local gy = groundAt(Vector3.new(wp.X, from.Y, wp.Z))
                if gy then
                    wp = Vector3.new(wp.X, gy, wp.Z)
                    if clearLine(from, wp) and clearLine(wp, to) then return wp, deg * sign end
                end
            end
        end
        for _, deg in ipairs(K.AROUND_ANGLES) do
            for _, sign in ipairs({ 1, -1 }) do
                local wp = from + rotated(dir, math.rad(deg) * sign) * r
                local gy = groundAt(Vector3.new(wp.X, from.Y, wp.Z))
                if gy and clearLine(from, Vector3.new(wp.X, gy, wp.Z)) then
                    return Vector3.new(wp.X, gy, wp.Z), deg * sign
                end
            end
        end
        return nil
    end

    ---------- hazards ----------

    local function hazardParts()
        local now = os.clock()
        if S.hazards and (now - S.hazardsAt) < K.HAZARD_CACHE then return S.hazards end
        local out = {}
        local folder = workspace:FindFirstChild("BossHazards")
        if folder then
            for _, d in ipairs(folder:GetDescendants()) do
                if d:IsA("BasePart") then out[#out + 1] = d end
            end
        end
        local a = arena()
        if a then
            for _, name in ipairs({ "SlamIndicator", "SlamArmHitbox", "SlamRestHitbox" }) do
                local d = a:FindFirstChild(name)
                if d and d:IsA("BasePart") then out[#out + 1] = d end
            end
        end
        local bh = workspace:FindFirstChild("BossBlackHole")
        if bh and bh:IsA("BasePart") then out[#out + 1] = bh end
        S.hazards, S.hazardsAt = out, now
        return out
    end

    local function hazardClear(part)
        local n = part.Name
        if n == "BossBlackHole" then return K.HOLE_CLEAR end
        if n:find("Slam") then return K.SLAM_CLEAR end
        if n:find("Ring") then return K.RING_CLEAR end
        return K.HAZARD_CLEAR
    end

    local function inHazard(part, pos, extra)
        local clear = hazardClear(part) + (extra or 0)
        if part:IsA("Part") and part.Shape == Enum.PartType.Cylinder then
            local flat = Vector3.new(pos.X - part.Position.X, 0, pos.Z - part.Position.Z)
            return flat.Magnitude <= part.Size.Y * 0.5 + clear
        end
        local rel = part.CFrame:PointToObjectSpace(pos)
        local half = part.Size * 0.5
        return math.abs(rel.X) <= half.X + clear
            and math.abs(rel.Z) <= half.Z + clear
            and math.abs(rel.Y) <= half.Y + 8
    end

    -- With dodging off nothing may refuse a move on account of a hazard
    -- either: this gate stopped V3.1 reaching the crystal until it was tied
    -- to the same switch.
    local function inAnyHazard(pos, extra)
        if not K.DODGE then return nil end
        for _, part in ipairs(hazardParts()) do
            if inHazard(part, pos, extra) then return part end
        end
        return nil
    end

    local function dodgeScore(spot, here)
        local aim = S.aim
        if typeof(aim) == "Vector3" then
            return Vector3.new(spot.X - aim.X, 0, spot.Z - aim.Z).Magnitude
        end
        return Vector3.new(spot.X - here.X, 0, spot.Z - here.Z).Magnitude
    end

    -- Publishes S.dodge for the mover; never moves the character itself.
    local function dodgeHazards()
        if not K.DODGE then S.dodge = nil return false end
        local h = ch.root()
        if not h then return false end
        local parts = hazardParts()
        if #parts == 0 then S.dodge = nil return false end
        local hit = nil
        for _, part in ipairs(parts) do
            if inHazard(part, h.Position) then hit = part break end
        end
        if not hit then S.dodge = nil return false end

        local here = h.Position
        local cands = {}
        if hit:IsA("Part") and hit.Shape == Enum.PartType.Cylinder then
            local want = hit.Size.Y * 0.5 + K.HOLE_CLEAR + 4
            for i = 0, K.DODGE_POINTS - 1 do
                local ang = (2 * math.pi / K.DODGE_POINTS) * i
                cands[#cands + 1] = Vector3.new(hit.Position.X + math.cos(ang) * want, here.Y,
                                                hit.Position.Z + math.sin(ang) * want)
            end
        else
            local rel = hit.CFrame:PointToObjectSpace(here)
            local half = hit.Size * 0.5
            local clear = hazardClear(hit) + 4
            local outX = (rel.X >= 0 and 1 or -1) * (half.X + clear)
            local outZ = (rel.Z >= 0 and 1 or -1) * (half.Z + clear)
            local cf = hit.CFrame
            cands[#cands + 1] = cf:PointToWorldSpace(Vector3.new(rel.X, rel.Y, outZ))
            cands[#cands + 1] = cf:PointToWorldSpace(Vector3.new(outX, rel.Y, rel.Z))
            cands[#cands + 1] = cf:PointToWorldSpace(Vector3.new(rel.X, rel.Y, -outZ))
            cands[#cands + 1] = cf:PointToWorldSpace(Vector3.new(-outX, rel.Y, rel.Z))
            cands[#cands + 1] = cf:PointToWorldSpace(Vector3.new(outX, rel.Y, outZ))
            cands[#cands + 1] = cf:PointToWorldSpace(Vector3.new(-outX, rel.Y, outZ))
        end

        local best, bestScore
        for _, spot in ipairs(cands) do
            if onFloor(spot) and not inAnyHazard(spot, 0) then
                local scr = dodgeScore(spot, here)
                if not bestScore or scr < bestScore then best, bestScore = spot, scr end
            end
        end
        if not best then
            for _, spot in ipairs(cands) do
                if onFloor(spot) then
                    local scr = dodgeScore(spot, here)
                    if not bestScore or scr < bestScore then best, bestScore = spot, scr end
                end
            end
        end
        if not best then
            local mid = arenaCentre()
            if mid then
                local inward = Vector3.new(mid.X - here.X, 0, mid.Z - here.Z)
                if inward.Magnitude > 1 then
                    best = here + inward.Unit * math.min(inward.Magnitude, 60)
                end
            end
        end
        if not best then return true end
        S.dodge = { pos = best }
        stats.dodges = stats.dodges + 1
        return true
    end

    -- ORBIT, DO NOT RETREAT. The black hole follows at 40% of our speed; slide
    -- tangentially round the target at swing radius and it trails behind.
    local function orbitPoint(tpos, reach)
        local h = ch.root()
        local bh = workspace:FindFirstChild("BossBlackHole")
        if not h or not bh or not bh:IsA("BasePart") then return nil end
        local toHole = Vector3.new(bh.Position.X - h.Position.X, 0, bh.Position.Z - h.Position.Z)
        if toHole.Magnitude > K.ORBIT_TRIGGER then return nil end
        local rel = Vector3.new(h.Position.X - tpos.X, 0, h.Position.Z - tpos.Z)
        if rel.Magnitude < 1 then rel = Vector3.new(1, 0, 0) end
        local ang = math.atan2(rel.Z, rel.X)
        local r = math.max(reach, 6)
        local function at(a)
            return Vector3.new(tpos.X + math.cos(a) * r, h.Position.Y, tpos.Z + math.sin(a) * r)
        end
        local p1, p2 = at(ang + K.ORBIT_STEP), at(ang - K.ORBIT_STEP)
        local function fromHole(p)
            return Vector3.new(p.X - bh.Position.X, 0, p.Z - bh.Position.Z).Magnitude
        end
        local first, second = p1, p2
        if fromHole(p2) > fromHole(p1) then first, second = p2, p1 end
        if onFloor(first) then return first end
        if onFloor(second) then return second end
        return nil
    end

    ---------- the character ----------

    -- A bat is a Tool the game marks IsBat (the gear item is "Bat [X1]" now);
    -- the name test stays as a fallback for older builds. V3.1 monolith
    -- BX.isBatTool - V3_RELEASE only had the name test.
    local function isBatTool(t)
        return t:IsA("Tool") and (t:GetAttribute("IsBat") == true or t.Name:find("Bat") ~= nil)
    end

    local function equipBat()
        local char = ch.get()
        if not char then return nil end
        for _, t in ipairs(char:GetChildren()) do
            if isBatTool(t) then return t end
        end
        local bp = svc.LocalPlayer:FindFirstChild("Backpack")
        if bp then
            for _, t in ipairs(bp:GetChildren()) do
                if isBatTool(t) then
                    -- EQUIP IT THE WAY THE GAME DOES. Reparenting the tool from
                    -- an executor does not reliably fire Tool.Equipped for the
                    -- bat's own controller, and that controller refuses every
                    -- swing it did not see equipped (CLIENT_TOOL_NOT_EQUIPPED)
                    -- - the "auto equip does nothing". Humanoid:EquipTool is
                    -- the real path; reparenting stays only as the fallback.
                    local hum = ch.humanoid()
                    local ok = hum and pcall(function() hum:EquipTool(t) end)
                    if not ok or t.Parent ~= char then t.Parent = char end
                    log.info("equipped %s", t.Name)
                    return t
                end
            end
        end
        return nil
    end

    -- ONE SWING, STRAIGHT TO THE SERVER. V3.1 monolith BX.batSwing.
    --
    -- Read out of Shared.Modules.BatController.Client: a click runs
    --     Tool.Activated -> _onActivated -> (equipped? gameplay area? 0.6s
    --     debounce? not ragdolled?) -> Remotes.BatSwing.Trigger:FireServer(
    --         target, "<UserId>:<seq>:<serverTimeMs>")
    -- where `target` is the nearest PLAYER in range and nil otherwise - the
    -- boss and crystals are resolved by the server from where we stand.
    -- bat:Activate() only works if the controller saw the tool equipped, which
    -- on some executors it never does: "I have to click to attack". So the
    -- swing is fired exactly as the controller fires it, and the bat's own hit
    -- animation is played so it still looks like a swing.
    local batSeq, batAnimTrack, batAnimFor = 0, nil, nil
    local function batSwing(bat)
        local ok = pcall(function()
            local rem = net.find("RE/BatSwing/Trigger")
            assert(rem, "no BatSwing remote")
            batSeq = batSeq + 1
            rem:FireServer(nil, ("%d:%d:%d"):format(svc.LocalPlayer.UserId, batSeq,
                math.floor(workspace:GetServerTimeNow() * 1000)))
        end)
        if not ok then
            pcall(function() bat:Activate() end)
            return
        end
        pcall(function()
            local anim = bat:FindFirstChild("HitAnim")
            local hum = ch.humanoid()
            local animator = hum and hum:FindFirstChildOfClass("Animator")
            if anim and animator then
                if batAnimFor ~= animator then
                    batAnimTrack = animator:LoadAnimation(anim)
                    batAnimFor = animator
                end
                batAnimTrack:Play()
            end
            local snd = bat:FindFirstChild("Slash", true)
            if snd and snd:IsA("Sound") then snd:Play() end
        end)
    end

    -- Put the humanoid back in a state that can act. V3.1 readyAfterRagdoll.
    local function readyAfterRagdoll()
        local hm, h = ch.humanoid(), ch.root()
        if not hm or not h then return end
        hm.PlatformStand = false
        hm.Sit = false
        hm.AutoRotate = true
        local st = hm:GetState()
        if st == Enum.HumanoidStateType.Physics
           or st == Enum.HumanoidStateType.PlatformStanding
           or st == Enum.HumanoidStateType.FallingDown
           or st == Enum.HumanoidStateType.Ragdoll
           or st == Enum.HumanoidStateType.Seated then
            hm:ChangeState(Enum.HumanoidStateType.GettingUp)
        end
        h.AssemblyLinearVelocity = Vector3.zero
        h.AssemblyAngularVelocity = Vector3.zero
    end

    -- The slam and the black hole knock with an impulse that is integrated
    -- inside one physics step. Remove only what our own walk could not have
    -- produced; leave downward motion so gravity and the void watch work.
    local function antiFling()
        local h, hum = ch.root(), ch.humanoid()
        if not h or not hum then return end
        local v = h.AssemblyLinearVelocity
        local flat = (v * Vector3.new(1, 0, 1)).Magnitude
        local cap = math.max((hum.WalkSpeed or 16) * K.FLING_MULT, 120)
        if v.Y <= K.FLING_UP and flat <= cap then return end
        local keep = Vector3.zero
        if flat > 0.001 then
            keep = (v * Vector3.new(1, 0, 1)).Unit * math.min(flat, hum.WalkSpeed or 16)
        end
        h.AssemblyLinearVelocity = Vector3.new(keep.X, math.min(v.Y, 0), keep.Z)
        h.AssemblyAngularVelocity = Vector3.zero
        stats.flings = stats.flings + 1
        every("fling", 2, "cancelled a launch (up %.0f, flat %.0f) - %d so far",
            v.Y, flat, stats.flings)
    end

    local function targetReach(part)
        if typeof(part) == "Vector3" then return K.REACH end
        if not (part and part:IsA("BasePart")) then return K.REACH end
        local half = math.max(part.Size.X, part.Size.Z) * 0.5
        return math.max(K.REACH, half + K.SURFACE_MARGIN)
    end

    ---------- the target ----------

    -- Returns target, kind: a BasePart for a crystal, a Vector3 for a hand.
    -- nil when there is genuinely nothing to hit, and the caller HOLDS.
    local function target()
        local h = ch.root()
        if not h then return nil end
        local ph = phase()
        if not ph then return nil end

        if ph == "crystals" then
            local a = arena()
            local towers = a and a:FindFirstChild("CrystalTowers", true)
            if not towers then return nil end
            local best, bestD
            for _, d in ipairs(towers:GetDescendants()) do
                if d:IsA("BasePart") and d.Name == "Hitbox" then
                    -- The game's own test: a missing Health attribute means the
                    -- tower is not live yet, NOT that it is full health.
                    local hp = d:GetAttribute("Health")
                    if type(hp) == "number" and hp > 0 then
                        local dist = (d.Position - h.Position).Magnitude
                        if not bestD or dist < bestD then best, bestD = d, dist end
                    end
                end
            end
            if best then return best, "crystal" end
            return nil
        end

        -- PHASE TWO: THE HANDS, AND ONLY THE HANDS. No health-bar gate: measured
        -- live, no bone ever carries a Health child while BossArmHits still
        -- climbed. Proximity is the signal.
        local b = bossModel()
        if not b then return nil end
        local myY = h.Position.Y
        local low, lowD, any, anyD, anyUp
        for _, bn in ipairs(K.HAND_BONES) do
            local bone = b:FindFirstChild(bn, true)
            if bone and bone:IsA("Bone") then
                local pos
                pcall(function() pos = bone.TransformedWorldCFrame.Position end)
                pos = pos or bone.WorldPosition
                if pos then
                    -- DO NOT CHASE AN ARM THAT IS LEAVING: it retracts to the
                    -- body, and the body sits over the pit.
                    local prev = S.handY[bn]
                    S.handY[bn] = pos.Y
                    local rising = prev ~= nil and (pos.Y - prev) > K.HAND_RISE_EPS
                    if not rising then
                        local flat = Vector3.new(pos.X - h.Position.X, 0, pos.Z - h.Position.Z).Magnitude
                        if not anyD or flat < anyD then any, anyD, anyUp = pos, flat, pos.Y - myY end
                        if (pos.Y - myY) <= K.HAND_REACH_Y and (not lowD or flat < lowD) then
                            low, lowD = pos, flat
                        end
                    end
                end
            end
        end

        -- STAND WHERE THERE IS FLOOR, EVEN IF THE HAND IS NOT OVER ANY.
        local function landable(p)
            if not p then return nil end
            if onFloor(p) and clearLine(h.Position, p) then return p end
            local wp, ang = ringWaypoint(h.Position, p)
            if not wp then wp, ang = detourAround(h.Position, p) end
            if wp then
                every("pit", 2, "pit in the way - walking round the ring (%+.0f deg)", ang or 0)
                return wp
            end
            return lastSolidToward(h.Position, p)
        end

        low = landable(low)
        if any and (anyUp or 0) <= K.HAND_CHASE_Y then any = landable(any) else any = nil end

        -- HOLD THE HAND WE PICKED, or the walk wanders between arms.
        local now = os.clock()
        if S.handPick and (now - S.handPickAt) < K.HAND_COMMIT then
            local keep = S.handPick
            if (low and (low - keep).Magnitude < 220) or (any and (any - keep).Magnitude < 220) then
                return keep, "hand"
            end
        end
        if low then
            S.handPick, S.handPickAt = low, now
            return low, "hand"
        end
        if any then
            S.handPick, S.handPickAt = any, now
            return any, "hand"
        end
        if anyUp then
            every("high", 2, "hands up: nearest is %.0f studs up (need <= %d) - holding for the slam",
                anyUp, K.HAND_REACH_Y)
        end
        return nil
    end

    ---------- leaving ----------

    local function leaveArena()
        local a = arena()
        local exit = a and a:FindFirstChild("BossArenaLeaveTeleport", true)
        local part = exit and (exit:IsA("BasePart") and exit
            or exit:FindFirstChild("Hitbox", true)
            or exit:FindFirstChildWhichIsA("BasePart", true))
        local c = ch.get()
        if not (part and c) then return false end
        c:MoveTo(part.Position + Vector3.new(0, 3, 0))
        return true
    end

    ---------- noclip, arena only ----------

    local function setNoclip(on)
        if on == S.noclipped then return end
        S.noclipped = on
        if on then
            mov.noclip(true)
        elseif not auto.isRunning() then
            -- The steal owns its own noclip while it runs; never pull it out
            -- from under a carry.
            mov.noclip(false)
        end
    end

    ---------- THE MOVER: one writer of the character's CFrame ----------

    local function moverStep(dt)
        if not S.inArena or auto.isRunning() then return end
        -- Do not write CFrame onto a character the server is still spawning:
        -- that race is the post-respawn snapback. Anti-fling still runs below
        -- once settled; during the hold the server owns the position.
        if S.settleUntil and os.clock() < S.settleUntil then return end
        antiFling()

        local dodging = S.dodge ~= nil
        local goal = S.dodge or S.goal
        if not goal then return end
        local h, hum = ch.root(), ch.humanoid()
        if not h or not hum then return end

        -- DEAD MAN'S GUARD: no ground under us outranks every other goal.
        if groundAt(h.Position) then
            S.lastSolid = h.Position
        elseif S.lastSolid then
            local back = Vector3.new(S.lastSolid.X - h.Position.X, 0, S.lastSolid.Z - h.Position.Z)
            if back.Magnitude > 1 then
                local st2 = math.min(back.Magnitude, math.min(dt, K.MAX_DT) * K.STEP_SPEED, K.MAX_STEP)
                local nb = h.Position + back.Unit * st2
                local gyb = groundAt(nb) or S.lastSolid.Y
                hum.PlatformStand = false
                h.CFrame = CFrame.lookAt(Vector3.new(nb.X, gyb, nb.Z), Vector3.new(nb.X, gyb, nb.Z) + back.Unit)
                h.AssemblyLinearVelocity = Vector3.zero
                stats.rescues = stats.rescues + 1
                every("rescue", 1, "no ground underneath - walking back to solid")
            end
            return
        end

        local flat = Vector3.new(goal.pos.X - h.Position.X, 0, goal.pos.Z - h.Position.Z)
        local reach = dodging and 0 or (goal.reach or K.REACH)
        local left = flat.Magnitude - reach
        if left <= K.MOVE_ARRIVE then
            if dodging then S.dodge = nil else S.goal = nil end
            return
        end

        -- STUCK ON SCENERY: watch progress, not the step.
        local now = os.clock()
        if not S.stuckBest or left < S.stuckBest - 2 then S.stuckBest, S.stuckSince = left, now end
        local dirUse = flat.Unit
        if S.stuckSince and (now - S.stuckSince) > K.STUCK_TIME then
            S.stuckFlip = not S.stuckFlip
            local sgn = S.stuckFlip and 1 or -1
            dirUse = Vector3.new(-flat.Unit.Z * sgn, 0, flat.Unit.X * sgn)
            S.stuckSince, S.stuckBest = now, nil
            every("stuck", 2, "not making progress - sidestepping")
        end

        local step = math.min(left, math.min(dt, K.MAX_DT) * K.STEP_SPEED, K.MAX_STEP)
        local nxt = h.Position + dirUse * step
        if not dodging and inAnyHazard(nxt, 0) then return end

        local function groundFor(dir, dist)
            local probe = h.Position + dir * dist
            return groundAt(Vector3.new(probe.X, h.Position.Y, probe.Z))
        end
        local gy = groundFor(dirUse, step)

        -- NOCLIP MEANS THE FLOOR CANNOT CATCH US EITHER. Remember the last
        -- real floor and refuse to write below it.
        if gy then
            S.arenaFloorY = gy
        elseif S.arenaFloorY and h.Position.Y < S.arenaFloorY - K.SINK_MAX then
            h.CFrame = CFrame.new(h.Position.X, S.arenaFloorY, h.Position.Z)
            h.AssemblyLinearVelocity = Vector3.zero
            every("sink", 2, "dropped below the floor - lifted back onto it")
            return
        end

        if not gy then
            -- NO GROUND THERE = DO NOT GO THERE, BUT DO NOT GIVE UP: follow the
            -- rim round until the way ahead is solid again.
            local found = nil
            for _, deg in ipairs(K.RIM_SWEEP) do
                for _, sgn in ipairs(S.rimSide == -1 and { -1, 1 } or { 1, -1 }) do
                    local d = rotated(dirUse, math.rad(deg * sgn))
                    local g = groundFor(d, step)
                    if g and groundFor(d, step + K.RIM_LOOKAHEAD) then
                        found, gy = d, g
                        S.rimSide = sgn
                        break
                    end
                end
                if found then break end
            end
            if not found then
                if dodging then S.dodge = nil else S.goal = nil end
                return
            end
            dirUse = found
            nxt = h.Position + dirUse * step
            S.stuckSince = now
            every("rim", 2, "hole in the way - following the rim round")
        end

        -- EASE THE HEIGHT, FRAME-RATE INDEPENDENTLY.
        local curY = h.Position.Y
        local k = 1 - math.exp(-dt / K.Y_TAU)
        local dest = Vector3.new(nxt.X, curY + (gy - curY) * k, nxt.Z)
        hum.PlatformStand = false
        hum:Move(Vector3.zero, false)
        h.CFrame = CFrame.lookAt(dest, dest + flat.Unit)
        h.AssemblyLinearVelocity = Vector3.new(0, h.AssemblyLinearVelocity.Y, 0)
        h.AssemblyAngularVelocity = Vector3.zero
    end

    ---------- THE FIGHT TICK ----------

    local function fightTick()
        -- Arena entry/exit edge: noclip on inside, off outside; a fresh
        -- fight's bookkeeping each time we go in.
        local inside = inArena()
        if inside ~= S.inArena then
            S.inArena = inside
            setNoclip(inside)
            S.goal, S.dodge, S.aim, S.trackPos, S.handPick = nil, nil, nil, nil, nil
            S.lastSolid, S.arenaFloorY, S.left = nil, nil, false
            S.voidAnchor, S.voidMisses = nil, 0
            if inside then
                -- Fresh (or freshly re-entered) character: put the humanoid in
                -- a movable state and hold the mover until the server has
                -- stopped positioning it. See K.RESPAWN_SETTLE.
                S.settleUntil = os.clock() + K.RESPAWN_SETTLE
                readyAfterRagdoll()
            end
            log.info(inside and "in the arena - fighting" or "left the arena")
        end
        if not inside or auto.isRunning() or S.left then return end
        -- The character is still settling after entry/respawn: no target, no
        -- goal, no CFrame writes yet.
        if S.settleUntil and os.clock() < S.settleUntil then return end

        -- NO BAT MUST NOT MEAN NO MOVEMENT. V3_RELEASE returned here without
        -- a bat - before the target was picked and before the goal was set -
        -- so the character stood still in the arena. The bat is a gear item
        -- with a use count now ("Bat [X1]", Uses=1, CooldownActive), so it can
        -- be used up or simply not there. The fight carries on without one -
        -- moving, targeting - and only the swing waits for a bat. The game
        -- added RF/Codex/AskWearFieldBat alongside that change; ask it for
        -- the arena bat now and then, and log the answer.
        local bat = equipBat()
        if not bat then
            if os.clock() - (S.batAskedAt or 0) > 5 then
                S.batAskedAt = os.clock()
                local okW, msgW = net.call("RF/Codex/AskWearFieldBat")
                log.info("no bat - AskWearFieldBat -> %s %s", tostring(okW), tostring(msgW or ""))
            end
        elseif S.batFor ~= bat then
            S.batFor = bat
            task.wait(K.EQUIP_SETTLE)
        end

        -- Physics state = IsRagdolled = swing refused. None turns up in the
        -- arena too and is not a state the humanoid can act from.
        local hmz = ch.humanoid()
        if hmz then
            local stt = hmz:GetState()
            if hmz.PlatformStand or stt == Enum.HumanoidStateType.Physics
               or stt == Enum.HumanoidStateType.PlatformStanding
               or stt == Enum.HumanoidStateType.None then
                readyAfterRagdoll()
            end
        end

        local inHaz = dodgeHazards()

        -- Dead boss: claim and get out. Then stand down until we leave.
        local snap = boss.snapshot()
        if snap and tonumber(snap.BossHealth) and snap.BossHealth <= 0 then
            stats.kills = stats.kills + 1
            log.info("boss dead - claiming and walking out")
            local n = boss.claimMilestones()
            log.info("claimed %d milestone(s)", n)
            S.left = leaveArena()
            S.goal, S.aim = nil, nil
            return
        end

        S.phase = phase()
        local part, kind = target()
        if not part then
            S.goal, S.aim, S.kind = nil, nil, nil
            if S.idlePhase ~= S.phase then
                S.idlePhase = S.phase
                log.info("nothing to hit (phase=%s) - holding position", tostring(S.phase or "spawning"))
            end
            return
        end
        S.idlePhase, S.kind = false, kind

        local tpos = (typeof(part) == "Vector3") and part or part.Position
        local h = ch.root()
        if not h then return end
        local reach = targetReach(part)

        -- FLAT DISTANCE, NOT 3D: a crystal's hitbox sits 27 studs up.
        local flatDir = Vector3.new(tpos.X - h.Position.X, 0, tpos.Z - h.Position.Z)
        local d = flatDir.Magnitude

        -- DO NOT WALK INTO THE SLAM TO REACH SOMETHING - but not forever.
        local stand = h.Position + (d > 0.001 and flatDir.Unit * math.max(d - reach, 0) or Vector3.zero)
        if inAnyHazard(Vector3.new(stand.X, h.Position.Y, stand.Z), 0) then
            S.waitAt = S.waitAt or os.clock()
            if os.clock() - S.waitAt < K.WAIT_MAX then
                S.goal = nil
                return
            end
        else
            S.waitAt = nil
        end

        S.aim = tpos

        -- SWING TOLERANCE > ARRIVAL TOLERANCE, OR THEY DEADLOCK.
        if d > reach + K.SWING_SLACK then
            -- SMOOTH THE THING WE ARE CHASING: a hand's bone jitters.
            local smooth = tpos
            if kind == "hand" then
                local prev = S.trackPos
                if prev and (prev - tpos).Magnitude < K.TRACK_JUMP then
                    smooth = prev:Lerp(tpos, 1 - math.exp(-K.TICK / K.TRACK_TAU))
                end
                S.trackPos = smooth
            else
                S.trackPos = nil
            end
            S.goal = { pos = smooth, reach = reach }
            return
        end

        -- IN RANGE. Keep circling if the hole is on us.
        local orbit = orbitPoint(tpos, reach)
        if orbit then
            S.goal = { pos = orbit, reach = 0 }
            every("orbit", 3, "black hole is on us - orbiting the target")
        else
            S.goal = nil
        end
        if inHaz then return end

        -- IN RANGE: STAND STILL, THE CAMERA IS WATCHING. Turn only when the
        -- aim is genuinely off, and ease into it.
        local flat = Vector3.new(tpos.X - h.Position.X, 0, tpos.Z - h.Position.Z)
        if flat.Magnitude > 0.1 then
            local wantDir = flat.Unit
            local haveDir = h.CFrame.LookVector * Vector3.new(1, 0, 1)
            haveDir = haveDir.Magnitude > 0.001 and haveDir.Unit or wantDir
            if haveDir:Dot(wantDir) < K.AIM_COS then
                local cur = h.CFrame
                h.CFrame = cur:Lerp(CFrame.lookAt(cur.Position, cur.Position + wantDir), K.AIM_EASE)
            end
        end
        -- The swing is the only part that needs a bat - and one that is off
        -- cooldown, or the game swallows it.
        if not bat or not bat.Parent then return end
        if bat:GetAttribute("CooldownActive") == true then return end
        if os.clock() - S.lastSwingAt < K.SWING_GAP then return end
        S.lastSwingAt = os.clock()
        batSwing(bat)
        stats.swings = stats.swings + 1
        if stats.swings % 20 == 1 then
            log.info("swinging at the %s (%d swings)", tostring(kind), stats.swings)
        end
    end

    ---------- THE VOID WATCH, arena half ----------

    local function voidTick()
        if not S.inArena then return end
        local c, h = ch.get(), ch.root()
        if not (c and h) then return end
        local pos = h.Position
        local gy = groundAt(pos)
        if gy and math.abs(pos.Y - gy) <= K.MAX_RISE then
            S.voidAnchor = Vector3.new(pos.X, gy, pos.Z)
            S.voidMisses = 0
            return
        end
        -- ONE MISSED RAYCAST IS NOT A FALL. It needs a run of misses AND real
        -- evidence: well below the last ground we stood on.
        if not gy then S.voidMisses = S.voidMisses + 1 else S.voidMisses = 0 end
        local falling = S.voidAnchor and (pos.Y < S.voidAnchor.Y - K.VOID_DROP_PROOF)
        if S.voidMisses >= K.VOID_MISSES and falling then
            S.voidMisses = 0
            local back = S.voidAnchor or arenaCentre()
            if back then
                stats.voidSaves = stats.voidSaves + 1
                h.AssemblyLinearVelocity = Vector3.zero
                h.AssemblyAngularVelocity = Vector3.zero
                c:MoveTo(back)
                h.CFrame = CFrame.new(back)
                log.info("voidwatch: off the floor at (%.0f, %.0f, %.0f) - pulled back (#%d)",
                    pos.X, pos.Y, pos.Z, stats.voidSaves)
                task.wait(0.3)
            end
        end
    end

    -- Public helpers for the Player Steal worker. They reuse the exact same
    -- Bat controller path as Auto Fight: Humanoid:EquipTool + BatSwing/Trigger.
    -- No second bat implementation is created in the UI worker.
    M.equipBat = equipBat
    M.swingBat = batSwing
    M.readyAfterRagdoll = readyAfterRagdoll

    ---------- the status line ----------

    -- Held data only; the Event tab's painter calls this once a second.
    function M.status()
        if not enabled then return { title = "Auto fight", body = "off" } end
        if auto.isRunning() then
            return { title = "Auto fight", body = "ON  \u{B7}  waiting for Auto Steal to finish" }
        end
        if not S.inArena then
            local held = boss.held()
            if held and held.Open == true then
                return { title = "Auto fight", body = boss.autoEnterOn()
                    and "ON  \u{B7}  boss open - entering"
                    or "ON  \u{B7}  boss open - press Enter or turn on Auto enter" }
            end
            return { title = "Auto fight", body = "ON  \u{B7}  waiting for the boss world to open" }
        end
        if S.left then return { title = "Auto fight", body = "Boss dead  \u{B7}  leaving" } end
        local ph = S.phase
        if not ph then return { title = "Auto fight", body = "In the arena  \u{B7}  boss spawning" } end
        local what = S.kind and ("hitting the " .. S.kind) or "holding"
        return { title = "Auto fight",
                 body = ("Fighting  \u{B7}  %s  \u{B7}  %s  \u{B7}  %d swings"):format(ph, what, stats.swings) }
    end

    ---------- on / off ----------

    function M.setEnabled(on)
        on = on and true or false
        if on == enabled then return true end

        if not on then
            enabled = false
            if sc then sc:destroy() sc = nil end
            if S then
                S.goal, S.dodge, S.aim = nil, nil, nil
                setNoclip(false)
            end
            S = nil
            log.info("off (%d swings, %d kills this session)", stats.swings, stats.kills)
            return true
        end

        -- Reading the arena needs the boss watcher for the health snapshot.
        if not boss.isOn() then boss.setEnabled(true) end

        S = fresh()
        sc = BX.scope("features.bossfight")
        enabled = true

        sc:onFrame("mover", svc.RunService.Heartbeat, moverStep)
        sc:loop("fight", K.TICK, fightTick)
        sc:loop("void", K.VOID_GAP, voidTick)
        if K.DODGE then
            sc:loop("dodge", K.DODGE_GAP, function()
                if S.inArena then dodgeHazards() end
            end)
        end
        -- A respawn is a fresh character: forget the old one's floor, goal
        -- and bat, and let the tick re-detect the arena.
        ch.onSpawn(sc, "bossfight.respawn", function()
            if not S then return end
            -- Collision back first: the tick re-applies it if we are still
            -- inside, and a respawn on the main map must not stay noclipped.
            setNoclip(false)
            S.goal, S.dodge, S.aim, S.trackPos, S.batFor = nil, nil, nil, nil, nil
            S.lastSolid, S.arenaFloorY, S.left = nil, nil, false
            S.voidAnchor, S.voidMisses = nil, 0
            S.inArena, S.noclipped = false, false
            -- Hold the mover even if InBossArena never flips false across the
            -- death (so the fightTick entry edge does not re-fire): the fresh
            -- root still needs to settle before we write to it.
            S.settleUntil = os.clock() + K.RESPAWN_SETTLE
        end)

        log.info("on (tick %.2fs, swing %.2fs, dodge %s) - waiting for the arena",
            K.TICK, K.SWING_GAP, K.DODGE and "on" or "off")
        return true
    end

    return M
end)

BX.module("features.drscramble", function(BX)
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")

    local M = {}
    local ch = BX.require("core.character")
    local data = BX.require("core.data")
    local eventTimeText = "NOT FOUND"
    local eventSeconds = nil
    local eventActive = false
    local running = false
    local token = 0
    local currentTarget = nil
    local currentTier = "-"
    local currentHP = "-"
    local statusText = "OFF"
    local smartSearch = true
    local godMode = false -- DR protection toggle; movement is never locked
    local godScope = nil
    local godOwnsAntiDeath = false
    local attackOwnsAntiDeath = false

    local PRIORITY = {
        [10] = 1,
        [5] = 2,
        [3] = 3,
    }

    local function character()
        local p = Players.LocalPlayer
        return p and p.Character
    end

    local function rootOf(model)
        if not model then return nil end
        return model:FindFirstChild("HumanoidRootPart")
            or model.PrimaryPart
            or model:FindFirstChild("UpperTorso")
            or model:FindFirstChild("Torso")
    end

    local function parseEventSeconds(text)
        local t = tostring(text or "")
        local lower = t:lower()
        local m, sec = lower:match("(%d+)%s*m%s*(%d+)%s*s")
        if not m then
            m, sec = lower:match("(%d+)%s*min%w*%s*(%d+)%s*sec%w*")
        end
        if m then
            return tonumber(m) * 60 + tonumber(sec)
        end
        local onlyM = lower:match("(%d+)%s*m")
        if onlyM then return tonumber(onlyM) * 60 end
        local onlyS = lower:match("(%d+)%s*s")
        if onlyS then return tonumber(onlyS) end
        return nil
    end

    local function formatEventClock(seconds)
        seconds = math.max(0, math.floor(tonumber(seconds) or 0))
        local mins = math.floor(seconds / 60)
        local secs = seconds % 60
        return string.format("%dm %02ds", mins, secs)
    end

    local function readEventTimer()
        local lp = Players.LocalPlayer
        local pg = lp and lp:FindFirstChildOfClass("PlayerGui")
        if not pg then return nil, "NOT FOUND", false end

        local function isText(inst)
            return inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")
        end

        local function center(inst)
            local ok, pos, size = pcall(function()
                return inst.AbsolutePosition, inst.AbsoluteSize
            end)
            if not ok then return nil end
            return Vector2.new(pos.X + size.X * 0.5, pos.Y + size.Y * 0.5)
        end

        local function distance(a, b)
            local ca, cb = center(a), center(b)
            if not ca or not cb then return math.huge end
            return (ca - cb).Magnitude
        end

        local allTexts = {}
        local countdowns = {}
        local eventAnchors = {}

        -- Read the entire PlayerGui.  In this game the words "Event ends in"
        -- and the actual countdown can be separate TextLabels, sometimes even
        -- under different frames.  Do not require them to share the same parent.
        for _, inst in ipairs(pg:GetDescendants()) do
            if isText(inst) then
                local txt = tostring(inst.Text or "")
                local low = txt:lower()
                allTexts[#allTexts + 1] = inst

                local secs = parseEventSeconds(txt)
                if secs then
                    countdowns[#countdowns + 1] = {
                        inst = inst,
                        seconds = secs,
                        text = txt,
                    }
                end

                if low:find("event ends", 1, true)
                    or low:find("event end", 1, true)
                    or low:find("dr. scramble", 1, true)
                    or low:find("dr scramble", 1, true)
                    or low:find("scramble experiment", 1, true) then
                    eventAnchors[#eventAnchors + 1] = inst
                end
            end
        end

        if #countdowns == 0 then
            return nil, "NOT FOUND", false
        end

        local best = nil
        local bestScore = math.huge

        -- Primary method: choose the countdown physically closest to the
        -- game's "Event ends in" / Scramble label.  This handles the layout
        -- visible in the supplied screenshot where the countdown is in a
        -- separate UI object next to the flask icon.
        for _, c in ipairs(countdowns) do
            local nearest = math.huge
            for _, anchor in ipairs(eventAnchors) do
                local d = distance(c.inst, anchor)
                if d < nearest then nearest = d end
            end

            if nearest < math.huge then
                local score = nearest
                -- Prefer a meaningful event countdown over tiny unrelated
                -- timers when distances are very close.
                if c.seconds < 15 then score = score + 250 end
                if score < bestScore then
                    bestScore = score
                    best = c
                end
            end
        end

        -- Fallback for games where the anchor text is hidden/not present:
        -- the event countdown shown in the screenshot is the longer timer,
        -- while short gameplay timers (e.g. 27s) are unrelated. Prefer the
        -- longest countdown, with a small bias toward timers >= 60 seconds.
        if not best then
            table.sort(countdowns, function(a, b)
                local aLong = a.seconds >= 60
                local bLong = b.seconds >= 60
                if aLong ~= bLong then return aLong end
                return a.seconds > b.seconds
            end)
            best = countdowns[1]
        end

        local secs = math.max(0, math.floor(tonumber(best.seconds) or 0))
        local mins = math.floor(secs / 60)
        local rem = secs % 60
        return secs, string.format("in %dm %02ds", mins, rem), secs > 0
    end

    -- ================================================================
    -- AUTHORITATIVE DR. SCRAMBLE EVENT STATE
    -- Source: RE/Scramble/State (primary), with the existing BossEvent/UI
    -- readers kept only as fallbacks.  The live hierarchy shown by the user is:
    --
    -- ReplicatedStorage/Packages/Networking
    --   RF/Scramble/Request
    --   RE/Scramble/Collect
    --   RE/Scramble/Drones
    --   RE/Scramble/Drops
    --   RE/Scramble/Effect
    --   RE/Scramble/RemoveDrops
    --   RE/Scramble/State
    --
    -- We do NOT blindly Invoke RF/Scramble/Request because its argument/operation
    -- contract is not present in the supplied source. Invoking an unknown request
    -- can perform an action rather than merely read state. RE/Scramble/State is
    -- therefore the safe authoritative listener; when its payload contains
    -- Open/Active/OpensAt/ClosesAt those values are used directly.
    -- ================================================================
    local ScrambleEvent = {
        state = nil,
        receivedAt = 0,
        connected = false,
        connection = nil,
    }

    local function scrambleNumber(v)
        local n = tonumber(v)
        return n
    end

    local function lowerKey(k)
        return tostring(k):lower():gsub('[%s_%-]', '')
    end

    -- Walk the event payload defensively. This accepts nested dictionaries
    -- without assuming the exact server serializer shape.
    local function extractScrambleState(value, out, depth)
        depth = depth or 0
        if depth > 5 or value == nil then return end
        if type(value) ~= 'table' then return end

        for k, v in pairs(value) do
            local key = lowerKey(k)
            if key == 'open' or key == 'opened' or key == 'active' or key == 'isopen' then
                if type(v) == 'boolean' then out.open = v end
            elseif key == 'opensat' or key == 'openat' or key == 'startat' or key == 'startsat' then
                local n = scrambleNumber(v)
                if n then out.opensAt = n end
            elseif key == 'closesat' or key == 'closeat' or key == 'endat' or key == 'endsat' then
                local n = scrambleNumber(v)
                if n then out.closesAt = n end
            elseif key == 'remaining' or key == 'remainingseconds' or key == 'timeseconds' then
                local n = scrambleNumber(v)
                if n and n >= 0 then out.remaining = n end
            end
            if type(v) == 'table' then
                extractScrambleState(v, out, depth + 1)
            end
        end
    end

    local function installScrambleStateListener()
        if ScrambleEvent.connected then return end
        ScrambleEvent.connected = true

        task.spawn(function()
            local net = BX.require('core.net')
            local re = net.find('RE/Scramble/State')
            if not re or not re:IsA('RemoteEvent') then
                ScrambleEvent.connected = false
                return
            end

            local ok, connection = pcall(function()
                return re.OnClientEvent:Connect(function(...)
                    local args = table.pack(...)
                    local parsed = {}
                    for i = 1, args.n do
                        extractScrambleState(args[i], parsed)
                    end

                    -- Keep the raw payload too, useful for diagnostics/status.
                    ScrambleEvent.state = parsed
                    ScrambleEvent.state.raw = args
                    ScrambleEvent.receivedAt = os.clock()

                    if parsed.open ~= nil or parsed.opensAt or parsed.closesAt or parsed.remaining then
                        refreshEventTimer()
                    end
                end)
            end)

            if ok then
                ScrambleEvent.connection = connection
            else
                ScrambleEvent.connected = false
            end
        end)
    end

    local DroneWatcher = { connection = nil }

    local function installDroneWatcher()
        if DroneWatcher.connection then return end
        DroneWatcher.connection = Workspace.DescendantAdded:Connect(function(desc)
            if not running then return end
            local model = desc:IsA("Model") and desc or desc:FindFirstAncestorOfClass("Model")
            if model and (model:GetAttribute("ScrambleDroneId") ~= nil
                or tostring(model.Name):lower():sub(1, 14) == "personaldrone_") then
                -- A drone can appear before Hitbox/Health is fully replicated.
                -- Invalidate the cache and let the next scan pick it up.
                task.defer(function()
                    if running and model.Parent then
                        currentTarget = nil
                    end
                end)
            end
        end)
    end

    local function readScrambleState()
        installScrambleStateListener()
        installDroneWatcher()
        return ScrambleEvent.state
    end

    refreshEventTimer = function()
        local state = readScrambleState()

        if type(state) == 'table' then
            local nowServer = workspace:GetServerTimeNow()
            local isOpen = state.open == true
            local opensAt = tonumber(state.opensAt)
            local closesAt = tonumber(state.closesAt)
            local remaining = tonumber(state.remaining)

            if isOpen and closesAt then
                eventActive = true
                eventSeconds = math.max(0, closesAt - nowServer)
                eventTimeText = 'OPEN • closes in ' .. formatEventClock(eventSeconds)
                return eventSeconds, eventTimeText, true
            elseif not isOpen and opensAt then
                eventActive = false
                eventSeconds = math.max(0, opensAt - nowServer)
                eventTimeText = 'CLOSED • opens in ' .. formatEventClock(eventSeconds)
                return eventSeconds, eventTimeText, false
            elseif isOpen and remaining then
                eventActive = true
                eventSeconds = math.max(0, remaining)
                eventTimeText = 'OPEN • remaining ' .. formatEventClock(eventSeconds)
                return eventSeconds, eventTimeText, true
            elseif isOpen then
                eventActive = true
                eventSeconds = nil
                eventTimeText = 'OPEN • timer unavailable'
                return nil, eventTimeText, true
            end
        end

        -- Final fallback: the visible game UI scanner.
        local secs, text, active = readEventTimer()
        eventSeconds = secs
        eventTimeText = text
        eventActive = active == true
        return secs, text, eventActive
    end

    -- DR. Scramble's real drone objects are NOT required to contain a Humanoid.
    -- DroneVisual reads the following from the server-side drone model:
    --   Attribute: ScrambleDroneId
    --   Attribute: DroneState
    --   Child: Hitbox
    --   Hitbox Attribute: Health
    --   Attribute: DroneMotion
    -- Therefore the old Humanoid-only scanner could never find the actual
    -- Experiment drones. This version intentionally uses ONLY that drone
    -- signature and never falls back to Humanoids or name matching.
    local function numberAttribute(inst, names)
        if not inst then return nil end
        for _, name in ipairs(names) do
            local value = inst:GetAttribute(name)
            local n = tonumber(value)
            if n then return n end
        end
        return nil
    end

    local function droneHealthInfo(model)
        if not model or not model:IsA("Model") then return nil end

        local droneId = model:GetAttribute("ScrambleDroneId")
        local droneState = tostring(model:GetAttribute("DroneState") or "")
        local motion = model:GetAttribute("DroneMotion")
        local hitbox = model:FindFirstChild("Hitbox")

        if droneId == nil or not hitbox then
            return nil
        end

        local hp = tonumber(hitbox:GetAttribute("Health"))
        if hp == nil then
            hp = tonumber(model:GetAttribute("Health"))
        end

        -- DroneVisual treats a missing Health attribute as alive:
        --     (Hitbox:GetAttribute("Health") or 1) <= 0
        -- Do the same here.  This matters during the first replication frame,
        -- when ScrambleDroneId/Hitbox arrive before Hitbox.Health.
        local healthKnown = hp ~= nil
        if hp == nil then
            hp = 1
        end

        if hp <= 0 or droneState == "Death" then
            return nil
        end

        -- The supplied DroneVisual proves Health is stored on Hitbox. It does
        -- not expose a MaxHealth attribute, so infer the 10/5/3 tier from the
        -- current value unless an explicit max-health attribute exists.
        local maxHp = numberAttribute(hitbox, {"MaxHealth", "MaxHP", "HealthMax"})
            or numberAttribute(model, {"MaxHealth", "MaxHP", "HealthMax"})

        if not maxHp and healthKnown then
            if hp >= 9.5 then
                maxHp = 10
            elseif hp >= 4.5 then
                maxHp = 5
            else
                maxHp = 3
            end
        end

        local tier = 0
        if maxHp then
            if maxHp >= 9.5 then
                tier = 10
            elseif maxHp >= 4.5 then
                tier = 5
            else
                tier = 3
            end
        end

        return {
            hp = hp,
            maxHp = tier,
            healthKnown = healthKnown,
            hitbox = hitbox,
            droneId = droneId,
            droneState = droneState,
            motion = motion,
        }
    end

    local function tierInfo(hp, maxHp, healthKnown)
        hp = tonumber(hp) or 0
        maxHp = tonumber(maxHp) or 0
        if maxHp <= 0 or healthKnown == false then
            return 99, "HP ?/ ?", 0
        end
        local tier = 3
        if maxHp >= 9.5 then
            tier = 10
        elseif maxHp >= 4.5 then
            tier = 5
        end
        return PRIORITY[tier] or 99, string.format("%d/%d HP", math.max(0, math.floor(hp + 0.5)), tier), tier
    end

    -- STRICT DRONE-ONLY TARGETING
    -- Accept both the authoritative ScrambleDroneId signature and the live
    -- PersonalDrone_... model name used by the current event.
    local function isPersonalDroneName(model)
        if not model or not model:IsA("Model") then return false end
        local name = tostring(model.Name):lower()
        return name:sub(1, 14) == "personaldrone_"
            or name:match("^personaldrone[%s_%-]") ~= nil
    end

    local function isDroneCandidate(model)
        if not model or not model:IsA("Model") then return false end
        return model:GetAttribute("ScrambleDroneId") ~= nil
            or isPersonalDroneName(model)
    end

    local function findHitbox(model)
        if not model then return nil end
        local direct = model:FindFirstChild("Hitbox")
        if direct and direct:IsA("BasePart") then return direct end
        local nested = model:FindFirstChild("Hitbox", true)
        if nested and nested:IsA("BasePart") then return nested end
        return nil
    end

    local function numberAttribute(inst, names)
        if not inst then return nil end
        for _, name in ipairs(names) do
            local value = inst:GetAttribute(name)
            local n = tonumber(value)
            if n then return n end
        end
        return nil
    end

    local function droneHealthInfo(model)
        if not model or not model:IsA("Model") or not isDroneCandidate(model) then
            return nil
        end

        local droneId = model:GetAttribute("ScrambleDroneId") or model.Name
        local droneState = tostring(model:GetAttribute("DroneState") or "")
        local motion = model:GetAttribute("DroneMotion")
        local hitbox = findHitbox(model)
        if not hitbox then return nil end

        local hp = numberAttribute(hitbox, {"Health", "HP", "HitPoints"})
        if hp == nil then
            hp = numberAttribute(model, {"Health", "HP", "HitPoints"})
        end

        local healthKnown = hp ~= nil
        if hp == nil then hp = 1 end
        if hp <= 0 or droneState == "Death" then return nil end

        local maxHp = numberAttribute(hitbox, {"MaxHealth", "MaxHP", "HealthMax"})
            or numberAttribute(model, {"MaxHealth", "MaxHP", "HealthMax"})

        if not maxHp and healthKnown then
            if hp >= 9.5 then
                maxHp = 10
            elseif hp >= 4.5 then
                maxHp = 5
            else
                maxHp = 3
            end
        end

        local tier = 0
        if maxHp then
            if maxHp >= 9.5 then
                tier = 10
            elseif maxHp >= 4.5 then
                tier = 5
            else
                tier = 3
            end
        end

        return {
            hp = hp,
            maxHp = tier,
            healthKnown = healthKnown,
            hitbox = hitbox,
            droneId = droneId,
            droneState = droneState,
            motion = motion,
        }
    end

    local function tierInfo(hp, maxHp, healthKnown)
        hp = tonumber(hp) or 0
        maxHp = tonumber(maxHp) or 0
        if maxHp <= 0 or healthKnown == false then
            return 99, "HP ?/ ?", 0
        end
        local tier = 3
        if maxHp >= 9.5 then
            tier = 10
        elseif maxHp >= 4.5 then
            tier = 5
        end
        return PRIORITY[tier] or 99,
            string.format("%d/%d HP", math.max(0, math.floor(hp + 0.5)), tier),
            tier
    end

    local function targetAlive(target)
        if not target or not target.drone or not target.model or not target.model.Parent then
            return false
        end
        local info = droneHealthInfo(target.model)
        if not info then return false end
        target.hp = info.hp
        target.maxHp = info.maxHp
        target.healthKnown = info.healthKnown
        target.hitbox = info.hitbox
        target.droneId = info.droneId
        target.droneState = info.droneState
        target.motion = info.motion
        return info.hp > 0 and info.droneState ~= "Death"
    end

    local function refreshTargetHealth(target)
        if not target or not target.drone then return false end
        local info = droneHealthInfo(target.model)
        if not info then return false end
        target.hp = info.hp
        target.maxHp = info.maxHp
        target.healthKnown = info.healthKnown
        target.hitbox = info.hitbox
        target.droneId = info.droneId
        target.droneState = info.droneState
        target.motion = info.motion
        target.rank, target.hpText, target.hpTier =
            tierInfo(info.hp, info.maxHp, info.healthKnown)
        return true
    end

    -- Global search: no distance/region gate, so PersonalDrone_... objects can
    -- be found from the Safe Zone.
    local function findTarget()
        local best, bestRank, bestDistance = nil, math.huge, math.huge
        local myChar = character()
        local myRoot = myChar and rootOf(myChar)
        local myPos = myRoot and myRoot.Position

        -- Scan the live DR. Scramble visual container first.  The current event
        -- uses PersonalDrone_* models here, while some builds also expose the
        -- authoritative ScrambleDroneId on the same model.
        local candidates = {}
        local seen = {}
        local visualRoot = Workspace:FindFirstChild("ScrambleLocalVisuals")
        if visualRoot then
            for _, inst in ipairs(visualRoot:GetDescendants()) do
                if inst:IsA("Model") and not seen[inst] then
                    seen[inst] = true
                    candidates[#candidates + 1] = inst
                end
            end
        end

        -- Global fallback catches PersonalDrone_* when the container is named
        -- differently or when the model is temporarily outside that folder.
        for _, inst in ipairs(Workspace:GetDescendants()) do
            if inst:IsA("Model") and not seen[inst] then
                seen[inst] = true
                candidates[#candidates + 1] = inst
            end
        end

        for _, inst in ipairs(candidates) do
            if isDroneCandidate(inst) then
                local info = droneHealthInfo(inst)

                if info
                    and info.hp > 0
                    and info.droneState ~= "Death"
                    and info.hitbox
                    and info.hitbox:IsA("BasePart") then

                    local root = rootOf(inst) or info.hitbox
                    if root and inst ~= myChar then
                        local rank, hpText, hpTier =
                            tierInfo(info.hp, info.maxHp, info.healthKnown)
                        local dist = myPos
                            and (root.Position - myPos).Magnitude
                            or math.huge

                        if rank < bestRank
                            or (rank == bestRank and dist < bestDistance) then
                            best = {
                                model = inst,
                                root = root,
                                rank = rank,
                                hpText = hpText,
                                hpTier = hpTier,
                                hp = info.hp,
                                maxHp = info.maxHp,
                                healthKnown = info.healthKnown,
                                hitbox = info.hitbox,
                                drone = true,
                                droneId = info.droneId,
                                droneState = info.droneState,
                                motion = info.motion,
                            }
                            bestRank = rank
                            bestDistance = dist
                        end
                    end
                end
            end
        end

        return best
    end

    local function getAttackTool()
        local ch = character()
        if not ch then return nil end

        local preferred = {
            "bat", "scrambler", "sword", "weapon", "katana", "blade", "club"
        }

        for _, wanted in ipairs(preferred) do
            for _, child in ipairs(ch:GetChildren()) do
                if child:IsA("Tool") and tostring(child.Name):lower():find(wanted, 1, true) then
                    return child
                end
            end
        end

        for _, child in ipairs(ch:GetChildren()) do
            if child:IsA("Tool") then return child end
        end

        local backpack = Players.LocalPlayer and Players.LocalPlayer:FindFirstChildOfClass("Backpack")
        if backpack then
            for _, wanted in ipairs(preferred) do
                for _, child in ipairs(backpack:GetChildren()) do
                    if child:IsA("Tool") and tostring(child.Name):lower():find(wanted, 1, true) then
                        return child
                    end
                end
            end
            for _, child in ipairs(backpack:GetChildren()) do
                if child:IsA("Tool") then return child end
            end
        end

        return nil
    end

    local function equipAndAttack()
        local char = character()
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not (char and hum and hum.Health > 0) then
            return false, "Character/Humanoid unavailable"
        end

        -- Use the same BatController path already present in this hub.
        -- The old DR worker relied only on Tool:Activate(), but this game's bat
        -- controller can refuse Activate() when it did not observe the equip.
        -- The controller's real path is Humanoid:EquipTool +
        -- RE/BatSwing/Trigger.
        local okBoss, boss = pcall(function()
            return BX.require("features.bossfight")
        end)
        if okBoss and boss then
            local bat
            local okEquip, equipped = pcall(function()
                return boss.equipBat()
            end)
            if okEquip and equipped then
                bat = equipped
            end

            if bat and bat.Parent == char then
                local okSwing = pcall(function()
                    boss.swingBat(bat)
                end)
                if okSwing then
                    return true
                end
            end
        end

        -- Fallback for builds where the bossfight module is unavailable.
        local tool = getAttackTool()
        if not tool then return false, "Bat/attack tool not found" end
        if tool.Parent ~= char then
            local okEquip = pcall(function() hum:EquipTool(tool) end)
            if not okEquip then
                return false, "Failed to equip attack tool"
            end
            task.wait(0.08)
        end
        local activated = pcall(function() tool:Activate() end)
        if not activated then
            return false, "Attack activation failed"
        end
        return true
    end

    -- SAFE DRONE MOVEMENT
    -- Uses the same movement engine as Auto Steal instead of a hard PivotTo.
    local movement = BX.require("features.movement")
    local attackMoveMode = "GLIDE"
    local ATTACK_MOVE_SPEEDS = {
        GLIDE = 1050,
        FLY = 1050,
    }

    local function waitForAttackCharacter(timeout)
        local deadline = os.clock() + (tonumber(timeout) or 1.5)
        repeat
            local char = ch.get()
            local root = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if char and root and hum and hum.Health > 0 then
                return char, root, hum
            end
            task.wait(0.03)
        until os.clock() >= deadline or not running
        return nil, nil, nil
    end

    -- TELEPORT/APPROACH IS A SEPARATE STATE FROM ATTACK.
    -- The old loop did movement.travel() immediately before every attack. If
    -- movement was still settling while the next attack tick arrived, the two
    -- jobs could fight over the same HumanoidRootPart. This version has one
    -- movement gate and one attack gate; an attack never starts a second move.
    local teleportBusy = false
    local attackBusy = false
    local teleportedTargetId = nil
    local teleportGeneration = 0

    local function moveToTargetSafely(target)
        if teleportBusy then
            return false, "teleport already in progress"
        end
        if not target or not target.root or not target.root.Parent then
            return false, "target root missing"
        end

        teleportBusy = true
        teleportGeneration = teleportGeneration + 1
        local myMove = teleportGeneration

        local _, attackRoot = waitForAttackCharacter(1.5)
        if not attackRoot then
            teleportBusy = false
            return false, "no character to move"
        end

        local mode = ATTACK_MOVE_SPEEDS[attackMoveMode] and attackMoveMode or "GLIDE"
        local speed = ATTACK_MOVE_SPEEDS[mode]
        local destination = target.root.Position + Vector3.new(0, 2.5, 0)

        local ok, info = movement.travel{
            to = destination,
            speed = speed,
            arrive = 5,
            carrying = false,
            keepY = true,
            tag = "dr scramble teleport " .. mode,
            cancel = function()
                return (not running)
                    or (not BX.alive())
                    or myMove ~= teleportGeneration
                    or (not targetAlive(target))
            end,
        }

        teleportBusy = false

        if not ok then
            return false, info and info.reason or "safe movement failed"
        end
        if not targetAlive(target) then
            return false, "target changed during teleport"
        end

        teleportedTargetId = tostring(target.droneId or target.model:GetDebugId())
        return true, mode
    end

    function M.teleportToDrone()
        local target = currentTarget
        if not targetAlive(target) then
            target = findTarget()
            currentTarget = target
        end
        if not target then return false, "No drone target" end
        local ok, why = moveToTargetSafely(target)
        if ok then
            statusText = "TELEPORT • " .. tostring(target.model.Name)
        end
        return ok, why
    end

    function M.setMovementMode(mode)
        mode = tostring(mode or "GLIDE"):upper()
        if not ATTACK_MOVE_SPEEDS[mode] then
            return false, "Unknown movement mode: " .. mode
        end
        attackMoveMode = mode
        return true, attackMoveMode
    end

    function M.getMovementMode()
        return attackMoveMode
    end

    -- GOD MODE / CHARACTER LIFECYCLE SAFETY
    -- Preserves DR setGodMode/isGodMode. This layer does not rewrite Humanoid
    -- Health/MaxHealth or physics every frame. Server-authoritative damage
    -- remains authoritative.
    local function applyGodToCharacter(char)
        if not godScope or godScope.dead or not char then return end
        pcall(function() char:SetAttribute("YOKUDO_GodMode", true) end)
    end

    local function setGodModeInternal(on)
        on = on == true
        if on == godMode and ((on and godScope) or not on) then return true end
        godMode = on
        if godScope then godScope:destroy(); godScope = nil end
        local char = ch.get()
        if not on then
            if char then pcall(function() char:SetAttribute("YOKUDO_GodMode", false) end) end
            if godOwnsAntiDeath then
                pcall(function() BX.require("features.antideath").disarm() end)
                godOwnsAntiDeath = false
            end
            return true
        end
        godScope = BX.scope("features.drscramble.god")
        ch.onSpawn(godScope, "godmode.rearm", function(newChar)
            task.defer(function()
                if godMode and godScope and godScope:alive() then applyGodToCharacter(newChar) end
            end)
        end)
        applyGodToCharacter(char)
        return true
    end

    function M.setGodMode(on) return setGodModeInternal(on) end
    function M.isGodMode() return godMode end

    -- EVENT LOCATION TELEPORTS ARE FULLY SEPARATE FROM AUTO ATTACK.
    -- Auto Attack only scans/attacks DR. Scramble drones. It never moves to a
    -- map location on enable. These helpers are used only by the manual
    -- "Teleport to Event Location" control below.
    local function normalizeAreaName(value)
        return tostring(value or "")
            :lower()
            :gsub("[%s_%-]", "")
            :gsub("[^%w]", "")
    end

    local KNOWN_EVENT_AREAS = {
        "Abyss Ocean",
        "Cherry Blossom",
        "Cosmic",
        "Desert",
        "Forest",
        "Jungle",
        "Lake",
        "Prehistoric",
        "Snow",
        "Titan Temple",
        "Volcano",
        "Angel",
    }

    local AREA_ALIASES = {
        ["obyss ocean"] = "Abyss Ocean",
        ["abyss ocean"] = "Abyss Ocean",
        ["obyss_ocean"] = "Abyss Ocean",
        ["abyss_ocean"] = "Abyss Ocean",
        ["obyss-ocean"] = "Abyss Ocean",
        ["abyss-ocean"] = "Abyss Ocean",
        ["angel"] = "Angel",
    }

    local function canonicalAreaName(value)
        local raw = tostring(value or "")
        local alias = AREA_ALIASES[raw:lower()]
        if alias then return alias end
        local key = normalizeAreaName(raw)
        for _, name in ipairs(KNOWN_EVENT_AREAS) do
            if normalizeAreaName(name) == key then
                return name
            end
        end
        return raw
    end

    -- LOCATION DETECTION CACHE
    -- Never walk Workspace:GetDescendants() on the 0.75s UI loop. That was
    -- the main source of spikes when "ACTIVE DRONE • <location>" was enabled.
    local eventAreaCache = {}
    local eventAreaCacheAt = 0
    local eventAreaCacheTTL = 8.0
    local function rebuildEventAreaCache(force)
        local now = os.clock()
        if not force and now - eventAreaCacheAt < eventAreaCacheTTL then
            return eventAreaCache
        end
        local cache = {}
        pcall(function()
            local dir = data.areasDir()
            for id, entry in pairs(dir or {}) do
                local name = type(id) == "string" and canonicalAreaName(id) or ""
                if name ~= "" then cache[normalizeAreaName(name)] = {name = name, pos = nil, source = "data"} end
                if type(entry) == "table" then
                    local n = canonicalAreaName(entry._id or entry.Id or entry.DisplayName or entry.Name)
                    if n ~= "" then cache[normalizeAreaName(n)] = cache[normalizeAreaName(n)] or {name = n, pos = nil, source = "data"} end
                end
            end
        end)
        -- One bounded workspace scan per cache lifetime, not every detection.
        pcall(function()
            for _, inst in ipairs(Workspace:GetDescendants()) do
                local key = normalizeAreaName(inst.Name)
                if key ~= "" then
                    for _, known in ipairs(KNOWN_EVENT_AREAS) do
                        if normalizeAreaName(known) == key then
                            local pos = positionFromInstance and positionFromInstance(inst) or nil
                            local e = cache[key] or {name = known, pos = nil, source = "workspace area"}
                            if pos then e.pos = pos end
                            e.name = known
                            e.source = "workspace area"
                            cache[key] = e
                            break
                        end
                    end
                end
            end
        end)
        eventAreaCache = cache
        eventAreaCacheAt = now
        return cache
    end

    local function areaOptions()
        local found = {}
        local eggAreas = {}
        local workspaceNames = {}

        local function add(name)
            name = canonicalAreaName(name)
            if name == "" then return end
            found[name] = true
        end

        -- Prefer the game's own Area directory. This automatically picks up
        -- newly added event locations without another hardcoded patch.
        pcall(function()
            local dir = data.areasDir()
            for id, entry in pairs(dir or {}) do
                if type(id) == "string" then add(id) end
                if type(entry) == "table" then
                    add(entry._id or entry.Id or entry.DisplayName or entry.Name)
                end
            end
        end)

        -- Read the live sources once, not once per known area.
        pcall(function()
            local eggs = BX.require("features.eggs")
            for _, egg in ipairs(eggs.list() or {}) do
                local id = tostring(egg.areaId or "")
                if id ~= "" then
                    eggAreas[normalizeAreaName(id)] = true
                end
            end
        end)

        pcall(function()
            for key in pairs(rebuildEventAreaCache(false)) do
                workspaceNames[key] = true
            end
        end)

        -- Keep the locations verified in this build available even if the
        -- Data.Areas module is temporarily unavailable.
        for _, name in ipairs(KNOWN_EVENT_AREAS) do
            local wanted = normalizeAreaName(name)
            if eggAreas[wanted] or workspaceNames[wanted] then
                add(name)
            end
        end

        local out = {}
        for name in pairs(found) do
            out[#out + 1] = name
        end
        table.sort(out, function(a, b)
            local ak, bk = normalizeAreaName(a), normalizeAreaName(b)
            if ak == "abyssocean" then return true end
            if bk == "abyssocean" then return false end
            return a < b
        end)
        return out
    end

    local positionFromInstance

    local function inferDroneArea(model)
        if not model or not model:IsA("Model") then return nil, "no drone model" end

        local attributeNames = {
            "AreaId", "areaId", "Area", "area", "Location", "LocationName",
            "EventLocation", "EventArea", "Zone", "ZoneId", "World", "Map"
        }
        for _, inst in ipairs({model, model:FindFirstChild("Hitbox")}) do
            if inst then
                for _, attr in ipairs(attributeNames) do
                    local value = inst:GetAttribute(attr)
                    if value ~= nil and tostring(value) ~= "" then
                        local canonical = canonicalAreaName(value)
                        if normalizeAreaName(canonical) ~= "" then
                            return canonical, "drone attribute " .. attr
                        end
                    end
                end
            end
        end

        local cursor = model.Parent
        while cursor and cursor ~= Workspace do
            local key = normalizeAreaName(cursor.Name)
            if key ~= "" then
                for _, known in ipairs(KNOWN_EVENT_AREAS) do
                    if normalizeAreaName(known) == key then
                        return known, "drone ancestor"
                    end
                end
            end
            cursor = cursor.Parent
        end

        local root = rootOf(model) or findHitbox(model)
        local dronePos = root and root.Position
        if dronePos then
            local best, bestDist

            -- Cached event-area anchors. This is intentionally read-only here.
            -- Rebuilding them is the expensive operation and is rate-limited.
            local cache = rebuildEventAreaCache(false)
            for _, anchor in pairs(cache) do
                if anchor.pos then
                    local dist = (anchor.pos - dronePos).Magnitude
                    if not bestDist or dist < bestDist then
                        best, bestDist = anchor, dist
                    end
                end
            end

            -- Egg data is already maintained by features.eggs; use it as a
            -- lightweight live anchor without scanning Workspace again.
            pcall(function()
                local eggs = BX.require("features.eggs")
                for _, egg in ipairs(eggs.list() or {}) do
                    if egg.areaId and typeof(egg.pos) == "Vector3" then
                        local dist = (egg.pos - dronePos).Magnitude
                        if not bestDist or dist < bestDist then
                            best = {
                                name = canonicalAreaName(egg.areaId),
                                pos = egg.pos,
                                source = "live egg"
                            }
                            bestDist = dist
                        end
                    end
                end
            end)

            if best and bestDist <= 3000 then
                return best.name, best.source .. " nearest " .. math.floor(bestDist) .. " studs"
            end
        end

        return nil, "drone area unresolved"
    end

    function M.detectActiveDroneLocation()
        local target = currentTarget
        if not targetAlive(target) then
            target = findTarget()
        end
        if not target or not target.model then
            return false, "No active DR. Scramble drone"
        end

        local area, via = inferDroneArea(target.model)
        if not area then
            return false, via or "Drone location unresolved", target
        end
        return true, area, target, via
    end

    positionFromInstance = function(inst)
        if not inst then return nil end
        if inst:IsA("BasePart") then return inst.Position end
        if inst:IsA("Model") then
            local ok, pivot = pcall(function() return inst:GetPivot() end)
            if ok and typeof(pivot) == "CFrame" then return pivot.Position end
        end
        return nil
    end

    local function resolveEventAreaPosition(areaName)
        local wanted = normalizeAreaName(canonicalAreaName(areaName))
        if wanted == "" then
            return nil, "Event location not selected"
        end

        -- 1) Prefer a live egg in the requested area. Egg positions are already
        -- resolved from the game's own area/slot data and are not hardcoded.
        local viaEgg
        pcall(function()
            local eggs = BX.require("features.eggs")
            for _, egg in ipairs(eggs.list() or {}) do
                if normalizeAreaName(egg.areaId) == wanted
                    and typeof(egg.pos) == "Vector3" then
                    viaEgg = egg.pos
                    break
                end
            end
        end)
        if viaEgg then return viaEgg + Vector3.new(0, 3, 0), "egg area" end

        -- 2) Prefer an exact named area/model/marker in Workspace.
        local cached = rebuildEventAreaCache(false)[wanted]
        if cached and cached.pos then
            return cached.pos + Vector3.new(0, 3, 0), cached.source or "workspace area"
        end

        -- Only a manual teleport is allowed to force a fresh area scan.
        local exact
        pcall(function()
            rebuildEventAreaCache(true)
            local fresh = eventAreaCache[wanted]
            exact = fresh and fresh.pos
        end)
        if exact then return exact + Vector3.new(0, 3, 0), "workspace area (refreshed)" end

        return nil, "Event location not found: " .. tostring(areaName)
    end

    local function flyGlideToEventArea(areaName)
        local destination, via = resolveEventAreaPosition(areaName)
        if typeof(destination) ~= "Vector3" then
            return false, via
        end

        local mode = ATTACK_MOVE_SPEEDS[attackMoveMode] and attackMoveMode or "GLIDE"
        local speed = ATTACK_MOVE_SPEEDS[mode]

        local ok, info = movement.travel{
            to = destination,
            speed = speed,
            arrive = 8,
            carrying = false,
            keepY = true,
            tag = "dr scramble event location " .. tostring(areaName) .. " " .. mode,
            cancel = function()
                return not BX.alive()
            end,
        }

        if not ok then
            return false, info and info.reason or "Event location travel failed"
        end

        return true, ("%s • %s"):format(tostring(areaName), tostring(via))
    end

    function M.eventLocationOptions()
        return areaOptions()
    end

    function M.teleportToEventLocation(areaName)
        local canonical = canonicalAreaName(areaName)
        return flyGlideToEventArea(canonical)
    end

    -- Public state API consumed by the DR. Scramble tab.
    -- The previous repair exposed setEnabled() but accidentally omitted these
    -- accessors, causing the UI to fall into its generic "MODULE ERROR" state
    -- before Auto Attack could even be toggled.
    function M.isRunning()
        return running == true
    end

    function M.isSmartSearch()
        return smartSearch == true
    end

    function M.setSmartSearch(on)
        smartSearch = on == true
        return true
    end

    function M.status()
        local target = currentTarget
        local targetName = "NONE"
        local hpText = currentHP or "-"

        if target and target.model and target.model.Parent then
            targetName = tostring(target.model.Name)
            if target.hpText then hpText = target.hpText end
        end

        return {
            on = running == true,
            running = running == true,
            eventTime = eventTimeText or "NOT FOUND",
            eventActive = eventActive == true,
            smartSearch = smartSearch == true,
            body = statusText or (running and "SCANNING" or "OFF"),
            target = targetName,
            hp = hpText,
            tier = currentTier or "-",
        }
    end

    function M.setEnabled(on)
        if not on then
            running = false
            token = token + 1
            currentTarget = nil
            currentTier = "-"
            currentHP = "-"
            statusText = "OFF"
            teleportBusy = false
            attackBusy = false
            teleportedTargetId = nil
            teleportGeneration = teleportGeneration + 1
            setGodModeInternal(false)
            if attackOwnsAntiDeath and not godOwnsAntiDeath then
                pcall(function()
                    BX.require("features.antideath").disarm()
                end)
                attackOwnsAntiDeath = false
            end
            return true
        end

        if running then return true end

        local auto = BX.require("features.autosteal")
        if auto.isRunning() then
            return false, "Turn Auto Steal OFF before using DR. Scramble Auto Attack"
        end

        token = token + 1
        local myToken = token
        running = true

        -- Auto Attack owns a dedicated AntiDeath arm for the whole attack run.
        -- God Mode may also arm it; in that case this feature does not take
        -- ownership and therefore will not disarm the user's existing arm.
        local antiDeath = BX.require("features.antideath")
        if not antiDeath.isArmed() then
            antiDeath.arm()
            attackOwnsAntiDeath = true
        else
            attackOwnsAntiDeath = false
        end

        setGodModeInternal(true)

        pcall(function() installScrambleStateListener() end)
        pcall(function() refreshEventTimer() end)

        task.spawn(function()
            local nextAttack = 0
            local nextScan = 0

            while running and myToken == token and BX.alive() do
                local now = os.clock()

                if now >= nextScan then
                    refreshEventTimer()
                end

                if now >= nextScan
                    or not targetAlive(currentTarget) then

                    currentTarget = findTarget()
                    nextScan = now + 0.10

                    if currentTarget then
                        refreshTargetHealth(currentTarget)
                        currentTier = tostring(currentTarget.hpTier or "-")
                        currentHP = currentTarget.hpText
                        statusText = "TARGET • " .. currentTarget.model.Name .. " • " .. currentHP
                    else
                        currentTier = "-"
                        currentHP = "-"
                        statusText = "SCANNING • DRONE ONLY • not found"
                    end
                end

                if currentTarget and not currentTarget.drone then
                    currentTarget = nil
                end

                if targetAlive(currentTarget) then
                    refreshTargetHealth(currentTarget)
                    currentHP = currentTarget.hpText
                    currentTier = tostring(currentTarget.hpTier or "-")

                    if now >= nextAttack and not attackBusy and not teleportBusy then
                        -- SEPARATE TELEPORT FROM ATTACK:
                        -- 1) teleport/approach only when the target changes or we
                        --    are genuinely far away;
                        -- 2) once in range, attack without starting another move.
                        local target = currentTarget
                        local valid = targetAlive(target)
                            and target.hitbox
                            and target.hitbox:IsA("BasePart")
                            and target.root
                            and target.root.Parent

                        if valid then
                            local charRoot = ch.root()
                            local targetId = tostring(target.droneId or target.model:GetDebugId())
                            local distance = charRoot and (charRoot.Position - target.root.Position).Magnitude or math.huge

                            if teleportedTargetId ~= targetId or distance > 12 then
                                local moved, moveWhy = moveToTargetSafely(target)
                                if not moved then
                                    statusText = "TELEPORT FAILED • " .. tostring(moveWhy)
                                    currentTarget = nil
                                else
                                    statusText = "TELEPORTED • " .. target.model.Name
                                end
                            else
                                attackBusy = true
                                local okAttack, why = equipAndAttack()
                                attackBusy = false
                                if okAttack then
                                    statusText = "ATTACK • " .. target.model.Name
                                else
                                    statusText = "ATTACK FAILED • " .. tostring(why)
                                end
                            end

                            task.wait(0.10)

                            if not targetAlive(target) then
                                currentTarget = nil
                                teleportedTargetId = nil
                                statusText = "NEXT DRONE • scanning globally"
                            end
                        else
                            currentTarget = nil
                            teleportedTargetId = nil
                        end

                        nextAttack = os.clock() + 0.22
                    end
                end

                task.wait(0.04)
            end

            if myToken == token then
                running = false
                if attackOwnsAntiDeath and not godOwnsAntiDeath then
                    pcall(function() antiDeath.disarm() end)
                    attackOwnsAntiDeath = false
                end
                statusText = "OFF"
            end
        end)

        return true
    end

    return M
end)


-- ===================== SAEGRR HUB MAIN UI =====================
do
Players = game:GetService("Players")
TweenService = game:GetService("TweenService")
RunService = game:GetService("RunService")
UserInputService = game:GetService("UserInputService")
player = Players.LocalPlayer
playerGui = player:WaitForChild("PlayerGui")

    -- Build the window FIRST.  A feature module is allowed to fail without
    -- preventing the GUI from appearing.
oldGui = playerGui:FindFirstChild("MainGui")
    if oldGui then pcall(function() oldGui:Destroy() end) end

gui = Instance.new("ScreenGui")
    gui.Name = "MainGui"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 999999
    gui.Enabled = true
    gui.Parent = playerGui

main = Instance.new("Frame")
    main.Name = "MainWindow"
    -- Prevent content below the header from escaping the window when
    -- minimized. The minimized state must show ONLY the header.
    main.ClipsDescendants = true
    -- Compact default size: still fully usable, but no longer dominates the screen.
    main.Size = UDim2.fromOffset(560, 370)
    main.Position = UDim2.new(0.5, -280, 0.5, -185)
    main.BackgroundColor3 = Color3.fromRGB(7, 5, 13)
    main.BackgroundTransparency = 0.08
    main.BorderSizePixel = 0
    main.Active = true
    main.Visible = true
    main.Parent = gui

    -- Responsive scale: the compact 700x450 design automatically fits
    -- smaller Roblox mobile screens instead of being clipped off-screen.
uiScale = Instance.new("UIScale", main)

    -- Free window resizing: drag the purple handle in the bottom-right corner.
    -- The limits prevent the content from becoming unusably tiny/huge.
resizeConstraint = Instance.new("UISizeConstraint")
    local resizeMinNormal = Vector2.new(500, 330)
    local resizeMaxNormal = Vector2.new(760, 520)
    resizeConstraint.MinSize = resizeMinNormal
    resizeConstraint.MaxSize = resizeMaxNormal
    resizeConstraint.Parent = main
    function fitHubToViewport()
        local cam = workspace.CurrentCamera
        if not cam then return end
        local vp = cam.ViewportSize
        uiScale.Scale = math.clamp(math.min(vp.X / 560, vp.Y / 370), 0.68, 1)
    end
    fitHubToViewport()
    pcall(function()
        workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitHubToViewport)
    end)

    function safeRequire(name, fallback)
        local ok, result = pcall(function() return BX.require(name) end)
        if ok and result ~= nil then return result end
        warn("[VIP DELS HUB] module failed: " .. tostring(name) .. " / " .. tostring(result))
        return fallback
    end

local dev = BX.require("core.device")

filter = safeRequire("features.farm.filter", {
        areaOptions=function() return {} end, rarityOptions=function() return {} end,
        setAreas=function() end, setRarities=function() end, setTargetBy=function() end,
        matchCount=function() return 0 end,
    })
hold = safeRequire("features.farm.treadmill_on", {
        setEnabled=function() return false, "Treadmill module unavailable" end,
    })
auto = safeRequire("features.autosteal", {
        isRunning=function() return false end, setOptions=function() return false end,
        getNightState=function() return nil, "autosteal unavailable" end,
    })

-- Instant Grab is enabled explicitly whenever an automatic egg-farm worker
-- is armed. It uses the normal ProximityPrompt path and only removes the
-- client-side HoldDuration; the grab module restores original values on OFF.
grab = safeRequire("features.grab", {
        setInstantGrab=function() end,
        instantGrabActive=function() return false end,
    })

-- Extreme FPS renderer optimizer. It never deletes gameplay instances; it only
-- disables cosmetic effects / shadows and lowers mesh render fidelity, with a
-- complete property restore when switched OFF.
fpsFeature = safeRequire("features.fps", {
        setEnabled=function() return false end,
        isOn=function() return false end,
        stats=function() return {} end,
    })


helpFriendsOn = false
extremeFpsOn = false
antiGuardOn = false
alwaysCarryOn = false
mobileFastCarryOn = true

function setAllAutoFarmInstantGrab(on)
    pcall(function()
        if grab and type(grab.setInstantGrab) == "function" then
            grab.setInstantGrab(on == true)
        end
    end)
end

    -- UI callbacks must never assume the AutoSteal API exists.  This also
    -- protects against a stale/partially-loaded generation after re-execute.
    function safeAutoSetOptions(src, opts)
        opts = opts or {}
        -- Farm, Rarity and Combo all use this helper. Combo delegates to the
        -- rarity worker, so one switch covers every automatic farm path.
        opts.returnToBase = autoReturnToBase == true
        opts.helpFriends = helpFriendsOn == true
        opts.alwaysCarry = alwaysCarryOn == true
        opts.mobileFastCarry = mobileFastCarryOn == true
        if type(auto) ~= "table" or type(auto.setOptions) ~= "function" then
            pcall(function()
                local log = BX.require("boot.log").for_module("ui.autosteal")
                log.warn("setOptions unavailable; ignored update for %s", tostring(src))
            end)
            return false
        end
        local ok, err = pcall(auto.setOptions, src, opts or {})
        if not ok then
            pcall(function()
                local log = BX.require("boot.log").for_module("ui.autosteal")
                log.warn("setOptions(%s) failed: %s", tostring(src), tostring(err))
            end)
            return false
        end
        return true
    end

    local function refreshAutoMovementOptions()
        for _, src in ipairs({"farm", "rarity", "rarity_mobile", "rift", "combo", "beta"}) do
            pcall(function() safeAutoSetOptions(src, {}) end)
        end
    end

boss = safeRequire("features.boss", {
        setEnabled=function() end, isOn=function() return false end,
        enter=function() return false, "Boss module unavailable" end,
        setAutoEnter=function() end, status=function() return {body="Boss module unavailable"} end,
    })
fight = safeRequire("features.bossfight", {
        setEnabled=function() end, status=function() return {body="Auto fight unavailable"} end,
    })

    -- Start the boss watcher so the status text is live, without enabling Auto Enter/Fight.
    pcall(function() boss.setEnabled(true) end)

    -- Custom drag system is used instead of the deprecated/fragile
    -- GuiObject.Draggable property. This keeps dragging reliable even when
    -- UIScale is active and prevents child buttons from stealing the drag.
    main.Draggable = false

    -- WHITE ROTATING ACCENT AROUND THE MENU PANEL
    do
        local glow = {}
        local function addPanelGlow(obj, baseThick)
            if not obj or not obj:IsA("GuiObject") then return end
            local panelStroke = Instance.new("UIStroke")
            panelStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
            panelStroke.LineJoinMode = Enum.LineJoinMode.Round
            panelStroke.Thickness = baseThick or 2.4
            panelStroke.Transparency = 0
            panelStroke.Color = Color3.fromRGB(188, 67, 255)
            panelStroke.Parent = obj

            local gradient = Instance.new("UIGradient")
            gradient.Rotation = 0
            gradient.Color = ColorSequence.new(Color3.fromRGB(188, 67, 255))
            gradient.Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0.00, 0.85),
                NumberSequenceKeypoint.new(0.42, 0.85),
                NumberSequenceKeypoint.new(0.50, 0.00),
                NumberSequenceKeypoint.new(0.58, 0.85),
                NumberSequenceKeypoint.new(1.00, 0.85),
            })
            gradient.Parent = panelStroke

            table.insert(glow, {stroke = panelStroke, gradient = gradient, base = baseThick or 2.4})
        end

        -- Lightweight UI: no RenderStepped border animation.
        -- Keep one static accent stroke so the menu stays readable on phone.
        addPanelGlow(main, 1.0)
        for _, e in ipairs(glow) do
            if e.gradient then e.gradient.Enabled = false end
            if e.stroke then e.stroke.Transparency = 0.72 end
        end
    end
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 10)

stroke = Instance.new("UIStroke", main)
    stroke.Thickness = 1
    stroke.Transparency = 0.55
    stroke.Color = Color3.fromRGB(94, 86, 112)

gradient = Instance.new("UIGradient", stroke)
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 45, 60)),
        ColorSequenceKeypoint.new(0.25, Color3.fromRGB(188, 67, 255)),
        ColorSequenceKeypoint.new(0.5, Color3.fromRGB(120, 235, 255)),
        ColorSequenceKeypoint.new(0.75, Color3.fromRGB(188, 67, 255)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(0, 45, 60))
    })

glow = Instance.new("UIStroke", main)
    glow.Thickness = 0
    glow.Transparency = 1
    glow.Color = Color3.fromRGB(188, 67, 255)

    -- Static border; animation intentionally removed for lower CPU/GPU use.
    gradient.Enabled = false

    -- HEADER / BRANDING -----------------------------------------------------
header = Instance.new("Frame", main)
    header.Name = "Header"
    header.Size = UDim2.new(1, 0, 0, 56)
    header.Position = UDim2.fromOffset(0, 0)
    header.BackgroundColor3 = Color3.fromRGB(12, 7, 20)
    header.BackgroundTransparency = 0.10
    header.BorderSizePixel = 0
    header.ZIndex = 5

headerGradient = Instance.new("UIGradient", header)
    headerGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(15, 8, 26)),
        ColorSequenceKeypoint.new(0.55, Color3.fromRGB(31, 10, 52)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(9, 5, 16)),
    })
    headerGradient.Rotation = 15

headerDivider = Instance.new("Frame", header)
    headerDivider.Size = UDim2.new(1, -20, 0, 1)
    headerDivider.Position = UDim2.fromOffset(10, 54)
    headerDivider.BackgroundColor3 = Color3.fromRGB(188, 67, 255)
    headerDivider.BackgroundTransparency = 0.18
    headerDivider.BorderSizePixel = 0
    headerDivider.ZIndex = 8

-- STEAL AN EGG BRAND ICON --------------------------------------------------
-- Replaces the old crown with a lightweight, executor-safe egg icon drawn
-- entirely from Roblox UI primitives. No external asset ID is required.
brandIcon = Instance.new("Frame", header)
    brandIcon.Name = "StealAnEggIcon"
    brandIcon.Size = UDim2.fromOffset(34, 34)
    brandIcon.Position = UDim2.fromOffset(14, 11)
    brandIcon.BackgroundColor3 = Color3.fromRGB(164, 48, 255)
    brandIcon.BackgroundTransparency = 0.10
    brandIcon.BorderSizePixel = 0
    brandIcon.ZIndex = 7
    Instance.new("UICorner", brandIcon).CornerRadius = UDim.new(0, 16)

brandIconStroke = Instance.new("UIStroke", brandIcon)
    brandIconStroke.Color = Color3.fromRGB(255, 80, 220)
    brandIconStroke.Thickness = 1.8
    brandIconStroke.Transparency = 0.02

brandIconRGB = Instance.new("UIGradient", brandIconStroke)
    brandIconRGB.Name = "RunningRGB"
    brandIconRGB.Rotation = 0
    brandIconRGB.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 55, 105)),
        ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 210, 55)),
        ColorSequenceKeypoint.new(0.34, Color3.fromRGB(75, 255, 130)),
        ColorSequenceKeypoint.new(0.51, Color3.fromRGB(55, 225, 255)),
        ColorSequenceKeypoint.new(0.68, Color3.fromRGB(95, 95, 255)),
        ColorSequenceKeypoint.new(0.84, Color3.fromRGB(235, 65, 255)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 55, 105)),
    })

-- Egg body
brandEgg = Instance.new("Frame", brandIcon)
    brandEgg.Name = "Egg"
    brandEgg.Size = UDim2.fromOffset(16, 20)
    brandEgg.Position = UDim2.fromOffset(9, 7)
    brandEgg.BackgroundColor3 = Color3.fromRGB(255, 244, 210)
    brandEgg.BorderSizePixel = 0
    brandEgg.ZIndex = 8
    Instance.new("UICorner", brandEgg).CornerRadius = UDim.new(0.5, 0)

brandEggStroke = Instance.new("UIStroke", brandEgg)
    brandEggStroke.Color = Color3.fromRGB(255, 214, 111)
    brandEggStroke.Thickness = 1.4

-- Small top highlight gives the egg a recognizable icon silhouette.
brandEggHighlight = Instance.new("Frame", brandEgg)
    brandEggHighlight.Size = UDim2.fromOffset(6, 9)
    brandEggHighlight.Position = UDim2.fromOffset(4, 4)
    brandEggHighlight.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    brandEggHighlight.BackgroundTransparency = 0.18
    brandEggHighlight.BorderSizePixel = 0
    brandEggHighlight.ZIndex = 9
    Instance.new("UICorner", brandEggHighlight).CornerRadius = UDim.new(0.5, 0)

-- Tiny STEAL AN EGG cue inside the icon.
brandEggLabel = Instance.new("TextLabel", brandIcon)
    brandEggLabel.Name = "EggLabel"
    brandEggLabel.Size = UDim2.fromOffset(32, 7)
    brandEggLabel.Position = UDim2.fromOffset(1, 26)
    brandEggLabel.BackgroundTransparency = 1
    brandEggLabel.Text = "STEAL"
    brandEggLabel.Font = Enum.Font.GothamBlack
    brandEggLabel.TextSize = 6
    brandEggLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    brandEggLabel.TextTransparency = 0.15
    brandEggLabel.TextXAlignment = Enum.TextXAlignment.Center
    brandEggLabel.ZIndex = 9

-- RESPONSIVE BRAND HEADER -------------------------------------------------
-- One brand label prevents VIP / DELS HUB from colliding when the window
-- is resized.  The brand uses a continuous RGB/HSV color cycle.
brandTitle = Instance.new("TextLabel", header)
    brandTitle.Name = "BrandTitle"
    brandTitle.Size = UDim2.new(1, -260, 0, 30)
    brandTitle.Position = UDim2.fromOffset(58, 7)
    brandTitle.BackgroundTransparency = 1
    brandTitle.Font = Enum.Font.GothamBlack
    brandTitle.Text = "Napoleon"
    brandTitle.TextColor3 = Color3.fromRGB(220, 80, 255)
    brandTitle.TextSize = 18
    brandTitle.TextScaled = true
    brandTitle.TextXAlignment = Enum.TextXAlignment.Left
    brandTitle.TextYAlignment = Enum.TextYAlignment.Center
    brandTitle.ZIndex = 7

brandTitleConstraint = Instance.new("UITextSizeConstraint", brandTitle)
    brandTitleConstraint.MinTextSize = 14
    brandTitleConstraint.MaxTextSize = 21

-- Minimized-only header labels.  These are separate from the normal brand
-- label so the minimized state can match the compact reference exactly.
miniVIP = Instance.new("TextLabel", header)
    miniVIP.Name = "MiniVIP"
    miniVIP.Size = UDim2.fromOffset(105, 34)
    miniVIP.Position = UDim2.fromOffset(91, 9)
    miniVIP.BackgroundTransparency = 1
    miniVIP.Font = Enum.Font.GothamBlack
    miniVIP.Text = "VIP"
    miniVIP.TextColor3 = Color3.fromRGB(230, 235, 245)
    miniVIP.TextSize = 24
    miniVIP.TextXAlignment = Enum.TextXAlignment.Left
    miniVIP.TextYAlignment = Enum.TextYAlignment.Center
    miniVIP.Visible = false
    miniVIP.ZIndex = 9

miniDels = Instance.new("TextLabel", header)
    miniDels.Name = "MiniDelsHub"
    miniDels.Size = UDim2.fromOffset(180, 34)
    miniDels.AnchorPoint = Vector2.new(0.5, 0)
    miniDels.Position = UDim2.new(0.5, 0, 0, 9)
    miniDels.BackgroundTransparency = 1
    miniDels.Font = Enum.Font.GothamBlack
    miniDels.Text = "DELS HUB"
    miniDels.TextColor3 = Color3.fromRGB(220, 80, 255)
    miniDels.TextSize = 24
    miniDels.TextXAlignment = Enum.TextXAlignment.Center
    miniDels.TextYAlignment = Enum.TextYAlignment.Center
    miniDels.Visible = false
    miniDels.ZIndex = 9

miniSubtitle = Instance.new("TextLabel", header)
    miniSubtitle.Name = "MiniSubtitle"
    miniSubtitle.Size = UDim2.fromOffset(220, 18)
    miniSubtitle.Position = UDim2.fromOffset(93, 47)
    miniSubtitle.BackgroundTransparency = 1
    miniSubtitle.Font = Enum.Font.GothamBold
    miniSubtitle.Text = "Click to restore"
    miniSubtitle.TextColor3 = Color3.fromRGB(205, 190, 215)
    miniSubtitle.TextSize = 9
    miniSubtitle.TextXAlignment = Enum.TextXAlignment.Left
    miniSubtitle.TextYAlignment = Enum.TextYAlignment.Center
    miniSubtitle.Visible = false
    miniSubtitle.ZIndex = 9

made = Instance.new("TextLabel", header)
    made.Name = "BrandSubtitle"
    made.Size = UDim2.new(1, -330, 0, 13)
    made.Position = UDim2.fromOffset(59, 30)
    made.BackgroundTransparency = 1
    made.Font = Enum.Font.GothamBold
    made.Text = "STEAL AN EGG  •  VIP DELS HUB"
    made.TextColor3 = Color3.fromRGB(224, 238, 88)
    made.TextSize = 9
    made.TextScaled = true
    made.TextXAlignment = Enum.TextXAlignment.Left
    made.TextYAlignment = Enum.TextYAlignment.Center
    made.ZIndex = 7

madeConstraint = Instance.new("UITextSizeConstraint", made)
    madeConstraint.MinTextSize = 7
    madeConstraint.MaxTextSize = 11

-- Lightweight branding: static colors; no per-frame RGB loops.
versionBadge = Instance.new("TextLabel", header)
    versionBadge.Size = UDim2.fromOffset(112, 28)
    versionBadge.Position = UDim2.new(1, -292, 0, 10)
    versionBadge.BackgroundColor3 = Color3.fromRGB(25, 10, 38)
    versionBadge.BackgroundTransparency = 0.05
    versionBadge.BorderSizePixel = 0
    versionBadge.Font = Enum.Font.GothamBold
    versionBadge.Text = "Steal An Egg"
    versionBadge.TextColor3 = Color3.fromRGB(205, 235, 245)
    versionBadge.TextSize = 11
    versionBadge.ZIndex = 8
    Instance.new("UICorner", versionBadge).CornerRadius = UDim.new(0, 12)

premiumBadge = Instance.new("TextLabel", header)
    premiumBadge.Size = UDim2.fromOffset(112, 28)
    premiumBadge.Position = UDim2.new(1, -174, 0, 10)
    premiumBadge.BackgroundColor3 = Color3.fromRGB(45, 58, 43)
    premiumBadge.BorderSizePixel = 0
    premiumBadge.Font = Enum.Font.GothamBold
    premiumBadge.Text = "Executor: Real"
    premiumBadge.TextColor3 = Color3.fromRGB(255, 239, 155)
    premiumBadge.TextSize = 11
    premiumBadge.ZIndex = 8
    Instance.new("UICorner", premiumBadge).CornerRadius = UDim.new(0, 12)

headerLine = Instance.new("Frame", header)
    headerLine.Size = UDim2.new(1, -28, 0, 1)
    headerLine.Position = UDim2.fromOffset(14, 55)
    headerLine.BackgroundColor3 = Color3.fromRGB(188, 67, 255)
    headerLine.BackgroundTransparency = 0.25
    headerLine.BorderSizePixel = 0
    headerLine.ZIndex = 8

    -- ======================================================================
    -- ALL HUB TARGET NOTIFIER
    -- Compact delivery card: clean typography, larger readable fields and
    -- separate colors so egg name / rarity / weight / gen / distance never
    -- collide with each other.
    -- ======================================================================
targetNotifyFrame = Instance.new("Frame", gui)
    targetNotifyFrame.Name = "AllHubTargetNotifier"
    targetNotifyFrame.AnchorPoint = Vector2.new(0.5, 0)
    targetNotifyFrame.Position = UDim2.new(0.5, 0, 0, 72)
    -- Compact floating HUD: smaller than the main menu and readable over the game.
    targetNotifyFrame.Size = UDim2.fromOffset(350, 88)
    targetNotifyFrame.BackgroundColor3 = Color3.fromRGB(9, 8, 16)
    -- Semi-transparent so the game world remains visible behind the card.
    targetNotifyFrame.BackgroundTransparency = 0.38
    targetNotifyFrame.BorderSizePixel = 0
    targetNotifyFrame.Visible = false
    targetNotifyFrame.ZIndex = 95
    Instance.new("UICorner", targetNotifyFrame).CornerRadius = UDim.new(0, 14)

targetNotifyGradient = Instance.new("UIGradient", targetNotifyFrame)
    targetNotifyGradient.Rotation = 0
    targetNotifyGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 12, 30)),
        ColorSequenceKeypoint.new(0.52, Color3.fromRGB(10, 12, 23)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(7, 9, 17)),
    })
    targetNotifyGradient.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.42),
        NumberSequenceKeypoint.new(1, 0.50),
    })

targetNotifyStroke = Instance.new("UIStroke", targetNotifyFrame)
    targetNotifyStroke.Thickness = 1.8
    targetNotifyStroke.Transparency = 0.02
    targetNotifyStroke.Color = Color3.fromRGB(255, 80, 220)

targetNotifyStrokeRGB = Instance.new("UIGradient", targetNotifyStroke)
    targetNotifyStrokeRGB.Name = "RunningRGB"
    targetNotifyStrokeRGB.Rotation = 0
    targetNotifyStrokeRGB.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 55, 105)),
        ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 210, 55)),
        ColorSequenceKeypoint.new(0.34, Color3.fromRGB(75, 255, 130)),
        ColorSequenceKeypoint.new(0.51, Color3.fromRGB(55, 225, 255)),
        ColorSequenceKeypoint.new(0.68, Color3.fromRGB(95, 95, 255)),
        ColorSequenceKeypoint.new(0.84, Color3.fromRGB(235, 65, 255)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 55, 105)),
    })

targetNotifyAccent = Instance.new("Frame", targetNotifyFrame)
    targetNotifyAccent.Size = UDim2.fromOffset(3, 64)
    targetNotifyAccent.Position = UDim2.fromOffset(8, 12)
    targetNotifyAccent.BackgroundColor3 = Color3.fromRGB(124, 235, 255)
    targetNotifyAccent.BorderSizePixel = 0
    targetNotifyAccent.ZIndex = 96
    Instance.new("UICorner", targetNotifyAccent).CornerRadius = UDim.new(0, 3)

targetNotifyHeader = Instance.new("TextLabel", targetNotifyFrame)
    targetNotifyHeader.Size = UDim2.new(1, -28, 0, 14)
    targetNotifyHeader.Position = UDim2.fromOffset(19, 5)
    targetNotifyHeader.BackgroundTransparency = 1
    targetNotifyHeader.Font = Enum.Font.GothamBold
    targetNotifyHeader.Text = "ALL HUB TARGET  •  DELIVERY"
    targetNotifyHeader.TextColor3 = Color3.fromRGB(214, 151, 255)
    targetNotifyHeader.TextSize = 9
    targetNotifyHeader.TextXAlignment = Enum.TextXAlignment.Left
    targetNotifyHeader.ZIndex = 96

targetNotifyIconBg = Instance.new("Frame", targetNotifyFrame)
    targetNotifyIconBg.Size = UDim2.fromOffset(44, 44)
    targetNotifyIconBg.Position = UDim2.fromOffset(14, 29)
    -- RGB running frame: the image sits inside this frame so the animated
    -- rainbow remains visible around all four sides.
    targetNotifyIconBg.BackgroundColor3 = Color3.fromRGB(188, 67, 255)
    targetNotifyIconBg.BackgroundTransparency = 0
    targetNotifyIconBg.BorderSizePixel = 0
    targetNotifyIconBg.ZIndex = 96
    Instance.new("UICorner", targetNotifyIconBg).CornerRadius = UDim.new(0, 12)

targetNotifyIconRGB = Instance.new("UIGradient", targetNotifyIconBg)
    targetNotifyIconRGB.Name = "RunningRGB"
    targetNotifyIconRGB.Rotation = 0
    targetNotifyIconRGB.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 55, 105)),
        ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 210, 55)),
        ColorSequenceKeypoint.new(0.34, Color3.fromRGB(75, 255, 130)),
        ColorSequenceKeypoint.new(0.51, Color3.fromRGB(55, 225, 255)),
        ColorSequenceKeypoint.new(0.68, Color3.fromRGB(95, 95, 255)),
        ColorSequenceKeypoint.new(0.84, Color3.fromRGB(235, 65, 255)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 55, 105)),
    })

targetNotifyIconStroke = Instance.new("UIStroke", targetNotifyIconBg)
    targetNotifyIconStroke.Thickness = 1.2
    targetNotifyIconStroke.Transparency = 0.02
    targetNotifyIconStroke.Color = Color3.fromRGB(255, 255, 255)

targetNotifyIcon = Instance.new("ImageLabel", targetNotifyIconBg)
    targetNotifyIcon.Size = UDim2.new(1, -10, 1, -10)
    targetNotifyIcon.Position = UDim2.fromOffset(5, 5)
    targetNotifyIcon.BackgroundTransparency = 1
    targetNotifyIcon.Image = ""
    targetNotifyIcon.ScaleType = Enum.ScaleType.Fit
    targetNotifyIcon.ZIndex = 97
    Instance.new("UICorner", targetNotifyIcon).CornerRadius = UDim.new(0, 9)

targetNotifyIconFallback = Instance.new("TextLabel", targetNotifyIconBg)
    targetNotifyIconFallback.Size = UDim2.new(1, -10, 1, -10)
    targetNotifyIconFallback.Position = UDim2.fromOffset(5, 5)
    targetNotifyIconFallback.BackgroundTransparency = 1
    targetNotifyIconFallback.Text = "EGG"
    targetNotifyIconFallback.Font = Enum.Font.GothamBold
    targetNotifyIconFallback.TextSize = 9
    targetNotifyIconFallback.TextColor3 = Color3.fromRGB(255, 218, 126)
    targetNotifyIconFallback.TextXAlignment = Enum.TextXAlignment.Center
    targetNotifyIconFallback.TextYAlignment = Enum.TextYAlignment.Center
    targetNotifyIconFallback.ZIndex = 96

targetNotifyName = Instance.new("TextLabel", targetNotifyFrame)
    targetNotifyName.Size = UDim2.new(1, -70, 0, 20)
    targetNotifyName.Position = UDim2.fromOffset(66, 24)
    targetNotifyName.BackgroundTransparency = 1
    targetNotifyName.Font = Enum.Font.GothamBold
    targetNotifyName.Text = "Waiting for target..."
    targetNotifyName.TextColor3 = Color3.fromRGB(247, 244, 255)
    targetNotifyName.TextSize = 14
    targetNotifyName.TextXAlignment = Enum.TextXAlignment.Left
    targetNotifyName.TextTruncate = Enum.TextTruncate.AtEnd
    targetNotifyName.ZIndex = 96

targetNotifyRarity = Instance.new("TextLabel", targetNotifyFrame)
    targetNotifyRarity.Size = UDim2.new(1, -70, 0, 15)
    targetNotifyRarity.Position = UDim2.fromOffset(66, 43)
    targetNotifyRarity.BackgroundTransparency = 1
    targetNotifyRarity.Font = Enum.Font.GothamBold
    targetNotifyRarity.Text = "—   •   WEIGHT  —"
    targetNotifyRarity.TextColor3 = Color3.fromRGB(221, 226, 238)
    targetNotifyRarity.TextSize = 10.5
    targetNotifyRarity.TextXAlignment = Enum.TextXAlignment.Left
    targetNotifyRarity.TextTruncate = Enum.TextTruncate.AtEnd
    targetNotifyRarity.ZIndex = 96

targetNotifyStats = Instance.new("TextLabel", targetNotifyFrame)
    targetNotifyStats.Size = UDim2.new(1, -70, 0, 15)
    targetNotifyStats.Position = UDim2.fromOffset(66, 57)
    targetNotifyStats.BackgroundTransparency = 1
    targetNotifyStats.Font = Enum.Font.GothamBold
    targetNotifyStats.Text = "GEN  —/s   •   DIST  —"
    targetNotifyStats.TextColor3 = Color3.fromRGB(178, 238, 208)
    targetNotifyStats.TextSize = 10.5
    targetNotifyStats.TextXAlignment = Enum.TextXAlignment.Left
    targetNotifyStats.TextTruncate = Enum.TextTruncate.AtEnd
    targetNotifyStats.ZIndex = 96

targetNotifyState = Instance.new("TextLabel", targetNotifyFrame)
    targetNotifyState.Size = UDim2.new(1, -70, 0, 13)
    targetNotifyState.Position = UDim2.fromOffset(66, 72)
    targetNotifyState.BackgroundTransparency = 1
    targetNotifyState.Font = Enum.Font.GothamMedium
    targetNotifyState.Text = "DELIVERY • SAFE ZONE"
    targetNotifyState.TextColor3 = Color3.fromRGB(164, 157, 188)
    targetNotifyState.TextSize = 8.5
    targetNotifyState.TextXAlignment = Enum.TextXAlignment.Left
    targetNotifyState.ZIndex = 96

-- Lightweight target card: static accent, no animation loop.
local targetData = BX.require("core.data")

local targetIconLoadToken = 0

local function setTargetEggIcon(egg)
    -- ALL HUB TARGET uses the same authoritative asset directory as the
    -- working Egg/Pet ESP cards: data.assetsDir()[egg.assetCategory].Icon.
    -- Keep the fallback visible until Roblox actually reports IsLoaded;
    -- otherwise an invalid URI leaves the broken-image placeholder on screen.
    targetIconLoadToken = targetIconLoadToken + 1
    local myToken = targetIconLoadToken

    targetNotifyIcon.Image = ""
    targetNotifyIconFallback.Visible = true

    local rColor = Color3.fromRGB(188, 91, 255)
    local fallback = tostring(egg and (egg.name or egg.Name) or "?"):sub(1, 1):upper()
    local iconValue = nil

    local function pickIcon(v)
        if iconValue ~= nil or v == nil then return end
        local tv = typeof(v)
        if tv == "string" or tv == "number" then
            local txt = tostring(v)
            if txt ~= "" then iconValue = txt end
            return
        end
        if tv == "table" then
            for _, k in ipairs({"Icon", "Image", "ImageId", "IconId", "AssetId", "TextureId"}) do
                local x = v[k]
                if x ~= nil then
                    pickIcon(x)
                    if iconValue ~= nil then return end
                end
            end
        end
    end

    -- 1) Authoritative Data.Assets directory.
    pcall(function()
        local dir = targetData and targetData.assetsDir and targetData.assetsDir()
        local category = egg and (egg.assetCategory or egg.AssetCategory)
        local entry = category and dir and dir[category]
        if entry then
            if entry.Rarity and typeof(entry.Rarity.Color) == "Color3" then
                rColor = entry.Rarity.Color
            end
            pickIcon(entry.Icon)
            if iconValue == nil then pickIcon(entry.PetIcon) end
            if iconValue == nil then pickIcon(entry.Pet) end
        end
    end)

    -- 2) Live egg record fallbacks.
    if iconValue == nil then
        pcall(function()
            pickIcon(egg and egg.Icon)
            if iconValue == nil then pickIcon(egg and egg.icon) end
            if iconValue == nil then pickIcon(egg and egg.PetIcon) end
        end)
    end

    -- 3) Same replicated Pets directory used by the Farm pet rows.
    if iconValue == nil then
        pcall(function()
            local RS = game:GetService("ReplicatedStorage")
            local dataFolder = RS:FindFirstChild("Data")
            local assets = dataFolder and dataFolder:FindFirstChild("Assets")
            local pets = assets and (assets:FindFirstChild("Pets") or assets:FindFirstChild("pets"))
            if not pets then return end

            local petName = tostring(egg and (egg.name or egg.Name) or "")
            for _, v in ipairs(pets:GetChildren()) do
                if v.Name:lower() == petName:lower() then
                    local img = v:FindFirstChildOfClass("ImageLabel")
                        or v:FindFirstChildOfClass("ImageButton")
                    if img and img.Image ~= "" then
                        iconValue = img.Image
                        return
                    end

                    local sv = v:FindFirstChild("IconId")
                        or v:FindFirstChild("Icon")
                        or v:FindFirstChild("Thumbnail")
                    if sv and sv.Value ~= nil and tostring(sv.Value) ~= "" then
                        iconValue = tostring(sv.Value)
                        return
                    end

                    for _, d in ipairs(v:GetDescendants()) do
                        if d:IsA("ImageLabel") or d:IsA("ImageButton") then
                            if d.Image ~= "" then
                                iconValue = d.Image
                                return
                            end
                        elseif d:IsA("StringValue") or d:IsA("IntValue") then
                            local n = d.Name:lower()
                            if n:find("icon") or n:find("thumbnail") then
                                if tostring(d.Value) ~= "" then
                                    iconValue = tostring(d.Value)
                                    return
                                end
                            end
                        end
                    end
                    break
                end
            end
        end)
    end

    -- 4) Robust Roblox image loading. Do NOT hide the fallback until the
    -- ImageLabel is actually loaded. This fixes the Koi/Demon Hound/etc.
    -- broken-image placeholder seen in ALL HUB TARGET.
    if iconValue ~= nil and tostring(iconValue) ~= "" then
        task.spawn(function()
            local raw = tostring(iconValue)
            local digits = raw:match("(%d+)$")

            local candidates = {}
            local function addCandidate(x)
                if x and x ~= "" then
                    for _, old in ipairs(candidates) do
                        if old == x then return end
                    end
                    candidates[#candidates + 1] = x
                end
            end

            -- Match the proven pet-row order: direct asset id first, then
            -- thumbnail. Also preserve an already valid URI exactly as given.
            if raw:match("^rbxassetid://") or raw:match("^rbxthumb://") or raw:match("^rbxgameasset://") then
                addCandidate(raw)
            elseif digits then
                addCandidate("rbxassetid://" .. digits)
                addCandidate(("rbxthumb://type=Asset&id=%s&w=420&h=420"):format(digits))
            else
                addCandidate(raw)
            end

            -- A second asset-id form is useful when the first URI was a
            -- thumbnail/decal string that Roblox does not resolve in ImageLabel.
            if digits then
                addCandidate("rbxassetid://" .. digits)
            end

            for _, candidate in ipairs(candidates) do
                if targetIconLoadToken ~= myToken or not targetNotifyIcon.Parent then return end

                targetNotifyIcon.Image = candidate
                targetNotifyIconFallback.Visible = true

                -- Give Roblox time to resolve the texture. PreloadAsync is
                -- best-effort; IsLoaded remains the source of truth.
                pcall(function()
                    game:GetService("ContentProvider"):PreloadAsync({targetNotifyIcon})
                end)

                local deadline = os.clock() + 1.25
                repeat
                    if targetIconLoadToken ~= myToken or not targetNotifyIcon.Parent then return end
                    if targetNotifyIcon.IsLoaded then
                        targetNotifyIconFallback.Visible = false
                        return
                    end
                    task.wait(0.08)
                until os.clock() >= deadline
            end

            if targetIconLoadToken == myToken and targetNotifyIcon.Parent then
                targetNotifyIcon.Image = ""
                targetNotifyIconFallback.Visible = true
            end
        end)
    end

    -- Rarity remains visible in the text/accent; the icon frame itself is
    -- intentionally RGB-running to match the HUB header design.
    targetNotifyIconStroke.Color = Color3.fromRGB(255, 255, 255)
    targetNotifyIconBg.BackgroundColor3 = Color3.fromRGB(188, 67, 255)
    targetNotifyIconFallback.Text = fallback
    targetNotifyIconFallback.TextColor3 = rColor
end

targetNotifyToken = 0

function updateAllHubTargetNotifier(egg, stateText)
    targetNotifyToken = targetNotifyToken + 1
    if not egg or not egg.uid then
        targetNotifyFrame.Visible = false
        return
    end

    local targetName = tostring(egg.name or "Unknown Egg")
    local targetRarity = tostring(egg.rarity or "?")
    local targetKg = tonumber(egg.kg) or 0
    local targetValue = tonumber(egg.value) or 0
    local targetRate = "-"
    pcall(function()
        targetRate = tostring(eggsFeature.formatRate(targetValue or 0))
    end)

    local distanceText = "-"
    pcall(function()
        local root = BX.require("core.character").root()
        if root and egg.pos then
            distanceText = string.format("%.0f studs", (root.Position - egg.pos).Magnitude)
        end
    end)

    targetNotifyName.Text = targetName
    targetNotifyRarity.Text = targetRarity .. "   •   WEIGHT  " .. string.format("%.1f KG", targetKg)
    targetNotifyStats.Text = "GEN  " .. targetRate .. "/s   •   DIST  " .. distanceText
    targetNotifyState.Text = tostring(stateText or "DELIVERY • SAFE ZONE")

    local rarityDisplayColor = Color3.fromRGB(221, 226, 238)
    pcall(function()
        local dir = targetData.assetsDir()
        local entry = egg.assetCategory and dir and dir[egg.assetCategory]
        if entry and entry.Rarity and typeof(entry.Rarity.Color) == "Color3" then
            rarityDisplayColor = entry.Rarity.Color
        end
    end)
    targetNotifyRarity.TextColor3 = rarityDisplayColor
    targetNotifyAccent.BackgroundColor3 = rarityDisplayColor
    -- Keep the target-card border RGB-running; rarity color remains on the
    -- rarity label and accent instead of overriding the animated frame.
    targetNotifyStroke.Color = Color3.fromRGB(255, 80, 220)
    setTargetEggIcon(egg)
    targetNotifyFrame.Visible = true
    -- Semi-transparent so the game world remains visible behind the card.
    targetNotifyFrame.BackgroundTransparency = 0.38
    targetNotifyFrame.Position = UDim2.new(0.5, 0, 0, 72)
    pcall(function()
        TweenService:Create(targetNotifyFrame, TweenInfo.new(0.20, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
            Position = UDim2.new(0.5, 0, 0, 74)
        }):Play()
    end)
end

function clearAllHubTargetNotifier()
    targetNotifyToken = targetNotifyToken + 1
    targetNotifyFrame.Visible = false
end

-- Keep the last delivery card visible after the carry reaches Safe Zone or
-- the delivery finishes/fails. A new successful grab simply replaces the old
-- card. This avoids the old behaviour where the card disappeared exactly at
-- the moment the user needed the result.
function finishAllHubTargetNotifier(egg, stateText, resultKind)
    if not egg or not egg.uid then
        return
    end

    updateAllHubTargetNotifier(egg, stateText or "DELIVERY COMPLETE")

    local kind = tostring(resultKind or "info"):lower()
    if kind == "success" then
        targetNotifyState.TextColor3 = Color3.fromRGB(120, 255, 170)
        targetNotifyAccent.BackgroundColor3 = Color3.fromRGB(80, 230, 145)
        targetNotifyState.Text = tostring(stateText or "DELIVERED ✓ • SAFE ZONE")
    elseif kind == "failed" then
        targetNotifyState.TextColor3 = Color3.fromRGB(255, 125, 125)
        targetNotifyAccent.BackgroundColor3 = Color3.fromRGB(255, 75, 90)
        targetNotifyState.Text = tostring(stateText or "DELIVERY FAILED ✕")
    elseif kind == "cancelled" then
        targetNotifyState.TextColor3 = Color3.fromRGB(255, 210, 105)
        targetNotifyAccent.BackgroundColor3 = Color3.fromRGB(255, 180, 65)
        targetNotifyState.Text = tostring(stateText or "DELIVERY CANCELLED")
    else
        targetNotifyState.TextColor3 = Color3.fromRGB(164, 157, 188)
        targetNotifyState.Text = tostring(stateText or "DELIVERY COMPLETE")
    end

    targetNotifyFrame.Visible = true
end

-- Delivery-only target card: it is visible after a successful grab and stays
-- visible through the entire delivery lifecycle.
function showAllHubDeliveryTarget(egg, stateText)
    if not egg or not egg.uid then
        return
    end
    updateAllHubTargetNotifier(egg, stateText or "DELIVERY • SAFE ZONE")
end

    -- ======================================================================
    -- NOTIFICATION CENTER REMOVED
    -- The separate "ALL HUB NOTIFIER" toast UI has been removed.
    -- Keep this compatibility function because existing feature callbacks
    -- still call showNotification(); calls are intentionally no-op.
    -- The ALL HUB TARGET / DELIVERY card above is intentionally preserved.
    -- ======================================================================
    function showNotification(titleText, messageText, kind, duration)
        return true
    end

lockButton = Instance.new("TextButton", main)
    lockButton.Size = UDim2.fromOffset(28, 28)
    lockButton.Position = UDim2.new(1, -140, 0, 10)
    lockButton.BackgroundColor3 = Color3.fromRGB(20, 10, 31)
    lockButton.BorderSizePixel = 0
    lockButton.Font = Enum.Font.GothamBold
    lockButton.Text = "≡"
    lockButton.TextColor3 = Color3.fromRGB(0,190,255)
    lockButton.TextSize = 13
    Instance.new("UICorner", lockButton).CornerRadius = UDim.new(0,6)

locked = false
    lockButton.Activated:Connect(function()
        locked = not locked
        main.Active = true
        -- Custom header dragging checks the locked state itself.
        lockButton.Text = locked and "LOCKED" or "LOCK"
        lockButton.TextColor3 = locked and Color3.fromRGB(255,255,255) or Color3.fromRGB(0,190,255)
    end)

    -- Window controls: minimize hides the whole menu and leaves only a small
    -- floating logo button. Clicking that logo toggles the menu back on.
scroll = nil
sidebar = nil
contentPanel = nil
minimized = false
normalSize = main.Size
normalPosition = main.Position
local hiddenUiVisibility = {}

minButton = Instance.new("TextButton", main)
    minButton.Name = "Minimize"
    minButton.Size = UDim2.fromOffset(26, 22)
    minButton.Position = UDim2.new(1, -98, 0, 8)
    minButton.BackgroundColor3 = Color3.fromRGB(20, 10, 31)
    minButton.BorderSizePixel = 0
    minButton.Font = Enum.Font.GothamBold
    minButton.Text = "—"
    minButton.TextColor3 = Color3.fromRGB(240, 230, 245)
    minButton.TextSize = 12
    minButton.ZIndex = 30
    Instance.new("UICorner", minButton).CornerRadius = UDim.new(0, 6)

closeButton = Instance.new("TextButton", main)
    closeButton.Name = "DestroyUI"
    closeButton.Size = UDim2.fromOffset(26, 22)
    closeButton.Position = UDim2.new(1, -68, 0, 8)
    closeButton.BackgroundColor3 = Color3.fromRGB(20, 10, 31)
    closeButton.BorderSizePixel = 0
    closeButton.Font = Enum.Font.GothamBold
    closeButton.Text = "×"
    closeButton.TextColor3 = Color3.fromRGB(240, 230, 245)
    closeButton.TextSize = 14
    closeButton.ZIndex = 30
    Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 6)

    -- Floating restore icon. It is deliberately tiny so minimizing really
    -- removes the large menu from the screen instead of leaving a header bar.
    miniMenuIcon = Instance.new("TextButton", gui)
    miniMenuIcon.Name = "MiniMenuIcon"
    miniMenuIcon.AnchorPoint = Vector2.new(0, 0)
    miniMenuIcon.Position = UDim2.fromOffset(14, 82)
    miniMenuIcon.Size = UDim2.fromOffset(50, 50)
    miniMenuIcon.BackgroundColor3 = Color3.fromRGB(8, 10, 18)
    miniMenuIcon.BackgroundTransparency = 0.02
    miniMenuIcon.BorderSizePixel = 0
    miniMenuIcon.AutoButtonColor = false
    miniMenuIcon.Text = ""
    -- The launcher is ALWAYS visible. It is the permanent hide/show control.
    miniMenuIcon.Visible = true
    miniMenuIcon.ZIndex = 1000
    Instance.new("UICorner", miniMenuIcon).CornerRadius = UDim.new(0.5, 0)

    miniMenuIconStroke = Instance.new("UIStroke", miniMenuIcon)
    miniMenuIconStroke.Thickness = 2.0
    miniMenuIconStroke.Color = Color3.fromRGB(85, 220, 255)
    miniMenuIconStroke.Transparency = 0.02

    miniMenuIconScale = Instance.new("UIScale", miniMenuIcon)
    miniMenuIconScale.Scale = 1

    -- Reuse the existing logo appearance without cloning the whole header.
    miniLogo = Instance.new("Frame", miniMenuIcon)
    miniLogo.Size = UDim2.fromOffset(36, 36)
    miniLogo.AnchorPoint = Vector2.new(0.5, 0.5)
    miniLogo.Position = UDim2.fromScale(0.5, 0.5)
    miniLogo.BackgroundColor3 = Color3.fromRGB(22, 27, 43)
    miniLogo.BorderSizePixel = 0
    miniLogo.ZIndex = 251
    Instance.new("UICorner", miniLogo).CornerRadius = UDim.new(0.5, 0)

    miniLogoStroke = Instance.new("UIStroke", miniLogo)
    miniLogoStroke.Thickness = 1.5
    miniLogoStroke.Color = Color3.fromRGB(120, 240, 255)
    miniLogoStroke.Transparency = 0.04

    miniLogoText = Instance.new("TextLabel", miniLogo)
    miniLogoText.Size = UDim2.fromScale(1, 1)
    miniLogoText.BackgroundTransparency = 1
    miniLogoText.Text = "N"
    miniLogoText.Font = Enum.Font.GothamBlack
    miniLogoText.TextSize = 20
    miniLogoText.TextColor3 = Color3.fromRGB(235, 250, 255)
    miniLogoText.TextTransparency = 0.08
    miniLogoText.ZIndex = 252

    -- Premium launcher detail: a tiny egg emblem sits behind the N, with
    -- a cyan highlight and a second dark ring for a cleaner app-icon look.
    miniEgg = Instance.new("Frame", miniLogo)
    miniEgg.Name = "EggCore"
    miniEgg.Size = UDim2.fromOffset(13, 17)
    miniEgg.AnchorPoint = Vector2.new(0.5, 0.5)
    miniEgg.Position = UDim2.fromScale(0.5, 0.53)
    miniEgg.BackgroundColor3 = Color3.fromRGB(225, 240, 255)
    miniEgg.BackgroundTransparency = 0.08
    miniEgg.BorderSizePixel = 0
    miniEgg.ZIndex = 251
    Instance.new("UICorner", miniEgg).CornerRadius = UDim.new(0.5, 0)

    miniEggStroke = Instance.new("UIStroke", miniEgg)
    miniEggStroke.Thickness = 1.0
    miniEggStroke.Color = Color3.fromRGB(95, 225, 255)
    miniEggStroke.Transparency = 0.08

    miniEggHighlight = Instance.new("Frame", miniEgg)
    miniEggHighlight.Size = UDim2.fromOffset(4, 7)
    miniEggHighlight.Position = UDim2.fromOffset(2, 2)
    miniEggHighlight.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    miniEggHighlight.BackgroundTransparency = 0.10
    miniEggHighlight.BorderSizePixel = 0
    miniEggHighlight.ZIndex = 252
    Instance.new("UICorner", miniEggHighlight).CornerRadius = UDim.new(0.5, 0)

    miniLogoText.ZIndex = 253

    local function setMenuMinimized(state)
        minimized = state == true

        -- The launcher is the ONLY hub object allowed to remain visible while
        -- hidden. Save the current visibility of every other top-level GUI
        -- object so target cards/popups cannot remain on screen.
        if minimized then
            normalSize = main.Size
            normalPosition = main.Position
            table.clear(hiddenUiVisibility)

            for _, obj in ipairs(gui:GetChildren()) do
                -- IMPORTANT: ALL HUB TARGET / DELIVERY is an independent HUD.
                -- Minimizing the main menu must NOT hide this card.
                if obj:IsA("GuiObject") and obj ~= miniMenuIcon and obj ~= targetNotifyFrame then
                    hiddenUiVisibility[obj] = obj.Visible
                    obj.Visible = false
                end
            end

            -- Keep the delivery HUD alive and above the game while the menu is minimized.
            if targetNotifyFrame and targetNotifyFrame.Parent == gui then
                targetNotifyFrame.Visible = targetNotifyFrame.Visible == true
                targetNotifyFrame.ZIndex = 1005
            end
            main.Visible = false
        else
            for obj, wasVisible in pairs(hiddenUiVisibility) do
                if obj and obj.Parent == gui and obj ~= miniMenuIcon then
                    obj.Visible = wasVisible == true
                end
            end
            table.clear(hiddenUiVisibility)

            main.Size = normalSize
            main.Position = normalPosition
            main.Visible = true
            if targetNotifyFrame and targetNotifyFrame.Parent == gui then
                targetNotifyFrame.ZIndex = 95
            end
        end

        -- Never hide the launcher itself. One click/tap always toggles back.
        miniMenuIcon.Visible = true
    end

    minButton.Activated:Connect(function()
        setMenuMinimized(not minimized)
    end)

    -- DRAGGABLE MINI LAUNCHER ------------------------------------------------
    -- Click = show/hide. Drag = move the launcher anywhere on screen.
    -- The launcher position is intentionally preserved across minimize/unminimize.
    local miniLauncherDragging = false
    local miniLauncherDragged = false
    local miniLauncherStart = nil
    local miniLauncherStartPos = nil
    local miniLauncherMovedAt = 0

    miniMenuIcon.Activated:Connect(function()
        if miniLauncherDragged then
            miniLauncherDragged = false
            return
        end
        setMenuMinimized(not minimized)
    end)

    miniMenuIcon.InputBegan:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        miniLauncherDragging = true
        miniLauncherDragged = false
        miniLauncherStart = input.Position
        miniLauncherStartPos = Vector2.new(miniMenuIcon.Position.X.Offset, miniMenuIcon.Position.Y.Offset)
    end)

    UserInputService.InputChanged:Connect(function(input)
        if not miniLauncherDragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = input.Position - miniLauncherStart
        if delta.Magnitude >= 5 then
            miniLauncherDragged = true
            miniLauncherMovedAt = os.clock()
        end
        local cam = workspace.CurrentCamera
        local vp = cam and cam.ViewportSize or Vector2.new(1920,1080)
        local w, h = miniMenuIcon.AbsoluteSize.X, miniMenuIcon.AbsoluteSize.Y
        local x = math.clamp(miniLauncherStartPos.X + delta.X, 4, math.max(4, vp.X - w - 4))
        local y = math.clamp(miniLauncherStartPos.Y + delta.Y, 4, math.max(4, vp.Y - h - 4))
        miniMenuIcon.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            if miniLauncherDragging then
                miniLauncherDragging = false
                if miniLauncherDragged then
                    task.delay(0.08, function() miniLauncherDragged = false end)
                end
            end
        end
    end)

    miniMenuIcon.MouseEnter:Connect(function()
        TweenService:Create(miniMenuIcon, TweenInfo.new(0.10), {
            BackgroundTransparency = 0,
            Size = UDim2.fromOffset(52, 52),
        }):Play()
    end)
    miniMenuIcon.MouseLeave:Connect(function()
        TweenService:Create(miniMenuIcon, TweenInfo.new(0.10), {
            BackgroundTransparency = 0.02,
            Size = UDim2.fromOffset(50, 50),
        }):Play()
    end)

    -- WINDOW MOVE + RESIZE ------------------------------------------------
    -- Drag anywhere on the header (except its buttons) to move the hub.
    -- Resize from the bottom-right grip. Both systems compensate for UIScale.
    resizeGrip = Instance.new("TextButton", main)
    resizeGrip.Visible = not (dev and dev.isTouch == true)
    resizeGrip.Name = "ResizeGrip"
    resizeGrip.Size = UDim2.fromOffset(30, 30)
    resizeGrip.AnchorPoint = Vector2.new(1, 1)
    resizeGrip.Position = UDim2.new(1, -3, 1, -3)
    resizeGrip.BackgroundColor3 = Color3.fromRGB(12, 7, 22)
    resizeGrip.BackgroundTransparency = 0.18
    resizeGrip.BorderSizePixel = 0
    resizeGrip.AutoButtonColor = false
    resizeGrip.Text = "↘"
    resizeGrip.Font = Enum.Font.GothamBlack
    resizeGrip.TextSize = 16
    resizeGrip.TextColor3 = Color3.fromRGB(188, 67, 255)
    resizeGrip.ZIndex = 80
    Instance.new("UICorner", resizeGrip).CornerRadius = UDim.new(0, 8)

    resizeGripStroke = Instance.new("UIStroke", resizeGrip)
    resizeGripStroke.Thickness = 1.1
    resizeGripStroke.Color = Color3.fromRGB(120, 235, 255)
    resizeGripStroke.Transparency = 0.18

    resizeDragging = false
    resizeStartInput = nil
    resizeStartSize = nil

    resizeGrip.InputBegan:Connect(function(input)
        if locked or minimized then return end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            resizeDragging = true
            resizeStartInput = input.Position
            resizeStartSize = Vector2.new(main.Size.X.Offset, main.Size.Y.Offset)
        end
    end)

    -- Header dragging. Buttons/controls are deliberately excluded.
    local dragDragging = false
    local dragStartInput = nil
    local dragStartPos = nil

    header.Active = true
    header.InputBegan:Connect(function(input)
        if locked or minimized or resizeDragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then return end

        local point = input.Position
        local controls = {minButton, closeButton, lockButton, versionBadge, premiumBadge, brandIcon}
        for _, control in ipairs(controls) do
            if control and control.Visible then
                local pos = control.AbsolutePosition
                local size = control.AbsoluteSize
                if point.X >= pos.X and point.X <= pos.X + size.X
                    and point.Y >= pos.Y and point.Y <= pos.Y + size.Y then
                    return
                end
            end
        end

        dragDragging = true
        dragStartInput = input.Position
        dragStartPos = Vector2.new(main.Position.X.Offset, main.Position.Y.Offset)
    end)

    UserInputService.InputChanged:Connect(function(input)
        local scale = math.max(uiScale.Scale, 0.01)

        if resizeDragging and not locked and not minimized then
            if input.UserInputType ~= Enum.UserInputType.MouseMovement
                and input.UserInputType ~= Enum.UserInputType.Touch then return end

            local delta = (input.Position - resizeStartInput) / scale
            local newW = math.clamp(
                resizeStartSize.X + delta.X,
                resizeConstraint.MinSize.X,
                resizeConstraint.MaxSize.X
            )
            local newH = math.clamp(
                resizeStartSize.Y + delta.Y,
                resizeConstraint.MinSize.Y,
                resizeConstraint.MaxSize.Y
            )
            main.Size = UDim2.fromOffset(math.floor(newW), math.floor(newH))
            normalSize = main.Size
            return
        end

        if dragDragging and not locked and not minimized then
            if input.UserInputType ~= Enum.UserInputType.MouseMovement
                and input.UserInputType ~= Enum.UserInputType.Touch then return end

            local delta = (input.Position - dragStartInput) / scale
            main.Position = UDim2.fromOffset(
                math.floor(dragStartPos.X + delta.X),
                math.floor(dragStartPos.Y + delta.Y)
            )
            normalPosition = main.Position
        end
    end)

    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            resizeDragging = false
            dragDragging = false
        end
    end)

    closeButton.Activated:Connect(function()
        gui:Destroy()
    end)

    -- RIGHT CONTENT AREA ----------------------------------------------------
    -- Compact palette: flat panels, minimal strokes, no decorative animation.
    contentPanel = Instance.new("Frame", main)
    contentPanel.Name = "ContentPanel"
    contentPanel.Size = UDim2.new(1, -112, 1, -64)
    contentPanel.Position = UDim2.fromOffset(108, 60)
    contentPanel.BackgroundColor3 = Color3.fromRGB(27, 29, 31)
    contentPanel.BackgroundTransparency = 0.20
    contentPanel.BorderSizePixel = 0
    contentPanel.ZIndex = 2
    contentPanel.ClipsDescendants = true
    Instance.new("UICorner", contentPanel).CornerRadius = UDim.new(0, 12)

contentStroke = Instance.new("UIStroke", contentPanel)
    contentStroke.Thickness = 1
    contentStroke.Transparency = 0.78
    contentStroke.Color = Color3.fromRGB(76, 68, 92)

    scroll = Instance.new("ScrollingFrame", contentPanel)
    scroll.Size = UDim2.new(1, -20, 1, -50)
    scroll.Position = UDim2.fromOffset(10, 40)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 3
    scroll.ScrollBarImageColor3 = Color3.fromRGB(96, 90, 112)
    scroll.CanvasSize = UDim2.fromOffset(0,0)
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.ScrollingDirection = Enum.ScrollingDirection.Y
    scroll.ClipsDescendants = true
    scroll.ZIndex = 4

    -- Reset the viewport after tab visibility/layout changes. Roblox may
    -- recalculate UIListLayout one frame after Visible/LayoutOrder changes,
    -- so a deferred second reset prevents opening a tab halfway down.
    local tabResetSerial = 0
    local function resetScrollTop()
        tabResetSerial = tabResetSerial + 1
        local serial = tabResetSerial
        scroll.CanvasPosition = Vector2.new(0, 0)
        task.defer(function()
            if serial ~= tabResetSerial or not scroll.Parent then return end
            scroll.CanvasPosition = Vector2.new(0, 0)
            task.defer(function()
                if serial == tabResetSerial and scroll.Parent then
                    scroll.CanvasPosition = Vector2.new(0, 0)
                end
            end)
        end)
    end

layout = Instance.new("UIListLayout", scroll)
    layout.Padding = UDim.new(0, 6)
    layout.SortOrder = Enum.SortOrder.LayoutOrder

pad = Instance.new("UIPadding", scroll)
    pad.PaddingLeft = UDim.new(0,2)
    pad.PaddingRight = UDim.new(0,2)
    pad.PaddingBottom = UDim.new(0,14)

sectionRefs = {}
    function sectionKey(text)
        return tostring(text):upper():gsub("[^%w]+", "_")
    end

    function section(text)
        local l = Instance.new("TextLabel", scroll)
        l.Size = UDim2.new(1,0,0,28)
        l.BackgroundTransparency = 1
        l.Font = Enum.Font.GothamBlack
        l.Text = "  " .. tostring(text)
        l.TextColor3 = Color3.fromRGB(230, 233, 235)
        l.TextSize = 11
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.ZIndex = 8
        sectionRefs[sectionKey(text)] = l
        return l
    end

    function button(text, callback, h)
        local b = Instance.new("TextButton", scroll)
        b.Size = UDim2.new(1,0,0,h or 38)
        b.BackgroundColor3 = Color3.fromRGB(36, 38, 40)
        b.BackgroundTransparency = 0
        b.BorderSizePixel = 0
        b.Font = Enum.Font.GothamBold
        b.Text = "   " .. tostring(text)
        b.TextColor3 = Color3.fromRGB(235, 238, 240)
        b.TextSize = 11
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.AutoButtonColor = false
        b.ZIndex = 7
        Instance.new("UICorner", b).CornerRadius = UDim.new(0,4)
        local bs = Instance.new("UIStroke", b)
        bs.Thickness = 1
        bs.Transparency = 0.88
        bs.Color = Color3.fromRGB(100, 90, 125)
        b.Activated:Connect(callback)
        return b
    end

    -- LEFT SIDEBAR ---------------------------------------------------------
    sidebar = Instance.new("Frame", main)
    sidebar.Name = "Sidebar"
    sidebar.Size = UDim2.new(0, 112, 1, -66)
    sidebar.Position = UDim2.fromOffset(8, 62)
    sidebar.BackgroundColor3 = Color3.fromRGB(18, 20, 22)
    sidebar.BackgroundTransparency = 0.10
    sidebar.BorderSizePixel = 0
    sidebar.ZIndex = 3
    Instance.new("UICorner", sidebar).CornerRadius = UDim.new(0, 12)

sideStroke = Instance.new("UIStroke", sidebar)
    sideStroke.Thickness = 1
    sideStroke.Transparency = 0.82
    sideStroke.Color = Color3.fromRGB(111, 38, 158)

sidePad = Instance.new("UIPadding", sidebar)
    sidePad.PaddingTop = UDim.new(0, 6)
    sidePad.PaddingLeft = UDim.new(0, 6)
    sidePad.PaddingRight = UDim.new(0, 6)
    sidePad.PaddingBottom = UDim.new(0, 12)

sideLayout = Instance.new("UIListLayout", sidebar)
    sideLayout.Padding = UDim.new(0, 3)
    sideLayout.SortOrder = Enum.SortOrder.LayoutOrder

sidebarCaption = Instance.new("TextLabel", sidebar)
    sidebarCaption.Size = UDim2.new(1, 0, 0, 22)
    sidebarCaption.BackgroundTransparency = 1
    sidebarCaption.Font = Enum.Font.GothamBold
    sidebarCaption.Text = "NAVIGATION"
    sidebarCaption.TextColor3 = Color3.fromRGB(160, 126, 180)
    sidebarCaption.TextSize = 9
    sidebarCaption.TextXAlignment = Enum.TextXAlignment.Left
    sidebarCaption.LayoutOrder = 1

    sidebarSearch = Instance.new("TextBox", sidebar)
    sidebarSearch.Name = "SidebarSearch"
    sidebarSearch.Size = UDim2.new(1, 0, 0, 30)
    sidebarSearch.LayoutOrder = 0
    sidebarSearch.BackgroundColor3 = Color3.fromRGB(31, 33, 35)
    sidebarSearch.BackgroundTransparency = 0.05
    sidebarSearch.BorderSizePixel = 0
    sidebarSearch.ClearTextOnFocus = false
    sidebarSearch.Font = Enum.Font.Gotham
    sidebarSearch.PlaceholderText = "⌕  Search..."
    sidebarSearch.PlaceholderColor3 = Color3.fromRGB(125, 130, 134)
    sidebarSearch.Text = ""
    sidebarSearch.TextColor3 = Color3.fromRGB(235, 238, 240)
    sidebarSearch.TextSize = 9
    sidebarSearch.TextXAlignment = Enum.TextXAlignment.Left
    sidebarSearch.ZIndex = 8
    Instance.new("UICorner", sidebarSearch).CornerRadius = UDim.new(0, 5)
    local searchPad = Instance.new("UIPadding", sidebarSearch)
    searchPad.PaddingLeft = UDim.new(0, 8)
    searchPad.PaddingRight = UDim.new(0, 6)

activeSide = nil
    function sidebarButton(label, icon, order, callback)
        local b = Instance.new("TextButton", sidebar)
        b.Name = "Nav_" .. tostring(label):gsub("%s+", "")
        b.Size = UDim2.new(1, 0, 0, 38)
        b.LayoutOrder = order
        b.BackgroundColor3 = Color3.fromRGB(13, 8, 21)
        b.BackgroundTransparency = 0.18
        b.BorderSizePixel = 0
        b.AutoButtonColor = false
        b.Font = Enum.Font.GothamSemibold
        b.Text = "  " .. icon .. "    " .. label
        b.TextColor3 = Color3.fromRGB(218, 207, 224)
        b.TextSize = 11
        b.TextXAlignment = Enum.TextXAlignment.Left
        b.ZIndex = 6
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
        local st = Instance.new("UIStroke", b)
        st.Thickness = 1
        st.Transparency = 0.9
        st.Color = Color3.fromRGB(207, 86, 255)

        local function paint(on)
            b.BackgroundColor3 = on and Color3.fromRGB(92, 118, 55) or Color3.fromRGB(28, 30, 32)
            b.BackgroundTransparency = on and 0.02 or 0.18
            b.TextColor3 = on and Color3.fromRGB(245, 255, 232) or Color3.fromRGB(198, 202, 205)
            st.Transparency = on and 0.15 or 0.9
        end
        b.MouseEnter:Connect(function()
            if b ~= activeSide then
                TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3=Color3.fromRGB(48,52,54)}):Play()
            end
        end)
        b.MouseLeave:Connect(function()
            if b ~= activeSide then
                TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3=Color3.fromRGB(28,30,32)}):Play()
            end
        end)
        b.Activated:Connect(function()
            if activeSide then paint(false) end
            activeSide = b
            paint(true)
            pcall(callback)
        end)
        return b
    end

-- TAB NAVIGATION ---------------------------------------------------------
-- One real page per category.  Auto Steal + Egg Farm live together in FARM;
-- Boss + DR. Scramble live together in BOSS.  The old jump-to-section
-- behaviour is intentionally removed so tabs never leave unrelated controls
-- visible underneath another feature.
navOverview = sidebarButton("Overview", "⌂", 1, function() setHubTab("OVERVIEW") end)
navFarm = sidebarButton("Farm", "♨", 2, function() setHubTab("FARM") end)
navBoss = sidebarButton("Boss", "☠", 3, function() setHubTab("BOSS") end)
navPlayerSteal = sidebarButton("Player Steal", "⚔", 4, function() setHubTab("PLAYER_STEAL") end)
navRift = sidebarButton("Rift", "✦", 5, function() setHubTab("RIFT") end)
navGuard = sidebarButton("Guard", "⬟", 6, function() setHubTab("GUARD") end)
navMisc = sidebarButton("Misc", "⚙", 8, function() setHubTab("MISC") end)
navSettings = sidebarButton("Settings", "☷", 9, function() setHubTab("SETTINGS") end)

local compactNav = {navOverview, navFarm, navBoss, navPlayerSteal, navRift, navGuard, navMisc, navSettings}
for i, b in ipairs(compactNav) do
    if b then
        b.LayoutOrder = i + 1
        b.Size = UDim2.new(1, 0, 0, 34)
    end
end
sidebarSearch:GetPropertyChangedSignal("Text"):Connect(function()
    local q = tostring(sidebarSearch.Text or ""):lower():gsub("%s+", "")
    for _, b in ipairs(compactNav) do
        if b then
            local label = tostring(b.Text or ""):lower():gsub("%s+", "")
            b.Visible = q == "" or label:find(q, 1, true) ~= nil
        end
    end
end)

-- Auto Steal and DR. Scramble are features inside Farm/Boss, not separate
-- pages. Legacy duplicate navigation entries are intentionally not created.

profileCard = Instance.new("Frame", sidebar)
    profileCard.Name = "ProfileCard"
    profileCard.Size = UDim2.new(1, 0, 0, 58)
    profileCard.LayoutOrder = 20
    profileCard.BackgroundColor3 = Color3.fromRGB(30, 32, 34)
    profileCard.BackgroundTransparency = 0
    profileCard.BorderSizePixel = 0
    profileCard.ZIndex = 5
    Instance.new("UICorner", profileCard).CornerRadius = UDim.new(0, 12)

profileIcon = Instance.new("TextLabel", profileCard)
    profileIcon.Size = UDim2.fromOffset(34,34)
    profileIcon.Position = UDim2.fromOffset(8,9)
    profileIcon.BackgroundColor3 = Color3.fromRGB(82, 108, 50)
    profileIcon.BorderSizePixel = 0
    profileIcon.Font = Enum.Font.GothamBold
    profileIcon.Text = "♛"
    profileIcon.TextColor3 = Color3.fromRGB(242, 224, 255)
    profileIcon.TextSize = 19
    profileIcon.ZIndex = 6
    Instance.new("UICorner", profileIcon).CornerRadius = UDim.new(1,0)

profileName = Instance.new("TextLabel", profileCard)
    profileName.Size = UDim2.new(1,-68,0,20)
    profileName.Position = UDim2.fromOffset(50,8)
    profileName.BackgroundTransparency = 1
    profileName.Font = Enum.Font.GothamBold
    profileName.Text = "VIP DELS HUB"
    profileName.TextColor3 = Color3.fromRGB(235,245,250)
    profileName.TextSize = 8
    profileName.TextXAlignment = Enum.TextXAlignment.Left
    profileName.ZIndex = 6

profileOnline = Instance.new("TextLabel", profileCard)
    profileOnline.Size = UDim2.new(1,-68,0,18)
    profileOnline.Position = UDim2.fromOffset(50,27)
    profileOnline.BackgroundTransparency = 1
    profileOnline.Font = Enum.Font.Gotham
    profileOnline.Text = "● Online"
    profileOnline.TextColor3 = Color3.fromRGB(80,245,125)
    profileOnline.TextSize = 8
    profileOnline.TextXAlignment = Enum.TextXAlignment.Left
    profileOnline.ZIndex = 6

profileSub = Instance.new("TextLabel", profileCard)
    profileSub.Size = UDim2.new(1,-20,0,18)
    profileSub.Position = UDim2.fromOffset(8,48)
    profileSub.BackgroundTransparency = 1
    profileSub.Font = Enum.Font.Gotham
    profileSub.Text = "Play Smart  •  Steal Faster"
    profileSub.TextColor3 = Color3.fromRGB(120,165,180)
    profileSub.TextSize = 7
    profileSub.TextXAlignment = Enum.TextXAlignment.Left
    profileSub.ZIndex = 6

    -- Start on Overview.
    task.defer(function()
        if navOverview and navOverview.Parent then
            activeSide = navOverview
            navOverview.BackgroundColor3 = Color3.fromRGB(0,104,140)
            navOverview.BackgroundTransparency = 0.02
            navOverview.TextColor3 = Color3.fromRGB(255, 247, 255)
        end
    end)

    function toggle(text, callback)
        local on = false
        local b
        b = button(text .. " [OFF]", function()
            on = not on
            b.Text = text .. (on and " [ON]" or " [OFF]")
            b.BackgroundColor3 = on and Color3.fromRGB(0, 105, 145) or Color3.fromRGB(9, 45, 60)
            local ok, why = pcall(callback, on)
            if not ok then
                on = false
                b.Text = text .. " [OFF]"
                b.BackgroundColor3 = Color3.fromRGB(9, 45, 60)
                print("[SAEGRR] " .. tostring(why))
            end
        end)
        return b, function(v)
            on = v and true or false
            b.Text = text .. (on and " [ON]" or " [OFF]")
            b.BackgroundColor3 = on and Color3.fromRGB(0, 105, 145) or Color3.fromRGB(9, 45, 60)
        end
    end

notice = Instance.new("TextLabel", scroll)
    notice.Size = UDim2.new(1,0,0,28)
    notice.BackgroundTransparency = 1
    notice.Font = Enum.Font.Gotham
    notice.Text = "Ready"
    notice.TextColor3 = Color3.fromRGB(165, 215, 230)
    notice.TextSize = 9
    notice.TextWrapped = true

    function say(t)
        local msg = tostring(t)
        notice.Text = msg
        showNotification("VIP DELL HUBS", msg, "info", 2.6)
    end

    function countText(t)
        if type(t) == "table" then return tostring(#t) else return tostring(t) end
    end

    -- OVERVIEW HERO --------------------------------------------------------
    hero = Instance.new("Frame", scroll)
    hero.Name = "OverviewHero"
    hero.Size = UDim2.new(1, 0, 0, 64)
    hero.BackgroundColor3 = Color3.fromRGB(34, 36, 38)
    hero.BackgroundTransparency = 0.12
    hero.BorderSizePixel = 0
    hero.ZIndex = 6
    Instance.new("UICorner", hero).CornerRadius = UDim.new(0, 12)
    heroStroke = Instance.new("UIStroke", hero)
    heroStroke.Thickness = 1
    heroStroke.Transparency = 0.42
    heroStroke.Color = Color3.fromRGB(188, 67, 255)

    heroIcon = Instance.new("TextLabel", hero)
    heroIcon.Size = UDim2.fromOffset(38,38)
    heroIcon.Position = UDim2.fromOffset(12,13)
    heroIcon.BackgroundColor3 = Color3.fromRGB(82, 108, 50)
    heroIcon.BorderSizePixel = 0
    heroIcon.Font = Enum.Font.GothamBlack
    heroIcon.Text = "◇"
    heroIcon.TextColor3 = Color3.fromRGB(225,252,255)
    heroIcon.TextSize = 22
    heroIcon.ZIndex = 7
    Instance.new("UICorner", heroIcon).CornerRadius = UDim.new(0, 15)

    heroTitle = Instance.new("TextLabel", hero)
    heroTitle.Size = UDim2.new(1,-250,0,25)
    heroTitle.Position = UDim2.fromOffset(62,10)
    heroTitle.BackgroundTransparency = 1
    heroTitle.Font = Enum.Font.GothamBlack
    heroTitle.Text = "Welcome to VIP DELS HUB"
    heroTitle.TextColor3 = Color3.fromRGB(235,248,252)
    heroTitle.TextSize = 14
    heroTitle.TextXAlignment = Enum.TextXAlignment.Left
    heroTitle.ZIndex = 7

    heroSub = Instance.new("TextLabel", hero)
    heroSub.Size = UDim2.new(1,-260,0,24)
    heroSub.Position = UDim2.fromOffset(62,34)
    heroSub.BackgroundTransparency = 1
    heroSub.Font = Enum.Font.Gotham
    heroSub.Text = "Auto Farm  •  Auto Steal  •  Boss  •  DR. Scramble"
    heroSub.TextColor3 = Color3.fromRGB(155,205,220)
    heroSub.TextSize = 8
    heroSub.TextXAlignment = Enum.TextXAlignment.Left
    heroSub.ZIndex = 7

    heroWorld = Instance.new("TextLabel", hero)
    heroWorld.Size = UDim2.fromOffset(130,28)
    heroWorld.Position = UDim2.new(1,-142,0,18)
    heroWorld.BackgroundColor3 = Color3.fromRGB(25, 27, 29)
    heroWorld.BorderSizePixel = 0
    heroWorld.Font = Enum.Font.GothamBold
    heroWorld.Text = "◉  Abyss Overlord  ›"
    heroWorld.TextColor3 = Color3.fromRGB(205,238,248)
    heroWorld.TextSize = 9
    heroWorld.ZIndex = 7
    Instance.new("UICorner", heroWorld).CornerRadius = UDim.new(0, 12)

    section("AUTO FARM")

    -- EQUIP BEST PETS ------------------------------------------------------
    -- Uses the game's own WearBest remote through features.farm.pets.
    -- One-shot action: no loop and no local pet ranking/cache.
    equipBestPetsButton = button("EQUIP THE BEST PETS", function()
        petsFeature = safeRequire("features.farm.pets", {
            equipBest = function() return false, "Pet module unavailable" end,
        })

        local ok, msg = false, "Unknown error"
        pcall(function()
            ok, msg = petsFeature.equipBest()
        end)

        if ok then
            say("Equip Best Pets: " .. tostring(msg or "Equipped your best pets"))
            showNotification("BEST PETS", tostring(msg or "Equipped your best pets"), "success", 2.5)
            equipBestPetsButton.BackgroundColor3 = Color3.fromRGB(0, 105, 145)
        else
            say("Equip Best Pets: " .. tostring(msg or "Failed"))
            showNotification("BEST PETS", tostring(msg or "Failed to equip best pets"), "warn", 2.8)
        end
    end, 36)

    -- Auto Steal was moved to the compact second UI below.
    toggle("Stay On Treadmill", function(on)
        local ok, why = hold.setEnabled(on)
        if on and ok == false then
            -- Auto Steal owns the character while a run is active. Do not throw
            -- from a UI callback here: the old `error(why)` became the noisy
            -- :14510 stack trace and made the treadmill retry every callback.
            say("Stay On Treadmill: blocked while Auto Steal is running")
            showNotification("TREADMILL", tostring(why or "Auto Steal is running"), "info", 2.0)
            return
        end
        say(on and "Stay On Treadmill: ON" or "Stay On Treadmill: OFF")
    end)

    section("PERFORMANCE")

    toggle("EXTREME FPS BOOST", function(on)
        extremeFpsOn = on == true
        local ok, err = pcall(function()
            if fpsFeature and type(fpsFeature.setEnabled) == "function" then
                fpsFeature.setEnabled(extremeFpsOn)
            end
        end)
        if not ok then
            extremeFpsOn = false
            error(err)
        end

        if extremeFpsOn then
            local st = {}
            pcall(function() st = fpsFeature.stats() or {} end)
            say(string.format(
                "EXTREME FPS BOOST: ON • effects/shadows reduced • tracked=%s",
                tostring(st.tracked or st.effects or 0)
            ))
            showNotification(
                "EXTREME FPS BOOST",
                "Heavy particles, post effects, shadows and mesh rendering reduced",
                "success",
                3.0
            )
        else
            say("EXTREME FPS BOOST: OFF • visual properties restored")
            showNotification(
                "EXTREME FPS BOOST",
                "Original rendering properties restored",
                "info",
                2.5
            )
        end
    end)

    toggle("ANTI GUARD [PROTECT + HIDE]", function(on)
        antiGuardOn = on == true
        pcall(function()
            if guard and type(guard.setAntiGuard) == "function" then
                guard.setAntiGuard(antiGuardOn)
            end
        end)
        -- Keep the existing anti-hit/drop protection armed whenever Auto Farm
        -- owns the character; this toggle additionally suppresses guard visuals.
        pcall(function()
            if antiGuardOn and guard and type(guard.arm) == "function" then guard.arm() end
        end)
        say(antiGuardOn and "ANTI GUARD: ON • protect + hide guards" or "ANTI GUARD: OFF")
        showNotification("ANTI GUARD", antiGuardOn and "Guard visuals hidden • protection active" or "Guard visuals restored", antiGuardOn and "success" or "info", 2.5)
    end)

    toggle("ALWAYS GRAB / CARRY EGG [NO DROP]", function(on)
        alwaysCarryOn = on == true
        pcall(function()
            if alwaysCarryOn and guard and type(guard.arm) == "function" then guard.arm() end
        end)
        refreshAutoMovementOptions()
        say(alwaysCarryOn and "ALWAYS CARRY: ON • drop block armed" or "ALWAYS CARRY: OFF")
        showNotification("ALWAYS CARRY", alwaysCarryOn and "Egg drop protection enabled" or "Egg drop protection follows Auto Farm", alwaysCarryOn and "success" or "info", 2.4)
    end)

    toggle("MOBILE FAST CARRY", function(on)
        mobileFastCarryOn = on == true
        refreshAutoMovementOptions()
        say(mobileFastCarryOn and "MOBILE FAST CARRY: ON • adaptive FPS cap" or "MOBILE FAST CARRY: OFF • conservative carry")
    end)

    -- ---------- Boss ----------
    section("ABYSS OVERLORD")
    bossStatus = Instance.new("TextLabel", scroll)
    bossStatus.Size = UDim2.new(1,0,0,28)
    bossStatus.BackgroundTransparency = 1
    bossStatus.Font = Enum.Font.Gotham
    bossStatus.Text = "Reading..."
    bossStatus.TextColor3 = Color3.fromRGB(165, 215, 230)
    bossStatus.TextSize = 9
    bossStatus.TextWrapped = true

    button("Enter the Boss World", function()
        local ok, msg = boss.enter()
        say(msg)
        bossStatus.Text = tostring(msg)
    end, 30)

    toggle("AUTO ENTER", function(on)
        if on and not boss.isOn() then boss.setEnabled(true) end
        boss.setAutoEnter(on)
        say(on and "Auto Enter: ON" or "Auto Enter: OFF")
    end)

    toggle("AUTO FIGHT", function(on)
        fight.setEnabled(on)
        say(on and "Auto Fight: ON" or "Auto Fight: OFF")
    end)

    fightStatus = Instance.new("TextLabel", scroll)
    fightStatus.Size = UDim2.new(1,0,0,34)
    fightStatus.BackgroundTransparency = 1
    fightStatus.Font = Enum.Font.Gotham
    fightStatus.Text = "Auto fight: off"
    fightStatus.TextColor3 = Color3.fromRGB(165, 215, 230)
    fightStatus.TextSize = 9
    fightStatus.TextWrapped = true

    task.spawn(function()
        while gui.Parent do
            pcall(function()
                local s = boss.status()
                if s and s.body then bossStatus.Text = tostring(s.body) end
            end)
            pcall(function()
                local s = fight.status()
                if s and s.body then fightStatus.Text = tostring(s.body) end
            end)
            task.wait(1)
        end
    end)

    --------------------------------------------------------------------------
    -- AUTO STEAL / EGG SELECTOR - INTEGRATED INTO THE MAIN HUB
    -- One menu only: premium transparent glass + animated RGB accent.
    --------------------------------------------------------------------------
    eggsFeature = safeRequire("features.eggs", {
        get=function() return nil end,
        list=function() return {} end,
        invalidate=function() end,
    })

    autoSection = Instance.new("Frame", scroll)
    autoSection.Name = "AutoStealSection"
    autoSection.LayoutOrder = 9000
    autoSection.Size = UDim2.new(1, 0, 0, 1000)
    autoSection.BackgroundColor3 = Color3.fromRGB(10, 11, 16)
    autoSection.BackgroundTransparency = 0.18
    autoSection.BorderSizePixel = 0
    Instance.new("UICorner", autoSection).CornerRadius = UDim.new(0, 12)

    autoStroke = Instance.new("UIStroke", autoSection)
    autoStroke.Thickness = 1.8
    autoStroke.Transparency = 0.12

autoGradient = Instance.new("UIGradient", autoStroke)
    autoGradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 35, 90)),
        ColorSequenceKeypoint.new(0.25, Color3.fromRGB(145, 70, 255)),
        ColorSequenceKeypoint.new(0.50, Color3.fromRGB(40, 210, 255)),
        ColorSequenceKeypoint.new(0.75, Color3.fromRGB(70, 255, 190)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255, 35, 90))
    })

    task.spawn(function()
        while gui.Parent and autoSection.Parent do
            autoGradient.Rotation = (autoGradient.Rotation + 2) % 360
            task.wait((dev and type(dev.visualInterval) == "function") and dev.visualInterval(0.06) or 0.06)
        end
    end)

    autoTitle = Instance.new("TextLabel", autoSection)
    autoTitle.Size = UDim2.new(1, -18, 0, 23)
    autoTitle.Position = UDim2.fromOffset(9, 7)
    autoTitle.BackgroundTransparency = 1
    autoTitle.Font = Enum.Font.GothamBold
    autoTitle.Text = "✦  AUTO STEAL"
    autoTitle.TextColor3 = Color3.fromRGB(245, 248, 255)
    autoTitle.TextSize = 13
    autoTitle.TextXAlignment = Enum.TextXAlignment.Left

    autoSub = Instance.new("TextLabel", autoSection)
    autoSub.Size = UDim2.new(1, -18, 0, 17)
    autoSub.Position = UDim2.fromOffset(9, 29)
    autoSub.BackgroundTransparency = 1
    autoSub.Font = Enum.Font.Gotham
    autoSub.Text = "Select an egg • search by name or rarity"
    autoSub.TextColor3 = Color3.fromRGB(165, 174, 195)
    autoSub.TextSize = 9
    autoSub.TextXAlignment = Enum.TextXAlignment.Left

    selectedUid = nil
    selectedText = Instance.new("TextLabel", autoSection)
    selectedText.Size = UDim2.new(1, -18, 0, 38)
    selectedText.Position = UDim2.fromOffset(9, 50)
    selectedText.BackgroundColor3 = Color3.fromRGB(18, 20, 29)
    selectedText.BackgroundTransparency = 0.12
    selectedText.BorderSizePixel = 0
    selectedText.Font = Enum.Font.GothamBold
    selectedText.Text = "SELECTED EGG: NONE"
    selectedText.TextColor3 = Color3.fromRGB(100, 225, 255)
    selectedText.TextSize = 10
    selectedText.TextWrapped = true
    selectedText.ZIndex = 21
    Instance.new("UICorner", selectedText).CornerRadius = UDim.new(0, 8)

    autoStealButton = Instance.new("TextButton", autoSection)
    autoStealButton.Size = UDim2.new(1, -18, 0, 32)
    autoStealButton.Position = UDim2.fromOffset(9, 93)
    autoStealButton.BackgroundColor3 = Color3.fromRGB(34, 37, 52)
    autoStealButton.BackgroundTransparency = 0.08
    autoStealButton.BorderSizePixel = 0
    autoStealButton.Font = Enum.Font.GothamBold
    autoStealButton.Text = "AUTO STEAL  [OFF]"
    autoStealButton.TextColor3 = Color3.fromRGB(235, 240, 255)
    autoStealButton.TextSize = 10
    autoStealButton.ZIndex = 21
    Instance.new("UICorner", autoStealButton).CornerRadius = UDim.new(0, 8)


    autoReturnBaseButton = Instance.new("TextButton", autoSection)
    autoReturnBaseButton.Name = "AutoReturnToBaseButton"
    autoReturnBaseButton.Size = UDim2.new(1, -18, 0, 32)
    autoReturnBaseButton.Position = UDim2.fromOffset(9, 128)
    autoReturnBaseButton.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
    autoReturnBaseButton.BackgroundTransparency = 0.05
    autoReturnBaseButton.BorderSizePixel = 0
    autoReturnBaseButton.Font = Enum.Font.GothamBold
    autoReturnBaseButton.Text = "AUTO RETURN BASE  [OFF]"
    autoReturnBaseButton.TextColor3 = Color3.fromRGB(185, 195, 215)
    autoReturnBaseButton.TextSize = 9
    autoReturnBaseButton.ZIndex = 21
    Instance.new("UICorner", autoReturnBaseButton).CornerRadius = UDim.new(0, 8)

    autoReturnBaseButton.Activated:Connect(function()
        autoReturnToBase = not autoReturnToBase
        autoReturnBaseButton.Text = autoReturnToBase
            and "AUTO RETURN BASE  [ON]"
            or "AUTO RETURN BASE  [OFF]"
        autoReturnBaseButton.BackgroundColor3 = autoReturnToBase
            and Color3.fromRGB(0, 105, 145)
            or Color3.fromRGB(23, 28, 38)
        autoReturnBaseButton.TextColor3 = autoReturnToBase
            and Color3.fromRGB(235, 250, 255)
            or Color3.fromRGB(185, 195, 215)

        if autoRarityOn then
            safeAutoSetOptions("rarity", {
                pick = pickByRarityPriority, continuous = true,
                cycleDelay = stealDelay, fastMode = true, method = autoStealMethod,
            })
        end
        if autoStealOn then
            safeAutoSetOptions("farm", {
                pick = pickByMethodLoop, continuous = true,
                cycleDelay = stealDelay, fastMode = true, method = autoStealMethod,
                deliverySpeed = deliverySpeeds[autoStealMethod],
            })
        end

        showNotification(
            "AUTO RETURN TO BASE",
            autoReturnToBase
                and "ON • Farm/Combo will place carried eggs at your base"
                or "OFF • Farm/Combo will deliver eggs to Safe Zone",
            autoReturnToBase and "success" or "info", 2.8
        )
    end)

    -- METHOD SELECTOR: always visible directly below Auto Steal.
    -- These choices are consumed only by AUTO FARM EGG BY RARITY.
    -- Normal/manual AUTO STEAL is intentionally independent of this selector.
    autoStealMethod = "GLIDE"
    -- Shared by method callbacks and the Auto Combo callback. Declare it
    -- before either callback so Lua captures the intended local, not _G.
    stealDelay = 0.70

    -- Delivery Egg -> Safe Zone speeds are independent per method.
    deliverySpeeds = {
        GLIDE = 1050,
        FLY = 1050,
        WALK = 1050,
        RIDE_GUARD = 1050,
    }

    methodTitle = Instance.new("TextLabel", autoSection)
    methodTitle.Name = "AutoStealMethodTitle"
    methodTitle.Size = UDim2.new(1, -18, 0, 16)
    methodTitle.Position = UDim2.fromOffset(9, 166)
    methodTitle.BackgroundTransparency = 1
    methodTitle.Font = Enum.Font.GothamBold
    methodTitle.Text = "DELIVERY METHOD  •  EGG → SAFE ZONE  •  LIVE TARGETING"
    methodTitle.TextColor3 = Color3.fromRGB(135, 220, 255)
    methodTitle.TextSize = 9
    methodTitle.TextXAlignment = Enum.TextXAlignment.Left
    methodTitle.ZIndex = 21

    method24 = Instance.new("TextButton", autoSection)
    method24.Name = "Method24x7"
    method24.Size = UDim2.new(1/4, -7, 0, 30)
    method24.Position = UDim2.fromOffset(9, 186)
    method24.BackgroundColor3 = Color3.fromRGB(0, 105, 145)
    method24.BorderSizePixel = 0
    method24.Font = Enum.Font.GothamBold
    method24.Text = "✓  GLIDE"
    method24.TextColor3 = Color3.fromRGB(240, 252, 255)
    method24.TextSize = 8
    method24.ZIndex = 22
    Instance.new("UICorner", method24).CornerRadius = UDim.new(0, 7)

    methodTP = Instance.new("TextButton", autoSection)
    methodTP.Name = "MethodAutoLoopTP"
    methodTP.Size = UDim2.new(1/4, -7, 0, 30)
    methodTP.Position = UDim2.new(1/4, 2, 0, 186)
    methodTP.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
    methodTP.BorderSizePixel = 0
    methodTP.Font = Enum.Font.GothamBold
    methodTP.Text = "○  FLY"
    methodTP.TextColor3 = Color3.fromRGB(170, 182, 198)
    methodTP.TextSize = 8
    methodTP.ZIndex = 22
    Instance.new("UICorner", methodTP).CornerRadius = UDim.new(0, 7)

    methodRG = Instance.new("TextButton", autoSection)
    methodRG.Name = "MethodRideGuardDelivery"
    methodRG.Size = UDim2.new(1/4, -7, 0, 30)
    methodRG.Position = UDim2.new(3/4, -5, 0, 186)
    methodRG.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
    methodRG.BorderSizePixel = 0
    methodRG.Font = Enum.Font.GothamBold
    methodRG.Text = "○  🐎 RIDE GUARD"
    methodRG.TextColor3 = Color3.fromRGB(170, 182, 198)
    methodRG.TextSize = 8
    methodRG.ZIndex = 22
    Instance.new("UICorner", methodRG).CornerRadius = UDim.new(0, 7)

    methodWalk = Instance.new("TextButton", autoSection)
    methodWalk.Name = "MethodWalkDelivery"
    methodWalk.Size = UDim2.new(1/4, -7, 0, 30)
    methodWalk.Position = UDim2.new(1/2, -2, 0, 186)
    methodWalk.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
    methodWalk.BorderSizePixel = 0
    methodWalk.Font = Enum.Font.GothamBold
    methodWalk.Text = "○  WALK"
    methodWalk.TextColor3 = Color3.fromRGB(170, 182, 198)
    methodWalk.TextSize = 8
    methodWalk.ZIndex = 22
    Instance.new("UICorner", methodWalk).CornerRadius = UDim.new(0, 7)

    methodStatus = Instance.new("TextLabel", autoSection)
    methodStatus.Name = "AutoStealMethodStatus"
    methodStatus.Size = UDim2.new(1, -18, 0, 15)
    methodStatus.Position = UDim2.fromOffset(9, 219)
    methodStatus.BackgroundTransparency = 1
    methodStatus.Font = Enum.Font.Gotham
    methodStatus.Text = "Current: Auto Farm Egg by Rarity worker"
    methodStatus.TextColor3 = Color3.fromRGB(150, 165, 185)
    methodStatus.TextSize = 8
    methodStatus.TextXAlignment = Enum.TextXAlignment.Left
    methodStatus.ZIndex = 21

    -- METHOD SELECTOR
    -- These methods belong ONLY to AUTO FARM EGG BY RARITY.
    -- They do NOT start the normal/manual Auto Steal worker.
    -- Select a method first, then enable Auto Steal 24/7 • BY RARITY.
    function updateMethodVisual(active)
        local is24 = autoStealMethod == "GLIDE"
        local isTP = autoStealMethod == "FLY"
        local isWalk = autoStealMethod == "WALK"
        local isRG = autoStealMethod == "RIDE_GUARD"
        local rarityRunning = autoRarityOn == true

        method24.Text = is24 and "✓  GLIDE" or "○  GLIDE"
        methodTP.Text = isTP and "✓  FLY" or "○  FLY"
        methodWalk.Text = isWalk and "✓  WALK" or "○  WALK"
        methodRG.Text = isRG and "✓  🐎 RIDE" or "○  🐎 RIDE"

        method24.BackgroundColor3 = is24 and Color3.fromRGB(0, 105, 145) or Color3.fromRGB(23, 28, 38)
        methodTP.BackgroundColor3 = isTP and Color3.fromRGB(0, 105, 145) or Color3.fromRGB(23, 28, 38)
        methodWalk.BackgroundColor3 = isWalk and Color3.fromRGB(0, 105, 145) or Color3.fromRGB(23, 28, 38)
        methodRG.BackgroundColor3 = isRG and Color3.fromRGB(0, 105, 145) or Color3.fromRGB(23, 28, 38)

        method24.TextColor3 = is24 and Color3.fromRGB(240, 252, 255) or Color3.fromRGB(170, 182, 198)
        methodTP.TextColor3 = isTP and Color3.fromRGB(240, 252, 255) or Color3.fromRGB(170, 182, 198)
        methodWalk.TextColor3 = isWalk and Color3.fromRGB(240, 252, 255) or Color3.fromRGB(170, 182, 198)
        methodRG.TextColor3 = isRG and Color3.fromRGB(240, 252, 255) or Color3.fromRGB(170, 182, 198)

        if rarityRunning then
            if is24 then
                methodStatus.Text = "ACTIVE: GLIDE • " .. tostring(deliverySpeeds.GLIDE) .. " studs/s"
            elseif isTP then
                methodStatus.Text = "ACTIVE: FLY • " .. tostring(deliverySpeeds.FLY) .. " studs/s"
            elseif isWalk then
                methodStatus.Text = "ACTIVE: WALK • " .. tostring(deliverySpeeds.WALK) .. " studs/s"
            else
                methodStatus.Text = "ACTIVE: RIDE GUARD • " .. tostring(deliverySpeeds.RIDE_GUARD) .. " studs/s"
            end
        else
            if is24 then
                methodStatus.Text = "Selected: GLIDE • set speed below"
            elseif isTP then
                methodStatus.Text = "Selected: FLY • set speed below"
            elseif isWalk then
                methodStatus.Text = "Selected: WALK • set speed below"
            else
                methodStatus.Text = "Selected: RIDE GUARD • set speed below"
            end
        end
    end

    function selectRarityMethod(method)
        autoStealMethod = tostring(method or "GLIDE"):upper()
        updateMethodVisual(autoRarityOn)

        -- If rarity mode is already running, update the existing rarity worker.
        if autoRarityOn then
            if method == "RIDE_GUARD" then
                local env = _G
                if type(getgenv) == "function" then
                    local ok, e = pcall(getgenv)
                    if ok and type(e) == "table" then env = e end
                end
                local api = env.__DELL_RIDE_GUARD_API
                if not api or type(api.beginDelivery) ~= "function" then
                    showNotification("METHOD", "Ride Guard is not ready", "warn", 2.4)
                    return
                end
            end

            pcall(function()
                safeAutoSetOptions("rarity", {
                    pick = pickByRarityPriority,
                    continuous = true,
                    cycleDelay = stealDelay,
                    fastMode = true,
                    method = autoStealMethod,
                    deliverySpeed = deliverySpeeds[autoStealMethod],
                })
            end)
            showNotification("RARITY METHOD", "Switched to " .. method .. " • rarity worker updated", "success", 2.2)
        else
            showNotification("RARITY METHOD", method .. " selected • now enable AUTO FARM EGG BY RARITY", "info", 2.2)
        end
    end

    method24.Activated:Connect(function()
        selectRarityMethod("GLIDE")
    end)

    methodTP.Activated:Connect(function()
        selectRarityMethod("FLY")
    end)

    methodWalk.Activated:Connect(function()
        selectRarityMethod("WALK")
    end)

    methodRG.Activated:Connect(function()
        selectRarityMethod("RIDE_GUARD")
    end)

    updateMethodVisual(false)

    -- NEW: automatic rarity filter / priority selector
    rarityTitle = Instance.new("TextLabel", autoSection)
    rarityTitle.Size = UDim2.new(1, -18, 0, 17)
    rarityTitle.Position = UDim2.fromOffset(9, 239)
    rarityTitle.BackgroundTransparency = 1
    rarityTitle.Font = Enum.Font.GothamBold
    rarityTitle.Text = "AUTO-DETECT RARITY  •  LIVE DIRECTORY"
    rarityTitle.TextColor3 = Color3.fromRGB(135, 220, 255)
    rarityTitle.TextSize = 9
    rarityTitle.TextXAlignment = Enum.TextXAlignment.Left
    rarityTitle.ZIndex = 21

    rarityFilterFrame = Instance.new("Frame", autoSection)
    rarityFilterFrame.Name = "RarityFilter"
    rarityFilterFrame.Size = UDim2.new(1, -18, 0, 80)
    rarityFilterFrame.Position = UDim2.fromOffset(9, 257)
    rarityFilterFrame.BackgroundTransparency = 1
    rarityFilterFrame.ZIndex = 21

    rarityLayout = Instance.new("UIGridLayout", rarityFilterFrame)
    rarityLayout.CellSize = UDim2.fromOffset(76, 24)
    rarityLayout.CellPadding = UDim2.fromOffset(5, 5)
    rarityLayout.FillDirection = Enum.FillDirection.Horizontal
    rarityLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
    rarityLayout.VerticalAlignment = Enum.VerticalAlignment.Top
    rarityLayout.SortOrder = Enum.SortOrder.LayoutOrder

refreshEggView = nil

raritySelected = {}
rarityButtons = {}
rarityAliases = {}
rarityColors = {}
rarityNumbers = {}
rarityOrder = {}
rarityDetectedSignature = ""

-- AUTO-DETECT RARITIES FROM THE GAME'S LIVE ASSET DIRECTORY.
-- Nothing here is hardcoded to a fixed rarity list. The existing
-- features.farm.filter module already reads Assets.Directory[*].Rarity,
-- including the current RarityNumber/DisplayName. We mirror that source so
-- newly-added rarities appear automatically without editing this script.
function rebuildDetectedRarityFilters()
    local detected = {}
    local rows = {}

    pcall(function()
        local options = filter and filter.rarityOptions and filter.rarityOptions()
        if type(options) == "table" then
            for _, row in ipairs(options) do
                if row and row.id then
                    local key = tostring(row.id)
                    local label = tostring(row.label or row.id)
                    local normKey = normalizeRarity(label)
                    if normKey == "" then normKey = normalizeRarity(key) end

                    if key ~= "" and normKey ~= "" and not detected[key] then
                        detected[key] = true
                        rows[#rows + 1] = {
                            key = key,
                            label = label,
                            num = tonumber(row.num) or 0,
                        }
                    end
                end
            end
        end
    end)

    -- If the filter module is temporarily unavailable, keep the previous
    -- detected list rather than destroying the user's active selections.
    if #rows == 0 and #rarityOrder > 0 then
        return false
    end

    -- Capture colours directly from the authoritative Assets.Directory.
    pcall(function()
        local dir = filter and filter.assetsDir and filter.assetsDir()
        if type(dir) ~= "table" then
            local d = BX.require("core.data")
            dir = d and d.assetsDir and d.assetsDir() or nil
        end
        if type(dir) == "table" then
            for _, entry in pairs(dir) do
                if type(entry) == "table" and type(entry.Rarity) == "table" then
                    local r = entry.Rarity
                    local key = tostring(r._id or r.DisplayName or "")
                    if key ~= "" then
                        local color = r.Color
                        if typeof(color) == "Color3" then
                            rarityColors[key] = color
                        end
                        if not rarityColors[key] and r.DisplayName then
                            rarityColors[tostring(r.DisplayName)] = color
                        end
                    end
                end
            end
        end
    end)

    table.sort(rows, function(a, b)
        -- Highest rarity number first for Auto Farm priority.
        if a.num ~= b.num then return a.num > b.num end
        return a.label < b.label
    end)

    local newSignatureParts = {}
    for _, row in ipairs(rows) do
        newSignatureParts[#newSignatureParts + 1] = tostring(row.key) .. ":" .. tostring(row.num) .. ":" .. tostring(row.label)
    end
    local newSignature = table.concat(newSignatureParts, "|")
    if newSignature == rarityDetectedSignature then
        return false
    end
    rarityDetectedSignature = newSignature

    local oldSelected = raritySelected
    raritySelected = {}
    rarityAliases = {}
    rarityNumbers = {}
    rarityOrder = {}

    for _, row in ipairs(rows) do
        local key = row.key
        local label = row.label
        rarityOrder[#rarityOrder + 1] = key
        raritySelected[key] = oldSelected[key] == true
        rarityNumbers[key] = row.num

        local aliases = {
            normalizeRarity(key),
            normalizeRarity(label),
        }

        -- Also accept the Rarity _id/display name from the live directory.
        pcall(function()
            local d = BX.require("core.data")
            local dir = d and d.assetsDir and d.assetsDir()
            if type(dir) == "table" then
                for _, entry in pairs(dir) do
                    local r = type(entry) == "table" and entry.Rarity or nil
                    if type(r) == "table" then
                        local rid = normalizeRarity(r._id)
                        local rname = normalizeRarity(r.DisplayName)
                        if rid == normalizeRarity(key) or rname == normalizeRarity(label) then
                            if rid ~= "" then aliases[#aliases + 1] = rid end
                            if rname ~= "" then aliases[#aliases + 1] = rname end
                            break
                        end
                    end
                end
            end
        end)

        rarityAliases[key] = aliases
    end

    -- Rebuild only the filter buttons. The rest of the GUI remains untouched.
    for _, child in ipairs(rarityFilterFrame:GetChildren()) do
        if child:IsA("TextButton") then
            child:Destroy()
        end
    end

    for index, key in ipairs(rarityOrder) do
        local rb = Instance.new("TextButton", rarityFilterFrame)
        rb.Name = "Rarity_" .. tostring(key)
        rb.Size = UDim2.fromOffset(76, 24)
        rb.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
        rb.BackgroundTransparency = 0.05
        rb.BorderSizePixel = 0
        rb.Font = Enum.Font.GothamBold
        rb.TextSize = 8
        rb.Text = "○ " .. tostring(key)
        rb.LayoutOrder = index
        rb.ZIndex = 22
        Instance.new("UICorner", rb).CornerRadius = UDim.new(0, 7)

        local rs = Instance.new("UIStroke", rb)
        rs.Thickness = 1
        rs.Transparency = 0.45
        rs.Color = rarityColors[key] or Color3.fromRGB(188, 67, 255)

        rarityButtons[key] = rb
        rb.Activated:Connect(function()
            raritySelected[key] = not raritySelected[key]
            updateRarityButtonVisuals()
            updateRarityStatus()
            refreshEggView()
        end)
    end

    updateRarityButtonVisuals()

    rarityTitle.Text = "AUTO-DETECT RARITY  •  LIVE DIRECTORY  •  "
        .. tostring(#rarityOrder) .. " AVAILABLE  •  HIGHEST → LOWEST"

    return true
end

function normalizeRarity(value)
    return tostring(value or ""):lower():gsub("%s+", "")
end

function rarityIsSelected(rarity)
    local r = normalizeRarity(rarity)
    for key, aliases in pairs(rarityAliases) do
        if raritySelected[key] then
            for _, alias in ipairs(aliases) do
                if r == alias then return true end
            end
        end
    end
    return false
end

function selectedRaritySummary()
    local parts = {}
    for _, key in ipairs(rarityOrder) do
        if raritySelected[key] then parts[#parts + 1] = tostring(key) end
    end
    return #parts > 0 and table.concat(parts, " • ") or "NONE"
end

function updateRarityButtonVisuals()
    for key, button in pairs(rarityButtons) do
        local on = raritySelected[key] == true
        button.Text = (on and "✓ " or "○ ") .. tostring(key)
        button.BackgroundColor3 = on and Color3.fromRGB(0, 115, 155) or Color3.fromRGB(23, 28, 38)
        button.TextColor3 = on and Color3.fromRGB(240, 252, 255) or (rarityColors[key] or Color3.fromRGB(170, 182, 198))
        local stroke = button:FindFirstChildOfClass("UIStroke")
        if stroke then
            stroke.Color = rarityColors[key] or Color3.fromRGB(188, 67, 255)
            stroke.Transparency = on and 0.15 or 0.45
        end
    end
end

-- First scan: the actual game Directory decides what rarities exist.
rebuildDetectedRarityFilters()

-- Keep the rarity list current if the game adds/removes tiers at runtime.
task.spawn(function()
    while gui and gui.Parent do
        task.wait(2)
        pcall(rebuildDetectedRarityFilters)
    end
end)

-- Refresh Eggs lives here with the live rarity status so the Farm tab has
-- one refresh control instead of the old duplicate Egg Filters block.
    refreshEggButton = Instance.new("TextButton", autoSection)
    refreshEggButton.Name = "RefreshEggsButton"
    refreshEggButton.Size = UDim2.new(0.5, -12, 0, 20)
    refreshEggButton.Position = UDim2.fromOffset(9, 340)
    refreshEggButton.BackgroundColor3 = Color3.fromRGB(20, 72, 92)
    refreshEggButton.BackgroundTransparency = 0.05
    refreshEggButton.BorderSizePixel = 0
    refreshEggButton.AutoButtonColor = false
    refreshEggButton.Font = Enum.Font.GothamBold
    refreshEggButton.Text = "↻  REFRESH EGGS"
    refreshEggButton.TextColor3 = Color3.fromRGB(225, 250, 255)
    refreshEggButton.TextSize = 8
    refreshEggButton.ZIndex = 21
    Instance.new("UICorner", refreshEggButton).CornerRadius = UDim.new(0, 7)

    rarityStatus = Instance.new("TextLabel", autoSection)
    rarityStatus.Name = "RarityStatus"
    rarityStatus.Size = UDim2.new(0.5, -12, 0, 20)
    rarityStatus.Position = UDim2.new(0.5, 3, 0, 340)
    rarityStatus.BackgroundTransparency = 1
    rarityStatus.Font = Enum.Font.Gotham
    rarityStatus.Text = "Selected: NONE  •  Auto rarity is OFF"
    rarityStatus.TextColor3 = Color3.fromRGB(150, 165, 185)
    rarityStatus.TextSize = 8
    rarityStatus.TextXAlignment = Enum.TextXAlignment.Left
    rarityStatus.TextTruncate = Enum.TextTruncate.AtEnd
    rarityStatus.ZIndex = 21

refreshEggButton.Activated:Connect(function()
    if refreshBusy then return end
    refreshBusy = true
    refreshEggButton.Text = "↻  REFRESHING..."

    local ok, err = pcall(function()
        local eggs = BX.require("features.eggs")
        eggs.invalidate("Farm refresh")
        eggs.list({}, true)
        local n = filter.matchCount()
        say(("Egg refresh: %d matching egg%s"):format(n, n == 1 and "" or "s"))
        showNotification("EGG REFRESH", string.format("Scan complete • %d matching egg%s", n, n == 1 and "" or "s"), n > 0 and "success" or "warn", 2.5)
    end)

    refreshBusy = false
    refreshEggButton.Text = "↻  REFRESH EGGS"
    if not ok then
        showNotification("EGG REFRESH", "Refresh failed: " .. tostring(err), "error", 2.8)
    end
end)

pcall(updateRarityStatus)

eggSearch = Instance.new("TextBox", autoSection)
    eggSearch.Name = "EggSearch"
    eggSearch.Size = UDim2.new(1, -18, 0, 31)
    eggSearch.Position = UDim2.fromOffset(9, 361)
    eggSearch.BackgroundColor3 = Color3.fromRGB(16, 18, 27)
    eggSearch.BackgroundTransparency = 0.08
    eggSearch.BorderSizePixel = 0
    eggSearch.ClearTextOnFocus = false
    eggSearch.Font = Enum.Font.Gotham
    eggSearch.PlaceholderText = "Search egg name / rarity..."
    eggSearch.PlaceholderColor3 = Color3.fromRGB(115, 124, 145)
    eggSearch.Text = ""
    eggSearch.TextColor3 = Color3.fromRGB(240, 245, 255)
    eggSearch.TextSize = 11
    eggSearch.TextXAlignment = Enum.TextXAlignment.Left
    eggSearch.ZIndex = 21
    Instance.new("UICorner", eggSearch).CornerRadius = UDim.new(0, 8)

searchPadding = Instance.new("UIPadding", eggSearch)
    searchPadding.PaddingLeft = UDim.new(0, 10)
    searchPadding.PaddingRight = UDim.new(0, 10)

eggList = Instance.new("ScrollingFrame", autoSection)
    eggList.Name = "EggView"
    eggList.Size = UDim2.new(1, -18, 0, 105)
    eggList.Position = UDim2.fromOffset(9, 398)
    eggList.BackgroundColor3 = Color3.fromRGB(9, 11, 17)
    eggList.BackgroundTransparency = 0.06
    eggList.BorderSizePixel = 0
    eggList.ScrollBarThickness = 10
    eggList.ScrollBarImageColor3 = Color3.fromRGB(188, 67, 255)
    eggList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    eggList.CanvasSize = UDim2.fromOffset(0, 0)
    eggList.ZIndex = 21
    Instance.new("UICorner", eggList).CornerRadius = UDim.new(0, 9)

eggLayout = Instance.new("UIListLayout", eggList)
    eggLayout.Padding = UDim.new(0, 5)
    eggLayout.SortOrder = Enum.SortOrder.LayoutOrder

eggPadding = Instance.new("UIPadding", eggList)
    eggPadding.PaddingTop = UDim.new(0, 6)
    eggPadding.PaddingLeft = UDim.new(0, 6)
    eggPadding.PaddingRight = UDim.new(0, 6)
    eggPadding.PaddingBottom = UDim.new(0, 6)

autoStealOn = false
eggSearchText = ""
selectedMissingTicks = 0
refreshBusy = false
autoRarityOn = false
autoReturnToBase = false
autoRarityRun = 0
pickByRarityPriority = nil
pickByMethodLoop = nil

    -- =====================================================================
    -- RARITY TARGET SAFE-ZONE GATE
    --
    -- After a scan has found NO matching egg, the next time a matching egg
    -- appears we must be physically back in Safe Zone before travelling to it.
    -- The gate accepts either:
    --   1) a full 3-second Safe Zone settle, OR
    --   2) two Space presses during that settle window.
    --
    -- This is shared by Auto Farm Egg By Rarity, Auto Combo, and Beta Test
    -- because all three use pickByRarityPriority().
    -- =====================================================================
raritySafeGateArmed = true
RARITY_SAFE_SETTLE = 3.0
RARITY_SAFE_ARRIVE = 6
RARITY_SAFE_SPEED = 1800

    function raritySafeZoneBeforeTarget(cancel)
        local plot = BX.require("features.plot")
        local move = BX.require("features.movement")
        local svc = BX.require("core.services")

        local safePos = nil
        pcall(function() safePos = plot.safeZone() end)
        if typeof(safePos) ~= "Vector3" then
            return false, "Safe Zone position unavailable"
        end

        -- First, physically return to Safe Zone. Do not allow the target leg
        -- to begin until this move has completed.
        local okMove = move.travel{
            to = safePos,
            speed = RARITY_SAFE_SPEED,
            arrive = RARITY_SAFE_ARRIVE,
            carrying = false,
            cancel = cancel,
            tag = "rarity-safezone-gate",
        }
        if not okMove then
            return false, "Safe Zone gate travel failed"
        end
        if cancel and cancel() then
            return false, "cancelled"
        end

        -- Verify the character is really at Safe Zone, not merely that the
        -- movement call returned.
        local root = nil
        pcall(function() root = BX.require("core.character").root() end)
        if not root or (root.Position - safePos).Magnitude > RARITY_SAFE_ARRIVE + 4 then
            return false, "not actually in Safe Zone"
        end

        -- Give the server/client a stable 3-second window. If the user presses
        -- Space twice during this window, the gate is considered settled early.
        local spaceCount = 0
        local conn = nil
        pcall(function()
            conn = svc.UserInputService.InputBegan:Connect(function(input, processed)
                if processed then return end
                if input.KeyCode == Enum.KeyCode.Space then
                    spaceCount = spaceCount + 1
                end
            end)
        end)

        local deadline = os.clock() + RARITY_SAFE_SETTLE
        while os.clock() < deadline do
            if cancel and cancel() then
                if conn then conn:Disconnect() end
                return false, "cancelled"
            end
            if spaceCount >= 2 then break end
            svc.RunService.Heartbeat:Wait()
        end
        if conn then conn:Disconnect() end

        return true, (spaceCount >= 2) and "two-space-confirmed" or "three-second-settle"
    end

    -- Manual Auto Steal follows the currently selected egg. If the selected egg
    -- disappears, refresh the live list and fall back to the best available egg.
    pickByMethodLoop = function()
        if selectedUid then
            local selected = eggsFeature.get and eggsFeature.get(selectedUid) or nil
            if selected and selected.uid then
                return selected
            end
        end
        local list = eggsFeature.list({}, true)
        if type(list) == "table" and #list > 0 then
            return list[1]
        end
        clearAllHubTargetNotifier()
        return nil, "No egg available"
    end

    -- Picks ONLY from the selected rarities. This is a ONE-EGG-AT-A-TIME queue:
    --   1) stay at Safe Zone until a matching egg exists;
    --   2) choose the highest-priority rarity;
    --   3) within that rarity choose the largest/value-highest egg;
    --   4) grab/carry -> deliver to Safe Zone;
    --   5) only after delivery completes, scan again for the next egg.
    -- Thus 2 Divine + 1 Eternal + 1 Secret is consumed as:
    -- Divine(biggest) -> Divine(next biggest) -> Eternal -> Secret.
    pickByRarityPriority = function()
        -- Prefer the background scanner's latest snapshot. It has been running
        -- continuously even while the previous egg was being carried/delivered.
        -- If the scanner has not produced its first frame yet, fall back to one
        -- immediate force-read so the first target never waits for the scanner.
        local list, scanAt = nil, 0
        local okLive, liveList, liveAt = pcall(function()
            return auto.liveEggSnapshot()
        end)
        if okLive and type(liveList) == "table" and #liveList > 0 then
            list, scanAt = liveList, liveAt
        else
            local ok, result = pcall(function()
                return eggsFeature.list({}, true)
            end)
            if ok and type(result) == "table" then
                list = result
                scanAt = os.clock()
            else
                list = {}
            end
        end

        -- Queue order follows the live game's RarityNumber (highest first).
        -- Only AFTER choosing the highest available rarity do we compare eggs
        -- inside that rarity by value.
        -- rarityOrder is discovered from Assets.Directory and sorted by the
        -- game's own RarityNumber, so newly added tiers automatically participate.
        for _, wantedKey in ipairs(rarityOrder) do
            if raritySelected[wantedKey] then
                local best, bestValue = nil, -math.huge

                -- First rank the already-fresh snapshot in memory. Do NOT call
                -- EggState.ReadFieldEgg once per candidate; that would turn a
                -- realtime picker into dozens of module reads every 0.01s.
                for _, e in ipairs(list) do
                    local r = normalizeRarity(e and e.rarity)
                    local match = false
                    for _, alias in ipairs(rarityAliases[wantedKey] or {}) do
                        if r == alias then
                            match = true
                            break
                        end
                    end

                    if match and e.uid then
                        local state = tostring(e.state or "")
                        if (state == "Slot" or state == "Dropped") and e.pos then
                            local value = tonumber(e.value) or 0
                            if value > bestValue then
                                best = e
                                bestValue = value
                            end
                        end
                    end
                end

                -- Only the winner gets one authoritative UID read. If it changed
                -- between scan and action, return nil so the next cycle uses the
                -- continuously updated list instead of stealing a stale target.
                if best then
                    local fresh = nil
                    pcall(function() fresh = eggsFeature.get(best.uid) end)
                    if fresh
                        and (fresh.state == "Slot" or fresh.state == "Dropped")
                        and fresh.pos then
                        -- The first matching egg after a NO-EGG scan is gated:
                        -- Safe Zone -> 3s settle OR Space x2 -> target.
                        if raritySafeGateArmed then
                            local gateOK = raritySafeZoneBeforeTarget(function()
                                return false
                            end)
                            if not gateOK then
                                return nil, "Safe Zone gate not ready"
                            end
                            raritySafeGateArmed = false
                        end
                        return fresh
                    end
                end
            end
        end
        -- No matching egg is available. Arm the Safe Zone gate so that when
        -- the first matching egg appears again, the worker must settle in Safe
        -- Zone before travelling to it.
        raritySafeGateArmed = true
        return nil, "No egg matches the selected rarity filter"
    end

    function updateRarityStatus()
        if autoRarityOn then
            local scanAge = 0
            pcall(function()
                local _, at = auto.liveEggSnapshot()
                scanAge = at > 0 and ((os.clock() - at) * 1000) or -1
            end)
            rarityStatus.Text = "LIVE SCAN  •  " .. selectedRaritySummary()
                .. (helpFriendsOn and "  •  FOREST DROP • HELP FRIENDS" or "  •  SAFE ZONE WAIT → HIGHEST PRIORITY")
                .. "  •  " .. (scanAge >= 0 and ("SCAN " .. math.floor(scanAge) .. "ms") or "SCANNING...")
            rarityStatus.TextColor3 = Color3.fromRGB(95, 235, 255)
        else
            rarityStatus.Text = "Selected: " .. selectedRaritySummary() .. "  •  Live scan is OFF"
            rarityStatus.TextColor3 = Color3.fromRGB(150, 165, 185)
        end
    end

autoRarityButton = Instance.new("TextButton", autoSection)
    autoRarityButton.Name = "AutoRaritySteal"
    autoRarityButton.Size = UDim2.new(0.49, -8, 0, 32)
    autoRarityButton.Position = UDim2.fromOffset(9, 510)
    autoRarityButton.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
    autoRarityButton.BackgroundTransparency = 0.05
    autoRarityButton.BorderSizePixel = 0
    autoRarityButton.Font = Enum.Font.GothamBold
    autoRarityButton.Text = "AUTO FARM EGG BY RARITY  [OFF]"
    autoRarityButton.TextColor3 = Color3.fromRGB(235, 245, 255)
    autoRarityButton.TextSize = 10
    autoRarityButton.ZIndex = 21
    Instance.new("UICorner", autoRarityButton).CornerRadius = UDim.new(0, 8)

rarityButtonStroke = Instance.new("UIStroke", autoRarityButton)
    rarityButtonStroke.Thickness = 1
    rarityButtonStroke.Transparency = 0.45
    rarityButtonStroke.Color = Color3.fromRGB(188, 67, 255)

    local mobileRarityOn = false
    local mobileRarityRun = 0
    local mobileRarityButton = Instance.new("TextButton", autoSection)
    mobileRarityButton.Name = "AutoRarityMobile"
    mobileRarityButton.Size = UDim2.new(0.51, -8, 0, 32)
    mobileRarityButton.Position = UDim2.new(0.49, 5, 0, 510)
    mobileRarityButton.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
    mobileRarityButton.BackgroundTransparency = 0.05
    mobileRarityButton.BorderSizePixel = 0
    mobileRarityButton.Font = Enum.Font.GothamBold
    mobileRarityButton.Text = "RARITY MOBILE  [OFF]"
    mobileRarityButton.TextColor3 = Color3.fromRGB(235, 245, 255)
    mobileRarityButton.TextSize = 9
    mobileRarityButton.ZIndex = 21
    Instance.new("UICorner", mobileRarityButton).CornerRadius = UDim.new(0, 8)
    local mobileRarityStroke = Instance.new("UIStroke", mobileRarityButton)
    mobileRarityStroke.Thickness = 1
    mobileRarityStroke.Transparency = 0.35
    mobileRarityStroke.Color = Color3.fromRGB(80, 210, 170)

helpFriendsButton = Instance.new("TextButton", autoSection)
    helpFriendsButton.Name = "AutoFarmRarityHelpFriends"
    helpFriendsButton.Size = UDim2.new(1, -18, 0, 32)
    helpFriendsButton.Position = UDim2.fromOffset(9, 549)
    helpFriendsButton.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
    helpFriendsButton.BackgroundTransparency = 0.05
    helpFriendsButton.BorderSizePixel = 0
    helpFriendsButton.Font = Enum.Font.GothamBold
    helpFriendsButton.Text = "AUTO FARM EGG BY RARITY • HELP FRIENDS  [OFF]"
    helpFriendsButton.TextColor3 = Color3.fromRGB(235, 248, 255)
    helpFriendsButton.TextSize = 9
    helpFriendsButton.ZIndex = 22
    Instance.new("UICorner", helpFriendsButton).CornerRadius = UDim.new(0, 8)
local helpFriendsStroke = Instance.new("UIStroke", helpFriendsButton)
    helpFriendsStroke.Thickness = 1
    helpFriendsStroke.Transparency = 0.35
    helpFriendsStroke.Color = Color3.fromRGB(90, 220, 150)

helpFriendsStatus = Instance.new("TextLabel", autoSection)
    helpFriendsStatus.Name = "AutoFarmRarityHelpFriendsStatus"
    helpFriendsStatus.Size = UDim2.new(1, -18, 0, 16)
    helpFriendsStatus.Position = UDim2.fromOffset(9, 583)
    helpFriendsStatus.BackgroundTransparency = 1
    helpFriendsStatus.Font = Enum.Font.Gotham
    helpFriendsStatus.Text = "OFF • normal Auto Farm delivery → Safe Zone"
    helpFriendsStatus.TextColor3 = Color3.fromRGB(150, 165, 185)
    helpFriendsStatus.TextSize = 8
    helpFriendsStatus.TextXAlignment = Enum.TextXAlignment.Left
    helpFriendsStatus.ZIndex = 21

    function setHelpFriendsVisual(on)
        helpFriendsOn = on and true or false
        helpFriendsButton.Text = helpFriendsOn
            and "AUTO FARM EGG BY RARITY • HELP FRIENDS  [ON]"
            or "AUTO FARM EGG BY RARITY • HELP FRIENDS  [OFF]"
        helpFriendsButton.BackgroundColor3 = helpFriendsOn
            and Color3.fromRGB(0, 115, 90)
            or Color3.fromRGB(23, 28, 38)
        helpFriendsStatus.Text = helpFriendsOn
            and "ON • same method → Forest • stop → Drop Egg for Friends"
            or "OFF • normal Auto Farm delivery → Safe Zone"
        helpFriendsStatus.TextColor3 = helpFriendsOn
            and Color3.fromRGB(120, 255, 190)
            or Color3.fromRGB(150, 165, 185)
    end

    local function setMobileRarityVisual(on)
        mobileRarityOn = on and true or false
        mobileRarityButton.Text = mobileRarityOn and "RARITY MOBILE  [ON]" or "RARITY MOBILE  [OFF]"
        mobileRarityButton.BackgroundColor3 = mobileRarityOn
            and Color3.fromRGB(0, 105, 125)
            or Color3.fromRGB(23, 28, 38)
    end

    local function stopMobileRarity(reason, silent)
        mobileRarityRun = mobileRarityRun + 1
        if mobileRarityOn then
            pcall(function() auto.setEnabled(false, "rarity_mobile") end)
        end
        setAllAutoFarmInstantGrab(false)
        setMobileRarityVisual(false)
        if not silent and reason then
            showNotification("RARITY MOBILE", tostring(reason), "info", 2.2)
        end
    end

    mobileRarityButton.Activated:Connect(function()
        if mobileRarityOn then
            stopMobileRarity("Mobile rarity stopped", false)
            return
        end
        if autoRarityOn or autoStealOn or comboOn or betaOn then
            showNotification("RARITY MOBILE", "Stop another Auto Farm mode first", "warn", 2.4)
            return
        end
        local anyRaritySelected = false
        for _, rarityKey in ipairs(rarityOrder) do
            if raritySelected[rarityKey] then anyRaritySelected = true break end
        end
        if not anyRaritySelected then
            showNotification("RARITY MOBILE", "Select at least one rarity first", "warn", 2.4)
            return
        end
        if autoStealMethod == "RIDE_GUARD" then
            local env = _G
            if type(getgenv) == "function" then
                local ok, e = pcall(getgenv)
                if ok and type(e) == "table" then env = e end
            end
            local api = env.__DELL_RIDE_GUARD_API
            if not api or type(api.beginDelivery) ~= "function" then
                showNotification("RARITY MOBILE", "Ride Guard is not ready", "warn", 2.6)
                return
            end
        end
        if hold.isOn() then pcall(function() hold.setEnabled(false) end) end
        if autoRarityOn then stopAutoRarity("Desktop rarity stopped for mobile mode") end
        if autoStealOn then
            pcall(function() auto.setEnabled(false, "farm") end)
            autoStealOn = false
            autoStealButton.Text = "AUTO STEAL  [OFF]"
            autoStealButton.BackgroundColor3 = Color3.fromRGB(34, 37, 52)
        end
        mobileRarityRun = mobileRarityRun + 1
        local run = mobileRarityRun
        setAllAutoFarmInstantGrab(true)
        safeAutoSetOptions("rarity_mobile", {
            pick = pickByRarityPriority,
            continuous = true,
            cycleDelay = math.max(0.9, stealDelay),
            fastMode = false,
            method = autoStealMethod,
            deliverySpeed = deliverySpeeds[autoStealMethod],
        })
        local ok, why = auto.setEnabled(true, "rarity_mobile")
        if ok == false then
            stopMobileRarity("ERROR: " .. tostring(why), true)
            return
        end
        setMobileRarityVisual(true)
        showNotification("RARITY MOBILE", "ON • lower scan rate • low UI refresh • phone optimized", "success", 3)
        -- No refreshEggView loop here. The worker scans the field at a lower
        -- cadence and the normal EggState UI remains event-driven.
        task.spawn(function()
            while gui.Parent and autoSection.Parent and mobileRarityOn and run == mobileRarityRun do
                pcall(updateRarityStatus)
                task.wait(0.55)
            end
        end)
    end)

    helpFriendsButton.Activated:Connect(function()
        setHelpFriendsVisual(not helpFriendsOn)
        -- If rarity/Combo is already running, apply the new terminal destination
        -- immediately to the same worker. No duplicate Auto Steal worker is made.
        if autoRarityOn or comboOn then
            pcall(function()
                safeAutoSetOptions("rarity", {
                    pick = pickByRarityPriority,
                    continuous = true,
                    cycleDelay = stealDelay,
                    fastMode = true,
                    method = autoStealMethod,
                })
            end)
        end
        showNotification("HELP FRIENDS", helpFriendsOn
            and "ON • Auto Farm Rarity will stop in Forest and drop the egg"
            or "OFF • Auto Farm Rarity returns to Safe Zone",
            helpFriendsOn and "success" or "info", 2.8)
    end)

    --------------------------------------------------------------------------
    -- AUTO COMBO: AUTO FARM EGG BY RARITY + STAY ON TREADMILL
    --
    -- Flow: stay on treadmill while waiting for a selected rarity -> when a
    -- matching egg exists, release the treadmill and suppress Jump/Space ->
    -- let the existing rarity worker take the highest-priority / largest egg
    -- and deliver it to Safe Zone -> after the current batch is exhausted,
    -- return to the treadmill and wait for the next egg.
    --
    -- The combo owns only the hand-off. Pickup, carry and delivery continue to
    -- use the proven Auto Farm Egg by Rarity worker, so its delivery path and
    -- continuous scanner are not duplicated here.
    --------------------------------------------------------------------------
comboOn = false
comboToken = 0
comboScanTarget = nil

    -- Forward declarations: these values are referenced by combo callbacks
    -- before their UI objects/functions are physically created below.
comboButton = nil
setAutoRarityVisual = nil
comboLastCycles = 0
comboJumpConn = nil
comboSavedAutoJump = nil
comboSavedJumpPower = nil
comboSavedUseJumpPower = nil

    function comboHumanoid()
        local char = player and player.Character
        return char and char:FindFirstChildOfClass("Humanoid") or nil
    end

    function comboSetJumpBlocked(blocked)
        local hum = comboHumanoid()
        if blocked then
            if hum then
                if comboSavedAutoJump == nil then comboSavedAutoJump = hum.AutoJumpEnabled end
                if comboSavedJumpPower == nil then comboSavedJumpPower = hum.JumpPower end
                if comboSavedUseJumpPower == nil then comboSavedUseJumpPower = hum.UseJumpPower end
                pcall(function() hum.AutoJumpEnabled = false end)
                pcall(function() hum.Jump = false end)
            end
            if not comboJumpConn then
                comboJumpConn = UserInputService.JumpRequest:Connect(function()
                    if not comboOn then return end
                    local h = comboHumanoid()
                    if h then pcall(function() h.Jump = false end) end
                end)
            end
        else
            if comboJumpConn then
                pcall(function() comboJumpConn:Disconnect() end)
                comboJumpConn = nil
            end
            if hum then
                if comboSavedAutoJump ~= nil then pcall(function() hum.AutoJumpEnabled = comboSavedAutoJump end) end
                if comboSavedUseJumpPower ~= nil then pcall(function() hum.UseJumpPower = comboSavedUseJumpPower end) end
                if comboSavedJumpPower ~= nil then pcall(function() hum.JumpPower = comboSavedJumpPower end) end
                pcall(function() hum.Jump = false end)
            end
            comboSavedAutoJump = nil
            comboSavedJumpPower = nil
            comboSavedUseJumpPower = nil
        end
    end

    function comboHasTarget()
        local ok, target = pcall(pickByRarityPriority)
        if ok and target and target.uid then
            comboScanTarget = target
            return true, target
        end
        comboScanTarget = nil
        return false, nil
    end

    -- The rarity worker deliberately stays alive at Safe Zone while it waits
    -- for the next selected egg. Combo uses that phase as the hand-off point:
    -- stop the worker, mount the treadmill, and let the combo wake it again
    -- only when the continuous scanner sees a real target.
    function comboLastAutoPhase()
        local ok, phases = pcall(function() return auto.phases() end)
        if ok and type(phases) == "table" and #phases > 0 then
            return tostring(phases[#phases])
        end
        return ""
    end

    function comboSetVisual(on, text)
        comboOn = on and true or false
        comboButton.Text = text or (comboOn
            and "AUTO COMBO  •  EGG RARITY + TREADMILL  [ON]"
            or "AUTO COMBO  •  EGG RARITY + TREADMILL  [OFF]")
        comboButton.BackgroundColor3 = comboOn
            and Color3.fromRGB(0, 120, 150)
            or Color3.fromRGB(23, 28, 38)
    end

    comboButton = Instance.new("TextButton", autoSection)
    comboButton.Name = "AutoComboEggRarityTreadmill"
    comboButton.Size = UDim2.new(1, -18, 0, 32)
    comboButton.Position = UDim2.fromOffset(9, 606)
    comboButton.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
    comboButton.BackgroundTransparency = 0.05
    comboButton.BorderSizePixel = 0
    comboButton.Font = Enum.Font.GothamBold
    comboButton.Text = "AUTO COMBO  •  EGG RARITY + TREADMILL  [OFF]"
    comboButton.TextColor3 = Color3.fromRGB(235, 248, 255)
    comboButton.TextSize = 9
    comboButton.ZIndex = 22
    Instance.new("UICorner", comboButton).CornerRadius = UDim.new(0, 8)
comboStroke = Instance.new("UIStroke", comboButton)
    comboStroke.Thickness = 1
    comboStroke.Transparency = 0.35
    comboStroke.Color = Color3.fromRGB(70, 220, 255)

comboStatus = Instance.new("TextLabel", autoSection)
    comboStatus.Name = "AutoComboStatus"
    comboStatus.Size = UDim2.new(1, -18, 0, 17)
    comboStatus.Position = UDim2.fromOffset(9, 640)
    comboStatus.BackgroundTransparency = 1
    comboStatus.Font = Enum.Font.Gotham
    comboStatus.Text = "Combo OFF  •  Treadmill manual"
    comboStatus.TextColor3 = Color3.fromRGB(150, 165, 185)
    comboStatus.TextSize = 8
    comboStatus.TextXAlignment = Enum.TextXAlignment.Left
    comboStatus.ZIndex = 21

    function comboStop(reason, keepTreadmill)
        comboToken = comboToken + 1
        comboScanTarget = nil
        if autoRarityOn then
            pcall(function() auto.setEnabled(false, "rarity") end)
        end
        if keepTreadmill then
            pcall(function() hold.setEnabled(true) end)
        else
            pcall(function() hold.setEnabled(false) end)
        end
        comboSetJumpBlocked(false)
        comboSetVisual(false)
        comboStatus.Text = reason or "Combo OFF  •  Treadmill manual"
        comboStatus.TextColor3 = Color3.fromRGB(150, 165, 185)
    end

    comboButton.Activated:Connect(function()
        if riftFarmOn or mobileRarityOn then
            showNotification("AUTO COMBO", "Stop Rift/Mobile Rarity mode first", "info", 2.2)
            return
        end
        if comboOn then
            comboStop("Combo OFF  •  Treadmill manual", false)
            showNotification("AUTO COMBO", "Stopped", "info", 2.0)
            return
        end

        local anyRaritySelected = false
        for _, rarityKey in ipairs(rarityOrder) do
            if raritySelected[rarityKey] then anyRaritySelected = true break end
        end
        if not anyRaritySelected then
            comboStatus.Text = "Pilih minimal 1 rarity terlebih dahulu"
            comboStatus.TextColor3 = Color3.fromRGB(255, 175, 110)
            showNotification("AUTO COMBO", "Pilih rarity terlebih dahulu", "warn", 2.4)
            return
        end

        -- Combo becomes the owner of the rarity worker.
        if autoRarityOn then
            pcall(function() auto.setEnabled(false, "rarity") end)
            setAutoRarityVisual(false)
        end
        if autoStealOn then
            pcall(function() auto.setEnabled(false, "farm") end)
            autoStealOn = false
            autoStealButton.Text = "AUTO STEAL  [OFF]"
            autoStealButton.BackgroundColor3 = Color3.fromRGB(34, 37, 52)
        end

        comboOn = true
        comboToken = comboToken + 1
        local myToken = comboToken
        comboLastCycles = (auto.status() or {}).cycles or 0
        -- Requested idle state: the combo starts parked on the treadmill.
        -- Jump/Space is NOT blocked while we are waiting; it is blocked only
        -- after an egg appears and the treadmill is released for the run.
        comboSetJumpBlocked(false)
        pcall(function() hold.setEnabled(true) end)
        comboSetVisual(true, "AUTO COMBO  •  EGG RARITY + TREADMILL  [ON]")
        comboStatus.Text = "LIVE SCAN • STAY ON TREADMILL • waiting for selected rarity"
        comboStatus.TextColor3 = Color3.fromRGB(95, 235, 255)

        task.spawn(function()
            while gui.Parent and comboOn and myToken == comboToken and BX.alive() do
                local found = false
                local target = nil
                pcall(function() found, target = comboHasTarget() end)

                if found then
                    -- A real target exists: get OFF the treadmill first, then
                    -- hand the complete pickup/carry/delivery job to the proven
                    -- Auto Farm Egg by Rarity worker.
                    pcall(function() hold.setEnabled(false) end)
                    comboSetJumpBlocked(true)
                    comboStatus.Text = "EGG FOUND: " .. tostring(target and target.rarity or "?")
                        .. " • " .. tostring(target and target.name or "?")
                        .. " • TREADMILL OFF → RARITY FARM → HELP FRIENDS / SAFE ZONE"
                    comboStatus.TextColor3 = Color3.fromRGB(95, 235, 255)

                    if not auto.isRunning() then
                        autoRarityRun = autoRarityRun + 1
        raritySafeGateArmed = true
                        safeAutoSetOptions("rarity", {
                            pick = pickByRarityPriority,
                            continuous = true,
                            cycleDelay = stealDelay,
                            fastMode = true,
                            method = autoStealMethod,
                        })
                        local ok = auto.setEnabled(true, "rarity")
                        if ok == false then
                            comboSetJumpBlocked(false)
                            pcall(function() hold.setEnabled(true) end)
                            comboStatus.Text = "AUTO RARITY gagal start • STAY ON TREADMILL"
                            comboStatus.TextColor3 = Color3.fromRGB(255, 175, 110)
                        else
                            comboLastCycles = tonumber((auto.status() or {}).cycles) or comboLastCycles
                            setAutoRarityVisual(true)
                        end
                    end
                else
                    local stAuto = auto.status()
                    local cyclesNow = tonumber(stAuto and stAuto.cycles) or comboLastCycles
                    local runningNow = stAuto and stAuto.running == true
                    local phaseNow = comboLastAutoPhase()

                    -- If the rarity worker is alive but has reached its own
                    -- SAFE_ZONE_WAIT phase, it is genuinely idle. This is the
                    -- exact moment the combo should remount the treadmill.
                    -- We stop that worker here so Stay On Treadmill can own the
                    -- character without fighting the autosteal state flag.
                    if runningNow and phaseNow == "SAFE_ZONE_WAIT" then
                        pcall(function() auto.setEnabled(false, "rarity") end)
                        setAutoRarityVisual(false)
                        comboSetJumpBlocked(false)
                        pcall(function() hold.setEnabled(true) end)
                        comboStatus.Text = "NO MATCHING EGG • STAY ON TREADMILL • LIVE SCAN"
                        comboStatus.TextColor3 = Color3.fromRGB(120, 255, 190)

                    elseif runningNow and cyclesNow > comboLastCycles then
                        -- A confirmed delivery completed. Re-scan immediately.
                        comboLastCycles = cyclesNow
                        task.wait(0.05)
                        local stillHas = false
                        pcall(function() stillHas = comboHasTarget() end)
                        if not stillHas then
                            pcall(function() auto.setEnabled(false, "rarity") end)
                            setAutoRarityVisual(false)
                            comboSetJumpBlocked(false)
                            pcall(function() hold.setEnabled(true) end)
                            comboStatus.Text = "DELIVERED • queue empty • STAY ON TREADMILL"
                            comboStatus.TextColor3 = Color3.fromRGB(120, 255, 190)
                        else
                            -- More eggs remain: keep treadmill OFF and let the
                            -- same worker take the next highest rarity / largest
                            -- value egg without remounting in between.
                            comboSetJumpBlocked(true)
                            pcall(function() hold.setEnabled(false) end)
                            comboStatus.Text = "NEXT EGG READY • priority continues • TREADMILL OFF"
                            comboStatus.TextColor3 = Color3.fromRGB(95, 235, 255)
                        end

                    elseif not runningNow then
                        -- Worker ended unexpectedly or after a failed start.
                        -- Return to the requested idle state instead of leaving
                        -- the player stranded off the treadmill.
                        comboSetJumpBlocked(false)
                        pcall(function() hold.setEnabled(true) end)
                        comboStatus.Text = "NO MATCHING EGG • STAY ON TREADMILL • LIVE SCAN"
                        comboStatus.TextColor3 = Color3.fromRGB(120, 255, 190)

                    else
                        -- The worker is actively carrying / returning /
                        -- delivering. Do NOT remount the treadmill here.
                        comboSetJumpBlocked(true)
                        comboStatus.Text = "EGG RUNNING • " .. (phaseNow ~= "" and phaseNow or "DELIVERY")
                            .. " • TREADMILL OFF"
                        comboStatus.TextColor3 = Color3.fromRGB(95, 235, 255)
                    end
                end

                task.wait(0.06)
            end
        end)

        showNotification("AUTO COMBO", "Treadmill wait → rarity priority → grab/carry → Forest/ Safe Zone → treadmill", "success", 3.2)
    end)

    --------------------------------------------------------------------------
    -- AUTO FARM BY RARITY {BETA TEST} - RECOMMENDED / STABLE PROFILE
    --
    -- Beta is intentionally aligned with the proven Auto Farm Egg By Rarity
    -- worker instead of maintaining a second experimental pickup/delivery
    -- implementation. This removes the old Beta-only failure modes:
    --   * separate reverse-delivery path
    --   * separate carry-speed tuning
    --   * duplicate pickup/recovery logic
    --   * desynchronisation between Beta and normal rarity farming
    --
    -- Recommended flow:
    --   SAFE ZONE -> wait for selected rarity -> highest priority/value
    --   -> proven Auto Farm Egg By Rarity pickup -> Safe Zone delivery
    --   -> claim confirmation -> scan again.
    --
    -- Therefore every speed/re-anchor/refresh/safety improvement made to the
    -- normal rarity worker is automatically used by Beta as well.
    --------------------------------------------------------------------------
betaOn = false
betaRun = 0

betaButton = Instance.new("TextButton", autoSection)
    betaButton.Name = "AutoFarmRarityBeta"
    betaButton.Size = UDim2.new(1, -18, 0, 32)
    betaButton.Position = UDim2.fromOffset(9, 665)
    betaButton.BackgroundColor3 = Color3.fromRGB(65, 50, 20)
    betaButton.BackgroundTransparency = 0.04
    betaButton.BorderSizePixel = 0
    betaButton.Font = Enum.Font.GothamBold
    betaButton.Text = "🧪 AUTO FARM BY RARITY  {BETA TEST}  [OFF]"
    betaButton.TextColor3 = Color3.fromRGB(255, 240, 190)
    betaButton.TextSize = 10
    betaButton.ZIndex = 22
    Instance.new("UICorner", betaButton).CornerRadius = UDim.new(0, 8)
betaStroke = Instance.new("UIStroke", betaButton)
    betaStroke.Thickness = 1
    betaStroke.Transparency = 0.25
    betaStroke.Color = Color3.fromRGB(255, 190, 60)

betaStatus = Instance.new("TextLabel", autoSection)
    betaStatus.Name = "AutoFarmRarityBetaStatus"
    betaStatus.Size = UDim2.new(1, -18, 0, 17)
    betaStatus.Position = UDim2.fromOffset(9, 699)
    betaStatus.BackgroundTransparency = 1
    betaStatus.Font = Enum.Font.Gotham
    betaStatus.Text = "BETA OFF • SAME ENGINE AS AUTO FARM BY RARITY"
    betaStatus.TextColor3 = Color3.fromRGB(170, 160, 135)
    betaStatus.TextSize = 8
    betaStatus.TextXAlignment = Enum.TextXAlignment.Left
    betaStatus.ZIndex = 22

    function betaVisual(on, status)
        betaOn = on and true or false
        betaButton.Text = betaOn
            and "🧪 AUTO FARM BY RARITY  {BETA TEST}  [ON]"
            or "🧪 AUTO FARM BY RARITY  {BETA TEST}  [OFF]"
        betaButton.BackgroundColor3 = betaOn
            and Color3.fromRGB(125, 82, 15)
            or Color3.fromRGB(65, 50, 20)
        betaStatus.Text = status or (betaOn
            and "BETA ON • PROVEN RARITY ENGINE → SAFE ZONE"
            or "BETA OFF • SAME ENGINE AS AUTO FARM BY RARITY")
        betaStatus.TextColor3 = betaOn
            and Color3.fromRGB(255, 220, 120)
            or Color3.fromRGB(170, 160, 135)
    end

    function stopBeta(reason)
        betaRun = betaRun + 1
        if betaOn then
            pcall(function() auto.setEnabled(false, "rarity") end)
            setAutoRarityVisual(false)
        end
        betaVisual(false, reason or "BETA OFF • same engine as Auto Farm Egg By Rarity")
    end

    betaButton.Activated:Connect(function()
        if betaOn then
            stopBeta("BETA stopped")
            showNotification("BETA TEST", "Auto Farm By Rarity stopped", "info", 2.2)
            return
        end

        local anyRaritySelected = false
        for _, rarityKey in ipairs(rarityOrder) do
            if raritySelected[rarityKey] then
                anyRaritySelected = true
                break
            end
        end
        if not anyRaritySelected then
            betaStatus.Text = "Pilih minimal 1 rarity terlebih dahulu"
            betaStatus.TextColor3 = Color3.fromRGB(255, 175, 110)
            showNotification("BETA TEST", "Pilih rarity terlebih dahulu", "warn", 2.4)
            return
        end

        -- Beta becomes the only movement owner. It deliberately hands the
        -- entire job to the exact same rarity worker used by Auto Farm Egg By
        -- Rarity, rather than running a second implementation.
        if comboOn then
            pcall(function() comboStop("Combo handed to BETA TEST", false) end)
        end
        if autoRarityOn then
            pcall(function() auto.setEnabled(false, "rarity") end)
            setAutoRarityVisual(false)
        end
        if autoStealOn then
            pcall(function() auto.setEnabled(false, "farm") end)
            autoStealOn = false
            autoStealButton.Text = "AUTO STEAL  [OFF]"
            autoStealButton.BackgroundColor3 = Color3.fromRGB(34, 37, 52)
        end
        pcall(function() hold.setEnabled(false) end)

        betaRun = betaRun + 1
        raritySafeGateArmed = true

        -- IMPORTANT: use the same options as the normal Auto Farm Egg By
        -- Rarity feature. This keeps delivery, claim wait, recovery, speed,
        -- and target-selection behaviour identical and proven.
        safeAutoSetOptions("rarity", {
            pick = pickByRarityPriority,
            continuous = true,
            cycleDelay = stealDelay,
            fastMode = true,
            method = autoStealMethod,
            deliverySpeed = deliverySpeeds[autoStealMethod],
        })

        local ok, why = auto.setEnabled(true, "rarity")
        if ok == false then
            betaVisual(false, "BETA ERROR: " .. tostring(why))
            return
        end

        setAutoRarityVisual(true)
        betaVisual(true, "BETA ON • SAFE ZONE → HIGHEST RARITY/VALUE → DELIVERY")
        showNotification(
            "BETA TEST",
            "Recommended stable profile: same engine as Auto Farm Egg By Rarity",
            "success",
            3.0
        )

        local myRun = betaRun
        task.spawn(function()
            while gui.Parent and autoSection.Parent and betaOn and myRun == betaRun and BX.alive() do
                local stNow = auto.status()
                local runningNow = stNow and stNow.running == true
                local phaseNow = comboLastAutoPhase()

                if not runningNow then
                    betaStatus.Text = "BETA • worker stopped • SAFE ZONE WAIT"
                    betaStatus.TextColor3 = Color3.fromRGB(255, 190, 120)
                    break
                end

                if phaseNow == "SAFE_ZONE_WAIT" then
                    betaStatus.Text = "BETA • SAFE ZONE • LIVE SCAN • WAITING FOR SELECTED RARITY"
                elseif phaseNow ~= "" then
                    betaStatus.Text = "BETA • " .. phaseNow .. " • PROVEN RARITY ENGINE"
                else
                    betaStatus.Text = "BETA • LIVE RARITY FARM • SAFE ZONE DELIVERY"
                end

                task.wait(0.08)
            end
        end)
    end)

    -- STEAL SPEED: delay between completed egg cycles. Lower = faster.
    speedTitle = Instance.new("TextLabel", autoSection)
    speedTitle.Name = "StealSpeedTitle"
    speedTitle.Size = UDim2.new(1, -18, 0, 17)
    speedTitle.Position = UDim2.fromOffset(9, 725)
    speedTitle.BackgroundTransparency = 1
    speedTitle.Font = Enum.Font.GothamBold
    speedTitle.Text = "STEAL SPEED  •  LOWER DELAY = FASTER"
    speedTitle.TextColor3 = Color3.fromRGB(135, 220, 255)
    speedTitle.TextSize = 9
    speedTitle.TextXAlignment = Enum.TextXAlignment.Left
    speedTitle.ZIndex = 21

    speedMinus = Instance.new("TextButton", autoSection)
    speedMinus.Size = UDim2.fromOffset(36, 30)
    speedMinus.Position = UDim2.fromOffset(9, 746)
    speedMinus.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
    speedMinus.BorderSizePixel = 0
    speedMinus.Font = Enum.Font.GothamBold
    speedMinus.Text = "−"
    speedMinus.TextColor3 = Color3.fromRGB(235, 245, 255)
    speedMinus.TextSize = 16
    speedMinus.ZIndex = 22
    Instance.new("UICorner", speedMinus).CornerRadius = UDim.new(0, 7)

    speedValue = Instance.new("TextLabel", autoSection)
    speedValue.Size = UDim2.new(1, -92, 0, 30)
    speedValue.Position = UDim2.fromOffset(51, 746)
    speedValue.BackgroundColor3 = Color3.fromRGB(16, 20, 29)
    speedValue.BackgroundTransparency = 0.05
    speedValue.BorderSizePixel = 0
    speedValue.Font = Enum.Font.GothamBold
    speedValue.TextColor3 = Color3.fromRGB(100, 225, 255)
    speedValue.TextSize = 10
    speedValue.ZIndex = 22
    Instance.new("UICorner", speedValue).CornerRadius = UDim.new(0, 7)

    speedPlus = Instance.new("TextButton", autoSection)
    speedPlus.Size = UDim2.fromOffset(36, 30)
    speedPlus.Position = UDim2.new(1, -45, 0, 746)
    speedPlus.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
    speedPlus.BorderSizePixel = 0
    speedPlus.Font = Enum.Font.GothamBold
    speedPlus.Text = "+"
    speedPlus.TextColor3 = Color3.fromRGB(235, 245, 255)
    speedPlus.TextSize = 16
    speedPlus.ZIndex = 22
    Instance.new("UICorner", speedPlus).CornerRadius = UDim.new(0, 7)

    superFastButton = Instance.new("TextButton", autoSection)
    superFastButton.Name = "SuperFastAutoSteal"
    superFastButton.Size = UDim2.new(1, -18, 0, 30)
    superFastButton.Position = UDim2.fromOffset(9, 785)
    superFastButton.BackgroundColor3 = Color3.fromRGB(0, 75, 105)
    superFastButton.BackgroundTransparency = 0.04
    superFastButton.BorderSizePixel = 0
    superFastButton.Font = Enum.Font.GothamBold
    superFastButton.Text = "⚡ SUPER FAST AUTO FARM EGG  [DIRECT • 0.02s]"
    superFastButton.TextColor3 = Color3.fromRGB(235, 250, 255)
    superFastButton.TextSize = 10
    superFastButton.ZIndex = 22
    Instance.new("UICorner", superFastButton).CornerRadius = UDim.new(0, 8)
sfStroke = Instance.new("UIStroke", superFastButton)
    sfStroke.Thickness = 1
    sfStroke.Color = Color3.fromRGB(211, 93, 255)
    sfStroke.Transparency = 0.35

    -- ===================== CLAIM TIMING CONTROLS =====================
    -- Primary and retry windows are editable independently.
    claimWaitTitle = Instance.new("TextLabel", autoSection)
    claimWaitTitle.Name = "ClaimWaitTitle"
    claimWaitTitle.Size = UDim2.new(1, -18, 0, 17)
    claimWaitTitle.Position = UDim2.fromOffset(9, 830)
    claimWaitTitle.BackgroundTransparency = 1
    claimWaitTitle.Font = Enum.Font.GothamBold
    claimWaitTitle.Text = "CLAIM WAIT  •  PRIMARY / RETRY (SECONDS)"
    claimWaitTitle.TextColor3 = Color3.fromRGB(135, 220, 255)
    claimWaitTitle.TextSize = 9
    claimWaitTitle.TextXAlignment = Enum.TextXAlignment.Left
    claimWaitTitle.ZIndex = 21

    claimWaitBox = Instance.new("TextBox", autoSection)
    claimWaitBox.Name = "ClaimWaitInput"
    claimWaitBox.Size = UDim2.new(0.5, -12, 0, 32)
    claimWaitBox.Position = UDim2.fromOffset(9, 866)
    claimWaitBox.BackgroundColor3 = Color3.fromRGB(16, 20, 29)
    claimWaitBox.BackgroundTransparency = 0.03
    claimWaitBox.BorderSizePixel = 0
    claimWaitBox.ClearTextOnFocus = false
    claimWaitBox.Font = Enum.Font.GothamBold
    claimWaitBox.PlaceholderText = "0.50"
    claimWaitBox.Text = "0.50"
    claimWaitBox.TextColor3 = Color3.fromRGB(100, 225, 255)
    claimWaitBox.PlaceholderColor3 = Color3.fromRGB(100, 120, 135)
    claimWaitBox.TextSize = 11
    claimWaitBox.TextXAlignment = Enum.TextXAlignment.Center
    claimWaitBox.ZIndex = 22
    Instance.new("UICorner", claimWaitBox).CornerRadius = UDim.new(0, 7)

    claimWaitRetryBox = Instance.new("TextBox", autoSection)
    claimWaitRetryBox.Name = "ClaimRetryWaitInput"
    claimWaitRetryBox.Size = UDim2.new(0.5, -12, 0, 32)
    claimWaitRetryBox.Position = UDim2.new(0.5, 3, 0, 866)
    claimWaitRetryBox.BackgroundColor3 = Color3.fromRGB(16, 20, 29)
    claimWaitRetryBox.BackgroundTransparency = 0.03
    claimWaitRetryBox.BorderSizePixel = 0
    claimWaitRetryBox.ClearTextOnFocus = false
    claimWaitRetryBox.Font = Enum.Font.GothamBold
    claimWaitRetryBox.PlaceholderText = "0.50"
    claimWaitRetryBox.Text = "0.50"
    claimWaitRetryBox.TextColor3 = Color3.fromRGB(255, 205, 120)
    claimWaitRetryBox.PlaceholderColor3 = Color3.fromRGB(100, 120, 135)
    claimWaitRetryBox.TextSize = 11
    claimWaitRetryBox.TextXAlignment = Enum.TextXAlignment.Center
    claimWaitRetryBox.ZIndex = 22
    Instance.new("UICorner", claimWaitRetryBox).CornerRadius = UDim.new(0, 7)

    claimWaitInfo = Instance.new("TextLabel", autoSection)
    claimWaitInfo.Name = "ClaimWaitInfo"
    claimWaitInfo.Size = UDim2.new(1, -18, 0, 34)
    claimWaitInfo.Position = UDim2.fromOffset(9, 905)
    claimWaitInfo.BackgroundTransparency = 1
    claimWaitInfo.Font = Enum.Font.Gotham
    claimWaitInfo.Text = "PRIMARY 0.50s   •   RETRY 0.50s   •   Enter / click outside to apply"
    claimWaitInfo.TextColor3 = Color3.fromRGB(145, 160, 180)
    claimWaitInfo.TextSize = 8
    claimWaitInfo.TextXAlignment = Enum.TextXAlignment.Center
    claimWaitInfo.ZIndex = 21

    claimWaitPrimaryLabel = Instance.new("TextLabel", autoSection)
    claimWaitPrimaryLabel.Size = UDim2.new(0.5, -12, 0, 14)
    claimWaitPrimaryLabel.Position = UDim2.fromOffset(9, 850)
    claimWaitPrimaryLabel.BackgroundTransparency = 1
    claimWaitPrimaryLabel.Font = Enum.Font.GothamBold
    claimWaitPrimaryLabel.Text = "PRIMARY"
    claimWaitPrimaryLabel.TextColor3 = Color3.fromRGB(135, 220, 255)
    claimWaitPrimaryLabel.TextSize = 8
    claimWaitPrimaryLabel.TextXAlignment = Enum.TextXAlignment.Center
    claimWaitPrimaryLabel.ZIndex = 23

    claimWaitRetryLabel = Instance.new("TextLabel", autoSection)
    claimWaitRetryLabel.Size = UDim2.new(0.5, -12, 0, 14)
    claimWaitRetryLabel.Position = UDim2.new(0.5, 3, 0, 850)
    claimWaitRetryLabel.BackgroundTransparency = 1
    claimWaitRetryLabel.Font = Enum.Font.GothamBold
    claimWaitRetryLabel.Text = "RETRY"
    claimWaitRetryLabel.TextColor3 = Color3.fromRGB(255, 205, 120)
    claimWaitRetryLabel.TextSize = 8
    claimWaitRetryLabel.TextXAlignment = Enum.TextXAlignment.Center
    claimWaitRetryLabel.ZIndex = 23

function applyClaimWait(raw)
    local value = tonumber(raw)
    if not value then
        claimWaitBox.Text = string.format("%.2f", tonumber(BX.require("features.carry").K.CLAIM_WAIT) or 0.5)
        return
    end
    value = math.clamp(value, 0.01, 15.0)
    value = math.floor(value * 100 + 0.5) / 100
    local carryFeature = BX.require("features.carry")
    carryFeature.K.CLAIM_WAIT = value
    claimWaitBox.Text = string.format("%.2f", value)
    local retry = tonumber(carryFeature.K.CLAIM_RETRY_WAIT) or 0.5
    claimWaitInfo.Text = string.format("PRIMARY %.2fs   •   RETRY %.2fs   •   aktif untuk delivery berikutnya", value, retry)
end

function applyClaimRetryWait(raw)
    local value = tonumber(raw)
    if not value then
        claimWaitRetryBox.Text = string.format("%.2f", tonumber(BX.require("features.carry").K.CLAIM_RETRY_WAIT) or 0.5)
        return
    end
    value = math.clamp(value, 0.01, 15.0)
    value = math.floor(value * 100 + 0.5) / 100
    local carryFeature = BX.require("features.carry")
    carryFeature.K.CLAIM_RETRY_WAIT = value
    claimWaitRetryBox.Text = string.format("%.2f", value)
    local primary = tonumber(carryFeature.K.CLAIM_WAIT) or 0.5
    claimWaitInfo.Text = string.format("PRIMARY %.2fs   •   RETRY %.2fs   •   aktif untuk delivery berikutnya", primary, value)
end

claimWaitBox.FocusLost:Connect(function()
    applyClaimWait(claimWaitBox.Text)
end)
claimWaitRetryBox.FocusLost:Connect(function()
    applyClaimRetryWait(claimWaitRetryBox.Text)
end)

pcall(function()
    local carryFeature = BX.require("features.carry")
    carryFeature.K.CLAIM_WAIT = 0.5
    carryFeature.K.CLAIM_RETRY_WAIT = 0.5
end)

    -- Forward-declare this callback helper.
    -- The old code declared it AFTER the MouseButton1Click closure, which made
    -- the closure resolve `updateSpeedUI` as a global. In the executor that
    -- global is nil, producing:
    --   attempt to call a nil value
updateSpeedUI = nil

    superFastButton.Activated:Connect(function()
        stealDelay = 0.05
        if autoRarityOn then
            pcall(function()
                safeAutoSetOptions("rarity", {
                    pick = pickByRarityPriority,
                    continuous = true,
                    cycleDelay = stealDelay,
                    fastMode = true,
                    method = autoStealMethod,
                })
            end)
        end
        if autoStealOn then
            pcall(function()
                safeAutoSetOptions("farm", {
                    pick = pickByMethodLoop,
                    continuous = true,
                    cycleDelay = stealDelay,
                    fastMode = true,
                    method = autoStealMethod,
                    deliverySpeed = deliverySpeeds[autoStealMethod],
                })
            end)
        end
        if updateSpeedUI then
            updateSpeedUI()
        end
        pcall(function()
            showNotification("SUPER FAST", "Live rarity scan → grab → Safe Zone loop enabled", "success", 2.2)
        end)
    end)

    updateSpeedUI = function()
        if not speedValue or not speedValue.Parent then return end
        local delay = tonumber(stealDelay) or 0.05
        local label =
            delay <= 0.05 and "SUPER FAST"
            or (delay <= 0.30 and "FAST"
            or (delay <= 0.80 and "NORMAL" or "SAFE"))
        speedValue.Text = string.format("%.2fs  •  %s", delay, label)
    end

    speedMinus.Activated:Connect(function()
        stealDelay = math.max(0.05, math.round((tonumber(stealDelay) or 0.05 - 0.10) * 100) / 100)
        if autoRarityOn then
            pcall(function()
                safeAutoSetOptions("rarity", {
                    pick = pickByRarityPriority,
                    continuous = true,
                    cycleDelay = stealDelay,
                    fastMode = true,
                    method = autoStealMethod,
                })
            end)
        end
        if autoStealOn then
            pcall(function()
                safeAutoSetOptions("farm", {
                    pick = pickByMethodLoop,
                    continuous = true,
                    cycleDelay = stealDelay,
                    fastMode = true,
                    method = autoStealMethod,
                    deliverySpeed = deliverySpeeds[autoStealMethod],
                })
            end)
        end
        if updateSpeedUI then updateSpeedUI() end
    end)
    speedPlus.Activated:Connect(function()
        stealDelay = math.min(3.00, math.round((tonumber(stealDelay) or 0.05 + 0.10) * 100) / 100)
        if autoRarityOn then
            pcall(function()
                safeAutoSetOptions("rarity", {
                    pick = pickByRarityPriority,
                    continuous = true,
                    cycleDelay = stealDelay,
                    fastMode = true,
                    method = autoStealMethod,
                })
            end)
        end
        if autoStealOn then
            pcall(function()
                safeAutoSetOptions("farm", {
                    pick = pickByMethodLoop,
                    continuous = true,
                    cycleDelay = stealDelay,
                    fastMode = true,
                    method = autoStealMethod,
                    deliverySpeed = deliverySpeeds[autoStealMethod],
                })
            end)
        end
        if updateSpeedUI then updateSpeedUI() end
    end)
    updateSpeedUI()

    updateRarityStatus()

    setAutoRarityVisual = function(on)
        autoRarityOn = on and true or false
        autoRarityButton.Text = autoRarityOn
            and "AUTO FARM EGG BY RARITY  [ON]"
            or "AUTO FARM EGG BY RARITY  [OFF]"
        autoRarityButton.BackgroundColor3 = autoRarityOn
            and Color3.fromRGB(0, 105, 145)
            or Color3.fromRGB(23, 28, 38)
        updateRarityStatus()
    end

    function stopAutoRarity(reason)
        autoRarityRun = autoRarityRun + 1
        setAllAutoFarmInstantGrab(false)
        if autoRarityOn then
            pcall(function() auto.setEnabled(false, "rarity") end)
        end
        setAutoRarityVisual(false)
        if reason then
            rarityStatus.Text = tostring(reason)
            showNotification("AUTO STEAL", tostring(reason), "info", 2.4)
        end
    end

    autoRarityButton.Activated:Connect(function()
        if riftFarmOn then
            showNotification("AUTO FARM EGG", "Stop AUTO FARM BY RIFT first", "info", 2.2)
            return
        end
        if mobileRarityOn then
            stopMobileRarity("Mobile rarity stopped for standard rarity", true)
        end
        if comboOn then
            showNotification("AUTO FARM EGG", "Matikan AUTO COMBO terlebih dahulu", "info", 2.2)
            return
        end
        if autoRarityOn then
            stopAutoRarity("Auto rarity stopped")
            return
        end

        local anyRaritySelected = false
        for _, rarityKey in ipairs(rarityOrder) do
            if raritySelected[rarityKey] then anyRaritySelected = true break end
        end
        if not anyRaritySelected then
            rarityStatus.Text = "Pilih minimal 1 rarity dari daftar filter"
            rarityStatus.TextColor3 = Color3.fromRGB(255, 175, 110)
            return
        end

        if autoStealMethod == "RIDE_GUARD" then
            local env = _G
            if type(getgenv) == "function" then
                local ok, e = pcall(getgenv)
                if ok and type(e) == "table" then env = e end
            end
            local api = env.__DELL_RIDE_GUARD_API
            if not api or type(api.beginDelivery) ~= "function" then
                rarityStatus.Text = "RIDE GUARD belum siap • aktifkan Ride Guard / pilih Guard"
                showNotification("RARITY METHOD", "Ride Guard is not ready", "warn", 2.6)
                return
            end
        end

        if hold.isOn() then hold.setEnabled(false) end

        -- The two modes share the same Auto Steal engine. Never let the manual
        -- single-egg mode and rarity mode fight over the same worker.
        if autoStealOn then
            pcall(function() auto.setEnabled(false, "farm") end)
            autoStealOn = false
            autoStealButton.Text = "AUTO STEAL  [OFF]"
            autoStealButton.BackgroundColor3 = Color3.fromRGB(34, 37, 52)
        end

        -- Force one fresh scan immediately when the feature is enabled.
        local okScan, scan = pcall(function() return eggsFeature.list({}, true) end)
        if not okScan or type(scan) ~= "table" then
            rarityStatus.Text = "EGG SCAN FAILED - retrying..."
        end

        autoRarityRun = autoRarityRun + 1
        local run = autoRarityRun
        setAllAutoFarmInstantGrab(true)
        safeAutoSetOptions("rarity", {
            pick = pickByRarityPriority,
            continuous = true,
            cycleDelay = stealDelay,
            fastMode = true,
            method = autoStealMethod,
        })

        local ok, why = auto.setEnabled(true, "rarity")
        if ok == false then
            setAllAutoFarmInstantGrab(false)
            setAutoRarityVisual(false)
            rarityStatus.Text = "AUTO RARITY ERROR: " .. tostring(why)
            return
        end

        setAutoRarityVisual(true)
        showNotification("AUTO FARM EGG", helpFriendsOn and "FOREST DROP • HELP FRIENDS • LIVE RARITY DIRECTORY" or "SAFE ZONE WAIT • LIVE RARITY DIRECTORY • highest priority first", "success", 3.0)

        -- Keep the visible list fresh while this mode is active. This is UI-only;
        -- the actual steal remains owned by the single Auto Steal worker.
        task.spawn(function()
            while gui.Parent and autoSection.Parent and autoRarityOn and run == autoRarityRun do
                pcall(refreshEggView)
                task.wait(0.12)
            end
        end)
    end)

    function setSecondAutoVisual(on)
        autoStealOn = on and true or false
        setAllAutoFarmInstantGrab(autoStealOn)
        autoStealButton.Text = autoStealOn and "AUTO STEAL  [ON]" or "AUTO STEAL  [OFF]"
        autoStealButton.BackgroundColor3 = autoStealOn
            and Color3.fromRGB(0, 105, 145)
            or Color3.fromRGB(34, 37, 52)
    end

    function normalizeSearchText(value)
        return tostring(value or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    end

    function eggMatchesSearch(e)
        if eggSearchText == "" then return true end
        local name = normalizeSearchText(e and e.name or "")
        local rarity = normalizeSearchText(e and e.rarity or "")
        return name:find(eggSearchText, 1, true) ~= nil
            or rarity:find(eggSearchText, 1, true) ~= nil
    end

    function describeEgg(e)
        local name = tostring(e.name or "Unknown Egg")
        local rarity = tostring(e.rarity or "?")
        local kg = tonumber(e.kg) or 0
        local rate = eggsFeature.formatRate(e.value or 0)
        return string.format("%s  •  %s  •  %.1fkg  •  %s/s", name, rarity, kg, rate)
    end

    function selectEgg(e)
        if not e or not e.uid then return end
        selectedUid = tostring(e.uid)
        selectedText.Text = "SELECTED EGG: " .. tostring(e.name or "Unknown")
            .. "\n" .. tostring(e.rarity or "?") .. " • " .. string.format("%.1fkg", tonumber(e.kg) or 0)

        if autoStealOn then
            safeAutoSetOptions("farm", {
                pick = pickByMethodLoop,
                continuous = true,
                cycleDelay = stealDelay,
                fastMode = true,
                method = autoStealMethod,
                deliverySpeed = deliverySpeeds[autoStealMethod],
            })
        end
    end

    function clearEggButtons()
        for _, child in ipairs(eggList:GetChildren()) do
            -- The old version only removed TextButtons, so every refresh with
            -- an empty result left another "NO EGGS FOUND" label behind.
            if child:IsA("TextButton") or child:IsA("TextLabel") then
                child:Destroy()
            end
        end
    end

    function refreshEggView()
        if not autoSection.Parent or refreshBusy then return end
        refreshBusy = true

        local list = {}
        local ok, result = pcall(function() return eggsFeature.list({}) end)
        if ok and type(result) == "table" then list = result end

        -- When the selected egg has just been grabbed, the server may briefly
        -- remove it from the live list. Wait for a real non-empty refresh before
        -- deciding that the search target is gone, then clear the search so the
        -- complete egg list appears again instead of leaving "NO MATCH" stuck.
        if #list > 0 and selectedUid then
            local selectedStillExists = false
            for _, e in ipairs(list) do
                if tostring(e.uid) == tostring(selectedUid) then
                    selectedStillExists = true
                    break
                end
            end
            if not selectedStillExists then
                selectedMissingTicks = selectedMissingTicks + 1
            else
                selectedMissingTicks = 0
            end

            if autoStealOn and selectedMissingTicks >= 2 and eggSearchText ~= "" then
                eggSearch.Text = ""
                eggSearchText = ""
                selectedMissingTicks = 0
            end
        else
            selectedMissingTicks = 0
        end

        clearEggButtons()
        local filtered = {}
        local hasRaritySelection = false
        for _, rarityKey in ipairs(rarityOrder) do
            if raritySelected[rarityKey] then hasRaritySelection = true break end
        end
        for _, e in ipairs(list) do
            local rarityOK = (not hasRaritySelection) or rarityIsSelected(e and e.rarity)
            if rarityOK and eggMatchesSearch(e) then filtered[#filtered + 1] = e end
        end

        if #filtered == 0 then
            local empty = Instance.new("TextLabel", eggList)
            empty.Name = "EmptyState"
            empty.Size = UDim2.new(1, -4, 0, 58)
            empty.BackgroundTransparency = 1
            empty.Font = Enum.Font.GothamBold
            empty.Text = eggSearchText ~= ""
                and ("NO MATCH\n\"" .. eggSearchText .. "\"")
                or "NO EGGS FOUND"
            empty.TextColor3 = Color3.fromRGB(125, 165, 185)
            empty.TextSize = 11
            empty.TextWrapped = true
            empty.ZIndex = 22
            showNotification(
                "ALL HUB NOTIFIER",
                eggSearchText ~= ""
                    and ("No egg matches: " .. eggSearchText)
                    or "No egg found. Waiting for the next refresh...",
                "warn",
                2.8
            )
            refreshBusy = false
            return
        end

        -- A successful scan replaces the warning with a compact success toast.
        if autoRarityOn then
            showNotification(
                "ALL HUB NOTIFIER",
                string.format("%d matching egg%s found • rarity priority active", #filtered, #filtered == 1 and "" or "s"),
                "success",
                2.2
            )
        end

        for index, e in ipairs(filtered) do
            local b = Instance.new("TextButton", eggList)
            b.LayoutOrder = index
            b.Size = UDim2.new(1, -2, 0, 50)
            b.BackgroundColor3 = (selectedUid == tostring(e.uid))
                and Color3.fromRGB(8, 75, 100)
                or Color3.fromRGB(16, 24, 31)
            b.BackgroundTransparency = 0.04
            b.BorderSizePixel = 0
            b.Font = Enum.Font.GothamBold
            b.Text = "  " .. describeEgg(e)
            b.TextColor3 = Color3.fromRGB(238, 248, 255)
            b.TextSize = 11
            b.TextXAlignment = Enum.TextXAlignment.Left
            b.TextTruncate = Enum.TextTruncate.AtEnd
            b.ZIndex = 22
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)

            local bs = Instance.new("UIStroke", b)
            bs.Thickness = 1.2
            bs.Transparency = selectedUid == tostring(e.uid) and 0.05 or 0.70
            bs.Color = Color3.fromRGB(188, 67, 255)

            b.Activated:Connect(function()
                selectEgg(e)
                refreshEggView()
            end)
        end
        refreshBusy = false
    end

    autoStealButton.Activated:Connect(function()
        if riftFarmOn then
            showNotification("AUTO STEAL", "Stop AUTO FARM BY RIFT first", "info", 2.2)
            return
        end
        if mobileRarityOn then
            showNotification("AUTO STEAL", "Stop RARITY MOBILE first", "info", 2.2)
            return
        end
        if autoRarityOn then stopAutoRarity("Stop Auto Rarity before using manual Auto Steal") return end
        if not autoStealOn then
            if not selectedUid then
                selectedText.Text = "SELECTED EGG: PICK AN EGG FIRST"
                return
            end
            if hold.isOn() then hold.setEnabled(false) end

            safeAutoSetOptions("farm", {
                pick = pickByMethodLoop,
                continuous = true,
                cycleDelay = stealDelay,
                fastMode = true,
                method = autoStealMethod,
                deliverySpeed = deliverySpeeds[autoStealMethod],
            })
            local ok, why = auto.setEnabled(true, "farm")
            if ok == false then
                setSecondAutoVisual(false)
                selectedText.Text = "AUTO STEAL ERROR: " .. tostring(why)
                return
            end
            setSecondAutoVisual(true)
            pcall(updateMethodVisual, true)
        else
            auto.setEnabled(false, "farm")
            setSecondAutoVisual(false)
            pcall(updateMethodVisual, false)
            showNotification("AUTO STEAL", "Manual Auto Steal stopped", "info", 2.4)
        end
    end)

    eggSearch:GetPropertyChangedSignal("Text"):Connect(function()
        eggSearchText = normalizeSearchText(eggSearch.Text)
        refreshEggView()
    end)

    pcall(function()
        auto.onStop(function(_, whose)
            if whose == "rift" then
                riftFarmOn = false
                setAllAutoFarmInstantGrab(false)
                if riftFarm and riftFarm.Parent then
                    riftFarm.Text = "AUTO FARM EGG BY RIFT  [OFF]"
                    riftFarm.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
                    riftFarmStatus.Text = "OFF • Rift Farm worker ended"
                    riftFarmStatus.TextColor3 = Color3.fromRGB(145, 165, 178)
                end
                task.defer(paintRiftUI)
            elseif whose == "rarity_mobile" then
                mobileRarityRun = mobileRarityRun + 1
                mobileRarityOn = false
                setAllAutoFarmInstantGrab(false)
                if mobileRarityButton and mobileRarityButton.Parent then
                    mobileRarityButton.Text = "RARITY MOBILE  [OFF]"
                    mobileRarityButton.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
                end
                task.defer(updateRarityStatus)
            elseif whose == "rarity" then
                setAutoRarityVisual(false)
                autoRarityRun = autoRarityRun + 1
                task.defer(refreshEggView)
            elseif whose == "farm" then
                setSecondAutoVisual(false)
                autoStealOn = false
                pcall(updateMethodVisual, false)
                -- A completed/ended steal should never leave the previous
                -- search filter hiding the refreshed egg list.
                selectedMissingTicks = 0
                if eggSearchText ~= "" then
                    eggSearch.Text = ""
                    eggSearchText = ""
                end
                task.defer(refreshEggView)
            end
        end)
    end)

    task.spawn(function()
        while gui.Parent and autoSection.Parent do
            pcall(refreshEggView)
            task.wait(1)
        end
    end)


    refreshEggView()

    -- ===================== DELIVERY SAFETY =====================
    -- Client-side safety/diagnostics only. This does NOT bypass or disable
    -- server anti-cheat. It prevents the client from continuing a delivery
    -- after an obvious state mismatch or character teardown.
deliverySafety = {
        enabled = true,
        maxCharacterJump = 220,
        maxWatchGap = 1.5,
    }

    function validateDeliveryState(uid)
        if not deliverySafety.enabled then return true end
        if not uid then return false, "missing egg uid" end

        local egg = eggsFeature.get(uid)
        if not egg then
            return false, "egg record unavailable"
        end

        local state = tostring(egg.state or "")
        if state ~= "Carried" then
            return false, "egg state is " .. state
        end

        local character = game:GetService("Players").LocalPlayer.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not root then
            return false, "character root unavailable"
        end

        return true
    end

    -- ===================== DELIVERY SPEEDS =====================
    -- Each Delivery Egg -> Safe Zone method has its own speed control.
deliverySpeedTitle = Instance.new("TextLabel", autoSection)
    deliverySpeedTitle.Name = "DeliverySpeedTitle"
    deliverySpeedTitle.Size = UDim2.new(1, -18, 0, 18)
    deliverySpeedTitle.Position = UDim2.fromOffset(9, 1000)
    deliverySpeedTitle.BackgroundTransparency = 1
    deliverySpeedTitle.Font = Enum.Font.GothamBold
    deliverySpeedTitle.Text = "DELIVERY EGG → SAFE ZONE  •  INDIVIDUAL SPEED"
    deliverySpeedTitle.TextColor3 = Color3.fromRGB(135, 220, 255)
    deliverySpeedTitle.TextSize = 9
    deliverySpeedTitle.TextXAlignment = Enum.TextXAlignment.Left
    deliverySpeedTitle.ZIndex = 21

deliverySpeedInfo = Instance.new("TextLabel", autoSection)
    deliverySpeedInfo.Size = UDim2.new(1, -18, 0, 28)
    deliverySpeedInfo.Position = UDim2.fromOffset(9, 1019)
    deliverySpeedInfo.BackgroundTransparency = 1
    deliverySpeedInfo.Font = Enum.Font.Gotham
    deliverySpeedInfo.Text = "GLIDE / FLY / WALK / RIDE GUARD • default 1050 studs/s • max 3000 studs/s • only the selected delivery leg is changed"
    deliverySpeedInfo.TextColor3 = Color3.fromRGB(145, 160, 180)
    deliverySpeedInfo.TextSize = 8
    deliverySpeedInfo.TextWrapped = true
    deliverySpeedInfo.TextXAlignment = Enum.TextXAlignment.Left
    deliverySpeedInfo.ZIndex = 21

deliverySpeedFrame = Instance.new("Frame", autoSection)
    deliverySpeedFrame.Name = "DeliverySpeedControls"
    deliverySpeedFrame.Size = UDim2.new(1, -18, 0, 142)
    deliverySpeedFrame.Position = UDim2.fromOffset(9, 1050)
    deliverySpeedFrame.BackgroundTransparency = 1
    deliverySpeedFrame.ZIndex = 21

deliverySpeedLayout = Instance.new("UIGridLayout", deliverySpeedFrame)
    deliverySpeedLayout.CellSize = UDim2.new(1/2, -5, 0, 64)
    deliverySpeedLayout.CellPadding = UDim2.fromOffset(8, 8)
    deliverySpeedLayout.FillDirection = Enum.FillDirection.Horizontal
    deliverySpeedLayout.SortOrder = Enum.SortOrder.LayoutOrder

speedControls = {}
methodLabels = {
        {key="GLIDE", label="GLIDE"},
        {key="FLY", label="FLY"},
        {key="WALK", label="WALK"},
        {key="RIDE_GUARD", label="RIDE GUARD"},
    }

    function clampDeliverySpeed(v)
        return math.clamp(math.floor((tonumber(v) or 500) + 0.5), 40, 3000)
    end

    function applyDeliverySpeed(key, value)
        value = clampDeliverySpeed(value)
        deliverySpeeds[key] = value
        pcall(function()
            BX.require("features.carry").setDeliverySpeed(key, value)
        end)
        if autoRarityOn then
            pcall(function()
                safeAutoSetOptions("rarity", {
                    pick = pickByRarityPriority,
                    continuous = true,
                    cycleDelay = stealDelay,
                    fastMode = true,
                    method = autoStealMethod,
                    deliverySpeed = deliverySpeeds[autoStealMethod],
                })
            end)
        end
        if autoStealOn then
            pcall(function()
                safeAutoSetOptions("farm", {
                    pick = pickByMethodLoop,
                    continuous = true,
                    cycleDelay = stealDelay,
                    fastMode = true,
                    method = autoStealMethod,
                    deliverySpeed = deliverySpeeds[autoStealMethod],
                })
            end)
        end
        updateMethodVisual(autoRarityOn)
    end

    for index, item in ipairs(methodLabels) do
        local card = Instance.new("Frame", deliverySpeedFrame)
        card.Name = item.key .. "Speed"
        card.LayoutOrder = index
        card.BackgroundColor3 = Color3.fromRGB(15, 20, 28)
        card.BackgroundTransparency = 0.05
        card.BorderSizePixel = 0
        card.ZIndex = 21
        Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

        local label = Instance.new("TextLabel", card)
        label.Size = UDim2.new(1, -92, 0, 20)
        label.Position = UDim2.fromOffset(8, 5)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.GothamBold
        label.Text = item.label
        label.TextColor3 = Color3.fromRGB(225, 240, 250)
        label.TextSize = 9
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.ZIndex = 22

        local value = Instance.new("TextLabel", card)
        value.Size = UDim2.new(1, -92, 0, 22)
        value.Position = UDim2.fromOffset(8, 27)
        value.BackgroundTransparency = 1
        value.Font = Enum.Font.GothamBold
        value.Text = tostring(deliverySpeeds[item.key]) .. " studs/s"
        value.TextColor3 = Color3.fromRGB(95, 225, 255)
        value.TextSize = 9
        value.TextXAlignment = Enum.TextXAlignment.Left
        value.ZIndex = 22

        local minus = Instance.new("TextButton", card)
        minus.Size = UDim2.fromOffset(34, 30)
        minus.Position = UDim2.new(1, -78, 0.5, -15)
        minus.BackgroundColor3 = Color3.fromRGB(28, 34, 45)
        minus.BorderSizePixel = 0
        minus.Font = Enum.Font.GothamBold
        minus.Text = "−"
        minus.TextColor3 = Color3.fromRGB(235, 245, 255)
        minus.TextSize = 15
        minus.ZIndex = 22
        Instance.new("UICorner", minus).CornerRadius = UDim.new(0, 6)

        local plus = Instance.new("TextButton", card)
        plus.Size = UDim2.fromOffset(34, 30)
        plus.Position = UDim2.new(1, -40, 0.5, -15)
        plus.BackgroundColor3 = Color3.fromRGB(28, 34, 45)
        plus.BorderSizePixel = 0
        plus.Font = Enum.Font.GothamBold
        plus.Text = "+"
        plus.TextColor3 = Color3.fromRGB(235, 245, 255)
        plus.TextSize = 15
        plus.ZIndex = 22
        Instance.new("UICorner", plus).CornerRadius = UDim.new(0, 6)

        speedControls[item.key] = value
        minus.Activated:Connect(function()
            applyDeliverySpeed(item.key, deliverySpeeds[item.key] - 50)
            value.Text = tostring(deliverySpeeds[item.key]) .. " studs/s"
        end)
        plus.Activated:Connect(function()
            applyDeliverySpeed(item.key, deliverySpeeds[item.key] + 50)
            value.Text = tostring(deliverySpeeds[item.key]) .. " studs/s"
        end)
    end

    -- Initialize the carry module with the same defaults shown by the UI.
    for key, value in pairs(deliverySpeeds) do
        pcall(function() BX.require("features.carry").setDeliverySpeed(key, value) end)
    end

    -- ===================== COMBAT / DR. SCRAMBLE =====================
local guardFeature = nil
pcall(function() guardFeature = BX.require("features.guard") end)

local dr = nil
do
ok, result = pcall(function()
        return BX.require("features.drscramble")
    end)
    if ok and type(result) == "table" then
        dr = result
    else
        -- Keep the main GUI alive even if the optional DR module fails to load.
        -- The original menu must never disappear because one feature errored.
        dr = {
            isRunning = function() return false end,
            setEnabled = function() return false, "DR. Scramble module failed to load" end,
            isSmartSearch = function() return false end,
            setSmartSearch = function() return false end,
            isGodMode = function() return false end,
            setGodMode = function() return false end,
            getMovementMode = function() return "GLIDE" end,
            setMovementMode = function() return false end,
            status = function() return {title="DR. Scramble", body="module unavailable"} end,
            teleportToDrone = function() return false end,
            eventLocationOptions = function() return {} end,
            detectActiveDroneLocation = function() return false, "DR. Scramble module unavailable" end,
            teleportToEventLocation = function() return false, "DR. Scramble module unavailable" end,
        }
    end
end

local drSection = Instance.new("Frame", scroll)
drSection.Name = "DRScrambleSection"

-- Dedicated DR. Scramble controls; layout leaves room for event-location teleport controls.
drSection.Size = UDim2.new(1, 0, 0, 515)

drSection.BackgroundColor3 = Color3.fromRGB(10, 11, 16)
drSection.BackgroundTransparency = 0.18
drSection.BorderSizePixel = 0

Instance.new("UICorner", drSection).CornerRadius = UDim.new(0, 12)

local drStroke = Instance.new("UIStroke", drSection)
drStroke.Thickness = 1.8
drStroke.Transparency = 0.12
drStroke.Color = Color3.fromRGB(188, 67, 255)

-- ============================================================
-- TITLE
-- ============================================================

local drTitle = Instance.new("TextLabel", drSection)
drTitle.Size = UDim2.new(1, -18, 0, 23)
drTitle.Position = UDim2.fromOffset(9, 7)
drTitle.BackgroundTransparency = 1
drTitle.Font = Enum.Font.GothamBold
drTitle.Text = "⚔  COMBAT • DR. SCRAMBLE EXPERIMENT"
drTitle.TextColor3 = Color3.fromRGB(245, 248, 255)
drTitle.TextSize = 12
drTitle.TextXAlignment = Enum.TextXAlignment.Left

-- ============================================================
-- SUBTITLE
-- ============================================================

local drSub = Instance.new("TextLabel", drSection)
drSub.Size = UDim2.new(1, -18, 0, 28)
drSub.Position = UDim2.fromOffset(9, 30)
drSub.BackgroundTransparency = 1
drSub.Font = Enum.Font.Gotham
drSub.Text = "Auto Attack = DR. Scramble drones only • safe GLIDE/FLY • event-location teleport is separate"
drSub.TextColor3 = Color3.fromRGB(155, 175, 195)
drSub.TextSize = 9
drSub.TextWrapped = true
drSub.TextXAlignment = Enum.TextXAlignment.Left

-- ============================================================
-- EVENT TIMER
-- ============================================================

local drEvent = Instance.new("TextLabel", drSection)
drEvent.Name = "ScrambleEventTimer"
drEvent.Size = UDim2.new(1, -18, 0, 24)
drEvent.Position = UDim2.fromOffset(9, 58)
drEvent.BackgroundColor3 = Color3.fromRGB(13, 24, 31)
drEvent.BackgroundTransparency = 0.02
drEvent.BorderSizePixel = 0
drEvent.Font = Enum.Font.GothamBold
drEvent.Text = "⏱ DR. SCRAMBLE EVENT: SCANNING..."
drEvent.TextColor3 = Color3.fromRGB(95, 235, 255)
drEvent.TextSize = 9
drEvent.TextXAlignment = Enum.TextXAlignment.Left
drEvent.ZIndex = 22

Instance.new("UICorner", drEvent).CornerRadius = UDim.new(0, 7)

local drEventPad = Instance.new("UIPadding", drEvent)
drEventPad.PaddingLeft = UDim.new(0, 8)

-- ============================================================
-- AUTO ATTACK
-- ============================================================

local drButton = Instance.new("TextButton", drSection)
drButton.Name = "AutoAttackDRScramble"
drButton.Size = UDim2.new(1, -18, 0, 34)
drButton.Position = UDim2.fromOffset(9, 88)
drButton.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
drButton.BackgroundTransparency = 0.04
drButton.BorderSizePixel = 0
drButton.Font = Enum.Font.GothamBold
drButton.Text = "⚔ AUTO ATTACK DR. SCRAMBLE  [OFF]"
drButton.TextColor3 = Color3.fromRGB(235, 245, 255)
drButton.TextSize = 10
drButton.ZIndex = 22

Instance.new("UICorner", drButton).CornerRadius = UDim.new(0, 8)

-- ============================================================
-- SMART SEARCH
-- ============================================================

local drMoveButton = Instance.new("TextButton", drSection)
drMoveButton.Name = "SafeDroneMovement"
drMoveButton.Size = UDim2.new(1, -18, 0, 34)
drMoveButton.Position = UDim2.fromOffset(9, 128)
drMoveButton.BackgroundColor3 = Color3.fromRGB(0, 105, 145)
drMoveButton.BorderSizePixel = 0
drMoveButton.Font = Enum.Font.GothamBold
drMoveButton.Text = "✈ SAFE DRONE MOVE • GLIDE  [GLIDE]"
drMoveButton.TextColor3 = Color3.fromRGB(235, 245, 255)
drMoveButton.TextSize = 9
drMoveButton.ZIndex = 22
Instance.new("UICorner", drMoveButton).CornerRadius = UDim.new(0, 8)

-- TELEPORT TO DRONE is intentionally separate from AUTO ATTACK.
-- One click performs one movement job; Auto Attack never starts a second
-- movement job while this one is active.
local drTeleportButton = Instance.new("TextButton", drSection)
drTeleportButton.Name = "TeleportToDrone"
drTeleportButton.Size = UDim2.new(1, -18, 0, 34)
drTeleportButton.Position = UDim2.fromOffset(9, 168)
drTeleportButton.BackgroundColor3 = Color3.fromRGB(0, 105, 145)
drTeleportButton.BorderSizePixel = 0
drTeleportButton.Font = Enum.Font.GothamBold
drTeleportButton.Text = "✈ TELEPORT TO DRONE  [ONE SHOT]"
drTeleportButton.TextColor3 = Color3.fromRGB(235, 245, 255)
drTeleportButton.TextSize = 9
drTeleportButton.ZIndex = 22
Instance.new("UICorner", drTeleportButton).CornerRadius = UDim.new(0, 8)

local drSmartButton = Instance.new("TextButton", drSection)
drSmartButton.Name = "SmartSearchDrone"
drSmartButton.Size = UDim2.new(1, -18, 0, 34)
drSmartButton.Position = UDim2.fromOffset(9, 208)
drSmartButton.BackgroundColor3 = Color3.fromRGB(0, 105, 145)
drSmartButton.BorderSizePixel = 0
drSmartButton.Font = Enum.Font.GothamBold
drSmartButton.Text = "⌁ SMART SEARCH DRONE • GLOBAL / SAFE ZONE  [ON]"
drSmartButton.TextColor3 = Color3.fromRGB(235, 245, 255)
drSmartButton.TextSize = 9
drSmartButton.ZIndex = 22

Instance.new("UICorner", drSmartButton).CornerRadius = UDim.new(0, 8)

-- ============================================================
-- BRUTAL ATTACK
-- ============================================================

local drBrutalButton = Instance.new("TextButton", drSection)
drBrutalButton.Name = "BrutalAttack"
drBrutalButton.Size = UDim2.new(1, -18, 0, 34)
drBrutalButton.Position = UDim2.fromOffset(9, 248)
drBrutalButton.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
drBrutalButton.BackgroundTransparency = 0.04
drBrutalButton.BorderSizePixel = 0
drBrutalButton.Font = Enum.Font.GothamBold
drBrutalButton.Text = "☠ BRUTAL ATTACK • DRONE  [OFF]"
drBrutalButton.TextColor3 = Color3.fromRGB(235, 245, 255)
drBrutalButton.TextSize = 10
drBrutalButton.ZIndex = 22

Instance.new("UICorner", drBrutalButton).CornerRadius = UDim.new(0, 8)

-- ============================================================
-- DRONE ESP
-- ============================================================

local drESPButton = Instance.new("TextButton", drSection)
drESPButton.Name = "DroneESP"
drESPButton.Size = UDim2.new(1, -18, 0, 34)
drESPButton.Position = UDim2.fromOffset(9, 288)
drESPButton.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
drESPButton.BackgroundTransparency = 0.04
drESPButton.BorderSizePixel = 0
drESPButton.Font = Enum.Font.GothamBold
drESPButton.Text = "◉ DRONE ESP • DR. SCRAMBLE  [OFF]"
drESPButton.TextColor3 = Color3.fromRGB(235, 245, 255)
drESPButton.TextSize = 10
drESPButton.ZIndex = 22

Instance.new("UICorner", drESPButton).CornerRadius = UDim.new(0, 8)

-- ============================================================
-- EVENT LOCATION TELEPORT
-- ============================================================
-- This is deliberately a separate selector + one-shot button. It does not
-- enable/disable Auto Attack and it does not share Auto Attack's target state.
local drLocationButton = Instance.new("TextButton", drSection)
drLocationButton.Name = "ScrambleEventLocationSelector"
drLocationButton.Size = UDim2.new(1, -18, 0, 34)
drLocationButton.Position = UDim2.fromOffset(9, 328)
drLocationButton.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
drLocationButton.BackgroundTransparency = 0.04
drLocationButton.BorderSizePixel = 0
drLocationButton.Font = Enum.Font.GothamBold
drLocationButton.Text = "📍 EVENT LOCATION • ABYSS OCEAN"
drLocationButton.TextColor3 = Color3.fromRGB(235, 245, 255)
drLocationButton.TextSize = 9
drLocationButton.ZIndex = 22
Instance.new("UICorner", drLocationButton).CornerRadius = UDim.new(0, 8)

local drLocationTeleportButton = Instance.new("TextButton", drSection)
drLocationTeleportButton.Name = "TeleportToScrambleEventLocation"
drLocationTeleportButton.Size = UDim2.new(1, -18, 0, 34)
drLocationTeleportButton.Position = UDim2.fromOffset(9, 368)
drLocationTeleportButton.BackgroundColor3 = Color3.fromRGB(0, 105, 145)
drLocationTeleportButton.BorderSizePixel = 0
drLocationTeleportButton.Font = Enum.Font.GothamBold
drLocationTeleportButton.Text = "✈ TELEPORT TO EVENT LOCATION • ONE SHOT"
drLocationTeleportButton.TextColor3 = Color3.fromRGB(235, 245, 255)
drLocationTeleportButton.TextSize = 9
drLocationTeleportButton.ZIndex = 22
Instance.new("UICorner", drLocationTeleportButton).CornerRadius = UDim.new(0, 8)

-- State Brutal Attack
local brutalOn = false
local droneESPOn = false
local drEventLocations = {}
local drEventLocationIndex = 1
local drSelectedEventLocation = "Abyss Ocean"

local function normalizeDrEventLocationName(value)
    return tostring(value or ""):lower():gsub("[%s_%-]", ""):gsub("[^%w]", "")
end

local drAutoDetectedDroneArea = nil
local drAutoDetectedDroneName = nil
local drAutoDetectedDroneVia = nil

local function refreshDrEventLocations()
ok, list = pcall(function()
        return dr.eventLocationOptions()
    end)
    if ok and type(list) == "table" and #list > 0 then
        drEventLocations = list
        local wanted = normalizeDrEventLocationName(drSelectedEventLocation)
        local found = false
        for i, name in ipairs(drEventLocations) do
            if normalizeDrEventLocationName(name) == wanted then
                drEventLocationIndex = i
                drSelectedEventLocation = name
                found = true
                break
            end
        end
        if not found then
            drEventLocationIndex = 1
            drSelectedEventLocation = drEventLocations[1]
        end
    end
end

local function autoDetectDrScrambleLocation()
ok, found, area, target, via = pcall(function()
        return dr.detectActiveDroneLocation()
    end)

    if not ok then
        return false, "detect error: " .. tostring(found)
    end

    if found == false then
        drAutoDetectedDroneArea = nil
        drAutoDetectedDroneName = nil
        drAutoDetectedDroneVia = nil
        return false, tostring(area or "No active drone")
    end

    if area and tostring(area) ~= "" then
        drAutoDetectedDroneArea = tostring(area)
        drAutoDetectedDroneName = target and target.model and tostring(target.model.Name) or nil
        drAutoDetectedDroneVia = via

        -- Auto-detect is authoritative while a live drone exists.
        local wanted = normalizeDrEventLocationName(drAutoDetectedDroneArea)
        for i, name in ipairs(drEventLocations) do
            if normalizeDrEventLocationName(name) == wanted then
                drEventLocationIndex = i
                drSelectedEventLocation = name
                break
            end
        end
        return true, drSelectedEventLocation
    end

    return false, "Drone area unresolved"
end

local function updateDrEventLocationUI()
    if not drLocationButton or not drLocationButton.Parent then return end
    if drAutoDetectedDroneArea then
        drLocationButton.Text =
            "🎯 ACTIVE DRONE • " .. tostring(drAutoDetectedDroneArea):upper()
    else
        drLocationButton.Text =
            "📍 EVENT LOCATION • " .. tostring(drSelectedEventLocation):upper()
    end
end

-- Do not block initial GUI construction with a full Workspace scan.
-- Populate the detector after the menu is already visible.
updateDrEventLocationUI()
task.delay(0.75, function()
    if not gui or not gui.Parent or not drSection or not drSection.Parent then return end
    pcall(refreshDrEventLocations)
    pcall(autoDetectDrScrambleLocation)
    pcall(updateDrEventLocationUI)
end)

-- ============================================================
-- STATUS
-- ============================================================

local drStatus = Instance.new("TextLabel", drSection)
drStatus.Size = UDim2.new(1, -18, 0, 80)
drStatus.Position = UDim2.fromOffset(9, 448)
drStatus.BackgroundColor3 = Color3.fromRGB(16, 20, 29)
drStatus.BackgroundTransparency = 0.05
drStatus.BorderSizePixel = 0
drStatus.Font = Enum.Font.Gotham
drStatus.Text = "Status: OFF • Target: NONE"
drStatus.TextColor3 = Color3.fromRGB(125, 210, 235)
drStatus.TextSize = 9
drStatus.TextWrapped = true
drStatus.ZIndex = 22

Instance.new("UICorner", drStatus).CornerRadius = UDim.new(0, 8)

-- ============================================================
-- DRONE ESP ENGINE
-- ============================================================

local droneESPObjects = {}
local droneESPConnection = nil

local function droneESPValid(model)
    if not model or not model:IsA("Model") or not model.Parent then
        return false
    end

droneId = model:GetAttribute("ScrambleDroneId")
hitbox = model:FindFirstChild("Hitbox")
    if droneId == nil or not hitbox then
        return false
    end

state = tostring(model:GetAttribute("DroneState") or "")
    return state ~= "Death" and state ~= "Dead"
end

local function droneESPText(model)
hitbox = model and model:FindFirstChild("Hitbox")
hp = hitbox and tonumber(hitbox:GetAttribute("Health"))
maxHp = model and tonumber(
        model:GetAttribute("MaxHealth")
        or model:GetAttribute("HealthMax")
        or (hitbox and hitbox:GetAttribute("MaxHealth"))
    )
id = model and model:GetAttribute("ScrambleDroneId")

    if hp and maxHp then
        return ("DR SCRAMBLE\n%s\nHP %d/%d"):format(
            tostring(id or "DRONE"),
            math.max(0, math.floor(hp + 0.5)),
            math.max(0, math.floor(maxHp + 0.5))
        )
    elseif hp then
        return ("DR SCRAMBLE\n%s\nHP %d"):format(
            tostring(id or "DRONE"),
            math.max(0, math.floor(hp + 0.5))
        )
    end

    return ("DR SCRAMBLE\n%s"):format(tostring(id or "DRONE"))
end

local function destroyDroneESP(model)
entry = droneESPObjects[model]
    if not entry then return end

    if entry.billboard then
        pcall(function() entry.billboard:Destroy() end)
    end
    if entry.highlight then
        pcall(function() entry.highlight:Destroy() end)
    end

    droneESPObjects[model] = nil
end

local function createDroneESP(model)
    if droneESPObjects[model] or not droneESPValid(model) then
        return
    end

highlight = Instance.new("Highlight")
    highlight.Name = "DellDrScrambleESP"
    highlight.Adornee = model
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.FillTransparency = 0.78
    highlight.OutlineTransparency = 0
    highlight.FillColor = Color3.fromRGB(255, 75, 75)
    highlight.OutlineColor = Color3.fromRGB(255, 220, 80)
    highlight.Parent = model

billboard = Instance.new("BillboardGui")
    billboard.Name = "DellDrScrambleESPLabel"
    billboard.Adornee = model:FindFirstChild("Hitbox")
        or model.PrimaryPart
        or model:FindFirstChildWhichIsA("BasePart")
    billboard.Size = UDim2.fromOffset(150, 46)
    billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
    billboard.AlwaysOnTop = true
    billboard.MaxDistance = 5000
    billboard.Parent = model

label = Instance.new("TextLabel")
    label.Name = "Info"
    label.Size = UDim2.fromScale(1, 1)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.GothamBold
    label.TextScaled = false
    label.TextSize = 11
    label.TextWrapped = true
    label.TextStrokeTransparency = 0.25
    label.TextColor3 = Color3.fromRGB(255, 230, 120)
    label.Text = droneESPText(model)
    label.Parent = billboard

    droneESPObjects[model] = {
        highlight = highlight,
        billboard = billboard,
        label = label,
    }
end

local function updateDroneESP()
    if not droneESPOn then
        for model in pairs(droneESPObjects) do
            destroyDroneESP(model)
        end
        return
    end

seen = {}

    -- Workspace-wide scan so a replicated drone can be marked even when it
    -- is far away from the player / Safe Zone.
    for _, inst in ipairs(workspace:GetDescendants()) do
        if inst:IsA("Model") and droneESPValid(inst) then
            seen[inst] = true
            createDroneESP(inst)

            local entry = droneESPObjects[inst]
            if entry and entry.label then
                entry.label.Text = droneESPText(inst)
            end
        end
    end

    for model in pairs(droneESPObjects) do
        if not seen[model] then
            destroyDroneESP(model)
        end
    end
end

local function setDroneESP(on)
    droneESPOn = on == true

    if droneESPConnection then
        droneESPConnection:Disconnect()
        droneESPConnection = nil
    end

    if droneESPOn then
        updateDroneESP()
        -- DO NOT scan Workspace every Heartbeat. Track only replication changes
        -- and refresh the small set of active labels on a low-frequency timer.
        droneESPConnection = Workspace.DescendantAdded:Connect(function(inst)
            if not droneESPOn then return end
            local model = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model")
            if model and droneESPValid(model) then
                createDroneESP(model)
            end
        end)
        task.spawn(function()
            while droneESPOn and gui and gui.Parent do
                for model, entry in pairs(droneESPObjects) do
                    if not droneESPValid(model) then
                        destroyDroneESP(model)
                    elseif entry.label then
                        entry.label.Text = droneESPText(model)
                    end
                end
                task.wait(0.25)
            end
        end)
    else
        updateDroneESP()
    end

    return true
end

-- ============================================================
-- STATE
-- ============================================================

local drOn = false

-- ============================================================
-- UPDATE DR UI
-- ============================================================

local function updateDRUI()

ok, s = pcall(function()
        return dr.status()
    end)

    -- Proteksi apabila status module gagal
    if not ok or type(s) ~= "table" then
        s = {
            on = false,
            eventTime = "NOT FOUND",
            eventActive = false,
            smartSearch = false,
            body = "MODULE ERROR",
            target = "NONE",
            hp = "-"
        }
    end

    -- ==================== AUTO ATTACK ====================

    drOn = s.on == true

    drButton.Text = drOn
        and "⚔ AUTO ATTACK DR. SCRAMBLE  [ON]"
        or "⚔ AUTO ATTACK DR. SCRAMBLE  [OFF]"

    drButton.BackgroundColor3 = drOn
        and Color3.fromRGB(0, 105, 145)
        or Color3.fromRGB(23, 28, 38)

    -- ==================== EVENT ====================

    drEvent.Text =
        "⏱ DR. SCRAMBLE EVENT: " ..
        tostring(s.eventTime or "NOT FOUND")

    drEvent.TextColor3 =
        s.eventActive
        and Color3.fromRGB(95, 255, 175)
        or Color3.fromRGB(255, 190, 100)

    -- ==================== SMART SEARCH ====================

smartOn = s.smartSearch == true

    drSmartButton.Text = smartOn
        and "⌁ SMART SEARCH DRONE • GLOBAL / SAFE ZONE  [ON]"
        or "⌁ SMART SEARCH DRONE • GLOBAL / SAFE ZONE  [OFF]"

    drSmartButton.BackgroundColor3 = smartOn
        and Color3.fromRGB(0, 105, 145)
        or Color3.fromRGB(23, 28, 38)

moveMode = "GLIDE"
    pcall(function()
        moveMode = tostring(dr.getMovementMode() or "GLIDE"):upper()
    end)
    drMoveButton.Text = "✈ SAFE DRONE MOVE • " .. moveMode .. "  [" .. moveMode .. "]"
    drMoveButton.BackgroundColor3 = drOn
        and Color3.fromRGB(0, 105, 145)
        or Color3.fromRGB(23, 28, 38)

    -- ==================== BRUTAL ====================

    drBrutalButton.Text = brutalOn
        and "☠ BRUTAL ATTACK • DRONE  [ON]"
        or "☠ BRUTAL ATTACK • DRONE  [OFF]"

    drBrutalButton.BackgroundColor3 = brutalOn
        and Color3.fromRGB(145, 35, 35)
        or Color3.fromRGB(23, 28, 38)

    -- ==================== DRONE ESP ====================

    drESPButton.Text = droneESPOn
        and "◉ DRONE ESP • DR. SCRAMBLE  [ON]"
        or "◉ DRONE ESP • DR. SCRAMBLE  [OFF]"

    drESPButton.BackgroundColor3 = droneESPOn
        and Color3.fromRGB(0, 105, 145)
        or Color3.fromRGB(23, 28, 38)

    -- ==================== STATUS ====================

    drStatus.Text = string.format(
        "Status: %s\nTarget: %s • HP: %s\nSearch: %s • Move: %s • AntiDeath: %s • Brutal: %s\nEvent TP: %s",
        tostring(s.body or "OFF"),
        tostring(s.target or "NONE"),
        tostring(s.hp or "-"),
        smartOn and "GLOBAL/SAFE ZONE" or "OFF",
        moveMode,
        drOn and "ARMED" or "OFF",
        brutalOn and "ON" or "OFF",
        tostring(drAutoDetectedDroneArea or drSelectedEventLocation or "NONE")
    )
end

-- ============================================================
-- BRUTAL ATTACK TOGGLE
-- ============================================================

drBrutalButton.Activated:Connect(function()

    brutalOn = not brutalOn

    if brutalOn then

        drBrutalButton.Text =
            "☠ BRUTAL ATTACK • DRONE  [ON]"

        drBrutalButton.BackgroundColor3 =
            Color3.fromRGB(145, 35, 35)

        showNotification(
            "DR. SCRAMBLE",
            "☠ BRUTAL ATTACK ENABLED",
            "success",
            2.5
        )

    else

        drBrutalButton.Text =
            "☠ BRUTAL ATTACK • DRONE  [OFF]"

        drBrutalButton.BackgroundColor3 =
            Color3.fromRGB(23, 28, 38)

        showNotification(
            "DR. SCRAMBLE",
            "BRUTAL ATTACK DISABLED",
            "info",
            2.5
        )

    end

    pcall(updateDRUI)
end)

-- ============================================================
-- SAFE GLIDE / FLY MODE
-- ============================================================

drMoveButton.Activated:Connect(function()
ok, current = pcall(function()
        return dr.getMovementMode()
    end)
    if not ok then
        showNotification("DR. SCRAMBLE", "Failed to read movement mode", "warn", 2.5)
        return
    end

nextMode = (tostring(current):upper() == "GLIDE") and "FLY" or "GLIDE"
success, err = pcall(function()
        return dr.setMovementMode(nextMode)
    end)

    if not success or err == false then
        showNotification("DR. SCRAMBLE", tostring(err or "Movement mode failed"), "warn", 2.5)
        return
    end

    pcall(updateDRUI)
    showNotification(
        "DR. SCRAMBLE",
        "Safe drone movement: " .. nextMode,
        "success",
        2.2
    )
end)

-- ============================================================
-- TELEPORT TO DRONE (ONE SHOT)
-- ============================================================

drTeleportButton.Activated:Connect(function()
ok, why = pcall(function()
        return dr.teleportToDrone()
    end)

    if not ok then
        showNotification("DR. SCRAMBLE", "Teleport error: " .. tostring(why), "warn", 2.8)
        return
    end
    if why == false then
        showNotification("DR. SCRAMBLE", "No current drone target • Auto Attack is not required", "warn", 2.5)
        return
    end
    showNotification("DR. SCRAMBLE", "Teleported to current drone • Auto Attack remains separate", "success", 2.2)
end)

-- ============================================================
-- EVENT LOCATION SELECTOR
-- ============================================================

drLocationButton.Activated:Connect(function()
    refreshDrEventLocations()
detected = false
    pcall(function()
        detected = autoDetectDrScrambleLocation() == true
    end)

    if detected and drAutoDetectedDroneArea then
        updateDrEventLocationUI()
        showNotification(
            "DR. SCRAMBLE",
            "Active drone detected • " .. tostring(drAutoDetectedDroneArea),
            "success",
            2.0
        )
        return
    end

    if #drEventLocations == 0 then
        showNotification("DR. SCRAMBLE", "No active DR. Scramble drone detected", "warn", 2.5)
        return
    end

    drAutoDetectedDroneArea = nil
    drAutoDetectedDroneName = nil
    drAutoDetectedDroneVia = nil
    drEventLocationIndex = (drEventLocationIndex % #drEventLocations) + 1
    drSelectedEventLocation = drEventLocations[drEventLocationIndex]
    updateDrEventLocationUI()

    showNotification(
        "DR. SCRAMBLE",
        "Manual event location: " .. tostring(drSelectedEventLocation),
        "info",
        1.8
    )
end)

drLocationTeleportButton.Activated:Connect(function()
    refreshDrEventLocations()
    pcall(autoDetectDrScrambleLocation)
    updateDrEventLocationUI()

    if not drSelectedEventLocation or drSelectedEventLocation == "" then
        showNotification("DR. SCRAMBLE", "No DR. Scramble event location detected", "warn", 2.4)
        return
    end

destinationArea = drAutoDetectedDroneArea or drSelectedEventLocation
ok, moved, detail = pcall(function()
        return dr.teleportToEventLocation(destinationArea)
    end)

    if not ok then
        showNotification("DR. SCRAMBLE", "Event location teleport error: " .. tostring(moved), "warn", 3.0)
        return
    end
    if moved == false then
        showNotification("DR. SCRAMBLE", tostring(detail or "Event location not found"), "warn", 3.0)
        return
    end

    showNotification(
        "DR. SCRAMBLE",
        "Teleported to " .. tostring(destinationArea) .. " • active drone auto-detected",
        "success",
        2.4
    )
end)

-- ============================================================
-- SMART SEARCH
-- ============================================================

drSmartButton.Activated:Connect(function()

ok, current = pcall(function()
        return dr.isSmartSearch()
    end)

    if not ok then

        showNotification(
            "DR. SCRAMBLE",
            "Failed to read Smart Search state",
            "warn",
            3
        )

        return
    end

newState = not current

success, err = pcall(function()
        dr.setSmartSearch(newState)
    end)

    if not success then

        showNotification(
            "DR. SCRAMBLE",
            tostring(err),
            "warn",
            3
        )

        return
    end

    updateDRUI()

    showNotification(
        "DR. SCRAMBLE",
        newState
            and "Smart Search ON • drones can be detected from Safe Zone"
            or "Smart Search OFF",
        newState and "success" or "info",
        2.5
    )
end)


-- ============================================================
-- DRONE ESP
-- ============================================================

drESPButton.Activated:Connect(function()
newState = not droneESPOn

ok, why = pcall(function()
        return setDroneESP(newState)
    end)

    if not ok or why == false then
        droneESPOn = false
        showNotification(
            "DR. SCRAMBLE",
            "Drone ESP failed: " .. tostring(why or "unknown error"),
            "warn",
            2.8
        )
        pcall(updateDRUI)
        return
    end

    pcall(updateDRUI)

    showNotification(
        "DR. SCRAMBLE",
        newState
            and "Drone ESP ON • ScrambleDroneId + Hitbox tracked"
            or "Drone ESP OFF",
        newState and "success" or "info",
        2.4
    )
end)

-- ============================================================
-- AUTO ATTACK
-- ============================================================

drButton.Activated:Connect(function()

    -- ==================== STOP ====================

    if dr.isRunning() then

        dr.setEnabled(false)

        updateDRUI()

        showNotification(
            "DR. SCRAMBLE",
            "Auto Attack stopped",
            "info",
            2.2
        )

        return
    end

    -- ==================== AUTO STEAL CHECK ====================

    if auto.isRunning() then

        drStatus.Text =
            "Status: Auto Steal is active • turn it OFF first"

        showNotification(
            "DR. SCRAMBLE",
            "Turn Auto Steal OFF first",
            "warn",
            2.6
        )

        return
    end

    -- ==================== START ====================

ok, why = dr.setEnabled(true)

    if ok == false then

        drStatus.Text =
            "Status: " .. tostring(why)

        showNotification(
            "DR. SCRAMBLE",
            tostring(why),
            "warn",
            3.0
        )

        return
    end

    updateDRUI()

    showNotification(
        "DR. SCRAMBLE",
        brutalOn
            and "☠ Auto Attack + Brutal Mode enabled"
            or "Auto detect + priority attack enabled",
        "success",
        2.6
    )
end)

-- ============================================================
-- LIVE UPDATE
-- ============================================================

task.spawn(function()

    while gui.Parent and drSection.Parent do

        pcall(refreshDrEventLocations)
        pcall(autoDetectDrScrambleLocation)
        pcall(updateDrEventLocationUI)
        pcall(updateDRUI)

        task.wait(0.75)

    end

end)

-- ============================================================
-- INITIAL UPDATE
-- ============================================================

pcall(updateDRUI)

-- GUI safety watchdog: keep the ScreenGui alive without overriding the user's
-- explicit hide/minimize state.  The old watchdog forced main.Visible=true every
-- second, which made the menu reappear immediately after clicking minimize.
task.spawn(function()
    while gui and gui.Parent do
        pcall(function()
            gui.Enabled = true
            if minimized then
                -- Watchdog must never undo minimize. Hide every top-level hub
                -- object except the permanent launcher icon.
                for _, obj in ipairs(gui:GetChildren()) do
                    if obj:IsA("GuiObject") and obj ~= miniMenuIcon then
                        obj.Visible = false
                    end
                end
                if main then main.Visible = false end
            else
                if main then main.Visible = true end
            end
            if miniMenuIcon then miniMenuIcon.Visible = true end
        end)
        task.wait(1)
    end
end)

-- Clean ESP objects if the hub GUI is removed.
task.spawn(function()
    while gui.Parent do
        task.wait(1)
    end
    pcall(function() setDroneESP(false) end)
end)

    -- ===================== RIDE GUARD + GUARD LIST =====================
    -- Added into the EXISTING VIP DELL HUBS menu.
    -- No second ScreenGui / no replacement of the original menu.

    function installRideGuard()
        local PlayersRG = game:GetService("Players")
        local RunServiceRG = game:GetService("RunService")
        local ReplicatedStorageRG = game:GetService("ReplicatedStorage")
        local WorkspaceRG = game:GetService("Workspace")
        local LocalPlayerRG = PlayersRG.LocalPlayer

        local rgSelected = nil
        local rgMount = nil
        local rgSaddle = nil
        -- The GuardAreas entry is a live/template model in this game and can
        -- already be visible. Ride Guard creates a client-side mount clone,
        -- so keep the original area guard hidden while the clone is active.
        -- This prevents the same Guard from appearing twice on screen.
        local rgHiddenSource = nil
        local rgHiddenState = {}
        local rgConn = nil
        local rgTrack = nil
        local rgIdleTrack = nil
        local rgFootOff = 0
        local rgBackOff = 0
        local rgRideLift = 0
        local rgRideOn = false
        local rgSearchText = ""

        local function rgHRP()
            local c = LocalPlayerRG and LocalPlayerRG.Character
            return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("RootPart"))
        end

        local function rgReq(moduleScript)
            if not moduleScript then return nil end
            local ok, result = pcall(require, moduleScript)
            return ok and result or nil
        end

        local function rgToast(msg)
            pcall(function()
                showNotification("RIDE GUARD", tostring(msg), "info", 2.4)
            end)
        end

        local rgContainer = nil
        local rgListCache = {}
        local rgListCacheAt = 0
        local RG_LIST_TTL = 1.25

        local function rgFindContainer()
            if rgContainer and rgContainer.Parent then
                return rgContainer
            end

            -- Fast path used by the normal game hierarchy.
            local objects = WorkspaceRG:FindFirstChild("__OBJECTS")
            local areas = objects and objects:FindFirstChild("Areas")
            local direct = areas and areas:FindFirstChild("GuardAreas")
            if direct then
                rgContainer = direct
                return direct
            end

            -- Replication can place GuardAreas deeper than the private
            -- __OBJECTS path. Recursive discovery prevents a false
            -- "No Ride Guard" during streaming.
            local recursive = WorkspaceRG:FindFirstChild("GuardAreas", true)
            if recursive then
                rgContainer = recursive
                return recursive
            end

            return nil
        end

        local function rgFullList(force)
            local now = os.clock()
            if not force and now - rgListCacheAt < RG_LIST_TTL and #rgListCache > 0 then
                return rgListCache
            end

            local container = rgFindContainer()
            local result = {}
            for _, area in ipairs((container and container:GetChildren()) or {}) do
                -- Some versions nest the live Guard under a model/holder.
                if area:FindFirstChild("Guard", true) then
                    result[#result + 1] = area.Name
                end
            end
            table.sort(result)
            if #result > 0 then
                rgListCache = result
                rgListCacheAt = now
            end
            return result
        end

        local function rgSource(areaId)
            local container = rgFindContainer()
            if not container then return nil end
            local holder = container:FindFirstChild(tostring(areaId or ""))
            return holder and holder:FindFirstChild("Guard", true)
        end

        -- Measure the real guard body. Skinned guards use Bone.WorldPosition.
        local function rgSpan(model)
            local pivotY = model:GetPivot().Position.Y
            local bones = {}

            for _, d in ipairs(model:GetDescendants()) do
                if d:IsA("Bone") then
                    bones[#bones + 1] = d.WorldPosition.Y
                end
            end

            if #bones > 0 then
                table.sort(bones)
                return bones[1] - pivotY, bones[#bones] - pivotY
            end

            local inner = model:FindFirstChild("Model") or model
            local lo, hi = math.huge, -math.huge

            for _, d in ipairs(inner:GetDescendants()) do
                if d:IsA("BasePart") and d.Size.Magnitude > 0.1 then
                    local nm = d.Name
                    if not nm:find("Root")
                        and not nm:find("Point")
                        and not nm:find("Proxy")
                        and not nm:find("Collider")
                        and nm ~= "CENTER"
                        and nm ~= "Head"
                        and not nm:find("Fire") then
                        lo = math.min(lo, d.Position.Y - d.Size.Y / 2)
                        hi = math.max(hi, d.Position.Y + d.Size.Y / 2)
                    end
                end
            end

            if lo == math.huge then
                return -8, 8
            end
            return lo - pivotY, hi - pivotY
        end

        local function rgSink(areaId, guardHeight)
            if areaId == "Titan Temple" then return 8.5 end
            if areaId == "Volcano" then return 4.8 end
            if areaId == "Prehistoric" then return 1.5 end
            if guardHeight < 10 then return 1.0 end
            if guardHeight < 18 then return 2.0 end
            return 4.5
        end

        local function rgRestoreSource()
            local source = rgHiddenSource
            if source then
                for inst, state in pairs(rgHiddenState) do
                    if inst and inst.Parent then
                        if inst:IsA("BasePart") then
                            pcall(function() inst.LocalTransparencyModifier = state end)
                        elseif inst:IsA("ParticleEmitter")
                            or inst:IsA("Trail")
                            or inst:IsA("Beam")
                            or inst:IsA("Smoke")
                            or inst:IsA("Fire")
                            or inst:IsA("Sparkles") then
                            pcall(function() inst.Enabled = state end)
                        end
                    end
                end
            end
            rgHiddenSource = nil
            table.clear(rgHiddenState)
        end

        local function rgHideSource(source)
            rgRestoreSource()
            if not source or not source.Parent then return end
            rgHiddenSource = source
            for _, inst in ipairs(source:GetDescendants()) do
                if inst:IsA("BasePart") then
                    rgHiddenState[inst] = inst.LocalTransparencyModifier
                    inst.LocalTransparencyModifier = 1
                elseif inst:IsA("ParticleEmitter")
                    or inst:IsA("Trail")
                    or inst:IsA("Beam")
                    or inst:IsA("Smoke")
                    or inst:IsA("Fire")
                    or inst:IsA("Sparkles") then
                    rgHiddenState[inst] = inst.Enabled
                    inst.Enabled = false
                end
            end
        end

        local function rgDespawn()
            if rgConn then
                pcall(function() rgConn:Disconnect() end)
                rgConn = nil
            end
            if rgTrack then pcall(function() rgTrack:Stop() end); rgTrack = nil end
            if rgIdleTrack then pcall(function() rgIdleTrack:Stop() end); rgIdleTrack = nil end
            if rgMount then pcall(function() rgMount:Destroy() end); rgMount = nil end
            if rgSaddle then pcall(function() rgSaddle:Destroy() end); rgSaddle = nil end
            rgRestoreSource()
            rgFootOff, rgBackOff, rgRideLift = 0, 0, 0
        end

        local function rgSpawn(areaId)
            rgDespawn()

            local srcGuard = rgSource(areaId)
            if not srcGuard then
                return false, "Guard model not found"
            end

            local c = srcGuard:Clone()
            -- The source Guard can be visible in GuardAreas. Hide only the
            -- local visual copy; the actual server-side object is untouched.
            -- The cloned Ride Guard remains the single visible Guard.
            rgHideSource(srcGuard)
            c.Name = "DELL_RideGuard"
            local ohrp = c:FindFirstChild("HumanoidRootPart")

            for _, d in ipairs(c:GetDescendants()) do
                if d:IsA("BasePart") then
                    d.Anchored = (d == ohrp)
                    d.CanCollide = false
                    d.CastShadow = true
                end
            end

            local hum = c:FindFirstChildOfClass("Humanoid")
            if hum then
                pcall(function() hum.EvaluateStateMachine = false end)
            end

            c.Parent = WorkspaceRG

            -- Guard animations.
            local inner = c:FindFirstChild("Model")
            local controller = inner and inner:FindFirstChildOfClass("AnimationController")
            local animator = controller and controller:FindFirstChildOfClass("Animator")
            local dataFolder = ReplicatedStorageRG:FindFirstChild("Data")
            local guardsModule = dataFolder and dataFolder:FindFirstChild("Guards")
            local guardsData = rgReq(guardsModule)
            local guardData = guardsData and (guardsData.Directory or guardsData)[areaId]

            if animator and guardData then
                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    pcall(function() track:Stop() end)
                end

                local walkId = tostring(guardData.WalkAnimation):match("(%d+)")
                local idleId = tostring(guardData.IdleAnimation):match("(%d+)")

                if walkId then
                    local anim = Instance.new("Animation")
                    anim.AnimationId = "rbxassetid://" .. walkId
                    local ok, track = pcall(function()
                        return animator:LoadAnimation(anim)
                    end)
                    if ok and track then
                        track.Looped = true
                        track.Priority = Enum.AnimationPriority.Movement
                        track:Play()
                        rgTrack = track
                    end
                end

                if idleId then
                    local anim = Instance.new("Animation")
                    anim.AnimationId = "rbxassetid://" .. idleId
                    local ok, track = pcall(function()
                        return animator:LoadAnimation(anim)
                    end)
                    if ok and track then
                        track.Looped = true
                        track.Priority = Enum.AnimationPriority.Idle
                        track:Play()
                        rgIdleTrack = track
                    end
                end
            end

            local footOff, backOff = rgSpan(c)
            local guardHeight = math.max(1, backOff - footOff)
            local sinkOffset = rgSink(areaId, guardHeight)

            rgFootOff = footOff
            rgBackOff = backOff
            rgRideLift = math.max(0, guardHeight - sinkOffset)
            pcall(function() c:SetAttribute("DELL_GuardArea", tostring(areaId)) end)

            -- Invisible saddle for the player's feet.
            local saddle = Instance.new("Part")
            saddle.Name = "DELL_RideSaddle"
            saddle.Size = Vector3.new(20, 1, 20)
            saddle.Transparency = 1
            saddle.CanCollide = true
            saddle.Anchored = true
            saddle.CanQuery = false
            saddle.CanTouch = false
            saddle.Parent = WorkspaceRG
            rgSaddle = saddle
            rgMount = c

            local lastLook = Vector3.new(0, 0, -1)
            local lastPos = (rgHRP() and rgHRP().Position) or Vector3.zero

            local rayParams = RaycastParams.new()
            rayParams.FilterType = Enum.RaycastFilterType.Exclude

            local character = LocalPlayerRG.Character
            local pHum = character and character:FindFirstChildOfClass("Humanoid")
            if pHum then
                pcall(function()
                    pHum.PlatformStand = false
                    pHum.Sit = false
                    pHum:SetStateEnabled(Enum.HumanoidStateType.Running, true)
                    pHum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
                    pHum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
                end)
            end

            -- Initial mount.
            local initialRoot = rgHRP()
            if initialRoot then
                rayParams.FilterDescendantsInstances = {character, c, saddle}
                local hit = WorkspaceRG:Raycast(
                    initialRoot.Position,
                    Vector3.new(0, -90, 0),
                    rayParams
                )
                local groundY = hit and hit.Position.Y or (initialRoot.Position.Y - 3)
                local saddleY = (groundY - footOff) + backOff - sinkOffset
                saddle.Position = Vector3.new(initialRoot.Position.X, saddleY, initialRoot.Position.Z)
                initialRoot.CFrame = CFrame.new(
                    initialRoot.Position.X,
                    saddleY + 3,
                    initialRoot.Position.Z
                )
                initialRoot.AssemblyLinearVelocity = Vector3.zero
            end

            local rgVisualAcc = 0
            rgConn = RunServiceRG.RenderStepped:Connect(function(dt)
                if not rgRideOn then return end
                if dev and type(dev.lite) == "function" and dev.lite() then
                    rgVisualAcc = rgVisualAcc + (dt or 0)
                    if rgVisualAcc < 0.033 then return end
                    rgVisualAcc = 0
                end

                local r = rgHRP()
                if not r or not c.Parent or not saddle.Parent then
                    return
                end

                local d = r.Position - lastPos
                lastPos = r.Position
                local flat = Vector3.new(d.X, 0, d.Z)
                local moveSpeed = flat.Magnitude / math.max(dt, 1 / 240)

                local currentHum = LocalPlayerRG.Character
                    and LocalPlayerRG.Character:FindFirstChildOfClass("Humanoid")

                local moveDir = currentHum and currentHum.MoveDirection or Vector3.zero
                local targetLook = lastLook

                if moveDir.Magnitude > 0.05 then
                    targetLook = Vector3.new(moveDir.X, 0, moveDir.Z).Unit
                elseif flat.Magnitude > 0.05 then
                    targetLook = flat.Unit
                else
                    local look = r.CFrame.LookVector
                    local flatLook = Vector3.new(look.X, 0, look.Z)
                    if flatLook.Magnitude > 0.01 then
                        targetLook = flatLook.Unit
                    end
                end

                if targetLook.Magnitude > 0.1 and lastLook.Magnitude > 0.1 then
                    local blended = lastLook:Lerp(
                        targetLook,
                        math.clamp(dt * 12.0, 0.05, 1.0)
                    )
                    if blended.Magnitude > 0.01 then
                        lastLook = blended.Unit
                    end
                end

                -- Keep the player's normal run/walk animation from fighting the mount.
                local playerAnimator = currentHum and currentHum:FindFirstChildOfClass("Animator")
                if playerAnimator then
                    for _, track in ipairs(playerAnimator:GetPlayingAnimationTracks()) do
                        local trackName = tostring(track.Name):lower()
                        local animation = track.Animation
                        local animationId = animation and animation.AnimationId or ""
                        if trackName:find("run")
                            or trackName:find("walk")
                            or trackName:find("jump")
                            or trackName:find("fall")
                            or trackName:find("swim")
                            or animationId:find("run")
                            or animationId:find("walk") then
                            pcall(function() track:Stop(0.1) end)
                        end
                    end
                end

                -- Guard animation blending.
                if rgTrack and rgIdleTrack then
                    if moveSpeed > 1.5 then
                        rgTrack:AdjustWeight(1.0, 0.1)
                        rgIdleTrack:AdjustWeight(0.0, 0.1)
                        rgTrack:AdjustSpeed(math.clamp(moveSpeed / 28, 0.5, 2.5))
                    else
                        rgTrack:AdjustWeight(0.0, 0.15)
                        rgIdleTrack:AdjustWeight(1.0, 0.15)
                    end
                elseif rgTrack then
                    rgTrack:AdjustSpeed(
                        moveSpeed > 1.5 and math.clamp(moveSpeed / 28, 0.5, 2.5) or 0.6
                    )
                end

                -- Ground detection + air mode.
                rayParams.FilterDescendantsInstances = {
                    LocalPlayerRG.Character, c, saddle
                }

                local startY = r.Position.Y + 4
                local hit = WorkspaceRG:Raycast(
                    Vector3.new(r.Position.X, startY, r.Position.Z),
                    Vector3.new(0, -(rgRideLift + 35), 0),
                    rayParams
                )

                if not hit or hit.Position.Y > (r.Position.Y + 2) then
                    hit = WorkspaceRG:Raycast(
                        Vector3.new(
                            r.Position.X,
                            r.Position.Y - rgRideLift + 2,
                            r.Position.Z
                        ),
                        Vector3.new(0, -30, 0),
                        rayParams
                    )
                end

                local groundY = (hit and hit.Position.Y < (r.Position.Y + 2))
                    and hit.Position.Y
                    or 67.57

                local inAir = (r.Position.Y - groundY) > (rgRideLift + 12)

                local guardPivotY
                local guardBackY
                local saddleY

                if not inAir then
                    guardPivotY = groundY - footOff
                    guardBackY = guardPivotY + backOff
                    saddleY = guardBackY - sinkOffset

                    saddle.Position = Vector3.new(
                        r.Position.X,
                        saddleY,
                        r.Position.Z
                    )
                    saddle.CanCollide = true

                    -- Do not fight the main Auto Steal mover if it is active.
                    local autoBusy = false
                    pcall(function() autoBusy = auto.isRunning() == true end)

                    if not autoBusy and r.Position.Y < saddleY + 2 then
                        r.CFrame = CFrame.new(
                            r.Position.X,
                            saddleY + 3,
                            r.Position.Z
                        )
                        r.AssemblyLinearVelocity = Vector3.zero
                    end
                else
                    -- Air mode: keep the guard's back directly under the player.
                    saddle.CanCollide = false
                    guardPivotY = r.Position.Y - 3 - backOff + sinkOffset
                end

                local base = Vector3.new(
                    r.Position.X,
                    guardPivotY,
                    r.Position.Z
                )
                local guardCFrame = CFrame.lookAt(
                    base,
                    base + lastLook
                )

                if inAir then
                    guardCFrame = guardCFrame * CFrame.Angles(math.rad(-15), 0, 0)
                end

                c:PivotTo(guardCFrame)
            end)

            return true
        end

        -- ===================== AUTO STEAL DELIVERY API =====================
        -- Auto Steal can temporarily mount the currently selected Ride Guard
        -- while the carried egg is travelling to the safe zone.  This uses the
        -- same Ride Guard implementation above; it does not create a second
        -- worker or a second GUI.
        local function rgEnv()
            local env = _G
            if type(getgenv) == "function" then
                local ok, e = pcall(getgenv)
                if ok and type(e) == "table" then env = e end
            end
            return env
        end

        local rgApi = {
            isOn = function() return rgRideOn == true end,
            selected = function() return rgSelected end,
            refresh = function() end,
        }

        -- Resolve the exact Ride Guard for an egg area.  GuardAreas uses the
        -- same area names as EggState (for example "Cherry Blossom", "Cosmic",
        -- "Forest", etc.).  A case/space-insensitive fallback makes this robust
        -- to small display-name differences without changing the actual area id.
        local function rgResolveAreaGuard(areaId)
            local wanted = tostring(areaId or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if wanted == "" then return nil end

            -- Refresh the container before resolving a dynamic rarity target.
            -- GuardAreas can appear a little after the egg field, so a cached
            -- container with an incomplete child set must not turn into a hard
            -- "Ride Guard not ready" failure.
            rgFindContainer()

            if rgSource(wanted) then
                return wanted
            end

            -- One tiny streaming refresh is enough here. Do NOT wait seconds
            -- inside the carry function: that blocks the Auto Steal worker and
            -- makes every missing Ride Guard look like game lag. The outer
            -- worker already has bounded backoff.
            task.wait(0.08)
            rgContainer = nil
            rgListCache = {}
            rgListCacheAt = 0
            if rgSource(wanted) then
                return wanted
            end

            local function norm(v)
                return tostring(v or ""):lower():gsub("[^%w]", "")
            end

            local folded = wanted:lower():gsub("%s+", " ")
            local wantedNorm = norm(wanted)
            for _, name in ipairs(rgFullList(true)) do
                local nText = tostring(name):gsub("^%s+", ""):gsub("%s+$", "")
                local n = nText:lower():gsub("%s+", " ")
                if n == folded or norm(nText) == wantedNorm then
                    return nText
                end
            end

            -- First-area naming has historically appeared as FirstArea/First
            -- Area while the live GuardAreas folder uses Forest. Keep the
            -- canonical live guard name as a compatibility alias.
            local first = wantedNorm
            if first == "firstarea" or first == "firstareaid" or first == "first" then
                for _, name in ipairs(rgFullList()) do
                    if norm(name) == "forest" then return name end
                end
            end

            return nil
        end

        function rgApi.beginDelivery(areaId, options)
            options = options or {}
            local wasOn = rgRideOn == true
            local previousGuard = nil
            if wasOn and rgMount then
                previousGuard = rgMount:GetAttribute("DELL_GuardArea")
            end
            previousGuard = previousGuard or rgSelected

            local target
            if options.onlyForRarity and areaId then
                target = rgResolveAreaGuard(areaId)
                if not target then
                    -- The egg can be valid while its GuardAreas child is still
                    -- replicating. Do not kill Auto Farm Rarity for that one
                    -- timing window: use the user's selected guard, or the first
                    -- live guard, and let delivery continue.
                    target = rgSelected or rgFullList(true)[1]
                    if target then
                        log.warn("Ride Guard area=%s unresolved; using fallback guard=%s",
                            tostring(areaId), tostring(target))
                    else
                        return false, "No Ride Guard available for egg area: " .. tostring(areaId)
                    end
                end
            else
                target = rgSelected or (rgFullList(true)[1])
            end

            if not target then
                return false, "No Ride Guard selected"
            end

            if not wasOn then
                rgRideOn = true
                local ok, why = rgSpawn(target)
                if not ok then
                    rgRideOn = false
                    rgDespawn()
                    return false, tostring(why or "Ride Guard spawn failed")
                end
            elseif not rgMount or not rgMount.Parent then
                local ok, why = rgSpawn(target)
                if not ok then
                    return false, tostring(why or "Ride Guard remount failed")
                end
            elseif options.onlyForRarity then
                -- Rarity mode is area-aware: if the current mounted guard is not
                -- the guard belonging to this egg's area, swap it before travel.
                -- The spawned clone is named DELL_RideGuard, so compare the source
                -- area stored below rather than the clone name.
                if rgMount:GetAttribute("DELL_GuardArea") ~= tostring(target) then
                    local ok, why = rgSpawn(target)
                    if not ok then
                        return false, tostring(why or "Ride Guard area swap failed")
                    end
                end
            end

            pcall(function()
                if rgMount then rgMount:SetAttribute("DELL_GuardArea", tostring(target)) end
            end)

            return true, {
                wasOn = wasOn,
                guard = target,
                areaId = areaId,
                dynamic = options.onlyForRarity == true,
                previousGuard = previousGuard,
            }
        end

        function rgApi.endDelivery(session)
            session = session or {}
            -- If the user already had Ride Guard ON, leave it running.
            -- If Auto Steal temporarily enabled it, return the UI to its
            -- original OFF state after delivery.
            if not session.wasOn then
                rgRideOn = false
                rgDespawn()
            elseif session.dynamic and session.previousGuard
                    and tostring(session.previousGuard) ~= tostring(session.guard) then
                -- A manually active Ride Guard must return to the user's
                -- original guard after the rarity delivery finishes.
                local restore = rgResolveAreaGuard(session.previousGuard)
                if restore then
                    pcall(function() rgSpawn(restore) end)
                    rgSelected = restore
                end
            end
            pcall(function() rgApi.refresh() end)
        end

        local env = rgEnv()
        env.__DELL_RIDE_GUARD_API = rgApi

        -- ---------- UI: added to the ORIGINAL scroll, no second ScreenGui ----------
        local rgSection = Instance.new("Frame", scroll)
        rgSection.Name = "RideGuardSection"
        rgSection.Size = UDim2.new(1, 0, 0, 426)
        rgSection.BackgroundColor3 = Color3.fromRGB(10, 11, 16)
        rgSection.BackgroundTransparency = 0.18
        rgSection.BorderSizePixel = 0

        local rgCorner = Instance.new("UICorner", rgSection)
        rgCorner.CornerRadius = UDim.new(0, 12)

        local rgStroke = Instance.new("UIStroke", rgSection)
        rgStroke.Thickness = 1.8
        rgStroke.Transparency = 0.12
        rgStroke.Color = Color3.fromRGB(188, 67, 255)

        local rgTitle = Instance.new("TextLabel", rgSection)
        rgTitle.Size = UDim2.new(1, -18, 0, 22)
        rgTitle.Position = UDim2.fromOffset(9, 7)
        rgTitle.BackgroundTransparency = 1
        rgTitle.Font = Enum.Font.GothamBold
        rgTitle.Text = "🐎  RIDE GUARD"
        rgTitle.TextColor3 = Color3.fromRGB(245, 248, 255)
        rgTitle.TextSize = 12
        rgTitle.TextXAlignment = Enum.TextXAlignment.Left

        local rgSub = Instance.new("TextLabel", rgSection)
        rgSub.Size = UDim2.new(1, -18, 0, 20)
        rgSub.Position = UDim2.fromOffset(9, 29)
        rgSub.BackgroundTransparency = 1
        rgSub.Font = Enum.Font.Gotham
        rgSub.Text = "Guard List • smooth follow • ground/air mode • auto remount"
        rgSub.TextColor3 = Color3.fromRGB(155, 175, 195)
        rgSub.TextSize = 9
        rgSub.TextXAlignment = Enum.TextXAlignment.Left

        local rgSelectedLabel = Instance.new("TextLabel", rgSection)
        rgSelectedLabel.Size = UDim2.new(1, -18, 0, 23)
        rgSelectedLabel.Position = UDim2.fromOffset(9, 52)
        rgSelectedLabel.BackgroundColor3 = Color3.fromRGB(13, 24, 31)
        rgSelectedLabel.BackgroundTransparency = 0.02
        rgSelectedLabel.BorderSizePixel = 0
        rgSelectedLabel.Font = Enum.Font.GothamBold
        rgSelectedLabel.Text = "GUARD: scanning..."
        rgSelectedLabel.TextColor3 = Color3.fromRGB(95, 235, 255)
        rgSelectedLabel.TextSize = 9
        rgSelectedLabel.TextXAlignment = Enum.TextXAlignment.Left
        Instance.new("UICorner", rgSelectedLabel).CornerRadius = UDim.new(0, 7)

        local rgSelPad = Instance.new("UIPadding", rgSelectedLabel)
        rgSelPad.PaddingLeft = UDim.new(0, 8)

        local rgSearch = Instance.new("TextBox", rgSection)
        rgSearch.Name = "GuardSearch"
        rgSearch.Size = UDim2.new(1, -18, 0, 29)
        rgSearch.Position = UDim2.fromOffset(9, 81)
        rgSearch.BackgroundColor3 = Color3.fromRGB(16, 18, 27)
        rgSearch.BackgroundTransparency = 0.08
        rgSearch.BorderSizePixel = 0
        rgSearch.ClearTextOnFocus = false
        rgSearch.Font = Enum.Font.Gotham
        rgSearch.PlaceholderText = "Search guard / area..."
        rgSearch.PlaceholderColor3 = Color3.fromRGB(115, 124, 145)
        rgSearch.Text = ""
        rgSearch.TextColor3 = Color3.fromRGB(240, 245, 255)
        rgSearch.TextSize = 10
        rgSearch.TextXAlignment = Enum.TextXAlignment.Left
        Instance.new("UICorner", rgSearch).CornerRadius = UDim.new(0, 8)

        local rgSearchPad = Instance.new("UIPadding", rgSearch)
        rgSearchPad.PaddingLeft = UDim.new(0, 9)
        rgSearchPad.PaddingRight = UDim.new(0, 9)

        local rgListFrame = Instance.new("ScrollingFrame", rgSection)
        rgListFrame.Name = "GuardList"
        rgListFrame.Size = UDim2.new(1, -18, 0, 122)
        rgListFrame.Position = UDim2.fromOffset(9, 115)
        rgListFrame.BackgroundColor3 = Color3.fromRGB(9, 11, 17)
        rgListFrame.BackgroundTransparency = 0.06
        rgListFrame.BorderSizePixel = 0
        rgListFrame.ScrollBarThickness = 8
        rgListFrame.ScrollBarImageColor3 = Color3.fromRGB(188, 67, 255)
        rgListFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
        rgListFrame.CanvasSize = UDim2.fromOffset(0, 0)

        Instance.new("UICorner", rgListFrame).CornerRadius = UDim.new(0, 9)

        local rgListLayout = Instance.new("UIListLayout", rgListFrame)
        rgListLayout.Padding = UDim.new(0, 4)
        rgListLayout.SortOrder = Enum.SortOrder.LayoutOrder

        local rgListPad = Instance.new("UIPadding", rgListFrame)
        rgListPad.PaddingTop = UDim.new(0, 5)
        rgListPad.PaddingLeft = UDim.new(0, 5)
        rgListPad.PaddingRight = UDim.new(0, 5)
        rgListPad.PaddingBottom = UDim.new(0, 5)

        local rgRefresh = Instance.new("TextButton", rgSection)
        rgRefresh.Size = UDim2.new(0.49, -7, 0, 30)
        rgRefresh.Position = UDim2.fromOffset(9, 245)
        rgRefresh.BackgroundColor3 = Color3.fromRGB(9, 45, 60)
        rgRefresh.BorderSizePixel = 0
        rgRefresh.Font = Enum.Font.GothamBold
        rgRefresh.Text = "↻ REFRESH GUARD LIST"
        rgRefresh.TextColor3 = Color3.fromRGB(255, 255, 255)
        rgRefresh.TextSize = 9
        Instance.new("UICorner", rgRefresh).CornerRadius = UDim.new(0, 7)

        local rgRideButton = Instance.new("TextButton", rgSection)
        rgRideButton.Size = UDim2.new(0.49, -7, 0, 30)
        rgRideButton.Position = UDim2.new(0.51, 4, 0, 245)
        rgRideButton.BackgroundColor3 = Color3.fromRGB(9, 45, 60)
        rgRideButton.BorderSizePixel = 0
        rgRideButton.Font = Enum.Font.GothamBold
        rgRideButton.Text = "🐎 RIDE GUARD [OFF]"
        rgRideButton.TextColor3 = Color3.fromRGB(255, 255, 255)
        rgRideButton.TextSize = 9
        Instance.new("UICorner", rgRideButton).CornerRadius = UDim.new(0, 7)

        -- Declare status before the callback so Lua closes over the correct local.
        local rgStatus = Instance.new("TextLabel", rgSection)
        rgStatus.Size = UDim2.new(1, -18, 0, 74)
        rgStatus.Position = UDim2.fromOffset(316)
        rgStatus.BackgroundColor3 = Color3.fromRGB(16, 20, 29)
        rgStatus.BackgroundTransparency = 0.05
        rgStatus.BorderSizePixel = 0
        rgStatus.Font = Enum.Font.Gotham
        rgStatus.Text = "Status: OFF\nGuard: NONE\nGuards found: 0"
        rgStatus.TextColor3 = Color3.fromRGB(125, 210, 235)
        rgStatus.TextSize = 9
        rgStatus.TextWrapped = true
        rgStatus.TextXAlignment = Enum.TextXAlignment.Left
        rgStatus.TextYAlignment = Enum.TextYAlignment.Center
        Instance.new("UICorner", rgStatus).CornerRadius = UDim.new(0, 8)

        local rgStatusPad = Instance.new("UIPadding", rgStatus)
        rgStatusPad.PaddingLeft = UDim.new(0, 9)
        rgStatusPad.PaddingRight = UDim.new(0, 9)

        local function updateRideVisual()
            rgRideButton.Text = rgRideOn
                and "🐎 RIDE GUARD [ON]"
                or "🐎 RIDE GUARD [OFF]"
            rgRideButton.BackgroundColor3 = rgRideOn
                and Color3.fromRGB(0, 105, 145)
                or Color3.fromRGB(9, 45, 60)

            rgSelectedLabel.Text = "GUARD: " .. tostring(rgSelected or "NONE")
        end

        local function refreshGuardList()
            for _, child in ipairs(rgListFrame:GetChildren()) do
                if child:IsA("TextButton") or child.Name == "RGEmpty" then
                    child:Destroy()
                end
            end

            local all = rgFullList()
            local shown = {}
            local q = rgSearchText:lower()

            for _, name in ipairs(all) do
                if q == "" or name:lower():find(q, 1, true) then
                    shown[#shown + 1] = name
                end
            end

            if #shown == 0 then
                local empty = Instance.new("TextLabel", rgListFrame)
                empty.Name = "RGEmpty"
                empty.Size = UDim2.new(1, -4, 0, 42)
                empty.BackgroundTransparency = 1
                empty.Font = Enum.Font.GothamBold
                empty.Text = "NO GUARD FOUND"
                empty.TextColor3 = Color3.fromRGB(125, 165, 185)
                empty.TextSize = 10
                return
            end

            for index, name in ipairs(shown) do
                local b = Instance.new("TextButton", rgListFrame)
                b.Name = "Guard_" .. name
                b.LayoutOrder = index
                b.Size = UDim2.new(1, -2, 0, 28)
                b.BackgroundColor3 = (rgSelected == name)
                    and Color3.fromRGB(8, 75, 100)
                    or Color3.fromRGB(16, 24, 31)
                b.BackgroundTransparency = 0.04
                b.BorderSizePixel = 0
                b.Font = Enum.Font.GothamBold
                b.Text = "  " .. name
                b.TextColor3 = Color3.fromRGB(238, 248, 255)
                b.TextSize = 9
                b.TextXAlignment = Enum.TextXAlignment.Left
                b.TextTruncate = Enum.TextTruncate.AtEnd

                Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)

                local s = Instance.new("UIStroke", b)
                s.Thickness = 1
                s.Transparency = (rgSelected == name) and 0.08 or 0.72
                s.Color = Color3.fromRGB(188, 67, 255)

                b.Activated:Connect(function()
                    rgSelected = name
                    updateRideVisual()
                    refreshGuardList()

                    if rgRideOn then
                        local ok, why = rgSpawn(name)
                        if not ok then
                            rgRideOn = false
                            updateRideVisual()
                            rgStatus.Text = "Status: ERROR\n" .. tostring(why)
                            return
                        end
                    end

                    rgStatus.Text = string.format(
                        "Status: %s\nGuard: %s\nGuards found: %d",
                        rgRideOn and "RIDING" or "READY",
                        name,
                        #all
                    )
                end)
            end

            if not rgSelected and shown[1] then
                rgSelected = shown[1]
                updateRideVisual()
            end

            rgStatus.Text = string.format(
                "Status: %s\nGuard: %s\nGuards found: %d",
                rgRideOn and "RIDING" or "READY",
                tostring(rgSelected or "NONE"),
                #all
            )
        end

        rgRefresh.Activated:Connect(function()
            refreshGuardList()
            rgToast("Guard List refreshed")
        end)

        rgSearch:GetPropertyChangedSignal("Text"):Connect(function()
            rgSearchText = tostring(rgSearch.Text or "")
            refreshGuardList()
        end)

        rgRideButton.Activated:Connect(function()
            if rgRideOn then
                rgRideOn = false
                rgDespawn()
                updateRideVisual()
                rgStatus.Text = string.format(
                    "Status: OFF\nGuard: %s\nGuards found: %d",
                    tostring(rgSelected or "NONE"),
                    #rgFullList()
                )
                rgToast("Ride Guard stopped")
                return
            end

            local target = rgSelected or rgFullList()[1]
            if not target then
                rgStatus.Text = "Status: ERROR\nNo guard model found"
                rgToast("No guard model found")
                return
            end

            local ok, why = rgSpawn(target)
            if not ok then
                rgRideOn = false
                updateRideVisual()
                rgStatus.Text = "Status: ERROR\n" .. tostring(why)
                rgToast(tostring(why))
                return
            end

            rgSelected = target
            rgRideOn = true
            updateRideVisual()
            rgStatus.Text = string.format(
                "Status: RIDING\nGuard: %s\nGuards found: %d",
                target,
                #rgFullList()
            )
            rgToast("Ride Guard enabled: " .. target)
        end)

        -- Auto re-mount after respawn when Ride Guard was enabled.
        LocalPlayerRG.CharacterAdded:Connect(function()
            task.wait(1.5)
            if not rgRideOn then return end

            local target = rgSelected or rgFullList()[1]
            if not target then
                rgRideOn = false
                updateRideVisual()
                return
            end

            local ok = rgSpawn(target)
            if not ok then
                rgRideOn = false
                updateRideVisual()
                rgStatus.Text = "Status: RESPAWN REMOUNT FAILED\nGuard: " .. tostring(target)
            else
                rgStatus.Text = "Status: RIDING\nGuard: " .. tostring(target) .. "\nRespawn remounted"
            end
        end)

        refreshGuardList()
        updateRideVisual()
    end

    pcall(installRideGuard)
    -- ===================== END RIDE GUARD + GUARD LIST =====================

    -- ======================================================================
    -- AUTO STEAL FROM PLAYERS BY RARITY
    -- ======================================================================
    --
    -- This is intentionally a separate worker from the egg-field rarity farm.
    -- It scans the current server's Players, tries to resolve the egg/pet/
    -- rarity metadata exposed on the player's character/tool/attributes, then:
    --
    --   player -> selected movement method -> equip Bat -> swing
    --       -> detect the newly Dropped egg -> instant grab -> Safe Zone
    --
    -- The actual Bat swing is the game's existing Bat controller path exposed
    -- by features.bossfight; the egg pickup/delivery uses the same instant and
    -- carry modules as Auto Farm Egg.
    -- ======================================================================
    playerStealOn = false
    playerStealRun = 0
    playerStealBusy = false
    playerStealSelected = {}
    playerStealRows = {}
    playerStealLastScan = 0
    playerStealCooldown = {}
    playerStealStatus = nil
    playerStealSection = nil

    local function playerStealReadAttr(obj, names)
        if not obj or type(names) ~= "table" then return nil end
        for _, name in ipairs(names) do
            local ok, value = pcall(function() return obj:GetAttribute(name) end)
            if ok and value ~= nil and tostring(value) ~= "" then
                return value
            end
        end
        return nil
    end

    local function playerStealClean(v)
        if v == nil then return nil end
        local t = tostring(v)
        t = t:gsub("^%s+", ""):gsub("%s+$", "")
        if t == "" or t:lower() == "nil" or t:lower() == "unknown" then return nil end
        return t
    end

    local function playerStealScanOne(plr)
        if not plr or plr == player then return nil end
        local char = plr.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return nil end

        local info = {
            player = plr,
            userId = plr.UserId,
            name = plr.Name,
            displayName = plr.DisplayName,
            pos = root.Position,
            distance = 0,
            egg = nil,
            pet = nil,
            rarity = nil,
            weight = nil,
            uid = nil,
        }

        local function absorb(obj)
            if not obj then return end
            local egg = playerStealReadAttr(obj, {
                "EggName", "Egg", "CarriedEgg", "HeldEgg", "EggType",
                "EggAsset", "AssetCategory", "EggId", "EggUID", "EggUid"
            })
            local pet = playerStealReadAttr(obj, {
                "PetName", "Pet", "HatchPet", "PetType", "PetId", "PetNameId"
            })
            local rarity = playerStealReadAttr(obj, {
                "Rarity", "EggRarity", "RarityName", "RarityId"
            })
            local weight = playerStealReadAttr(obj, { "Weight", "Kg", "KG", "EggWeight" })
            local uid = playerStealReadAttr(obj, { "UID", "Uid", "EggUID", "EggUid" })

            egg, pet, rarity, weight, uid = playerStealClean(egg), playerStealClean(pet),
                playerStealClean(rarity), playerStealClean(weight), playerStealClean(uid)

            local n = tostring(obj.Name or "")
            local low = n:lower()
            local looksEgg = low:find("egg", 1, true) ~= nil
            local looksPet = low:find("pet", 1, true) ~= nil
            if looksEgg and not egg then egg = n end
            if looksPet and not pet then pet = n end

            if egg and not info.egg then info.egg = egg end
            if pet and not info.pet then info.pet = pet end
            if rarity and not info.rarity then info.rarity = rarity end
            if weight and not info.weight then info.weight = weight end
            if uid and not info.uid then info.uid = uid end
        end

        absorb(plr)
        absorb(char)

        -- Prefer the game's replicated EggState when a build exposes the
        -- carrier/owner field. Different builds have used different field
        -- names, so this reader accepts the common variants without assuming
        -- one schema. This is what lets the list show the actual egg carried
        -- by a player even when the egg model itself is not parented to their
        -- character.
        pcall(function()
            local ES = BX.require("core.data").eggState()
            local records = ES and ES.ReadFieldEggs and ES.ReadFieldEggs()
            for _, rec in pairs(records and records.Records or {}) do
                if tostring(rec.State or "") == "Carried" then
                    local carrier = rec.CarrierUserId or rec.CarrierId or rec.HolderUserId
                        or rec.HolderId or rec.PlayerUserId or rec.PlayerId
                        or rec.OwnerUserId or rec.OwnerId or rec.UserId
                    if tonumber(carrier) == tonumber(plr.UserId) or tostring(carrier) == tostring(plr.UserId) then
                        local egg = rec.EggName or rec.EggType or rec.AssetCategory or rec.Name
                        local pet = rec.PetName or rec.Pet or rec.HatchPet or rec.PetType
                        local rarity = rec.Rarity or rec.EggRarity or rec.RarityName
                        local weight = rec.Weight or rec.Kg or rec.KG or rec.EggWeight
                        info.egg = playerStealClean(egg) or info.egg
                        info.pet = playerStealClean(pet) or info.pet
                        info.rarity = playerStealClean(rarity) or info.rarity
                        info.weight = playerStealClean(weight) or info.weight
                        info.uid = playerStealClean(rec.Uid or rec.UID or rec.EggUid or rec.EggUID) or info.uid
                        break
                    end
                end
            end
        end)

        for _, obj in ipairs(char:GetChildren()) do absorb(obj) end

        -- Only descend through objects that plausibly represent the held egg/
        -- pet. This avoids a full metadata scrape of every cosmetic instance.
        local desc = char:GetDescendants()
        for i = 1, #desc do
            local obj = desc[i]
            local n = tostring(obj.Name or "")
            local low = n:lower()
            if low:find("egg", 1, true) or low:find("pet", 1, true)
                or low:find("carried", 1, true) or low:find("held", 1, true) then
                absorb(obj)
            else
                -- Attribute-only carriers are still useful, but stop after a
                -- small bounded sample to keep the server scanner cheap.
                local hasR = playerStealReadAttr(obj, { "Rarity", "EggRarity", "RarityName" })
                local hasE = playerStealReadAttr(obj, { "EggName", "Egg", "CarriedEgg", "HeldEgg" })
                if hasR or hasE then absorb(obj) end
            end
        end

        -- Some builds expose the carried object as a Tool in Backpack/character.
        local bp = plr:FindFirstChildOfClass("Backpack")
        if bp then
            for _, obj in ipairs(bp:GetChildren()) do absorb(obj) end
        end

        info.distance = (root.Position - (ch.root() and ch.root().Position or root.Position)).Magnitude
        info.rarity = info.rarity or "UNKNOWN"
        info.egg = info.egg or "Egg metadata not exposed"
        info.pet = info.pet or "Pet metadata not exposed"
        return info
    end

    local function playerStealRarityMatches(rarity)
        local wanted = {}
        for key, on in pairs(playerStealSelected) do
            if on then wanted[normalizeRarity(key)] = true end
        end
        if next(wanted) == nil then return true end
        local r = normalizeRarity(rarity)
        if r == "" then return false end
        if wanted[r] then return true end
        for _, key in ipairs(rarityOrder or {}) do
            if playerStealSelected[key] then
                for _, alias in ipairs(rarityAliases[key] or {}) do
                    if r == normalizeRarity(alias) then return true end
                end
            end
        end
        return false
    end

    local function playerStealFindRows()
        local rows = {}

        -- Some executor/runtime states can expose the cached services table
        -- before the Players entry is available. Never index svc.Players
        -- blindly: player-steal scanning must fail closed instead of crashing
        -- the whole hub.
        local PlayersService = svc and svc.Players
        if not PlayersService then
            local ok, service = pcall(game.GetService, game, "Players")
            if ok and service then
                PlayersService = service
            end
        end

        if not PlayersService then
            pcall(function()
                BX.require("boot.log").for_module("playersteal"):warn(
                    "Players service unavailable; player steal scan skipped safely"
                )
            end)
            return rows
        end

        local players = PlayersService:GetPlayers()
        for i = 1, #players do
            local plr = players[i]
            local ok, row = pcall(playerStealScanOne, plr)
            if ok and row and playerStealRarityMatches(row.rarity) then
                rows[#rows + 1] = row
            end
        end
        table.sort(rows, function(a, b)
            local ar = normalizeRarity(a.rarity)
            local br = normalizeRarity(b.rarity)
            if ar ~= br then return ar < br end
            return (a.distance or math.huge) < (b.distance or math.huge)
        end)
        return rows
    end

    local function playerStealFindDroppedNear(pos, wantedRarity, maxDist)
        local list = nil
        local ok = pcall(function()
            list = eggsFeature.list({ state = { Dropped = true, Slot = true } }, true)
        end)
        if not ok or type(list) ~= "table" then return nil end

        local best, bestD = nil, maxDist or 24
        for _, e in ipairs(list) do
            if e and e.uid and e.pos and playerStealRarityMatches(e.rarity)
                and (not wantedRarity or normalizeRarity(e.rarity) == normalizeRarity(wantedRarity)) then
                local d = (e.pos - pos).Magnitude
                if d <= bestD then
                    best, bestD = e, d
                end
            end
        end
        return best
    end

    local function playerStealMoveTo(pos, cancel)
        local move = BX.require("features.movement")
        local speed = tonumber(deliverySpeeds[autoStealMethod]) or 1050
        speed = math.min(speed, 3000)
        return move.travel{
            to = pos,
            speed = speed,
            arrive = 5,
            carrying = false,
            cancel = cancel,
            maxStep = 10,
            maxFrame = 0.075,
            maxDebt = 0.12,
            tag = "player steal " .. tostring(autoStealMethod),
        }
    end

    local function playerStealCycle(targetRow, token)
        if not targetRow or token ~= playerStealRun then return false, "cancelled" end
        if playerStealBusy then return false, "busy" end
        playerStealBusy = true

        local function done(ok, why)
            playerStealBusy = false
            return ok, why
        end

        local targetPlayer = targetRow.player
        local cooldownUntil = tonumber(playerStealCooldown[targetPlayer.UserId]) or 0
        if os.clock() < cooldownUntil then
            return done(false, "target cooldown")
        end
        playerStealCooldown[targetPlayer.UserId] = os.clock() + 1.5

        local targetRoot = targetPlayer and targetPlayer.Character
            and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not targetRoot then return done(false, "target left the server") end

        -- Do not start a player-steal run while we are carrying our own egg.
        local held = eggsFeature.carryingUid and eggsFeature.carryingUid() or nil
        if held then
            local carryFeature = BX.require("features.carry")
            local ok = carryFeature.home(held, {
                method = autoStealMethod,
                deliverySpeed = deliverySpeeds[autoStealMethod],
                returnToBase = false,
            })
            if not ok then return done(false, "could not clear carried egg") end
        end

        local cancel = function()
            return token ~= playerStealRun or not playerStealOn or not BX.alive()
        end

        -- Selected method is used for the approach. RIDE GUARD is a delivery
        -- transport in the core engine, so the approach falls back to its
        -- normal movement travel rather than mounting a guard without an egg.
        local latestRoot = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not latestRoot then return done(false, "target character disappeared") end
        local targetPos = latestRoot.Position
        local moved = playerStealMoveTo(targetPos, cancel)
        if not moved then return done(false, "approach cancelled/failed") end
        if cancel() then return done(false, "cancelled") end

        local fight = nil
        pcall(function() fight = BX.require("features.bossfight") end)
        -- Try the same keyboard slot the user requested first, then use the
        -- reliable Humanoid:EquipTool fallback from the Bat controller.
        pcall(function()
            local vim = game:GetService("VirtualInputManager")
            vim:SendKeyEvent(true, Enum.KeyCode.One, false, game)
            vim:SendKeyEvent(false, Enum.KeyCode.One, false, game)
        end)
        task.wait(0.05)
        local bat = fight and fight.equipBat and fight.equipBat() or nil
        if not bat then return done(false, "Bat not found") end

        -- Re-anchor the target once more immediately before the swing.
        latestRoot = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
        if latestRoot then targetPos = latestRoot.Position end
        local myRoot = ch.root()
        if not myRoot or (myRoot.Position - targetPos).Magnitude > 12 then
            playerStealMoveTo(targetPos, cancel)
        end
        if cancel() then return done(false, "cancelled") end

        -- The Bat controller selects the nearest player server-side. Keep the
        -- selected target inside the hit radius, then swing through the exact
        -- same remote/animation path used by Auto Fight.
        pcall(function()
            if fight and fight.readyAfterRagdoll then fight.readyAfterRagdoll() end
        end)
        if fight and fight.swingBat then
            fight.swingBat(bat)
        else
            return done(false, "Bat swing API unavailable")
        end

        task.wait(0.18)
        local dropped = nil
        local deadline = os.clock() + 1.8
        while os.clock() < deadline and not cancel() do
            dropped = playerStealFindDroppedNear(targetPos, targetRow.rarity, 30)
            if dropped then break end
            task.wait(0.05)
        end
        if not dropped then
            return done(false, "no matching dropped egg detected after Bat hit")
        end

        local instant = BX.require("features.instant")
        local carryFeature = BX.require("features.carry")
        local fresh = eggsFeature.get(dropped.uid) or dropped
        local okGrab, grabInfo = instant.take(fresh.uid, fresh.pos, {
            areaId = fresh.areaId,
            nestId = fresh.nestId,
            timeout = 2.0,
            method = autoStealMethod,
            cancel = cancel,
        })
        if not okGrab then
            local why = type(grabInfo) == "table" and grabInfo.reason or grabInfo
            return done(false, "grab failed: " .. tostring(why or "unknown"))
        end
        if cancel() then return done(false, "cancelled") end

        local okDeliver, deliverInfo = carryFeature.home(fresh.uid, {
            method = autoStealMethod,
            deliverySpeed = deliverySpeeds[autoStealMethod],
            returnToBase = false,
        })
        if not okDeliver then
            local why = type(deliverInfo) == "table" and deliverInfo.reason or deliverInfo
            return done(false, "delivery failed: " .. tostring(why or "unknown"))
        end

        return done(true, string.format("stole %s • %s • %s", tostring(fresh.rarity or targetRow.rarity), tostring(fresh.name or targetRow.egg), tostring(targetPlayer.Name)))
    end

    -- Build the panel late, after all shared rarity/method controls exist.
    playerStealSection = Instance.new("Frame", scroll)
    playerStealSection.Name = "PlayerStealByRaritySection"
    playerStealSection.Size = UDim2.new(1, 0, 0, 720)
    playerStealSection.LayoutOrder = 5000
    playerStealSection.BackgroundColor3 = Color3.fromRGB(10, 11, 16)
    playerStealSection.BackgroundTransparency = 0.18
    playerStealSection.BorderSizePixel = 0
    Instance.new("UICorner", playerStealSection).CornerRadius = UDim.new(0, 12)
    local psStroke = Instance.new("UIStroke", playerStealSection)
    psStroke.Thickness = 1.8
    psStroke.Transparency = 0.12
    psStroke.Color = Color3.fromRGB(255, 70, 130)

    local psTitle = Instance.new("TextLabel", playerStealSection)
    psTitle.Size = UDim2.new(1, -18, 0, 24)
    psTitle.Position = UDim2.fromOffset(9, 8)
    psTitle.BackgroundTransparency = 1
    psTitle.Font = Enum.Font.GothamBlack
    psTitle.Text = "⚔  AUTO STEAL FROM PLAYERS BY RARITY"
    psTitle.TextColor3 = Color3.fromRGB(245, 248, 255)
    psTitle.TextSize = 12
    psTitle.TextXAlignment = Enum.TextXAlignment.Left

    local psInfo = Instance.new("TextLabel", playerStealSection)
    psInfo.Size = UDim2.new(1, -18, 0, 34)
    psInfo.Position = UDim2.fromOffset(9, 34)
    psInfo.BackgroundTransparency = 1
    psInfo.Font = Enum.Font.Gotham
    psInfo.Text = "SERVER PLAYER SCAN  •  rarity → player → Bat hit → dropped egg → instant grab → Safe Zone"
    psInfo.TextColor3 = Color3.fromRGB(155, 170, 190)
    psInfo.TextSize = 8
    psInfo.TextWrapped = true
    psInfo.TextXAlignment = Enum.TextXAlignment.Left

    local psToggle = Instance.new("TextButton", playerStealSection)
    psToggle.Size = UDim2.new(1, -18, 0, 34)
    psToggle.Position = UDim2.fromOffset(9, 73)
    psToggle.BackgroundColor3 = Color3.fromRGB(34, 37, 52)
    psToggle.BorderSizePixel = 0
    psToggle.Font = Enum.Font.GothamBold
    psToggle.Text = "AUTO STEAL FROM PLAYERS  [OFF]"
    psToggle.TextColor3 = Color3.fromRGB(235, 245, 255)
    psToggle.TextSize = 9
    Instance.new("UICorner", psToggle).CornerRadius = UDim.new(0, 8)

    local psRarityTitle = Instance.new("TextLabel", playerStealSection)
    psRarityTitle.Size = UDim2.new(1, -18, 0, 18)
    psRarityTitle.Position = UDim2.fromOffset(9, 116)
    psRarityTitle.BackgroundTransparency = 1
    psRarityTitle.Font = Enum.Font.GothamBold
    psRarityTitle.Text = "TARGET RARITY  •  AUTO-DETECT LIVE DIRECTORY"
    psRarityTitle.TextColor3 = Color3.fromRGB(135, 220, 255)
    psRarityTitle.TextSize = 9
    psRarityTitle.TextXAlignment = Enum.TextXAlignment.Left

    local psRarityFrame = Instance.new("Frame", playerStealSection)
    psRarityFrame.Size = UDim2.new(1, -18, 0, 120)
    psRarityFrame.Position = UDim2.fromOffset(9, 137)
    psRarityFrame.BackgroundTransparency = 1
    local psGrid = Instance.new("UIGridLayout", psRarityFrame)
    psGrid.CellSize = UDim2.new(1/3, -6, 0, 28)
    psGrid.CellPadding = UDim2.fromOffset(6, 6)
    psGrid.SortOrder = Enum.SortOrder.LayoutOrder

    local psRarityButtons = {}
    local function rebuildPlayerRarityButtons()
        for _, b in pairs(psRarityButtons) do pcall(function() b:Destroy() end) end
        psRarityButtons = {}
        for index, key in ipairs(rarityOrder or {}) do
            local b = Instance.new("TextButton", psRarityFrame)
            b.LayoutOrder = index
            b.Text = (playerStealSelected[key] and "✓ " or "○ ") .. tostring(key)
            b.Font = Enum.Font.GothamBold
            b.TextSize = 8
            b.BackgroundColor3 = playerStealSelected[key] and Color3.fromRGB(0, 105, 145) or Color3.fromRGB(23, 28, 38)
            b.TextColor3 = playerStealSelected[key] and Color3.fromRGB(240, 252, 255) or (rarityColors[key] or Color3.fromRGB(170, 182, 198))
            b.BorderSizePixel = 0
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
            b.Activated:Connect(function()
                playerStealSelected[key] = not playerStealSelected[key]
                rebuildPlayerRarityButtons()
            end)
            psRarityButtons[key] = b
        end
    end
    rebuildPlayerRarityButtons()

    local psSearch = Instance.new("TextBox", playerStealSection)
    psSearch.Size = UDim2.new(1, -18, 0, 30)
    psSearch.Position = UDim2.fromOffset(9, 264)
    psSearch.BackgroundColor3 = Color3.fromRGB(16, 18, 27)
    psSearch.BackgroundTransparency = 0.08
    psSearch.BorderSizePixel = 0
    psSearch.ClearTextOnFocus = false
    psSearch.Font = Enum.Font.Gotham
    psSearch.PlaceholderText = "Search player / egg / pet / rarity..."
    psSearch.Text = ""
    psSearch.TextColor3 = Color3.fromRGB(240, 245, 255)
    psSearch.TextSize = 9
    psSearch.TextXAlignment = Enum.TextXAlignment.Left
    local psPad = Instance.new("UIPadding", psSearch)
    psPad.PaddingLeft = UDim.new(0, 10)
    psPad.PaddingRight = UDim.new(0, 10)
    Instance.new("UICorner", psSearch).CornerRadius = UDim.new(0, 8)

    local psList = Instance.new("ScrollingFrame", playerStealSection)
    psList.Size = UDim2.new(1, -18, 0, 350)
    psList.Position = UDim2.fromOffset(9, 302)
    psList.BackgroundColor3 = Color3.fromRGB(9, 11, 17)
    psList.BackgroundTransparency = 0.06
    psList.BorderSizePixel = 0
    psList.ScrollBarThickness = 7
    psList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    psList.CanvasSize = UDim2.fromOffset(0, 0)
    Instance.new("UICorner", psList).CornerRadius = UDim.new(0, 9)
    local psListLayout = Instance.new("UIListLayout", psList)
    psListLayout.Padding = UDim.new(0, 5)
    psListLayout.SortOrder = Enum.SortOrder.LayoutOrder
    local psListPad = Instance.new("UIPadding", psList)
    psListPad.PaddingTop = UDim.new(0, 6)
    psListPad.PaddingLeft = UDim.new(0, 6)
    psListPad.PaddingRight = UDim.new(0, 6)
    psListPad.PaddingBottom = UDim.new(0, 6)

    local psStatus = Instance.new("TextLabel", playerStealSection)
    psStatus.Size = UDim2.new(1, -18, 0, 44)
    psStatus.Position = UDim2.fromOffset(9, 660)
    psStatus.BackgroundTransparency = 1
    psStatus.Font = Enum.Font.Gotham
    psStatus.Text = "OFF • waiting for player scan"
    psStatus.TextColor3 = Color3.fromRGB(150, 165, 185)
    psStatus.TextSize = 8
    psStatus.TextWrapped = true
    psStatus.TextXAlignment = Enum.TextXAlignment.Left
    playerStealStatus = psStatus

    local function psMatchesSearch(row)
        local q = tostring(psSearch.Text or ""):lower()
        if q == "" then return true end
        local hay = table.concat({ row.name, row.displayName, row.egg, row.pet, row.rarity }, " "):lower()
        return hay:find(q, 1, true) ~= nil
    end

    local function refreshPlayerStealList()
        if not playerStealSection or not playerStealSection.Parent then return end
        local rows = playerStealFindRows()
        for _, child in ipairs(psList:GetChildren()) do
            if child:IsA("GuiObject") then child:Destroy() end
        end
        playerStealRows = {}
        local shown = 0
        for index, row in ipairs(rows) do
            if psMatchesSearch(row) then
                shown = shown + 1
                local b = Instance.new("TextButton", psList)
                b.Size = UDim2.new(1, -2, 0, 58)
                b.LayoutOrder = index
                b.BackgroundColor3 = Color3.fromRGB(16, 20, 29)
                b.BorderSizePixel = 0
                b.Text = string.format("%s  [%s]\n%s  •  %s  •  %s  •  %.0f studs", row.displayName or row.name, row.rarity or "UNKNOWN", row.egg or "Egg ?", row.pet or "Pet ?", row.name or "", row.distance or 0)
                b.TextColor3 = Color3.fromRGB(235, 245, 255)
                b.TextSize = 8
                b.Font = Enum.Font.GothamBold
                b.TextWrapped = true
                b.TextXAlignment = Enum.TextXAlignment.Left
                Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
                local pad = Instance.new("UIPadding", b)
                pad.PaddingLeft = UDim.new(0, 8)
                pad.PaddingRight = UDim.new(0, 8)
                b.Activated:Connect(function()
                    local token = playerStealRun + 1
                    playerStealRun = token
                    task.spawn(function()
                        local ok, why = playerStealCycle(row, token)
                        if ok then
                            psStatus.Text = "SUCCESS • " .. tostring(why)
                            psStatus.TextColor3 = Color3.fromRGB(100, 235, 170)
                        else
                            psStatus.Text = "FAILED • " .. tostring(why)
                            psStatus.TextColor3 = Color3.fromRGB(255, 170, 120)
                        end
                    end)
                end)
                playerStealRows[#playerStealRows + 1] = row
            end
        end
        if shown == 0 then
            local empty = Instance.new("TextLabel", psList)
            empty.Size = UDim2.new(1, -2, 0, 52)
            empty.BackgroundTransparency = 1
            empty.Font = Enum.Font.GothamBold
            empty.Text = "NO MATCHING PLAYERS / CARRIED-EGG METADATA NOT EXPOSED"
            empty.TextColor3 = Color3.fromRGB(135, 150, 170)
            empty.TextSize = 8
            empty.TextWrapped = true
        end
        playerStealLastScan = os.clock()
        if playerStealOn then
            psStatus.Text = string.format("ON • %d matching player(s) • method=%s • scan %.0fms ago", shown, tostring(autoStealMethod), 0)
        end
    end

    psSearch:GetPropertyChangedSignal("Text"):Connect(refreshPlayerStealList)
    psToggle.Activated:Connect(function()
        if playerStealOn then
            playerStealOn = false
            playerStealRun = playerStealRun + 1
            psToggle.Text = "AUTO STEAL FROM PLAYERS  [OFF]"
            psToggle.BackgroundColor3 = Color3.fromRGB(34, 37, 52)
            psStatus.Text = "OFF • player steal stopped"
            return
        end

        local any = false
        for _, on in pairs(playerStealSelected) do if on then any = true break end end
        if not any then
            psStatus.Text = "Select at least 1 target rarity first"
            psStatus.TextColor3 = Color3.fromRGB(255, 180, 110)
            return
        end
        if autoRarityOn or autoStealOn or comboOn or betaOn then
            psStatus.Text = "Stop the other Auto Farm/Auto Steal worker first"
            psStatus.TextColor3 = Color3.fromRGB(255, 180, 110)
            return
        end
        playerStealOn = true
        playerStealRun = playerStealRun + 1
        psToggle.Text = "AUTO STEAL FROM PLAYERS  [ON]"
        psToggle.BackgroundColor3 = Color3.fromRGB(145, 35, 85)
        psStatus.Text = "ON • scanning server players..."
        showNotification("PLAYER STEAL", "Scanning room for selected carried-egg rarities", "success", 2.5)
    end)

    task.spawn(function()
        while gui and gui.Parent do
            if playerStealSection and playerStealSection.Parent then
                pcall(refreshPlayerStealList)
                if playerStealOn and not playerStealBusy then
                    local rows = playerStealFindRows()
                    if #rows > 0 then
                        local token = playerStealRun
                        local row = rows[1]
                        task.spawn(function()
                            local ok, why = playerStealCycle(row, token)
                            if ok then
                                psStatus.Text = "SUCCESS • " .. tostring(why)
                                psStatus.TextColor3 = Color3.fromRGB(100, 235, 170)
                            elseif token == playerStealRun and playerStealOn then
                                psStatus.Text = "WAIT • " .. tostring(why)
                                psStatus.TextColor3 = Color3.fromRGB(255, 205, 120)
                            end
                        end)
                    else
                        psStatus.Text = "ON • no matching player metadata found"
                        psStatus.TextColor3 = Color3.fromRGB(150, 165, 185)
                    end
                end
            end
            task.wait(0.35)
        end
    end)

    -- ======================================================================
    -- ======================================================================
-- CENTRAL GOD MODE LIFECYCLE API
-- ======================================================================
-- Coordination/state API. It intentionally does not attempt to defeat
-- server-authoritative damage or anti-cheat checks.
_G.YOKUDO_GodMode = _G.YOKUDO_GodMode or {}
local YOKUDO_GodMode = _G.YOKUDO_GodMode

function YOKUDO_GodMode.IsEnabled()
    local enabled = false
    pcall(function() enabled = guardFeature and guardFeature.isGodMode and guardFeature.isGodMode() == true end)
    if not enabled then pcall(function() enabled = dr and dr.isGodMode and dr.isGodMode() == true end) end
    return enabled
end

function YOKUDO_GodMode.Enable()
    local ok1, r1, ok2, r2 = true, true, true, true
    if guardFeature and type(guardFeature.setGodMode) == "function" then ok1, r1 = pcall(function() return guardFeature.setGodMode(true) end) end
    if dr and type(dr.setGodMode) == "function" then ok2, r2 = pcall(function() return dr.setGodMode(true) end) end
    return ok1 and ok2 and r1 ~= false and r2 ~= false
end

function YOKUDO_GodMode.Disable()
    local ok1, r1, ok2, r2 = true, true, true, true
    if guardFeature and type(guardFeature.setGodMode) == "function" then ok1, r1 = pcall(function() return guardFeature.setGodMode(false) end) end
    if dr and type(dr.setGodMode) == "function" then ok2, r2 = pcall(function() return dr.setGodMode(false) end) end
    return ok1 and ok2 and r1 ~= false and r2 ~= false
end

function YOKUDO_GodMode.Toggle()
    return YOKUDO_GodMode.IsEnabled() and YOKUDO_GodMode.Disable() or YOKUDO_GodMode.Enable()
end

function YOKUDO_GodMode.GetCharacter() return Players.LocalPlayer and Players.LocalPlayer.Character end
function YOKUDO_GodMode.GetHumanoid()
    local c = YOKUDO_GodMode.GetCharacter()
    return c and c:FindFirstChildOfClass("Humanoid") or nil
end
function YOKUDO_GodMode.GetRoot()
    local c = YOKUDO_GodMode.GetCharacter()
    return c and c:FindFirstChild("HumanoidRootPart") or nil
end

-- UNIFIED GOD MODE • MISC ONLY
    -- ======================================================================
    local unifiedGodOn = false

    local godModeSection = Instance.new("Frame", scroll)
    godModeSection.Name = "UnifiedGodModeSection"
    godModeSection.Size = UDim2.new(1, 0, 0, 188)
    godModeSection.BackgroundColor3 = Color3.fromRGB(10, 11, 16)
    godModeSection.BackgroundTransparency = 0.10
    godModeSection.BorderSizePixel = 0
    godModeSection.LayoutOrder = 9988
    Instance.new("UICorner", godModeSection).CornerRadius = UDim.new(0, 12)

    local godModeStroke = Instance.new("UIStroke", godModeSection)
    godModeStroke.Thickness = 1.5
    godModeStroke.Transparency = 0.15
    godModeStroke.Color = Color3.fromRGB(188, 67, 255)

    local godModeTitle = Instance.new("TextLabel", godModeSection)
    godModeTitle.Size = UDim2.new(1, -20, 0, 28)
    godModeTitle.Position = UDim2.fromOffset(10, 9)
    godModeTitle.BackgroundTransparency = 1
    godModeTitle.Font = Enum.Font.GothamBlack
    godModeTitle.Text = "♜  GOD MODE • ALL SYSTEMS"
    godModeTitle.TextColor3 = Color3.fromRGB(235, 210, 255)
    godModeTitle.TextSize = 14
    godModeTitle.TextXAlignment = Enum.TextXAlignment.Left

    local godModeInfo = Instance.new("TextLabel", godModeSection)
    godModeInfo.Size = UDim2.new(1, -20, 0, 45)
    godModeInfo.Position = UDim2.fromOffset(10, 39)
    godModeInfo.BackgroundTransparency = 1
    godModeInfo.Font = Enum.Font.Gotham
    godModeInfo.Text = "ONE SWITCH • PLAYER + GUARD + BAT/SPIKE + DR. SCRAMBLE\nLifecycle-safe client coordination; server damage rules remain authoritative."
    godModeInfo.TextColor3 = Color3.fromRGB(165, 185, 205)
    godModeInfo.TextSize = 9
    godModeInfo.TextWrapped = true
    godModeInfo.TextXAlignment = Enum.TextXAlignment.Left
    godModeInfo.TextYAlignment = Enum.TextYAlignment.Center

    local unifiedGodButton = Instance.new("TextButton", godModeSection)
    unifiedGodButton.Name = "UnifiedGodMode"
    unifiedGodButton.Size = UDim2.new(1, -20, 0, 42)
    unifiedGodButton.Position = UDim2.fromOffset(10, 90)
    unifiedGodButton.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
    unifiedGodButton.BorderSizePixel = 0
    unifiedGodButton.Font = Enum.Font.GothamBlack
    unifiedGodButton.Text = "♜ GOD MODE • ALL SYSTEMS  [OFF]"
    unifiedGodButton.TextColor3 = Color3.fromRGB(245, 248, 255)
    unifiedGodButton.TextSize = 11
    unifiedGodButton.ZIndex = 22
    Instance.new("UICorner", unifiedGodButton).CornerRadius = UDim.new(0, 9)

    local unifiedGodStatus = Instance.new("TextLabel", godModeSection)
    unifiedGodStatus.Size = UDim2.new(1, -20, 0, 42)
    unifiedGodStatus.Position = UDim2.fromOffset(10, 138)
    unifiedGodStatus.BackgroundTransparency = 1
    unifiedGodStatus.Font = Enum.Font.Gotham
    unifiedGodStatus.Text = "Status: OFF • Player / Guard / DR. Scramble protection disabled"
    unifiedGodStatus.TextColor3 = Color3.fromRGB(145, 165, 185)
    unifiedGodStatus.TextSize = 9
    unifiedGodStatus.TextWrapped = true
    unifiedGodStatus.TextXAlignment = Enum.TextXAlignment.Left
    unifiedGodStatus.TextYAlignment = Enum.TextYAlignment.Center

    local function readUnifiedGodState()
        local g, d = false, false
        pcall(function() g = guardFeature and type(guardFeature.isGodMode) == "function" and guardFeature.isGodMode() == true end)
        pcall(function() d = dr and type(dr.isGodMode) == "function" and dr.isGodMode() == true end)
        return g or d
    end

    local function applyUnifiedGod(on)
        on = on == true
        local guardOK, guardWhy = true, nil
        local drOK, drWhy = true, nil
        if guardFeature and type(guardFeature.setGodMode) == "function" then
            guardOK, guardWhy = pcall(function() return guardFeature.setGodMode(on) end)
            if guardOK and guardWhy == false then guardOK, guardWhy = false, "Guard protection refused" end
        end
        if dr and type(dr.setGodMode) == "function" then
            drOK, drWhy = pcall(function() return dr.setGodMode(on) end)
            if drOK and drWhy == false then drOK, drWhy = false, "DR. Scramble protection refused" end
        end
        if not guardOK or not drOK then
            if on then
                if guardOK and guardFeature and type(guardFeature.setGodMode) == "function" then pcall(function() guardFeature.setGodMode(false) end) end
                if drOK and dr and type(dr.setGodMode) == "function" then pcall(function() dr.setGodMode(false) end) end
            end
            unifiedGodOn = false
            return false, tostring(guardWhy or drWhy or "God Mode failed")
        end
        unifiedGodOn = on
        return true
    end

    local function paintUnifiedGod()
        unifiedGodOn = readUnifiedGodState()
        unifiedGodButton.Text = unifiedGodOn and "♜ GOD MODE • ALL SYSTEMS  [ON]" or "♜ GOD MODE • ALL SYSTEMS  [OFF]"
        unifiedGodButton.BackgroundColor3 = unifiedGodOn and Color3.fromRGB(0, 105, 145) or Color3.fromRGB(23, 28, 38)
        unifiedGodStatus.Text = unifiedGodOn and "Status: ON • Character lifecycle safety active" or "Status: OFF • Character lifecycle safety disabled"
        unifiedGodStatus.TextColor3 = unifiedGodOn and Color3.fromRGB(110, 235, 180) or Color3.fromRGB(145, 165, 185)
    end

    unifiedGodButton.Activated:Connect(function()
        local target = not readUnifiedGodState()
        local okGod, why = applyUnifiedGod(target)
        paintUnifiedGod()
        if not okGod then
            showNotification("GOD MODE", tostring(why or "God Mode failed"), "warn", 3)
            return
        end
        showNotification("GOD MODE", target and "ON • Character lifecycle safety enabled" or "OFF • Character lifecycle safety disabled", target and "success" or "info", 2.5)
    end)

    task.spawn(function()
        while godModeSection and godModeSection.Parent do
            pcall(paintUnifiedGod)
            task.wait(0.35)
        end
    end)

    -- ======================================================================
    -- THE RIFT TAB
    -- Live quest requirements + REAL backpack inventory + matching field eggs.
    -- Missing pets get a Go To Egg button that uses the same movement engine as
    -- Auto Farm. The Add/Fuse button is manual and requires a second click so
    -- three pets cannot be consumed accidentally.
    -- ======================================================================
    local riftFeature = nil
    pcall(function() riftFeature = BX.require("features.rift") end)

    local riftSection = Instance.new("Frame", scroll)
    riftSection.Name = "RiftQuestSection"
    riftSection.Size = UDim2.new(1, 0, 0, 760)
    riftSection.BackgroundColor3 = Color3.fromRGB(18, 20, 22)
    riftSection.BackgroundTransparency = 0.08
    riftSection.BorderSizePixel = 0
    riftSection.LayoutOrder = 9988
    riftSection.Visible = true
    Instance.new("UICorner", riftSection).CornerRadius = UDim.new(0, 12)
    local riftStroke = Instance.new("UIStroke", riftSection)
    riftStroke.Thickness = 1
    riftStroke.Transparency = 0.78
    riftStroke.Color = Color3.fromRGB(112, 150, 65)

    local riftTitle = Instance.new("TextLabel", riftSection)
    riftTitle.Size = UDim2.new(1, -20, 0, 26)
    riftTitle.Position = UDim2.fromOffset(10, 8)
    riftTitle.BackgroundTransparency = 1
    riftTitle.Font = Enum.Font.GothamBlack
    riftTitle.Text = "✦  THE RIFT • QUESTS + BACKPACK"
    riftTitle.TextColor3 = Color3.fromRGB(236, 239, 241)
    riftTitle.TextSize = 13
    riftTitle.TextXAlignment = Enum.TextXAlignment.Left

    local riftStatus = Instance.new("TextLabel", riftSection)
    riftStatus.Size = UDim2.new(1, -20, 0, 30)
    riftStatus.Position = UDim2.fromOffset(10, 36)
    riftStatus.BackgroundColor3 = Color3.fromRGB(29, 31, 33)
    riftStatus.BackgroundTransparency = 0.18
    riftStatus.BorderSizePixel = 0
    riftStatus.Font = Enum.Font.GothamBold
    riftStatus.Text = "Rift: Reading..."
    riftStatus.TextColor3 = Color3.fromRGB(188, 220, 235)
    riftStatus.TextSize = 9
    riftStatus.TextXAlignment = Enum.TextXAlignment.Left
    riftStatus.ZIndex = 8
    Instance.new("UICorner", riftStatus).CornerRadius = UDim.new(0, 7)
    local riftStatusPad = Instance.new("UIPadding", riftStatus)
    riftStatusPad.PaddingLeft = UDim.new(0, 9)
    riftStatusPad.PaddingRight = UDim.new(0, 8)

    local riftReqTitle = Instance.new("TextLabel", riftSection)
    riftReqTitle.Size = UDim2.new(1, -20, 0, 20)
    riftReqTitle.Position = UDim2.fromOffset(10, 72)
    riftReqTitle.BackgroundTransparency = 1
    riftReqTitle.Font = Enum.Font.GothamBlack
    riftReqTitle.Text = "QUEST REQUIREMENTS • LIVE BACKPACK STATUS"
    riftReqTitle.TextColor3 = Color3.fromRGB(170, 178, 184)
    riftReqTitle.TextSize = 9
    riftReqTitle.TextXAlignment = Enum.TextXAlignment.Left

    local riftRows = {}
    for i = 1, 3 do
        local row = Instance.new("Frame", riftSection)
        row.Name = "Requirement" .. i
        row.Size = UDim2.new(1, -20, 0, 42)
        row.Position = UDim2.fromOffset(10, 94 + ((i - 1) * 46))
        row.BackgroundColor3 = Color3.fromRGB(29, 31, 33)
        row.BackgroundTransparency = 0.12
        row.BorderSizePixel = 0
        row.ZIndex = 7
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

        local num = Instance.new("TextLabel", row)
        num.Size = UDim2.fromOffset(28, 42)
        num.BackgroundTransparency = 1
        num.Font = Enum.Font.GothamBlack
        num.Text = tostring(i)
        num.TextColor3 = Color3.fromRGB(120, 220, 160)
        num.TextSize = 11
        num.ZIndex = 8

        local name = Instance.new("TextLabel", row)
        name.Name = "PetName"
        name.Size = UDim2.new(1, -180, 1, 0)
        name.Position = UDim2.fromOffset(32, 0)
        name.BackgroundTransparency = 1
        name.Font = Enum.Font.GothamBold
        name.Text = "Waiting for Rift..."
        name.TextColor3 = Color3.fromRGB(235, 238, 240)
        name.TextSize = 10
        name.TextXAlignment = Enum.TextXAlignment.Left
        name.TextTruncate = Enum.TextTruncate.AtEnd
        name.ZIndex = 8

        local inv = Instance.new("TextLabel", row)
        inv.Name = "InventoryCount"
        inv.Size = UDim2.fromOffset(105, 30)
        inv.Position = UDim2.new(1, -155, 0.5, -15)
        inv.BackgroundTransparency = 1
        inv.Font = Enum.Font.GothamBold
        inv.Text = "BACKPACK —"
        inv.TextColor3 = Color3.fromRGB(170, 185, 194)
        inv.TextSize = 8
        inv.TextXAlignment = Enum.TextXAlignment.Right
        inv.ZIndex = 8

        local state = Instance.new("TextLabel", row)
        state.Name = "OwnedState"
        state.Size = UDim2.fromOffset(46, 30)
        state.Position = UDim2.new(1, -52, 0.5, -15)
        state.BackgroundTransparency = 1
        state.Font = Enum.Font.GothamBlack
        state.Text = "—"
        state.TextColor3 = Color3.fromRGB(145, 165, 175)
        state.TextSize = 8
        state.TextXAlignment = Enum.TextXAlignment.Right
        state.ZIndex = 8
        riftRows[i] = {row=row, name=name, state=state, inv=inv}
    end

    local riftEggTitle = Instance.new("TextLabel", riftSection)
    riftEggTitle.Size = UDim2.new(1, -20, 0, 20)
    riftEggTitle.Position = UDim2.fromOffset(10, 238)
    riftEggTitle.BackgroundTransparency = 1
    riftEggTitle.Font = Enum.Font.GothamBlack
    riftEggTitle.Text = "MISSING PETS • MATCHING EGGS ON FIELD"
    riftEggTitle.TextColor3 = Color3.fromRGB(170, 178, 184)
    riftEggTitle.TextSize = 9
    riftEggTitle.TextXAlignment = Enum.TextXAlignment.Left

    local riftEggList = Instance.new("ScrollingFrame", riftSection)
    riftEggList.Name = "MissingPetEggList"
    riftEggList.Size = UDim2.new(1, -20, 0, 150)
    riftEggList.Position = UDim2.fromOffset(10, 260)
    riftEggList.BackgroundColor3 = Color3.fromRGB(24, 26, 28)
    riftEggList.BackgroundTransparency = 0.12
    riftEggList.BorderSizePixel = 0
    riftEggList.ScrollBarThickness = 3
    riftEggList.CanvasSize = UDim2.new(0, 0, 0, 0)
    riftEggList.AutomaticCanvasSize = Enum.AutomaticSize.Y
    riftEggList.ZIndex = 7
    Instance.new("UICorner", riftEggList).CornerRadius = UDim.new(0, 8)
    local eggListPad = Instance.new("UIPadding", riftEggList)
    eggListPad.PaddingTop = UDim.new(0, 5)
    eggListPad.PaddingBottom = UDim.new(0, 5)
    eggListPad.PaddingLeft = UDim.new(0, 5)
    eggListPad.PaddingRight = UDim.new(0, 5)
    local eggListLayout = Instance.new("UIListLayout", riftEggList)
    eggListLayout.Padding = UDim.new(0, 4)
    eggListLayout.SortOrder = Enum.SortOrder.LayoutOrder

    local riftEggEmpty = Instance.new("TextLabel", riftEggList)
    riftEggEmpty.Size = UDim2.new(1, -10, 0, 32)
    riftEggEmpty.BackgroundTransparency = 1
    riftEggEmpty.Font = Enum.Font.GothamBold
    riftEggEmpty.Text = "No missing-pet egg is currently on the field."
    riftEggEmpty.TextColor3 = Color3.fromRGB(130, 140, 147)
    riftEggEmpty.TextSize = 8
    riftEggEmpty.TextXAlignment = Enum.TextXAlignment.Left
    riftEggEmpty.LayoutOrder = 1
    riftEggEmpty.ZIndex = 8

    local function clearRiftEggRows()
        for _, child in ipairs(riftEggList:GetChildren()) do
            if child ~= eggListLayout and child ~= eggListPad and child ~= riftEggEmpty then
                child:Destroy()
            end
        end
    end

    local riftBannerTitle = Instance.new("TextLabel", riftSection)
    riftBannerTitle.Size = UDim2.new(1, -20, 0, 20)
    riftBannerTitle.Position = UDim2.fromOffset(10, 420)
    riftBannerTitle.BackgroundTransparency = 1
    riftBannerTitle.Font = Enum.Font.GothamBlack
    riftBannerTitle.Text = "RIFT ROTATION / TARGET"
    riftBannerTitle.TextColor3 = Color3.fromRGB(170, 178, 184)
    riftBannerTitle.TextSize = 9
    riftBannerTitle.TextXAlignment = Enum.TextXAlignment.Left

    local riftChoice = "RiftBeasts"
    local riftChoiceButtons = {}
    local riftChoices = {"RiftBorn", "RiftBeasts", "Shattered Rift"}
    for i, label in ipairs(riftChoices) do
        local b = Instance.new("TextButton", riftSection)
        b.Name = "Select_" .. label:gsub("%s+", "")
        b.Size = UDim2.new(1/3, -7, 0, 34)
        b.Position = UDim2.new((i - 1) / 3, 10, 0, 444)
        if i > 1 then b.Position = UDim2.new((i - 1) / 3, 5, 0, 444) end
        b.BackgroundColor3 = Color3.fromRGB(36, 38, 40)
        b.BackgroundTransparency = 0.05
        b.BorderSizePixel = 0
        b.AutoButtonColor = false
        b.Font = Enum.Font.GothamBlack
        b.Text = label
        b.TextColor3 = Color3.fromRGB(205, 210, 213)
        b.TextSize = 9
        b.ZIndex = 8
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
        local bs = Instance.new("UIStroke", b)
        bs.Thickness = 1
        bs.Transparency = 0.82
        bs.Color = Color3.fromRGB(112, 150, 65)
        riftChoiceButtons[label] = {button=b, stroke=bs}
        b.Activated:Connect(function() riftChoice = label end)
    end

    local riftReroll = Instance.new("TextButton", riftSection)
    riftReroll.Name = "Reroll"
    riftReroll.Size = UDim2.new(0.49, -8, 0, 38)
    riftReroll.Position = UDim2.fromOffset(10, 484)
    riftReroll.BackgroundColor3 = Color3.fromRGB(42, 45, 47)
    riftReroll.BorderSizePixel = 0
    riftReroll.AutoButtonColor = false
    riftReroll.Font = Enum.Font.GothamBlack
    riftReroll.Text = "↻  REROLL"
    riftReroll.TextColor3 = Color3.fromRGB(235, 238, 240)
    riftReroll.TextSize = 10
    riftReroll.ZIndex = 8
    Instance.new("UICorner", riftReroll).CornerRadius = UDim.new(0, 8)

    local riftAuto = Instance.new("TextButton", riftSection)
    riftAuto.Name = "AutoReroll"
    riftAuto.Size = UDim2.new(0.51, -8, 0, 38)
    riftAuto.Position = UDim2.new(0.49, 5, 0, 484)
    riftAuto.BackgroundColor3 = Color3.fromRGB(42, 45, 47)
    riftAuto.BorderSizePixel = 0
    riftAuto.AutoButtonColor = false
    riftAuto.Font = Enum.Font.GothamBlack
    riftAuto.Text = "AUTO REROLL  [OFF]"
    riftAuto.TextColor3 = Color3.fromRGB(235, 238, 240)
    riftAuto.TextSize = 9
    riftAuto.ZIndex = 8
    Instance.new("UICorner", riftAuto).CornerRadius = UDim.new(0, 8)

    local riftFarm = Instance.new("TextButton", riftSection)
    riftFarm.Name = "AutoFarmEggByRift"
    riftFarm.Size = UDim2.new(1, -20, 0, 38)
    riftFarm.Position = UDim2.fromOffset(10, 530)
    riftFarm.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
    riftFarm.BorderSizePixel = 0
    riftFarm.AutoButtonColor = false
    riftFarm.Font = Enum.Font.GothamBlack
    riftFarm.Text = "AUTO FARM EGG BY RIFT  [OFF]"
    riftFarm.TextColor3 = Color3.fromRGB(235, 248, 255)
    riftFarm.TextSize = 9
    riftFarm.ZIndex = 8
    Instance.new("UICorner", riftFarm).CornerRadius = UDim.new(0, 8)
    local riftFarmStroke = Instance.new("UIStroke", riftFarm)
    riftFarmStroke.Thickness = 1
    riftFarmStroke.Transparency = 0.35
    riftFarmStroke.Color = Color3.fromRGB(70, 190, 230)

    local riftFarmStatus = Instance.new("TextLabel", riftSection)
    riftFarmStatus.Name = "AutoFarmEggByRiftStatus"
    riftFarmStatus.Size = UDim2.new(1, -20, 0, 18)
    riftFarmStatus.Position = UDim2.fromOffset(10, 570)
    riftFarmStatus.BackgroundTransparency = 1
    riftFarmStatus.Font = Enum.Font.Gotham
    riftFarmStatus.Text = "OFF • waits for any missing Rift requirement to appear"
    riftFarmStatus.TextColor3 = Color3.fromRGB(145, 165, 178)
    riftFarmStatus.TextSize = 8
    riftFarmStatus.TextXAlignment = Enum.TextXAlignment.Left
    riftFarmStatus.ZIndex = 8

    local riftAdd = Instance.new("TextButton", riftSection)
    riftAdd.Name = "AddPetsToRift"
    riftAdd.Size = UDim2.new(1, -20, 0, 40)
    riftAdd.Position = UDim2.fromOffset(10, 592)
    riftAdd.BackgroundColor3 = Color3.fromRGB(74, 102, 52)
    riftAdd.BorderSizePixel = 0
    riftAdd.AutoButtonColor = false
    riftAdd.Font = Enum.Font.GothamBlack
    riftAdd.Text = "＋  ADD / FUSE 3 PETS TO RIFT"
    riftAdd.TextColor3 = Color3.fromRGB(242, 250, 232)
    riftAdd.TextSize = 9
    riftAdd.ZIndex = 8
    Instance.new("UICorner", riftAdd).CornerRadius = UDim.new(0, 8)

    local riftRefresh = Instance.new("TextButton", riftSection)
    riftRefresh.Name = "RefreshRiftData"
    riftRefresh.Size = UDim2.new(1, -20, 0, 34)
    riftRefresh.Position = UDim2.fromOffset(10, 640)
    riftRefresh.BackgroundColor3 = Color3.fromRGB(31, 34, 36)
    riftRefresh.BorderSizePixel = 0
    riftRefresh.AutoButtonColor = false
    riftRefresh.Font = Enum.Font.GothamBold
    riftRefresh.Text = "↻  REFRESH RIFT + BACKPACK"
    riftRefresh.TextColor3 = Color3.fromRGB(190, 210, 218)
    riftRefresh.TextSize = 9
    riftRefresh.ZIndex = 8
    Instance.new("UICorner", riftRefresh).CornerRadius = UDim.new(0, 7)

    local riftBottom = Instance.new("TextLabel", riftSection)
    riftBottom.Size = UDim2.new(1, -20, 0, 70)
    riftBottom.Position = UDim2.fromOffset(10, 682)
    riftBottom.BackgroundTransparency = 1
    riftBottom.Font = Enum.Font.Gotham
    riftBottom.Text = "BACKPACK = live Save.Inventory • Rift Farm reads Requirements directly.\nAUTO FARM BY RIFT = steals only eggs whose Category matches a missing Rift pet.\nGO TO EGG uses the same movement engine as Auto Farm. ADD/FUSE remains manual with confirmation."
    riftBottom.TextColor3 = Color3.fromRGB(125, 135, 142)
    riftBottom.TextSize = 8
    riftBottom.TextWrapped = true
    riftBottom.TextXAlignment = Enum.TextXAlignment.Left
    riftBottom.ZIndex = 8

    local riftAutoOn = false
    local riftFarmOn = false
    local riftFuseArmed = false
    local riftFuseArmAt = 0
    local riftEggFingerprint = nil

    -- REAL-TIME EGG WATCHER (event-driven, NOT Heartbeat/RenderStepped).
    -- EggState exposes replication events; use those as the source of truth
    -- and repaint only when the field actually changes. A tiny 30ms coalescer
    -- absorbs burst events without tying the Rift UI to the Android frame rate.
    local riftEggPaintPending = false
    local riftEggWatchScope = BX.scope("ui.rift.eggwatch")
    local paintRiftUI
    local scheduleRiftAutoReroll

    local function queueRiftEggPaint(reason)
        if riftEggPaintPending then return end
        riftEggPaintPending = true
        task.delay(0.03, function()
            riftEggPaintPending = false
            if not (riftSection and riftSection.Parent) then return end
            -- Drop the egg cache only after an actual replication event. The
            -- next eggsForPet() call performs one fresh in-memory read; there
            -- is no frame loop and no periodic workspace scan here.
            pcall(function()
                local eggFeature = BX.require("features.eggs")
                if eggFeature.invalidate then eggFeature.invalidate(reason or "Rift UI egg event") end
            end)
            pcall(paintRiftUI)
        end)
    end

    local function riftBannerMatches(actual, wanted)
        local a = tostring(actual or ""):lower():gsub("[^%w]+", "")
        local w = tostring(wanted or ""):lower():gsub("[^%w]+", "")
        if a == w then return true end
        if w == "riftborn" then return a:find("riftborn", 1, true) ~= nil end
        if w == "riftbeasts" then return a:find("riftbeast", 1, true) ~= nil end
        if w == "shatteredrift" then return a:find("shatteredrift", 1, true) ~= nil end
        return false
    end

    local function addRiftEggRow(petId, egg, order)
        local row = Instance.new("Frame", riftEggList)
        row.Name = "Egg_" .. tostring(egg.uid)
        row.Size = UDim2.new(1, -10, 0, 42)
        row.BackgroundColor3 = Color3.fromRGB(31, 34, 36)
        row.BackgroundTransparency = 0.08
        row.BorderSizePixel = 0
        row.LayoutOrder = order
        row.ZIndex = 8
        Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

        local name = Instance.new("TextLabel", row)
        name.Size = UDim2.new(1, -92, 0, 20)
        name.Position = UDim2.fromOffset(8, 3)
        name.BackgroundTransparency = 1
        name.Font = Enum.Font.GothamBold
        name.Text = (riftFeature and riftFeature.petName and riftFeature.petName(petId) or tostring(petId)) .. "  ←  " .. tostring(egg.name or "Egg")
        name.TextColor3 = Color3.fromRGB(235, 238, 240)
        name.TextSize = 8
        name.TextXAlignment = Enum.TextXAlignment.Left
        name.TextTruncate = Enum.TextTruncate.AtEnd
        name.ZIndex = 9

        local meta = Instance.new("TextLabel", row)
        meta.Size = UDim2.new(1, -92, 0, 16)
        meta.Position = UDim2.fromOffset(8, 23)
        meta.BackgroundTransparency = 1
        meta.Font = Enum.Font.Gotham
        meta.Text = string.format("%s • %.0f/s • %.1fkg • %s", tostring(egg.rarity or "?"), tonumber(egg.value) or 0, tonumber(egg.kg) or 0, tostring(egg.state or "Slot"))
        meta.TextColor3 = Color3.fromRGB(135, 165, 178)
        meta.TextSize = 7
        meta.TextXAlignment = Enum.TextXAlignment.Left
        meta.ZIndex = 9

        local go = Instance.new("TextButton", row)
        go.Size = UDim2.fromOffset(74, 32)
        go.Position = UDim2.new(1, -80, 0.5, -16)
        go.BackgroundColor3 = Color3.fromRGB(0, 105, 145)
        go.BorderSizePixel = 0
        go.AutoButtonColor = false
        go.Font = Enum.Font.GothamBlack
        go.Text = "GO TO EGG"
        go.TextColor3 = Color3.fromRGB(235, 245, 255)
        go.TextSize = 7
        go.ZIndex = 10
        Instance.new("UICorner", go).CornerRadius = UDim.new(0, 7)
        go.Activated:Connect(function()
            go.Text = "GO..."
            local ok, why = riftFeature and riftFeature.goToEgg and riftFeature.goToEgg(egg.uid)
            go.Text = ok and "ARRIVED" or "GO TO EGG"
            showNotification("THE RIFT", ok and ("Moved to " .. tostring(egg.name)) or tostring(why or "Egg unavailable"), ok and "success" or "warn", 2.2)
        end)
    end

    paintRiftUI = function()
        if not riftFeature or type(riftFeature.snapshot) ~= "function" then
            riftStatus.Text = "Rift feature unavailable"
            return
        end
        local st = riftFeature.snapshot(false)
        if type(st) ~= "table" then
            riftStatus.Text = "Rift: waiting for state..."
            return
        end

        local banner = tostring(st.BannerDisplayName or st.BannerId or "Rift")
        local reqs = type(st.Requirements) == "table" and st.Requirements or {}
        local details, have, missing
        if type(riftFeature.inventorySnapshot) == "function" then
            details, have, missing = riftFeature.inventorySnapshot(false)
        else
            have, missing = riftFeature.owned()
        end
        local missingSet = {}
        for _, id in ipairs(missing or {}) do missingSet[id] = true end
        local free = tonumber(st.FreeRefreshesRemaining) or 0
        local pity = tonumber(st.PityCount)
        local pityMax = tonumber(st.PityThreshold)
        local secs = tonumber(st.SecondsUntilRotation) or 0
        riftStatus.Text = ("%s  •  %d/%d pets  •  %ds  •  FREE %d  •  PITY %s"):format(
            banner, tonumber(have) or 0, #reqs, math.max(0, math.floor(secs)), free,
            pity and pityMax and (tostring(pity).."/"..tostring(pityMax)) or "—")

        local eggCount = 0
        local eggRows = {}
        for i = 1, 3 do
            local id = reqs[i]
            local row = riftRows[i]
            if id then
                local slot = details and details[id]
                local count = slot and slot.count or 0
                local eligible = slot and slot.eligible or 0
                row.name.Text = tostring(riftFeature.petName(id))
                row.inv.Text = string.format("BACKPACK %d • USE %d", count, eligible)
                if missingSet[id] then
                    row.state.Text = "MISS"
                    row.state.TextColor3 = Color3.fromRGB(255, 145, 125)
                    local matches = riftFeature.eggsForPet and riftFeature.eggsForPet(id) or {}
                    for _, egg in ipairs(matches) do
                        if eggCount < 8 then
                            eggCount = eggCount + 1
                            eggRows[#eggRows + 1] = {id = id, egg = egg}
                        end
                    end
                else
                    row.state.Text = "READY"
                    row.state.TextColor3 = Color3.fromRGB(105, 235, 165)
                end
            else
                row.name.Text = "No requirement"
                row.inv.Text = "BACKPACK —"
                row.state.Text = "—"
                row.state.TextColor3 = Color3.fromRGB(145, 165, 175)
            end
        end

        local fpParts = {}
        for _, item in ipairs(eggRows) do
            fpParts[#fpParts + 1] = tostring(item.id) .. ":" .. tostring(item.egg.uid)
        end
        local eggFp = table.concat(fpParts, "|")
        if eggFp ~= riftEggFingerprint then
            riftEggFingerprint = eggFp
            clearRiftEggRows()
            for i, item in ipairs(eggRows) do addRiftEggRow(item.id, item.egg, i) end
        end
        riftEggEmpty.Visible = #eggRows == 0
        riftEggEmpty.LayoutOrder = 1

        for label, ref in pairs(riftChoiceButtons) do
            local on = label == riftChoice
            ref.button.BackgroundColor3 = on and Color3.fromRGB(72, 98, 52) or Color3.fromRGB(36, 38, 40)
            ref.stroke.Transparency = on and 0.25 or 0.82
            ref.button.TextColor3 = on and Color3.fromRGB(245, 255, 232) or Color3.fromRGB(205, 210, 213)
        end
        riftReroll.Text = ("↻  REROLL  •  %d FREE"):format(free)
        riftAuto.Text = riftAutoOn and ("AUTO REROLL  [%s]  ON"):format(riftChoice) or "AUTO REROLL  [OFF]"
        riftAuto.BackgroundColor3 = riftAutoOn and Color3.fromRGB(72, 98, 52) or Color3.fromRGB(42, 45, 47)
        if riftFarmOn then
            local reqCount = #reqs
            local missCount = #(missing or {})
            riftFarm.Text = "AUTO FARM EGG BY RIFT  [ON]"
            riftFarm.BackgroundColor3 = Color3.fromRGB(0, 105, 145)
            riftFarmStatus.Text = (missCount > 0)
                and ("ON • LIVE RIFT FILTER • " .. tostring(missCount) .. "/" .. tostring(reqCount) .. " requirements missing")
                or "ON • ALL RIFT PETS OWNED • waiting for next Rift state"
            riftFarmStatus.TextColor3 = Color3.fromRGB(105, 230, 255)
        else
            riftFarm.Text = "AUTO FARM EGG BY RIFT  [OFF]"
            riftFarm.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
            riftFarmStatus.Text = "OFF • waits for any missing Rift requirement to appear"
            riftFarmStatus.TextColor3 = Color3.fromRGB(145, 165, 178)
        end

        local preview = riftFeature.tradePreview and riftFeature.tradePreview() or nil
        local tradeReady = true
        if not preview then tradeReady = false end
        if preview then
            for _, slot in ipairs(preview) do if not slot.ready then tradeReady = false break end end
        end
        if riftFuseArmed and os.clock() - riftFuseArmAt < 4 and tradeReady then
            riftAdd.Text = "⚠  CONFIRM ADD / FUSE 3 PETS"
            riftAdd.BackgroundColor3 = Color3.fromRGB(135, 82, 42)
        else
            riftFuseArmed = false
            riftAdd.Text = tradeReady and "＋  ADD / FUSE 3 PETS TO RIFT" or "＋  RIFT NEEDS 3 ELIGIBLE PETS"
            riftAdd.BackgroundColor3 = tradeReady and Color3.fromRGB(74, 102, 52) or Color3.fromRGB(55, 58, 60)
        end
    end

    local function stopRiftFarm(reason, silent)
        if not riftFarmOn then return end
        riftFarmOn = false
        pcall(function() auto.setEnabled(false, "rift") end)
        setAllAutoFarmInstantGrab(false)
        riftFarm.Text = "AUTO FARM EGG BY RIFT  [OFF]"
        riftFarm.BackgroundColor3 = Color3.fromRGB(23, 28, 38)
        riftFarmStatus.Text = reason or "OFF • Rift Farm stopped"
        riftFarmStatus.TextColor3 = Color3.fromRGB(145, 165, 178)
        if not silent then
            showNotification("THE RIFT", reason or "Auto Farm Egg by Rift stopped", "info", 2.2)
        end
    end

    riftFarm.Activated:Connect(function()
        if riftFarmOn then
            stopRiftFarm("OFF • Rift Farm stopped", false)
            return
        end
        if autoRarityOn or autoStealOn or comboOn or betaOn then
            showNotification("THE RIFT", "Stop another Auto Farm mode first", "warn", 2.4)
            return
        end
        if not riftFeature or type(riftFeature.pickTarget) ~= "function" then
            riftFarmStatus.Text = "RIFT MODULE ERROR • pickTarget unavailable"
            showNotification("THE RIFT", "Rift target module is unavailable", "warn", 2.6)
            return
        end
        if hold.isOn() then pcall(function() hold.setEnabled(false) end) end
        pcall(function() riftFeature.setEnabled(true) end)

        -- The Rift picker is the filter. The normal Auto Steal worker remains
        -- responsible for bait, pickup, movement and delivery, so this mode
        -- does not duplicate the expensive farm engine.
        safeAutoSetOptions("rift", {
            pick = function()
                return riftFeature.pickTarget()
            end,
            continuous = true,
            cycleDelay = 0.85,
            fastMode = true,
            method = autoStealMethod,
            deliverySpeed = deliverySpeeds[autoStealMethod],
        })
        setAllAutoFarmInstantGrab(true)
        local ok, why = auto.setEnabled(true, "rift")
        if ok == false then
            setAllAutoFarmInstantGrab(false)
            riftFarmStatus.Text = "RIFT FARM ERROR: " .. tostring(why)
            return
        end
        riftFarmOn = true
        paintRiftUI()
        showNotification("THE RIFT", "AUTO FARM BY RIFT ON • missing Rift pets only", "success", 3)
    end)

    riftReroll.Activated:Connect(function()
        if not riftFeature or type(riftFeature.reroll) ~= "function" then return end
        local ok, why = riftFeature.reroll()
        paintRiftUI()
        showNotification("THE RIFT", ok and "Reroll complete" or tostring(why or "Reroll failed"), ok and "success" or "warn", 2.4)
    end)

    riftRefresh.Activated:Connect(function()
        if riftFeature and type(riftFeature.refresh) == "function" then riftFeature.refresh("Rift tab refresh") end
        if riftFeature and type(riftFeature.inventorySnapshot) == "function" then riftFeature.inventorySnapshot(true) end
        task.defer(paintRiftUI)
    end)

    riftAdd.Activated:Connect(function()
        if not riftFeature or type(riftFeature.tradePreview) ~= "function" or type(riftFeature.tradeNow) ~= "function" then return end
        local preview = riftFeature.tradePreview()
        if not preview then
            showNotification("THE RIFT", "Three eligible pets are not ready.", "warn", 2.4)
            return
        end
        for _, slot in ipairs(preview) do
            if not slot.ready then
                showNotification("THE RIFT", "Missing eligible pet: " .. tostring(slot.name), "warn", 2.4)
                return
            end
        end
        if not riftFuseArmed or os.clock() - riftFuseArmAt >= 4 then
            riftFuseArmed = true
            riftFuseArmAt = os.clock()
            paintRiftUI()
            showNotification("THE RIFT", "Tap ADD/FUSE again within 4s to submit the 3 pets.", "warn", 3)
            return
        end
        riftFuseArmed = false
        local ok, why = riftFeature.tradeNow()
        paintRiftUI()
        showNotification("THE RIFT", ok and "Pets submitted • Rift reward flow started" or tostring(why or "Rift trade failed"), ok and "success" or "warn", 3)
    end)

    riftAuto.Activated:Connect(function()
        riftAutoOn = not riftAutoOn
        paintRiftUI()
        if riftAutoOn then scheduleRiftAutoReroll() end
    end)

    if riftFeature then
        pcall(function() riftFeature.setEnabled(true) end)
        pcall(function()
            riftFeature.onChange(function()
                -- Rift state/inventory changes are already event-driven inside
                -- features.rift; only repaint when that feature tells us it
                -- changed. No polling timer is needed for the egg list.
                task.defer(paintRiftUI)
            end)
        end)
        pcall(function()
            riftFeature.onTrade(function() task.defer(paintRiftUI) end)
        end)
    end

    -- Subscribe directly to the game's replicated EggState events. This is
    -- what makes the missing-pet egg list genuinely live: spawn, despawn,
    -- shift, carry and snapshot events trigger a refresh immediately.
    pcall(function()
        local eggState = BX.require("core.data").eggState()
        if eggState then
            local watch = {
                "FieldRefreshed",
                "FieldGone",
                "FieldShifted",
                "CarryChanged",
                "FieldClaimed",
                "SnapshotRefreshed",
            }
            for _, eventName in ipairs(watch) do
                local sig = eggState[eventName]
                if sig and type(sig) == "table" and type(sig.Connect) == "function" then
                    riftEggWatchScope:connect(sig, function()
                        queueRiftEggPaint("EggState." .. eventName)
                    end)
                end
            end
        end
    end)

    -- Auto-Reroll is a separate action worker. It is intentionally not used
    -- to drive the egg UI, so the Android client does not repaint the list
    -- every 0.75s just because Auto-Reroll is enabled.
    local function runRiftAutoReroll()
        if not riftAutoOn or not riftFeature or type(riftFeature.snapshot) ~= "function" then
            return
        end
        local st = riftFeature.snapshot(false)
        local free = st and tonumber(st.FreeRefreshesRemaining) or 0
        local banner = st and (st.BannerDisplayName or st.BannerId) or nil
        if free <= 0 then
            riftAutoOn = false
            task.defer(paintRiftUI)
            return
        end
        if banner and not riftBannerMatches(banner, riftChoice) then
            local ok = riftFeature.reroll()
            if not ok then riftAutoOn = false end
        end
    end

    scheduleRiftAutoReroll = function()
        if not riftAutoOn or not (riftSection and riftSection.Parent) then return end
        task.delay(0.75, function()
            if not (riftSection and riftSection.Parent) then return end
            runRiftAutoReroll()
            if riftAutoOn then scheduleRiftAutoReroll() end
        end)
    end

    -- Initial paint only. From here onward the egg list is event-driven.
    pcall(paintRiftUI)

    -- ======================================================================
    -- REAL TAB SYSTEM
    -- ======================================================================
    -- The original menu used one giant ScrollingFrame and only jumped the
    -- scrollbar.  That made unrelated features remain visible together.
    -- Here we classify the existing controls once, then show exactly one
    -- category at a time.  Feature callbacks/engines are NOT recreated, so
    -- their existing state and connections stay intact.

    local tabItems = {
        OVERVIEW = {},
        FARM = {},
        BOSS = {},
        GUARD = {},
        PLAYER_STEAL = {},
        RIFT = {},
        MISC = {},
        SETTINGS = {},
    }

    local tabOrder = {}
    local function tabAdd(tab, obj, order)
        if obj and obj:IsA("GuiObject") then
            local list = tabItems[tab]
            list[#list + 1] = obj
            tabOrder[obj] = order or (#list * 10)
            obj.LayoutOrder = tabOrder[obj]
        end
    end

    -- Header/status + hero belong only to Overview.
    tabAdd("OVERVIEW", notice, 100)
    tabAdd("OVERVIEW", hero, 200)

    local farmStart = sectionRefs["AUTO_FARM"]
    local bossStart = sectionRefs["ABYSS_OVERLORD"]
    local children = scroll:GetChildren()
    local farmIndex, bossIndex, autoIndex, drIndex, guardIndex = nil, nil, nil, nil, nil

    for i, child in ipairs(children) do
        if child == farmStart then farmIndex = i end
        if child == bossStart then bossIndex = i end
        if child == autoSection then autoIndex = i end
        if child == drSection then drIndex = i end
        if child == rgSection then guardIndex = i end
    end

    -- Auto Farm, Performance and Auto Steal are one FARM page.
    if farmIndex and bossIndex then
        for i = farmIndex, math.max(farmIndex, bossIndex - 1) do
            local child = children[i]
            if child and child ~= drSection and child ~= rgSection then
                tabAdd("FARM", child, i)
            end
        end
    end
    tabAdd("FARM", autoSection, 9000)

    -- Boss controls are the block from ABYSS OVERLORD until Auto Steal.
    if bossIndex and autoIndex then
        for i = bossIndex, math.max(bossIndex, autoIndex - 1) do
            local child = children[i]
            if child and child ~= autoSection then
                tabAdd("BOSS", child, i)
            end
        end
    end
    -- DR. Scramble is deliberately part of the Boss tab.
    tabAdd("BOSS", drSection, 9000)

    -- Ride Guard gets its own Guard tab.
    tabAdd("GUARD", rgSection, 100)

    -- Player Steal gets a dedicated tab.
    tabAdd("PLAYER_STEAL", playerStealSection, 100)

    -- The Rift gets its own page so its quest requirements never mix with
    -- Farm/Boss controls.
    tabAdd("RIFT", riftSection, 100)

    -- ======================================================================
    -- MISC SAFETY TOOLS
    -- ======================================================================
    -- Anti-Trap is reversible: original collision/touch properties are cached
    -- and restored when switched OFF.
    local antiTrapOn = false
    local antiTrapCache = {}
    local antiTrapToken = 0

    local antiTrapSection = Instance.new("Frame", scroll)
    antiTrapSection.Name = "AntiTrapSection"
    antiTrapSection.Size = UDim2.new(1, 0, 0, 112)
    antiTrapSection.BackgroundColor3 = Color3.fromRGB(10, 11, 16)
    antiTrapSection.BackgroundTransparency = 0.10
    antiTrapSection.BorderSizePixel = 0
    antiTrapSection.LayoutOrder = 9986
    Instance.new("UICorner", antiTrapSection).CornerRadius = UDim.new(0, 10)

    local antiTrapTitle = Instance.new("TextLabel", antiTrapSection)
    antiTrapTitle.Size = UDim2.new(1, -20, 0, 24)
    antiTrapTitle.Position = UDim2.fromOffset(10, 8)
    antiTrapTitle.BackgroundTransparency = 1
    antiTrapTitle.Font = Enum.Font.GothamBlack
    antiTrapTitle.Text = "⚠  ANTI-TRAP"
    antiTrapTitle.TextColor3 = Color3.fromRGB(235, 240, 245)
    antiTrapTitle.TextSize = 12
    antiTrapTitle.TextXAlignment = Enum.TextXAlignment.Left

    local antiTrapInfo = Instance.new("TextLabel", antiTrapSection)
    antiTrapInfo.Size = UDim2.new(1, -20, 0, 26)
    antiTrapInfo.Position = UDim2.fromOffset(10, 31)
    antiTrapInfo.BackgroundTransparency = 1
    antiTrapInfo.Font = Enum.Font.Gotham
    antiTrapInfo.Text = "Disables touch/collision on detected trap models.\nReversible when OFF."
    antiTrapInfo.TextColor3 = Color3.fromRGB(150, 160, 168)
    antiTrapInfo.TextSize = 8
    antiTrapInfo.TextWrapped = true
    antiTrapInfo.TextXAlignment = Enum.TextXAlignment.Left

    local antiTrapButton = Instance.new("TextButton", antiTrapSection)
    antiTrapButton.Size = UDim2.new(1, -20, 0, 38)
    antiTrapButton.Position = UDim2.fromOffset(10, 65)
    antiTrapButton.BackgroundColor3 = Color3.fromRGB(30, 33, 35)
    antiTrapButton.BorderSizePixel = 0
    antiTrapButton.AutoButtonColor = false
    antiTrapButton.Font = Enum.Font.GothamBlack
    antiTrapButton.Text = "⚠ ANTI-TRAP  [OFF]"
    antiTrapButton.TextColor3 = Color3.fromRGB(235, 238, 240)
    antiTrapButton.TextSize = 10
    Instance.new("UICorner", antiTrapButton).CornerRadius = UDim.new(0, 8)

    local function antiTrapMatches(model)
        if not model or not model:IsA("Model") then return false end
        if model:FindFirstChild("UnplacePrompt") then return true end
        local lower = model.Name:lower()
        return lower:find("trap", 1, true) ~= nil
            or lower:find("cage", 1, true) ~= nil
            or lower:find("snare", 1, true) ~= nil
    end

    local function antiTrapScan()
        local roots = {}
        local debris = workspace:FindFirstChild("__DEBRIS")
        if debris then roots[#roots + 1] = debris end
        roots[#roots + 1] = workspace
        for _, root in ipairs(roots) do
            for _, child in ipairs(root:GetChildren()) do
                if antiTrapMatches(child) then
                    for _, d in ipairs(child:GetDescendants()) do
                        if d:IsA("BasePart") then
                            if antiTrapCache[d] == nil then
                                antiTrapCache[d] = {CanTouch=d.CanTouch, CanCollide=d.CanCollide}
                            end
                            pcall(function() d.CanTouch = false end)
                            pcall(function() d.CanCollide = false end)
                        end
                    end
                end
            end
        end
    end

    local function antiTrapRestore()
        for part, props in pairs(antiTrapCache) do
            if part and part.Parent and props then
                pcall(function() part.CanTouch = props.CanTouch end)
                pcall(function() part.CanCollide = props.CanCollide end)
            end
        end
        table.clear(antiTrapCache)
    end

    local function setAntiTrap(on)
        antiTrapOn = on == true
        antiTrapToken = antiTrapToken + 1
        local token = antiTrapToken
        if antiTrapOn then
            antiTrapScan()
            task.spawn(function()
                while antiTrapOn and token == antiTrapToken do
                    pcall(antiTrapScan)
                    task.wait(0.75)
                end
            end)
        else
            antiTrapRestore()
        end
        antiTrapButton.Text = antiTrapOn and "⚠ ANTI-TRAP  [ON]" or "⚠ ANTI-TRAP  [OFF]"
        antiTrapButton.BackgroundColor3 = antiTrapOn and Color3.fromRGB(68, 105, 48) or Color3.fromRGB(30, 33, 35)
    end

    antiTrapButton.Activated:Connect(function() setAntiTrap(not antiTrapOn) end)

    -- The supplied Humanoid replacement is intended to evade an anti-cheat
    -- detector. This build deliberately does not install that bypass. Instead
    -- expose a clearly labeled safety switch that only records the user's
    -- preference; it does not alter or replace Humanoids.
    local antiCheatOn = false
    local antiCheatSection = Instance.new("Frame", scroll)
    antiCheatSection.Name = "AntiCheatSection"
    antiCheatSection.Size = UDim2.new(1, 0, 0, 112)
    antiCheatSection.BackgroundColor3 = Color3.fromRGB(10, 11, 16)
    antiCheatSection.BackgroundTransparency = 0.10
    antiCheatSection.BorderSizePixel = 0
    antiCheatSection.LayoutOrder = 9987
    Instance.new("UICorner", antiCheatSection).CornerRadius = UDim.new(0, 10)

    local antiCheatTitle = Instance.new("TextLabel", antiCheatSection)
    antiCheatTitle.Size = UDim2.new(1, -20, 0, 24)
    antiCheatTitle.Position = UDim2.fromOffset(10, 8)
    antiCheatTitle.BackgroundTransparency = 1
    antiCheatTitle.Font = Enum.Font.GothamBlack
    antiCheatTitle.Text = "🛡  ANTI-CHEAT SAFETY"
    antiCheatTitle.TextColor3 = Color3.fromRGB(235, 240, 245)
    antiCheatTitle.TextSize = 12
    antiCheatTitle.TextXAlignment = Enum.TextXAlignment.Left

    local antiCheatInfo = Instance.new("TextLabel", antiCheatSection)
    antiCheatInfo.Size = UDim2.new(1, -20, 0, 26)
    antiCheatInfo.Position = UDim2.fromOffset(10, 31)
    antiCheatInfo.BackgroundTransparency = 1
    antiCheatInfo.Font = Enum.Font.Gotham
    antiCheatInfo.Text = "Safety preference only • does not replace or modify Humanoids."
    antiCheatInfo.TextColor3 = Color3.fromRGB(150, 160, 168)
    antiCheatInfo.TextSize = 8
    antiCheatInfo.TextWrapped = true
    antiCheatInfo.TextXAlignment = Enum.TextXAlignment.Left

    local antiCheatButton = Instance.new("TextButton", antiCheatSection)
    antiCheatButton.Size = UDim2.new(1, -20, 0, 38)
    antiCheatButton.Position = UDim2.fromOffset(10, 65)
    antiCheatButton.BackgroundColor3 = Color3.fromRGB(30, 33, 35)
    antiCheatButton.BorderSizePixel = 0
    antiCheatButton.AutoButtonColor = false
    antiCheatButton.Font = Enum.Font.GothamBlack
    antiCheatButton.Text = "🛡 ANTI-CHEAT  [OFF]"
    antiCheatButton.TextColor3 = Color3.fromRGB(235, 238, 240)
    antiCheatButton.TextSize = 10
    Instance.new("UICorner", antiCheatButton).CornerRadius = UDim.new(0, 8)
    antiCheatButton.Activated:Connect(function()
        antiCheatOn = not antiCheatOn
        antiCheatButton.Text = antiCheatOn and "🛡 ANTI-CHEAT  [ON]" or "🛡 ANTI-CHEAT  [OFF]"
        antiCheatButton.BackgroundColor3 = antiCheatOn and Color3.fromRGB(68, 105, 48) or Color3.fromRGB(30, 33, 35)
        showNotification("ANTI-CHEAT SAFETY", antiCheatOn and "Preference ON • no Humanoid bypass installed" or "Preference OFF", "info", 2.0)
    end)

    tabAdd("MISC", antiTrapSection, 100)
    tabAdd("MISC", antiCheatSection, 200)
    tabAdd("MISC", godModeSection, 300)

    -- Anything not claimed above is kept in Misc instead of being silently
    -- lost. This also makes future small utility controls safe by default.
    local claimed = {}
    for _, list in pairs(tabItems) do
        for _, obj in ipairs(list) do claimed[obj] = true end
    end
    for _, child in ipairs(children) do
        if child:IsA("GuiObject") and not claimed[child] then
            tabAdd("MISC", child)
            claimed[child] = true
        end
    end

    -- A compact Settings page. It is UI-only and does not alter feature state.
    settingsPanel = Instance.new("Frame", scroll)
    settingsPanel.Name = "SettingsTabPanel"
    settingsPanel.Size = UDim2.new(1, 0, 0, 180)
    settingsPanel.BackgroundColor3 = Color3.fromRGB(10, 16, 24)
    settingsPanel.BackgroundTransparency = 0.08
    settingsPanel.BorderSizePixel = 0
    settingsPanel.LayoutOrder = 9999
    Instance.new("UICorner", settingsPanel).CornerRadius = UDim.new(0, 12)

    settingsTitle = Instance.new("TextLabel", settingsPanel)
    settingsTitle.Size = UDim2.new(1, -20, 0, 28)
    settingsTitle.Position = UDim2.fromOffset(10, 10)
    settingsTitle.BackgroundTransparency = 1
    settingsTitle.Font = Enum.Font.GothamBlack
    settingsTitle.Text = "⚙  HUB SETTINGS"
    settingsTitle.TextColor3 = Color3.fromRGB(211, 93, 255)
    settingsTitle.TextSize = 14
    settingsTitle.TextXAlignment = Enum.TextXAlignment.Left

    settingsInfo = Instance.new("TextLabel", settingsPanel)
    settingsInfo.Size = UDim2.new(1, -20, 0, 86)
    settingsInfo.Position = UDim2.fromOffset(10, 45)
    settingsInfo.BackgroundColor3 = Color3.fromRGB(13, 8, 21)
    settingsInfo.BackgroundTransparency = 0.1
    settingsInfo.BorderSizePixel = 0
    settingsInfo.Font = Enum.Font.Gotham
    settingsInfo.Text = "LOCK  •  drag lock is controlled from the header\nMINIMIZE  •  use the — button in the header\nCLOSE  •  use the × button in the header\n\nFeature settings remain inside their own tabs."
    settingsInfo.TextColor3 = Color3.fromRGB(190, 215, 225)
    settingsInfo.TextSize = 10
    settingsInfo.TextWrapped = true
    settingsInfo.TextXAlignment = Enum.TextXAlignment.Left
    settingsInfo.TextYAlignment = Enum.TextYAlignment.Center
    Instance.new("UICorner", settingsInfo).CornerRadius = UDim.new(0, 9)
    local settingsPad = Instance.new("UIPadding", settingsInfo)
    settingsPad.PaddingLeft = UDim.new(0, 10)
    settingsPad.PaddingRight = UDim.new(0, 10)

    tabAdd("SETTINGS", settingsPanel, 100)

    local function paintHubTab(tab)
        activeHubTab = tab
        for key, list in pairs(tabItems) do
            local visible = key == tab
            for _, obj in ipairs(list) do
                if obj and obj.Parent then
                    obj.Visible = visible
                end
            end
        end
        resetScrollTop()

        local buttons = {
            OVERVIEW = navOverview, FARM = navFarm, BOSS = navBoss,
            GUARD = navGuard, PLAYER_STEAL = navPlayerSteal, RIFT = navRift, MISC = navMisc, SETTINGS = navSettings,
        }
        for key, b in pairs(buttons) do
            if b then
                local on = key == tab
                b.BackgroundColor3 = on and Color3.fromRGB(92, 118, 55) or Color3.fromRGB(28, 30, 32)
                b.BackgroundTransparency = on and 0.02 or 0.18
                b.TextColor3 = on and Color3.fromRGB(245, 255, 232) or Color3.fromRGB(198, 202, 205)
            end
        end
    end

    function setHubTab(tab)
        tab = tostring(tab or "OVERVIEW"):upper()
        if not tabItems[tab] then tab = "OVERVIEW" end
        paintHubTab(tab)
    end

    -- Default page: Overview.
    setHubTab("OVERVIEW")

    do
        -- Reference: dark translucent Roblox overlay with compact rows and lime active state.
        main.BackgroundColor3 = Color3.fromRGB(18, 20, 22)
        main.BackgroundTransparency = 0.16
        header.BackgroundColor3 = Color3.fromRGB(24, 26, 28)
        header.BackgroundTransparency = 0.06
        headerGradient.Enabled = false
        headerDivider.BackgroundColor3 = Color3.fromRGB(112, 150, 65)
        headerDivider.BackgroundTransparency = 0.55
        headerLine.BackgroundColor3 = Color3.fromRGB(112, 150, 65)
        headerLine.BackgroundTransparency = 0.65
        brandIcon.BackgroundColor3 = Color3.fromRGB(42, 45, 47)
        brandIconStroke.Color = Color3.fromRGB(110, 145, 62)
        brandIconStroke.Thickness = 1
        brandIconRGB.Enabled = false
        brandTitle.TextColor3 = Color3.fromRGB(236, 239, 241)
        made.TextColor3 = Color3.fromRGB(142, 154, 160)
        versionBadge.BackgroundColor3 = Color3.fromRGB(44, 46, 48)
        versionBadge.TextColor3 = Color3.fromRGB(225, 228, 230)
        premiumBadge.BackgroundColor3 = Color3.fromRGB(44, 46, 48)
        premiumBadge.TextColor3 = Color3.fromRGB(225, 228, 230)
        lockButton.BackgroundColor3 = Color3.fromRGB(38, 40, 42)
        minButton.BackgroundColor3 = Color3.fromRGB(38, 40, 42)
        closeButton.BackgroundColor3 = Color3.fromRGB(38, 40, 42)
        lockButton.TextColor3 = Color3.fromRGB(205, 210, 213)
        minButton.TextColor3 = Color3.fromRGB(205, 210, 213)
        closeButton.TextColor3 = Color3.fromRGB(205, 210, 213)
        sidebar.BackgroundColor3 = Color3.fromRGB(20, 22, 24)
        sidebar.BackgroundTransparency = 0.06
        sideStroke.Color = Color3.fromRGB(65, 68, 71)
        sidebarCaption.TextColor3 = Color3.fromRGB(145, 150, 154)
        sidebarCaption.Text = "MENU"
        contentPanel.BackgroundColor3 = Color3.fromRGB(29, 31, 33)
        contentPanel.BackgroundTransparency = 0.24
        contentStroke.Color = Color3.fromRGB(72, 75, 78)
        for _, obj in ipairs(scroll:GetChildren()) do
            if obj:IsA("TextButton") then
                obj.BackgroundColor3 = Color3.fromRGB(38, 40, 42)
                obj.BackgroundTransparency = 0.20
                obj.TextColor3 = Color3.fromRGB(232, 235, 237)
            end
        end
        if targetNotifyFrame then
            targetNotifyFrame.BackgroundColor3 = Color3.fromRGB(25, 27, 29)
            targetNotifyGradient.Enabled = false
            targetNotifyStroke.Color = Color3.fromRGB(95, 125, 55)
            targetNotifyStrokeRGB.Enabled = false
        end
        if not contentPageTitle then
            contentPageTitle = Instance.new("TextLabel", contentPanel)
            contentPageTitle.Name = "ReferencePageTitle"
            contentPageTitle.Size = UDim2.new(1, -28, 0, 28)
            contentPageTitle.Position = UDim2.fromOffset(14, 8)
            contentPageTitle.BackgroundTransparency = 1
            contentPageTitle.Font = Enum.Font.GothamBold
            contentPageTitle.Text = "Auto Farm"
            contentPageTitle.TextColor3 = Color3.fromRGB(239, 242, 244)
            contentPageTitle.TextSize = 12
            contentPageTitle.TextXAlignment = Enum.TextXAlignment.Left
            contentPageTitle.ZIndex = 30
        end
        local pageNames = {OVERVIEW="Overview", FARM="Auto Farm", BOSS="Boss", GUARD="Guard", PLAYER_STEAL="Player Steal", RIFT="The Rift", MISC="Misc", SETTINGS="Settings"}
        local oldPaint = paintHubTab
        paintHubTab = function(tab)
            oldPaint(tab)
            if contentPageTitle then contentPageTitle.Text = pageNames[tab] or "VIP DELS HUB" end
        end
        pcall(function() setHubTab(activeHubTab or "OVERVIEW") end)
    end

    -- Single-menu design: one ScreenGui, real category tabs.
    -- Layout policy: one vertical scroll container, deterministic tab order,
    -- no hidden legacy navigation buttons, and every tab opens at the top.
end
