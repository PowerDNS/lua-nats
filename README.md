NATS Lua library
================

LUA client for NATS messaging system. https://nats.io

This repository is a fork of the [original implementation][original]
by [dawnangel][github].
It adds optional support for connecting to a NATS server over TLS,
and is maintained by [PowerDNS.com B.V][PowerDNS].

[original]: https://github.com/DawnAngel/lua-nats "Original repository"
[github]: https://github.com/dawnangel/ "Github repositories"
[PowerDNS]: https://www.powerdns.com/ "PowerDNS.com B.V"

[![License](https://img.shields.io/:license-mit-blue.svg)](https://mit-license.org)

Requirements
------------

* Lua >= 5.1
* [luasocket](https://github.com/diegonehab/luasocket)
* [lua-cjson](https://github.com/mpx/lua-cjson)
* [uuid](https://github.com/Tieske/uuid)
* [nats](https://github.com/derekcollison/nats) or [gnatsd](https://github.com/apcera/gnatsd)
* [luasec](https://github.com/lunarmodules/luasec) if TLS support is needed

This is a NATS Lua library for Lua 5.1, 5.2 and 5.3. The
libraries are copyright by their author 2015 (see the Creators
file for details), and released under the MIT license (the same
license as Lua itself). There is no warranty.


Usage
-----

### Basic usage: Subscribe / Unsubscribe

```lua
local nats = require 'nats'

local client = nats.connect({
    host = '127.0.0.1',
    port = 4222,
})

-- connect to the server
client:connect()

-- callback function for subscriptions
local function subscribe_callback(payload)
    print('Received data: ' .. payload)
end

-- subscribe to a subject
local subscribe_id = client:subscribe('foo', subscribe_callback)

-- wait until 2 messages come
client:wait(2)

-- unsubscribe from the subject
client:unsubscribe(subscribe_id)
```

### Basic usage: Publish

```lua
local nats = require 'nats'

local client = nats.connect({
    host = '127.0.0.1',
    port = 4222,
})

-- connect to the server
client:connect()

-- publish to a subject
local subscribe_id = client:publish('foo', 'message to be published')
```

### Basic usage: User authentication

```lua
local nats = require 'nats'

local client = nats.connect({
    host = '127.0.0.1',
    port = 4222,
})

-- user authentication
local user, password = 'user', 'password'
client:set_auth(user, password)

-- connect to the server
client:connect()
```

### Basic usage: TLS connection

```lua
local nats = require 'nats'

local client = nats.connect({
    host = '127.0.0.1',
    port = 4222,
    tls = true,
    tls_ca_path = '/etc/ssl/certs',
})

-- connect to the server using TLS and validating the server certificate
client:connect()
```

Developer's Information
-----------------------

### Installation of the libraries

To install the required libraries you can execute `make deps`.

### Tests

Tests are in the `tests` folder.
To run them, you require:

- `luarocks` and `telescope` installed.
- execute `make test`.

Creators
--------

**Eric Pinto**

- <https://twitter.com/_dawnangel_>
- <https://github.com/dawnangel>

Bug reports and code contributions
----------------------------------

These libraries are written and maintained by their users. Please make
bug report and suggestions on GitHub (see URL at top of file). Pull
requests are especially appreciated.
