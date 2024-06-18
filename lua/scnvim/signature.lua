--- Signature help.
---@module scnvim.signature
---@local

local sclang = require 'scnvim.sclang'
local config = require 'scnvim.config'
local api = vim.api
local lsp_util = vim.lsp.util
local hint_winid = nil

local M = {}

local function get_method_signature(object, cb)
  local cmd = string.format('SCNvim.methodArgs("%s")', object)
  sclang.eval(cmd, cb)
end

local function is_outside_of_statement(line, line_to_cursor)
  if not line or not line_to_cursor then
    return true
  end
  local line_endswith = vim.endswith(line, ')') or vim.endswith(line, ';')
  local curs_line_endswith = vim.endswith(line_to_cursor, ')') or vim.endswith(line_to_cursor, ';')
  return line_endswith and curs_line_endswith
end

local function extract_objects_helper(str)
  if not str then
    return ''
  end
  local objects = vim.split(str, '(', { plain = true })
  objects = vim.tbl_map(function(s)
    return vim.split(s, ',', { plain = true })
  end, objects)
  objects = vim.tbl_flatten(objects)
  objects = vim.tbl_map(function(s)
    if s == '' then
      return nil
    end
    s = vim.trim(s)
    if s:sub(1, 1) == '"' then
      return nil
    end
    s = s:gsub('%)', '')
    local obj_start = s:find '%u'
    return obj_start and s:sub(obj_start, -1)
  end, objects)
  objects = vim.tbl_filter(function(s)
    return s ~= nil
  end, objects)
  local len = #objects
  if len > 0 then
    return vim.trim(objects[len])
  end
  return ''
end

local function extract_object(line_to_cursor)
  local object_stack = {}
  local paren_count = 0
  local current_object = ''

  for i = 1, #line_to_cursor do
    local char = line_to_cursor:sub(i, i)
    if char == '(' then
      paren_count = paren_count + 1
      local obj = extract_objects_helper(line_to_cursor:sub(1, i))
      if obj ~= '' then
        table.insert(object_stack, obj)
      end
    elseif char == ')' then
      paren_count = paren_count - 1
      if paren_count < #object_stack then
        table.remove(object_stack)
      end
    end

    if paren_count > 0 then
      current_object = object_stack[#object_stack] or ''
    else
      current_object = ''
    end
  end

  return current_object
end

local function show_signature(object)
  if object ~= '' then
    local float = config.editor.signature.float
    local float_conf = config.editor.signature.config
    get_method_signature(object, function(res)
      local signature = res:match '%((.+)%)'
      if signature then
        if float then
          local _, id = lsp_util.open_floating_preview({ signature }, 'supercollider', float_conf)
          hint_winid = id
        else
          print(signature)
        end
      end
    end)
  end
end

local function update_signature()
  local line, line_to_cursor = get_line_info()
  if not line or not line_to_cursor then
    return
  end
  if is_outside_of_statement(line, line_to_cursor) then
    M.close()
    return
  end

  local object = extract_object(line_to_cursor)
  if object ~= '' then
    show_signature(object)
  else
    M.close()
  end
end

local function close_signature()
  if hint_winid ~= nil and vim.api.nvim_win_is_valid(hint_winid) then
    vim.api.nvim_win_close(hint_winid, false)
    hint_winid = nil
  end
end

function M.show()
  update_signature()
end

function M.ins_show()
  local _, line_to_cursor = get_line_info()
  if vim.v.char == '(' then
    update_signature()
  end
end

function M.close()
  close_signature()
end

function M.toggle()
  if hint_winid ~= nil and vim.api.nvim_win_is_valid(hint_winid) then
    close_signature()
  else
    update_signature()
  end
end

api.nvim_create_autocmd({ 'CursorMovedI', 'CursorMoved' }, {
  callback = function()
    update_signature()
  end,
})

api.nvim_create_autocmd('TextChangedI', {
  callback = function()
    update_signature()
  end,
})

function get_line_info()
  local _, col = unpack(api.nvim_win_get_cursor(0))
  local line = api.nvim_get_current_line()
  local line_to_cursor = line:sub(1, col + 1)
  return line, line_to_cursor
end

return M
