-- Test setup for busted

-- Lua version compatibility - ensure unpack is available
if not _G.unpack then
  _G.unpack = table.unpack
end

-- Create mock vim API if we're running tests outside of Neovim
if not _G.vim then
  _G.vim = require("tests.mocks.vim")
end

-- Ensure vim global is accessible
_G.vim = _G.vim or {}

-- Setup test globals
_G.assert = require("luassert")

-- Helper function to verify expectations
_G.expect = function(value)
  return {
    to_be = function(expected)
      assert.are.equal(expected, value)
    end,
    to_be_nil = function()
      assert.is_nil(value)
    end,
    to_be_true = function()
      assert.is_true(value)
    end,
    to_be_false = function()
      assert.is_false(value)
    end,
    to_be_table = function()
      assert.is_table(value)
    end,
    to_be_string = function()
      assert.is_string(value)
    end,
    to_be_function = function()
      assert.is_function(value)
    end,
    to_be_boolean = function()
      assert.is_boolean(value)
    end,
    to_be_at_least = function(expected)
      assert.is_true(value >= expected)
    end,
    to_have_key = function(key)
      assert.is_table(value)
      assert.not_nil(value[key])
    end,
    -- to_contain was here, moved to _G.assert_contains
    not_to_be_nil = function()
      assert.is_not_nil(value)
    end,
    -- not_to_contain was here, moved to _G.assert_not_contains
    to_be_truthy = function()
      assert.is_truthy(value)
    end,
  }
end

_G.assert_contains = function(actual_value, expected_pattern)
  if type(actual_value) == "string" then
    if type(expected_pattern) ~= "string" then
      error(
        "assert_contains expected a string pattern for a string actual_value, but expected_pattern was type: "
          .. type(expected_pattern)
      )
    end
    assert.is_true(
      string.find(actual_value, expected_pattern, 1, true) ~= nil,
      "Expected string '" .. actual_value .. "' to contain '" .. expected_pattern .. "'"
    )
  elseif type(actual_value) == "table" then
    local found = false
    for _, v in ipairs(actual_value) do
      if v == expected_pattern then
        found = true
        break
      end
    end
    assert.is_true(found, "Expected table to contain value: " .. tostring(expected_pattern))
  else
    error("assert_contains can only be used with string or table actual_values, got type: " .. type(actual_value))
  end
end

_G.assert_not_contains = function(actual_value, expected_pattern)
  if type(actual_value) == "string" then
    if type(expected_pattern) ~= "string" then
      error(
        "assert_not_contains expected a string pattern for a string actual_value, but expected_pattern was type: "
          .. type(expected_pattern)
      )
    end
    assert.is_true(
      string.find(actual_value, expected_pattern, 1, true) == nil,
      "Expected string '" .. actual_value .. "' NOT to contain '" .. expected_pattern .. "'"
    )
  elseif type(actual_value) == "table" then
    local found = false
    for _, v in ipairs(actual_value) do
      if v == expected_pattern then
        found = true
        break
      end
    end
    assert.is_false(found, "Expected table NOT to contain value: " .. tostring(expected_pattern))
  else
    error("assert_not_contains can only be used with string or table actual_values, got type: " .. type(actual_value))
  end
end

-- Return true to indicate setup was successful
return true
