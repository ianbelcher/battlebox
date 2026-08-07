extends Node
## Connection management. WebSocket transport (same server binary talks to
## every client; on a LAN the TCP-vs-UDP difference is negligible).

const DEFAULT_PORT := 9081

## The public world. One host serves the page, the downloads and the game
## socket, all on 443 — the websocket is proxied through the same origin
## as everything else (see nginx.conf), so there is only ever one name and
## one port to get wrong.
const PUBLIC_HOST := "battlebox.games"
const PUBLIC_SERVER_URL := "wss://battlebox.games/ws"

## Port the web role listens on when it is reached directly, with no proxy
## in front of it — a LAN box or a dev machine.
const WEB_PORT := 8081

signal connected_to_server
signal connection_failed
signal server_disconnected

var is_server := false

func _ready() -> void:
	multiplayer.connected_to_server.connect(func() -> void: connected_to_server.emit())
	multiplayer.connection_failed.connect(func() -> void: connection_failed.emit())
	multiplayer.server_disconnected.connect(func() -> void: server_disconnected.emit())

func start_server() -> Error:
	var port := DEFAULT_PORT
	var env_port := OS.get_environment("WORLD_PORT")
	if env_port.is_valid_int():
		port = env_port.to_int()
	var peer := WebSocketMultiplayerPeer.new()
	# Chunk payloads are ~10-20 KiB compressed; the default 64 KiB inbound
	# buffer is fine, but give outbound plenty of headroom for join bursts
	# (a new machine asks for ~150 chunks at once).
	peer.outbound_buffer_size = 4 * 1024 * 1024
	peer.inbound_buffer_size = 256 * 1024
	var err := peer.create_server(port)
	if err != OK:
		push_error("Failed to listen on port %d: %s" % [port, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	is_server = true
	print("BattleBox server listening on ws://0.0.0.0:%d" % port)
	return OK

## Host of the server we last connected to (the updater fetches builds from
## its web port). Falls back to the public world.
var last_host := PUBLIC_HOST

func connect_to(url: String) -> Error:
	var stripped := url.replace("ws://", "").replace("wss://", "")
	var host_part := stripped.split(":")[0].split("/")[0]
	if not host_part.is_empty():
		last_host = host_part
	var peer := WebSocketMultiplayerPeer.new()
	peer.outbound_buffer_size = 256 * 1024
	peer.inbound_buffer_size = 4 * 1024 * 1024
	var err := peer.create_client(url)
	if err != OK:
		push_error("Failed to start connection to %s: %s" % [url, error_string(err)])
		return err
	multiplayer.multiplayer_peer = peer
	return OK

## Drop the link on purpose — the world menu pointing this client at a
## different server. main.gd's reconnect loop dials the new address.
func disconnect_now() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	server_disconnected.emit()

func go_offline() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()

## In a browser the address is NOT ours to choose: go back to whatever
## origin served the page, on /ws. Same scheme, host and port as the page.
##
## A page served over https cannot open a plain ws:// socket at all — the
## browser blocks it as mixed content, with no prompt and nothing to click,
## so the game would sit on "Finding the world…" forever. Deriving it from
## the page is also what makes a preview deployment or a LAN copy work with
## no rebuild: the build never names a host.
##
## Native clients have no page to inherit from, so they get the public
## world. WORLD_SERVER_URL overrides it for a LAN or dev server.
func default_server_url() -> String:
	if OS.has_feature("web"):
		var host := str(JavaScriptBridge.eval("window.location.host", true))
		if not host.is_empty():
			var secure := str(JavaScriptBridge.eval(
				"window.location.protocol", true)) == "https:"
			return "%s://%s/ws" % ["wss" if secure else "ws", host]
	var forced := OS.get_environment("WORLD_SERVER_URL")
	if not forced.is_empty():
		return forced
	return PUBLIC_SERVER_URL

## Where this client fetches build downloads and version.txt from — the web
## side of whatever server it is connected to.
##
## The public world is behind a proxy that serves everything on 443; a LAN
## or dev server is a bare container with nothing in front of it, so its web
## role is on its own port. Getting this wrong is not visible until someone
## presses "Install update" and it 404s, so both cases live in one place.
func downloads_base() -> String:
	if last_host == PUBLIC_HOST or last_host.ends_with("." + PUBLIC_HOST):
		return "https://%s/downloads" % last_host
	return "http://%s:%d/downloads" % [last_host, WEB_PORT]
