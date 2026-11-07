wh3ep_locale_ru=assert(loadfile('src/locales/ru.lua'))()
wh3ep_locale_eng=assert(loadfile('src/locales/eng.lua'))()
local test_catalogs={eng=wh3ep_locale_eng,ru=wh3ep_locale_ru}
for _,id in ipairs({'cn','zh','sp','br','ge','ja','fr','pl','kr'})do
 local catalog=assert(loadfile('src/locales/'..id..'.lua'))();test_catalogs[id]=catalog;_G['wh3ep_locale_'..id]=catalog
end
wh3ep_localization_factory=assert(loadfile('src/wh3ep_localization.lua'))()
local create_ui=assert(loadfile('src/wh3ep_library_ui.lua'))()
local model=assert(loadfile('src/wh3ep_model.lua'))()
do
 local file=assert(io.open('src/ui/wh3ep_status.twui.xml','rb'));local xml=file:read('*a');file:close()
 local states,centered=0,0
 for alignment in xml:gmatch('texthalign="([^"]+)"')do states=states+1;if alignment=='Left'then centered=centered+1 end end
 assert(states==4 and centered==4,'result captions must share a left-aligned column')
end
local json=assert(loadfile('vendor/dkjson/dkjson.lua'))()
local store={}
local storage=assert(loadfile('src/wh3ep_storage.lua'))()(model,json,{read=function(k)return store[k]end,write=function(k,v)store[k]=v end})
local nodes,listeners={},{}
local node_sequence=0
local ui_errors=0
local viewport_width,viewport_height=1920,1080
local search_timer,entry_timer,form_timer
local priority_lock
local native_panel_cqi
common={get_context_value=function(kind,id,query)
 if kind=='LocLanguage'then return WH3EP_TEST_LANGUAGE or 'RU'end
 assert(kind=='CcoCampaignCharacter'and id=='opaque-character-context'and query=='CQI')
 return native_panel_cqi
end}
local category_sizes,template_sizes={},{}
do
 local file=assert(io.open('research/game81/ui/fontcategories.xml','rb'));local definitions=file:read('*a');file:close()
 for name,size in definitions:gmatch('<font name="([^"]+)".- size="(%d+)"')do category_sizes[name]=tonumber(size)end
end
cm={repeat_real_callback=function(self,fn,ms,name)assert(ms==200);if name=='wh3ep_library_form'then form_timer=fn elseif name=='wh3ep_library_search'then search_timer=fn else assert(name=='wh3ep_entry_layout');entry_timer=fn end end,remove_real_callback=function(self,name)if name=='wh3ep_library_form'then form_timer=nil elseif name=='wh3ep_library_search'then search_timer=nil elseif name=='wh3ep_entry_layout'then entry_timer=nil else error('unknown timer')end end}
local function node(id,parent)
 node_sequence=node_sequence+1
 local n={id=id,parent=parent,children={},visible=true,text='',order=node_sequence}
 nodes[id]=n;if parent then parent.children[id]=n end
 function n:AddScriptEventReporter()self.reports_events=true end
 function n:Id()return self.id end
 function n:GetContextObjectId(kind)
  assert(self.id=='character_context_parent'and kind=='CcoCampaignCharacter')
  if self.context_error then error('PRIVATE_CONTEXT_FAILURE',0)end
  if not self.context_missing then return 'opaque-character-context'end
 end
 function n:SetStateText(v)
  self.state_text=self.state_text or{};self.state_text[self.state or 'active']=v;self.text=v
  if self.template=='ui/templates/wh3ep_label.twui.xml' then self.text_width=108 end
 end
 function n:SetText(v)
  self.state_text=self.state_text or{}
  for _,state in ipairs({'active','hover','down','down_off','inactive','selected','selected_hover','selected_down','selected_down_off','good','available','warning'})do self.state_text[state]=v end
  self.text=v
 end
 function n:ResizeTextResizingComponentToInitialSize(w,h)self.text_width=w;self.text_height=h end
 function n:WidthOfTextLine(value)local chars=0;for i=1,#value do local b=value:byte(i);if b<128 or b>=192 then chars=chars+1 end end;return chars*(self.font_size or 18)*2/3 end -- Approximate average glyph width, not native raster metrics.
 function n:GetStateText()return self.text end
 function n:SetTooltipText(value)self.tooltip=value end
 function n:GetCurrentStateImageIndex(index)index=index or 0;local layers=(self.state_image_indices or{})[self.state or 'active']or{};if #layers==0 then return 0 end;return assert(layers[index+1],'state image layer must exist')end
 function n:SetImagePath(path,index,resize)if self.fail_image then error('image unavailable')end;index=index or 0;self.component_images=self.component_images or{};self.component_images[index]=path;self.image_path=self.component_images[self:GetCurrentStateImageIndex(0)];if resize then self.image_size={128,128}end end
 function n:ResizeCurrentStateImage(index,w,h)assert(self.resize_image_w and self.resize_image_h,'state image resizing must be explicitly allowed');if index==0 then self.image_size={w,h}end;self.state_sizes=self.state_sizes or{};self.state_sizes[self.state or 'active']=self.state_sizes[self.state or 'active']or{};self.state_sizes[self.state or 'active'][index]={w,h}end
 function n:SetCanResizeCurrentStateImageWidth(index,value)self.resize_image_w=value end
 function n:SetCanResizeCurrentStateImageHeight(index,value)self.resize_image_h=value end
 function n:SetCurrentStateImageDockingPoint(index,value)self.image_dock=value end
 function n:SetCurrentStateImageDockOffset(index,x,y)self.image_offset={x,y}end
 function n:GetCurrentStateImageDimensions(index)return self.image_size[1],self.image_size[2]end
 function n:GetCurrentStateImageDockOffset(index)return self.image_offset[1],self.image_offset[2]end
 function n:GetCurrentStateImageDockingPoint(index)return self.image_dock end
 function n:SetVisible(v)self.visible=v end
 function n:Visible(recursive)
  local current=self
  while current do if not current.visible then return false end;if not recursive then return true end;current=current.parent end
  return true
 end
 function n:ChildCount()local count=0;for _ in pairs(self.children)do count=count+1 end;return count end
 function n:Find(index)
  local children={};for _,child in pairs(self.children)do children[#children+1]=child end
  table.sort(children,function(a,b)return a.order<b.order end);return children[index+1]
 end
 function n:Bounds()
  local x,y=self:Position();local w,h=self:Dimensions();local l,t,r,b=x,y,x+w,y+h
  for _,child in pairs(self.children)do local cx,cy=child:Position();local cw,ch=child:Bounds();l=math.min(l,cx);t=math.min(t,cy);r=math.max(r,cx+cw);b=math.max(b,cy+ch)end
  return r-l,b-t
 end
 function n:LockPriority(value)assert(not priority_lock,'own modal must release its previous lock');priority_lock={owner=self,value=value or self.priority}end
 function n:UnLockPriority()assert(priority_lock and priority_lock.owner==self,'only owning popup may release its lock');priority_lock=nil end
 function n:RegisterTopMost()self.topmost=true end
 function n:RemoveTopMost()self.topmost=false end
 function n:Resize(w,h)
  if self.template=='ui/templates/wh3ep_icon.twui.xml' and self.image_offset then assert(self.image_offset[1]==0 and self.image_offset[2]==0,'reuse must reset prior padded-image offset before component resize')end
  self.w=w;self.h=h;self.text_width=w;self.text_height=h
 end
 function n:SetState(value)self.state=value;self.text=(self.state_text or{})[value]or '';self.image_path=(self.component_images or{})[self:GetCurrentStateImageIndex(0)];self.image_size=((self.state_sizes or{})[value]or{})[0]or self.image_size end
 function n:SetCanResizeWidth()end
 function n:SetCanResizeHeight()end
 function n:MoveTo(x,y)self.x=x;self.y=y end
 function n:PropagatePriority(value)self.priority=value end
 function n:Priority()return self.priority or 50 end
 function n:CurrentState()return self.state or 'active'end
 function n:IsInteractive()if self.interactive_override~=nil then return self.interactive_override end;return (self.state_interactive or{})[self.state or 'active']~=false end
 function n:SetInteractive(value)self.interactive_override=value end
 function n:NativeTransition(index)local target=assert(self.transitions[self:CurrentState()][index],'missing native transition');self:SetState(target)end
 function n:Dimensions()return self.w or viewport_width,self.h or viewport_height end
 function n:Position()return self.x or 0,self.y or 0 end
 return n
end
local root=node('root')
local panel=node('character_details_panel',root)
local state_matrix_checks=0
local function assert_role_states(component,role,mode)
 local before=component:CurrentState()
 for _,state in ipairs({'active','hover','down','down_off','inactive','selected','selected_hover','selected_down','selected_down_off'})do
  component:SetState(state)
  assert(component.image_path=='ui/skins/wh3ep/role_'..role..'_'..mode..'_active.png','the active base remains under every blended state: '..component.id..'/'..state..'; got='..tostring(component.image_path))
  local layers={'active','hover','down','inactive'}
  for layer,variant in ipairs(layers)do
   local image=layer-1;local expected='ui/skins/wh3ep/role_'..role..'_'..mode..'_'..variant..'.png'
   assert(component.component_images[component:GetCurrentStateImageIndex(image)]==expected,'state overlay resource mismatch: '..component.id..'/'..state..'/'..variant)
   assert(component.state_sizes[state][image][1]==component.w and component.state_sizes[state][image][2]==component.h,'each overlay keeps role dimensions')
  end
  local expected_alpha={active={'FFFFFFFF','FFFFFF00','FFFFFF00','FFFFFF00'},hover={'FFFFFFFF','FFFFFFFF','FFFFFF00','FFFFFF00'},down={'FFFFFFFF','FFFFFF00','FFFFFFFF','FFFFFF00'},down_off={'FFFFFFFF','FFFFFF00','FFFFFF00','FFFFFF00'},inactive={'FFFFFFFF','FFFFFF00','FFFFFF00','FFFFFFFF'},selected={'FFFFFFFF','FFFFFF00','FFFFFF00','FFFFFF00'},selected_hover={'FFFFFFFF','FFFFFFFF','FFFFFF00','FFFFFF00'},selected_down={'FFFFFFFF','FFFFFF00','FFFFFFFF','FFFFFF00'},selected_down_off={'FFFFFFFF','FFFFFF00','FFFFFF00','FFFFFF00'}}
  for layer,alpha in ipairs(expected_alpha[state])do assert(component.state_image_colors[state][layer]=='#'..alpha,'state overlay opacity differs from native endpoint: '..component.id..'/'..state..'/'..layer)end
  assert((mode=='plain'and component.text~='')or(mode=='fixed'and component.text==''),'catalog captions or word-free symbol art must survive state transitions')
  assert(component:WidthOfTextLine(component.text)<=component.w*.90,'native caption must keep centered 5% side margins: '..component.id..'/'..state)
  state_matrix_checks=state_matrix_checks+1
 end
 component:SetState(before)
end
local function make(id,path,parent)
 parent=parent or root
 local n=parent.children[id]
 if n then return n end
 if path:match('^ui/templates/wh3ep_')then local file=assert(io.open('src/ui/'..path:match('([^/]+)$'),'rb'),'runtime owned template missing from source: '..path);file:close()end
 n=node(id,parent);n.template=path
 if template_sizes[path]==nil then
  local file=io.open('src/ui/'..path:match('([^/]+)$'),'rb')
  if file then local xml=file:read('*a');file:close();template_sizes[path]=category_sizes[xml:match('fontcat_name="([^"]+)"')]or 18 else template_sizes[path]=18 end
 end
 -- ComponentImages are shared by the component; state imagemetrics reference GUIDs.
 -- Parse actual shipped TWUI references instead of assuming SetImagePath is state-local.
 local template=io.open('src/ui/'..path:match('([^/]+)$'),'rb')
 if template then
  local xml=template:read('*a');template:close()
  local component_name=path:match('([^/]+)%.twui%.xml$')
  local component_xml=xml:match('<'..component_name..'%s.-</'..component_name..'>')or ''
  local images=component_xml:match('<componentimages>(.-)</componentimages>')or ''
  local guids={};n.component_images={};n.state_image_indices={};n.state_image_colors={};n.transitions={};n.state_interactive={};local state_guids={}
  local index=0
  for attributes in images:gmatch('<component_image%s+([^>]+)')do
   local guid=attributes:match('uniqueguid="([^"]+)"');guids[guid]=index
   n.component_images[index]=attributes:match('imagepath="([^"]+)"');index=index+1
  end
  for _,state in ipairs({'active','hover','down','down_off','inactive','selected','selected_hover','selected_down','selected_down_off','good','available','warning'})do
   local attributes=component_xml:match('<'..state..'%s([^>]*)>')
   if attributes then state_guids[attributes:match('uniqueguid="([^"]+)"')]=state;n.state_interactive[state]=attributes:match('interactive="([^"]+)"')~='false'end
  end
  for _,state in ipairs({'active','hover','down','down_off','inactive','selected','selected_hover','selected_down','selected_down_off','good','available','warning'})do
   local body=component_xml:match('<'..state..'%s[^>]*>(.-)</'..state..'>')
   n.state_image_indices[state]={};n.state_image_colors[state]={}
   local metrics=body and body:match('<imagemetrics>(.-)</imagemetrics>')or''
   for image_attrs in metrics:gmatch('<image%s+([^>]+)/>')do
    local guid=image_attrs:match('componentimage="([^"]+)"')
    n.state_image_indices[state][#n.state_image_indices[state]+1]=assert(guids[guid],'state image must resolve a component-wide GUID')
    n.state_image_colors[state][#n.state_image_colors[state]+1]=image_attrs:match('colour="([^"]+)"')or'#FFFFFFFF'
   end
   n.transitions[state]={}
   for index,target in (body or ''):gmatch('<transition index="(%d+)" transition_m_target_state="([^"]+)"')do n.transitions[state][tonumber(index)]=assert(state_guids[target],'native transition must resolve a state GUID')end
  end
  n:SetState('active')
 end
 n.font_size=template_sizes[path]
 if path:find('square_medium_text_button',1,true)then node('button_txt',n)
 elseif path:find('popup_text_input',1,true)then
  node('text_input',node('text_input_list_parent',n))
  node('heading_txt',node('panel_title',n))
  local group=node('ok_cancel_buttongroup',n);node('button_ok',group);node('button_cancel',group)
 end
 return n
end
core={get_ui_root=function()return root end,get_or_create_component=function(self,id,path,parent)return make(id,path,parent)end,
 add_listener=function(self,name,event,condition,callback)listeners[event]=listeners[event] or {};listeners[event][#listeners[event]+1]={condition,callback}end}
find_uicomponent=function(parent,...)
 for _,id in ipairs({...})do parent=parent and parent.children[id]end
 return parent
end
UIComponent=function(value)return value end
uicomponent_descended_from=function(value,id)value=value and value.parent;while value do if value.id==id then return true end;value=value.parent end;return false end
ModLog=function(value)if value:find('library_ui_lua_error',1,true)then ui_errors=ui_errors+1 end end
local function describe(cqi)
 if cqi~=42 and cqi~=43 and cqi~=44 and cqi~=45 then return nil,'select_character' end
 return {cqi=cqi,faction_key='test_faction',class_key=cqi==42 and 'class_a' or cqi==44 and 'alchemist' or cqi==45 and 'wh3_main_cth_lord_caravan_master' or 'class_b',character_kind=cqi==44 and 'hero' or 'lord'}
end
local captures=0
local function capture(cqi)
 captures=captures+1
 local result=describe(cqi)
 result.equipment={{slot_key='weapon',item_key='test_sword'}};result.followers={'test_follower'}
 return result
end
local apply_calls={preview=0,start=0,resume=0,cancel=0};local applying,waiting,notify=false,false,nil
local apply={busy=function()return applying end,waiting=function()return waiting end}
function apply.preview(cqi,preset,take)
 apply_calls.preview=apply_calls.preview+1
 local entries={};for _,v in ipairs(preset.equipment)do entries[#entries+1]={key=v.item_key,slot_key=v.slot_key,category='equipment',status='free',replacement={key='old_sword'}}end
 for _,v in ipairs(preset.followers)do entries[#entries+1]={key=v,category='general',status='free'}end
 return{state={target={cqi=cqi},names={test_sword='Меч',test_follower='Спутник',old_sword='Старый меч'},icons={test_sword='ui/test/sword.png',test_follower='ui/test/follower.png'},donors={}},entries=entries,actions=entries,summary={free=#entries},take=take,goal=preset}
end
function apply.start(cqi,preset,take,approved,callback)
 assert(not priority_lock,'native confirmation/application may only start after own modal lock is released')
 assert(approved.state.target.cqi==cqi and approved.take==take)
 apply_calls.start=apply_calls.start+1;applying=true;notify=callback
 callback({status='running',completed=0,summary=approved.summary});return true
end
function apply.resume()apply_calls.resume=apply_calls.resume+1;applying,waiting=false,false;notify({status='complete',completed=2,summary={free=2}});return true end
function apply.cancel()if applying then apply_calls.cancel=apply_calls.cancel+1 end;return true end
local ui=create_ui(model,storage,{describe=describe,capture=capture,apply=apply,inspect=function(cqi)return{names={test_sword='Меч',test_follower='Спутник'},icons={test_sword='ui/test/sword.png',test_follower='ui/test/follower.png'}}end})
ui.start()
local registrations=0;for _,group in pairs(listeners)do registrations=registrations+#group end
ui.start()
local repeated=0;for _,group in pairs(listeners)do repeated=repeated+#group end
assert(registrations==repeated,'start must not register duplicate listeners')
local function event(name,context)
 if priority_lock and (name=='ComponentLClickUp'or name=='ComponentMouseOn'or name=='ComponentMouseOff')and (context.component.priority or 0)<priority_lock.value then return end
 if (name=='ComponentMouseOn'or name=='ComponentMouseOff')and not context.component.reports_events then return end
 -- Native-owned popup descendants can disappear before the script confirms.
 if name=='ComponentLClickUp'and context.component.id=='button_ok'then
  local popup=nodes.wh3ep_lib_input_popup
  if popup and popup.template:find('popup_text_input',1,true)then
   popup.children.text_input_list_parent.children.text_input=nil
  end
 end
 for _,entry in ipairs(listeners[name] or {})do if entry[1]==true or entry[1](context)then entry[2](context)end end
end
local function select(cqi)native_panel_cqi=cqi;event('CharacterSelected',{character=function()return{command_queue_index=function()return cqi end}end})end
local function click(id,component,reported)
 local n=component or assert(nodes[id],id)
 event('ComponentLClickUp',{string=reported or n.id,component=n})
end
local function input(text)
 local popup=assert(nodes.wh3ep_lib_input_popup)
 local input_component=find_uicomponent(popup,'text_input')or find_uicomponent(popup,'text_input_list_parent','text_input')
 input_component:SetStateText(text)
 click('button_ok',find_uicomponent(popup,'button_ok')or find_uicomponent(popup,'ok_cancel_buttongroup','button_ok'))
end
local function tooltip_at(px,py)
 local hit
 for _,candidate in pairs(nodes)do
  if candidate:Visible(true)and candidate:IsInteractive()then
   local cx,cy=candidate:Position();local cw,ch=candidate:Dimensions()
   if px>=cx and px<cx+cw and py>=cy and py<cy+ch and(not hit or(candidate.priority or 0)>(hit.priority or 0)or((candidate.priority or 0)==(hit.priority or 0)and candidate.order>hit.order))then hit=candidate end
  end
 end
 return hit
end
assert(captures==0 and next(store)==nil,'startup must not capture or write')
if WH3EP_TEST_LANGUAGE and WH3EP_TEST_LANGUAGE~='EN'and WH3EP_TEST_LANGUAGE~='RU'then
 local locale=wh3ep_localization_factory(test_catalogs,function()return WH3EP_TEST_LANGUAGE end);local T=locale.text
 local function capture_locale(name)
  local destination=os.getenv('WH3EP_UI_CAPTURE');if not destination then return end
  local out={};for _,n in pairs(nodes)do if n:Visible(true)and n.template and n.x and n.w then out[#out+1]={id=n.id,template=n.template,x=n.x,y=n.y,w=n.w,h=n.h,text=n.text,state=n.state or 'active',image=n.image_path,image_size=n.image_size,image_offset=n.image_offset,image_dock=n.image_dock,priority=n.priority or 0,order=n.order}end end
  local file=assert(io.open(destination..'/'..locale.language..'-'..name..'.json','wb'));file:write(assert(json.encode(out)));file:close()
 end
 local anchor=node('equipment_holder',node('character_details_subpanel',node('tab_panels',node('character_context_parent',panel))))
 anchor:Resize(642,682);anchor:MoveTo(1180,150)
 select(42);event('PanelOpenedCampaign',{string='character_details_panel'});click('wh3ep_lib_open')
 assert(nodes.wh3ep_lib_title.text==T('library_title')and nodes.wh3ep_lib_filter.tooltip==T('filter_matching'))
 assert(nodes.wh3ep_lib_save.text==T('button_save'))
 assert(nodes.wh3ep_lib_previous.text==T('button_previous')and nodes.wh3ep_lib_next.text==T('button_next'),'pagination captions must stay separate from arrow artwork')
 assert(not T('button_previous'):find('←',1,true)and not T('button_next'):find('→',1,true),'pagination captions must not contain arrow glyphs')
 assert(nodes.wh3ep_lib_previous_arrow.image_path=='ui/skins/wh3ep/glyph_arrow_back_inactive.png'and nodes.wh3ep_lib_next_arrow.image_path=='ui/skins/wh3ep/glyph_arrow_forward_inactive.png','one-page arrow paths '..tostring(nodes.wh3ep_lib_previous_arrow.image_path)..' / '..tostring(nodes.wh3ep_lib_next_arrow.image_path))
 for _,id in ipairs({'wh3ep_lib_save_class_label','wh3ep_lib_save_general_label'})do
  local c=nodes[id];local expected=id=='wh3ep_lib_save_class_label'and T('radio_class')or T('radio_general')
  for _,state in ipairs({'active','hover','down','inactive','selected'})do c:SetState(state);assert(c.text==expected and c:WidthOfTextLine(c.text)<=c.w,'compact translated radio fit '..locale.language)end
 end
 click('wh3ep_lib_save');assert(nodes.wh3ep_lib_input_popup.h==540)
 for _,key in ipairs({'general','attack','defense','scouting','magic','ranged','cavalry','command','support','supplies'})do
  local caption=assert(nodes['preset_icon_option_'..key]);assert(caption:WidthOfTextLine(caption.text)<=caption.w-6 and caption.tooltip==T('preset_icon_'..key),'translated icon label needs a 5% side inset and full tooltip: '..locale.language..'/'..key)
 end
 capture_locale('icon-picker')
 click('button_cancel',nodes.wh3ep_lib_input_popup.children.button_cancel)
 click('wh3ep_lib_save');input('Предпросмотр')
 assert(nodes.wh3ep_lib_details.text=='Предпросмотр','native/user text must bypass locale')
 capture_locale('library')
 click('wh3ep_lib_apply');assert(nodes.apply_row_1.text=='Меч')
 for _,id in ipairs({'summary_equip','summary_already','summary_skipped'})do local c=nodes[id];assert(c:WidthOfTextLine(c.text)<=c.w and c.tooltip==c.text,'localized preview count must fit and retain its complete tooltip: '..locale.language..'/'..id)end
 assert(nodes.preview_subtitle.tooltip=='Предпросмотр'and nodes.preview_subtitle.text=='Предпросмотр')
 capture_locale('preview')
 click('button_ok');assert(nodes.wh3ep_apply_progress:Visible(true)and nodes.progress_title.text==T('progress_applying'))
 capture_locale('progress')
 applying=false;notify({status='complete',completed=2,summary={free=2}})
 assert(nodes.result_summary:Visible(true)and ui_errors==0)
 for _,id in ipairs({'result_count_1','result_count_2','result_count_3'})do
  local c=nodes[id];local chars=0;for byte=1,#c.text do local b=c.text:byte(byte);if b<128 or b>=192 then chars=chars+1 end end
  local measured=(locale.language=='cn'or locale.language=='zh'or locale.language=='ja'or locale.language=='kr')and chars*20 or c:WidthOfTextLine(c.text)
  assert(measured<=c.w-6 and c.tooltip==c.text,'translated result caption must fit its centered safe width: '..locale.language..'/'..id)
 end
 capture_locale('result')
 print('PASS: translated controller library/preview/progress/result and preserved user/native text: '..locale.language)
 return
end
if WH3EP_TEST_LANGUAGE=='EN' then
 local function english_capture(name)
  local destination=os.getenv('WH3EP_UI_CAPTURE');if not destination then return end
  local output={}
  for _,n in pairs(nodes)do
   if n:Visible(true)and n.template and n.x and n.w then
    output[#output+1]={id=n.id,template=n.template,x=n.x,y=n.y,w=n.w,h=n.h,text=n.text,state=n.state or 'active',image=n.image_path,image_size=n.image_size,image_offset=n.image_offset,image_dock=n.image_dock,priority=n.priority or 0,order=n.order}
   end
  end
  local file=assert(io.open(destination..'/english-'..name..'.json','wb'));file:write(assert(json.encode(output)));file:close()
 end
 local anchor=node('equipment_holder',node('character_details_subpanel',node('tab_panels',node('character_context_parent',panel))))
 anchor:Resize(642,682);anchor:MoveTo(1180,150)
 select(42);event('PanelOpenedCampaign',{string='character_details_panel'});click('wh3ep_lib_open')
 assert(nodes.wh3ep_lib_frame.image_path=='ui/skins/wh3ep/en_panel.png'and nodes.wh3ep_lib_title.visible and nodes.wh3ep_lib_title.text=='Equipment presets','English uses blank art and the catalog heading')
 assert(nodes.wh3ep_lib_save.text=='Save loadout'and nodes.wh3ep_lib_save.image_path:find('role_save_plain_',1,true),'English buttons must not show baked Russian captions')
 assert(nodes.wh3ep_lib_previous.text=='Back'and nodes.wh3ep_lib_next.text=='Next','button captions must be centered without inline arrows')
 assert(nodes.wh3ep_lib_previous_arrow.image_path=='ui/skins/wh3ep/glyph_arrow_back_inactive.png'and nodes.wh3ep_lib_next_arrow.image_path=='ui/skins/wh3ep/glyph_arrow_forward_inactive.png','one-page arrow paths '..tostring(nodes.wh3ep_lib_previous_arrow.image_path)..' / '..tostring(nodes.wh3ep_lib_next_arrow.image_path))
 assert(not nodes.wh3ep_lib_previous_arrow.visible and not nodes.wh3ep_lib_next_arrow.visible,'one-page lists must hide pagination arrow artwork with the buttons')
 assert(nodes.wh3ep_lib_filter.tooltip=='Class + general'and nodes.search_hint.text=='Search presets…')
 assert(nodes.wh3ep_lib_save_class_label.text=='Class'and nodes.wh3ep_lib_save_general_label.text=='Shared')
 for _,id in ipairs({'wh3ep_lib_save_class_label','wh3ep_lib_save_general_label'})do
  local c=nodes[id];assert(c.template=='ui/templates/wh3ep_radio_text.twui.xml'and c:WidthOfTextLine(c.text)<=c.w)
  for _,state in ipairs({'active','hover','down','down_off','inactive','selected','selected_hover','selected_down','selected_down_off'})do c:SetState(state);assert(c.text==(id=='wh3ep_lib_save_class_label'and 'Class'or 'Shared'))end
 end
 click('wh3ep_lib_save');assert(nodes.panel_title.text=='New preset name')
 assert(nodes.wh3ep_lib_input_popup.h==540,'name and icon picker needs a dedicated safe modal height')
 for _,key in ipairs({'general','attack','defense','scouting','magic','ranged','cavalry','command','support','supplies'})do
  local button=assert(nodes['preset_icon_option_'..key],'missing preset icon choice: '..key)
  local art=assert(nodes['preset_icon_art_'..key],'missing preset icon glyph: '..key)
  assert(button:Visible(true)and art:Visible(true),'preset icon choice must be visible: '..key)
  assert(button.w==72 and button.h==72,'preset icon choice needs a 72x72 target')
  assert(button.x>=nodes.wh3ep_lib_input_popup.x and button.y>=nodes.wh3ep_lib_input_popup.y,'icon target must stay inside modal safe zone')
  assert(button.x+button.w<=nodes.wh3ep_lib_input_popup.x+nodes.wh3ep_lib_input_popup.w and button.y+button.h<=nodes.wh3ep_lib_input_popup.y+nodes.wh3ep_lib_input_popup.h,'icon target must stay inside modal safe zone')
  assert(art.image_path=='ui/skins/wh3ep/preset_icon_'..key..'.png','preset icon choice must show its saved archetype')
  assert(not art:IsInteractive(),'icon art must not steal the button hit target')
  assert(art.x==button.x+8 and art.y==button.y+8 and art.x+art.w<=button.x+button.w-8 and art.y+art.h<=button.y+button.h-8,'icon art must stay clear of the caption safe area')
  assert(tooltip_at(art.x+art.w/2,art.y+art.h/2)==button,'the full tile remains one click target')
  assert(button.text=='','archetypes must have tooltip only');local expected_caption=wh3ep_locale_eng['preset_icon_'..key]
  assert(button:WidthOfTextLine(button.text)<=button.w-6 and button.tooltip==expected_caption,'localized archetype caption must stay inside a 5% horizontal safe zone and preserve the full tooltip')
  for _,state in ipairs({'active','hover','down','down_off','inactive','selected','selected_hover','selected_down','selected_down_off'})do
   button:SetState(state)
   local images=button.state_image_indices[state];local colors=button.state_image_colors[state]
   assert(button.component_images[images[1]]=='ui/skins/wh3ep/preset_icon_option_active.png'and colors[1]=='#FFFFFFFF','tile keeps its active base under blended overlays: '..key..'/'..state)
   if state=='active'then for layer=2,#images do assert(colors[layer]=='#FFFFFF00','idle tile overlays remain transparent')end
   else
    local overlay='ui/skins/wh3ep/preset_icon_option_'..state..'.png';local visible=false
    for layer=2,#images do if button.component_images[images[layer]]==overlay and colors[layer]=='#FFFFFFFF'then visible=true end end
    assert(visible,'tile state art must be blended over its base: '..key..'/'..state)
   end
   assert(button:WidthOfTextLine(button.text)<=button.w-6 and button.tooltip==expected_caption,'tile background, safe caption and full tooltip must follow native button state: '..key..'/'..state)
  end
  button:SetState(key=='general'and 'selected'or 'active')
 end
 assert(nodes.preset_icon_option_general.state=='selected','new presets must initially choose the general icon')
 english_capture('icon-picker')
 click('preset_icon_option_attack',nodes.preset_icon_option_attack)
 input('Предпросмотр')
 local icon_library=assert(storage.load());local icon_preset=assert(model.list(icon_library,'test_faction','class_a','all','', 'lord')[1])
 assert(icon_preset.icon_key=='attack','create must persist the selected preset icon')
 assert(nodes.wh3ep_lib_details.text=='Предпросмотр','user preset names must never pass through UI translation')
 assert(nodes.wh3ep_lib_card_count.text=='1 item · 1 follower')
 assert(nodes.row_icon_1.image_path=='ui/skins/wh3ep/preset_icon_attack.png','library identity must use the stored preset icon')
 assert(nodes.row_icon_1.visible,'preset row icon must remain visible after its image is assigned')
 assert(nodes.row_icon_1.w==64 and nodes.row_icon_1.h==64,'preset archetype glyph must match its 64x64 native canvas')
 assert(nodes.row_icon_1.order>nodes.row_item_frame_1.order,'preset row icon must be layered after its opaque item frame')
 assert(nodes.row_icon_1.priority>nodes.row_item_frame_1.priority,'preset row icon must be above the frame priority')
 assert(nodes.row_icon_1.tooltip=='Attack'and nodes.card_heading_icon.tooltip=='Attack','preset archetype icons must describe their saved meaning')
 assert(nodes.row_item_frame_1.image_path=='ui/skins/wh3ep/rarity_default.png','archetype icons must use a neutral frame, not the first item rarity')
 assert(nodes.card_heading_icon.image_path=='ui/skins/wh3ep/preset_icon_attack.png','selected card identity must use the stored preset icon')
 assert(nodes.card_heading_frame.image_path=='ui/skins/wh3ep/rarity_default.png','card archetype icon must use a neutral frame')
 click('wh3ep_lib_rename')
 assert(nodes.preset_icon_option_attack.state=='selected','rename must reopen with the stored icon selected')
 click('preset_icon_option_scouting',nodes.preset_icon_option_scouting);input('Предпросмотр')
 icon_library=assert(storage.load());icon_preset=assert(model.list(icon_library,'test_faction','class_a','all','', 'lord')[1])
 assert(icon_preset.icon_key=='scouting'and nodes.row_icon_1.image_path=='ui/skins/wh3ep/preset_icon_scouting.png'and nodes.card_heading_icon.image_path=='ui/skins/wh3ep/preset_icon_scouting.png','rename must atomically persist and display its new icon')
 click('wh3ep_lib_rename');assert(nodes.preset_icon_option_scouting.state=='selected')
 click('preset_icon_option_magic',nodes.preset_icon_option_magic);click('button_cancel',nodes.wh3ep_lib_input_popup.children.button_cancel)
 icon_library=assert(storage.load());icon_preset=assert(model.list(icon_library,'test_faction','class_a','all','', 'lord')[1])
 assert(icon_preset.icon_key=='scouting','cancelling icon choice must leave the saved icon unchanged')
 english_capture('library')
 click('wh3ep_lib_apply')
 assert(nodes.wh3ep_lib_input_popup.image_path=='ui/skins/wh3ep/en_preview_panel_titled.png'and nodes.panel_title.visible and nodes.panel_title.text=='Loadout preview')
 assert(nodes.apply_row_1.text=='Меч'and nodes.apply_detail_1.text=='Replaces: Старый меч','native item names must remain in the native language')
 for _,id in ipairs({'summary_equip','summary_already','summary_skipped'})do local c=nodes[id];assert(c:WidthOfTextLine(c.text)<=c.w and c.tooltip==c.text,'preview count label must fit and keep its full tooltip: '..id)end
 assert(nodes.button_preview_previous.text=='Back'and nodes.button_preview_next.text=='Next','preview page buttons must keep arrow glyphs separate')
 assert(nodes.button_preview_previous_arrow.image_path=='ui/skins/wh3ep/glyph_arrow_back_inactive.png'and nodes.button_preview_next_arrow.image_path=='ui/skins/wh3ep/glyph_arrow_forward_inactive.png','disabled pagination buttons need muted arrow overlays')
 assert(nodes.apply_status_1.text=='From inventory'and not nodes.apply_status_art_1.visible and nodes.button_ok.text=='Apply available')
 assert(nodes.button_preview_help.tooltip:find('Free copies',1,true))
 english_capture('preview')
 click('button_cancel');click('wh3ep_lib_close')
 local lib,code,meta=storage.load();assert(lib,code)
 local long_name=string.rep('W',64)
 local updated=assert(model.add(lib,capture(42),long_name,'class_a'))
 assert(storage.save(updated,lib.library_revision,meta.token))
 click('wh3ep_lib_open')
 for i=1,4 do if nodes['wh3ep_lib_row_'..i].tooltip==long_name then click('wh3ep_lib_row_'..i)end end
 click('wh3ep_lib_apply')
 assert(nodes.preview_subtitle.tooltip==long_name and nodes.preview_subtitle:WidthOfTextLine(nodes.preview_subtitle.text)<=nodes.preview_subtitle.w*.85,'long stored names must fit the preview ribbon at its 85 percent text limit')
 click('button_ok');assert(nodes.progress_track.image_path=='ui/skins/wh3ep/progress_track.png'and nodes.progress_track.image_size[1]==590 and nodes.progress_track.image_size[2]==16);assert(nodes.progress_fill.image_path=='ui/skins/wh3ep/progress_fill.png'and nodes.progress_fill.image_size[2]==10);english_capture('progress')
 applying=false;notify({status='complete',completed=2,summary={free=2}});english_capture('result')
 assert(nodes.result_icon_1.image_path=='ui/skins/wh3ep/glyph_equipped.png'and nodes.result_icon_2.image_path=='ui/skins/wh3ep/glyph_already.png'and nodes.result_icon_3.image_path=='ui/skins/wh3ep/glyph_skipped.png','normal result icons must match their captions')
 assert(nodes.result_icon_1.x==nodes.result_icon_2.x and nodes.result_icon_2.x==nodes.result_icon_3.x,'result icons share one column');for i=1,3 do local icon,label=nodes['result_icon_'..i],nodes['result_count_'..i];assert(label.x==icon.x+icon.w+12 and label:WidthOfTextLine(label.text)<=label.w-6 and label.tooltip==label.text,'result icon and centered caption need a safe aligned group')end
 click('button_ok',nodes.wh3ep_lib_input_popup.children.button_ok)
 local page_lib,_,page_meta=storage.load();local page_updated=page_lib
 for i=1,3 do
  local next_lib=assert(model.add(page_updated,capture(42),'Pagination '..i,'class_a'))
  local saved,save_code,info=storage.save(next_lib,page_updated.library_revision,page_meta.token);assert(saved,save_code)
  page_updated,page_meta=next_lib,info
 end
 click('wh3ep_lib_close');click('wh3ep_lib_open')
 assert(nodes.wh3ep_lib_previous.visible and nodes.wh3ep_lib_next.visible and nodes.wh3ep_lib_previous_arrow.visible and nodes.wh3ep_lib_next_arrow.visible)
 assert(nodes.wh3ep_lib_previous_arrow.image_path=='ui/skins/wh3ep/glyph_arrow_back_inactive.png'and nodes.wh3ep_lib_next_arrow.image_path=='ui/skins/wh3ep/glyph_arrow_forward.png','first library page must mute only Back')
 click('wh3ep_lib_next')
 assert(nodes.wh3ep_lib_previous_arrow.image_path=='ui/skins/wh3ep/glyph_arrow_back.png'and nodes.wh3ep_lib_next_arrow.image_path=='ui/skins/wh3ep/glyph_arrow_forward_inactive.png','last library page must mute only Next')
 english_capture('library-pages')
 assert(ui_errors==0,'English UI must not raise guarded errors')
 print('PASS: English catalog UI, text-free artwork, nine radio states, native/user names preserved, long stored preview name fits')
 return
end
local equipment_anchor=node('equipment_holder',node('character_details_subpanel',node('tab_panels',node('character_context_parent',panel))))
equipment_anchor:Resize(642,682);equipment_anchor:MoveTo(1180,150)
select(42);event('PanelOpenedCampaign',{string='character_details_panel'})
assert(nodes.wh3ep_lib_open.x==984 and nodes.wh3ep_lib_open.y==150,'entry must follow the real equipment anchor with a 12px gap')
local ancillary=node('ancillary_parent',equipment_anchor);ancillary:MoveTo(1000,150);ancillary:Resize(292,676)
local magic=node('magic_items_equiped',ancillary);magic:MoveTo(980,120);magic:Resize(320,374)
local row_outside=node('native_armour_row',magic);row_outside:MoveTo(960,180);row_outside:Resize(340,70)
local followers=node('general_ancillaries_equipped',ancillary);followers:MoveTo(1000,520);followers:Resize(320,430)
local reserve=node('global_pool',equipment_anchor);reserve:MoveTo(1440,145);reserve:Resize(340,840)
local hidden=node('native_hidden_selector',equipment_anchor);hidden:MoveTo(0,0);hidden:Resize(1920,1080);hidden:SetVisible(false)
local hidden_child=node('native_hidden_selector_child',hidden);hidden_child:MoveTo(0,0);hidden_child:Resize(1920,1080)
event('PanelOpenedCampaign',{string='character_details_panel'})
assert(nodes.wh3ep_lib_open.x==764 and nodes.wh3ep_lib_open.y==120,'entry must avoid actual visible descendants extending left/up/down outside holder bounds')
assert(nodes.wh3ep_lib_open.x+nodes.wh3ep_lib_open.w<=row_outside.x-12,'entry must not cover the out-of-parent armour row')
assert(nodes.wh3ep_lib_open.visible,'hidden selector descendants must not block a valid adjacent position')
-- Stock8.1 list_clip children keep Visible(true) while scrolled outside the viewport.
local reserve_clip=node('list_clip',reserve);reserve_clip:MoveTo(1450,270);reserve_clip:Resize(320,650)
local scrolled_above=node('native_scrolled_above',reserve_clip);scrolled_above:MoveTo(1450,-883);scrolled_above:Resize(320,70)
local scrolled_below=node('native_scrolled_below',reserve_clip);scrolled_below:MoveTo(1450,1900);scrolled_below:Resize(320,70)
local partially_clipped=node('native_scrolled_partial',reserve_clip);partially_clipped:MoveTo(1450,245);partially_clipped:Resize(320,70)
event('PanelOpenedCampaign',{string='character_details_panel'})
assert(nodes.wh3ep_lib_open.visible and nodes.wh3ep_lib_open.x==764 and nodes.wh3ep_lib_open.y==120,'clipped reserve descendants must not hide or displace Presets; real armour protrusion still counts')
select(43);entry_timer()
assert(nodes.wh3ep_lib_open.visible and nodes.wh3ep_lib_open.y==120,'portrait switch with scrolled reserve must retain valid entry placement')
select(42)
reserve.children={}
if os.getenv('WH3EP_UI_CAPTURE')then
 local function rectangle(component)local x,y=component:Position();local w,h=component:Dimensions();return{x=x,y=y,w=w,h=h}end
 local file=assert(io.open(os.getenv('WH3EP_UI_CAPTURE')..'/entry-union-regression.json','wb'))
 file:write(assert(json.encode({synthetic=true,panel=rectangle(panel),holder=rectangle(equipment_anchor),magic=rectangle(magic),armour=rectangle(row_outside),followers=rectangle(followers),reserve=rectangle(reserve),hidden_selector=rectangle(hidden),entry=rectangle(nodes.wh3ep_lib_open),expected_union={x=960,y=120,w=862,h=865},gap=12})));file:close()
end
equipment_anchor.children={}
-- The native panel keeps its dimensions while its equipment anchors animate.
assert(entry_timer,'opening the native panel must arm bounded layout tracking')
local stale_entry_tick=entry_timer
magic.parent.children.magic_items_equiped=magic;equipment_anchor.children.ancillary_parent=ancillary
ancillary.children={magic_items_equiped=magic};magic.children={}
equipment_anchor:MoveTo(1619,182);magic:MoveTo(1591,182)
entry_timer()
assert(not nodes.wh3ep_lib_open.visible,'offscreen major anchors must hide the previously placed entry')
equipment_anchor:MoveTo(1278,150);ancillary:MoveTo(1278,150);magic:MoveTo(1250,150)
entry_timer()
assert(nodes.wh3ep_lib_open.visible and nodes.wh3ep_lib_open.x==1054,'same-size panel child movement must re-place entry without a second PanelOpened')
local tracked_entry=nodes.wh3ep_lib_open
local before_start=apply_calls.start
select(43);local new_entry_tick=entry_timer
assert(new_entry_tick and new_entry_tick~=stale_entry_tick,'selection must replace the bounded tracker')
stale_entry_tick();assert(entry_timer==new_entry_tick,'stale generation must not remove the replacement timer')
for i=1,30 do if entry_timer then entry_timer()end end
assert(not entry_timer and apply_calls.start==before_start,'layout polling must expire without gameplay commands')
event('PanelOpenedCampaign',{string='character_details_panel'})
local closed_tick=entry_timer
event('PanelClosedCampaign',{string='character_details_panel'})
assert(not entry_timer,'native close must remove tracking')
closed_tick();assert(not entry_timer,'stale tick after close must remain inert')
equipment_anchor.children={};select(42)

equipment_anchor:MoveTo(0,0);equipment_anchor:Resize(1920,1080);event('PanelOpenedCampaign',{string='character_details_panel'})
assert(not nodes.wh3ep_lib_open.visible,'present equipment with no free adjacent area must not use an overlapping fallback')
equipment_anchor:Resize(642,682)
equipment_anchor:MoveTo(1280,220);event('PanelOpenedCampaign',{string='character_details_panel'})
assert(nodes.wh3ep_lib_open.x==1084 and nodes.wh3ep_lib_open.y==220,'entry must follow moved native equipment, not a fixed screen coordinate')
assert(nodes.wh3ep_lib_open.x+nodes.wh3ep_lib_open.w<=equipment_anchor.x-12,'entry must not intercept equipment clicks')
local anchor_parent=equipment_anchor.parent;anchor_parent.children.equipment_holder=nil
panel:MoveTo(20,30);event('PanelOpenedCampaign',{string='character_details_panel'})
assert(nodes.wh3ep_lib_open.x==1102 and nodes.wh3ep_lib_open.y==180,'missing-anchor fallback must include actual parent Position and Dimensions')
anchor_parent.children.equipment_holder=equipment_anchor;panel:MoveTo(0,0);equipment_anchor:MoveTo(1180,150)
event('PanelOpenedCampaign',{string='character_details_panel'})
select(99);click('wh3ep_lib_open',nodes.wh3ep_lib_open)
assert(nodes.wh3ep_lib_open.text:find('Выбор',1,true)==1 and nodes.wh3ep_lib_open.tooltip=='Выберите своего лорда или героя','invalid target needs a short caption and full tooltip')
assert(nodes.wh3ep_lib_open:WidthOfTextLine(nodes.wh3ep_lib_open.text)<=124,'entry caption must fit the text area after reserving the emblem and a right-side safe margin')
select(42);event('PanelOpenedCampaign',{string='character_details_panel'})
click('wh3ep_lib_open',nodes.wh3ep_lib_open,'wh3ep_lib_open_callback')
assert(nodes.wh3ep_lib_open.template=='ui/templates/wh3ep_entry.twui.xml','entry must use compact CJM preset control')
assert(nodes.wh3ep_lib_open.w==184 and nodes.wh3ep_lib_open.h==46,'entry must not retain stock wide geometry')
assert(not nodes.wh3ep_lib_open.visible,'entry must remain hidden while library is visible')
assert(nodes.wh3ep_lib_title.visible and nodes.wh3ep_lib_title.text=='Пресеты снаряжения'and nodes.wh3ep_lib_frame.image_path=='ui/skins/wh3ep/en_panel.png','Russian uses clean art and a live catalog heading: visible='..tostring(nodes.wh3ep_lib_title.visible)..'; text='..tostring(nodes.wh3ep_lib_title.text)..'; image='..tostring(nodes.wh3ep_lib_frame.image_path))
assert(nodes.wh3ep_lib_title:WidthOfTextLine(nodes.wh3ep_lib_title.text)<=nodes.wh3ep_lib_title.w,'Russian title must fit its native heading')
assert(nodes.search_hint.template=='ui/templates/wh3ep_search_hint.twui.xml','search placeholder needs its independent faded role')
assert(entry_timer);entry_timer();assert(not nodes.wh3ep_lib_open.visible,'layout tick must not reveal entry over library')
assert(nodes.wh3ep_lib_frame and nodes.wh3ep_lib_frame.visible,'real component ID must win over reported event string')
assert(nodes.wh3ep_lib_search_input and nodes.wh3ep_lib_search_input.visible,'search must be editable in library')
assert(nodes.wh3ep_lib_filter.w==44 and nodes.wh3ep_lib_filter.text=='' and nodes.wh3ep_lib_filter.tooltip:find('Класс',1,true),'mode selector must be icon-only with immediate human-readable tooltip')
for layer,variant in ipairs({'active','hover','down','inactive'})do assert(nodes.wh3ep_lib_filter.component_images[nodes.wh3ep_lib_filter:GetCurrentStateImageIndex(layer-1)]=='ui/skins/wh3ep/filter_matching_'..variant..'.png','filter state layer maps the selected mode and visual state')end
assert(not nodes.wh3ep_lib_scope.text:find('Библиотека фракции',1,true),'character ribbon must omit faction library suffix')
assert(nodes.wh3ep_lib_help.tooltip~='?' and #nodes.wh3ep_lib_help.tooltip>20,'help guidance is available before clicking')
assert(nodes.wh3ep_lib_save_class.w==34 and nodes.wh3ep_lib_save_class.h==40 and nodes.wh3ep_lib_save_class.text=='','scope radio needs an independent fixed glyph')
assert(nodes.wh3ep_lib_save_class_label and nodes.wh3ep_lib_save_class_label.w==98,'scope caption needs its original available width')
assert(nodes.wh3ep_lib_save_class_label.text=='Класс' and nodes.wh3ep_lib_save_general_label.text=='Общий' and nodes.wh3ep_lib_save_general_label.template=='ui/templates/wh3ep_radio_text.twui.xml','Russian radio captions must come from the catalog through native text')
assert(nodes.wh3ep_lib_save_class_label.tooltip=='Класс' and nodes.wh3ep_lib_save_general_label.tooltip=='Общий','native radio text must retain complete semantic tooltips')
for _,id in ipairs({'wh3ep_lib_save_class_label','wh3ep_lib_save_general_label'})do
 local c=nodes[id];local caption=c.text
 assert(c:WidthOfTextLine(caption)<=c.w,'Russian radio caption must fit the original width')
 for _,state in ipairs({'active','hover','down','down_off','inactive','selected','selected_hover','selected_down','selected_down_off'})do c:SetState(state);assert(c.text==caption,'catalog radio text must survive all native states')end
end
assert(nodes.wh3ep_lib_save and nodes.wh3ep_lib_save.visible,'one Save button needs class/common selectors')
assert(nodes.wh3ep_lib_save.y>nodes.wh3ep_lib_search.y,'save belongs in footer')
for id,role in pairs({wh3ep_lib_save='save',wh3ep_lib_apply='preview',wh3ep_lib_close='close',wh3ep_lib_rename='rename',wh3ep_lib_overwrite='update',wh3ep_lib_change_scope='scope',wh3ep_lib_delete='delete',wh3ep_lib_previous='previous',wh3ep_lib_next='next',wh3ep_lib_help='library_help'})do
 assert_role_states(nodes[id],role,(role=='library_help'or role=='help'or role=='cross')and 'fixed'or 'plain')
end
-- Drive the actual shipped transition graph, without Lua repaint callbacks.
local native_button=nodes.wh3ep_lib_save;native_button:SetState('active')
for _,step in ipairs({{0,'hover'},{2,'down'},{1,'down_off'},{0,'down'},{3,'hover'},{1,'active'}})do
 native_button:NativeTransition(step[1]);assert(native_button:CurrentState()==step[2]);assert(native_button.image_path:find('role_save_plain_',1,true),'native-only transition must retain catalog caption')
end
event('ComponentMouseOn',{component=nodes.wh3ep_lib_save,string='wh3ep_lib_save'})
assert(nodes.wh3ep_lib_save.state=='hover','own buttons need hover feedback')
assert(nodes.wh3ep_lib_save.tooltip=='Сохранить комплект' and nodes.wh3ep_lib_save.image_path:find('role_save_plain_',1,true)~=nil,'hover must retain caption')
nodes.wh3ep_lib_save:SetState('down');assert(nodes.wh3ep_lib_save.tooltip=='Сохранить комплект' and nodes.wh3ep_lib_save.image_path:find('role_save_plain_',1,true)~=nil,'native pressed state must retain caption')
-- Model the native transition first, then ensure Lua does not clobber it.
nodes.wh3ep_lib_save:SetState('down_off')
event('ComponentMouseOff',{component=nodes.wh3ep_lib_save})
assert(nodes.wh3ep_lib_save.state=='down_off','mouse leave while held must preserve native down_off')
nodes.wh3ep_lib_save:SetState('down')
event('ComponentMouseOn',{component=nodes.wh3ep_lib_save})
assert(nodes.wh3ep_lib_save.state=='down','re-entry while held must preserve native down')
nodes.wh3ep_lib_save:SetState('hover') -- native release
event('ComponentMouseOff',{component=nodes.wh3ep_lib_save,string='wh3ep_lib_save'})
assert(nodes.wh3ep_lib_save.state=='active','mouse leave must restore active button')
assert(nodes.wh3ep_lib_frame.template=='ui/templates/wh3ep_panel.twui.xml','main window must use shipped custom graphics')
assert(nodes.wh3ep_lib_save.w==250 and nodes.wh3ep_lib_save.h==52 and nodes.wh3ep_lib_save.image_path=='ui/skins/wh3ep/role_save_plain_active.png','Save must use original own-canvas role art, not scaled CRUD')
click('wh3ep_lib_close')
click('wh3ep_lib_open',nodes.wh3ep_lib_open,'wh3ep_lib_unrelated')
assert(nodes.wh3ep_lib_frame.visible,'child label must resolve to registered parent button')
click('wh3ep_lib_save_class');click('wh3ep_lib_save')
assert(nodes.panel_title.visible and nodes.wh3ep_lib_input_popup.image_path=='ui/skins/wh3ep/card.png','create dialog must preserve clean art and dynamic native heading')
assert(nodes.form_context and nodes.form_context.visible and nodes.form_context.text:find('Для класса',1,true),'create confirmation must retain the selected class scope after hiding library')
local modal=assert(nodes.wh3ep_lib_input_popup)
assert(nodes.form_counter and nodes.form_counter.text=='0 / 30','create dialog needs a live Unicode name counter')
assert(modal.parent==panel and not nodes.wh3ep_lib_frame.visible and not nodes.wh3ep_lib_open.visible,'real modal must be a sibling and hide library/entry, not only hide them in QA')
assert(priority_lock and priority_lock.owner==root and modal.topmost,'modal must own a native priority lock and topmost registration')
assert(not modal.template:find('popup_text_input',1,true),'script-owned dialog must not use PopupTextInput callback')
local captured_before_background=captures
click('wh3ep_lib_save_general');click('wh3ep_lib_save')
assert(captures==captured_before_background,'background actions must be blocked while entering a name')
local field=assert(modal.children.text_input)
modal.children.text_input=nil
click('button_ok',assert(modal.children.button_ok))
assert(next(store)==nil and modal.visible and not nodes.wh3ep_lib_frame.visible and priority_lock,'missing input must retain modal and lock without revealing library')
assert(nodes.panel_title.text=='Имя нового пресета' and nodes.form_feedback.visible and nodes.form_feedback.tooltip:find('Поле ввода',1,true),'input error must preserve title and provide separate full feedback')
modal.children.text_input=field
field:SetStateText(string.rep('Я',31));assert(form_timer);form_timer()
assert(field:GetStateText()==string.rep('Я',30)and nodes.form_counter.text=='30 / 30','name cap counts Unicode characters, not bytes')
field:SetStateText('');form_timer();assert(nodes.form_counter.text=='0 / 30')
input('Боевой класс')
local saved=storage.load()
assert(not priority_lock and not modal.topmost and nodes.wh3ep_lib_frame.visible and not nodes.wh3ep_lib_open.visible,'successful modal close must restore library while keeping entry hidden and release native locks')
assert(saved and #saved.factions.test_faction.presets==1 and saved.factions.test_faction.presets[1].class_key=='class_a')
assert(nodes.wh3ep_lib_row_1.state=='selected','selected preset needs native selected state')
assert(nodes.row_star_1 and nodes.row_star_1.visible,'approved list requires separate right-aligned favorite stars')
assert(nodes.row_star_1.x>nodes.row_name_1.x+nodes.row_name_1.w,'star must not overlap name')
click('row_star_1');assert(storage.load().factions.test_faction.presets[1].favorite and nodes.row_star_1.state=='selected','row star must toggle that preset favorite')
click('row_star_1');assert(not storage.load().factions.test_faction.presets[1].favorite,'row star must toggle favorite off')
click('wh3ep_lib_filter');assert(nodes.wh3ep_lib_filter_option_favorites.visible and nodes.wh3ep_lib_filter_menu.topmost,'filter menu must be topmost');assert(nodes.wh3ep_lib_filter_option_favorites.parent==nodes.wh3ep_lib_filter_menu,'options belong to overlay');click('wh3ep_lib_filter_option_favorites')
assert(nodes.library_empty_title.text=='В избранном пусто' and nodes.library_empty_hint.text:find('звезду',1,true),'empty favorites must give a useful next action')
click('wh3ep_lib_filter');click('wh3ep_lib_filter_option_matching')
event('ComponentMouseOn',{component=nodes.row_icon_1,string='row_icon_1'})
assert(nodes.wh3ep_lib_row_1.state=='selected_hover','hover on icon must highlight selected row')
event('ComponentMouseOff',{component=nodes.row_icon_1,string='row_icon_1'})
assert(nodes.wh3ep_lib_row_1.state=='selected','selected row survives mouse leave')
assert(nodes.row_name_1.visible and nodes.row_meta_1.visible,'row content must be separate from fixed background')
assert(nodes.row_icon_1.y>=nodes.wh3ep_lib_row_1.y and nodes.row_icon_1.y+44<=nodes.wh3ep_lib_row_1.y+nodes.wh3ep_lib_row_1.h,'icon must remain inside row')
assert(nodes.card_icon_frame_1.visible,'card icons need own graphic frames')
assert(nodes.card_icon_1.visible and nodes.card_icon_1.image_path=='ui/test/sword.png','selected card must show actual item icons')
assert(nodes.card_icon_1.image_size[1]==48 and nodes.card_icon_1.image_size[2]==48,'native file dimensions must not reset the compact icon slot')
assert(nodes.card_icon_1.image_dock==1 and nodes.card_icon_1.image_offset[1]==0 and nodes.card_icon_1.image_offset[2]==0,'icon needs explicit top-left metric anchor and zero offset')
assert(apply_calls.preview==0,'read-only card must not create application plan')
local before_live=storage.load().library_revision;local before_capture=captures
nodes.wh3ep_lib_search_input:SetStateText('нет такого');assert(search_timer);search_timer()
assert(not nodes.wh3ep_lib_row_1.visible and not nodes.search_hint.visible and storage.load().library_revision==before_live and captures==before_capture,'live search must filter without writes or capture')
assert(nodes.library_empty_title.visible and nodes.library_empty_title.text=='Ничего не найдено','empty search must explain its state')
assert(nodes.wh3ep_lib_apply.state=='inactive' and nodes.wh3ep_lib_rename.state=='inactive','empty search must disable selected-preset actions')
nodes.wh3ep_lib_search_input:SetStateText('');search_timer();assert(nodes.wh3ep_lib_row_1.visible and not nodes.library_empty_title.visible,'clearing input must restore results and remove guidance')
nodes.wh3ep_lib_search_input:SetStateText(string.rep('Щ',64));search_timer()
assert(nodes.wh3ep_lib_search_input:WidthOfTextLine(nodes.wh3ep_lib_search_input:GetStateText())<=(414-54-4)*0.85,'query must retain15% reserve after the lens inset')
nodes.wh3ep_lib_search_input:SetStateText('');search_timer()
local save_count=#saved.factions.test_faction.presets
click('wh3ep_lib_save_general');click('wh3ep_lib_save');click('button_cancel',nodes.wh3ep_lib_input_popup.children.button_cancel)
click('wh3ep_lib_save');input('Общий через выбор области')
assert(storage.load().factions.test_faction.presets[save_count+1].class_key=='','Save must honor common selector')
click('wh3ep_lib_delete');input('')
click('wh3ep_lib_save_general');click('wh3ep_lib_save');input('Общий')
saved=storage.load();assert(#saved.factions.test_faction.presets==2 and saved.factions.test_faction.presets[2].class_key=='')
click('wh3ep_lib_filter');click('wh3ep_lib_filter_option_general') -- matching -> classless
click('wh3ep_lib_row_1');click('wh3ep_lib_favorite')
saved=storage.load();assert(saved.factions.test_faction.presets[2].favorite)
click('wh3ep_lib_rename');input('Общий новый')
saved=storage.load();assert(saved.factions.test_faction.presets[2].name=='Общий новый')
nodes.wh3ep_lib_search_input:SetStateText('ОБЩИЙ');click('wh3ep_lib_search')
assert(nodes.wh3ep_lib_row_1.visible and not nodes.wh3ep_lib_row_2.visible,'search/filter must update visible list')
local search_revision=storage.load().library_revision
local search_captures=captures
click('wh3ep_lib_clear_search')
assert(nodes.wh3ep_lib_search_input.text=='' and storage.load().library_revision==search_revision and captures==search_captures,'search reset must only update view')
nodes.wh3ep_lib_search_input:SetStateText('ОБЩИЙ');click('wh3ep_lib_search')
local before=saved.library_revision
click('wh3ep_lib_delete')
local popup=nodes.wh3ep_lib_input_popup
click('button_cancel',find_uicomponent(popup,'button_cancel')or find_uicomponent(popup,'ok_cancel_buttongroup','button_cancel'))
assert(storage.load().library_revision==before,'cancel must not modify library')
click('wh3ep_lib_delete');input('')
saved=storage.load();assert(#saved.factions.test_faction.presets==1,'confirmed delete must persist')
click('wh3ep_lib_save_class');click('wh3ep_lib_save');select(43);input('Wrong target')
assert(storage.load().library_revision==saved.library_revision,'selection change during name entry must not save old target')
event('PanelClosedCampaign',{string='character_details_panel'})
assert(not nodes.wh3ep_lib_frame.visible,'closing game panel must hide library')
select(42);event('PanelOpenedCampaign',{string='character_details_panel'});click('wh3ep_lib_open')
assert(storage.load().factions.test_faction.presets[1].name=='Боевой класс','reopen must read persistent library')
for index=1,11 do
 local lib,_,meta=storage.load()
 local updated=assert(model.add(lib,capture(42),string.format('Page test %02d',index),'class_a'))
 assert(storage.save(updated,lib.library_revision,meta.token))
end
event('PanelClosedCampaign',{string='character_details_panel'})
event('PanelOpenedCampaign',{string='character_details_panel'});click('wh3ep_lib_open')
nodes.wh3ep_lib_search_input:SetStateText('');click('wh3ep_lib_search')
click('wh3ep_lib_filter');click('wh3ep_lib_filter_option_all') -- classless -> all
click('wh3ep_lib_row_1');click('wh3ep_lib_next')
assert(nodes.wh3ep_lib_row_1.state=='selected' and nodes.wh3ep_lib_details.text:find('Page test',1,true),'page navigation must select a visible row')
for i=1,20 do click('wh3ep_lib_next')end
assert(nodes.wh3ep_lib_next.state=='inactive','last library page must disable next')
local keep_last=nodes.wh3ep_lib_details.tooltip;click('wh3ep_lib_next');assert(nodes.wh3ep_lib_details.tooltip==keep_last,'out-of-bounds next must preserve selection')
for i=1,20 do click('wh3ep_lib_previous')end
assert(nodes.wh3ep_lib_previous.state=='inactive','first library page must disable previous')
for _,selected in ipairs({2,3})do click('wh3ep_lib_row_'..selected);assert(nodes['wh3ep_lib_row_'..selected].h==84 and nodes['wh3ep_lib_row_'..selected].image_size[2]==88,'selected row must keep distinct84px hitbox and original88px glow');for row=1,3 do assert(nodes['wh3ep_lib_row_'..row].y+nodes['wh3ep_lib_row_'..row].h<=nodes['wh3ep_lib_row_'..(row+1)].y,'row hitboxes must not overlap')end end
click('wh3ep_lib_row_2');local keep_first=nodes.wh3ep_lib_details.tooltip;click('wh3ep_lib_previous');assert(nodes.wh3ep_lib_details.tooltip==keep_first,'out-of-bounds previous must not select another preset')
assert(ui_errors==0,'guarded UI errors must fail the integration test')
print('PASS: native UI boundary, named class/classless save, favorites/rename/search/delete, canceled and changed-target writes, panel lifecycle and persistent reopen')
-- Existing general presets become visible on a hero and can bind to that hero class.
select(42);click('wh3ep_lib_save_general');click('wh3ep_lib_save');input('Общий лорда для героя')
select(44);nodes.wh3ep_lib_search_input:SetStateText('Общий лорда для героя');click('wh3ep_lib_search')
assert(nodes.wh3ep_lib_row_1.visible,'hero must see a general preset created by lord')
click('wh3ep_lib_row_1');click('wh3ep_lib_change_scope')
local rebound
for _,p in ipairs(storage.load().factions.test_faction.presets)do if p.name=='Общий лорда для героя'then rebound=p end end
assert(rebound and rebound.class_key=='alchemist'and rebound.character_kind=='hero','scope binding on hero must update subtype and kind together')
select(42)
assert(not nodes.wh3ep_lib_row_1.visible,'hero-bound preset must disappear on lord')
select(44);click('wh3ep_lib_save_general');click('wh3ep_lib_save');input('Общий героя для лорда')
select(42);nodes.wh3ep_lib_search_input:SetStateText('Общий героя для лорда');click('wh3ep_lib_search')
assert(nodes.wh3ep_lib_row_1.visible,'lord must see general preset created by hero')
select(45)
assert(nodes.wh3ep_lib_row_1.visible,'caravan lord must see common faction presets')
click('wh3ep_lib_save_class');click('wh3ep_lib_save');input('Класс караванщика')
select(42);nodes.wh3ep_lib_search_input:SetStateText('Класс караванщика');click('wh3ep_lib_search')
assert(not nodes.wh3ep_lib_row_1.visible,'caravan class preset must be hidden for another lord subtype')
select(45)
assert(nodes.wh3ep_lib_row_1.visible,'caravan class preset must remain visible on caravan lord')
assert(ui_errors==0,'hero/caravan UI lifecycle must not raise errors')
print('PASS: hero/lord shared UI, scope rebinding, caravan subtype visibility and saves')
-- Applying requires its own explicit preview and never writes the preset library.
local revision_before_apply=storage.load().library_revision
click('wh3ep_lib_apply')
assert(apply_calls.preview==1 and apply_calls.start==0,'preview must not start mutation')
for id,role in pairs({button_ok='apply',button_cancel='cancel',button_preview_previous='previous',button_preview_next='next',button_preview_help='help',button_preview_close='cross'})do assert_role_states(nodes[id],role,(role=='library_help'or role=='help'or role=='cross')and 'fixed'or 'plain')end

local original_icons=apply.preview
local stock_key='weapon'
function apply.preview(...)
 local plan=original_icons(...);plan.state.icons.test_sword='ui/skins/default/equipment_items_'..stock_key..'.png';return plan
end
click('preview_take_label',nodes.wh3ep_lib_input_popup.children.preview_take_label)
local function assert_image_centered(icon,padded)
 assert(icon.image_dock==1,'normalized stock and portraits must use TopLeft docking')
 assert(icon.image_size[1]==icon.w and icon.image_size[2]==icon.h,'runtime image canvas must equal its slot')
 assert(icon.image_offset[1]==0 and icon.image_offset[2]==0,'centering must not depend on negative offsets')
 local iw,ih=icon.image_size[1],icon.image_size[2]
 local image_x=icon.x+(icon.image_dock==5 and (icon.w-iw)/2 or 0)+icon.image_offset[1]
 local image_y=icon.y+(icon.image_dock==5 and (icon.h-ih)/2 or 0)+icon.image_offset[2]
 assert(image_x+iw/2==icon.x+icon.w/2 and image_y+ih/2==icon.y+icon.h/2,'state-image bounds must share the component centre')
end
assert(nodes.apply_icon_1.image_path=='ui/skins/wh3ep/stock_weapon.png','exact stock IconPath must use the compiled native-art asset')
assert(nodes.apply_icon_1.w==64 and nodes.apply_icon_1.image_size[1]==64,'normalized stock uses no runtime oversized canvas')
assert_image_centered(nodes.apply_icon_1,true)
for _,kind in ipairs({'armour','talisman','enchanted','arcane'})do
 stock_key=kind;click('preview_take_label',nodes.wh3ep_lib_input_popup.children.preview_take_label)
 assert(nodes.apply_icon_1.image_path=='ui/skins/wh3ep/stock_'..kind..'.png','only the five exact paths map to compiled stock assets')
 assert_image_centered(nodes.apply_icon_1,true)
end
stock_key='weapon_variant';click('preview_take_label',nodes.wh3ep_lib_input_popup.children.preview_take_label)
assert(nodes.apply_icon_1.image_path=='ui/skins/default/equipment_items_weapon_variant.png','similar custom paths must not enter the exact stock alias map')
assert_image_centered(nodes.apply_icon_1,false)
stock_key='arcane';click('preview_take_label',nodes.wh3ep_lib_input_popup.children.preview_take_label)
apply.preview=original_icons
assert(apply_calls.start==0 and nodes.wh3ep_lib_input_popup.visible,'preview donor toggle must only rebuild plan')
click('button_preview_take',nodes.wh3ep_lib_input_popup.children.button_preview_take)
assert(nodes.apply_preview.text_width==600,'fixed preview label must retain its assigned width after text update')
assert(nodes.wh3ep_lib_count.text_width==474 and nodes.wh3ep_lib_details.text_width==292,'library labels must retain assigned text widths')
local preview_text=nodes.apply_preview.text..nodes.apply_row_1.text..nodes.apply_row_2.text..nodes.apply_detail_1.text..nodes.apply_detail_2.text
assert(nodes.apply_status_1.state=='available','free item status must have available color')
assert(nodes.apply_state_icon_1.y+nodes.apply_state_icon_1.h/2==nodes.apply_status_1.y+nodes.apply_status_1.h/2,'preview status glyphs use the same row centre')
assert(nodes.apply_status_1.x>=nodes.apply_row_1.x+nodes.apply_row_1.w,'preview status must be a distinct right column')
assert(nodes.apply_icon_1.image_size[1]==64,'approved preview needs large native item icon')
assert_image_centered(nodes.apply_icon_1,false) -- Same physical component reused from padded to portrait.
assert(nodes.button_preview_take.template=='ui/templates/wh3ep_checkbox.twui.xml','donor switch must use real checkbox graphics')
assert(nodes.apply_icon_1.visible and nodes.apply_icon_1.image_path=='ui/test/sword.png','gear icon must use native path')
assert(nodes.apply_icon_2.visible and nodes.apply_icon_2.image_path=='ui/test/follower.png','follower icon must use native path')
assert(not nodes.apply_icon_3.visible,'unused rows must not show stale icons')
nodes.apply_icon_1.fail_image=true
click('button_preview_previous',nodes.wh3ep_lib_input_popup.children.button_preview_previous)
assert(not nodes.apply_icon_1.visible and nodes.apply_placeholder_1.visible and nodes.apply_row_1.visible,'image failure must leave readable item and placeholder')
assert(nodes.apply_placeholder_1.priority>nodes.apply_icon_frame_1.priority,'fallback must render above opaque icon frame')
nodes.apply_icon_1.fail_image=false
click('button_preview_previous',nodes.wh3ep_lib_input_popup.children.button_preview_previous)
assert(preview_text:find('Будет надето: 2',1,true),'preview needs total action count')
assert(preview_text:find('Меч',1,true) and preview_text:find('Спутник',1,true),'preview needs readable categories')
assert(preview_text:find('Заменит: Старый меч',1,true),'replacement must be visible before confirmation')
click('button_cancel',nodes.wh3ep_lib_input_popup.children.button_cancel)
assert(apply_calls.start==0,'cancel preview must not apply')
click('wh3ep_lib_apply')
assert(nodes.wh3ep_lib_input_popup.visible)
event('ComponentMouseOn',{component=nodes.wh3ep_lib_input_popup.children.button_ok,string='button_ok'})
assert(nodes.wh3ep_lib_input_popup.children.button_ok.state=='hover','confirm button needs hover feedback')
event('ComponentMouseOff',{component=nodes.wh3ep_lib_input_popup.children.button_ok,string='button_ok'})
click('button_ok',nodes.wh3ep_lib_input_popup.children.button_ok)
assert(apply_calls.start==1 and applying and storage.load().library_revision==revision_before_apply,'applying must not alter saved preset')
assert(nodes.wh3ep_lib_save.state=='inactive','busy actions need disabled feedback')
event('ComponentMouseOn',{component=nodes.wh3ep_lib_save,string='wh3ep_lib_save'})
assert(nodes.wh3ep_lib_save.state=='inactive','disabled button must not gain hover state')
click('wh3ep_lib_delete')
assert(not nodes.wh3ep_lib_input_popup.visible and storage.load().library_revision==revision_before_apply,'CRUD blocked while applying')
waiting=true;notify({status='awaiting_confirmation',completed=0,summary={donor=1}})
local background_slot=node('native_background_follower_slot',panel);background_slot.priority=100;background_slot:SetTooltipText('Native follower slot')
do
 local saved_revision=storage.load().library_revision;local saved_starts=apply_calls.start
 local progress=nodes.wh3ep_apply_progress
 assert(progress and progress:Visible(true)and nodes.progress_count.text=='0 / 2','active application shows confirmed progress in its own window')
 assert(not progress.topmost and not priority_lock,'progress must not block native donor confirmation')
 progress:SetVisible(false) -- Verify underlying disabled controls separately from the new overlay.
 for _,id in ipairs({'wh3ep_lib_overwrite','wh3ep_lib_save','wh3ep_lib_rename','wh3ep_lib_delete','wh3ep_lib_change_scope','wh3ep_lib_previous','wh3ep_lib_next'})do
  local disabled=assert(nodes[id]);assert(disabled:CurrentState()=='inactive')
  local bx,by=disabled:Position();local bw,bh=disabled:Dimensions()
  background_slot:MoveTo(bx,by);background_slot:Resize(bw,bh)
  local hit=tooltip_at(bx+bw/2,by+bh/2)
  assert(hit==nodes.wh3ep_lib_frame or hit==nodes.wh3ep_apply_progress,'inactive control must hit an owned surface instead of native follower slot underneath: '..id)
  click(hit:Id(),hit)
 end
 assert(storage.load().library_revision==saved_revision and apply_calls.start==saved_starts and not nodes.wh3ep_lib_input_popup.visible,'absorbed disabled-control hit must not mutate presets or apply equipment')
 local fx,fy=nodes.wh3ep_lib_frame:Position()
 background_slot:MoveTo(fx+5,fy+300);background_slot:Resize(10,10)
 assert(tooltip_at(fx+10,fy+305)==nodes.wh3ep_lib_frame,'blank panel area must also block background hover')
 background_slot:SetVisible(false)
 for _,id in ipairs({'wh3ep_lib_apply','wh3ep_lib_close'})do
  local active=nodes[id];local ax,ay=active:Position();local aw,ah=active:Dimensions()
  assert(tooltip_at(ax+aw/2,ay+ah/2)==active,'panel must not intercept active Verify/Stop: '..id)
 end
 progress:SetVisible(true)
end
assert(nodes.wh3ep_lib_apply.text=='Проверить' and nodes.wh3ep_lib_apply.tooltip:find('продолжить',1,true),'verify must remain readable and explain continuation')
assert(nodes.wh3ep_lib_close.text=='Стоп' and nodes.wh3ep_lib_close.tooltip:find('закрыть',1,true),'stop must remain readable and explain closure')
assert_role_states(nodes.wh3ep_lib_apply,'preview','plain');assert_role_states(nodes.wh3ep_lib_close,'close','plain')
assert(nodes.wh3ep_lib_apply.image_path:find('role_preview_plain_',1,true) and nodes.wh3ep_lib_close.image_path:find('role_close_plain_',1,true),'dynamic captions must use untitled own-role surfaces')
click('wh3ep_lib_apply');assert(apply_calls.resume==1 and not applying,'continue must verify pending operation')
assert(nodes.wh3ep_lib_apply.text=='Предпросмотр' and nodes.wh3ep_lib_apply.image_path:find('role_preview_plain_',1,true),'normal return must restore the catalog caption on a plain surface')
notify({status='complete',completed=0,summary={already=1,missing=2,incompatible=1,no_slot=1,unsupported=2}})
assert(nodes.result_count_3.text:find('Пропуск:',1,true)and not nodes.result_count_3.text:find('…',1,true)and nodes.result_count_3:WidthOfTextLine(nodes.result_count_3.text)<=nodes.result_count_3.w-6,'Russian skipped caption must fit its result row')
assert(nodes.wh3ep_lib_status.tooltip:find('Нет предмета: 2',1,true) and nodes.wh3ep_lib_status.tooltip:find('Несовместимо: 1',1,true),'result needs reasons for skipped positions')
assert(nodes.wh3ep_lib_status.text_width==906,'result reflow must keep the full footer width')
assert(nodes.wh3ep_lib_status.tooltip:find('Нет слота: 1',1,true) and nodes.wh3ep_lib_status.tooltip:find('Не поддерживается: 2',1,true),'all skipped reasons must be represented')
assert(nodes.result_summary.visible and #nodes.result_summary.text>0,'result modal must show complete reasons')
assert(nodes.result_status_strip.visible,'result reasons need a highlighted status strip')
for i=1,3 do
 local icon,label=nodes['result_icon_'..i],nodes['result_count_'..i]
 assert(icon.x==nodes.result_icon_1.x and label.x==nodes.result_count_1.x,'result states must share fixed icon/text columns')
 assert(icon.y+icon.h/2==label.y+label.h/2,'result icons must align to text row centers')
end
for row=1,4 do assert(not nodes['apply_status_art_'..row].visible,'result must hide preview status art')end
click('button_ok',nodes.wh3ep_lib_input_popup.children.button_ok)
assert(not nodes.wh3ep_lib_input_popup.visible,'Done must close result and return to library')
notify({status='complete',completed=0,summary={already=1}});click('button_preview_close',nodes.wh3ep_lib_input_popup.children.button_preview_close)
assert(not priority_lock and not nodes.wh3ep_lib_input_popup.visible and nodes.wh3ep_lib_frame.visible,'themed result close must behave like Done and release native gate')
click('wh3ep_lib_apply');click('button_ok',nodes.wh3ep_lib_input_popup.children.button_ok)
select(44)
assert(apply_calls.cancel==1,'changing target cancels unsent apply steps')
applying,waiting=false,false
assert(nodes.wh3ep_lib_count.template=='ui/templates/wh3ep_label.twui.xml','static labels must not be editable TextInput components')
select(45)
local original_preview=apply.preview
function apply.preview(cqi,preset,take)
 local entries={};for i=1,5 do entries[i]={key='missing_'..i,category='general',status='missing'}end
 entries[2].status='incompatible'
 return{state={target={cqi=cqi},names={},donors={}},entries=entries,actions={},summary={missing=4,incompatible=1},take=take,goal=preset}
end
click('wh3ep_lib_apply')
assert(nodes.apply_detail_1.text:find('Текущее снаряжение сохранится',1,true))
assert(nodes.apply_row_1.text:find('Название недоступно',1,true))
assert(nodes.preview_page.text=='1 / 2')
assert(nodes.apply_icon_1.visible and nodes.apply_icon_1.image_path=='ui/skins/wh3ep/empty_preset.png' and not nodes.apply_placeholder_1.visible,'missing icon needs styled placeholder art, never a stale image')
assert(not nodes.apply_status_art_1.visible and nodes.apply_status_1.visible,'unavailable status must restore native text')
assert(nodes.apply_row_4.visible and not nodes.apply_row_4.text:find('5. ',1,true),'fifth item belongs on next page')
click('button_preview_next',nodes.wh3ep_lib_input_popup.children.button_preview_next)
assert(nodes.preview_page.text=='2 / 2' )
assert(not nodes.apply_row_2.visible and not nodes.apply_status_2.visible and not nodes.apply_detail_2.visible and not nodes.apply_icon_2.visible and not nodes.apply_placeholder_2.visible,'short page must hide reused rows and icons')
click('button_cancel',nodes.wh3ep_lib_input_popup.children.button_cancel)
apply.preview=original_preview

-- Full item/source/replacement names must remain available behind fitted visible text.
local long_item=string.rep('Очень длинное название предмета ',5)
local long_replacement=string.rep('Доспехи невероятно длинного имени ',5)
local long_owner=string.rep('Легендарный владелец ',5)
local starts_before_longtext=apply_calls.start
function apply.preview(cqi,preset,take)
 local first={key='long_item',category='equipment',slot_key='armour',status='free',replacement={key='long_replacement'}}
 local second={key='owned_item',category='equipment',slot_key='weapon',status=take and 'donor'or 'occupied',replacement={key='long_replacement'}}
 if take then second.candidate={owner=43}end
 return{state={target={cqi=cqi},names={long_item=long_item,owned_item=long_item,long_replacement=long_replacement},donors={[43]={name=long_owner}},instances={{key='owned_item',owner=43,category='equipment',slot_key='weapon'}}},entries={first,second},actions=take and {first,second}or {first},summary={free=1,occupied=take and 0 or 1,donor=take and 1 or 0},take=take,goal=preset}
end
click('wh3ep_lib_apply')
if nodes.button_preview_take.state=='selected'then click('button_preview_take',nodes.wh3ep_lib_input_popup.children.button_preview_take)end
assert(nodes.apply_row_1.tooltip==long_item and nodes.apply_row_1.text~=long_item,'long item must fit visibly while retaining the full name tooltip')
assert(nodes.apply_row_1:IsInteractive(),'preview long name needs an actual mouse hit target, not tooltip text on a noninteractive label')
local lx,ly=nodes.apply_row_1:Position()
assert(tooltip_at(lx+80,ly+10)==nodes.apply_row_1,'preview name mouse target must win actual visible sibling hit testing')
assert(nodes.apply_row_1.x+nodes.apply_row_1.w<=nodes.apply_status_1.x,'name tooltip target must not overlap status column')
event('ComponentMouseOn',{component=nodes.apply_row_1,string='apply_row_1'});click('apply_row_1',nodes.apply_row_1);event('ComponentMouseOff',{component=nodes.apply_row_1,string='apply_row_1'})
assert(apply_calls.start==starts_before_longtext,'tooltip hover/click must not start an application')

assert(nodes.apply_detail_1.tooltip:find(long_replacement,1,true),'replacement tooltip must preserve the entire name beyond44 characters')
assert(nodes.apply_detail_2.tooltip:find(long_owner,1,true) and nodes.apply_detail_2.tooltip:find(long_replacement,1,true),'transfer-off tooltip must retain full owner and replacement names')
assert(nodes.apply_detail_2.text:find('перенос выключен',1,true),'disabled transfer must still identify its state')
assert(not nodes.apply_status_art_2.visible and nodes.apply_status_2.visible and nodes.apply_state_icon_2.image_path=='ui/skins/wh3ep/glyph_occupied.png','occupied must show exact original caption instead of native truncation')
assert(nodes.apply_detail_1.font_size==14,'preview detail must use the measured closer14 role')
for row=1,2 do local n=nodes['apply_detail_'..row];assert(n:WidthOfTextLine(n.text)<=n.w,'long detail must fit its original allocation')end
click('button_preview_take',nodes.wh3ep_lib_input_popup.children.button_preview_take)
assert(nodes.apply_detail_2.tooltip:find(long_owner,1,true) and nodes.apply_detail_2.tooltip:find(long_replacement,1,true),'enabled transfer tooltip must retain full owner and replacement names')
assert(not nodes.apply_status_art_2.visible and nodes.apply_status_2.visible,'reused donor row must restore dynamic native status and hide fixed sprite')
assert(nodes.apply_detail_2.text:find('Заменит:',1,true) and nodes.apply_detail_2.text:find('Дос',1,true),'enabled transfer must keep replacement action meaningful in the visible detail')
assert(nodes.apply_detail_2:WidthOfTextLine(nodes.apply_detail_2.text)<=nodes.apply_detail_2.w,'enabled transfer detail must fit after owner/replacement ellipsis')
click('button_preview_take',nodes.wh3ep_lib_input_popup.children.button_preview_take)
assert(not nodes.apply_status_art_2.visible and nodes.apply_status_2.visible,'returning to transfer-off must restore fixed occupied caption')
assert(apply_calls.start==starts_before_longtext,'long-name preview and transfer toggles must not issue commands')
click('button_cancel',nodes.wh3ep_lib_input_popup.children.button_cancel)
apply.preview=original_preview

-- Native0.7.11 report: a truncated follower on page3 had no tooltip target.
local long_follower='Мастер по обслуживанию артиллерии с полным длинным названием'
function apply.preview(cqi,preset,take)
 local entries,names={},{}
 for i=1,9 do local key='follower_'..i;entries[i]={key=key,category='general',status='free'};names[key]=long_follower..' '..i end
 return{state={target={cqi=cqi},names=names,instances={}},entries=entries,actions=entries,summary={free=9},take=take,goal=preset}
end
local tooltip_starts=apply_calls.start
click('wh3ep_lib_apply');click('button_preview_next',nodes.button_preview_next);click('button_preview_next',nodes.button_preview_next)
local follower_label=nodes.apply_row_1;local fx,fy=follower_label:Position()
assert(follower_label.tooltip==long_follower..' 9'and follower_label.text~=follower_label.tooltip,'page3 must refresh the entire follower tooltip, retaining visible fitting')
assert(tooltip_at(fx+80,fy+10)==follower_label,'long follower tooltip must be mouse reachable after page reuse')
assert(not nodes.apply_row_2:Visible(true)and not nodes.apply_row_3:Visible(true),'absent reused rows must not expose stale tooltip targets')
event('ComponentMouseOn',{component=follower_label});click('apply_row_1',follower_label);event('ComponentMouseOff',{component=follower_label})
assert(apply_calls.start==tooltip_starts,'follower tooltip interactions must not issue commands')
click('button_preview_previous',nodes.button_preview_previous);assert(nodes.apply_row_1.tooltip==long_follower..' 5','previous page must replace the tooltip source')
click('button_cancel',nodes.button_cancel);assert(not follower_label:Visible(true),'closed preview must remove its tooltip hit target')
apply.preview=original_preview

-- One physical status row must switch between exact art and every native-only state.
local reuse_status='already'
function apply.preview(cqi,preset,take)
 local item=reuse_status and {key='reuse',category='equipment',slot_key='weapon',status=reuse_status,candidate={owner=43}}or nil
 local entries=item and {item}or {};local actions=(reuse_status=='free'or reuse_status=='donor')and entries or {}
 return{state={target={cqi=cqi},names={reuse='Предмет'},donors={[43]={name='Владелец'}},instances={{key='reuse',owner=43,category='equipment',slot_key='weapon'}}},entries=entries,actions=actions,summary=reuse_status and {[reuse_status]=1}or {},take=take,goal=preset}
end
click('wh3ep_lib_apply')
local expected_state_glyph={already='already',free='free',occupied='occupied',donor='donor',missing='missing',incompatible='incompatible',unsupported='unsupported',no_slot='no_slot'}
for _,state in ipairs({'already','free','occupied','donor','missing','incompatible','unsupported','no_slot'})do
 reuse_status=state;click('button_preview_take',nodes.wh3ep_lib_input_popup.children.button_preview_take)
 assert(not nodes.apply_status_art_1.visible and nodes.apply_status_1.visible,'status caption and glyph must survive reuse: '..state)
 assert(nodes.apply_state_icon_1.visible and nodes.apply_state_icon_1.w>0,'every status has a visible glyph')
 assert(nodes.apply_state_icon_1.image_path=='ui/skins/wh3ep/glyph_'..expected_state_glyph[state]..'.png','status needs its own meaningful game-style symbol: '..state)
end
reuse_status=nil;click('button_preview_take',nodes.wh3ep_lib_input_popup.children.button_preview_take)
assert(not nodes.apply_status_art_1.visible and not nodes.apply_status_1.visible,'empty reused status row must hide both representations')
click('button_cancel',nodes.wh3ep_lib_input_popup.children.button_cancel);apply.preview=original_preview

-- Terminal reports must show confirmed work and a reason, never planned success counts.
click('wh3ep_lib_apply');click('button_ok',nodes.wh3ep_lib_input_popup.children.button_ok);applying,waiting=false,false
local terminal_starts=apply_calls.start
for _,terminal in ipairs({'not_applied','inventory_changed','error'})do
 notify({status=terminal,completed=1,summary={already=99,free=99,donor=99,missing=99},code='engine_error'})
 assert(nodes.wh3ep_lib_input_popup.visible and nodes.panel_title.text=='Применение остановлено','terminal state must open an honest result')
 assert(nodes.result_icon_1.image_path=='ui/skins/wh3ep/glyph_equipped.png'and nodes.result_icon_2.image_path=='ui/skins/wh3ep/state_warning.png'and nodes.result_icon_3.image_path=='ui/skins/wh3ep/glyph_missing.png','stopped result rows need confirmed, warning and recheck glyphs')
 assert(nodes.result_count_1.text:find('1',1,true)and not nodes.result_count_2.text:find('99',1,true)and not nodes.result_summary.text:find('99',1,true),'terminal result must use confirmed count, not initial planned summary')
 assert(nodes.result_summary.tooltip and #nodes.result_summary.tooltip>0,'terminal result must explain its reason')
 click('button_ok',nodes.wh3ep_lib_input_popup.children.button_ok)
end
click('wh3ep_lib_close');notify({status='error',completed=1,summary={}})
assert(not nodes.wh3ep_lib_input_popup.visible,'hidden library must not resurrect a result')
click('wh3ep_lib_open');click('wh3ep_lib_save');notify({status='error',completed=1,summary={}})
assert(nodes.panel_title.text=='Имя нового пресета','terminal report must not replace another modal')
click('button_cancel',nodes.wh3ep_lib_input_popup.children.button_cancel)
select(44);notify({status='error',completed=1,summary={}});assert(not nodes.wh3ep_lib_input_popup.visible,'old-target terminal callback must not open a result on another character');select(45)
assert(apply_calls.start==terminal_starts,'terminal presentation cannot issue another command')

-- Both logical surfaces fit the library, footer, card and full preview inside their frames.
for _,surface in ipairs({{1920,1080},{1280,720}})do
 viewport_width,viewport_height=surface[1],surface[2]
 event('PanelClosedCampaign',{string='character_details_panel'})
 event('PanelOpenedCampaign',{string='character_details_panel'});click('wh3ep_lib_open')
 local frame=nodes.wh3ep_lib_frame
 for _,id in ipairs({'wh3ep_lib_save','wh3ep_lib_apply','wh3ep_lib_close','wh3ep_lib_status','wh3ep_lib_card','wh3ep_lib_favorite'})do
  local component=nodes[id]
  assert(component.x>=frame.x and component.y>=frame.y and component.x+component.w<=frame.x+frame.w and component.y+component.h<=frame.y+frame.h,'library geometry out of bounds: '..id)
 end
 assert(nodes.wh3ep_lib_card_count.y+nodes.wh3ep_lib_card_count.h<=nodes.wh3ep_lib_rename.y,'counter must not overlap CRUD at compact height')
 assert(nodes.wh3ep_lib_next.y+nodes.wh3ep_lib_next.h<=nodes.wh3ep_lib_save.y,'paging and footer must not overlap')
 assert(nodes.wh3ep_lib_save.y+nodes.wh3ep_lib_save.h<=nodes.wh3ep_lib_status.y,'footer actions and status must not overlap')
 click('wh3ep_lib_apply')
 for row=1,4 do local y=({174,257,340,424})[row];local scale=nodes.wh3ep_lib_input_popup.w/660;assert(math.abs(nodes['apply_icon_frame_'..row].y-(nodes.wh3ep_lib_input_popup.y+y*scale))<0.01,'preview frame source anchor mismatch');assert(math.abs(nodes['apply_separator_'..row].y-(nodes.wh3ep_lib_input_popup.y+(y+80)*scale))<0.01,'preview separator source anchor mismatch')end
 assert(nodes.button_preview_take.w<=40 and nodes.button_preview_take.text=='','donor checkbox must be a square glyph without resizing text')
 assert(nodes.preview_take_label and nodes.preview_take_label.visible,'donor toggle needs a separate caption')
 local dialog=nodes.wh3ep_lib_input_popup
 assert(dialog.y>=0 and dialog.y+dialog.h<=viewport_height,'preview must fit viewport vertically')
 assert(nodes.apply_detail_4.y+nodes.apply_detail_4.h<=nodes.button_preview_take.y,'rows must not overlap donor toggle')
 assert(nodes.button_ok.y+nodes.button_ok.h<=dialog.y+dialog.h,'confirm must fit dialog')
 click('button_cancel',dialog.children.button_cancel)
end
viewport_width,viewport_height=1920,1080

-- Native failures must expose a useful location without echoing private error text.
local diagnostics={}
local previous_log=ModLog
ModLog=function(value)diagnostics[#diagnostics+1]=value;if value=='[WH3EP] library_ui_lua_error'then ui_errors=ui_errors+1 end end
local original_find=string.find
string.find=function(subject,pattern,start,plain)
 assert(plain==nil,'native find accepts only three arguments')
 return original_find(subject,pattern,start,true)
end
string.find_lua=original_find
model.list=function()error('PRIVATE_PATH_MARKER:27: attempt to call a nil value',0)end
click('wh3ep_lib_filter');click('wh3ep_lib_filter_option_matching')
string.find=original_find
local diagnostic_text=table.concat(diagnostics,'\n')
assert(diagnostic_text:find('library_ui_error_line=27',1,true),'native error line must be diagnosed')
assert(diagnostic_text:find('library_ui_error_kind=call',1,true),'native error kind must be diagnosed')
assert(not diagnostic_text:find('PRIVATE_PATH_MARKER',1,true),'raw exception text must remain private')
assert(ui_errors==1,'the injected failure must be caught once')
assert(nodes.wh3ep_lib_open.text=='Ошибка' and nodes.wh3ep_lib_open.tooltip:find('журнале',1,true),'faulted entry needs compact caption and detailed tooltip')
print('PASS: safe native error diagnostics preserve line/kind and omit raw error text')
assert(not nodes.wh3ep_lib_frame.visible,'a failed panel must close before accepting more native clicks')
background_slot:MoveTo(nodes.wh3ep_lib_frame.x+5,nodes.wh3ep_lib_frame.y+300);background_slot:Resize(10,10);background_slot:SetVisible(true)
assert(tooltip_at(background_slot.x+5,background_slot.y+5)==background_slot,'fault cleanup must release background mouse hits instead of leaving a shield')
background_slot:SetVisible(false)
local captures_before_fault=captures
click('wh3ep_lib_save_class');click('wh3ep_lib_save')
assert(captures==captures_before_fault,'a failed UI must reject further actions')

-- Use the real controller through the real UI, including close/reopen and UI fault.
local equipment_fixture=assert(loadfile('tests/fixtures/equipment.lua'))()
local function real_apply_ui()
 nodes,listeners={},{};root=node('root');panel=node('character_details_panel',root)
 node('character_context_parent',panel)
 local actual_model=assert(loadfile('src/wh3ep_model.lua'))()
 local data={}
 local actual_storage=assert(loadfile('src/wh3ep_storage.lua'))()(actual_model,json,{read=function(k)return data[k]end,write=function(k,v)data[k]=v end})
 local snapshot={faction_key='f',class_key='a',character_kind='lord',equipment={{slot_key='weapon',item_key='sword'},{slot_key='armor',item_key='armor'}},followers={}}
 assert(actual_storage.save(assert(actual_model.add(actual_model.new(),snapshot,'Набор','a')),0))
 local app,world=equipment_fixture.fixture({equipment_fixture.gear('sword',2),equipment_fixture.gear('armor',0,'armor')})
 local actual_ui=create_ui(actual_model,actual_storage,{apply=app,describe=function(cqi)if cqi==1 then return{cqi=1,faction_key='f',class_key='a',character_kind='lord'}end end,capture=function()return snapshot end})
 actual_ui.start();select(1);event('PanelOpenedCampaign',{string='character_details_panel'});click('wh3ep_lib_open');click('wh3ep_lib_apply');assert(nodes.apply_detail_1.text:find('Hero',1,true)and nodes.apply_detail_1.text:find('перенос выключен',1,true)and world.commands==0,'disabled transfer preview must identify owner without issuing commands');click('button_preview_take',nodes.wh3ep_lib_input_popup.children.button_preview_take);click('button_cancel',nodes.wh3ep_lib_input_popup.children.button_cancel)
 return app,world
end
local actual_app,actual_world=real_apply_ui()
click('wh3ep_lib_apply');click('button_ok',nodes.wh3ep_lib_input_popup.children.button_ok)
assert(actual_app.waiting()and actual_world.commands==1)
click('wh3ep_lib_close');event('PanelClosedCampaign',{string='character_details_panel'})
event('PanelOpenedCampaign',{string='character_details_panel'});click('wh3ep_lib_open')
actual_world.confirm();click('wh3ep_lib_apply')
assert(not actual_app.busy()and actual_world.commands==1 and actual_app.report().status=='cancelled','reopened UI must verify issued donor command without advancing cancelled queue')
actual_app,actual_world=real_apply_ui()
click('wh3ep_lib_apply')
function nodes.wh3ep_lib_status:SetText()error('PRIVATE_UI_LIFECYCLE_MARKER',0)end
click('button_ok',nodes.wh3ep_lib_input_popup.children.button_ok)
assert(actual_app.waiting()and actual_world.commands==1,'fault must retain verification barrier for already-issued command')
actual_world.confirm()
-- Simulate native parent recreation after closing the character panel.
panel.children={}
event('PanelClosedCampaign',{string='character_details_panel'})
event('PanelOpenedCampaign',{string='character_details_panel'})
local recovery=assert(panel.children.wh3ep_lib_open,'faulted UI must recreate a verification-only entry')
assert(recovery.text=='Проверить' and recovery.tooltip:find('перенос',1,true),'recovery must keep instructions in tooltip, not overflow caption')
click('wh3ep_lib_open',recovery)
assert(recovery.text=='Проверено' and recovery.tooltip:find('Перезапустите',1,true),'verified recovery needs a compact result and full next-step instruction')
assert(not actual_app.busy()and actual_world.commands==1 and actual_app.report().status=='cancelled','fault recovery must only verify and stop')
assert(not table.concat(diagnostics,'\n'):find('PRIVATE_UI_LIFECYCLE_MARKER',1,true),'native UI exception text must remain private')
-- A stable root owns the native lock; losing the character subtree must not strand it.
actual_app,actual_world=real_apply_ui();click('wh3ep_lib_apply')
assert(nodes.button_preview_previous.template=='ui/templates/wh3ep_primary.twui.xml' and nodes.button_preview_next.template=='ui/templates/wh3ep_primary.twui.xml','active preview pagination must use original cyan skin')
assert(nodes.button_preview_previous.state=='inactive','first-page previous must remain disabled')
assert(nodes.wh3ep_lib_input_popup.image_path=='ui/skins/wh3ep/en_preview_panel_titled.png' and nodes.panel_title.visible,'preview must use clean art and its native catalog heading')
assert(nodes.apply_detail_1.template=='ui/templates/wh3ep_preview_detail.twui.xml','preview detail must have an independent readable role')
assert(nodes.preview_subtitle.template=='ui/templates/wh3ep_preview_ribbon.twui.xml' and nodes.preview_subtitle.font_size==16,'preview needs the larger original ribbon role independent of result')
assert(nodes.apply_status_1.font_size==14 and nodes.apply_status_1.w==178,'preview status needs its dedicated measured role/allocation')
assert(nodes.apply_status_1:WidthOfTextLine(nodes.apply_status_1.text)<=nodes.apply_status_1.w and nodes.apply_status_1.tooltip~='', 'status caption stays within its safe column and retains tooltip')
local modal_before_close=nodes.wh3ep_lib_input_popup
assert(priority_lock and priority_lock.owner==root and not nodes.wh3ep_lib_frame.visible)
assert(entry_timer);entry_timer();assert(not nodes.wh3ep_lib_open.visible,'layout tick must not reveal entry over modal')
event('PanelClosedCampaign',{string='character_details_panel'})
assert(not priority_lock and not modal_before_close.topmost and not modal_before_close.visible and actual_world.commands==0,'native panel close must release modal lock/topmost without commands')
actual_app,actual_world=real_apply_ui();click('wh3ep_lib_apply')
function nodes.preview_take_label:SetText()error('PRIVATE_MODAL_FAULT',0)end
click('button_preview_take',nodes.wh3ep_lib_input_popup.children.button_preview_take)
assert(not priority_lock and not nodes.wh3ep_lib_input_popup.topmost and not nodes.wh3ep_lib_input_popup.visible and not nodes.wh3ep_lib_frame.visible and actual_world.commands==0,'modal render fault must release native locks and stop before issuing commands')
assert(not nodes.wh3ep_lib_open.visible and nodes.wh3ep_lib_open.text=='Ошибка','faulted non-recovery entry must remain hidden')
if entry_timer then entry_timer()end;assert(not nodes.wh3ep_lib_open.visible,'faulted polling must not reveal normal entry')
event('PanelClosedCampaign',{string='character_details_panel'});assert(not entry_timer,'faulted close must still remove entry timer')
-- An SDK failure while measuring a new subtree must never leave the previous entry visible.
actual_app,actual_world=real_apply_ui();click('wh3ep_lib_close')
local broken_holder=node('equipment_holder',node('character_details_subpanel',node('tab_panels',node('character_context_parent',panel))))
broken_holder:MoveTo(1200,150);broken_holder:Resize(642,682)
local broken_child=node('native_unavailable_geometry',broken_holder)
function broken_child:Dimensions()error('PRIVATE_NATIVE_GEOMETRY_FAILURE',0)end
event('PanelOpenedCampaign',{string='character_details_panel'})
assert(not nodes.wh3ep_lib_open.visible and actual_world.commands==0,'failed native geometry must hide entry rather than retain an unchecked old rectangle')
print('PASS: real apply-controller close/reopen and verification-only recovery after UI fault')
-- Native details portraits change their CCO without a map CharacterSelected event.
nodes,listeners={},{};root=node('root');panel=node('character_details_panel',root)
local native_context=node('character_context_parent',panel)
local target_data={}
local target_model=assert(loadfile('src/wh3ep_model.lua'))()
local target_storage=assert(loadfile('src/wh3ep_storage.lua'))()(target_model,json,{read=function(k)return target_data[k]end,write=function(k,v)target_data[k]=v end})
local target_snapshot={faction_key='test_faction',class_key='class_a',character_kind='lord',equipment={{slot_key='weapon',item_key='test_sword'}},followers={}}
assert(target_storage.save(assert(target_model.add(target_model.new(),target_snapshot,'Shared target test','')),0))
local preview_target,capture_target,start_count=nil,nil,0
local target_apply={busy=function()return false end,waiting=function()return false end,cancel=function()end,
 preview=function(cqi,preset,take)preview_target=cqi;return apply.preview(cqi,preset,take)end,
 start=function()start_count=start_count+1;return true end}
local target_ui=create_ui(target_model,target_storage,{describe=describe,apply=target_apply,capture=function(cqi)capture_target=cqi;return capture(cqi)end})
target_ui.start();select(42);event('PanelOpenedCampaign',{string='character_details_panel'})
native_panel_cqi=44 -- Portrait-only switch to hero; map selection remains lord42.
click('wh3ep_lib_open');click('wh3ep_lib_apply')
assert(preview_target==44,'portrait-only hero switch must preview the displayed character, never stale map selection')
native_panel_cqi=42 -- Switch after preview was built; stale apply must not start.
click('button_ok',nodes.wh3ep_lib_input_popup.children.button_ok)
assert(start_count==0 and not priority_lock,'changed native context must cancel stale apply and release own modal')
click('wh3ep_lib_open');click('wh3ep_lib_save')
assert(capture_target==42,'save must capture the displayed character')
local before_target_write=target_storage.load()
native_panel_cqi=44
input('Must not save stale snapshot')
local after_target_write=target_storage.load()
assert(after_target_write.library_revision==before_target_write.library_revision,'portrait switch during create must prevent stale snapshot write')
click('wh3ep_lib_open');click('wh3ep_lib_apply')
assert(preview_target==44,'reopen after target rejection must bind current hero')
native_context.context_missing=true
click('button_ok',nodes.wh3ep_lib_input_popup.children.button_ok)
assert(start_count==0 and not priority_lock,'missing panel context during confirm must fail closed')
for _,value in ipairs({false,0,-1,1.5,'44',math.huge})do
 native_context.context_missing=false;native_panel_cqi=value
 click('wh3ep_lib_open')
 assert(not nodes.wh3ep_lib_frame.visible,'invalid CQI must not reopen stale library')
end
native_panel_cqi=44;native_context.context_missing=true;click('wh3ep_lib_open')
assert(not nodes.wh3ep_lib_frame.visible,'missing context must not fall back to map selection')
native_context.context_missing=false;native_context.context_error=true;click('wh3ep_lib_open')
assert(not nodes.wh3ep_lib_frame.visible,'context query error must fail closed')
native_context.context_error=false
local saved_huge=math.huge;math.huge=nil -- CA runtime does not expose math.huge.
click('wh3ep_lib_open');assert(nodes.wh3ep_lib_frame.visible,'valid CQI must work without native math.huge');click('wh3ep_lib_close');math.huge=saved_huge
assert(not nodes.wh3ep_lib_frame.visible,'valid context must remain usable after a failed query')
print('PASS: displayed character context binds preview/capture, rejects stale apply/write and fails closed without stale map fallback')
for _,next_target in ipairs({44,false,'error'})do
 nodes,listeners={},{};root=node('root');panel=node('character_details_panel',root);node('character_context_parent',panel)
 local queue_data={}
 local queue_storage=assert(loadfile('src/wh3ep_storage.lua'))()(target_model,json,{read=function(k)return queue_data[k]end,write=function(k,v)queue_data[k]=v end})
 local queue_snapshot={faction_key='f',class_key='a',character_kind='lord',equipment={{slot_key='weapon',item_key='sword'},{slot_key='armor',item_key='armor'}},followers={}}
 assert(queue_storage.save(assert(target_model.add(target_model.new(),queue_snapshot,'Two free items','a')),0))
 local queue_app,queue_world=equipment_fixture.fixture({equipment_fixture.gear('sword',0),equipment_fixture.gear('armor',0,'armor')})
 local queue_ui=create_ui(target_model,queue_storage,{apply=queue_app,describe=function(cqi)if cqi==1 then return{cqi=1,faction_key='f',class_key='a',character_kind='lord'}end end})
 queue_ui.start();select(1);event('PanelOpenedCampaign',{string='character_details_panel'});click('wh3ep_lib_open');click('wh3ep_lib_apply')
 click('button_ok',nodes.wh3ep_lib_input_popup.children.button_ok)
 assert(queue_world.commands==1,'first command must be issued before scheduled verification')
 native_panel_cqi=next_target;nodes.character_context_parent.context_error=next_target=='error';queue_world.drain()
 assert(queue_world.commands==1 and not queue_app.busy()and queue_app.report().status=='cancelled','portrait-only switch or missing context between callbacks must verify issued work and stop before second command')
 assert(not nodes.wh3ep_lib_frame.visible,'stale queue UI must close')
end
print('PASS: real asynchronous free-item queue stops on displayed-context change/loss before further commands')
actual_app,actual_world=real_apply_ui();click('wh3ep_lib_apply');click('button_ok',nodes.wh3ep_lib_input_popup.children.button_ok)
assert(actual_app.waiting()and actual_world.commands==1)
native_panel_cqi=false;click('wh3ep_lib_apply')
assert(actual_app.waiting()and not nodes.wh3ep_lib_frame.visible,'context loss must cancel queue while retaining issued donor verification')
actual_world.confirm();native_panel_cqi=1;click('wh3ep_lib_open');click('wh3ep_lib_apply')
assert(not actual_app.busy()and actual_world.commands==1 and actual_app.report().status=='cancelled','restored context must permit verification only, never a second command')
assert(nodes.wh3ep_lib_frame.visible and nodes.wh3ep_lib_status.text=='Очередь остановлена. Уже надетые предметы оставлены.','verified cancellation must refresh recovered UI status')
print('PASS: donor recovery after native-context loss verifies issued command and displays cancellation without advancing queue')
-- The full preset card must show both categories without overflow or writes.
do
 local model=assert(loadfile('src/wh3ep_model.lua'))()
 local equipment,followers,names,icons={},{},{},{}
 for i=1,8 do
  equipment[i]={slot_key='fixture_slot_'..i,item_key='gear_'..i};followers[i]='follower_'..i
  names['gear_'..i]='Equipment '..i;names[followers[i]]='Follower '..i
  icons['gear_'..i]='ui/skins/default/equipment_items_weapon.png'
  icons[followers[i]]='ui/campaign ui/ancillaries/wh3_main_anc_cathay_lord.png'
 end
 for _,surface in ipairs({{1920,1080},{1280,720}})do
  viewport_width,viewport_height=surface[1],surface[2]
  for _,counts in ipairs({{6,6},{5,6},{7,8},{1,0},{0,6},{0,0}})do
   nodes,listeners={},{};root=node('root');panel=node('character_details_panel',root)
   local holder=node('equipment_holder',node('character_details_subpanel',node('tab_panels',node('character_context_parent',panel))))
   holder:MoveTo(viewport_width-642,150);holder:Resize(642,682)
   local data={};local st=assert(loadfile('src/wh3ep_storage.lua'))()(model,json,{read=function(k)return data[k]end,write=function(k,v)data[k]=v end})
   local snap={faction_key='fixture',class_key='miao',character_kind='lord',equipment={},followers={}}
   for i=1,counts[1]do snap.equipment[i]=equipment[i]end
   for i=1,counts[2]do snap.followers[i]=followers[i]end
   local lib=assert(model.add(model.new(),snap,string.rep('W',64),'miao'));lib.library_revision=1;assert(st.save(lib,0))
   local desc=function()return{cqi=42,faction_key='fixture',class_key='miao',character_kind='lord',name='Miao Ying'}end
   local app={busy=function()return false end,waiting=function()return false end,cancel=function()end,preview=function()error('card must stay read-only')end}
   local fixture=create_ui(model,st,{describe=desc,capture=function()return snap end,inspect=function()return{names=names,icons=icons}end,apply=app})
   fixture.start();select(42);event('PanelOpenedCampaign',{string='character_details_panel'});click('wh3ep_lib_open')
   local card=nodes.wh3ep_lib_card;local revision=st.load().library_revision
   assert(nodes.wh3ep_lib_card_scope.y+nodes.wh3ep_lib_card_scope.h<=nodes.card_divider.y,'scope caption clears divider on compact cards')
   assert(not nodes.card_heading_icon.visible or nodes.card_heading_icon.y+nodes.card_heading_icon.h<=nodes.card_divider.y,'heading icon clears divider')
   if nodes.card_heading_icon.visible then
    local frame,icon=nodes.card_heading_frame,nodes.card_heading_icon
    assert(icon.x>=frame.x and icon.y>=frame.y and icon.x+icon.w<=frame.x+frame.w and icon.y+icon.h<=frame.y+frame.h,'preset archetype stays inside its rarity frame')
    assert(math.abs((icon.x+icon.w/2)-(frame.x+frame.w/2))<=0.5 and math.abs((icon.y+icon.h/2)-(frame.y+frame.h/2))<=0.5,'preset archetype stays centered in its rarity frame')
   end
   assert(nodes.card_divider.y+nodes.card_divider.h<=nodes.card_icon_frame_1.y,'divider clears grid')
   local columns=math.max(6,counts[1],counts[2]);local gap=columns==6 and 8 or 4
   local size=math.min(56,math.floor((378-(columns-1)*gap)/columns))
   local shown=0
   for i=1,columns*2 do
    local row=math.floor((i-1)/columns);local col=(i-1)%columns
    local key=row==0 and snap.equipment[col+1]and snap.equipment[col+1].item_key or row==1 and snap.followers[col+1]or nil
    local icon,slot=nodes['card_icon_'..i],nodes['card_icon_frame_'..i]
    assert(icon and slot,'full card requires every category slot')
    local placeholder=counts[1]==0 and counts[2]==0 and i==1
    assert(icon.visible==(key~=nil or placeholder)and slot.visible==(key~=nil or placeholder),'category positions must survive partial or empty presets: '..i..' '..tostring(key)..' '..tostring(icon.visible)..' '..tostring(slot.visible))
    assert(slot.w==size and slot.h==size and icon.w==size-8 and icon.h==size-8,'calculated slot and icon sizes')
    assert(slot.x>=card.x and slot.x+slot.w<=card.x+card.w and slot.y>=card.y,'grid stays inside card')
    assert(slot.y+slot.h<=nodes.wh3ep_lib_card_count.y,'grid must clear counter')
    if col>0 then local previous=nodes['card_icon_frame_'..(i-1)];assert(slot.x-previous.x==size+gap and slot.x>=previous.x+previous.w,'category columns must not overlap')end
    if row==1 then local above=nodes['card_icon_frame_'..(i-columns)];assert(slot.y-above.y==size+8 and slot.y>=above.y+above.h,'category rows must not overlap')end
    if placeholder then
     assert(icon.image_path=='ui/skins/wh3ep/empty_preset.png'and icon.tooltip==wh3ep_locale_ru.empty_loadout,'empty presets need a styled placeholder')
     assert(icon:IsInteractive(),'empty preset placeholder must keep its explanatory tooltip');click(icon.id);assert(st.load().library_revision==revision,'placeholder clicks must not mutate presets')
    end
    if key then
     shown=shown+1
     assert(icon.image_path==(row==0 and 'ui/skins/wh3ep/stock_weapon.png'or icons[key])and icon.tooltip==names[key],'every item has its own icon and full name')
     assert(icon:IsInteractive(),'compact icons must receive their name tooltips')
     assert_image_centered(icon,row==0)
     click(icon.id);assert(st.load().library_revision==revision,'icon clicks must not mutate presets')
    end
   end
   assert(shown==counts[1]+counts[2],'every stored item must remain visible')
   assert(not nodes.card_overflow and not nodes.card_overflow_frame,'full card must not collapse items into ellipsis')
   assert(nodes.wh3ep_lib_card_count.y+nodes.wh3ep_lib_card_count.h<=nodes.wh3ep_lib_rename.y,'counter clears buttons at compact height')
   if os.getenv('WH3EP_UI_CAPTURE')and counts[1]==6 and counts[2]==6 then
    local out={};for _,n in pairs(nodes)do
     if n:Visible(true)and n.template and n.x and n.w then out[#out+1]={id=n.id,template=n.template,x=n.x,y=n.y,w=n.w,h=n.h,text=n.text,state=n.state or 'active',image=n.image_path,image_size=n.image_size,image_offset=n.image_offset,image_dock=n.image_dock,priority=n.priority or 0,order=n.order}end
    end
    local file=assert(io.open(os.getenv('WH3EP_UI_CAPTURE')..'/library-full12-'..surface[1]..'.json','wb'));file:write(assert(json.encode(out)));file:close()
   end
   if counts[1]==6 and counts[2]==6 then
    local empty=assert(model.update(st.load(),'fixture',lib.factions.fixture.presets[1].id,{equipment={},followers={}}));assert(st.save(empty,revision))
    click('wh3ep_lib_close');click('wh3ep_lib_open')
    for i=1,12 do assert(nodes['card_icon_'..i].visible==(i==1)and nodes['card_icon_frame_'..i].visible==(i==1),'empty preset must retain only its placeholder after clearing items')end
    local partial=assert(model.update(st.load(),'fixture',lib.factions.fixture.presets[1].id,{followers={followers[1]}}));assert(st.save(partial,empty.library_revision))
    click('wh3ep_lib_close');click('wh3ep_lib_open')
    for i=1,12 do assert(nodes['card_icon_'..i].visible==(i==7),'reused card keeps a follower in its category row without stale gear')end
   end
   if counts[1]==7 and counts[2]==8 then
    local normal={};local companions={};for i=1,6 do normal[i]=equipment[i];companions[i]=followers[i]end
    local updated=assert(model.update(st.load(),'fixture',lib.factions.fixture.presets[1].id,{equipment=normal,followers=companions}))
    assert(st.save(updated,revision));click('wh3ep_lib_close');click('wh3ep_lib_open')
    for i=1,16 do
     assert(nodes['card_icon_'..i].visible==(i<=12)and nodes['card_icon_frame_'..i].visible==(i<=12),'7+8 to6+6 reuse must hide every extra slot: '..i..' icon='..tostring(nodes['card_icon_'..i].visible)..' frame='..tostring(nodes['card_icon_frame_'..i].visible))
     if i<=12 then
      local key=i<=6 and equipment[i].item_key or followers[i-6]
      assert(nodes['card_icon_'..i].tooltip==names[key]and nodes['card_icon_'..i].w==48,'normal category positions and icon sizes must be restored')
     end
    end
   end
  end
 end
 viewport_width,viewport_height=1920,1080
 print('PASS: 6+6, 5+6, 7+8, partial and empty cards fit both surfaces, preserve every item and clear reused slots')
end
-- Optional offline visual fixture: actual controller positions, templates and states.
do
 nodes,listeners={},{};root=node('root');panel=node('character_details_panel',root)
 local catalog={};for key,value in pairs(wh3ep_locale_ru)do catalog[key]=value end
 catalog.button_save='Из каталога';catalog.library_title='Проверка каталога'
 local localized=wh3ep_localization_factory({ru=catalog,eng=wh3ep_locale_eng},function()return 'RU'end)
 local memory={}
 local st=assert(loadfile('src/wh3ep_storage.lua'))()(model,json,{read=function(k)return memory[k]end,write=function(k,v)memory[k]=v end})
 local anchor=node('equipment_holder',node('character_details_subpanel',node('tab_panels',node('character_context_parent',panel))))
 anchor:MoveTo(1180,150);anchor:Resize(642,682)
 local fixture=create_ui(model,st,{describe=describe,capture=capture},localized)
 fixture.start();select(42);event('PanelOpenedCampaign',{string='character_details_panel'});click('wh3ep_lib_open')
 assert(nodes.wh3ep_lib_title.text==catalog.library_title and nodes.wh3ep_lib_title.visible,'Russian heading overrides must be displayed directly from the catalog')
 local button=nodes.wh3ep_lib_save
 for _,state in ipairs({'active','hover','down','down_off','inactive','selected','selected_hover','selected_down','selected_down_off'})do
  button:SetState(state)
  assert(button.text==catalog.button_save and button.image_path:find('role_save_plain_',1,true),'Russian catalog edits must change every visible button state without baked text')
  assert(button:WidthOfTextLine(button.text)<=button.w,'native Russian caption must fit its control')
 end
 print('PASS: Russian catalog overrides drive live heading and all nine native button states')
end
-- Never included in the game bundle. Values are synthetic and use extracted game glyphs.
if os.getenv('WH3EP_UI_CAPTURE')then
 nodes,listeners={},{};root=node('root');panel=node('character_details_panel',root)
 local m=assert(loadfile('src/wh3ep_model.lua'))();local data={}
 local st=assert(loadfile('src/wh3ep_storage.lua'))()(m,json,{read=function(k)return data[k]end,write=function(k,v)data[k]=v end})
 local snap={faction_key='fixture',class_key='miao',character_kind='lord',equipment={{slot_key='weapon',item_key='sword'},{slot_key='armour',item_key='armour'},{slot_key='talisman',item_key='stone'},{slot_key='enchanted_item',item_key='potion'},{slot_key='arcane_item',item_key='staff'}},followers={'messenger','steward','lion','sage','groom','master'}}
 local lib=m.new();for i,name in ipairs({'Боевой комплект','Походный комплект','Магическая защита','Караван'})do
 local example=snap
 if i==2 then example={faction_key=snap.faction_key,class_key=snap.class_key,character_kind='lord',equipment={snap.equipment[2],snap.equipment[3]},followers={'groom'}}end
 if i==3 then example={faction_key=snap.faction_key,class_key=snap.class_key,character_kind='lord',equipment={snap.equipment[5],snap.equipment[3]},followers={'sage'}}end
 if i==4 then example={faction_key=snap.faction_key,class_key=snap.class_key,character_kind='lord',equipment={},followers={'messenger','steward'}}end
 lib=assert(m.add(lib,example,name,i==4 and ''or 'miao'))
end
 lib=assert(m.update(lib,'fixture',lib.factions.fixture.presets[1].id,{favorite=true}));lib.library_revision=1;assert(st.save(lib,0))
 local names={sword='Меч Битвы',armour='Зачарованный щит',stone='Камень удачи',potion='Зелье скорости',staff='Посох энергии',messenger='Гонец',steward='Городской распорядитель',lion='Заклинатель нефритовых львов',sage='Древний мудрец',groom='Конюх',master='Мастер по обслуживанию Стражей'}
 local icons={};for key in pairs(names)do icons[key]='ui/skins/default/equipment_items_weapon.png'end
 for _,key in ipairs(snap.followers)do icons[key]='ui/campaign ui/ancillaries/wh3_main_anc_cathay_lord.png'end
 icons.potion='ui/skins/default/equipment_items_enchanted.png';icons.staff='ui/skins/default/equipment_items_arcane.png';icons.armour='ui/skins/default/equipment_items_armour.png';icons.stone='ui/skins/default/equipment_items_talisman.png'
 local desc=function()return{cqi=42,faction_key='fixture',class_key='miao',character_kind='lord',name='Мяо Инь'}end
 local app={busy=function()return false end,waiting=function()return false end,cancel=function()end}
 function app.preview(cqi,preset,take)
  local entries,actions={},{};local keys={};for _,v in ipairs(preset.equipment)do keys[#keys+1]={v.item_key,v.slot_key,'equipment'}end;for _,k in ipairs(preset.followers)do keys[#keys+1]={k,nil,'general'}end
  local sum={already=0,free=0,occupied=0,donor=0}
  for i,v in ipairs(keys)do local status=i==1 and 'already'or i==3 and (take and 'donor'or 'occupied')or 'free';local item={key=v[1],slot_key=v[2],category=v[3],status=status}
   if status=='donor'then item.candidate={owner=43}end;if i==2 then item.replacement={key='old_armour'}end
   entries[i]=item;sum[status]=sum[status]+1;if status=='free'or status=='donor'then actions[#actions+1]=item end
  end
  names.old_armour='Простые доспехи'
  return{state={target={cqi=cqi},names=names,icons=icons,instances={{key='stone',owner=43,slot_key='talisman',category='equipment'}},donors={[43]={name='Алхимик'}}},entries=entries,actions=actions,summary=sum,take=take,goal=preset}
 end
 local visual_notify
 local visual_busy,visual_waiting=false,false
 app.busy=function()return visual_busy end;app.waiting=function()return visual_waiting end
 function app.start(cqi,preset,take,plan,callback)visual_notify=callback;callback({status='complete',completed=#plan.actions,summary=plan.summary});return true end
 local fixture_equipment=node('equipment_holder',node('character_details_subpanel',node('tab_panels',node('character_context_parent',panel))))
 fixture_equipment:MoveTo(viewport_width-642,150);fixture_equipment:Resize(642,682)
 local visual=create_ui(m,st,{describe=desc,capture=function()return snap end,inspect=function()return{names=names,icons=icons}end,apply=app});visual.start();select(42);event('PanelOpenedCampaign',{string='character_details_panel'});click('wh3ep_lib_open')
 local function capture(name)
  if name:match('^preview')then assert(nodes.wh3ep_lib_input_popup.image_path=='ui/skins/wh3ep/en_preview_panel_titled.png' and nodes.panel_title.visible,'preview reuse must retain clean art and the catalog heading')
  elseif name:match('^result')then assert(nodes.wh3ep_lib_input_popup.image_path=='ui/skins/wh3ep/result_panel.png' and nodes.panel_title.visible,'result reuse must restore clean art and native heading')end
  local out={};for _,n in pairs(nodes)do
   local shown=n.visible;local parent=n.parent;while parent do shown=shown and parent.visible;parent=parent.parent end
   if shown and n.template=='ui/templates/wh3ep_icon.twui.xml' and n.image_size then
    local padded=n.image_path and n.image_path:match('^ui/skins/default/equipment_items_%a+%.png$')~=nil
    assert_image_centered(n,padded) -- Real controller row72, heading76, card64, preview and reuse slot bounds.
   end
   if shown and n.template and n.x and n.w then out[#out+1]={id=n.id,template=n.template,x=n.x,y=n.y,w=n.w,h=n.h,text=n.text,state=n.state or 'active',image=n.image_path,image_size=n.image_size,image_offset=n.image_offset,image_dock=n.image_dock,priority=n.priority or 0,order=n.order}end
  end
  local file=assert(io.open(os.getenv('WH3EP_UI_CAPTURE')..'/'..name..'.json','wb'));file:write(assert(json.encode(out)));file:close()
 end
 click('wh3ep_lib_close');capture('entry')
 local placement=assert(io.open(os.getenv('WH3EP_UI_CAPTURE')..'/entry-placement.json','wb'))
 placement:write(assert(json.encode({entry={x=nodes.wh3ep_lib_open.x,y=nodes.wh3ep_lib_open.y,w=184,h=46},equipment={x=fixture_equipment.x,y=fixture_equipment.y,w=fixture_equipment.w,h=fixture_equipment.h},gap=12,source='synthetic real-anchor boundary fixture; not a native screenshot'})));placement:close()
 click('wh3ep_lib_open');capture('library')
 local function capture_button_states(name,ids)
  local previous={};for _,id in ipairs(ids)do previous[id]=nodes[id]:CurrentState();nodes[id]:SetState('hover')end;capture(name..'-hover')
  for _,id in ipairs(ids)do nodes[id]:SetState('inactive')end;capture(name..'-inactive')
  for _,id in ipairs(ids)do nodes[id]:SetState(previous[id])end
 end
 capture_button_states('library-buttons',{'wh3ep_lib_save','wh3ep_lib_apply','wh3ep_lib_close','wh3ep_lib_rename','wh3ep_lib_overwrite','wh3ep_lib_delete','wh3ep_lib_change_scope','wh3ep_lib_previous','wh3ep_lib_next','wh3ep_lib_help'});click('wh3ep_lib_row_2');capture('library-row2-selected');click('wh3ep_lib_row_3');capture('library-row3-selected');click('wh3ep_lib_row_1')
 nodes.wh3ep_lib_search_input:SetStateText('нет совпадений');search_timer();capture('search-empty');nodes.wh3ep_lib_search_input:SetStateText('');search_timer()
 click('row_star_1');click('wh3ep_lib_filter');assert(nodes.wh3ep_lib_filter_option_favorites.visible and nodes.wh3ep_lib_filter_menu.topmost,'filter menu must be topmost');assert(nodes.wh3ep_lib_filter_option_favorites.parent==nodes.wh3ep_lib_filter_menu,'options belong to overlay');click('wh3ep_lib_filter_option_favorites');capture('favorites-empty');click('wh3ep_lib_filter');click('wh3ep_lib_filter_option_matching');click('row_star_1')
 click('wh3ep_lib_save_class');click('wh3ep_lib_save');capture('create-class');input('');capture('input-error');click('button_cancel',nodes.wh3ep_lib_input_popup.children.button_cancel)
 click('wh3ep_lib_save_general');click('wh3ep_lib_save');capture('create-general');click('button_cancel',nodes.wh3ep_lib_input_popup.children.button_cancel)
 click('wh3ep_lib_save_class');click('wh3ep_lib_delete');capture('delete-confirm');click('button_cancel',nodes.wh3ep_lib_input_popup.children.button_cancel)
 click('wh3ep_lib_apply');capture('preview')
 capture_button_states('preview-buttons',{'button_ok','button_cancel','button_preview_previous','button_preview_next','button_preview_help','button_preview_close'})
 click('button_preview_take',nodes.wh3ep_lib_input_popup.children.button_preview_take);capture('preview-donor')
 click('button_preview_next',nodes.wh3ep_lib_input_popup.children.button_preview_next);capture('preview-followers')
 click('button_ok',nodes.wh3ep_lib_input_popup.children.button_ok);capture('result')
 visual_notify({status='complete',completed=3,summary={already=2,missing=1,incompatible=1,no_slot=1,occupied=1,unsupported=1}});capture('result-mixed')
 for _,terminal in ipairs({'not_applied','error','inventory_changed'})do visual_notify({status=terminal,completed=1,summary={free=99,donor=99,already=99},code='engine_error'});capture('terminal-'..terminal:gsub('_','-'))end
 visual_notify({status='complete',completed=3,summary={already=2,missing=1,incompatible=1,no_slot=1,occupied=1,unsupported=1}})
 click('button_ok',nodes.wh3ep_lib_input_popup.children.button_ok);capture('library-after-result')
 visual_busy=true;visual_notify({status='running',completed=0,summary={}});capture('library-running')
 visual_waiting=true;visual_notify({status='awaiting_confirmation',completed=0,summary={}});capture('library-waiting')
 visual_busy,visual_waiting=false,false;visual_notify({status='cancelled',completed=0,summary={}});capture('library-after-waiting')
 click('wh3ep_lib_filter');click('wh3ep_lib_filter_option_general');capture('library-general-portrait-reuse')
 print('PASS: exported synthetic visual fixture from actual UI controller')
end
assert(state_matrix_checks>=162);print("PASS: real TWUI component-image references, native transition graph and "..state_matrix_checks.." role/state/mode checks")
