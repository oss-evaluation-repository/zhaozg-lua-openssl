local openssl = require 'openssl'
local bio, ssl = openssl.bio, openssl.ssl
local sslctx = require 'sslctx'
local _, _, opensslv = openssl.version(true)
local host, port, loop

local arg = assert(arg)
host = arg[1] or "127.0.0.1"; -- only ip
port = arg[2] or "8383";
loop = arg[3] and tonumber(arg[3]) or 100

local params = {
  mode = "server",
  protocol = ssl.default,
  key = "luasec/certs/serverAkey.pem",
  certificate = "luasec/certs/serverA.pem",
  cafile = "luasec/certs/rootA.pem",
  verify = ssl.peer + ssl.fail,
  options = {"all",  "no_sslv2"}
}

local params01 = {
  mode = "server",
  protocol = ssl.default,
  key = "luasec/certs/serverAkey.pem",
  certificate = "luasec/certs/serverA.pem",
  cafile = "luasec/certs/rootA.pem",
  verify = ssl.none,
  options = {"all",  "no_sslv2"},
  ciphers = "ALL:!ADH:@STRENGTH",
}

local params02 = {
  mode = "server",
  protocol = ssl.default,
  key = "luasec/certs/serverBkey.pem",
  certificate = "luasec/certs/serverB.pem",
  cafile = "luasec/certs/rootB.pem",
  verify = ssl.none,
  options = {"all",  "no_sslv2"},
  ciphers = "ALL:!ADH:@STRENGTH",
}

local certstore
if opensslv > 0x10002000 then
  certstore = openssl.x509.store:new()
  local cas = require 'root_ca'
  for i = 1, #cas do
    local cert = assert(openssl.x509.read(cas[i]))
    assert(certstore:add(cert))
  end
end


local function ssl_mode()
  local ctx = assert(sslctx.new(params))
  assert(ctx:verify_mode())
  assert(ctx:verify_depth(9)==9)

  local ctx01 = assert(sslctx.new(params01))
  local ctx02 = assert(sslctx.new(params02))

  ctx:set_servername_callback({
    ["servera.br"]  = ctx01,
    ["serveraa.br"] = ctx02,
  })

  if certstore then ctx:cert_store(certstore) end
  -- ctx:set_cert_verify({always_continue=true,verify_depth=4})
  ctx:set_cert_verify(function(arg)
    -- do some check
    --[[
          for k,v in pairs(arg) do
                print(k,v)
          end
     --]]
    return true -- return false will fail ssh handshake
  end)

  print(string.format('Listen at %s:%s SSL', host, port))
  local srv = assert(bio.accept(host .. ':' .. port))
  local i = 0
  if srv then
    -- make real listen
    -- FIXME
    if(srv:accept(true)) then
      while i < loop do
        local cli = assert(srv:accept()) -- bio tcp
        local s = ctx:ssl(cli, true)
        if (i % 2 == 0) then
          assert(s:handshake())
        else
          assert(s:accept())
        end
        s:getpeerverification()
        s:dup()
        repeat
          local d = s:read()
          if d then assert(#d == s:write(d)) end
        until not d
        s:shutdown()
        s:session()
        s:ctx()
        s:cache_hit()
        s:session_reused()
        s:clear()
        assert(type(tostring(s))=='string')
        cli:close()
        cli = nil
        assert(cli==nil)
        collectgarbage()
        i = i + 1
      end
    end
    srv:close()
  end
end

ssl_mode()
print(openssl.error(true))
