
-- Lua Element Tree --

local base = {tostring = tostring}
local lparse = require"lxp.lom"

local _M = {}

-- 'attr' is optional. Is my code ok with this ?

_M.fromstring = lparse.parse

local function Type(cls)
  local constructor = function(cls, ...)
    return cls:new(...) -- cls:new(...) in Lua 5.1
  end
  local mt = getmetatable(cls)
  if mt == nil then
    mt = {}
    setmetatable(cls, mt)
  end
  mt.__call = constructor
  return cls
end
_M.Type = Type

_M.StringBuffer = Type {

  new = function(cls, elt)
    local buffer = {}
    cls.__index = cls
    setmetatable(buffer, cls)
    return buffer
  end,

  write = table.insert,

  __tostring = table.concat,

}

local function table_update(self, other)
  for key, value in pairs(other) do
    self[key] = value
  end
end

local mapping = { ['&']  = "&amp;"  ,
                  ['<']  = "&lt;"   ,
                  ['>']  = "&gt;"   ,
                  ['"']  = "&quot;" ,
                  ["'"]  = "&apos;" , -- not used
                  ["\t"] = "&9;"    ,
                  ["\r"] = "&10;"   ,
                  ["\n"] = "&13;"   }

local function map(symbols)
  local array = {}
  for _, symbol in ipairs(symbols) do
    table.insert(array, {symbol, mapping[symbol]})
  end
  return array
end

local encoding = {}

encoding[1] = { map{'&', '<'}      ,
                map{'&', '<', '"'} }

encoding[2] = { map{'&', '<', '>'}      ,
                map{'&', '<', '>', '"'} }

encoding[3] = { map{'\r', '&', '<', '>'}                  ,
                map{'\r', '\n', '\t', '&', '<', '>', '"'} }

encoding[4] = { map{'\r', '\n', '\t', '&', '<', '>', '"'} ,
                map{'\r', '\n', '\t', '&', '<', '>', '"'} }

encoding["minimal"]   = encoding[1]
encoding["standard"]  = encoding[2]
encoding["strict"]    = encoding[3]
encoding["most"]      = encoding[4]

_M.encoding = encoding

local function lom_sort(attrs)
  -- collect the ordered attributes
  local indices = {}
  for key, _ in pairs(attrs) do
    if type(key) == "number" then
      table.insert(indices, key)
    end
  end
  table.sort(indices)
  local attrs_ = {}
  for _, index in ipairs(indices) do
    local attr = attrs[index]
    table.insert(attrs_, attr)
    attrs_[attr] = true
  end
  -- the others will appear last, in no particular order
  for attr, _ in pairs(attrs) do
    if type(attr)=="string" and not attrs_[attr] then
      table.insert(attrs_, attr)
    end
  end
  return attrs_
end
_M.lom_sort = lom_sort

local function lexicographic(attrs)
  local attrs_ = {}
  for attr, _ in attrs do
    if type(attr) == "string" then
      table.insert(attrs_, attr)
    end
  end
  return table.sort(attrs_)
end
_M.lexicographic = lexicographic

_M.ElementTree = Type {

  new = function(cls, elt, options)
    local etree = {}
    cls.__index = cls
    setmetatable(etree, cls)

    etree.root = assert(elt, "ElementTree:new: root element required")
    etree.options = {}

    table_update(etree.options, cls.options)
    table_update(etree.options, options or {})

    return etree
  end,

  options = { attr_sort  = lom_sort          ,
              decl       = true              ,
              empty_tags = true              ,
              encoding   = encoding.standard } ,

  _encode = function(text, encoding)
    for _, key_value in pairs(encoding) do
      text = string.gsub(text, key_value[1], key_value[2])
    end
    return text
  end,

  write = function(self, file, elt)
    if file == nil then
      file = io.stdout
    end
    if not elt and self.options.decl then
      local decl = "<?xml version='1.0' encoding='UTF-8'?>\n"
      file:write(decl)
    end
    local elt = elt or self.root
    local cdata_encoding, attributes_encoding = unpack(self.options.encoding)

    file:write("<" .. elt.tag)
    local elt_attr = elt.attr or {}
    local attrs = self.options.attr_sort(elt_attr)
    for _, name in ipairs(attrs) do
      local value = elt_attr[name]
      name  = _M.ElementTree._encode(name, cdata_encoding)
      value = _M.ElementTree._encode(value, attributes_encoding)
      local assignment = string.format('%s="%s"', name, value)
      file:write(" " .. assignment)
    end

    if #(elt) == 0 and self.options.empty == true then
      file:write("/>")
    else
      file:write(">")
      for _, child in ipairs(elt) do
        if type(child)=="string" then
          child = _M.ElementTree._encode(child, cdata_encoding)
          file:write(child)
        else
          assert(type(child)=="table")
          self:write(file, child)
        end
      end
      file:write("</" .. elt.tag .. ">")
    end
  end,

  __tostring = function(self)
    local mt = getmetatable(self)
    setmetatable(self, nil)
    local repr = base.tostring(self)
    setmetatable(self, mt)
    local _, _, address = string.find(repr, "[a-zA-Z]*: (.+)")
    return string.format("element tree: %s", address)
  end,
}

local function tostring(elt)
  buffer = _M.StringBuffer()
  _M.ElementTree(elt):write(buffer)
  return base.tostring(buffer)
end
_M.tostring = tostring

--[[ Compat with old module behaviour, if any ]]

_M._PACKAGE="";
_M._NAME="etree";
_M._M=_M;

--[[ End ]]

return _M
