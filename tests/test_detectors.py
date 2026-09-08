"""Behavioral Lua regression tests. Run: python tests/test_detectors.py"""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parent / "review-runtime"))
from lupa.lua51 import LuaRuntime


class DetectorTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            print = function() end
            g_time = 1000
            currentFarm = 1
            g_currentMission = {getFarmId=function() return currentFarm end, vehicles={}}
            g_i18n = {getText=function(_, key) return key end}
            MessageType = {AI_JOB_STARTED=1, AI_JOB_STOPPED=2}
            g_messageCenter = {subscriptions=0, removals=0,
                subscribe=function(self) self.subscriptions=self.subscriptions+1 end,
                unsubscribeAll=function(self) self.removals=self.removals+1 end}
            FillType = {DIESEL=1}
            FruitType = {UNKNOWN=0}
            AIMessageSuccessFinishedJob = {}
            AIMessageType = {ERROR=2}
            success = {isa=function() return true end}
            for _, kind in ipairs({'String', 'Int', 'Float', 'Bool'}) do
                _G['setXML' .. kind] = function(xml, key, value) xml[key]=value end
                _G['getXML' .. kind] = function(xml, key) return xml[key] end
            end
            function vehicle(id)
                return {uniqueId=id, fuel=0.1,
                    getOwnerFarmId=function() return 1 end,
                    getFullName=function() return 'Tractor' end,
                    getConsumerFillUnitIndex=function() return 1 end,
                    getFillUnitFillLevelPercentage=function(self) return self.fuel end}
            end
            function silo(id)
                local storage={capacity=100, level=100, supportsMultipleFillTypes=false,
                    getFillLevels=function(self) return {[1]=self.level} end}
                return {uniqueId=id, spec_silo={storages={storage}},
                    getOwnerFarmId=function() return 1 end, getName=function() return 'Silo' end}
            end
        """)
        for name in ("NotificationManager", "EventDetector"):
            self.lua.execute((ROOT / "scripts" / f"{name}.lua").read_text(encoding="utf-8"))
        self.lua.execute("NotificationManager:init(); EventDetector:init(); EventDetector:syncFarm()")

    def run_lua(self, code):
        self.lua.execute(code)

    def test_two_full_silos_have_independent_stable_cooldowns(self):
        self.run_lua("""
            a, b = silo('A'), silo('B')
            places = {a,b}
            g_currentMission.placeableSystem={getPlaceables=function() return places end}
            EventDetector:checkSilos()
            assert(#NotificationManager.history == 2)
            assert(EventDetector:_getEntityKey(silo('A'), 'silo') == 'silo:A')
            EventDetector.siloStates={}
            EventDetector:checkSilos()
            assert(not EventDetector.siloStates['silo:A'].notifiedFull)
            g_time=g_time+300001
            EventDetector:checkSilos()
            assert(#NotificationManager.history == 4)
            places={}; EventDetector:checkSilos(); assert(next(EventDetector.siloStates)==nil)
        """)

    def test_fuel_transition_retries_after_rejection_and_rearms(self):
        self.run_lua("""
            v=vehicle('V'); g_currentMission.vehicles={v}
            NotificationManager.MAX_QUEUE=0
            EventDetector:checkVehicles()
            assert(not EventDetector.vehicleStates['vehicle:V'].notifiedLow)
            NotificationManager.MAX_QUEUE=50
            EventDetector:checkVehicles(); assert(#NotificationManager.history==1)
            v.fuel=1; EventDetector:checkVehicles()
            v.fuel=0.1; EventDetector:checkVehicles()
            assert(not EventDetector.vehicleStates['vehicle:V'].notifiedLow)
            g_time=g_time+120001; EventDetector:checkVehicles()
            assert(#NotificationManager.history==2)
            assert(EventDetector:_getEntityKey(vehicle('V'), 'vehicle')=='vehicle:V')
            assert(EventDetector:_getEntityKey(vehicle(nil), 'vehicle') ~= EventDetector:_getEntityKey(vehicle(nil), 'vehicle'))
            g_currentMission.vehicles={}; EventDetector:checkVehicles()
            assert(next(EventDetector.vehicleStates)==nil)
        """)

    def test_field_ready_and_withered_retry(self):
        self.run_lua("""
            field={fieldId=1, farmland={id=1}, fieldState={isValid=true,fruitTypeIndex=1,growthState=5}}
            g_fieldManager={fields={field}}
            g_farmlandManager={getFarmlandOwner=function() return 1 end}
            g_fruitTypeManager={getFruitTypeByIndex=function() return {
                name='Wheat', getIsWithered=function(_,state) return state==9 end,
                getIsHarvestReady=function(_,state) return state==5 end} end}
            NotificationManager.MAX_QUEUE=0; EventDetector:checkFields()
            assert(not EventDetector.fieldStates[1].notifiedReady)
            NotificationManager.MAX_QUEUE=50; EventDetector:checkFields()
            assert(#NotificationManager.history==1)
            field.fieldState.growthState=9
            NotificationManager.MAX_QUEUE=1; EventDetector:checkFields()
            assert(not EventDetector.fieldStates[1].notifiedOverdue)
            NotificationManager:clearPendingPopups(); EventDetector:checkFields()
            assert(#NotificationManager.history==2)
            assert(NotificationManager.history[1].type=='harvest_overdue')
            EventDetector:checkFields(); assert(#NotificationManager.history==2)
        """)

    def test_one_shot_job_and_rain_retry(self):
        self.run_lua("""
            local v=vehicle('V')
            job={startedFarmId=1,vehicleParameter={getVehicle=function() return v end}}
            EventDetector:onAIJobStarted(job,1)
            NotificationManager.MAX_QUEUE=0
            EventDetector:onAIJobStopped(job,success)
            assert(#EventDetector.pendingEvents==1)
            raining=false
            g_currentMission.environment={weather={getIsRaining=function() return raining end}}
            EventDetector:checkWeather(); raining=true; EventDetector:checkWeather()
            assert(#EventDetector.pendingEvents==2)
            NotificationManager.MAX_QUEUE=50; EventDetector:update(1)
            assert(#EventDetector.pendingEvents==0 and #NotificationManager.history==2)
        """)

    def test_farm_isolation_and_callback_does_not_hide_switch(self):
        self.run_lua("""
            NotificationManager:push('fuel_low','title','msg',nil,'vehicle:V')
            EventDetector:_pushOrRetry('fuel_low','title','msg',nil,'vehicle:V')
            currentFarm=2
            EventDetector:onAIJobStarted({},2)
            assert(NotificationManager.farmId==1) -- main must observe the switch itself
            EventDetector:syncFarm()
            assert(NotificationManager.farmId==2 and #NotificationManager.history==0)
            assert(#EventDetector.pendingEvents==0)
            assert(NotificationManager:push('fuel_low','title','msg',nil,'vehicle:V'))
            currentFarm=255; EventDetector:syncFarm()
            assert(NotificationManager.farmId==nil and #NotificationManager.history==0)
            assert(NotificationManager:push('fuel_low','x','x')==nil)
            currentFarm=1; EventDetector:syncFarm()
            assert(#NotificationManager.history==1 and #NotificationManager.queue==1)
            assert(NotificationManager:push('fuel_low','title','msg',nil,'vehicle:V')==nil)
            NotificationManager:markAllRead()
            currentFarm=2; EventDetector:syncFarm(); currentFarm=1; EventDetector:syncFarm()
            assert(#NotificationManager.queue==0 and NotificationManager:getUnreadCount()==0)
        """)

    def test_persistence_before_farm_selection_remaining_time_and_ids(self):
        self.run_lua("""
            NotificationManager:push('fuel_low','a','a',7,'vehicle:A')
            NotificationManager:setFarmId(2)
            NotificationManager:push('silo_full','b','b',nil,'silo:B')
            NotificationManager:push('fuel_low','c','c',nil,'session:vehicle:1')
            g_time=g_time+50000
            xml={}; NotificationManager:saveToXML(xml,'root')
            NotificationManager:init(); g_time=0
            NotificationManager:loadFromXML(xml,'root')
            assert(NotificationManager.farmId==nil and #NotificationManager.history==0)
            NotificationManager:setFarmId(1)
            assert(#NotificationManager.history==1 and #NotificationManager.queue==1)
            assert(NotificationManager.history[1].vehicleId=='vehicle:A')
            assert(NotificationManager.history[1].farmId==1)
            assert(NotificationManager.cooldowns['fuel_low|7|vehicle:A']==70000)
            local loadedId=NotificationManager.history[1].id
            g_time=70001
            local n=NotificationManager:push('fuel_low','a','a',7,'vehicle:A')
            assert(n and n.id~=loadedId)
            NotificationManager:setFarmId(2)
            assert(#NotificationManager.history==2)
            assert(NotificationManager.cooldowns['fuel_low||session:vehicle:1']==nil)
            assert(NotificationManager.cooldowns['silo_full||silo:B']==250000)
        """)

    def test_bounds_cleanup_and_legacy_isolation(self):
        self.run_lua("""
            for i=1,200 do NotificationManager:push('fuel_low','a','a',nil,'vehicle:'..i) end
            assert(#NotificationManager.queue==50 and #NotificationManager.history==50)
            NotificationManager:clearPendingPopups()
            for i=201,500 do NotificationManager:push('fuel_low','a','a',nil,'vehicle:'..i) end
            assert(#NotificationManager.queue<=50 and #NotificationManager.history==50)
            g_time=g_time+120001; NotificationManager:cleanupCooldowns()
            assert(next(NotificationManager.cooldowns)==nil)
            NotificationManager:loadFromXML({['root#count']=1},'root')
            assert(#NotificationManager.history==0)
            NotificationManager.MAX_QUEUE=0
            for i=1,100 do EventDetector:_pushOrRetry('worker_done','a','a',nil,'vehicle:'..i) end
            assert(#EventDetector.pendingEvents==50)
            g_time=g_time+600001; EventDetector:update(1)
            assert(#EventDetector.pendingEvents==0)
        """)

    def test_delete_unsubscribes_original_message_center(self):
        self.run_lua("""
            local original=g_messageCenter
            local before=original.removals
            g_messageCenter=nil
            EventDetector:delete()
            assert(original.removals==before+1)
            assert(next(EventDetector.activeAIJobs)==nil and #EventDetector.pendingEvents==0)
            EventDetector:delete() -- idempotent
            assert(original.removals==before+1)
        """)

    def test_cleanup_throttle_force_save_and_clock_reset(self):
        self.run_lua("""
            NotificationManager.cooldowns['fuel_low||old']=g_time+10
            g_time=g_time+20
            NotificationManager:cleanupCooldowns()
            assert(NotificationManager.cooldowns['fuel_low||old']~=nil)
            xml={}; NotificationManager:saveToXML(xml,'root')
            assert(NotificationManager.cooldowns['fuel_low||old']==nil)
            assert(xml['root.farm(0)#cooldownCount']==0)
            NotificationManager.cooldowns['fuel_low||old']=g_time+10
            g_time=g_time+1000; NotificationManager:cleanupCooldowns()
            assert(NotificationManager.cooldowns['fuel_low||old']==nil)
            NotificationManager.cooldowns['fuel_low||old']=-1
            g_time=0; NotificationManager:cleanupCooldowns()
            assert(NotificationManager.cooldowns['fuel_low||old']==nil)
        """)

    def test_loaded_field_ids_validate_only_against_known_fields(self):
        self.run_lua("""
            NotificationManager:push('harvest_ready','a','a',7)
            NotificationManager:push('harvest_ready','b','b',8)
            xml={}; NotificationManager:saveToXML(xml,'root')
            NotificationManager:loadFromXML(xml,'root')
            assert(NotificationManager.history[1].fieldId==8)
            assert(NotificationManager.history[2].fieldId==7)
            -- Index 8 contains actual field ID 7; index is not an ID.
            g_fieldManager={fields={[8]={getId=function() return 7 end}}}
            NotificationManager:loadFromXML(xml,'root')
            assert(NotificationManager.history[1].fieldId==nil)
            assert(NotificationManager.history[2].fieldId==7)
            g_fieldManager={fields={{fieldId=8}}}
            NotificationManager:loadFromXML(xml,'root')
            assert(NotificationManager.history[1].fieldId==8)
            assert(NotificationManager.history[2].fieldId==nil)
        """)


if __name__ == '__main__':
    unittest.main()
