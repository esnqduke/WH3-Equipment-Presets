local suite=arg[1]=='--suite' and arg[2] or 'all'
if suite~='all' and suite~='model' and suite~='storage' then error('Unknown suite')end
if suite=='all' or suite=='model' then assert(loadfile('tests/model.lua'))() end
if suite=='all' or suite=='storage' then assert(loadfile('tests/storage.lua'))() end