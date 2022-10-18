---@meta

---
---Utilites for encoding detection and conversion.
---@class encoding
encoding = {}

---@alias encoding.charset
---|>'"ARMSCII-8"'
---| '"BIG5"'
---| '"BIG5-HKSCS"'
---| '"CP866"'
---| '"CP932"'
---| '"EUC-JP"'
---| '"EUC-KR"'
---| '"EUC-TW"'
---| '"GB18030"'
---| '"GB2312"'
---| '"GBK"'
---| '"GEORGIAN-ACADEMY"'
---| '"HZ"'
---| '"IBM850"'
---| '"IBM852"'
---| '"IBM855"'
---| '"IBM857"'
---| '"IBM862"'
---| '"IBM864"'
---| '"ISO-2022-JP"'
---| '"ISO-2022-KR"'
---| '"ISO-8859-1"'
---| '"ISO-8859-2"'
---| '"ISO-8859-3"'
---| '"ISO-8859-4"'
---| '"ISO-8859-5"'
---| '"ISO-8859-6"'
---| '"ISO-8859-7"'
---| '"ISO-8859-8"'
---| '"ISO-8859-8-I"'
---| '"ISO-8859-9"'
---| '"ISO-8859-10"'
---| '"ISO-8859-13"'
---| '"ISO-8859-14"'
---| '"ISO-8859-15"'
---| '"ISO-8859-16"'
---| '"ISO-IR-111"'
---| '"JOHAB"'
---| '"KOI8-R"'
---| '"KOI8-U"'
---| '"SHIFT_JIS"'
---| '"TCVN"'
---| '"TIS-620"'
---| '"UCS-2BE"'
---| '"UCS-2LE"'
---| '"UHC"'
---| '"UTF-16BE"'
---| '"UTF-16LE"'
---| '"UTF-32BE"'
---| '"UTF-32LE"'
---| '"UTF-7"'
---| '"UTF-8"'
---| '"VISCII"'
---| '"WINDOWS-1250"'
---| '"WINDOWS-1251"'
---| '"WINDOWS-1252"'
---| '"WINDOWS-1253"'
---| '"WINDOWS-1254"'
---| '"WINDOWS-1255"'
---| '"WINDOWS-1256"'
---| '"WINDOWS-1257"'
---| '"WINDOWS-1258"'

---
---Try and detect the encoding to best of capabilities for given file given or
---returns nil and error message on failure.
---@param filename string
---@return string | nil charset
---@return string errmsg
function encoding.detect(filename) end

---
---Same as encoding.detect() but for strings.
---@param text string
---@return string | nil charset
---@return string errmsg
function encoding.detect_string(text) end

---@class encoding.convert_options
---@field handle_to_bom boolean @If applicable adds the byte order marks.
---@field handle_from_bom boolean @If applicable strips the byte order marks.
---@field strict boolean @When true fail if errors found.

---
---Converts the given text from one encoding into another.
---@param tocharset encoding.charset
---@param fromcharset encoding.charset
---@param text string
---@param options? encoding.convert_options
---@return string | nil converted_text
---@return string errmsg
function encoding.convert(tocharset, fromcharset, text, options) end

---
---Get the byte order marks for the given charset if applicable.
---@param charset encoding.charset
---@return string bom
function encoding.get_charset_bom(charset) end

---
---Remove the byte order marks from the given text.
---@param text string A string that may contain a byte order marks.
---@param charset? encoding.charset Charset to scan, if nil scan all charsets with bom.
---@return string cleaned_text
function encoding.strip_bom(text, charset) end
