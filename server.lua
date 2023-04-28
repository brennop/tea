--
-- http.lua
--
-- MIT License
--
-- Copyright (c) 2022 brennop
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--

local socket = require "socket"
local scheduler = require "scheduler"

sched = scheduler.Scheduler()

local http = { handlers = { } }

local messages = {
  [200] = "OK",
  [404] = "Not Found",
  [500] = "Internal Server Error",
}

local function match_handler(pattern)
  for key, handler in pairs(http.handlers) do
    local match = pattern:match(key .. "$")
    if match then
      return handler({}, match)
    end
  end

  return { status = 404, body = "Not Found" }
end

local function serialize(data)
  local message = messages[data.status] or "Unknown"

  local headers = {
    "Content-Length: " .. #data.body,
    "Connection: close",
  }

  local response = {
    "HTTP/1.1 " .. data.status .. " " .. message,
    table.concat(headers, "\r\n") .. table.concat(data.headers or {}, "\r\n"),
    "",
    data.body,
  }

  return table.concat(response, "\r\n")
end

local function handle_client(client)
  local pattern, version = 
    client:receive():match("(%u+%s[%p%w]+)%s(HTTP/1.1)")

  -- ignore headers for now
  for line in function() client:receive() end do end

  local data = match_handler(pattern)

  local response = ""

  if type(data) == "table" then
    response = serialize(data)
  else
    response = serialize({ status = 200, body = data })
  end

  client:send(response)
end

local function wrapper(client)
  client:settimeout(5)
  ok, err = pcall(handle_client, client)
  if not ok then
    -- TODO: log errors
    client:send(serialize({ status = 500, body = err }))
  end
  client:close()
end

function http.listen(port)
  local server = socket.bind("*", port or 3000)

  -- make non-blocking
  server:settimeout(0)

  while true do
    local worked, err = sched:select()

    local client = server:accept()

    if client then
      sched:spawn(wrapper, client)
    end
  end

  print("Server listening on port " .. port)
end

function http.get(pattern, handler)
  http.handlers["GET " .. pattern] = handler
  return http
end

return http
