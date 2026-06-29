extends Node
## Phantom wallet bridge for the web export (via JavaScriptBridge), with a demo
## fallback for editor/native runs. Web browsers without Phantom stay unsigned.

signal changed

var address := ""
var connected := false
var token := ""
var verified := false
var last_error := ""

func short() -> String:
	if address.length() <= 10:
		return address
	return address.substr(0, 4) + "..." + address.substr(address.length() - 4)

func connect_wallet() -> void:
	token = ""
	verified = false
	last_error = ""
	if not OS.has_feature("web"):
		address = "DEMO7H3K9XQ2vN"
		connected = true
		changed.emit()
		return
	var has_phantom = JavaScriptBridge.eval("!!(window.solana && window.solana.isPhantom)", true)
	if not bool(has_phantom):
		address = ""
		connected = false
		last_error = "Phantom not found"
		JavaScriptBridge.eval("window.__avwWalletAddress=''; window.__avwWalletToken=''; window.__avwWalletVerified=false; window.__avwWalletError='Phantom not found';", true)
		changed.emit()
		return
	var immediate = JavaScriptBridge.eval("""
	(function(){
		window.__avwWalletAddress = window.__avwWalletAddress || "";
		window.__avwWalletToken = "";
		window.__avwWalletVerified = false;
		window.__avwWalletError = "";
		if (window.solana && window.solana.isPhantom) {
			window.solana.connect().then(async function(r){
				const address = r.publicKey.toString();
				window.__avwWalletAddress = address;
				const challenge = await fetch('/wallet-challenge', {
					method: 'POST',
					headers: {'content-type':'application/json'},
					body: JSON.stringify({address})
				}).then(function(res){ return res.json(); });
				if (!challenge.ok) throw new Error(challenge.error || 'wallet challenge failed');
				const signed = await window.solana.signMessage(new TextEncoder().encode(challenge.message), 'utf8');
				const bytes = signed.signature || signed;
				let binary = '';
				for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
				const login = await fetch('/wallet-login', {
					method: 'POST',
					headers: {'content-type':'application/json'},
					body: JSON.stringify({address, nonce: challenge.nonce, signature: btoa(binary)})
				}).then(function(res){ return res.json(); });
				if (!login.ok) throw new Error(login.error || 'wallet login failed');
				window.__avwWalletToken = login.token || '';
				window.__avwWalletVerified = !!login.verified;
			}).catch(function(err){
				window.__avwWalletError = String(err && err.message || err);
			});
			return "";
		}
		window.__avwWalletAddress = "DEMO" + Math.random().toString(36).slice(2, 10).toUpperCase();
		return window.__avwWalletAddress;
	})()
	""", true)
	if immediate != null and String(immediate) != "":
		address = String(immediate)
		connected = true
		changed.emit()
		return
	_poll(0)

func _poll(n: int) -> void:
	await get_tree().create_timer(0.35).timeout
	var changed_state := _read_web_wallet_state()
	if changed_state:
		changed.emit()
	if connected and (verified or last_error != "" or n >= 18):
		return
	if n < 18:
		_poll(n + 1)

func _read_web_wallet_state() -> bool:
	var old_address := address
	var old_connected := connected
	var old_token := token
	var old_verified := verified
	var old_error := last_error
	var a = JavaScriptBridge.eval("window.__avwWalletAddress || ''", true)
	var t = JavaScriptBridge.eval("window.__avwWalletToken || ''", true)
	var v = JavaScriptBridge.eval("!!window.__avwWalletVerified", true)
	var e = JavaScriptBridge.eval("window.__avwWalletError || ''", true)
	if a != null and String(a) != "":
		address = String(a)
		connected = true
	if t != null:
		token = String(t)
	verified = bool(v)
	if e != null:
		last_error = String(e)
	return old_address != address or old_connected != connected or old_token != token or old_verified != verified or old_error != last_error

func disconnect_wallet() -> void:
	address = ""
	connected = false
	token = ""
	verified = false
	last_error = ""
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.__avwWalletAddress=''; window.__avwWalletToken=''; window.__avwWalletVerified=false; window.__avwWalletError='';", true)
	changed.emit()
