local make=assert(loadfile('src/wh3ep_localization.lua'))()
local ru=assert(loadfile('src/locales/ru.lua'))()
local eng=assert(loadfile('src/locales/eng.lua'))()
local function locale(code,ru_catalog)
 return make({ru=ru_catalog or ru,eng=eng},function(expression)
  assert(expression=='LocLanguage');return code
 end)
end
assert(locale('RU').language=='ru' and locale('ru').text('button_preview')=='Предпросмотр')
for _,id in ipairs({'EN','en','BR','CN','CZ','FR','GE','IT','KR','PL','SP','TR','ZH','unknown'})do
 local l=locale(id);assert(l.language=='eng' and l.text('button_preview')=='Preview')
end
assert(make({ru=ru,eng=eng}).language=='eng')
assert(make({ru=ru,eng=eng},function()error('PRIVATE_NATIVE_FAILURE')end).language=='eng')
assert(locale('RU',{}).text('button_preview')=='Preview','missing translation must use English')
assert(locale('RU').text('missing_key')=='[missing_key]')
assert(locale('RU').text('format_presets',12)=='Пресеты: 12')
assert(locale('EN').text('format_presets',12)=='Presets: 12')
assert(locale('EN').quantity(1,'item')=='1 item')
assert(locale('EN').quantity(22,'item')=='22 items')
assert(locale('RU').quantity(1,'item')=='1 предмет')
assert(locale('RU').quantity(2,'item')=='2 предмета')
assert(locale('RU').quantity(11,'item')=='11 предметов')
assert(locale('RU').quantity(21,'follower')=='21 спутник')
local layers={ru=ru,eng=eng,cn={button_preview='预览'},pl={quantity_item_one='przedmiot',quantity_item_few='przedmioty',quantity_item_many='przedmiotów'}}
assert(make(layers,function()return 'CN'end).text('button_preview')=='预览','installed Chinese language code selects Chinese layer')
assert(make(layers,function()return 'PL'end).quantity(21,'item')=='21 przedmiotów','Polish21 uses plural-many, not Russian singular')
for key,value in pairs(ru)do assert(type(eng[key])==type(value),'English catalog missing '..key)end
for key,value in pairs(eng)do assert(type(ru[key])==type(value),'Russian catalog missing '..key)end
for _,path in ipairs({'src/wh3ep_library_ui.lua','src/wh3ep_equipment.lua'})do
 local source=assert(io.open(path,'rb'));local content=source:read('*a');source:close()
 assert(not content:find('[\208\209]'),'Russian interface literals must remain in the catalog: '..path)
 for key in content:gmatch("L%('([^']+)'%)")do assert(eng[key]and ru[key],'UI key missing from catalogs: '..key)end
end
print('PASS: native language selection, English fallback, complete catalogs, formatting and plural rules')
