--------------------------------------------------------------------------------
-- inject utf8extra functions to strings
--------------------------------------------------------------------------------
string.ubyte = utf8extra.byte
string.uchar = utf8extra.char
string.ufind = utf8extra.find
string.ugmatch = utf8extra.gmatch
string.ugsub = utf8extra.gsub
string.ulen = utf8extra.len
string.ulower = utf8extra.lower
string.umatch = utf8extra.match
string.ureverse = utf8extra.reverse
string.usub = utf8extra.sub
string.uupper = utf8extra.upper

<<<<<<< HEAD
string.uescape = utf8extra.escape
string.ucharpos = utf8extra.charpos
string.unext = utf8extra.next
string.uinsert = utf8extra.insert
string.uremove = utf8extra.remove
string.uwidth = utf8extra.width
string.uwidthindex = utf8extra.widthindex
string.utitle = utf8extra.title
string.ufold = utf8extra.fold
string.uncasecmp = utf8extra.ncasecmp
=======
local utf8 = require "utf8extra"

string.ubyte = utf8.byte
string.uchar = utf8.char
string.ufind = utf8.find
string.ugmatch = utf8.gmatch
string.ugsub = utf8.gsub
string.ulen = utf8.len
string.ulower = utf8.lower
string.umatch = utf8.match
string.ureverse = utf8.reverse
string.usub = utf8.sub
string.uupper = utf8.upper
>>>>>>> lite-xl/master

string.uoffset = utf8extra.offset
string.ucodepoint = utf8extra.codepoint
string.ucodes = utf8extra.codes
