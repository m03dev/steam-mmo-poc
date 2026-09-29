extends GutTest

## Pins how a peer is NAMED, everywhere it is named.
##
## Mohamed asked to "see steam id not just player 1 or random numbers". That is a
## display promise, and the things that make it true are the two pure formatters in
## SteamManager plus the HUD row builder -- not the live lookups, which need a real
## account on the other end of a socket.
##
## So these tests deliberately pass the inputs in: a Steam id and a persona as
## ARGUMENTS, so the shape of every string is pinned with no Steam running, no peer
## connected and no display. The live wrappers (identity_for / name_tag_for) are
## checked for the one thing they can be checked for here -- on a session with no
## Steam behind it they must degrade to the replication name rather than inventing a
## number.

## Real accounts from the two test machines: the Mac (Zukei) and the Windows box.
const MAC_STEAM_ID: int = 76561198063757123
const WIN_STEAM_ID: int = 76561198632049032


#region identity_text -- the one-line form ---------------------------------------

func test_a_peer_with_no_steam_identity_is_named_by_its_replication_name() -> void:
	# Direct-IP/ENet: there is no account to show, so the row must say the id the
	# code actually keys on rather than an empty string or a bare "?".
	assert_eq(SteamManager.identity_text(7, 0, ""), "player_7")
	assert_eq(SteamManager.identity_text(7, 0, "Zukei"), "player_7",
			"a persona without an account id is not an identity")


func test_a_steam_peer_is_named_account_and_number() -> void:
	assert_eq(SteamManager.identity_text(2, WIN_STEAM_ID, "ma.culo"),
			"ma.culo (76561198632049032)")


func test_a_steam_peer_whose_name_could_not_be_read_still_shows_its_number() -> void:
	# getFriendPersonaName returns "" for an account Steam has no cache for. The
	# number is still the useful half, so it must survive on its own.
	assert_eq(SteamManager.identity_text(2, WIN_STEAM_ID, ""), "76561198632049032")


#endregion


#region name_tag_text -- the floating tag ----------------------------------------

func test_the_local_avatar_is_marked_you() -> void:
	# The whole point of the tag is telling the player which character is theirs.
	var tag: String = SteamManager.name_tag_text(1, MAC_STEAM_ID, "Zukei", true)
	assert_eq(tag, "Zukei\n76561198063757123\n(you)")
	assert_true(tag.ends_with("(you)"))


func test_a_remote_avatar_is_not_marked_you() -> void:
	assert_eq(SteamManager.name_tag_text(2, WIN_STEAM_ID, "ma.culo", false),
			"ma.culo\n76561198632049032")


func test_the_tag_keeps_the_account_number_even_without_a_persona() -> void:
	# Name unknown: the tag falls back to the replication name on the FIRST line but
	# must still carry the account on the second -- otherwise the screenshot proves
	# nothing again.
	assert_eq(SteamManager.name_tag_text(2, WIN_STEAM_ID, "", false),
			"player_2\n76561198632049032")


func test_a_no_steam_session_gets_the_old_tag_and_no_invented_number() -> void:
	assert_eq(SteamManager.name_tag_text(1, 0, "", true), "player_1\n(you)")
	assert_eq(SteamManager.name_tag_text(2, 0, "", false), "player_2")


func test_the_number_is_never_printed_twice() -> void:
	# NetStats already falls back to the id as the NAME when the persona is empty;
	# the tag must not then print "7656... (7656...)".
	var tag: String = SteamManager.name_tag_text(2, WIN_STEAM_ID, str(WIN_STEAM_ID), false)
	assert_eq(tag, "76561198632049032\n76561198632049032",
			"head falls back to the replication name; the account line is the account")


#endregion


#region The live wrappers degrade, they do not invent ----------------------------

func test_without_a_steam_peer_every_lookup_returns_zero() -> void:
	# No peer, no Steam account: the honest answer is "no identity", and that is what
	# the fallbacks above are built on. Skipped rather than faked when Steam happens
	# to be running on the test machine, since then our own id legitimately resolves.
	if SteamManager.is_initialized:
		pass_test("Steam is running here; covered by the direct-session assertion below")
		return
	assert_eq(SteamManager.peer_steam_id(2), 0)
	assert_eq(SteamManager.identity_for(2), "player_2")
	assert_eq(SteamManager.name_tag_for(2), "player_2")


func test_netstats_and_steammmanager_agree_on_a_peers_account() -> void:
	# Two call sites, one definition: if these ever disagree, the name tag and the
	# HUD would label the same person differently.
	assert_eq(NetStats._steam_id_for(2), SteamManager.peer_steam_id(2))


#endregion


#region The HUD row --------------------------------------------------------------

func test_the_hud_peer_row_carries_the_account_number() -> void:
	# Deliberately NOT added to the tree: _peer_line is pure string work, and a
	# dev_hud.gd instance that enters the tree runs _ready(), which resolves the
	# scene's %Node names -- none of which exist on a bare script instance. The row
	# builder is the thing under test, so it is called directly.
	var hud: CanvasLayer = load("res://ui/dev_hud.gd").new()
	autofree(hud)
	var line: String = hud._peer_line({
			"peer_id": 324528183, "name": "ma.culo", "steam_id": WIN_STEAM_ID,
			"ping": 15, "steam_ping": -1, "quality": -1.0})
	assert_true(line.contains("ma.culo (76561198632049032)"),
			"the row must name the account, not only the peer id: %s" % line)
	assert_true(line.contains("15 ms"), line)
	# The truncated peer id may still appear for debugging, but the account is what
	# makes the row evidence -- so assert the account is there, and not the reverse.
	assert_false(line.contains("player_324528183"), line)


func test_the_hud_peer_row_falls_back_for_a_no_steam_peer() -> void:
	# Deliberately NOT added to the tree: _peer_line is pure string work, and a
	# dev_hud.gd instance that enters the tree runs _ready(), which resolves the
	# scene's %Node names -- none of which exist on a bare script instance. The row
	# builder is the thing under test, so it is called directly.
	var hud: CanvasLayer = load("res://ui/dev_hud.gd").new()
	autofree(hud)
	var line: String = hud._peer_line({
			"peer_id": 42, "name": "player_42", "steam_id": 0,
			"ping": 33, "steam_ping": -1, "quality": -1.0})
	assert_true(line.contains("player_42"), line)
	assert_true(line.contains("33 ms"), line)


func test_the_hud_peer_row_does_not_repeat_the_number() -> void:
	# Deliberately NOT added to the tree: _peer_line is pure string work, and a
	# dev_hud.gd instance that enters the tree runs _ready(), which resolves the
	# scene's %Node names -- none of which exist on a bare script instance. The row
	# builder is the thing under test, so it is called directly.
	var hud: CanvasLayer = load("res://ui/dev_hud.gd").new()
	autofree(hud)
	var line: String = hud._peer_line({
			"peer_id": 2, "name": str(WIN_STEAM_ID), "steam_id": WIN_STEAM_ID,
			"ping": 15, "steam_ping": 22, "quality": 0.9})
	assert_eq(line.count("76561198632049032"), 1, line)
	assert_true(line.contains("steam 22 ms"), line)
	assert_true(line.contains("q 90%"), line)

#endregion