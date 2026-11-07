-- Transparent, byte-exact storage over short native registry strings.
-- Native string capacity is undocumented; all new values stay below 512 bytes.
local sub=string.sub_lua or string.sub
local match=string.match
local floor=math.floor
local MAX_BYTES,PART_BYTES,MAX_GENERATION=2*1024*1024,192,2147483647
local MAX_ARCHIVE_BYTES=6*1024*1024
local function max_bytes(key)
    return key=='wh3ep_library_damaged_v1'and MAX_ARCHIVE_BYTES or MAX_BYTES
end
local function integer(value,min,max)
    return type(value)=='number'and value-value==0 and value%1==0 and value>=min and value<=max
end
local function checksum(value)
    local a,b=1,0
    for index=1,#value do a=(a+value:byte(index))%65521;b=(b+a)%65521 end
    return b*65536+a
end
local function manifest(value,key)
    if type(value)~='string'then return nil end
    local version=tonumber(match(value,'^WH3EP_CHUNK(%d+):'))
    if version and version>1 then return nil,'future_schema'end
    if #value>160 then return nil end
    local bank,generation,count,bytes,sum=match(value,'^WH3EP_CHUNK1:(%d+):(%d+):(%d+):(%d+):(%d+)$')
    bank,generation,count,bytes,sum=tonumber(bank),tonumber(generation),tonumber(count),tonumber(bytes),tonumber(sum)
    if not integer(bank,0,1)or not integer(generation,1,MAX_GENERATION)
        or not integer(count,0,math.ceil(max_bytes(key)/PART_BYTES))or not integer(bytes,0,max_bytes(key))
        or not integer(sum,0,4294967295)or count~=math.ceil(bytes/PART_BYTES)then return nil end
    return {bank=bank,generation=generation,count=count,bytes=bytes,sum=sum}
end
local function part_key(key,bank,index)return key..'_chunks_v1_'..bank..'_'..index end
local function part_prefix(generation,index)return 'WH3EP_PART1:'..generation..':'..index..':'end
local function hex_encode(value)
    local result={}
    for index=1,#value do result[index]=string.format('%02x',value:byte(index))end
    return table.concat(result)
end
local function hex_decode(value)
    if not match(value,'^[0-9a-f]*$')or #value%2~=0 then return nil end
    local result={}
    for index=1,#value,2 do result[#result+1]=string.char(tonumber(sub(value,index,index+1),16))end
    return table.concat(result)
end
return function(native)
    local R={}
    local function safe_read(key)
        local ok,value=pcall(native.read,key)
        if not ok or(value~=nil and type(value)~='string')then return nil,false end
        return value,true
    end
    local function short_write(key,value)
        local ok,result=pcall(native.write,key,value)
        if not ok or result==false then return false end
        local actual,read_ok=safe_read(key)
        return read_ok and actual==value
    end
    function R.read(key)
        local raw,ok=safe_read(key)
        if not ok then error('native_registry_read_failed',0)end
        local info,status=manifest(raw,key)
        if status then return nil,status end
        if not info then return raw end -- Existing plain JSON, or damaged envelope.
        local pieces={}
        for index=1,info.count do
            local part,part_ok=safe_read(part_key(key,info.bank,index))
            local prefix=part_prefix(info.generation,index)
            local bytes=math.min(PART_BYTES,info.bytes-(index-1)*PART_BYTES)
            if not part_ok or type(part)~='string'or #part~=#prefix+bytes*2
                or sub(part,1,#prefix)~=prefix then return raw end
            pieces[index]=hex_decode(sub(part,#prefix+1))
            if not pieces[index]then return raw end
        end
        local value=table.concat(pieces)
        if #value~=info.bytes or checksum(value)~=info.sum then return raw end
        return value
    end
    function R.archive(key)
        local raw,ok=safe_read(key)
        if not ok then return nil,'archive_failed'end
        local info,status=manifest(raw,key)
        if status then return nil,status end
        if not info then return raw end
        -- Preserve the actual referenced raw parts, not a pointer into reusable banks.
        -- Length framing retains arbitrary corrupt bytes and explicit missing entries.
        local pieces={'WH3EP_DAMAGED1:',tostring(#raw),':',tostring(info.count),':',raw}
        local size=#table.concat(pieces)
        for index=1,info.count do
            local part,part_ok=safe_read(part_key(key,info.bank,index))
            if not part_ok then return nil,'archive_failed'end
            local header=index..':'..(part and tostring(#part)or '-1')..':'
            size=size+#header+(part and #part or 0)
            if size>MAX_ARCHIVE_BYTES then return nil,'archive_failed'end
            pieces[#pieces+1]=header
            if part then pieces[#pieces+1]=part end
        end
        return table.concat(pieces)
    end
    function R.write(key,value)
        if type(key)~='string'or type(value)~='string'or #value>max_bytes(key)then return false end
        local original,ok=safe_read(key)
        if not ok then return false end
        local previous,status=manifest(original,key)
        if status then return false end
        local bank=previous and 1-previous.bank or 0
        local generation=previous and previous.generation+1 or 1
        if generation>MAX_GENERATION then return false end
        local count=math.ceil(#value/PART_BYTES)
        for index=1,count do
            local payload=sub(value,(index-1)*PART_BYTES+1,index*PART_BYTES)
            local part=part_prefix(generation,index)..hex_encode(payload)
            if not short_write(part_key(key,bank,index),part)then return false end
        end
        -- Publishing never happens until every new part is readable and the head is unchanged.
        local current,read_ok=safe_read(key)
        if not read_ok or current~=original then return false end
        local head='WH3EP_CHUNK1:'..bank..':'..generation..':'..count..':'..#value..':'..checksum(value)
        if not short_write(key,head)then return false end
        local read_back,actual,read_status=pcall(R.read,key)
        return read_back and read_status==nil and actual==value
    end
    return R
end