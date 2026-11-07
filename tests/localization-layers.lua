local make=assert(loadfile('src/wh3ep_localization.lua'))()
local ids={'eng','ru','cn','zh','sp','br','ge','ja','fr','pl','kr'}
local catalogs={}
for _,id in ipairs(ids)do catalogs[id]=assert(loadfile('src/locales/'..id..'.lua'))()end
local function signature(value)
 local result={};value=value:gsub('%%%%','')
 for kind in value:gmatch('%%([a-zA-Z])')do result[#result+1]=kind end
 return table.concat(result,',')
end
local count=0
for key,value in pairs(catalogs.eng)do
 count=count+1
 for _,id in ipairs(ids)do
  local translated=catalogs[id][key]
  assert(type(translated)=='string'and translated~='',id..' missing '..key)
  assert(signature(translated)==signature(value),id..' format signature '..key)
  local _,lines=value:gsub('\n','');local _,translated_lines=translated:gsub('\n','')
  assert(lines==translated_lines,id..' newline signature '..key)
 end
end
for _,id in ipairs(ids)do for key in pairs(catalogs[id])do assert(catalogs.eng[key],id..' unexpected '..key)end end
for native,id in pairs({EN='eng',RU='ru',CN='cn',ZH='zh',SP='sp',BR='br',GE='ge',JA='ja',FR='fr',PL='pl',KR='kr',DE='ge',JP='ja',KO='kr',zh_CN='cn',zh_TW='zh'})do
 local locale=make(catalogs,function()return native end)
 assert(locale.language==id and locale.text('library_title')==catalogs[id].library_title,'language map '..native)
 assert(locale.text('format_presets',12):find('12',1,true))
end
for _,native in ipairs({'CZ','IT','TR','unknown'})do assert(make(catalogs,function()return native end).language=='eng')end
local pl=make(catalogs,function()return 'PL'end)
for _,n in ipairs({0,5,11,12,14,21,25,112})do assert(pl.quantity(n,'item')==n..' '..catalogs.pl.quantity_item_many)end
for _,n in ipairs({2,3,4,22,23,24,102})do assert(pl.quantity(n,'item')==n..' '..catalogs.pl.quantity_item_few)end
assert(pl.quantity(1,'item')=='1 '..catalogs.pl.quantity_item_one)
assert(make(catalogs,function()return 'FR'end).quantity(0,'item')=='0 '..catalogs.fr.quantity_item_one)
print('PASS: '..#ids..' isolated language layers, '..count..' keys each, formats/newlines, native codes/aliases, fallbacks and plural variants')
