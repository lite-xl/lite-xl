--------------------------------------------------------------------------------
-- inject utf8 functions to strings
--------------------------------------------------------------------------------

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

string.uescape = utf8.escape
string.ucharpos = utf8.charpos
string.unext = utf8.next
string.uinsert = utf8.insert
string.uremove = utf8.remove
string.uwidth = utf8.width
string.uwidthindex = utf8.widthindex
string.utitle = utf8.title
string.ufold = utf8.fold
string.uncasecmp = utf8.ncasecmp

string.uoffset = utf8.offset
string.ucodepoint = utf8.codepoint
string.ucodes = utf8.codes
