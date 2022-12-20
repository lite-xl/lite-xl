---@meta

---A wrapper around SDL_Net to provide TCP and UDP Network functionality.
---@see SDL_Net https://github.com/libsdl-org/SDL_net
---@class net
net = {}

---A list of TCP or UDP sockets to monitor for incoming data.
---@class net.Set
net.Set = {}

---A TCP socket.
---@class net.TCP
net.TCP = {}

---A UDP socket.
---@class net.UDP
net.UDP = {}

---@class net.address
---@field host string
---@field port integer

---
---Initialize network system.
---
---You must successfully call this function before it is safe to call any
---other function in this library.
---
---It is safe to call this more than once; the library keeps a counter of init
---calls, and decrements it on each call to net.quit, so you must pair your
---init and quit calls.
---
---@return boolean success False on failure.
function net.init() end

---
---Deinitialize network system.
---
---You must call this when done with the library, to free internal resources.
---It is safe to call this when the library isn't initialized, as it will just
---return immediately.
---
---Once you have as many quit calls as you have had successful calls to
---net.init, the library will actually deinitialize.
function net.quit() end

---
---Resolve a host name to an IP address.
---
---@param host string The hostname to lookup (like "lite-xl.org")
---
---@return string? ip
---@return string? errmsg
function net.resolve_host(host) end

---
---Resolve an IP address to a host name in canonical form.
---
---@param ip string The ip to resolve (like "127.0.0.1")
---
---@return string? hostname
---@return string? errmsg
function net.resolve_ip(ip) end

---
---Get the addresses of network interfaces on this system.
---
---@param max_amount? integer The number of results to retrieve
---
---@return table<integer,string> | nil ip_list List of ip addresses
function net.get_local_addresses(max_amount) end

---
---Allocate a socket set to easily check if a group of sockets has sent any data.
---
---To query if new data is available on a socket, you call the
---net.Set:check_sockets() method. A socket set is just a list of sockets
---behind the scenes; you allocate a set and then add/remove individual
---sockets to/from the set.
---
---@param max_sockets integer Maximum amount of sockets to include in this set.
---
---@return net.Set
function net.set(max_sockets) end

---
---Open a TCP network socket.
---
---@param host string
---@param port integer
---
---@return net.TCP? socket The newly created socket, or nil if there was an error.
---@return string? errmsg
function net.open_tcp(host, port) end

---
---Open a UDP network socket.
---
---If `port` is non-zero, the UDP socket is bound to a local port.
---
---Note that UDP sockets at the platform layer "bind" to a nework port number,
---but net UDP sockets also "bind" to a "channel" on top of that, with
---net.UDP:bind(). But the term is used for both.
---
---@param port integer
---
---@return net.UDP socket The newly created socket, or nil if there was an error.
---@return string? errmsg
function net.open_udp(port) end

---
---Add a socket to a set, to be checked for available data.
---
---@param socket net.TCP | net.UDP
---
---@return integer? len Current set leight
---@return string? errmsg
function net.Set:add(socket) end

---
---Remove a socket from a set.
---
---@param socket net.TCP | net.UDP
---
---@return integer? len Current set leight
---@return string? errmsg
function net.Set:delete(socket) end

---
---Check a socket set for data availability.
---
---This function checks to see if data is available for reading on the given
---set of sockets. If 'timeout' is 0, it performs a quick poll, otherwise the
---function returns when either data is available for reading, or the timeout
---in milliseconds has elapsed, whichever occurs first.
---
---@param timeout integer
---
---@return integer? ready Sockets ready for reading
---@return string? errmsg
function net.Set:check_sockets(timeout) end

---
---Accept an incoming connection on the given server socket.
---
---Note: To create a server socket you have to use 0.0.0.0 as the address
---when creating the TCP socket with net.open_tcp()
---
---@return net.TCP client
function net.TCP:accept() end

---
---Get the IP address of the remote system associated with the socket.
---
---If the socket is a server socket, this function returns nil.
---
---@return net.address? address The address information for the socket.
function net.TCP:get_peer_address() end

---
---Send data over a non-server socket.
---
---Must be a valid socket that was created by net.open_tcp with a specific
---address, or net.TCP:accept.
---
---This function returns true if data sent. If the return value
---is false then either the remote connection was closed, or an unknown
---socket error occurred.
---
---@return boolean success
---@return string? errmsg
function net.TCP:send(data) end

---
---Receive data from a non-server socket.
---
---Must be a valid socket that was created by net.open_tcp with a specific
---address, or net.TCP:accept.
---
---@param max_len integer The maximum number of bytes to retrieve.
---
---@return string? data
---@return string? errmsg
function net.TCP:receive(max_len) end

---
---See if a specific socket has data available after checking it in a set.
---
---After calling net.Set:check_sockets(), you can use this function on a
---socket that was in the socket set, to find out if data is available
---for reading.
---
---@return boolean is_ready
function net.TCP:ready() end

---
---Close a TCP network socket.
---
---All TCP sockets (server and non-server) are deinitialized through this
---function. Call this once you are done with a socket, and assume the handle
---is invalid once you have.
function net.TCP:close() end

---
---Bind an address to the requested channel on the UDP socket.
---
---Note that UDP sockets at the platform layer "bind" to a nework port number,
---but net.UDP sockets also "bind" to a "channel" on top of that, with
---net.UDP:Bind(). But the term is used for both.
---
---If `channel` is -1, then the first unbound channel that has not yet been
---bound to the maximum number of addresses will be bound with the given
---address as it's primary address.
---
---If the channel is already bound, this new address will be added to the list
---of valid source addresses for packets arriving on the channel. If the
---channel is not already bound, then the address becomes the primary address,
---to which all outbound packets on the channel are sent.
---
---@param channel integer The channel of the socket to bind to, or -1 to use
---the first available channel.
---@param address net.address The address to bind to the socket's channel.
---
function net.UDP:bind(channel, address) end

---
---Unbind all addresses from the given channel.
---
---Note that UDP sockets at the platform layer "bind" to a nework port number,
---but net.UDP sockets also "bind" to a "channel" on top of that, with
---net.UDP:Bind(). But the term is used for both.
---
---@param channel integer The channel of the socket to unbind.
function net.UDP:unbind(channel) end

---
---Get the IP address of the remote system for a socket and channel.
---
---If `channel` is -1, then the primary IP port of the UDP socket is returned
---this is only meaningful for sockets opened with a specific port.
---
---If the channel is not bound and not -1, this function returns nil.
---
---@param channel integer
---
---@return net.address address
function net.UDP:get_peer_address(channel) end

---
---Send a single UDP packet to the specified channel or address.
---
---**Warning**: UDP is an _unreliable protocol_, which means we can report
---that your packet has been successfully sent from your machine, but then it
---never makes it to its destination when a router along the way quietly drops
---it. If this happens--and this is a common result on the internet!--you will
---not know the packet never made it. Also, packets may arrive in a different
---order than you sent them. Plan accordingly!
---
---**Warning**: The maximum size of the packet is limited by the MTU (Maximum
---Transfer Unit) of the transport medium. It can be as low as 250 bytes for
---some PPP links, and as high as 1500 bytes for ethernet. Different sizes can
---be sent, but the system might split it into multiple transmission fragments
---behind the scenes, that need to be reassembled on the other side (and the
---packet is lost if any fragment is lost in transit). So the less you can
---reasonably send in a single packet, the better, as it will be more reliable
---and lower latency.
---
---@param data string
---@param destination integer | net.address Can be a channel or address.
---
---@return integer? sent
---@return string? errmsg
function net.UDP:send(data, destination) end

---
---Receive a single packet from a UDP socket.
---
---@param max_len integer
---
---@return string? data
---@return boolean | string | nil has_more_or_errmsg
function net.UDP:receive(max_len) end

---
---See if a specific socket has data available after checking it in a set.
---
---After calling net.Set:check_sockets(), you can use this function on a
---socket that was in the socket set, to find out if data is available
---for reading.
---
---@return boolean is_ready
function net.UDP:ready() end

---
---Close a UPD network socket.
---
---This socket may not be used again.
function net.UDP:close() end


return net
