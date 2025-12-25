-- AI Tests for LiteXL
-- Run these tests by loading this file when the editor starts
-- or via: lua data/tests/ai_tests.lua

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    print(string.format("[PASS] %s", name))
    return true
  else
    print(string.format("[FAIL] %s", name))
    print("       " .. tostring(err))
    return false
  end
end

local function run_tests()
  print("\n=== AI Module Tests ===\n")
  
  local passed = 0
  local failed = 0
  
  -- Test 1: AI module loads
  if test("ai module loads", function()
    local ai = require "core.ai"
    assert(ai, "ai module should exist")
    assert(ai.chat, "ai.chat should exist")
    assert(ai.stream, "ai.stream should exist")
    assert(ai.completion, "ai.completion should exist")
  end) then passed = passed + 1 else failed = failed + 1 end
  
  -- Test 2: JSON encode
  if test("json_encode basic types", function()
    local ai = require "core.ai"
    assert(ai.json_encode(nil) == "null", "nil should encode to null")
    assert(ai.json_encode(true) == "true", "true should encode to true")
    assert(ai.json_encode(false) == "false", "false should encode to false")
    assert(ai.json_encode(42) == "42", "number should encode correctly")
    assert(ai.json_encode("hello") == '"hello"', "string should encode correctly")
  end) then passed = passed + 1 else failed = failed + 1 end
  
  -- Test 3: JSON encode tables
  if test("json_encode tables", function()
    local ai = require "core.ai"
    local arr = ai.json_encode({1, 2, 3})
    assert(arr == "[1,2,3]", "array should encode: got " .. arr)
    local obj = ai.json_encode({a = 1})
    assert(obj:find('"a":1'), "object should encode: got " .. obj)
  end) then passed = passed + 1 else failed = failed + 1 end
  
  -- Test 4: JSON decode
  if test("json_decode basic types", function()
    local ai = require "core.ai"
    assert(ai.json_decode("null") == nil, "null should decode to nil")
    assert(ai.json_decode("true") == true, "true should decode to true")
    assert(ai.json_decode("false") == false, "false should decode to false")
    assert(ai.json_decode("42") == 42, "number should decode correctly")
    assert(ai.json_decode('"hello"') == "hello", "string should decode correctly")
  end) then passed = passed + 1 else failed = failed + 1 end
  
  -- Test 5: JSON decode complex
  if test("json_decode complex", function()
    local ai = require "core.ai"
    local obj = ai.json_decode('{"name":"test","count":5}')
    assert(obj.name == "test", "object property should decode")
    assert(obj.count == 5, "number property should decode")
    local arr = ai.json_decode('[1,2,3]')
    assert(#arr == 3, "array length should be 3")
    assert(arr[1] == 1, "array element should decode")
  end) then passed = passed + 1 else failed = failed + 1 end
  
  -- Test 6: Tools module loads
  if test("tools module loads", function()
    local tools = require "core.tools"
    assert(tools, "tools module should exist")
    assert(tools.register, "tools.register should exist")
    assert(tools.execute, "tools.execute should exist")
    assert(tools.get_all, "tools.get_all should exist")
  end) then passed = passed + 1 else failed = failed + 1 end
  
  -- Test 7: Built-in tools registered
  if test("built-in tools registered", function()
    local tools = require "core.tools"
    local all = tools.get_all()
    assert(#all >= 5, "should have at least 5 built-in tools")
    
    local tool_names = {}
    for _, t in ipairs(all) do
      tool_names[t.name] = true
    end
    
    assert(tool_names["read_file"], "read_file tool should exist")
    assert(tool_names["write_file"], "write_file tool should exist")
    assert(tool_names["edit_file"], "edit_file tool should exist")
    assert(tool_names["search_project"], "search_project tool should exist")
    assert(tool_names["list_files"], "list_files tool should exist")
    assert(tool_names["run_command"], "run_command tool should exist")
  end) then passed = passed + 1 else failed = failed + 1 end
  
  -- Test 8: Tool execution
  if test("tool execution works", function()
    local tools = require "core.tools"
    
    -- Register a test tool
    tools.register("test_add", {
      description = "Test tool that adds two numbers",
      fn = function(args)
        return args.a + args.b
      end
    })
    
    local result, err = tools.execute("test_add", { a = 2, b = 3 })
    assert(err == nil, "should not have error")
    assert(result == 5, "result should be 5, got " .. tostring(result))
    
    tools.unregister("test_add")
  end) then passed = passed + 1 else failed = failed + 1 end
  
  -- Test 9: OpenAI format generation
  if test("tools OpenAI format", function()
    local tools = require "core.tools"
    local format = tools.get_openai_format()
    assert(#format > 0, "should have tools in OpenAI format")
    assert(format[1].type == "function", "type should be function")
    assert(format[1]["function"].name, "should have function name")
    assert(format[1]["function"].description, "should have description")
  end) then passed = passed + 1 else failed = failed + 1 end
  
  -- Test 10: Agent module loads
  if test("agent module loads", function()
    local agent_mod = require "core.agent"
    assert(agent_mod, "agent module should exist")
    assert(agent_mod.new, "agent.new should exist")
    assert(agent_mod.Agent, "agent.Agent should exist")
  end) then passed = passed + 1 else failed = failed + 1 end
  
  -- Test 11: Agent creation
  if test("agent creation works", function()
    local agent_mod = require "core.agent"
    local agent = agent_mod.new({
      system_prompt = "Test agent"
    })
    assert(agent, "agent should be created")
    assert(agent.messages, "agent should have messages")
    assert(#agent.messages == 1, "agent should have system message")
    assert(agent.messages[1].role == "system", "first message should be system")
    assert(agent:get_state_string() == "idle", "agent should start idle")
  end) then passed = passed + 1 else failed = failed + 1 end
  
  -- Test 12: Agent clear
  if test("agent clear works", function()
    local agent_mod = require "core.agent"
    local agent = agent_mod.new()
    agent:add_user_message("test")
    assert(#agent.messages == 2, "should have 2 messages")
    agent:clear()
    assert(#agent.messages == 1, "should have 1 message after clear")
    assert(agent.messages[1].role == "system", "should keep system prompt")
  end) then passed = passed + 1 else failed = failed + 1 end
  
  print(string.format("\n=== Results: %d passed, %d failed ===\n", passed, failed))
  
  return failed == 0
end

-- Export for running in editor
return {
  run = run_tests
}
