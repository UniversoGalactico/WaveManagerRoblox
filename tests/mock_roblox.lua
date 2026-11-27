-- Lua 5.4-only mock of the example's Roblox boundary. This is NOT Studio.
-- Tests the published example verbatim with controllable time and signal order.
local W = require("WaveManagerRoblox")
local function setup(options)
    options = options or {}
    local test = {clock=0,queue={},models={},folders={},warnings={},messages={}}
    local function signal()
        local callbacks = {}
        local s = {}
        function s:Connect(fn)
            local c = {Connected=true,fn=fn}
            function c:Disconnect() self.Connected=false end
            callbacks[#callbacks+1]=c
            return c
        end
        function s:Fire(defer,...)
            local args = table.pack(...)
            local pending={}
            for _,c in ipairs(callbacks) do
                if c.Connected then pending[#pending+1]=c.fn end
            end
            for _,fn in ipairs(pending) do
                if defer then
                    test.queue[#test.queue+1]=function() fn(table.unpack(args,1,args.n)) end
                else fn(table.unpack(args,1,args.n)) end
            end
        end
        function s:count()
            local n=0
            for _,c in ipairs(callbacks) do if c.Connected then n=n+1 end end
            return n
        end
        return s
    end
    local function instance(class)
        local i={ClassName=class,Destroying=signal(),destroyed=false,destructions=0}
        function i:IsA(c) return c==self.ClassName end
        function i:Destroy()
            if self.destroyed then return end
            self.destroyed=true; self.destructions=self.destructions+1
            self.Destroying:Fire(false)
        end
        return i
    end
    local heartbeat=signal()
    local scriptObject={Parent={WaveManagerRoblox="WaveManagerRoblox"},Destroying=signal()}
    local template=instance("Model")
    function template:Clone()
        if options.badClone then return nil end
        local m=instance("Model")
        local h={Health=100,Died=signal()}
        m.humanoid=h
        function m:FindFirstChildWhichIsA(class)
            if class=="Humanoid" and not options.badHumanoid then return h end
        end
        function m:PivotTo()
            if options.badPivot then error("mock pivot failure") end
        end
        setmetatable(m,{__newindex=function(self,k,v)
            if k=="Parent" then
                if options.badParent then error("mock parent failure") end
                rawset(self,k,v)
                if options.dieOnSpawn then h.Died:Fire(false) end
            else rawset(self,k,v) end
        end})
        test.models[#test.models+1]=m
        return m
    end
    local spawn=instance("BasePart"); spawn.CFrame={}
    local world={}
    function world:WaitForChild(name) if name=="EnemySpawn" and not options.noSpawn then return spawn end end
    local storage={}
    function storage:WaitForChild(name) if name=="EnemyTemplate" and not options.noTemplate then return template end end
    local game={}
    function game:GetService(name)
        if name=="RunService" then return {Heartbeat=heartbeat} end
        if name=="ServerStorage" then return storage end
        error("Unknown service: "..name)
    end
    local env=setmetatable({
        game=game,workspace=world,script=scriptObject,
        os={clock=function() return test.clock end},
        require=function(name)
            assert(name=="WaveManagerRoblox")
            return {new=function(plan) test.match=W.new(plan); return test.match end}
        end,
        Instance={new=function(class)
            local i=instance(class)
            test.folders[#test.folders+1]=i
            return i
        end},
        warn=function(...) test.warnings[#test.warnings+1]=table.pack(...) end,
        print=function(...) test.messages[#test.messages+1]=table.pack(...) end,
    },{__index=_G})
    function test:load(path)
        return assert(loadfile(path,"t",env))()
    end
    function test:tick(dt)
        self.clock=self.clock+dt
        heartbeat:Fire(false,dt)
    end
    function test:advanceClock(dt) self.clock=self.clock+dt end
    function test:die(index,defer)
        self.models[index].humanoid.Died:Fire(defer or false)
    end
    function test:flush()
        local q=self.queue; self.queue={}
        for _,fn in ipairs(q) do fn() end
    end
    function test:destroyScript(defer) scriptObject.Destroying:Fire(defer or false) end
    function test:connections() return heartbeat:count() end
    function test:state() return self.match:getState() end
    function test:assertClean()
        assert(self:connections()==0,"heartbeat not disconnected")
        assert(scriptObject.Destroying:count()==0,"teardown connection not disconnected")
        for _,m in ipairs(self.models) do
            assert(m.destroyed,"NPC not destroyed")
            assert(m.humanoid.Died:count()==0,"death connection not disconnected")
        end
        for _,f in ipairs(self.folders) do assert(f.destroyed,"folder not destroyed") end
    end
    return test
end
local example="examples/RobloxMatch.server.lua"
local smoke="examples/StudioSmokeTest.server.lua"
local cases=0
local function case(name,fn)
    fn(); cases=cases+1; print("PASS:",name)
end
case("asset-free smoke logic",function()
    local t=setup(); t:load(smoke)
    assert(t:state().phase=="Completed")
    assert(t.messages[1][1]=="WaveManager Studio smoke test: PASS")
    t:assertClean()
end)
case("two full waves with immediate and delayed duplicate deaths",function()
    local t=setup(); t:load(example)
    t:tick(2.9); assert(#t.models==0)
    t:tick(.1); assert(#t.models==1)
    t:tick(.1); assert(#t.models==1)
    t:tick(.4); assert(#t.models==2)
    t:die(1,true); t:die(1,true); t:flush()
    assert(t:state().killedEnemies==1)
    t:tick(.4); assert(#t.models==3)
    t:die(2); t:die(3)
    assert(t:state().phase=="Intermission" and t:state().completedWaves==1)
    t:tick(6); assert(t:state().wave==2 and #t.models==4)
    for _=1,4 do t:tick(.4) end
    assert(#t.models==8)
    for i=4,8 do t:die(i,true); t:die(i,true) end
    t:flush(); assert(t:state().phase=="Completed")
    t:tick(0); t:assertClean()
end)
case("lag spike does not spawn a catch-up burst",function()
    local t=setup(); t:load(example); t:tick(3); assert(#t.models==1)
    t:tick(10); assert(#t.models==2)
    t:tick(20); assert(t:state().phase=="Failed" and t:state().reason=="timeout")
    t:assertClean()
end)
case("death before deadline wins; death at deadline loses",function()
    local a=setup(); a:load(example); a:tick(3); a:tick(.4); a:tick(.4)
    a:die(1); a:die(2); a:advanceClock(29.19); a:die(3)
    assert(a:state().phase=="Intermission")
    a:destroyScript(); a:assertClean()
    local b=setup(); b:load(example); b:tick(3); b:tick(.4); b:tick(.4)
    b:die(1); b:die(2); b:advanceClock(29.2); b:die(3)
    assert(b:state().phase=="Failed" and b:state().reason=="timeout")
    b:tick(0); b:assertClean()
end)
case("death callback queued before cancellation is harmless",function()
    local t=setup(); t:load(example); t:tick(3)
    t:die(1,true); t:destroyScript(); t:flush(); t:tick(100)
    assert(t:state().phase=="Cancelled" and t:state().killedEnemies==0)
    t:assertClean()
end)
case("immediate deaths on parenting do not race registration",function()
    local t=setup({dieOnSpawn=true}); t:load(example); t:tick(3)
    t:tick(.4); t:tick(.4)
    assert(t:state().phase=="Intermission" and t:state().killedEnemies==3)
    t:tick(6); for _=1,4 do t:tick(.4) end
    assert(t:state().phase=="Completed")
    t:tick(0); t:assertClean()
end)
for _,name in ipairs({"badClone","badHumanoid","badPivot","badParent"}) do
    case("spawn error: "..name,function()
        local t=setup({[name]=true}); t:load(example); t:tick(3)
        assert(t:state().phase=="Failed" and #t.warnings==1)
        t:tick(0); t:assertClean()
    end)
end
for _,name in ipairs({"noSpawn","noTemplate"}) do
    case("invalid setup: "..name,function()
        local t=setup({[name]=true})
        assert(not pcall(function() t:load(example) end))
        assert(t.match==nil and t:connections()==0)
    end)
end
print("MOCK ROBLOX PASS: "..cases.." integration scenarios (Lua 5.4 mocks, not Studio)")
