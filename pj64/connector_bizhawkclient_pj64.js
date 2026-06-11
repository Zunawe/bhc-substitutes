// This script allows Project64 to communicate with Archipelago's BizHawk
// Client. It's intended to work on both the original Project64 and Luna's
// fork via Wine.

// For Luna's Project64
// In the menu, click `Debugger > Enable Debugger` and then Yes on the dialog
// that opens. Skip the next paragraph.

// For Project64
// While a game is running, open `Options > Configuration` in the menu.
// In General Settings, uncheck `Hide advanced settings`. Then go to Advanced
// and check `Enable debugger`. Then click OK to close the Configuration window.

// For both
// Open `Debugger > Scripts...` in the main emulator menu. In the new scripts
// window, click the `...` button in the bottom left corner to open Project64's
// scripts folder. Move this script into this folder, and it should appear in
// the left column of the scripts window. Double-clicking the script or
// selecting it and clicking the `Run` button will start the script.

// Only one instance of Project64 can connect to any BizHawk Client at a time.
// But it should be able to run alongside instances of BizHawk if PJ64 is
// connected last. If PJ64 connects first, clients will start getting stuck
// on it.


// Copyright (c) 2026 Zunawe
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.


const DEBUG = false

const BHC_SERVER_PORTS = [43055, 43056, 43057, 43058, 43059]
const DOMAIN_OFFSETS = {
    'RDRAM': 0xA0000000,
    'VI Register': 0xA4400000,
    'AI Register': 0xA4500000,
    'PI Register': 0xA4600000,
    'RI Register': 0xA4700000,
    'SI Register': 0xA4800000,
    // 'EEPROM': No direct access,
    // 'SRAM': No direct access,
    // 'FlashRAM': No direct access,
    'ROM': 0xB0000000,
    'System Bus': 0x0,
}

function checkDomain (req) {
    if (DOMAIN_OFFSETS[req.domain] === undefined) {
        return {
            type: 'ERROR',
            err: 'Domain ' + req.domain + ' is not supported/known by the Project64 connector script.',
        }
    }
    return null
}

function main () {
    var clientsConnected = 0
    const requestChainQueue = []
    const messageQueue = []
    var messageTimer = 0
    var messageInterval = 0

    console.log('Starting server')
    const server = new Server({})
    function startServer () {
        for (var i = 0; i < BHC_SERVER_PORTS.length; ++i) {
            try {
                server.listen(BHC_SERVER_PORTS[i])
                return true
            } catch (error) {}
        }
        return false
    }
    if (!startServer()) {
        console.log('All ports busy. No more connections can be supported. Exiting script.')
        return
    }

    server.on('connection', function (socket) {
        // This doesn't actually work because the client doesn't move on to
        // other ports if it establishes a connection, even if it closes
        // immediately. But, it does bounce out other clients.
        ++clientsConnected
        if (clientsConnected > 1) {
            socket.close()
            return
        }

        console.log('Client connected')
        socket.on('data', function (data) {
            if (data == 'VERSION\n') {
                socket.write('1\n')
                return
            }
            if (DEBUG) {
                console.log('Received Message: ' + '"' + data.toString() + '"')
            }
            requestChainQueue.push({
                requests: JSON.parse(data.toString()),
                callback: function (response) {
                    socket.write(JSON.stringify(response) + '\n')
                },
            })
        })

        socket.on('close', function () {
            --clientsConnected
        })
    })

    const requestHandlers = {
        'PING': function (req) {
            return { type: 'PONG' }
        },
        'SYSTEM': function (req) {
            return { type: 'SYSTEM_RESPONSE', value: 'N64' }
        },
        'PREFERRED_CORES': function (req) {
            return { type: 'PREFERRED_CORES_RESPONSE', value: {} }
        },
        'HASH': function (req) {
            // ROM header's check code, which is the best we can do
            return { type: 'HASH_RESPONSE', value: Duktape.enc('base64', rom.getblock(0x10, 8)) }
        },
        'MEMORY_SIZE': function (req) {
            // TODO: Implement if possible
            // Current PJ64 does have a romSize and ramSize attribute, but
            // Luna's doesn't
            return { type: 'MEMORY_SIZE_RESPONSE', value: 0 }
        },
        'GUARD': function (req) {
            var result
            if ((result = checkDomain(req)) !== null) {
                return result
            }

            expectedData = Duktape.dec('base64', req.expected_data)
            data = Duktape.Buffer(req.expected_data.length)
            switch (req.domain) {
                case 'ROM':
                    for (var i = 0; i < req.size; ++i) {
                        data[i] = rom.u8[req.address + i]
                    }
                    break
                default:
                    for (var i = 0; i < req.size; ++i) {
                        data[i] = mem.u8[DOMAIN_OFFSETS[req.domain] + req.address + i]
                    }
                    break
            }

            validated = true
            for (var i = 0; i < expectedData.length; ++i) {
                if (expectedData[i] !== data[i]) {
                    validated = false
                    break
                }
            }

            return {
                type: 'GUARD_RESPONSE',
                value: validated,
                address: req.address,
            }
        },
        'LOCK': function (req) {
            return { type: 'ERROR', err: 'LOCK is unimplemented' }
        },
        'UNLOCK': function (req) {
            return { type: 'ERROR', err: 'UNLOCK is unimplemented' }
        },
        'READ': function (req) {
            var result
            if ((result = checkDomain(req)) !== null) {
                return result
            }

            data = Duktape.Buffer(req.size)
            switch (req.domain) {
                case 'ROM':
                    for (var i = 0; i < req.size; ++i) {
                        data[i] = rom.u8[req.address + i]
                    }
                    break
                default:
                    for (var i = 0; i < req.size; ++i) {
                        data[i] = mem.u8[DOMAIN_OFFSETS[req.domain] + req.address + i]
                    }
                    break
            }
            return {
                type: 'READ_RESPONSE',
                value: Duktape.enc('base64', data),
            }
        },
        'WRITE': function (req) {
            var result
            if ((result = checkDomain(req)) !== null) {
                return result
            }

            data = Duktape.dec('base64', req.value)
            for (var i = 0; i < data.length; ++i) {
                mem.u8[DOMAIN_OFFSETS[req.domain] + req.address + i] = data[i]
            }
            return { type: 'WRITE_RESPONSE' }
        },
        'DISPLAY_MESSAGE': function (req) {
            messageQueue.push(req.message)
            return { type: 'DISPLAY_MESSAGE_RESPONSE' }
        },
        'SET_MESSAGE_INTERVAL': function (req) {
            messageInterval = req.value
            return { type: 'SET_MESSAGE_INTERVAL_RESPONSE' }
        },
    }

    events.ondraw(function () {
        if (messageQueue.length > 0) {
            --messageTimer
            if (messageTimer <= 0) {
                // Could use screen.print here, but it's currently quite
                // flickery and needs to be called every frame, so we'd need to
                // manually display messages in the queue with a tracked lifetime
                // at programmatically determined coordinates.
                console.log(messageQueue.shift())
                if (messageQueue.length > 0) {
                    messageTimer = messageInterval
                }
            }
        }

        if (requestChainQueue.length === 0) return

        var next = requestChainQueue.shift()
        var failedGuard = null

        const responses = []
        for (var i = 0; i < next.requests.length; ++i) {
            if (failedGuard !== null) {
                responses.push(res)
                continue
            }

            res = requestHandlers[next.requests[i].type](next.requests[i])
            responses.push(res)
            if (res.type === 'GUARD' && !res.value) {
                failedGuard = res
            }
        }

        next.callback(responses)
    })
}

main()
