local model=assert(loadfile('src/wh3ep_model.lua'))()
local function check(value,message)assert(value,message)end
local function snapshot(faction,class)
 return {faction_key=faction,class_key=class,character_kind='lord',character_cqi=777,
 equipment={{slot_key='weapon',item_key='test_sword',instance_id='session-only'},{slot_key='armour',item_key='unknown_mod_armour'}},
 followers={'same_follower','same_follower'}}
end
local library=model.new()
check(model.validate(library))
local first,preset=model.add(library,snapshot('reikland','general'),'  Ранний комплект  ','general')
check(first and preset.name=='Ранний комплект' and preset.id=='p1')
check(library.next_id==1 and library.library_revision==0,'editing must not mutate input')
check(first.library_revision==1 and first.next_id==2)
check(preset.character_cqi==nil and preset.equipment[1].instance_id==nil,'presets must exclude session identities')
check(#preset.followers==2,'identical followers are separate desired copies')
local second,shared=model.add(first,snapshot('reikland','general'),'Общий комплект','')
local third=model.add(second,snapshot('other_faction','general'),'Общий комплект','')
local fourth,duplicate=model.add(third,snapshot('reikland','other_class'),'Ранний комплект','other_class')
check(fourth and duplicate.id~=preset.id,'duplicate names must be allowed')
local list=model.list(fourth,'reikland','general','matching','')
check(#list==2,'matching list must include class and classless, but not other class/faction')
check(#model.list(fourth,'reikland','other_class','matching','')==2)
check(#model.list(fourth,'reikland','general','general','')==1)
check(#model.list(fourth,'reikland','general','all','')==3)
check(#model.list(fourth,'reikland','general','matching','РАННИЙ')==1,'Cyrillic search must ignore case')
local favorite=model.update(fourth,'reikland',shared.id,{favorite=true})
check(favorite and #model.list(favorite,'reikland','general','favorites','')==1)
check(model.list(favorite,'reikland','general','matching','')[1].id==shared.id,'favorites sort first')
local renamed=model.update(favorite,'reikland',preset.id,{name='Ёлка'})
check(#model.list(renamed,'reikland','general','matching','ёлка')==1)
check(fourth.factions.reikland.presets[1].name=='Ранний комплект','update must not mutate input')
list[1].name='external mutation'
check(model.list(fourth,'reikland','general','matching','')[1].name~='external mutation','list must not expose stored records')
local deleted=model.delete(renamed,'reikland',shared.id)
check(deleted and #model.list(deleted,'reikland','general','matching','')==1)
check(model.validate(deleted))
check(not model.add(library,snapshot('reikland','general'),' \t ','general'))
check(not model.add(library,snapshot('reikland','general'),'\194\160','general'),'Unicode whitespace-only name rejected')
check(not model.add(library,snapshot('reikland','general'),string.rep('Я',65),'general'))
check(model.add(library,snapshot('reikland','general'),string.rep('Я',64),'general'))
check(not model.add(library,snapshot('reikland','general'),'bad\255','general'),'invalid UTF8 rejected')
check(not model.add(library,snapshot('reikland','general'),'line\nbreak','general'))
local invalid=snapshot('reikland','general');invalid.equipment[2].slot_key='weapon'
check(not model.add(library,invalid,'bad','general'),'duplicate gear slots rejected')
check(not model.update(first,'other_faction','p1',{favorite=true}),'cannot edit another faction record')
check(not model.update(first,'reikland','p1',{id='p99'}),'ID cannot be patched')
local missing=model.add(library,snapshot('reikland','general'),'Valid','general')
missing.factions.reikland.presets[1].name=nil
check(not model.validate(missing),'missing name must not pass validation')
local extra=model.add(library,snapshot('reikland','general'),'Valid','general')
extra.factions.reikland.presets[1].character_cqi=777
check(not model.validate(extra),'session identities forbidden in stored schema')
local future=model.new();future.schema_version=2
local ok,code=model.validate(future);check(not ok and code=='future_schema')
future.schema_version=2147483648
local future_ok,future_code=model.validate(future);check(not future_ok and future_code=='future_schema','large future schema must remain read-only')
local broken=model.new();broken.factions.x={presets={}}
broken.factions.x.presets[2]=preset
check(not model.validate(broken),'sparse preset arrays rejected')
local cycle=model.new();cycle.loop=cycle;check(not model.validate(cycle),'cycles rejected')
local full=model.new();full.factions.reikland={presets={}}
for index=1,500 do
 local item=assert(model.capture(snapshot('reikland','general'),'Комплект '..index,'','p'..index))
 full.factions.reikland.presets[index]=item
end
full.next_id=501
check(model.validate(full))
local rejected,limit=model.add(full,snapshot('reikland','general'),'Лишний','')
check(not rejected and limit=='preset_limit' and #full.factions.reikland.presets==500)
local shallow=model.new();local cursor=shallow
for index=1,18 do cursor.extra={};cursor=cursor.extra end
check(not model.validate(shallow),'depth limit enforced')
print('PASS: faction/class/classless scopes, duplicate names, Cyrillic/Unicode names and search, favorites, immutable CRUD, stable item keys, limits/corruption')
-- General presets are shared between lords/heroes of a faction, class presets are not.
local hero_snapshot=snapshot('reikland','alchemist');hero_snapshot.character_kind='hero'
local mixed,hero_shared=assert(model.add(favorite,hero_snapshot,'Общий героя',''))
local mixed_class,hero_class=model.add(mixed,hero_snapshot,'Класс алхимика','alchemist')
check(#model.list(mixed_class,'reikland','alchemist','matching','','hero')==3,'hero must see both general presets plus own class')
check(#model.list(mixed_class,'reikland','general','matching','','lord')==3,'lord must see general preset created by hero')
check(#model.list(mixed_class,'reikland','other_hero','matching','','hero')==2,'other hero sees only general presets')
check(#model.list(mixed_class,'reikland','general','matching','','hero')==2,'same subtype text must not expose class preset of another kind')
check(#model.list(mixed_class,'reikland','alchemist','favorites','','hero')==1,'favorite general lord preset must be visible to hero')
check(#model.list(mixed_class,'other_faction','alchemist','matching','','hero')==1,'other faction has its own general preset only')
local bound,bound_preset=model.update(mixed_class,'reikland',shared.id,{class_key='alchemist',character_kind='hero'})
check(bound and bound_preset.character_kind=='hero','binding a general preset on hero must also bind kind')
check(#model.list(bound,'reikland','general','matching','','lord')==2,'bound hero preset must disappear from lord list')
check(not model.update(mixed_class,'reikland',shared.id,{character_kind='colonel'}),'unsupported kinds rejected')
print('PASS: classless presets shared across lords/heroes, class/kind/faction isolation, scope rebinding')check(not model.update(mixed_class,'reikland',hero_class.id,{character_kind=false}),'explicit false kind must not silently become lord')

-- Schema-1 records without semantic icons stay valid and keep the legacy fallback.
local legacy_preset={id='p1',name='Legacy',class_key='',character_kind='lord',favorite=false,equipment={},followers={}}
local legacy=model.new();legacy.factions.reikland={presets={legacy_preset}};legacy.next_id=2
check(model.validate(legacy),'schema-1 records may omit icon_key')
local legacy_favorite=assert(model.update(legacy,'reikland','p1',{favorite=true}))
check(legacy_favorite.factions.reikland.presets[1].icon_key==nil,'unrelated edits must not migrate legacy icon data')

local invalid_icon_library=model.add(model.new(),snapshot('reikland','general'),'Invalid icon','', 'not-an-icon')
check(not invalid_icon_library,'new records must reject unknown icon keys')
local invalid_icon_record=model.new()
invalid_icon_record.factions.reikland={presets={{id='p1',name='Invalid icon',class_key='',character_kind='lord',favorite=false,icon_key='not-an-icon',equipment={},followers={}}}}
invalid_icon_record.next_id=2
check(not model.validate(invalid_icon_record),'stored unknown icon keys must be rejected')

local icon_keys={'general','attack','defense','scouting','magic','ranged','cavalry','command','support','supplies'}
local exposed_icon_keys=model.preset_icon_keys()
for index,icon_key in ipairs(icon_keys) do
 check(exposed_icon_keys[index]==icon_key,'icon key order is stable')
end
exposed_icon_keys[1]='mutated'
check(model.preset_icon_keys()[1]=='general','icon key access returns a fresh copy')
local icon_library=model.new()
for _,icon_key in ipairs(icon_keys) do
 local created
 icon_library,created=model.add(icon_library,snapshot('reikland','general'),'Icon '..icon_key,'',icon_key)
 check(created and created.icon_key==icon_key,'allowed icon key must round-trip: '..icon_key)
end
local default_icon_library,default_icon=model.add(model.new(),snapshot('reikland','general'),'Default icon','')
check(default_icon_library and default_icon.icon_key=='general','new records default to the general icon')
local selected_library,selected=model.add(model.new(),snapshot('reikland','general'),'Selected icon','', 'scouting')
local selected_list=assert(model.list(selected_library,'reikland','general','all',''))
check(selected_list[1].icon_key=='scouting','list returns the selected icon')
local selected_favorite,selected_favorite_preset=model.update(selected_library,'reikland',selected.id,{favorite=true})
check(selected_favorite_preset.icon_key=='scouting','favorite updates preserve the icon')
local same_icon_rename,renamed_preset=model.update(selected_favorite,'reikland',selected.id,{name='Renamed icon'})
check(renamed_preset.name=='Renamed icon' and renamed_preset.icon_key=='scouting','rename preserves the selected icon')
local renamed_icon,changed_icon_preset=model.update(same_icon_rename,'reikland',selected.id,{name='Changed icon name',icon_key='magic'})
check(changed_icon_preset.name=='Changed icon name' and changed_icon_preset.icon_key=='magic','rename can change the icon')
local updated_icon,updated_preset=model.update(renamed_icon,'reikland',selected.id,{equipment={},followers={}})
check(updated_preset.icon_key=='magic','equipment updates preserve the selected icon')
local with_remaining,remaining=model.add(updated_icon,snapshot('reikland','general'),'Remaining icon','', 'defense')
local after_icon_delete=assert(model.delete(with_remaining,'reikland',selected.id))
check(after_icon_delete.factions.reikland.presets[1].icon_key=='defense','delete leaves other selected icons intact')
check(not model.update(with_remaining,'reikland',remaining.id,{icon_key='not-an-icon'}),'icon updates reject unknown keys')
print('PASS: optional schema-1 icons, semantic icon validation/defaults, and icon-preserving CRUD')
