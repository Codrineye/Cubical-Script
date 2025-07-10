local current_line, variables;
local dynamicFunc = {
  min = true,
  max = true,
  rnd = true,
  ["if"] = true
};

local function process_vectors(token_type)
  if token_type == "vector" then
    return "vec2";
  else
    return token_type;
  end
end

local tokenError = function(...)
  local str, repl = current_line:gsub("^\1(.+)\2$", "%1");
  local pos = { ... };
  local msg = table.remove(pos);

  for i = 1, #pos do
    local position = pos[i];
    if type(position) == "table" then
      pos[i] = position.pos;
    end
  end

  local markers = "";

  for i = 1, #pos do
    local position = pos[i];
    if type(position) == "table" then
      position = position.pos;
    end
    markers = markers .. string.rep(" ", position - (repl == 0 and 1 or 2) - #markers) .. "^";
  end

  return error_lexer(string.format("%s\n\n%s\n%s", msg, str, markers));
end

local newNode = function (pos, parent, func)
  local node_func = func;
  if type(func) == "string" then
    node_func = FUNCTION[func];
    if not node_func then
      error_lexer("trying to call a non-function: " .. tostring(func));
    end
  end

  return {
    pos = pos,
    parent = parent,
    tokens = {},
    func = node_func,
    args = {}
  }
end

local nextToken = function (str, pos, prev)
  pos = pos or 1;
  for _, token in ipairs(TOKEN) do
    if token.pattern then
      local match = str:match(token.pattern, pos);

      if match then
        if token.alias then
          token = TOKEN[token.alias];
        end

        local ret = {
          pos = pos,
          len = #match,
          type = token.name
        };
        if ret.type ~= "number" then
          ret.value = match;
        else
          ret.value = tonumber(match);
          if not ret.value then
            tokenError(pos, "invalid number: " .. match);
          end
        end
        ret.op = OPERATOR[match];

        if ret.type == "identifier" and (ret.value == "true" or ret.value == "false") then
          ret.type = "bool";
          ret.value = ret.value == "true";
        elseif ret.type == "string" then
          ret.value = string.sub(tostring(ret.value), 2, -2);
        end

        if ret.type == "operator" and not ret.op then
          tokenError(pos, "invalid operator: " .. match);
        elseif #token ~= 0 and prev and not token[prev.type] then
          tokenError(pos, "unexpected symbol" .. (ret.type == "eof" and "<eof>" or match));
        end

        return ret;
      end
    end
  end

  tokenError(pos, "unexpected symbol: " .. str:sub(pos, pos))
end

local resolveID = function (token)
  if token.type == "identifier" and not token.func then
    token.var = variables[token.value];
    if not token.var then
      tokenError(token, "undefined variable: " .. token.value);
    
    elseif token.var.scope == "constant" then
      token.type = token.var.type;
      if string.match("double|int", token.type) == token.type then
        token.type = "number";
      end
      token.value = token.var.value;
      return token;
    end

    token.type = "string";

    local token_type = process_vectors(token.var.type);
    local new = newNode(token.pos, nil, token.var.label and "label" or string.format("%s.%s.get", token.var.scope, token_type));
    new.args = {token};
    return new;
  end

  return token;
end

local resolveType = function (token)

  local type = token.type;
  if token.var then
    type = token.var.type;
  elseif token.op then
    type = token.op.type;
  elseif token.func then
    type = token.func.ret;
  elseif token.type == "number" then
    type = math.type(token.value) == "integer" and "int" or "double";
  end

  return type;
end

local resolveTypeOp = function (token)
  local resolved = resolveType(token);
  return process_vectors(resolved);
end

local typeCheck = function (left, op, right)
  local typeLeft, typeRight = resolveType(left), resolveType(right);
  if typeLeft ~= typeRight then
    tokenError(left, op, right, string.format("trying to %s different types: %s and %s", op.op.name, typeLeft, typeRight));
  end
end

local function set_operation(node, idx, left, op, right)
  local var = left.args[1].var;
  if var.label then
    tokenError(left, "You can't assign values to constants");
  end

  if op.value ~= "=" then
    op.value = op.value:sub(1, -2);
    op.op = OPERATOR[op.value];

    typeCheck(left, op, right);

    if op.value == "." then
      local new = newNode(left.pos, node, "concat");
      new.args = {left, right};
      right = new;
    else
      local new = newNode(left.pos, node, "arithmetic." .. resolveTypeOp(left.args[1]));
      new.args = {left, op, right};
      right = new;
    end
  end

  typeCheck(left.args[1], op, right);

  local token_type = process_vectors(var.type);
  local new = newNode(left.pos, node, string.format("%s.%s.set", var.scope, token_type));
  new.args = {left.args[1], right};
  node.tokens[idx] = new;
end

local consumeTokensWorker = function (node)
  if #node.tokens == 0 then
    if not node.func then
      tokenError(node, "invalid empty parenthesis");
    end
    return;
  
  elseif #node.tokens == 1 then
    node.args[#node.args + 1] = resolveID(node.tokens[1]);
    node.tokens = {};
    return;
  end

  if #node.tokens % 2 ~= 1 then
    error_lexer("BUG REPORT: invalid expression");
  end

  for i = 1, #node.tokens do
    local token = node.tokens[i];
    node.tokens[i] = resolveID(token);
  end

  for i = 1, OPERATOR.max_precedence do
    local j, k = 1, 1;

    while j + 2 <= #node.tokes do
      local left, op, right = node.tokens[j], node.tokens[j + 1], node.tokens[j + 2];
      local type = op.op.type;

      if op.op.precedence ~= i then
        node.tokens[k] = node.tokens[j];
        node.tokens[k + 1] = node.tokens[j + 1];
        k = k + 2;
      else

        if type == "op.set" then
          if not left.args then
            tokenError(left, "You can't assign values to constants");
          end

          set_operation(node, j, left, op, right);

        else
          local const = false;
          local addition = {
            left = (string.match("number|string", left.type) == left.type),
            right = (string.match("number|string", right.type) == right.type)
          }
          if type == "op.math" and (left.type == right.type or op.value == ".") and addition.left and addition.right then
            local isNegativeRemainder;
            if op.value == "%" then
              right.value = math.abs(right.value);
              if left.value < 0 then
                isNegativeRemainder = true;
                left.value = -left.value;
              end
            end

            local operation = {};
            if op.value == "." then
              operation = {
                "return %q .. %q",
                tostring(left.value),
                tostring(right.value)
              };
            elseif op.value == "//" then
              operation = {
                "return math.ceil(%s, %s)",
                left.value,
                right.value
              };
            else
              operation = {
                "return %s, %s, %s",
                left.value,
                op.value,
                right.value
              };
            end
            local func, err = load(
              string.format(table.unpack(operation)),
              "lexer",
              "t"
            )

            if not func then
              error(string.format(
                "Obtained error message when processing `%s`\nExited with error message %s",
                table.concat(operation, ", "),
                err or "nil error message"
              ))
            end

            local status, ret = pcall(func);
            if status then
              const = true;
              if resolveType(left) == "int" and op.value ~= "." then
                left.value = math.modf(ret);
              else
                left.value = ret;
              end

              left.value = isNegativeRemainder and -left.value or left.value;
              left.type = op.value == "." and "string" or "number";
              node.tokens[j] = left;
            end
          end

          if not const then
            local typeLeft, typeRight = resolveType(left), resolveType(right);

            if op.value == "." then
              if typeLeft == "int" or typeLeft == "double" then
                local new = newNode(left.pos, node, typeLeft == "int" and "i2s" or "d2s");
                new.args = {left};
                left = new;
              end

              if typeRight == "int" or typeRight == "double" then
                local new = newNode(right.pos, node, typeRight == "int" and "i2s" or "d2s");
                new.args = {right};
                right = new;
              end

              typeCheck(left, op, right);

              if left.type == "string" and left.value == "" then
                node.tokens[j] = right;
              elseif right == "string" and right.value == "" then
                node.tokens[j] = left;
              else
                local new = newNode(left.pos, node, "concat");
                new.args = {left, right};
                node.tokens[j] = new;
              end
            else
              if type == "op.math" then
                local types = {
                  int = 1,
                  double = 1,
                  vector = 1
                };
                if not types[typeLeft] then
                  tokenError(left, "arithmetic cannot be performed on a " .. typeLeft);
                elseif not types[typeRight] then
                  tokenError(left, "arithmetic cannot be performed on a " .. typeRight);
                elseif op.value == "%" and typeLeft == "vector" then
                  tokenError(op, "vector doesn't support modulus");
                end
              end

              typeCheck(left, op, right);
              local new = newNode(left.pos, node, (type == "op.math" and "arithmetic." or "comparison.") .. resolveTypeOp(left));
              new.args = {left, op, right};
              node.tokens[j] = new;
            end
          end
        end
      end
      j = j + 2;
    end
    node.tokens[k] = node.tokens[j];
    while k < j do
      k = k + 1;
      node.tokens[k] = nil;
    end
  end

  if #node.tokens ~= 1 then
    error_lexer("invalid expression");
  end

  node.args[#node.args+1] = node.tokens[1];
  node.tokens = {};
end


local function consumeTokens(node)
  consumeTokensWorker(node);
  local arg_count = #node.args;
  local last_arg = node.args[arg_count];

  if last_arg and node.func then
    local type = resolveType(last_arg);
    local expected = node.func.args[arg];
    if not expected then
      tokenError(node, last_arg, string.format(
        "function %s expects %s arguments, got %s",
        node.func.short, #node.func.args, arg_count
      ));
    end

    if not dynamicFunc[node.func.name] then
      if type ~= expected.type and (type ~= "string" or not expected.type:match("^op")) then
        tokenError(node, last_arg, string.format(
          "bad argument #%s to %s (%s expected, got %s)",
          arg_count, node.func.short, expected.type, type
        ));
      end

      if expected.valid and (last_arg.type == "number" or last_arg.type == "string") then
        local status, err = expected.valid(last_arg.value);
        if not status then
          tokenError(node, last_arg, string.format("bad argument %s to %s\n\n%s", arg_count, node.func.short, err));
        end
      end
    end
  end
end

local function lexer(line, vars)
  local debug = {};
  local node, prev;
  local pos = 1;

  node = newNode();
  if not line then
    error_lexer("no input");
  end

  line = string.format("\1%s\2", line);

  current_line = line;
  variables = vars;

  while pos <= #line do
    local token = nextToken(line, pos, prev);
    pos = pos + token.len;

    if token.type ~= "skip" and token.type ~= "comment" then
      debug[#debug + 1] = string.format("%s %s", token.type, token.value);
      --print(token.type, token.value);

      if token.type == "close" then
        if not node.parent then
          tokenError(token, "unmatched parenthesis");
        end
        consumeTokens(node);

        if node.args and #node.args == 1 and not node.func then
          node.parent.tokens[#node.parent.tokens+1] = node.args[1];
        else
          node.parent.tokens[#node.parent.tokens+1] = node;
        end

        if node.func then
          if #node.args ~= #node.func.args then
            tokenError(node, token, string.format(
              "function %s expects %s arguments, got %s",
              node.func.short, #node.func.args, #node.args
            ));
          end

          if node.func.name == "clickrel" then
            for i, arg in ipairs(node.args) do
              local new = newNode(arg.pos, node, "arithmetic.double");
              new.args = {
                arg,
                nextToken"*",
                newNode(arg.pos, node, i == 1 and "screen.width.d" or "screen.height.d")
              };
              node.args[i] = new;
            end

            local new = newNode(node.pos, node, "vec.fromCoords");
            new.args = node.args;
            node.args = {new};
            node.func = FUNCTION.click;
          
          elseif node.func.short == "vec" then
            -- Represent the vector as a constant if both values are constant
            local x_coord = node.args[1];
            local y_coord = node.args[2];
            if not x_coord.func and x_coord.type == "number" and not y_coord.func and y_coord.type == "number" then
              assert(x_coord.value, "x_coord.value");
              assert(y_coord.value, "y_coord.value");
              node.value = {
                x_coord = x_coord.value,
                y_coord = y_coord.value
              };
              node.type = "vector";
              node.func = nil;
            end

          elseif dynamicFunc[node.func.name] then
            if node.func.short == "if" then
              local arg1 = resolveType(node.args[1]);
              if arg1 ~= "bool" then
                tokenError(
                  node,
                  node.args[1],
                  string.format("bad argument #1 to %s (bool expected, got %s)", node.func.short, arg1)
                );
              end

              local arg2 = resolveType(node.args[2]);
              local arg3 = resolveType(node.args[3]);
              local func = FUNCTION["ternary." .. arg2];
              if not func then
                tokenError(
                  node,
                  node.args[2],
                  string.format("bad argument ^2 to %s (int, double, string or vector expected, for $s)", node.func.short, arg2)
                );
              elseif arg3 ~= arg2 then
                tokenError(
                  node,
                  node.args[3],
                  string.format("bad argument #3 to %s (%s expected, got %s)", node.func.short, arg2, arg3)
                );
              end

              node.func = func;
            else
              local arg = resolveType(node.args[1]);
              if arg ~= "int" and arg ~= "double" then
                tokenError(
                  node,
                  node.args[1],
                  string.format("bad argument #1 to %s (int or double expected, got %s)", node.func.short, arg)
                );
              end

              for i = 2, #node.args do
                local arg_type = resolveType(node.args[i]);
                if arg_type ~= arg then
                  tokenError(
                    node,
                    node.args[i],
                    string.format("bad argument #%s to %s (%s expected, got %s)", i, node.func.short, arg, type)
                  );
                end
              end

              local name = string.format("%s.%s", arg, node.func.name);
              node.func = FUNCTION[name];
            end
          end
        end

        node = node.parent;
      elseif token.type == "open" then
        local last = table.remove(node.tokens);
        local func = nil;
        if last and last.type == "identifier" then
          func = last.value;
        else
          node.tokens[#node.tokens + 1] = last;
        end

        if func then
          if not FUNCTION[func] then
            tokenError(last, "trying to call a non-function: " .. func);
          end
          func = FUNCTION[func];
        end

        node = newNode(func and last.pos or token.pos, node, func);
      elseif token.type == "next" then
        if not node.func then
          tokenError(token, "unexpected symbol: " .. token.value);
        end
        consumeTokens(node);
      elseif token.type == "eof" then
        consumeTokens(node);
      elseif not token.type:match("^.of$") then
        node.tokens[#node.tokens+1] = token;
        local arg = node.func and node.func.args[#node.args + 1];

        if token.type == "operator" and token.op.token == "op_set" then
          if node.parent or #node.tokens ~= 2 or node.tokens[1].type ~= "identifier" then
            tokenError(token, "unexpected symbol: " .. token.value);
          end
        end
      end

      prev = token;
    end
  end

  if node.parent then
    error_lexer("unmatched parenthesis");
  end

  node = node.args[1];

  if node then
    local ret = node.func and node.func.ret;
    if ret ~= "impulse" and ret ~= "bool" and ret ~= "void" then
      error_lexer("lines must return impulse, bool or nothing");
    end

    return node, debug;
  end
end

if DEBUG then
  local text =
  [[dig(rnd(1, 3) + ((dig + ((3 + 1 + 2) + 5) - dig * (3 - dig) ^ (8 - 9)) - 2), 3)]];
  --[[foo = isfill("bar", bar)]];
  --[[a = OR(AND(1, 2, 3), AND(4, 5, 6))]];
  --[[foo == dig]];
  --[[gotoif(hello, 3 == 5)]];
  --[[click(vec(3.0, 4.0))]];

  local vars = {
    dig = {type = "int", scope = "local"},
    foo = {type = "int", scope = "global"};
  }
  for _ = 1, 2 do
    local node, _ = lexer(text, vars);
    print();
    print(AST(node));
    print();
    print("  input: " .. text);
    print();
    text = Rebuild(text);
    print("rebuild: " .. text);
  end
end