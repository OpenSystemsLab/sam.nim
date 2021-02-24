# Copyright 2016 Huy Doan
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


## Fast and just works JSON-Binding for Nim (requires `Jsmn <https://github.com/OpenSystemsLab/jsmn.nim>`_)
##
## This module is to celebrate 100 days old of Sam - my second princess
##
## Installation
## ============
##.. code-block::
##  nimble install sam
##

import jsmn, strutils, macros, options
import sam/utils

type
  Mapper = ref object
    tokens: seq[JsmnToken]
    json: string

  JsonNode* = ref object
    mapper: Mapper
    pos: int

  JsonRaw* {.borrow: `.`.} = distinct string

  NamingConverter = proc(input: string): string

when (NimMajor, NimMinor, NimPatch) < (1, 4, 0):
  type
    IndexDefect* = IndexError
    FieldDefect* = FieldError

{.push boundChecks: off, overflowChecks: off.}

template getValue(t: JsmnToken, json: string): untyped =
  ## Returns a string present of token ``t``
  json[t.start..<t.stop]

proc `$`*(n: JsonNode): string = getValue(n.mapper.tokens[n.pos], n.mapper.json)

iterator children(m: Mapper, parent = 0): tuple[token: JsmnToken, pos: int] {.noSideEffect.} =
  var
    i = parent
    tok: JsmnToken
    count = m.tokens[parent].size

  assert m.tokens[parent].kind in {JSMN_OBJECT, JSMN_ARRAY}
  while count > 0:
    inc(i)
    tok = m.tokens[i]

    if tok.parent == parent:
      yield (tok, i)
      dec(count)

proc findValue(m: Mapper, key: string, pos = 0): int {.noSideEffect.} =
  result = -1
  for node in m.children(pos):
    if key == node.token.getValue(m.json):
      result = node.pos + 1
      break

proc loads(target: var any, m: Mapper, pos = 0) =
  if pos < 0: return
  when target is Option:
    if m.tokens[pos].getValue(m.json) == "null":
      target = none(target.get.type)
    else:
      var t: target.get.type
      loads(t, m, pos)
      target = some(t)
  elif target is ref:
    if m.tokens[pos].getValue(m.json) != "null":
      if target == nil:
        new(target)
      loads(target[], m, pos)
  elif target is object or target is tuple:
    when defined(verbose):
      debugEcho "object ", m.tokens[pos], " ", getValue(m.tokens[pos], m.json)
    assert m.tokens[pos].kind == JSMN_OBJECT
    var
      i = pos + 1
      tok: JsmnToken
      count = m.tokens[pos].size
      key: string
      match: bool
    while count > 0:
      match = false
      assert i <= m.tokens.len
      tok = m.tokens[i]
      assert tok.kind != JSMN_UNDEFINED
      when defined(verbose):
        echo "tok ", tok, " value: ", tok.getValue(m.json)
      if likely(tok.parent == pos):
        assert tok.kind == JSMN_STRING
        key = tok.getValue(m.json)
        for n, v in fieldPairs(target):
          if n == key:
            match = true
            when defined(verbose):
              echo "i ", i, " ", m.tokens[i+1].getValue(m.json)
            loads(v, m, i+1)
            break
        if match:
          inc(i, tok.size+1)
        else:
          inc(i)
        dec(count)
      else:
        inc(i)
  elif target is array or target is seq:
    assert m.tokens[pos].kind == JSMN_ARRAY
    when target is seq:
      newSeq(target, m.tokens[pos].size)
    var
      i = pos + 1
      x = 0
      tok: JsmnToken
      count = m.tokens[pos].size

    while x < count:
      tok = m.tokens[i]
      when defined(verbose):
        echo "array ", i, " ", tok.parent, " ", pos, " ", tok, " ", getValue(tok, m.json)
      if unlikely(tok.parent != pos):
        inc(i)
        continue
      loads(target[x], m, i)
      inc(i)
      inc(x)
  elif target is SomeInteger:
    assert m.tokens[pos].kind == JSMN_PRIMITIVE
    let value = m.tokens[pos].getValue(m.json)
    target = cast[target.type](parseInt(value))
  elif target is string:
    assert m.tokens[pos].kind == JSMN_STRING or m.tokens[pos].getValue(m.json) == "null"
    if m.tokens[pos].kind == JSMN_STRING:
      target = unescape(m.tokens[pos].getValue(m.json), "", "")
  elif target is bool:
    assert m.tokens[pos].kind == JSMN_PRIMITIVE
    target = m.json[m.tokens[pos].start] == 't'
  elif target is SomeFloat:
    assert m.tokens[pos].kind == JSMN_PRIMITIVE
    target = parseFloat(m.tokens[pos].getValue(m.json))
  elif target is char:
    assert m.tokens[pos].kind == JSMN_STRING
    assert m.tokens[pos].start <  m.tokens[pos].stop
    if likely(m.tokens[pos].start < m.tokens[pos].stop):
      target = m.json[m.tokens[pos].start]
  elif target is enum:
    assert m.tokens[pos].kind == JSMN_STRING
    let value = m.tokens[pos].getValue(m.json)
    for e in low(target.type)..high(target.type):
      if $e == value:
        target = e
        break
  else:
    raise newException(KeyError, "unsupported type: " & $target.type)

proc loads*(target: var any, json: string, bufferSize = 256) =
  var mapper = new(Mapper)
  mapper.tokens = jsmn.parseJson(json, bufferSize, autoResize=true)
  mapper.json = json

  loads(target, mapper)

proc parse*(json: string, bufferSize = 256): JsonNode =
  # Parse JSON string and returns a `JsonNode`
  new(result)
  result.mapper = new(Mapper)
  result.mapper.tokens = jsmn.parseJson(json, bufferSize, autoResize=true)
  result.mapper.json = json


proc parse*(json: string, tokens: seq[JsmnToken]): JsonNode =
  ## Load a parsed JSON tokens and returns a `JsonNode`
  new(result)
  result.mapper = new(Mapper)
  result.mapper.tokens = tokens
  result.mapper.json = json


func `[]`*(n: JsonNode, key: string): JsonNode {.noSideEffect.} =
  ## Get a field from a json object, raises `FieldError` if field does not exists
  assert n.mapper.tokens[n.pos].kind == JSMN_OBJECT
  new(result)
  result.mapper = n.mapper
  result.pos = n.mapper.findValue(key, n.pos)

func `[]`*(n: JsonNode, idx: int): JsonNode {.noSideEffect.} =
  ## Get a field from json array, raises `IndexError` if array is empty or index out of bounds
  assert n.mapper.tokens[n.pos].kind == JSMN_ARRAY
  new(result)
  result.mapper = n.mapper

  if n.mapper.tokens[n.pos].size <= 0:
    raise newException(IndexDefect, "index out of bounds")

  if idx == 0:
    result.pos = n.pos + 1
  else:
    var i = 0
    for child in n.mapper.children(n.pos):
      if i == idx:
        result.pos = child.pos
      inc(i)

func len*(n: JsonNode): int =
  ## Returns the number of elements in a json array
  assert n.mapper.tokens[n.pos].kind == JSMN_ARRAY
  n.mapper.tokens[n.pos].size

func hasKey*(n: JsonNode, key: string): bool =
  ## Checks if field exists in object
  assert n.mapper.tokens[n.pos].kind == JSMN_OBJECT
  var pos = -1
  try:
    pos = n.mapper.findValue(key, n.pos)
  except FieldDefect:
    discard
  result = pos > n.pos

func toStr*(node: JsonNode): string {.inline.} =
  ## Retrieves the string value of a JSMN_STRING node
  assert node.mapper.tokens[node.pos].kind == JSMN_STRING
  var tmp = ""
  loads(tmp, node.mapper, node.pos)
  result = escapeString(tmp)

func toInt*(node: JsonNode): int {.inline.} =
  ## Retrieves the int value of a JSMN_PRIMITIVE node
  assert node.mapper.tokens[node.pos].kind == JSMN_PRIMITIVE
  loads(result, node.mapper, node.pos)

func toFloat*(node: JsonNode): float {.inline.} =
  ## Retrieves the float value of a JSMN_PRIMITIVE node
  assert node.mapper.tokens[node.pos].kind == JSMN_PRIMITIVE
  loads(result, node.mapper, node.pos)

func toBool*(node: JsonNode): bool {.inline.} =
  ## Retrieves the bool value of a JSMN_PRIMITIVE node
  assert node.mapper.tokens[node.pos].kind == JSMN_PRIMITIVE
  loads(result, node.mapper, node.pos)

func to*[T](node: JsonNode): T =
  ## Map a JSMN_OBJECT node into a Nim object
  when result is ref:
    new(result)
  loads(result, node.mapper, node.pos)

iterator items*(n: JsonNode): JsonNode =
  ## Iterator for the items of an array node
  assert n.mapper.tokens[n.pos].kind == JSMN_ARRAY
  var
    i = n.pos
    count = n.mapper.tokens[n.pos].size

  while count > 0:
    inc(i)
    if n.mapper.tokens[i].parent == n.pos:
      dec(count)
      var node = new JsonNode
      node.mapper = n.mapper
      node.pos = i
      yield node

iterator pairs*(n: JsonNode): tuple[key: string, val: JsonNode] =
  ## Iterator for the child elements of an object node
  assert n.mapper.tokens[n.pos].kind == JSMN_OBJECT
  var
    i = n.pos + 1
    tok: JsmnToken
    key: string
    val = new(JsonNode)
    count = n.mapper.tokens[n.pos].size

  val.mapper = n.mapper
  while count > 0:
    if n.mapper.tokens[i].parent == n.pos:
      key = tok.getValue(n.mapper.json)
      val.pos = i + 1
      inc(i, 2)
      dec(count, 2)
      yield (key, val)
    else:
      inc(i)

proc dumps*(t: auto, x: var string, namingConverter: NamingConverter = nil) =
  ## Serialize `t` into `x`
  when t is Option:
    if t.isSome():
      dumps(t.get(), x, namingConverter)
    else:
      x.add "null"
  elif t is object or t is tuple:
    var first = true
    x.add "{"
    for n, v in fieldPairs(t):
      if unlikely(first):
        first = false
      else:
        x.add ","
      if likely(namingConverter != nil):
        x.add "\"" & namingConverter(n) & "\""
      else:
        x.add "\"" & n & "\""
      x.add ":"
      dumps(v, x)
    x.add "}"
  elif t is string:
    if t.len == 0:
        x.add "null"
        return
    x.add "\"" & escapeString(t) & "\""
  elif t is char:
    x.add "\"" & $t & "\""
  elif t is bool:
    if t:
      x.add "true"
    else:
      x.add "false"
  elif t is array or t is seq:
    var first = true
    when compiles(t == nil):
        if t == nil:
          x.add "null"
          return
    x.add "["
    for e in t:
      if first:
        first = false
      else:
        x.add ","
      dumps(e, x)
    x.add "]"

  elif t is enum:
    x.add "\"" & $t & "\""
  elif t is ref or t is pointer:
    dumps(t[], x)
  elif t is JsonRaw:
    x.add t.string
  else:
    x.add $t

proc dumps*(t: auto, namingConverter: NamingConverter = nil): string =
  ## Serialize `t` to a JSON formatted
  result = newStringOfCap(sizeof(t) shl 1)
  dumps(t, result, namingConverter)

proc `%`*(x: auto): JsonRaw {.inline.} =
  ## Convert `x` to a raw json string (JsonRaw is not wrapped when added to json string)
  (JsonRaw)dumps(x)

proc stringify(x: NimNode, top = false): NimNode {.compileTime.} =
  var left, right: NimNode
  case x.kind
  of nnkBracket:
    result = newNimNode(nnkBracket)
    for i in 0 .. x.len-1:
      result.add(stringify(x[i]))
  of nnkTableConstr:
    result = newNimNode(nnkPar)
    for i in 0 .. x.len-1:
      assert x[i].kind == nnkExprColonExpr
      if x[i][0].kind == nnkStrLit:
        left = newIdentNode(strVal(x[i][0]))
      else:
        left = x[i][0]
      right = stringify(x[i][1])
      result.add(newNimNode(nnkExprColonExpr).add(left).add(right))
  of nnkPar:
    result = newNimNode(nnkBracket)
    for i in 0 .. x.len-1:
      result.add prefix(stringify(x[i]), "%")
  else:
    result = x
  if top:
    result = newCall(newIdentNode("dumps"), result)

macro `$$`*(x: untyped): untyped =
  ## Convert anything to a json string
  stringify(x, true)

{.pop.}

func isObject*(n: JsonNode): bool =
  n.mapper.tokens[n.pos].kind == JSMN_OBJECT

func isArray*(n: JsonNode): bool =
  n.mapper.tokens[n.pos].kind == JSMN_ARRAY

func isString*(n: JsonNode): bool =
  n.mapper.tokens[n.pos].kind == JSMN_STRING

func isPrimitive*(n: JsonNode): bool =
  n.mapper.tokens[n.pos].kind == JSMN_PRIMITIVE
