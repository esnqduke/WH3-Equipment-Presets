local sub=string.sub_lua or string.sub
-- Registry: read(key) -> string|nil, optional future_schema; write(key,string).
-- Optional archive(key) returns an independent damaged-data snapshot before recovery.
-- No campaign save values and no direct filesystem calls.
return function(model,json,registry)
    local S={}
    local primary='wh3ep_library_v1'
    local backup='wh3ep_library_backup_v1'
    local pending='wh3ep_library_pending_v1'
    local damaged='wh3ep_library_damaged_v1'
    local MAX_BYTES=2*1024*1024
    local null,object_meta,array_meta={}, {__jsontype="object"}, {__jsontype="array"}
    local function read(key)
        local ok,value,registry_status=pcall(registry.read,key)
        if ok and registry_status=='future_schema'then return nil,registry_status end
        if not ok or (value~=nil and type(value)~='string') then return nil,'read_failed' end
        if value=='' then value=nil end
        return value
    end
    local function checked_write(key,value)
        local ok,result=pcall(registry.write,key,value)
        if not ok or result==false then return nil end
        local actual,code=read(key)
        return not code and (actual or '')==value
    end
    -- dkjson accepts some relaxed syntax; validate strict JSON grammar first.
    -- This scan constructs no values and caps nesting before the decoder runs.
    local function scan(raw)
        if #raw>MAX_BYTES then return nil,'too_large' end
        local position,failure=1,'invalid_json'
        local function space()
            while true do
                local byte=raw:byte(position)
                if byte~=32 and byte~=9 and byte~=10 and byte~=13 then return end
                position=position+1
            end
        end
        local function string_token()
            if raw:byte(position)~=34 then return false end
            position=position+1
            while position<=#raw do
                local byte=raw:byte(position)
                if byte==34 then position=position+1;return true end
                if byte<32 then return false end
                if byte==92 then
                    local escape=sub(raw,position+1,position+1)
                    if escape=='u' then
                        if not sub(raw,position+2,position+5):match('^%x%x%x%x$') then return false end
                        position=position+6
                    elseif escape=='"' or escape=='\\' or escape=='/' or escape=='b' or escape=='f' or escape=='n' or escape=='r' or escape=='t' then
                        position=position+2
                    else return false end
                else position=position+1 end
            end
            return false
        end
        local function digit()
            local byte=raw:byte(position)
            return byte and byte>=48 and byte<=57
        end
        local function number_token()
            if raw:byte(position)==45 then position=position+1 end
            if raw:byte(position)==48 then position=position+1
            elseif digit() then repeat position=position+1 until not digit()
            else return false end
            if raw:byte(position)==46 then
                position=position+1;if not digit() then return false end
                repeat position=position+1 until not digit()
            end
            local byte=raw:byte(position)
            if byte==69 or byte==101 then
                position=position+1;byte=raw:byte(position)
                if byte==43 or byte==45 then position=position+1 end
                if not digit() then return false end
                repeat position=position+1 until not digit()
            end
            return true
        end
        local value
        value=function(depth)
            space()
            local byte=raw:byte(position)
            if byte==34 then return string_token() end
            if byte==123 or byte==91 then
                if depth>16 then failure='too_deep';return false end
                local object=byte==123
                local closing=object and 125 or 93
                position=position+1;space()
                if raw:byte(position)==closing then position=position+1;return true end
                while true do
                    if object then
                        if not string_token() then return false end
                        space();if raw:byte(position)~=58 then return false end
                        position=position+1
                    end
                    if not value(depth+1) then return false end
                    space();byte=raw:byte(position)
                    if byte==closing then position=position+1;return true end
                    if byte~=44 then return false end
                    position=position+1;space()
                end
            end
            if byte==45 or (byte and byte>=48 and byte<=57) then return number_token() end
            for _,literal in ipairs({'true','false','null'}) do
                if sub(raw,position,position+#literal-1)==literal then position=position+#literal;return true end
            end
            return false
        end
        if not value(1) then return nil,failure end
        space()
        if position<=#raw then return nil,'invalid_json' end
        return true
    end
    local function contains_null(value)
        if value==null then return true end
        if type(value)=='table' then for _,item in pairs(value) do if contains_null(item) then return true end end end
        return false
    end
    local function valid_shapes(library)
        if getmetatable(library)~=object_meta or getmetatable(library.factions)~=object_meta then return false end
        for _,entry in pairs(library.factions) do
            if getmetatable(entry)~=object_meta or getmetatable(entry.presets)~=array_meta then return false end
            for _,preset in ipairs(entry.presets) do
                if getmetatable(preset)~=object_meta or getmetatable(preset.equipment)~=array_meta or getmetatable(preset.followers)~=array_meta then return false end
                for _,item in ipairs(preset.equipment) do if getmetatable(item)~=object_meta then return false end end
            end
        end
        return true
    end
    local function decode(raw)
        if not raw then return nil,'missing_primary' end
        local ok,code=scan(raw);if not ok then return nil,code end
        local parsed,library,position,error_code=pcall(json.decode,raw,1,null,object_meta,array_meta)
        if not parsed or error_code or type(position)~='number' or not sub(raw,position):match('^%s*$') then return nil,'invalid_json' end
        local valid,reason=model.validate(library)
        if not valid then return nil,reason end
        if contains_null(library) or not valid_shapes(library) then return nil,'invalid_structure' end
        return library
    end
    local function plain_copy(value)
        if type(value)~='table' then return value end
        local result={}
        for key,item in pairs(value) do result[key]=plain_copy(item) end
        return result
    end
    local function encode(library)
        local valid,code=model.validate(library);if not valid then return nil,code end
        local value=plain_copy(library)
        setmetatable(value.factions,{__jsontype='object'})
        local ok,raw=pcall(json.encode,value)
        if not ok or type(raw)~='string' then return nil,'encode_failed' end
        if #raw>MAX_BYTES then return nil,'too_large' end
        return raw
    end
    function S.load()
        local raw,read_error=read(primary)
        if read_error then return nil,read_error end
        local info={token=raw}
        local library,reason=decode(raw)
        if library then return library,'ok',info end
        if reason=='future_schema' then return nil,reason,info end
        local backup_raw,backup_error=read(backup)
        if backup_error then return nil,backup_error,info end
        if not raw and not backup_raw then return model.new(),'new',info end
        local previous,backup_reason=decode(backup_raw)
        if previous then info.reason=reason;return previous,'backup_available',info end
        if backup_reason=='future_schema' then return nil,'future_backup_schema',info end
        return nil,raw and reason or 'invalid_backup',info
    end
    local function commit(raw,old_raw)
        if checked_write(primary,raw) then return true end
        if checked_write(primary,old_raw or '') then return nil,'write_failed' end
        return nil,'write_failed_backup_available'
    end
    function S.save(library,expected_revision,expected_token)
        local raw,encode_error=encode(library)
        if not raw then return nil,encode_error end
        local current,status,info=S.load()
        if not current or (status~='ok' and status~='new') then return nil,status end
        if current.library_revision~=expected_revision or library.library_revision~=expected_revision+1 then return nil,'revision_conflict' end
        if expected_token~=nil and info.token~=expected_token then return nil,'content_conflict' end
        if not checked_write(pending,raw) then return nil,'stage_write_failed' end
        -- Never replace the primary until the candidate and previous version are readable.
        if info.token and not checked_write(backup,info.token) then return nil,'backup_write_failed' end
        local current_raw,read_error=read(primary)
        if read_error then return nil,read_error end
        if current_raw~=info.token then return nil,'content_conflict' end
        local saved,code=commit(raw,info.token)
        if not saved then return nil,code end
        return true,'saved',{token=raw}
    end
    function S.restore_backup(expected_token)
        local raw,read_error=read(primary)
        if read_error then return nil,read_error end
        if raw~=expected_token then return nil,'content_conflict' end
        local current,reason=decode(raw)
        if reason=='future_schema' then return nil,reason end
        if current then return nil,'primary_valid' end
        local previous_raw,backup_error=read(backup)
        if backup_error then return nil,backup_error end
        local previous,code=decode(previous_raw)
        if not previous then return nil,code end
        -- Preserve the damaged original before an explicit recovery overwrites it.
        local damaged_raw=raw
        if raw and type(registry.archive)=='function'then
            local captured,value=pcall(registry.archive,primary)
            if not captured or type(value)~='string'then return nil,'damage_preservation_failed'end
            damaged_raw=value
        end
        if raw and not checked_write(damaged,damaged_raw) then return nil,'damage_preservation_failed' end
        local actual,read_failure=read(primary)
        if read_failure then return nil,read_failure end
        if actual~=raw then return nil,'content_conflict' end
        local restored,restore_code=commit(previous_raw,raw)
        if not restored then return nil,restore_code end
        return previous,'restored',{token=previous_raw}
    end
    return S
end