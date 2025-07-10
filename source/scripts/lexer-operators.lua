OPERATOR = {};

local operators = {
  "^  exponent    op.math",
  "// log         op.math",
  "",
  "*  multiply    op.math",
  "/  divide      op.math",
  "%% remainder   op.math",
  "",
  "%+ add         op.math",
  "-  subtract    op.math",
  "",
  ". concatenate  op.math",
  "",
  "== compare     op.comp",
  "!= compare     op.comp",
  "<  compare     op.comp",
  "<= compare     op.comp",
  ">  compare     op.comp",
  ">= compare     op.comp",
  "",
  "&& compare     op.comp",
  "&  compare     op.comp",
  "",
  "|| compare     op.comp",
  "|  compare     op.comp",
  "",
  "=  assign      op.set"
}

local precedence = 1;
for _, line in ipairs(operators) do
  if line == "" then
    precedence = precedence + 1;
  else
    local op, name, type = line:match("([^%s]+)%s+(%w+)%s+(.*)");
    OPERATOR[op] = {
      order = precedence,
      type = type,
      name = name
    }
  end
end

local final = {};
for i, val in pairs(OPERATOR) do
  final[i] = val;

  if val.type == "op.math" then
    final[i .. "="] = {
      order = precedence,
      type = "op.set",
      name = "assign"
    }
  end
end

OPERATOR = final;
OPERATOR.max_precedence = precedence