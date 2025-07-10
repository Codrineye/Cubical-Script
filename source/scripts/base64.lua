local base64 = {};

local keys = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
local key_idx = {};
for i = 1, #keys do
  local key = keys:sub(i, i);
  key_idx[key] = i - 1;
end

function base64.encode(input)
  local output = {};

  for i = 1, #input, 3 do
    local chr = table.pack(
      input:byte(i),
      input:byte(i + 1),
      input:byte(i + 2)
    );

    local enc = {
      chr[1] >> 2,
      ((chr[1] & 3) << 4) | ((chr[2] or 0) >> 4),
      -- if i + 1 is out of bounds, encodings 3 and 4 are changed to 64
      chr[2] == nil and 64 or ((chr[2] % 15) << 2) | (chr[3] >> 6),
      chr[3] == nil and 64 or chr[3] & 63
    };

    for j = 1, 4 do
      output[#output + 1] = keys:sub(enc[j] + 1, enc[j] + 1);
    end
  end

  return table.concat(output);
end

function base64.decode(input)
  local output = {};
  input = input:gsub("[^A-Za-z0-9%+%/%=]", "");
  for i = 1, #input, 4 do
    local enc = {
      key_idx[input:sub(i, i)] or 0,
      key_idx[input:sub(i + 1, i + 1)] or 0,
      key_idx[input:sub(i + 2, i + 2)] or 0,
      key_idx[input:sub(i + 3, i + 3)] or 0
    };

    local chr = {
      (enc[1] << 2) | (enc[2] >> 4),
      ((enc[2] & 15) << 4) | (enc[3] >> 2),
      ((enc[3] & 3) << 6) | enc[4]
    }

    output[#output + 1] = string.char(chr[1]);

    if enc[3] ~= 64 then
      output[#output + 1] = string.char(chr[2]);
    end

    if enc[4] ~= 64 then
      output[#output + 1] = string.char(chr[3]);
    end
  end

  return table.concat(output);
end
