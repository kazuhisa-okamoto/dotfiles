-- WezTerm の workspace 復元 (wezterm/workspace_session.lua) と連携する。
-- WezTerm の pane で直接起動した nvim だけが対象で、次の 2 つのファイルを書く。
--   panes/<WEZTERM_PANE>.nvim.json : この pane で nvim が動いているという目印
--   nvim/<pid>.vim                 : :mksession で書いた編集状態 (WezTerm は復元時に nvim -S で読む)
-- :q などで普通に終了したときは両方消す。WezTerm ごと閉じたときはセッションファイルを残し、
-- WezTerm は次回の起動時にそれを使って復元する
local M = {}

-- セッションに保存する項目。terminal / help / 空のウィンドウは復元しても意味がないので外す
local sessionoptions = "buffers,curdir,folds,tabpages,winsize"

-- pane ごと閉じられた nvim のセッションファイルは誰も消さないので、古くなったら消す
local stale_seconds = 7 * 24 * 60 * 60

local function normalize(path)
  return vim.fs.normalize(path):lower()
end

-- WezTerm が保存した state.json から参照されていない、古いセッションファイルを消す
local function remove_stale_sessions(dir, session_dir)
  local f = io.open(vim.fs.joinpath(dir, "state.json"), "rb")
  local state = f and f:read("*a") or ""
  if f then
    f:close()
  end
  local now = os.time()
  for name, kind in vim.fs.dir(session_dir) do
    local path = vim.fs.joinpath(session_dir, name)
    local stat = kind == "file" and vim.uv.fs_stat(path)
    if stat and now - stat.mtime.sec > stale_seconds
        and not state:find("[^%d]" .. vim.pesc(name) .. '"') then
      os.remove(path)
    end
  end
end

function M.setup()
  local dir = vim.env.WEZTERM_WORKSPACE_SESSION_DIR
  local pane_id = vim.env.WEZTERM_PANE
  -- WezTerm の外や、nvim の :terminal の中 ($NVIM が入る) で起動したときは何もしない。
  -- ほかの WezTerm が動いているあいだに起動した WezTerm は、この変数を空にしている
  if not dir or dir == "" or not pane_id or vim.env.NVIM then
    return
  end

  local session_dir = vim.fs.joinpath(dir, "nvim")
  local session_file = vim.fs.joinpath(session_dir, vim.fn.getpid() .. ".vim")
  local marker = vim.fs.joinpath(dir, "panes", pane_id .. ".nvim.json")

  local function write_session()
    local saved = vim.o.sessionoptions
    vim.o.sessionoptions = sessionoptions
    pcall(vim.cmd, "mksession! " .. vim.fn.fnameescape(session_file))
    vim.o.sessionoptions = saved
  end

  -- 画面の変化が続いても書くのは 1 秒に 1 回まで
  local timer = assert(vim.uv.new_timer())
  local function schedule_write()
    timer:stop()
    timer:start(1000, 0, vim.schedule_wrap(write_session))
  end

  -- 復元で読み込んだ前回の nvim のセッションファイルは、読み終えたら要らない
  local function remove_loaded_session()
    local loaded = vim.v.this_session
    if loaded ~= "" and normalize(vim.fs.dirname(loaded)) == normalize(session_dir)
        and normalize(loaded) ~= normalize(session_file) then
      os.remove(loaded)
    end
  end

  local group = vim.api.nvim_create_augroup("WeztermSession", { clear = true })
  vim.api.nvim_create_autocmd("VimEnter", {
    group = group,
    callback = function()
      vim.fn.mkdir(session_dir, "p")
      vim.fn.mkdir(vim.fs.dirname(marker), "p")
      remove_loaded_session()
      write_session()
      vim.fn.writefile({ vim.json.encode({ session_file = session_file }) }, marker)
      vim.defer_fn(function()
        remove_stale_sessions(dir, session_dir)
      end, 3000)

      vim.api.nvim_create_autocmd({
        "BufEnter", "BufWritePost", "WinNew", "WinClosed", "TabNew", "TabClosed",
        "VimResized", "CursorHold", "FocusLost",
      }, { group = group, callback = schedule_write })
      vim.api.nvim_create_autocmd("SessionLoadPost", { group = group, callback = remove_loaded_session })
      vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
          timer:stop()
          os.remove(marker)
          -- WezTerm ごと閉じたときは、画面を描く TUI のプロセスが先に消えてから本体が終了するので
          -- UI が 1 つも無い。そのときは次回の復元のためにセッションファイルを残す
          if #vim.api.nvim_list_uis() > 0 then
            os.remove(session_file)
          end
        end,
      })
    end,
  })
end

return M
