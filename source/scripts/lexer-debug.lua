
local table

function table.print(tbl, ignoreKeys)
  local ignore = {};
  for i, _ in ipairs(ignoreKeys or {}) do
    ignore[i] = true;
  end

  local function internal(target_table, visited, depth)
    local sorted = {};

    for i, val in pairs(target_table) do
      if not ignore[i] and (type(val) ~= "table" or not visited[val]) then
        visited[val] = visited[val] or type(val) == "table";
        sorted[#sorted+1] = {i, val};
      end
    end

    table.sort(sorted, function (a, b)
      return a[1] < b[1];
    end);

    for i, key in ipairs(sorted) do
      print(string.format("%s[%s] %s: %s", string.rep("  ", depth), key[1], type(key[2]), key[2]));

      if type(key[2]) == "table" then
        internal(key[2], visited, depth + 1)
      end
    end
  end

  internal(tbl, {}, 0);
end

function AST(node, debugging)
  local ret = {};

  local char = {
    connect = debugging and "\179" or "  ",
    split = debugging and "\195" or "  ",
    ending = debugging and "\192" or "  "
  };

  local function internal(target_node, prefix, isLast)
    prefix = prefix:gsub("..$", isLast and char.ending or char.split);
    if target_node.type then
      ret[#ret+1] = prefix .. target_node.type .. " " .. tostring(target_node.value);
    else
      if target_node.func then
        ret[#ret+1] = prefix .. target_node.func.name;
      else
        ret[#ret+1] = prefix .. "()";
      end

      prefix = prefix:gsub("..$", isLast and "  " or char.connect) .. "  ";

      for i, arg in ipairs(target_node.args) do
        internal(arg, prefix, i == #target_node.args);
      end
    end
  end

  internal(node, "", false);
  return table.concat(ret, "\n");
end

function Rebuild(node)
  local strip = function (str)
    return tostring(str):gsub("^%((.+)%)$", "%1");
  end

  local function internal(target_node, isTop)
    if target_node.type then
      return target_node.value;
    end

    local args = {};
    for i, arg in ipairs(target_node.args) do
      args[i] = internal(arg, false);
    end

    local func, ret;
    if target_node.func.short then
      func = target_node.func.name;
    else
      func = "";
    end

    if func:match("^arithmetic") or func:match("^comparison") then
      ret = string.format("(%s)", table.concat(args, " "));
    elseif func:match("%.set$") then
      return string.format("%s = %s", args[1]:sub(2, -2), strip(args[2]));
    elseif func:match("%.get") then
      return args[1]:sub(2, -2);

    else
      for i, arg in ipairs(args) do
        args[i] = strip(arg);
      end

      ret = string.format("%s(%s)", func, table.concat(args, ", "));
    end

    return isTop and strip(ret) or ret;
  end

  return internal(node, true);
end