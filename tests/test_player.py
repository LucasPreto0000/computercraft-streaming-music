"""Run: python -m pip install lupa && python -m unittest discover -s tests -v"""
import unittest
from pathlib import Path
from lupa import LuaRuntime

SOURCE = (Path(__file__).resolve().parents[1] / "music.lua").read_text(encoding="utf-8")
ENTRY = "local ok, err = pcall(parallel.waitForAny, uiLoop, audioLoop, httpLoop)"


class PlayerTests(unittest.TestCase):
    def runtime(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.execute("""
            settings = {get=function(_, default) return default end}
            colors = {}
            for i,name in ipairs({"white","black","gray","lightGray","cyan","blue",
                "lime","orange","red","lightBlue"}) do colors[name]=2^i end
            term = {getSize=function() return 51,19 end,
                setCursorBlink=function() end, setBackgroundColor=function() end,
                clear=function() end,setCursorPos=function(x,y)
                    assert(x>=1 and x<=51 and y>=1 and y<=19)
                end,setTextColor=function() end,write=function() end,clearLine=function() end}
            peripheral = {getNames=function() return {} end,
                hasType=function() return true end, isPresent=function() return true end}
            timerNumber = 0
            os = {
                startTimer=function() timerNumber=timerNumber+1; return timerNumber end,
                cancelTimer=function() end,
                pullEventRaw=function(filter) return coroutine.yield(filter) end,
                pullEvent=function(filter)
                    local ev=table.pack(coroutine.yield(filter))
                    if ev[1]=="terminate" then error("Terminated") end
                    return table.unpack(ev,1,ev.n)
                end,
                queueEvent=function() end
            }
            textutils = {urlEncode=function(s) return s end}
            http = {request=function() return true end}
        """)
        prefix = SOURCE[:SOURCE.index(ENTRY)]
        api = lua.execute(prefix + """
            return {
                play=playBufferOnAllSpeakers,
                render=redrawScreen,
                tab=function(value) tab=value end,
                search=requestMusicSearch,
                result=function() return search_results, search_notice end,
                refresh=refreshSpeakers,
                count=function() return #speakers end
            }
        """)
        lua.globals().api = api
        return lua, api

    def test_syntax_and_screens(self):
        lua, api = self.runtime()
        for tab in (1, 2, 3):
            api.tab(tab)
            api.render()
        lua.execute('assert(load(...))', SOURCE)

    def test_parallel_dispatch_and_barrier(self):
        for count in (1, 6, 128, 1000):
            lua, _ = self.runtime()
            lua.globals().count = count
            lua.execute("""
                local calls, group = {}, {}
                for i=1,count do
                    local name="speaker_"..i
                    group[i]={name=name, device={playAudio=function(audio,volume)
                        calls[name]=(calls[name] or 0)+1
                        assert(audio[1]==12 and volume==3)
                        -- Model a peripheral call which yields until the next tick.
                        coroutine.yield("task_complete")
                        return true
                    end}}
                end
                local co=coroutine.create(function() api.play({12,34},group) end)
                assert(coroutine.resume(co))
                for i=1,count do assert(calls["speaker_"..i]==1) end
                assert(coroutine.resume(co,"task_complete"))
                for i=1,count-1 do
                    assert(coroutine.resume(co,"speaker_audio_empty","speaker_"..i))
                    assert(coroutine.status(co)=="suspended")
                end
                assert(coroutine.resume(co,"speaker_audio_empty","speaker_"..count))
                assert(coroutine.status(co)=="dead")
                for i=1,count do assert(calls["speaker_"..i]==1) end
            """)

    def test_busy_speaker_retries_without_repeating_accepted_chunk(self):
        lua, _ = self.runtime()
        lua.execute("""
            local calls={0,0}
            local group={}
            for i=1,2 do
                group[i]={name="speaker_"..i,device={playAudio=function()
                    calls[i]=calls[i]+1
                    return i==1 or calls[i]>1
                end}}
            end
            local co=coroutine.create(function() api.play({1},group) end)
            assert(coroutine.resume(co))
            assert(coroutine.resume(co,"speaker_audio_empty","speaker_1"))
            assert(coroutine.resume(co,"speaker_audio_empty","speaker_2"))
            assert(coroutine.resume(co,"speaker_audio_empty","speaker_2"))
            assert(coroutine.status(co)=="dead")
            assert(calls[1]==1 and calls[2]==2)
        """)

    def test_detach_and_timeout_surface_errors(self):
        for event, value in (("peripheral_detach", "speaker_1"), ("timer", 1)):
            lua, _ = self.runtime()
            lua.globals().event, lua.globals().value = event, value
            lua.execute("""
                local co=coroutine.create(function()
                    api.play({1},{{name="speaker_1",device={playAudio=function() return true end}}})
                end)
                assert(coroutine.resume(co))
                local ok,err=coroutine.resume(co,event,value)
                assert(not ok and tostring(err):find("speaker_1"))
            """)

    def test_external_site_requires_backend(self):
        _, api = self.runtime()
        self.assertFalse(api.search("https://vimeo.com/123"))
        _, notice = api.result()
        self.assertIn("music.media_backend", notice)
        self.assertTrue(api.search("https://example.org/music.dfpwm"))
        results, _ = api.result()
        self.assertEqual(results[1]["direct_url"], "https://example.org/music.dfpwm")


if __name__ == "__main__":
    unittest.main()
