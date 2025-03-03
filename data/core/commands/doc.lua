local core = require "core"
local command = require "core.command"
local common = require "core.common"
local config = require "core.config"
local translate = require "core.doc.translate"
local style = require "core.style"
local DocView = require "core.docview"
local tokenizer = require "core.tokenizer"


local function doc()
  return core.active_view.doc
end


local function save(filename)
  local abs_filename
  if filename then
    filename = core.normalize_to_project_dir(filename)
    abs_filename = core.project_absolute_path(filename)
  end
  local ok, err = pcall(doc().save, doc(), filename, abs_filename)
  if ok then
    local saved_filename = doc().filename
    core.log("Saved \"%s\"", saved_filename)
  else
    core.error(err)
    core.nag_view:show("Saving failed", string.format("Couldn't save file \"%s\". Do you want to save to another location?", doc().filename), {
      { text = "Yes", default_yes = true },
      { text = "No", default_no = true }
    }, function(item)
      if item.text == "Yes" then
        core.add_thread(function()
          -- we need to run this in a thread because of the odd way the nagview is.
          command.perform("doc:save-as")
        end)
      end
    end)
  end
end

local commands = {

  ["doc:toggle-line-ending"] = function(dv)
    dv.doc.crlf = not dv.doc.crlf
  end,

  ["doc:save-as"] = function(dv)
    local last_doc = core.last_active_view and core.last_active_view.doc
    local text
    if dv.doc.filename then
      text = dv.doc.filename
    elseif last_doc and last_doc.filename then
      local dirname, filename = core.last_active_view.doc.abs_filename:match("(.*)[/\\](.+)$")
      text = core.normalize_to_project_dir(dirname) .. PATHSEP
      if text == core.root_project().path then text = "" end
    end
    core.command_view:enter("Save As", {
      text = text,
      submit = function(filename)
        save(common.home_expand(filename))
      end,
      suggest = function (text)
        return common.home_encode_list(common.path_suggest(common.home_expand(text)))
      end
    })
  end,

  ["doc:save"] = function(dv)
    if dv.doc.filename then
      save()
    else
      command.perform("doc:save-as")
    end
  end,

  ["doc:reload"] = function(dv)
    dv.doc:reload()
  end,

  ["file:rename"] = function(dv)
    local old_filename = dv.doc.filename
    if not old_filename then
      core.error("Cannot rename unsaved doc")
      return
    end
    core.command_view:enter("Rename", {
      text = old_filename,
      submit = function(filename)
        save(common.home_expand(filename))
        core.log("Renamed \"%s\" to \"%s\"", old_filename, filename)
        if filename ~= old_filename then
          os.remove(old_filename)
        end
      end,
      suggest = function (text)
        return common.home_encode_list(common.path_suggest(common.home_expand(text)))
      end
    })
  end,


  ["file:delete"] = function(dv)
    local filename = dv.doc.abs_filename
    if not filename then
      core.error("Cannot remove unsaved doc")
      return
    end
    for i,docview in ipairs(core.get_views_referencing_doc(dv.doc)) do
      local node = core.root_view.root_node:get_node_for_view(docview)
      node:close_view(core.root_view.root_node, docview)
    end
    os.remove(filename)
    core.log("Removed \"%s\"", filename)
  end
}

command.add("core.docview", commands)
