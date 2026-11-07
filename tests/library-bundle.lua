local events,logs={},''
core={add_listener=function(self,name,event)events[event]=true end}
ModLog=function(value)logs=logs..value..'\n'end
cm=nil;cco=nil
local language_reads=0
common={get_context_value=function(expression)assert(expression=='LocLanguage');language_reads=language_reads+1;return 'RU'end}
assert(loadfile('.superpowers/library-probe-bundle.lua'))()
wh3ep_probe();wh3ep_probe()
assert(events.CharacterSelected and events.PanelOpenedCampaign and events.PanelClosedCampaign and events.ComponentLClickUp)
assert(logs:find('library_version=0.7.16',1,true) and logs:find('library_listeners_ready',1,true))
assert(language_reads==1,'startup may read only the global language once, without campaign/character context')
print('PASS: bundled entry registers once, global language only, no startup campaign/character CCO access or library writes')
