local nats = {
    _VERSION     = 'lua-nats 0.0.5',
    _DESCRIPTION = 'LUA client for NATS messaging system. https://nats.io',
    _COPYRIGHT   = 'Copyright (C) 2015 Eric Pinto',
}


-- ### Library requirements ###

local cjson  = require('cjson')
local uuid   = require('uuid')

-- set the random number generator for /dev/urandom. On Windows this isn't available
-- and it returns nil+error, which is passed on to set_rng which then
-- throws a meaningful error.
uuid.set_rng(uuid.rng.urandom())

-- ### Local properties ###

local unpack = _G.unpack or table.unpack
local network, request, response, command = {}, {}, {}, {}

local client_prototype = {
    user          = nil,
    pass          = nil,
    lang          = 'lua',
    version       = '0.0.5',
    verbose       = false,
    pedantic      = false,
    trace         = false,
    reconnect     = true,
    subscriptions = {},
    information   = {},
}

local defaults = {
    host        = '127.0.0.1',
    port        = 4222,
    tcp_nodelay = true,
    path        = nil,
    tls         = false,
    tls_ca_path = nil,
    tls_ca_file = nil,
    tls_cert    = nil,
    tls_key     = nil,
}

-- ### Create a properly formatted inbox subject.

local function create_inbox()
    return '_INBOX.' .. uuid()
end

-- ### Local methods ###

local function merge_defaults(parameters)
    if parameters == nil then
        parameters = {}
    end
    for k, _ in pairs(defaults) do
        if parameters[k] == nil then
            parameters[k] = defaults[k]
        end
    end
    return parameters
end

local function load_methods(proto, commands)
    -- inherit client metatable from client_proto metatable
    local client = setmetatable({}, getmetatable(proto))

    -- Assign commands functions to the client
    for cmd, fn in pairs(commands) do
        if type(fn) ~= 'function' then
            nats.error('invalid type for command ' .. cmd .. '(must be a function)')
        end
        client[cmd] = fn
    end

    -- assing client properties and methods from client_proto
    for i, v in pairs(proto) do
        client[i] = v
    end

    return client
end

local function create_client(client_proto, client_socket, commands, parameters)
    local client = load_methods(client_proto, commands)
    -- assign client error handler
    client.error = nats.error
    -- keep parameters around, for TLS
    client.parameters = parameters
    -- assign client network methods
    client.network = {
        socket = client_socket,
        read   = network.read,
        write  = network.write,
        lread  = nil,
        lwrite = nil,
    }
    -- assign client requests methods
    client.requests = {
        multibulk = request.raw,
    }
    uuid.seed()
    return client
end

-- ### Network methods ###

function network.write(client, buffer)
    if client.trace then print('->> '..buffer:sub(1,-3)) end
    local _, err = client.network.socket:send(buffer)
    if not err then
        client.network.lwrite = buffer
    else
        client.error(err)
    end
end

function network.read(client, len)
    if len == nil then len = '*l' end
    local line, err = client.network.socket:receive(len)
    if client.trace then print('<<- '..line) end
    if not err then
        client.network.lread = line
        return line
    else
        client.error('connection error: ' .. err)
    end
end

-- ### Response methods ###

-- Client response reader
function response.read(client)
    local payload = client.network.read(client)
    local slices  = {}
    local data    = {}

    for slice in payload:gmatch('[^%s]+') do
        table.insert(slices, slice)
    end

    -- PING
    if slices[1] == 'PING' then
        data.action = 'PING'

    -- PONG
    elseif slices[1] == 'PONG' then
        data.action = 'PONG'

    -- MSG
    elseif slices[1] == 'MSG' then
        data.action    = 'MSG'
        data.subject   = slices[2]
        data.unique_id = slices[3]
        -- ask for line ending chars and remove them
        if #slices == 4 then
            data.content   = client.network.read(client,  slices[4]+2):sub(1, -3)
        else
            data.reply     = slices[4]
            data.content   = client.network.read(client,  slices[5]+2):sub(1, -3)
        end

    -- INFO
    elseif slices[1] == 'INFO' then
        data.action  = 'INFO'
        data.content = slices[2]

    -- INFO
    elseif slices[1] == '+OK' then
        data.action  = 'OK'

    -- INFO
    elseif slices[1] == '-ERR' then
        data.action  = 'ERROR'
        -- data.content = slices[2]

   -- unknown type of reply
    else
        data = client.error('unknown response: ' .. payload)
    end

    return data
end


-- ### Request methods ###

-- Client request sender (RAW)
function request.raw(client, buffer)
    local bufferType = type(buffer)

    if bufferType == 'table' then
        client.network.write(client, table.concat(buffer))
    elseif bufferType == 'string' then
        client.network.write(client, buffer)
    else
        client.error('argument error: ' .. bufferType)
    end
end


-- ### Client prototype methods ###

client_prototype.raw_cmd = function(client, buffer)
    request.raw(client, buffer .. '\r\n')
    return response.read(client)
end

client_prototype.set_auth = function(client, user, pass)
    client.user = user
    client.pass = pass
end

client_prototype.enable_trace = function(client)
    client.trace = true
end

client_prototype.set_verbose = function(client, verbose)
    client.verbose = verbose
end

client_prototype.set_pedantic = function(client, pedantic)
    client.pedantic = pedantic
end

client_prototype.count_subscriptions = function(client)
    return #client.subscriptions
end

client_prototype.get_server_info = function(client)
    return client.information
end

client_prototype.upgrade_to_tls = function(client)
    local status, luasec = pcall(require, 'ssl')
    if not status then
        nats.error('TLS is required but the luasec library is not available')
    end
    local params = {
        capath = client.parameters.tls_ca_path,
        cafile = client.parameters.tls_ca_file,
        certificate = client.parameters.tls_cert,
        key = client.parameters.tls_key,
        mode = "client",
        options = {"all", "no_sslv3"},
        protocol = "tlsv1_2",
        verify = "peer",
    }

    client.network.socket = luasec.wrap(client.network.socket, params)
    client.network.socket:dohandshake()
end

client_prototype.shutdown = function(client)
    client.network.socket:shutdown()
end

-- ### Socket connection methods ###

local function connect_tcp(socket, parameters)
    local host, port = parameters.host, tonumber(parameters.port)
    if parameters.timeout then
        socket:settimeout(parameters.timeout, 't')
    end

    local ok, err = socket:connect(host, port)
    if not ok then
        nats.error('could not connect to '..host..':'..port..' ['..err..']')
    end
    socket:setoption('tcp-nodelay', parameters.tcp_nodelay)
    return socket
end

local function connect_unix(socket, parameters)
    local ok, err = socket:connect(parameters.path)
    if not ok then
        nats.error('could not connect to '..parameters.path..' ['..err..']')
    end
    return socket
end

local function create_connection(parameters)
    if parameters.socket then
        return parameters.socket
    end

    local perform_connection, socket

    if parameters.scheme == 'unix' then
        perform_connection, socket = connect_unix, require('socket.unix')
        assert(socket, 'your build of LuaSocket does not support UNIX domain sockets')
    else
        if parameters.scheme then
            local scheme = parameters.scheme
            assert(scheme == 'nats' or scheme == 'tcp' or scheme == 'tls', 'invalid scheme: '..scheme)
            if scheme == 'tls' then
                parameters.tls = true
            end
        end
        perform_connection, socket = connect_tcp, require('socket').tcp
    end

    return perform_connection(socket(), parameters)
end

-- ### Nats library methods ###

function nats.error(message, level)
    error(message, (level or 1) + 1)
end

function nats.connect(...)
    local args, parameters = {...}, nil

    if #args == 1 then
        parameters = args[1]
    elseif #args > 1 then
        local host, port, timeout = unpack(args)
        parameters = { host = host, port = port, timeout = tonumber(timeout) }
    end

    local commands = nats.commands or {}
    if type(commands) ~= 'table' then
        nats.error('invalid type for the commands table')
    end

    local socket = create_connection(merge_defaults(parameters))
    local client = create_client(client_prototype, socket, commands, parameters)

    return client
end

function nats.command(cmd, opts)
    return command(cmd, opts)
end

-- ### Command methods ###

function command.connect(client)
    local config = {
        lang         = client.lang,
        version      = client.version,
        verbose      = client.verbose,
        pedantic     = client.pedantic,
        tls_required = client.parameters.tls,
    }

    if client.user ~= nil and client.pass ~= nil then
        config.user = client.user
        config.pass = client.pass
    end

    -- gather the server information
    local data = response.read(client)
    if data.action == 'INFO' then
        client.information = cjson.decode(data.content)
        if client.parameters.tls then
            if (client.information['tls_available'] or client.information['tls_required']) then
                client:upgrade_to_tls()
            else
                nats.error('TLS is required but not offered by the server')
            end
        end
    end

    request.raw(client, 'CONNECT '..cjson.encode(config)..'\r\n')
end

function command.ping(client)
    request.raw(client, 'PING\r\n')

    -- wait for the server pong
    local data = response.read(client)
    if data.action == 'PONG' then
        return true
    else
        return false
    end

end

function command.pong(client)
    request.raw(client, 'PONG\r\n')
end

function command.request(client, subject, payload, callback)
    local inbox = create_inbox()
    local unique_id = uuid()
    client:subscribe(inbox, function(message, reply)
        client:unsubscribe(unique_id)
        callback(message, reply)
    end, unique_id)
    client:publish(subject, payload, inbox)
    return unique_id, inbox
end

function command.subscribe(client, subject, callback, unique_id)
    unique_id = unique_id or uuid()
    request.raw(client, 'SUB '..subject..' '..unique_id..'\r\n')
    client.subscriptions[unique_id] = callback

    return unique_id
end

function command.unsubscribe(client, unique_id)
    request.raw(client, 'UNSUB '..unique_id..'\r\n')
    client.subscriptions[unique_id] = nil
end

function command.publish(client, subject, payload, reply)
    if reply ~= nil then
        reply = ' '..reply
    else
        reply = ''
    end
    request.raw(client, {
        'PUB '..subject..reply..' '..#payload..'\r\n',
        payload..'\r\n',
    })
end

function command.wait(client, quantity)
    quantity = quantity or 0

    local count = 0
    repeat
        local data = response.read(client)

        if data.action == 'PING' then
            command.pong(client)

        elseif data.action == 'MSG' then
            count = count + 1
            client.subscriptions[data.unique_id](data.content, data.reply)
        end
    until quantity > 0 and count >= quantity
end

-- Commands defined in this table do not take the precedence over
-- methods defined in the client prototype table.

nats.commands = {
    connect     = command.connect,
    ping        = command.ping,
    pong        = command.pong,
    request     = command.request,
    subscribe   = command.subscribe,
    unsubscribe = command.unsubscribe,
    publish     = command.publish,
    wait        = command.wait,
}

return nats
