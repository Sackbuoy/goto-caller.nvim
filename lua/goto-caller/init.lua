local M = {}

function M.goto_caller()
  local ts_utils = require("nvim-treesitter.ts_utils")
  local node = ts_utils.get_node_at_cursor()

  -- Walk up to find the enclosing function
  while node do
    local type = node:type()
    if type:match("function") or type:match("method") or type == "arrow_function" or type == "function_item" or type == "function_definition" then
      break
    end
    node = node:parent()
  end

  if not node then
    vim.notify("Not inside a function", vim.log.levels.WARN)
    return
  end

  -- Find the function name node
  local name_node = nil
  for child in node:iter_children() do
    local t = child:type()
    if t == "identifier" or t == "name" or t == "property_identifier" or t == "field_identifier" then
      name_node = child
      break
    end
  end

  if not name_node then
    vim.notify("Could not determine function name", vim.log.levels.WARN)
    return
  end

  -- Remember where we are
  local save_buf = vim.api.nvim_get_current_buf()
  local save_pos = vim.api.nvim_win_get_cursor(0)

  -- Silently move to function name for LSP (no jumplist)
  local sr, sc = name_node:start()
  vim.api.nvim_win_set_cursor(0, { sr + 1, sc })

  local client = vim.lsp.get_clients({ bufnr = 0 })[1]
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)

  -- Immediately restore cursor so nothing visible changes
  vim.api.nvim_win_set_cursor(0, save_pos)

  vim.lsp.buf_request(0, "textDocument/prepareCallHierarchy", params, function(err, result)
    if err or not result or #result == 0 then
      vim.notify("LSP: no call hierarchy available", vim.log.levels.WARN)
      return
    end

    local item = result[1]
    vim.lsp.buf_request(0, "callHierarchy/incomingCalls", { item = item }, function(err2, calls)
      if err2 or not calls or #calls == 0 then
        vim.notify("No callers found", vim.log.levels.INFO)
        return
      end

      -- Flatten all call sites
      local sites = {}
      for _, call in ipairs(calls) do
        local from = call.from
        local fname = vim.uri_to_fname(from.uri)
        local ranges = call.fromRanges or {}
        if #ranges == 0 then
          ranges = { from.selectionRange or from.range }
        end
        for _, range in ipairs(ranges) do
          table.insert(sites, {
            filename = fname,
            lnum = range.start.line + 1,
            col = range.start.character,
            caller_name = from.name,
          })
        end
      end

      if #sites == 0 then
        vim.notify("No call sites found", vim.log.levels.INFO)
        return
      end

      local function jump_to(s)
        -- Set jumplist mark at original position, then jump
        vim.api.nvim_win_set_cursor(0, save_pos)
        vim.cmd("normal! m'")
        if vim.fn.bufnr(s.filename) ~= save_buf then
          vim.cmd("edit " .. vim.fn.fnameescape(s.filename))
        end
        vim.api.nvim_win_set_cursor(0, { s.lnum, s.col })
      end

      -- If only one call site, jump directly
      if #sites == 1 then
        vim.schedule(function() jump_to(sites[1]) end)
        return
      end

      -- Multiple call sites → Telescope
      vim.schedule(function()
        local pickers = require("telescope.pickers")
        local finders = require("telescope.finders")
        local conf = require("telescope.config").values
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")

        local entries = {}
        for _, s in ipairs(sites) do
          local short = vim.fn.fnamemodify(s.filename, ":~:.")
          table.insert(entries, {
            display = string.format("%s — %s:%d", s.caller_name, short, s.lnum),
            filename = s.filename,
            lnum = s.lnum,
            col = s.col,
          })
        end

        pickers.new({}, {
          prompt_title = "Callers",
          finder = finders.new_table({
            results = entries,
            entry_maker = function(e)
              return {
                value = e,
                display = e.display,
                ordinal = e.display,
                filename = e.filename,
                lnum = e.lnum,
                col = e.col + 1,
              }
            end,
          }),
          sorter = conf.generic_sorter({}),
          previewer = conf.grep_previewer({}),
          attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
              actions.close(prompt_bufnr)
              local sel = action_state.get_selected_entry()
              if sel then
                jump_to(sel.value)
              end
            end)
            return true
          end,
        }):find()
      end)
    end)
  end)
end

return M
