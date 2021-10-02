table.unpack = unpack

table.pack = function(...)
   return { n = select('#', ...), ... }
end
