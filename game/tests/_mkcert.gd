extends SceneTree
## Genera un cert+key PEM autofirmado en la ruta indicada por argv:
## godot --headless --path game -s tests/_mkcert.gd -- <dir>
func _init() -> void:
	var dir := OS.get_cmdline_user_args()[-1]
	var crypto := Crypto.new()
	var key := crypto.generate_rsa(2048)
	var cert := crypto.generate_self_signed_certificate(
		key, "CN=beliber-test,O=beliber,C=ES",
		"20200101000000", "20990101000000")
	var ok := key.save(dir + "/bel_key.pem") == OK \
		and cert.save(dir + "/bel_cert.pem") == OK
	print("cert:", "OK" if ok else "FAIL")
	quit(0 if ok else 1)
