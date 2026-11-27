-- Generated input-boundary and defensive-copy cases, not a performance test.
local W=require(_VERSION=="Lua 5.4" and "WaveManagerRoblox" or "../WaveManagerRoblox")
local seed=7654321
local function rand(n) seed=(seed*48271)%2147483647; return seed%n+1 end
local invalidCounts={0,-1,10001,1.5,math.huge,-math.huge,0/0,"1",true,{}}
local invalidTimes={-1,86401,math.huge,-math.huge,0/0,"2",false,{}}
local validTimes={0,1e-12,.25,1,86400}
local bad=0
local good=0
for trial=1,20000 do
    local n=rand(5)
    local p={}
    for i=1,n do
        p[i]={count=rand(10000),duration=rand(86400000)/1000,
            countdown=validTimes[rand(#validTimes)],intermission=validTimes[rand(#validTimes)]}
    end
    local action=rand(16)
    local at=rand(n)
    local expected=action<=4
    if action==1 then p[at].duration=nil
    elseif action==2 then p[at].countdown=nil
    elseif action==3 then p[at].intermission=nil
    elseif action==5 then p[at].count=invalidCounts[rand(#invalidCounts)]
    elseif action==6 then p[at].duration=invalidTimes[rand(#invalidTimes)]
    elseif action==7 then p[at].countdown=invalidTimes[rand(#invalidTimes)]
    elseif action==8 then p[at].intermission=invalidTimes[rand(#invalidTimes)]
    elseif action==9 then p[n+2]=p[at]; p[at]=nil
    elseif action==10 then p.extra=true
    elseif action==11 then p[at][{}]=1
    elseif action==12 then p[at]=setmetatable(p[at],{__metatable=false})
    elseif action==13 then p[at].duration=0.000999
    elseif action==14 then p[at].count=nil
    elseif action==15 then p[at]=false
    elseif action==16 then p=setmetatable(p,{__index=function() error("unexpected external callback") end}) end
    local ok,m=pcall(W.new,p)
    assert(ok==expected,"configuration case "..action)
    if ok then
        local first=p[1]
        local count=first.count; local countdown=first.countdown or 10
        local active=first.duration or 60
        -- Mutate all caller-owned tables after construction.
        for i=1,n do p[i].count=0; p[i].duration=0; p[i].countdown=0; p[i]=nil end
        assert(m:start()); local s=m:getState()
        assert(s.waveCount==n and s.totalEnemies==count)
        if countdown>0 then assert(s.phase=="Countdown" and s.timeLeft==countdown); assert(m:step(countdown)) end
        s=m:getState(); assert(s.phase=="Active" and math.abs(s.timeLeft-active)<1e-9)
        good=good+1
    else bad=bad+1 end
end
print("CONFIGURATION PASS: "..good.." valid copied plans; "..bad.." malformed plans rejected")
