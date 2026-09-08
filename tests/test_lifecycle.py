"""Regression tests with Lua 5.1 and simulated GIANTS APIs; not an in-game test."""
import sys
import unittest
from pathlib import Path
import xml.etree.ElementTree as ET

try:
    from lupa.lua51 import LuaRuntime
except ImportError:
    sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'review-runtime'))
    from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            print=function(...) end
            g_currentModDirectory=''; g_currentModName='FS25_FarmNotify'
            addModEventListener=function(x) listener=x end
            g_currentMission={isMissionStarted=true, missionDynamicInfo={}, missionInfo={savegameDirectory='save'}}
            g_gui={getIsGuiVisible=function() return false end}
            files={}; failWrite=false
            fileExists=function(p) return files[p]~=nil end
            createXMLFile=function(_,p) return {path=p,values={}} end
            loadXMLFile=function(_,p) return files[p] end
            delete=function() end
            setXMLString=function(x,k,v) x.values[k]=v end
            setXMLInt=setXMLString; setXMLBool=setXMLString
            getXMLString=function(x,k) return x.values[k] end
            getXMLInt=getXMLString; getXMLBool=getXMLString
            saveXMLFile=function(x)
                if failWrite then return false end
                files[x.path]=x; return true
            end
        ''')
        self.lua.execute((ROOT/'scripts/FarmNotify.lua').read_text(encoding='utf-8'))
        self.lua.execute('''
            FarmNotify.initialized=true; FarmNotify.historyLoaded=true
            FarmNotify.saveGeneration=0
            FarmNotify.saveToXML=function(_,x,k) setXMLString(x,k..'#version','test') end
            FarmNotify.loadFromXML=function(_,x,k) loadedGeneration=getXMLInt(x,k..'#generation') end
        ''')

    def test_syntax(self):
        compile_lua=self.lua.eval('function(s) local f,e=loadstring(s);return f~=nil,e end')
        for f in (ROOT/'scripts').glob('*.lua'):
            ok, error=compile_lua(f.read_text(encoding='utf-8'))
            self.assertTrue(ok, f'{f}: {error}')

    def test_external_translations_and_assets(self):
        keys=[]
        for language in ('de','en'):
            root=ET.parse(ROOT/f'lang/lang_{language}.xml').getroot()
            texts=root.findall('texts/text')
            self.assertGreater(len(texts), 30)
            self.assertTrue(all('name' in e.attrib and 'text' in e.attrib for e in texts))
            keys.append({e.attrib['name'] for e in texts})
        self.assertEqual(*keys)
        desc=ET.parse(ROOT/'modDesc.xml').getroot()
        for node in desc.findall('extraSourceFiles/sourceFile'):
            self.assertTrue((ROOT/node.attrib['filename']).is_file())
        self.assertTrue((ROOT/desc.findtext('iconFilename')).is_file())

    def test_real_mission_flag_without_nested_flag(self):
        self.assertTrue(self.lua.eval('FarmNotify:isGameStarted()'))
        self.lua.execute('g_currentMission.isMissionStarted=false')
        self.assertFalse(self.lua.eval('FarmNotify:isGameStarted()'))

    def test_dedicated_object_skips_client_initialization(self):
        self.lua.execute('FarmNotify.initialized=false; g_dedicatedServer={}; NotificationManager={init=function() end}; FarmNotify:init()')
        self.assertTrue(self.lua.eval('FarmNotify.headless and FarmNotify.initialized'))

    def test_alternating_snapshots_load_newest(self):
        self.assertTrue(self.lua.eval('FarmNotify:saveHistory()'))
        self.assertTrue(self.lua.eval('FarmNotify:saveHistory()'))
        self.lua.execute('FarmNotify:loadHistory()')
        self.assertEqual(self.lua.eval('loadedGeneration'), 2)
        self.assertEqual(self.lua.eval('files["save/farmnotify.xml"].values["FarmNotify#generation"]'),1)

    def test_failed_write_preserves_previous(self):
        self.lua.execute('FarmNotify:saveHistory(); failWrite=true')
        self.assertFalse(self.lua.eval('FarmNotify:saveHistory()'))
        self.lua.execute('FarmNotify:loadHistory()')
        self.assertEqual(self.lua.eval('loadedGeneration'),1)

    def test_incomplete_snapshot_falls_back(self):
        self.lua.execute('FarmNotify:saveHistory(); FarmNotify:saveHistory(); files["save/farmnotify.backup.xml"].values["FarmNotify#complete"]=false; FarmNotify:loadHistory()')
        self.assertEqual(self.lua.eval('loadedGeneration'),1)

    def test_no_remote_save_directory(self):
        self.lua.execute('g_currentMission.missionInfo.savegameDirectory=nil')
        self.assertFalse(self.lua.eval('FarmNotify:saveHistory()'))

    def test_hook_preserves_results_and_saves(self):
        self.lua.execute('g_currentMission.saveSavegame=function(_,n) return n,nil,3 end; FarmNotify:installSaveHook()')
        self.assertEqual(self.lua.eval('g_currentMission:saveSavegame(7)'),(7,None,3))
        self.assertEqual(self.lua.eval('FarmNotify.saveGeneration'),1)

    def test_cursor_preserved_when_gui_takes_over(self):
        self.lua.execute('''
            cursor=false
            g_inputBinding={getShowMouseCursor=function() return cursor end,setShowMouseCursor=function(_,v) cursor=v end}
            FarmNotify:_setInboxMouseCursor(true)
            g_gui.getIsGuiVisible=function() return true end
            FarmNotify:_setInboxMouseCursor(false)
        ''')
        self.assertTrue(self.lua.eval('cursor'))

    def test_cursor_previous_state_restored(self):
        self.lua.execute('''
            cursor=true
            g_inputBinding={getShowMouseCursor=function() return cursor end,setShowMouseCursor=function(_,v) cursor=v end}
            FarmNotify:_setInboxMouseCursor(true);FarmNotify:_setInboxMouseCursor(false)
        ''')
        self.assertTrue(self.lua.eval('cursor'))

    def test_rejected_animation_does_not_consume_popup(self):
        self.lua.execute('''
            consumed=false
            FarmNotify.settings={get=function() return true end}
            NotificationManager={peekNext=function() return {id=1} end,markDisplayed=function() consumed=true end}
            PhoneAnimator={showNotification=function() return false end}
            FarmNotify:_tryShowNextNotification()
        ''')
        self.assertFalse(self.lua.eval('consumed'))

    def test_audio_handles_use_engine_delete(self):
        self.lua.execute((ROOT/'scripts/SoundController.lua').read_text(encoding='utf-8'))
        self.lua.execute('''
            count=0; stopSample=function() end
            delete=function(id) assert(type(id)=='number');count=count+1 end
            SoundController.samples={event={a=1},default=2,phone={iphone={message=3}}}
            SoundController:delete()
        ''')
        self.assertEqual(self.lua.eval('count'),3)

    def test_full_startup_save_and_cleanup(self):
        desc=ET.parse(ROOT/'modDesc.xml').getroot()
        for node in desc.findall('extraSourceFiles/sourceFile'):
            self.lua.execute((ROOT/node.attrib['filename']).read_text(encoding='utf-8'))
        self.lua.execute('''
            getUserProfileAppPath=function() return 'profile/' end
            createFolder=function() end
            createSample=function() return 1 end
            loadSample=function() return true end
            stopSample=function() end
            g_currentMission.getFarmId=function() return 1 end
            g_currentMission.saveSavegame=function() return 'saved' end
            g_inputBinding={registerActionEvent=function() return false,nil end}
            setXMLFloat=setXMLString;getXMLFloat=getXMLString
            FarmNotify:init();FarmNotify:update(16)
        ''')
        self.assertTrue(self.lua.eval('FarmNotify.initialized and FarmNotify.started'))
        self.assertEqual(self.lua.eval('NotificationManager.farmId'),1)
        self.assertEqual(self.lua.eval('g_currentMission:saveSavegame()'),'saved')
        self.lua.execute('FarmNotify:delete()')
        self.assertFalse(self.lua.eval('FarmNotify.initialized'))

if __name__=='__main__':
    unittest.main(verbosity=2)
