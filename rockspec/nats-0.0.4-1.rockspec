package = "nats"
version = "0.0.4-1"

source = {
   url = "git://github.com/PowerDNS/lua-nats.git",
   tag = "0.0.4"
}

description = {
   summary = "LUA client for NATS messaging system. https://nats.io/",
   detailed = [[
      LUA client for NATS messaging system. https://nats.io/
      Fork of the original implementation https://github.com/DawnAngel/lua-nats/
      by Eric Pinto <https://github.com/DawnAngel/>
   ]],
   homepage = "https://github.com/PowerDNS/lua-nats/",
   maintainer = "PowerDNS.com B.V.<https://www.powerdns.com/>",
   license = "MIT"
}

dependencies = {
   "lua >= 5.1",
   "luasocket",
   "lua-cjson",
   "uuid"
}

build = {
   type = "none",
   install = {
      lua = {
         "src/nats.lua"
      }
   }
}
