local core = require "core"
local common = require "core.common"

local encodings = {}

---@class encodings.encoding
---@field charset string
---@field name string

---List of encoding regions.
---@type table<integer,string>
encodings.groups = {
  "West European",
  "East European",
  "East Asian",
  "SE & SW Asian",
  "Middle Eastern",
  "Unicode"
}

---Supported iconv encodings grouped by region.
---@type table<integer,encodings.encoding[]>
encodings.list = {
  -- West European
  {
    { charset = "ISO-8859-14",  name = "Celtic"         },
    { charset = "ISO-8859-7",   name = "Greek"          },
    { charset = "WINDOWS-1253", name = "Greek"          },
    { charset = "ISO-8859-10",  name = "Nordic"         },
    { charset = "ISO-8859-3",   name = "South European" },
    { charset = "IBM850",       name = "Western"        },
    { charset = "ISO-8859-1",   name = "Western"        },
    { charset = "ISO-8859-15",  name = "Western"        },
    { charset = "WINDOWS-1252", name = "Western"        }
  },
  -- East European
  {
    { charset = "ISO-8859-4",   name = "Baltic"             },
    { charset = "ISO-8859-13",  name = "Baltic"             },
    { charset = "WINDOWS-1257", name = "Baltic"             },
    { charset = "IBM852",       name = "Central European"   },
    { charset = "ISO-8859-2",   name = "Central European"   },
    { charset = "WINDOWS-1250", name = "Central European"   },
    { charset = "IBM855",       name = "Cyrillic"           },
    { charset = "ISO-8859-5",   name = "Cyrillic"           },
    { charset = "ISO-IR-111",   name = "Cyrillic"           },
    { charset = "KOI8-R",       name = "Cyrillic"           },
    { charset = "WINDOWS-1251", name = "Cyrillic"           },
    { charset = "CP866",        name = "Cyrillic/Russian"   },
    { charset = "KOI8-U",       name = "Cyrillic/Ukrainian" },
    { charset = "ISO-8859-16",  name = "Romanian"           }
  },
  -- East Asian
  {
    { charset = "GB18030",     name = "Chinese Simplified" },
    { charset = "GB2312",      name = "Chinese Simplified" },
    { charset = "GBK",         name = "Chinese Simplified" },
    { charset = "HZ",          name = "Chinese Simplified" },
    { charset = "BIG5",        name = "Chinese Traditional" },
    { charset = "BIG5-HKSCS",  name = "Chinese Traditional" },
    { charset = "EUC-TW",      name = "Chinese Traditional" },
    { charset = "EUC-JP",      name = "Japanese" },
    { charset = "ISO-2022-JP", name = "Japanese" },
    { charset = "SHIFT_JIS",   name = "Japanese" },
    { charset = "CP932",       name = "Japanese" },
    { charset = "EUC-KR",      name = "Korean" },
    { charset = "ISO-2022-KR", name = "Korean" },
    { charset = "JOHAB",       name = "Korean" },
    { charset = "UHC",         name = "Korean" }
  },
  -- SE & SW Asian
  {
    { charset = "ARMSCII-8",        name = "Armenian"   },
    { charset = "GEORGIAN-ACADEMY", name = "Georgian"   },
    { charset = "TIS-620",          name = "Thai"       },
    { charset = "IBM857",           name = "Turkish"    },
    { charset = "WINDOWS-1254",     name = "Turkish"    },
    { charset = "ISO-8859-9",       name = "Turkish"    },
    { charset = "TCVN",             name = "Vietnamese" },
    { charset = "VISCII",           name = "Vietnamese" },
    { charset = "WINDOWS-1258",     name = "Vietnamese" }
  },
  -- Middle Eastern
  {
    { charset = "IBM864",       name = "Arabic"        },
    { charset = "ISO-8859-6",   name = "Arabic"        },
    { charset = "WINDOWS-1256", name = "Arabic"        },
    { charset = "IBM862",       name = "Hebrew"        },
    { charset = "ISO-8859-8-I", name = "Hebrew"        },
    { charset = "WINDOWS-1255", name = "Hebrew"        },
    { charset = "ISO-8859-8",   name = "Hebrew Visual" }
  },
  -- Unicode
  {
    { charset = "UTF-7",    name = "Unicode" },
    { charset = "UTF-8",    name = "Unicode" },
    { charset = "UTF-16LE", name = "Unicode" },
    { charset = "UTF-16BE", name = "Unicode" },
    { charset = "UCS-2LE",  name = "Unicode" },
    { charset = "UCS-2BE",  name = "Unicode" },
    { charset = "UTF-32LE", name = "Unicode" },
    { charset = "UTF-32BE", name = "Unicode" }
  }
};

---Get the list of encodings associated to a region.
---@param label string
---@return encodings.encoding[] | nil
function encodings.get_group(label)
  for idx, name in ipairs(encodings.groups) do
    if name == label then
      return encodings.list[idx]
    end
  end
end

---Get the list of encodings associated to a region.
---@return encodings.encoding[] | nil
function encodings.get_all()
  local all = {}
  for idx, _ in ipairs(encodings.groups) do
      for _, item in ipairs(encodings.list[idx]) do
        table.insert(all, item)
      end
  end
  return all
end

---Open a commandview to select a charset and executes the given callback,
---@param title_label string Title displayed on the commandview
---@param callback fun(charset: string)
function encodings.select_encoding(title_label, callback)
  core.command_view:enter(title_label, {
    submit = function(_, item)
      callback(item.charset)
    end,
    suggest = function(text)
      local charsets = encodings.get_all()
      local list_labels = {}
      local list_charset = {}
      for _, element in ipairs(charsets) do
        local label = element.name .. " (" .. element.charset .. ")"
        table.insert(list_labels, label)
        list_charset[label] = element.charset
      end
      local res = common.fuzzy_match(list_labels, text)
      for i, name in ipairs(res) do
        res[i] = {
          text = name,
          charset = list_charset[name]
        }
      end
      return res
    end
  })
end


return encodings;
