-- post_commit_reject 行为测试：用桩对象模拟 librime Lua API，运行真实模块逻辑。
-- 运行：lua5.2 rime/tests/test_post_commit_reject.lua [模块路径]

-- 生产环境由 librime-lua 注册全局 yield（= lua_yield），此处等价替代
_G.yield = _G.yield or coroutine.yield

-- Lua 5.2 无内置 utf8，桩提供等价实现（统计 UTF-8 码点起点）
_G.utf8 = _G.utf8 or { len = function(s)
  local n = 0
  for i = 1, #s do
    local b = s:byte(i)
    if b < 0x80 or b >= 0xC0 then n = n + 1 end
  end
  return n
end }

local module_path = arg and arg[1] or "rime/lua/post_commit_reject.lua"

local XK_BackSpace = 0xFF08
local XK_Return = 0xFF0D
local XK_Escape = 0xFF1B
local XK_space = 0x20

-- 桩：KeyEvent
local function new_key_event(keycode, opts)
  opts = opts or {}
  return {
    keycode = keycode,
    release = function() return opts.release or false end,
    ctrl = function() return opts.ctrl or false end,
    alt = function() return opts.alt or false end,
    super = function() return opts.super or false end,
    shift = function() return opts.shift or false end,
  }
end

-- 桩：Context + commit_history（record 为 {type=, text=}）
local function new_context()
  local ctx = {
    input = "",
    _composing = false,
    _history = {},
  }
  ctx.commit_history = {
    repr = function()
      local parts = {}
      for _, r in ipairs(ctx._history) do
        parts[#parts + 1] = "[" .. r.type .. "]" .. r.text
      end
      return table.concat(parts)
    end,
    back = function()
      if #ctx._history == 0 then return nil end
      return ctx._history[#ctx._history]
    end,
  }
  function ctx:is_composing() return self._composing end
  return ctx
end

local function new_env(ctx)
  return { engine = { context = ctx } }
end

-- 桩：Translation（候选为文本列表，iter 逐个返回 {text=}）
local function new_translation(texts)
  local i = 0
  return {
    iter = function()
      return function()
        i = i + 1
        return texts[i] and { text = texts[i] } or nil
      end
    end,
  }
end

-- 以协程方式运行 filter（与 librime 的 LuaFilter 运行方式一致），返回产出文本
local function run_filter(module, env, texts)
  local co = coroutine.create(function(t, e)
    module.reorder(t, e)
  end)
  local out = {}
  local args = { new_translation(texts), env }
  while true do
    local ok, v = coroutine.resume(co, table.unpack(args))
    args = {}
    if not ok then error(v, 2) end
    if v == nil then break end
    out[#out + 1] = v.text
  end
  return out
end

-- 每轮测试加载全新模块实例，隔离模块级状态
local function fresh_module()
  return dofile(module_path)
end

-- 模拟按键后的引擎行为（镜像 ConcreteEngine::ProcessKey 的未处理键分支：
-- 非组合态下的 BackSpace/Return 清空 history，可打印字符推入 thru 记录）
local function engine_after_unhandled(ctx, keycode, opts)
  opts = opts or {}
  if opts.modified or opts.shift then return end
  if keycode == XK_BackSpace or keycode == XK_Return then
    ctx._history = {}
  elseif keycode >= 0x20 and keycode <= 0x7e then
    table.insert(ctx._history, { type = "thru", text = string.char(keycode) })
  end
end

-- 输入字母：processor 先见按键前状态，随后 speller 把字母加入 input 并进入组合
local function type_letters(module, env, ctx, str)
  for i = 1, #str do
    local c = str:sub(i, i)
    module.processor(new_key_event(string.byte(c)), env)
    ctx.input = ctx.input .. c
    ctx._composing = true
  end
end

-- 空格提交：processor 见 Space，随后 Context::Commit（history 推记录 + 清空组合）
local function press_space_commit(module, env, ctx, rtype, text)
  module.processor(new_key_event(XK_space), env)
  table.insert(ctx._history, { type = rtype, text = text })
  ctx.input = ""
  ctx._composing = false
end

-- 按 Backspace：processor 处理后按引擎行为处理 history
local function press_backspace(module, env, ctx, opts)
  local was_composing = ctx._composing
  module.processor(new_key_event(XK_BackSpace, opts or {}), env)
  if was_composing then
    -- 组合中由 express_editor 处理，不推 history
    ctx.input = ctx.input:sub(1, -2)
    if #ctx.input == 0 then ctx._composing = false end
  else
    engine_after_unhandled(ctx, XK_BackSpace, opts)
  end
end

-- Escape：清空组合，history 不变
local function press_escape(module, env, ctx)
  module.processor(new_key_event(XK_Escape), env)
  ctx.input = ""
  ctx._composing = false
end

local tests = {}
local function test(name, fn)
  tests[#tests + 1] = { name = name, fn = fn }
end

test("processor 始终返回 kNoop，不干扰按键", function()
  local module = fresh_module()
  local ctx = new_context()
  local env = new_env(ctx)
  assert(module.processor(new_key_event(string.byte("n")), env) == 2)
  ctx.input, ctx._composing = "n", true
  assert(module.processor(new_key_event(XK_BackSpace), env) == 2)
  assert(module.processor(new_key_event(0xFFE1), env) == 2) -- Shift
  assert(module.processor(new_key_event(string.byte("x"), { ctrl = true }), env) == 2)
  assert(module.processor(new_key_event(XK_BackSpace, { release = true }), env) == 2)
end)

test("空格提交→连续删除→重新输入交换并消费", function()
  local module = fresh_module()
  local ctx = new_context()
  local env = new_env(ctx)

  type_letters(module, env, ctx, "nihao")
  press_space_commit(module, env, ctx, "phrase", "你好")
  press_backspace(module, env, ctx)
  press_backspace(module, env, ctx)

  type_letters(module, env, ctx, "nihao")
  local out = run_filter(module, env, { "你好", "拟好", "你号" })
  assert(out[1] == "拟好" and out[2] == "你好" and out[3] == "你号",
    "期望 [拟好,你好,你号]，得到 [" .. table.concat(out, ",") .. "]")

  -- 一次性：消费后再次输入不再交换
  ctx.input, ctx._composing = "", false
  type_letters(module, env, ctx, "nihao")
  local out2 = run_filter(module, env, { "你好", "拟好", "你号" })
  assert(out2[1] == "你好" and out2[2] == "拟好", "rejection 应已消费")
end)

test("点击候选提交：编码由组合中预测补全", function()
  local module = fresh_module()
  local ctx = new_context()
  local env = new_env(ctx)

  type_letters(module, env, ctx, "nihao")
  -- 点击候选直接上屏（无按键事件）
  table.insert(ctx._history, { type = "phrase", text = "拟好" })
  ctx.input, ctx._composing = "", false

  press_backspace(module, env, ctx)
  press_backspace(module, env, ctx)

  type_letters(module, env, ctx, "nihao")
  local out = run_filter(module, env, { "你好", "拟好", "你号" })
  assert(out[1] == "你好" and out[2] == "你号" and out[3] == "拟好",
    "期望 [你好,你号,拟好]（编码应为 nihao 而非 niha），得到 ["
      .. table.concat(out, ",") .. "]")
end)

test("数字键选择上屏：编码与文本正确记录", function()
  local module = fresh_module()
  local ctx = new_context()
  local env = new_env(ctx)

  type_letters(module, env, ctx, "nihao")
  module.processor(new_key_event(string.byte("2")), env)
  table.insert(ctx._history, { type = "phrase", text = "拟好" })
  ctx.input, ctx._composing = "", false

  press_backspace(module, env, ctx)
  press_backspace(module, env, ctx)

  type_letters(module, env, ctx, "nihao")
  local out = run_filter(module, env, { "你好", "拟好", "你号" })
  assert(out[1] == "你好" and out[2] == "你号" and out[3] == "拟好",
    "期望 [你好,你号,拟好]，得到 [" .. table.concat(out, ",") .. "]")
end)

test("删除一半后输入其他字符：取消，不记录", function()
  local module = fresh_module()
  local ctx = new_context()
  local env = new_env(ctx)

  type_letters(module, env, ctx, "nihao")
  press_space_commit(module, env, ctx, "phrase", "你好")
  press_backspace(module, env, ctx) -- 只删了一个字
  type_letters(module, env, ctx, "x") -- 输入其他字符（开始新组合）

  ctx.input, ctx._composing = "", false
  type_letters(module, env, ctx, "nihao")
  local out = run_filter(module, env, { "你好", "拟好", "你号" })
  assert(out[1] == "你好" and out[2] == "拟好", "取消后不应交换")
end)

test("上屏后第一个键非 Backspace：不记录", function()
  local module = fresh_module()
  local ctx = new_context()
  local env = new_env(ctx)

  type_letters(module, env, ctx, "nihao")
  press_space_commit(module, env, ctx, "phrase", "你好")
  type_letters(module, env, ctx, "a") -- 先输入字符（新组合），再按 Backspace
  press_backspace(module, env, ctx)

  ctx.input, ctx._composing = "", false
  type_letters(module, env, ctx, "nihao")
  local out = run_filter(module, env, { "你好", "拟好", "你号" })
  assert(out[1] == "你好", "上屏后先输入字符不应记录")
end)

test("旧上屏记录 + Escape 放弃组合后按 Backspace：不误判", function()
  local module = fresh_module()
  local ctx = new_context()
  local env = new_env(ctx)

  type_letters(module, env, ctx, "nihao")
  press_space_commit(module, env, ctx, "phrase", "你好")
  type_letters(module, env, ctx, "nihao") -- 重新组合，history 仍留有旧上屏记录
  press_escape(module, env, ctx) -- 放弃组合，history 不变
  press_backspace(module, env, ctx) -- back() 仍是旧记录，但 repr 未变 → 不应误判

  type_letters(module, env, ctx, "nihao")
  local out = run_filter(module, env, { "你好", "拟好", "你号" })
  assert(out[1] == "你好", "Escape 放弃后不应产生 rejection")
end)

test("标点上屏（punct）不记录", function()
  local module = fresh_module()
  local ctx = new_context()
  local env = new_env(ctx)

  type_letters(module, env, ctx, "nihao")
  table.insert(ctx._history, { type = "punct", text = "," })
  ctx.input, ctx._composing = "", false

  press_backspace(module, env, ctx)
  press_backspace(module, env, ctx)

  type_letters(module, env, ctx, "nihao")
  local out = run_filter(module, env, { "你好", "拟好", "你号" })
  assert(out[1] == "你好", "标点上屏不应产生 rejection")
end)

test("编码匹配但候选无被拒文本：不交换也不消费", function()
  local module = fresh_module()
  local ctx = new_context()
  local env = new_env(ctx)

  type_letters(module, env, ctx, "nihao")
  press_space_commit(module, env, ctx, "phrase", "你好")
  press_backspace(module, env, ctx)
  press_backspace(module, env, ctx)
  -- phase = rejected

  -- 英文等其他模式：同编码但候选不含「你好」
  ctx.input = "nihao"
  ctx._composing = true
  local out = run_filter(module, env, { "Ni", "Hao" })
  assert(out[1] == "Ni" and out[2] == "Hao", "无被拒文本时原样输出")
  -- 不应消费：回拼音后交换仍生效
  ctx.input, ctx._composing = "", false
  type_letters(module, env, ctx, "nihao")
  local out2 = run_filter(module, env, { "你好", "拟好", "你号" })
  assert(out2[1] == "拟好" and out2[2] == "你好", "rejection 应保留")
end)

test("被拒文本在末位：不交换也不消费", function()
  local module = fresh_module()
  local ctx = new_context()
  local env = new_env(ctx)

  type_letters(module, env, ctx, "nihao")
  press_space_commit(module, env, ctx, "phrase", "你好")
  press_backspace(module, env, ctx)
  press_backspace(module, env, ctx)

  type_letters(module, env, ctx, "nihao")
  local out = run_filter(module, env, { "拟好", "你好" })
  assert(out[1] == "拟好" and out[2] == "你好", "末位不应交换")
  -- 未消费：候选出现下一项时仍可交换
  ctx.input, ctx._composing = "", false
  type_letters(module, env, ctx, "nihao")
  local out2 = run_filter(module, env, { "你好", "拟好", "你号" })
  assert(out2[1] == "拟好" and out2[2] == "你好", "rejection 应保留")
end)

test("单字上屏：1 个 Backspace 即记录", function()
  local module = fresh_module()
  local ctx = new_context()
  local env = new_env(ctx)

  type_letters(module, env, ctx, "n")
  press_space_commit(module, env, ctx, "phrase", "你")
  press_backspace(module, env, ctx)

  type_letters(module, env, ctx, "n")
  local out = run_filter(module, env, { "你", "泥" })
  assert(out[1] == "泥" and out[2] == "你", "单字 rejection 应生效")
end)

test("user_phrase 类型同样记录", function()
  local module = fresh_module()
  local ctx = new_context()
  local env = new_env(ctx)

  type_letters(module, env, ctx, "nihao")
  press_space_commit(module, env, ctx, "user_phrase", "你好")
  press_backspace(module, env, ctx)
  press_backspace(module, env, ctx)

  type_letters(module, env, ctx, "nihao")
  local out = run_filter(module, env, { "你好", "拟好", "你号" })
  assert(out[1] == "拟好" and out[2] == "你好", "user_phrase 应记录")
end)

test("direct_uppercase 等 raw 上屏不记录", function()
  local module = fresh_module()
  local ctx = new_context()
  local env = new_env(ctx)

  -- 非组合态 Shift+N：direct_uppercase 直接上屏大写
  table.insert(ctx._history, { type = "raw", text = "N" })
  ctx.input, ctx._composing = "", false
  press_backspace(module, env, ctx)
  press_backspace(module, env, ctx)

  type_letters(module, env, ctx, "nihao")
  local out = run_filter(module, env, { "你好", "拟好", "你号" })
  assert(out[1] == "你好", "raw 上屏不应记录")
end)

local failed = 0
for _, t in ipairs(tests) do
  local ok, err = pcall(t.fn)
  if ok then
    print("[PASS] " .. t.name)
  else
    failed = failed + 1
    print("[FAIL] " .. t.name)
    print("       " .. tostring(err))
  end
end
if failed > 0 then
  print(failed .. " of " .. #tests .. " tests failed")
  os.exit(1)
end
print("all " .. #tests .. " tests passed")
