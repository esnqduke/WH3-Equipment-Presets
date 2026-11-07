-- CA CcoRoot.LocLanguage is the active text language, independent of the OS.
-- The game's English pack is local_en.pack; our English catalog is named eng.
return function(catalogs,get_context_value)
    local language='eng'
    if get_context_value then
        local ok,id=pcall(get_context_value,'LocLanguage')
        if ok and type(id)=='string'then
            local aliases={en='eng',eng='eng',english='eng',ru='ru',russian='ru',cn='cn',schinese='cn',zh_cn='cn',zh='zh',tchinese='zh',zh_tw='zh',sp='sp',es='sp',spanish='sp',br='br',pt_br='br',brazilian='br',ge='ge',de='ge',german='ge',fr='fr',french='fr',pl='pl',polish='pl',kr='kr',ko='kr',koreana='kr',ja='ja',jp='ja',japanese='ja'}
            local mapped=aliases[id:lower()]
            if mapped and catalogs[mapped]then language=mapped end
        end
    end
    local selected=catalogs[language]or catalogs.eng
    local function text(key,...)
        local value=selected[key]or catalogs.eng[key]or('['..key..']')
        if select('#',...)>0 then return string.format(value,...)end
        return value
    end
    local function quantity(n,kind)
        local form=n==1 and 'one'or 'many'
        if language=='ru'then
            local last=n%100
            form=(last>=11 and last<=14)and 'many'or n%10==1 and 'one'or(n%10>=2 and n%10<=4)and 'few'or 'many'
        elseif language=='pl'then
            local last=n%100
            form=n==1 and 'one'or(n%10>=2 and n%10<=4 and(last<12 or last>14))and 'few'or 'many'
        elseif language=='fr'and n==0 then form='one'
        end
        return n..' '..text('quantity_'..kind..'_'..form)
    end
    return {language=language,text=text,quantity=quantity}
end
