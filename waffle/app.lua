local async = require 'async'
local response = require 'waffle.response'
local paths = require 'waffle.paths'
local string = require 'waffle.string'

local app = {}
app.properties = {}
app.viewFuncs = {}
app.errorFuncs = {}

app.set = function(field, value)
   app.properties[field] = value

   if field == 'public' then
      for file in paths.gwalk(value) do
         local route = file

         if string.sub(file, 1, 1) == '.' then
            route = string.sub(file, 2)
         end

         app.get(route, function(req, res)
            res.sendFile(file)
         end)
      end
   end
end

local _handle = function(request, handler)
   local url = request.url.path
   local method = request.method
   response.new()
   response.setHandler(handler)

   for pattern, funcs in pairs(app.viewFuncs) do
      local match = {string.match(url, pattern)}
      local b1 = #match > 0
      local b2 = match[1] == '/'
      local b3 = url == '/'

      if b1 and (not(b2) or b3) then
         request.params = match
         request.url.args = {}
         for param in string.gsplit(request.url.query, '&') do
            local arg = string.split(param, '=')
            request.url.args[arg[1]] = arg[2]
         end

         if funcs[method] then
            local ok, err = pcall(function() 
               funcs[method](request, response) 
            end)
            if not(ok) then
               if app.properties.debug then print(err) end
               app.abort(500, err, request, response) 
            end
         else app.abort(403, 'Forbidden', request, response)
         end

         return
      end
   end

   app.abort(404, 'Not Found', request, response)
end

app.listen = function(options)
   local options = options or {}
   local host, port

   if (options.host) then host = options.host
   else host = '127.0.0.1' end
   if (options.port) then port = options.port
   else port = '8080' end

   async.http.listen({host=host, port=port}, _handle)
   print(string.format('Listening on %s:%s', host, port))
   async.go()
end

app.serve = function(url, method, cb)
   if app.viewFuncs[url] == nil then
      app.viewFuncs[url] = {}
   end
   app.viewFuncs[url][method] = cb
end

app.get = function(url, cb) app.serve(url, 'GET', cb)
end

app.post = function(url, cb) app.serve(url, 'POST', cb)
end

app.put = function(url, cb) app.serve(url, 'PUT', cb)
end

app.delete = function(url, cb) app.serve(url, 'DELETE', cb)
end

app.error = function(errorCode, cb)
   app.errorFuncs[errorCode] = cb
end

app.abort = function(errorCode, description, req, res)
   if app.errorFuncs[errorCode] ~= nil then
      app.errorFuncs[errorCode](description, req, res)
      return
   else
      res.setStatus(errorCode)
      res.setHeader('Content-Type', 'text/html')
      res.send(string.format(
[[<html>
<head></head>
<body><h1>Error: %d</h1><p>%s</p></body>
</html>]], errorCode, async.http.codes[errorCode]))
   end
end

return app