DEBUG = not fangari;
local js = nil;
if fengari then
  js = require "js";
else
  package.path = "scripts/?.lua";
end

local line_number;
local compile_file;
local _cache = {};

-- Defined here to pick up compile_file and line_number
function error_lexer(msg, _)
  error(string.format("%s:%s: %s", compile_file, line_number, msg), 0);
end

for _, lib in ipairs {"base64", "lexer-functions"} do
  if DEBUG then
    dofile(package.path:gsub("?", lib));
  else
    require(lib);
  end
end

do
  local assert_old = assert;

  local function assert_lexer(test, msg)
    if not test then
      error_lexer(msg);
    end

    return test;
  end

  function lua_main(func, arg1, arg2, arg3)
    local status, ret;

    if func == "compile" then
      assert = assert_lexer;
      local exported = {};

      for i = 1, #arg1 do
        status, ret = pcall(compile, pair.name, pair.text, arg2, arg3);

        if not status then
          assert = assert_old;
          if js then
            -- Fengari has a bug where it can return a native JS exception object
            ret = js.tostring(ret);
          end
          return false, pair.name .. "\n" .. ret;
        end

        exported[i] = ret;
      end
      assert = assert_old;
      return true, exported;
    elseif func == "import" then
      status, ret = pcall(import, arg1);
      if status then
        return true, ret[1], ret[2];
      end
    elseif func == "unittest" then
      status, ret = pcall(unittest);
    else
      assert(false, "BUG REPORT: unknown lua_main function: " .. func);
    end

    return status, ret;
  end
end

local function cache(line, variables)
  local key = {};

  for _, v in pairs(variables) do
    key[#key+1] = string.format("%s.%s.%s.%s", v.scope, v.type, v.name, v.value);
  end

  table.sort(key);
  key[#key+1] = line;

  local formed_key = table.concat(key, "¤");
  if not _cache[formed_key] then
    _cache[formed_key] = lexer(line, variable);
  end

  return _cache[formed_key];
end

local function parseMacro(text, macros, depth, env)
  assert(depth < 100, "macro expansion depth reached " .. depth .. ", probable infinite loop in " .. text);
  local function expand_macro(macro)
    if #macro == 2 then
      return;
    end

    local parsed_macro = parseMacro(macro:sub(2, -2), macros, depth + 1, env) or "";
    local arg_body = "";
    local name = parsed_macro:match("^([^%(]+)$");
    if not name then
      name, arg_body = parsed_macro:match("^([^(%]+)(%b())");
    end
    assert(name, "invalid macro call: " .. name);
    assert(#name + #arg_body == #parsed_macro, "trailing junk after macro call: " .. name);

    if name == "len" then
      assert(arg_body ~= "", "len is a macro function");
      return tostring(#arg_body - 2);

    elseif name == "lua" then
      assert(arg_body ~= "", "lua is a macro function");
      local lua_text = arg_body:sub(2, -2);
      local chunk, err = load(lua_text, lua_text, "t", env);
      assert(chunk, err);

      local status, result = pcall(chunk);
      if status then
        return tostring(result or "");
      end
      error_lexer(result);
    end

    local args = {};
    local arg_count = 0;
    local arg_begin = 2;
    local nesting = 0;

    for i = 2, #arg_body do
      local char = arg_body:sub(i, i);
      if nesting == 0 and (char == "," or i == #arg_body) then
        args["{#" .. arg_count .. "#}"] = arg_body:sub(arg_begin, i - 1);
        arg_count = arg_count + 1;
        arg_begin = i + 1;
      elseif char == "(" then
        nesting = nesting + 1;
      elseif char == ")" and i ~= #arg_body then
        nesting = nesting - 1;
        assert(nesting >= 0, "unbalanced parenthesis inside macro call: " .. parsed_macro);
      end
    end

    assert(nesting == 0, "unclosed parenthesis inside macro call: " .. macro);

    local macro_obj = macros[name];
    assert(macro_obj, "macro does not exist: " .. name);

    local unexpanded, arg_len = macro_obj.text, macro_obj.arg_len;
    assert(arg_len == arg_count, "macro call has wrong number of args, expected " ..
      arg_len .. "but got" .. arg_count .. ": " .. macro);
    return parseMacro(unexpanded:gsub("{#[0-9]+#}", args), macros, depth + 1, env);
  end

  return text:gsub("%b{}", expand_macro);
end

-- Whitelist of functions and tables that are allowed in the lua() macro.
-- We store this as a string so that we can bind the names properly.
local globals_whitelist = {};
for k in string.match([[
assert
error
getmetatable
ipairs
load
next
pairs
pcall
prints
rawequal
rawget
rawlen
rawset
select
setmetatable
tonumber
tostring
type
_VERSION
xpcall
coroutine
string
utf8
table
math
]], "%g+") do globals_whitelist[#globals_whitelist+1] = k; end
local os_whitelist = {"clock", "date", "difftime", "time"};

local function filter_table(table_in, whitelist)
  local res = {};
  for i = 1, #whitelist do
    local k = whitelist[i];
    local v = table_in[k];

    if type(v) == "table" then
      local new_tab = {};
      for k2, v2 in ipairs(v) do
        new_tab[k2] = v2;
      end
      v = new_tab;
    end
    res[k] = v;
  end

  return res;
end

local function clone_global()
  local new_global = filter_table(_G, globals_whitelist);
  new_global.os = filter_table(_G.os, os_whitelist);
  new_global._G = new_global;
  return new_global;
end

local function is_empty(line)
  return line:find("^%s*$") or line:find("^%s*;.*$");
end

local json_escape_table = {
  ["\\"] = [[\\]],
  ['"'] = [[\"]]
}

for i = 0, 31 do
  json_escape_table[string.char(i)] = string.format([[\u%04x]], i);
end
json_escape_table["\b"] = [[\b]];
json_escape_table["\f"] = [[\f]];
json_escape_table["\n"] = [[\n]];
json_escape_table["\r"] = [[\r]];
json_escape_table["\t"] = [[\t]];

local line_encode_table = {};
local utf_decode_table = {};
for k, v in pairs(json_escape_table) do
  line_encode_table[k] = v;
end
for i = 0x80, 0xFF do
  line_encode_table[string.char(i)] = utf8.char(i);
  utf_decode_table[utf8.char(i)] = string.char(i);
end


do
  local variables, impulses, conditions, actions;
  local budget, use_budget;
  local macros, imported;
  local env;
  local ret;

  local function import(file_name, input, is_import, importFunc)
    if imported[file_name] then
      return {};
    end
    imported[file_name] = true;
    line_number = 0;
    compile_file = file_name;

    local lines = {};
    local line_cache = {};
    local label_cache = {};

    for real_line in input:gmatch("[^\n]*") do
      line_number = line_number + 1;

      if real_line:sub(-1) == "\\" then
        line_cache[#line_cache+1] = real_line:sub(1, -2);
      else

        line_cache[#line_cache+1] = real_line;
        local line = table.concat(line_cache):gsub("^%s+", ""):gsub("%s+$", "");
        if line:sub(1, 1) ~= "#" then
          line = parseMacro(line, macros, 1, env);
        end

        line_cache = {};
        if line:match("^#") then
          local macro_args = "";
          local name, macro = line:sub(2):match(TOKEN.identifier.pattern .. " (.+)$");
          if not name then
            name, macro_args, macro = line:sub(2):match(TOKEN.identifier.pattern .. "(%([%w%._ ,]+%)) (.+)$");
          end
          assert(name, "macro definition: #name <text> or #name(args...) <text>");

          local args = {};
          local arg_len = 0;
          local arg_begin = 2;
          while arg_begin <= #macro_args do
            local pos = macro_args:find(",", arg_begin, true);
            if not pos then
              pos = #macro_args;
            end

            local arg_string = macro_args:sub(arg_begin, pos - 1);
            local arg = arg_string:match("^ " .. TOKEN.identifier.patternAnywhere .. " *$");
            assert(arg, "bad macro function argument name: " .. arg_string);
            args["{" .. arg .. "}"] = "{#" .. arg_len .. "#}";
            arg_len = arg_len + 1;
            arg_begin = pos + 1;
          end

          assert(not macros[name], "macro already exists: " .. name);
          macros[name] = {text = macro:gsub("{[^{}]+}", args), arg_len = arg_len};
        elseif line:match("^:") then
          local token = line:match("^:" .. TOKEN.identifier.patternAnywhere);
          if token == "const" then
            local _, type, name, value = line:sub(2):match("^(%a+) (%a+) " .. TOKEN.identifier.patternAnywhere .. " (.+)$");
            assert(type, "constant definition: const [int/double/string/bool/vector] name value");
            assert(
              ({bool = true, int = true, double = true, string = true, vector = true})[type],
              "constant types are 'int', 'double', 'string', 'bool' and 'vector'"
            );

            if (type == "int" or type == "double") then
              assert(
                (value:match("^%d+$") and type == "int") or (value:match("^%d+%.%d*$") and type == "double"),
                "bad argument, " .. type .. " expected, got " .. value
              );
              value = tonumber(value);

            elseif type == "bool" then
              assert(value:match("^true$") or value:match("^false$"), "bool values are 'true' or 'false'");
              value = value:match("^true$");
              -- returns true if value is true and false if value is false

            elseif type == "string" then
              value = value:match("^%b''") or value:match('^%b""$');
              assert(value, "strings must be enclosed in either single or double quotes");
              value = value:sub(2, -2);
            
            elseif type == "vector" then
              local matches = table.pack(value:match("^vec%((.+),(.+)%)$"));
              assert(matches.n > 1, "vector constants must use vec(x, y) syntax");
              local x = tonumber(matches[1]);
              assert(x, "Can not convernt '" .. matches[1] .. "' to a number");
              local y = tonumber(matches[2]);
              assert(y, "Can not convert '" .. matches[2] .. "' to a number");
              value = {x = x, y = y};
            end

            assert(not variables[name], "variable/label/constant already exists: " .. name);
            variables[name] = {name = name, scope = "constant", type = type, value = value};
          
          elseif token == "import" then
            local import_name = line:match("^:%a+ +(.+)");
            assert(import_name, "import directive: :import file");

            local status, import_result = importFunc(import_name);
            assert(status, "Import failed: " .. import_result);

            local saved_line_number, saved_compile_file = line_number, compile_file;
            local _ = import(import_name, import_result, true, importFunc);

            -- These get stomped by the import. re-set them
            line_number, compile_file = saved_line_number, saved_compile_file;

          elseif token == "global" or token == "local" then
            local scope, type, name;
            scope, type, name = line:sub(2):gsub(" *;.*", ""):match("^(%a+) +(%a+) +" .. TOKEN.identifier.patternAnywhere .. "$");
            assert(scope, "variable definition: [global/local] [bool/int/double/string/vector] name");

            assert(
              ({bool = true, int = true, double = true, string = true, vector = true})[type],
              "variable types are 'bool', 'int', 'double', 'string' and 'vector'"
            );
            assert(not variables[name], "variable/label already exists: " .. name);
            variables[name] = {name = name, scope = scope, type = type};

          elseif token == "name" then
            local name = line:match("^:%a+ +(.+)");
            assert(name, "name directive: :name script_name");
            compile_file = name;

          elseif token == "budget_cap" then
            local cost = line:match("^:[%a_]+ +(.+)");
            if cost and cost ~= "max" then
              cost = tonumber(cost);
              if cost then
                assert(
                  -2147483648 <= cost and cost < 2147483648,
                  "budget_cap must fit in an integer (-2 ^ 31 <= cost < 2 ^ 31), got " .. cost
                );
              end
            end
            assert(cost, "budget_cap directive: :budget_cap [max/<integer>]");
            budget = cost;

          elseif token == "use_budget" then
            use_budget = line:match("^:[%a_]+ +(.+)");
            assert(
              use_budget == "true" or use_budget == "false" or use_budget == "default",
              "use_budget directive: :use_budget [true/false/default]"
            );

          else
            assert(false, "Unrecognized directive: " .. token);
          end

        else
          local function define_label(name)
            assert(not (variables[name] or label_cache[name]), "variable/label already exists: " .. name);
            variables[name] = {name = name, scrope = "local", type = "int", label = 0};
            label_cache[#label_cache+1] = name;
            return "";
          end

          line = line:gsub(TOKEN.identifier.pattern .. ":", define_label):gsub("^%s+", ""):gsub("%s+$", "");
          if not is_empty(line) then
            assert(not is_import, "Imported files can not produce output, they must only contain variable and macro declarations");
            lines[#lines+1] = {text = line, num = line_number, label = label_cache};
            label_cache = {};
          end
        end
      end
    end

    -- anything left in the label cache points to the end of the script
    for _, label in ipairs(label_cache) do
      variables[label].label = 99;
    end

    return lines;
  end

  local function ins(format, val)
    ret[#ret + 1] = string.pack(format, val);
  end

  local function prefix_code(size)
    while size > 0x80 do
      ins("B", 0x80 + (size & 0x7F));
      size = size >> 7;
    end
    ins("B", size);
  end

  local function encode(node)
    if node.func then
      if node.func.name == "label" then
        local var = node.args[1].value;
        assert(variables[var], "why are you calling the label funciton manually?");
        encode({type = "number", value = variables[var].label});
        return;
      end

      prefix_code(#node.func.name);
      ret[#ret+1] = node.func.name;

      for _, arg in ipairs(node.args) do
        encode(arg);
      end

    else
      ins("s1", "constant");

      if node.type == "bool" then
        ins("b", 1);
        ins("b", node.value and 1 or 0);

      elseif node.type == "number" then
        if math.type(node.value) == "integer" then
          ins("b", 2);
          ins("i4", node.value);

        else
          ins("b", 3);
          ins("d", node.value);
        end

      elseif node.type == "string" then
        ins("b", 4);
        prefix_code(#node.value);
        ret[#ret + 1] = node.value;

      elseif node.type == "vector" then
        ins("b", 5);
        ins("f", node.value.x);
        ins("f", node.value.y);

      elseif node.type == "operator" then
        ins("b", 4);

        if node.value == "%" then
          node.value = "mod";
        elseif node.value == "^" then
          node.value = "pow";
        elseif node.value == "//" then
          node.value = "log";
        end

        ins("s1", node.value);
      else
        assert(false, "BUG REPORT: unknown compile type: " .. node.type);
      end
    end
  end


-- importFunc takes a string (file_name) and returns a pair of (status, string)
-- the content of the imported file on success, an error message on failure

  function compile(name, input, options, importFunc)
    env = clone_global();
    macros, imported = {len = "__builtin__", lua = "__builtin__"}, {};

    variables, impulses, conditions, actions = {}, {}, {}, {};
    budget, use_budget = nil, nil;
    ret = {};

    local _ = import("__stdlib__", STDLIB, true, importFunc);
    local lines = import(name, input, false, importFunc);

    for _, line in ipairs(lines) do
      line_number = line.num;
      local node = cache(line.text, variables);

      if node and node.func then

        if node.func.ret == "void" then
          actions[#actions+1] = node;

          if #line.label > 0 then
            for _, label in ipairs(line.label) do
              variables[label].label = #actions;
            end
          end
        
        else
          assert(#line.label == 0, "labels cannot be placed before impulses/conditions");

          if node.func.ret == "impulse" then
            impulses[#impulses+1] = node;
          else
            conditions[#conditions+1] = node;
          end
        end
      end
    end

    local function json_encode(node)
      local current_pos = #ret;
      encode(node);
      for i = current_pos + 1, #ret do
        -- Need to JSON-escape control characters, backslash and double-quote,
        -- and also UTF-8 encode high-byte chars
        ret[i] = ret[i]:gsub('[\0-\x1f\\"\x80-\xff]', line_encode_table);
      end
    end

    local function json_escape(str)
      ret[#ret+1] = str:gsub('[\0-\x1f\\"]', json_escape_table);
    end

    local package_name, script_name = compile_file:match("([^:]*):(.*)");
    if not script_name then
      script_name = compile_file;
    end

    if options.format ~= "v2" then
      prefix_code(#compile_file);
      ret[#ret+1] = compile_file;

      for _, tbl in ipairs({impulses, conditions, actions}) do
        ins("i4", #tbl);

        for _, line in ipairs(tbl) do
          encode(line);
        end
      end

      ret = base64.encode(table.concat(ret));

    else
      for num, pair in ipairs({
        {name = "actions", tbl = actions},
        {name = "conditions", tbl = conditions},
        {name = "impulses", tbl = impulses}
      }) do
        ret[#ret+1] = (num == 1) and [[{"]] or [[],"]];
        ret[#ret+1] = pair.name;
        ret[#ret+1] = [[":[]];

        for line_num, line in ipairs(pair.tbl) do
          if line_num ~= 1 then
            ret[#ret+1] = [[,]];
          end
          ret[#ret+1] = [["]];
          if pair.name == "impulses" then
            -- Inpulses are no-arg functions with static ASCII names
            ret[#ret+1] = line.func.name;

          else
            encode(line);
          end

          ret[#ret+1] = [["]];
        end
      end

      ret[#ret+1] = [[],"name":"]];
      json_encode(script_name);

      ret[#ret+1] = [[","package":"]];
      json_encode(package_name or "");

      ret[#ret+1] = [["]];
      if budget then
        ret[#ret+1] = [[,"budget":]];
        -- No quotes because budget is a number in the JSON
        ret[#ret+1] = (budget == "max") and "-1" or string.format("%d", budget);
      end

      if use_budget ~= "default" and (use_budget or budget) then
        ret[#ret+1] = [[,"useBudget":]];
        -- No quotes because useBudget is a boolean in the JSON
        ret[#ret+1] = use_budget or "true";
      end
      ret[#ret+1] = [[}]];

      ret = table.concat(ret);
    end

    package_name = package_name and package_name:sub(1, 24) .. ":" or "";
    script_name = script_name:sub(1, 24);

    return {
      name = package_name .. script_name,
      type = "script",
      impulses = #impulses,
      conditions = #conditions,
      actions = #actions,
      code = ret
    };
  end
end

do
  local data, pos, num_vars;
  local variables;
  local ret;

  local function read(format)
    local input, new = string.unpack(format, data, pos);
    pos = new;
    return ret;
  end

  local function parse()
    local func = read("s1");

    if func == "constant" then
      local type = read("b");

      if type == 1 then -- data type boolean
        return (read("b") == 1) and "true" or "false";

      elseif type == 2 then -- data type integer
        return tostring(read("i4"));

      elseif type == 3 then -- data type double
        local val = read("d");
        if val == 1 / 0 then
          return "(1.0 / 0.0)";
        elseif val == -1 / 0 then
          return "(-1.0 / 0.0)";
        elseif val ~= val then
          return "(0.0 / 0.0)";
        end

        return tostring(val);

      elseif type == 4 then -- data type string
        local string_pos, len = 0, 0;

        repeat
          local byte = read("B");
          len = len + ((byte & 0x7F) << 7 * string_pos);
          string_pos = string_pos + 1;
        until byte & 0x80 == 0

        local str = read("c" .. len);
        local single_quote, double_quote = str:match("'"), str:match('"');

        if not double_quote then
          return '"' .. str .. '"';
        elseif double_quote and not single_quote then
          return "'" .. str .. "'";
        end

        str = string.format([["%s"]], str:gsub([["]], [[" . '"' . "]])):gsub([[. ""]], "");

      elseif type == 5 then -- data type vector
        return string.format("vec(%s, %s)", read("f"), read("f"));

      else
        assert(false, "BUG REPORT: unknown constant type:" .. type);
      end

    else

      do
        local func_cpy = FUNCTION[func];
        assert(func_cpy, "BUG REPORT: unknown function: " .. func);
        func = func_cpy;
      end

      local args = {};
      local dynamic_operator = false;

      for i, arg in ipairs(func.args) do
        
      end
    end
  end
  function import(input)
    data = nil;
    pos = 1;

    variables = {};
    num_vars = 0;
    ret = {};
  end
end
