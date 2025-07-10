STDLIB = [===[
#pos.relative(x_pos, y_pos, x_anchor, y_anchor) {lua(
  local x_pos = [==[{x_pos}]==];
  local y_pos = [==[{y_pos}]==];
  local x_anchor = [==[{x_anchor}]==];
  local y_anchor = [==[{y_anchor}]==];

  local rel_width = "min(width.d(), (16.0 / 9.0) * height.d())";
  local rel_height = "min(height.d(), (9.0 / 16.0) * width.d())";

  local function equation(term, pos, anchor, mult)
    local pos_num, anchor_num = tonumber(pos), tonumber(anchor);
  
    local difference = (pos_num and anchor_num) and (pos_num - anchor_num) or nil;
    local first_term = "0.0";
    if difference ~= 0.0 then
      first_term = term .. " * ui.size()";
      if difference ~= 1.0 then
        first_term = first_term .. " * ((" .. pos .. ") - (" .. anchor .. "))";
      end
    end

    local last_term = "";
    if anchor_num ~= 0.0 then
      last_term = " + " .. mult;
      if anchor_num ~= 1.0 then
        last_term = last_term .. " * (" .. anchor .. ")";
      end
    end

    return first_term .. last_term;
  end

  return "vec("
    .. equation(rel_width, x_pos, x_anchor, "width.d()")
    .. equation(rel_height, y_pos, y_anchor, "height.d()")
  .. ")"
)}

#click.relative(x_pos, y_pos, x_anchor, y_anchor) click({pos.relative({x_pos}, {y_pos}, {x_anchor}, {y_anchor})})
]===]