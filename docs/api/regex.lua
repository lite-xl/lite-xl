---@meta

---
---Provides the base functionality for regular expressions matching.
---@class regex
regex = {}

---Instruct regex:cmatch() to match only at the first position.
---@type integer
regex.ANCHORED = 0x80000000

---Tell regex:cmatch() that the pattern can match only at end of subject.
---@type integer
regex.ENDANCHORED = 0x20000000

---Tell regex:cmatch() that subject string is not the beginning of a line.
---@type integer
regex.NOTBOL = 0x00000001

---Tell regex:cmatch() that subject string is not the end of a line.
---@type integer
regex.NOTEOL = 0x00000002

---Tell regex:cmatch() that an empty string is not a valid match.
---@type integer
regex.NOTEMPTY = 0x00000004

---Tell regex:cmatch() that an empty string at the start of the
---subject is not a valid match.
---@type integer
regex.NOTEMPTY_ATSTART = 0x00000008

---@alias regex.modifiers
---| "i"  # Case insesitive matching
---| "m"  # Multiline matching
---| "s"  # Match all characters with dot (.) metacharacter even new lines

---
---Compiles a regular expression pattern that can be used to search in strings.
---
---@param pattern string
---@param options? regex.modifiers A string of one or more pattern modifiers.
---
---@return regex? regex Ready to use regular expression object or nil on error.
---@return string? error The error message if compiling the pattern failed.
function regex.compile(pattern, options) end

---
---Search a string for valid matches and returns a list of matching offsets.
---
---@param subject string The string to search for valid matches.
---@param offset? integer The position on the subject to start searching.
---@param options? integer A bit field of matching options, eg:
---regex.NOTBOL | regex.NOTEMPTY
---
---@return integer? ... List of offsets where a match was found.
function regex:cmatch(subject, offset, options) end

---
---Returns an iterator function that, each time it is called, returns the
---next captures from `pattern` over the string subject.
---
---Example:
---```lua
---    s = "hello world hello world"
---    for hello, world in regex.gmatch("(hello)\\s+(world)", s) do
---        print(hello .. " " .. world)
---    end
---```
---
---@param pattern string
---@param subject string
---@param offset? integer
---
---@return fun():string, ...
function regex.gmatch(pattern, subject, offset) end

---
---Replaces the matched pattern globally on the subject with the given
---replacement, supports named captures ((?'name'<pattern>), ${name}) and
---$[1-9][0-9]* substitutions. Raises an error when failing to compile the
---pattern or by a substitution mistake.
---
---@param pattern regex|string
---@param subject string
---@param replacement string
---@param limit? integer Limits the number of substitutions that will be done.
---
---@return string? replaced_subject
---@return integer? total_replacements
function regex.gsub(pattern, subject, replacement, limit) end


return regex
