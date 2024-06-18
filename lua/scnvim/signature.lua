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

local function get_current_argument_idx(line_to_cursor)
  local comma_count = 0
  local in_parenthesis = false

  for i = 1, #line_to_cursor do
    local char = line_to_cursor:sub(i, i)
    if char == '(' then
      in_parenthesis = true
    elseif char == ')' then
      in_parenthesis = false
    elseif char == ',' and in_parenthesis then
      comma_count = comma_count + 1
    end
  end

  return comma_count + 1
end

local function split_signature(signature)
  local args = {}
  local start_idx = 1
  local in_arg = false

  for i = 1, #signature do
    local char = signature:sub(i, i)
    if char == ',' and not in_arg then
      table.insert(args, vim.trim(signature:sub(start_idx, i - 1)))
      start_idx = i + 1
    elseif char == '(' or char == ')' then
      in_arg = not in_arg
    end
  end

  table.insert(args, vim.trim(signature:sub(start_idx)))
  return args
end

local function show_signature(object)
  if object ~= '' then
    local float = config.editor.signature.float
    local float_conf = config.editor.signature.config
    get_method_signature(object, function(res)
      local signature = res:match '%((.+)%)'
      if signature then
        local line, line_to_cursor = get_line_info()
        local current_arg_idx = get_current_argument_idx(line_to_cursor)

        local args = split_signature(signature)
        local signature_text = table.concat(args, ', ')
        local current_arg_start = 0
        local current_arg_end = 0
        local char_count = 0

        for i, arg in ipairs(args) do
          arg = vim.trim(arg)
          if i == current_arg_idx then
            current_arg_start = char_count
            current_arg_end = char_count + #arg
            break
          end
          char_count = char_count + #arg + 2 -- account for ", "
        end

        if float then
          local bufnr, id = lsp_util.open_floating_preview({ signature_text }, 'supercollider', float_conf)
          hint_winid = id

          -- Add highlight to the current argument
          api.nvim_buf_add_highlight(bufnr, -1, 'ErrorMsg', 0, current_arg_start, current_arg_end)
        else
          print(signature_text)
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
