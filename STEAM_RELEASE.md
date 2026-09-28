# Shipping this as a Steam private alpha

Two halves. The **build half is done** and tested; the **Steam half needs you**,
because it needs your identity, your Steam account, and your sign-off - I cannot
create a Steamworks account or accept Valve's agreements on your behalf.

You do the Steam half **once**. After that, pushing an update is one command.

---

## 1. What the build already does (so you know what you are getting)

| Thing | Where | State |
| --- | --- | --- |
| Talks to **your** App ID, not a hardcoded one | `steam_appid.txt`, or `--appid=N` | done |
| **Friends-only sessions** once it is your app | `NetworkManager.lobby_visibility` | done, tested |
| **Invite friends** from inside the game | Dev HUD → "Invite friends" | done |
| Steam's own **"Join Game"** in the friends list | rich presence `connect` key | done |
| Joining a friend goes **straight into the world** | `NetworkManager.join_invited` | done, tested |
| Join by **lobby id**, for when invites are not working | start screen → Join | already existed |
| Everyone's build identity is **visible and compared** | startup log, lobby data | already existed |
| The App ID **ships in step with the repo** | `tools/release.sh` | done |

Verified on this machine: `[SteamManager] OK | ... | App ID 480 (DEV: Spacewar)`,
`[NetworkManager] Lobby visibility: public (dev App ID 480)`.

**The one thing that has never been tested by me is a real App ID**, because I do
not have one. Everything above is written and unit-tested against the dev app; the
first run with your App ID is the test.

---

## 2. Your Steam side (once)

1. **Steamworks partner account.** Sign up at
   <https://partner.steamgames.com/>, complete Valve's registration process for your
   account. This is the step I cannot do and the one that gates everything else.
2. **Create the app** in Steamworks → *Create New App*. It gives you an **App ID**
   (a small number, nothing like 480). Write it down.
3. **Pick the alpha shape.** Both are supported by this build; they differ in how a
   friend gets access:

   | Shape | How a friend gets in | What you must do |
   | --- | --- | --- |
   | **Steam Playtest** (cleanest for alpha) | They open the Playtest page and request access; you approve. No store page needed, they do not need to own anything. | Enable Playtest for the app; it gets its **own App ID** - use *that* one in `steam_appid.txt`. |
   | **Unreleased app + password branch** | You hand them a password; they redeem it under *Steam → Activate a Product*, then pick the beta branch in the game's properties. | Set up the depot and a password-protected beta branch (step 5). |

   Playtest is less to configure and is designed exactly for "friends play before
   it is real". Pick it unless you specifically want the branch workflow.

4. **Rich presence for the "Join Game" line (optional, 2 minutes).** The *Join Game*
   button itself comes from the `connect` rich-presence key and works with no
   configuration. To make the *text* next to your name say something civilised
   ("In a 'world'") instead of blank, add a rich presence localization entry in
   Steamworks: *App Admin → Localization → (language) →* add the key **`status`** with
   the token value `#Status`, then the token **`Status`** → `{SteamMMO}`-style text.
   Skipping this changes nothing about joining.

5. **Depots and a branch, if you chose the branch shape.** In Steamworks → *SteamPipe →
   Depots*, add one Windows depot, set the launch option to `SteamMMO.exe`. Then
   create a branch (e.g. `alpha`, optionally password-protected) and set the launch
   option to also allow that branch.

---

## 3. Pointing the build at your App ID

One file, one line, no code change anywhere:

    echo YOUR_APP_ID > steam_appid.txt

Anything already running against 480 is unaffected; anything that builds afterwards
is your app. `--appid=N` overrides it for a single run. The startup log tells you
which one won:

    [SteamManager] OK | GodotSteam v4.22.1 | App ID 1234567 | user 'Zukei' (76561198...)

With your own App ID, the same log line stops saying `(DEV: Spacewar)` and the lobby
visibility default flips to **friends-only** automatically - that is the rule in
`_resolve_lobby_visibility()`: on Valve's shared test app, sessions are already
visible to every Steam user, so hiding ours would only hide them from us.

---

## 4. Building a release

    tools/release.sh "what changed"        # bumps VERSION, exports, zips, records

It also copies `steam_appid.txt` into the build and warns you in red when it is
still 480. Output: `dist/SteamMMO_<version>.zip` and, if Drive is mounted, a copy in
`ver_control/`.

---

## 5. Pushing that build to Steam

`steamcmd` does the upload. First install/log in once, **interactively** - this is
your account and (if you have 2FA on) your approval prompt:

    steamcmd +login YOUR_STEAM_LOGIN
    # ... type the password and the Steam Guard code, then: quit

Then, with `tools/steampipe.sh` (in this repo; **untested against real Steam** - I have
no app to test it against):

    cp tools/steam_alpha.env.example tools/steam_alpha.env   # fill in: app id, depot id, your login
    tools/steampipe.sh --preview                             # prints what it would do, uploads nothing
    tools/steampipe.sh                                       # uploads to the 'alpha' branch

Under the hood it is SteamPipe: `steamcmd +run_app_build` with two generated scripts -
a depot (which files go where) and an app build (which depots, which branch). It
writes them fresh from your config each run, so they cannot drift from it. That
config file is gitignored on purpose: it names your account and your app's ids.

The parts of it I **could** test, I did: it refuses to upload a build whose shipped
App ID does not match the app it is targeting (`ships App ID '480' but this config
targets '999999'` - a build running as Spacewar must never be pushed to a real app),
and `--preview` generates both scripts and prints the exact command without touching
Steam.

**Every push after that is the same two commands:**

    tools/release.sh "note"
    tools/steampipe.sh

A friend who already has the alpha gets the new build the next time Steam checks
(immediately if they relaunch). That is the "update in one place" you wanted.

---

## 6. What is still true, and worth telling your friends

- **The host is a player, not a server.** Whoever presses PLAY first becomes the
  host; if they quit, that session ends for everyone. Fine for an alpha with a few
  friends, not for a persistent world.
- **Everyone must be on the same protocol.** Mismatched builds print
  `BUILD MISMATCH` on join instead of failing mysteriously later. Version strings
  may differ; protocol must not. Current: protocol **3**.
- **The alpha is a real multiplayer POC, not a finished game.** One world, one
  dungeon, a quest loop, wolves that fight back. That is what it is.
- **480 is for local testing only.** Never hand out a build whose log says
  `(DEV: Spacewar)` - all of Steam shares that app.