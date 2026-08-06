extends Node
## Connection management. WebSocket transport (same server binary talks to
## every client; on a LAN the TCP-vs-UDP difference is negligible).

const DEFAULT_PORT := 9081
## NodePort the game-server Service is exposed on (see _configurations/world.yaml).
const LAN_NODE_PORT := 30810
const DEFAULT_LAN_HOST := "10.0.0.200"

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
	print("Voxel Battle server listening on ws://0.0.0.0:%d" % port)
	return OK

## Host of the server we last connected to (updater fetches from its web
## port). Falls back to the LAN default.
var last_host := DEFAULT_LAN_HOST

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
## origin served the page, on /ws.
##
## This has to be the same scheme, host AND port as the page, and that is
## not tidiness — it is the only arrangement that works. The certificate
## is self-signed, so the browser refuses it until someone clicks through
## the warning, and it only ever offers that click for the PAGE. A socket
## to any other origin is refused with no warning and no way to accept it,
## so the game would sit on "Finding the world…" forever with nothing to
## click. nginx proxies /ws through to this same server binary.
func default_server_url() -> String:
	if OS.has_feature("web"):
		var host := str(JavaScriptBridge.eval("window.location.host", true))
		if not host.is_empty():
			var secure := str(JavaScriptBridge.eval(
				"window.location.protocol", true)) == "https:"
			return "%s://%s/ws" % ["wss" if secure else "ws", host]
	return "ws://%s:%d" % [DEFAULT_LAN_HOST, LAN_NODE_PORT]
