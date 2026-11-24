#Requires AutoHotkey v2.0
#SingleInstance Force
; Not started as administrator (no "Run as administrator" in the right-click menu, or a double click)?
; Relaunch itself elevated. Windows shows one "Do you want to allow this app" prompt, answer Yes.
if !A_IsAdmin {
    try {
        Run('*RunAs "' A_AhkPath '" "' A_ScriptFullPath '"')
        ExitApp()
    } catch {
        MsgBox("This macro needs administrator rights and Windows did not allow it.`n`nRight click the file, choose Show more options, then Run as administrator.", "THY HOZ's AOTR MACRO")
        ExitApp()
    }
}
CoordMode "Pixel", "Screen"
CoordMode "Mouse", "Screen"
CoordMode "ToolTip", "Screen"     ; tooltips stay put on the screen instead of following the active window
ListLines(false)                                   ; no line logging: slightly faster
try ProcessSetPriority("High")                     ; the OBJECTIVES watcher keeps up even while Roblox is loading
DllCall("winmm\timeBeginPeriod", "UInt", 1)        ; 1 ms timer resolution, so Sleep 1 really is ~1 ms
OnExit(ReleaseTimer)
; ---- updates: the script asks this page for the newest version number (version.txt). A higher number = a new release. ----
ScriptVersion := "5.8"                             ; this script is UPDATE 5.1 (a number like 5.1 or 6; version.txt on GitHub holds the newest one)
UpdateVerUrl := "https://raw.githubusercontent.com/THY-HOZ/THY-HOZ-S-AOTR-MACRO/refs/heads/main/version.txt"
UpdateScriptUrl := "https://raw.githubusercontent.com/THY-HOZ/THY-HOZ-S-AOTR-MACRO/refs/heads/main/UPD5_AOTR_Macro.ahk"

;  BUILT-IN MACRO: F10 records your keys, F8 plays / stops them (loops). Presets by name (Outskirts, Female Titan ...).
;  Switch on "Built-in macro (no TinyTask)" in the app; TinyTask is then not needed.
; =====================================================================
;  WINDOWED BUILD: Roblox runs in its smallest window (about 800x600, less GPU over RDP). This script pins that window to
;  one spot and a control window (the app) docks next to it. Settings and the webhook are typed into the app window.
;  Windowed mode covers: win / fail detection + RETRY + F8, drops, Discord reports, loading and HUD detection, disconnect
;  alert, automatic rejoin (Roblox home > search > AOTR > PLAY ... modifiers > START), stuck recovery, error pop-up (always Leave).
;  Untick "Windowed mode" in the app to get the old fullscreen 1920x1080 behaviour back.
;
;  When the MISSION FAILED screen appears it presses F8 twice (stop, then
;  start again), ONE time only. It won't trigger again until that screen
;  has gone away.
;
;  Every time it presses F8 it shows a tooltip in the top-left corner
;  and writes a line to mission_failed_f8.log, so you can tell whether
;  this script is what stopped your TinyTask.
;
;  Optional helpers:
;   F6 = hover the RETRY button on the end screen and press F6 to calibrate
;   F5 = press F5 to test how much of the end screen is detected
;   F1 = restart this script from scratch (resets everything)
;   Ctrl+Shift+F9 = send a test message + screenshot to your Discord webhook
;   F4 = tell me which screen the script thinks it sees (home, game page, slots, menu, lobby ...)
;   F7 = (optional) hover the LEAVE button of a Roblox error pop-up and press F7 to save its position.
;        Without it the script finds the pop-up's buttons by itself and clicks Leave (back to the Roblox home)
;   Ctrl+Shift+F8 = turn the automatic RETRY + restart on the win / fail screen on or off (remembered)
;   F3 = PAUSE / RESUME the whole script: stops the main macro, keeps a small PAUSED tooltip, nothing is clicked or pressed
;   F9 = SETUP CHECK: lists everything that is wrong with the setup (admin, resolution, Roblox, TinyTask, webhook, files)
;   Ctrl+Shift+F6 = choose which modifiers the rejoin ticks (or none are touched)
;   Ctrl+Shift+F7 = rejoin through the menu's PLAY button instead of CODES + VIP server (other servers), on/off (remembered)
;   Ctrl+Shift+F10 = run the automatic rejoin right now, from whatever screen is showing
;
;  Extras (all optional, set in SETTINGS below):
;   - Screenshot of the screen on every mission fail, saved in the "shots" folder
;   - Discord webhook: fail messages with the screenshot attached
;   - Disconnect alert that @pings you when Roblox closes/crashes, or when ANY
;     Roblox error pop-up appears (Disconnected, Connection Failed, kicked...)
;   - Auto-reconnect: after pinging you it rejoins BY ITSELF: it reads the screen and clicks through
;     the Roblox home, the game page, slot A, the menu, the lobby and the mission setup
;     (modifiers), then presses F8. The old F12 "disconnected" TinyTask macro is gone.
;   - Tells MISSION FAILED and MISSION COMPLETED apart, counts both
;   - Discord "mission report" embed: session record, win rate, session time, round
;     time, streaks, rounds/hour, drops by rarity, rare-drop totals, disconnect and
;     stuck counters, plus the screenshot
;   - @pings you when the drops include a Mythic (red) or Divine (blue-purple
;     gradient) item
;   - Stuck mission: no end screen for StuckMinutes -> Esc, L, Enter (leave the game),
;     then rejoins by itself. Ctrl+Shift+F11 turns this watcher on/off (turning it on restarts its timer).
;     The timer is paused while you are in the AOTR lobby (top menu bar detected).
;   - Reads the two TinyTask windows (title = playing or idle), so F8 is only pressed when
;     needed: the main macro is really OFF while rejoining and really ON afterwards.
;   - Rejoin supervision: if a rejoin attempt gets stuck, it waits (backoff) and tries again.
;   - Fast end screen: F8 restart first, screenshot / drops / Discord run separately.
;
;  Run as administrator.
; =====================================================================

; ------------------------------ SETTINGS -----------------------------
CheckEveryMs     := 10      ; how often to look at the screen (smaller = notices the end screen sooner)
RestartDelayMs   := 100    ; pause between the stop (1st F8) and the start (2nd F8)
RearmAfterGoneMs := 2000    ; screen must be gone this long before it can trigger again

; ---- Discord / screenshots (all optional) ----
WebhookUrl       := ""      ; paste your Discord webhook URL between the quotes. KEEP IT PRIVATE.
DiscordUserId    := ""      ; your Discord user ID, so alerts can @ping you
BotName          := "AOTR Macro"
TakeScreenshots  := true    ; save a screenshot to the "shots" folder on every mission fail
MaxShots         := 50      ; keep only the newest N screenshots (0 = never delete)
PingOnFail       := false   ; true = also @ping you on every mission fail

; ---- Disconnect alerts (always @ping you) ----
WatchDisconnect     := true
DisconnectCheckMs   := 2000
DisconnectRepeatMin := 10   ; re-ping every N minutes while still disconnected (0 = only once)

; ---- Auto-reconnect (rejoins by itself, see AUTOMATIC REJOIN near the end of this file) ----
AutoReconnect        := true
StopMainFirst        := true    ; only used if TinyTask's window can't be read: then one blind F8 stops the main macro
ReconnectMaxTries    := 3       ; attempts per disconnect before it gives up and only pings you

; ---- Mission result / rare drops ----
ItemScanDelayMs := 500     ; wait after the end screen appears before reading the drops
PingOnMythic    := true     ; @ping you when a Mythic (red bar) item drops
PingOnDivine    := true     ; @ping you when a Divine (pink-purple-blue gradient bar) item drops
PingOnScroll     := false    ; @ping you when a Scroll drops
PingOnDisconnect := true     ; @ping you when the account is disconnected
PingOnStuck      := true     ; @ping you when a mission looks stuck
PingOnGaveUp     := true     ; @ping you when the macro could not rejoin and stopped
StatusMsgs       := true     ; also post the short "back in / reconnected" messages

; ---- Stuck mission (e.g. a titan that can't reach you, so the mission never ends) ----
StuckEnabled          := true
StuckMinutes          := 3     ; no end screen for this long = stuck
StuckLeaveWaitSeconds := 8     ; wait after Esc, L, Enter before pressing the reconnect key
PauseStuckInLobby     := true  ; the stuck timer does not run while you're in the AOTR lobby

; ---- TinyTask control (so the main macro is never in the wrong state) ----
MainMacroName := "outskirts"      ; part of the main macro's file name, as shown in its TinyTask window
ConfirmMs     := 350             ; the end screen must still be there after this long (3 looks) before acting. 80 was too short:
                                  ; the Colossal Titan transformation / nuke flash briefly looks like an end screen. 350 gave no false wins.
; Private server code / link for people who JOIN a private server instead of owning a VIP one: put it between the
; quotes and it is pasted into the VIP SERVERS box. Leave it empty ("") to keep whatever code is already in that box.
PrivateServerCode := ""

; ---- Rejoin supervision (after a disconnect or a stuck mission) ----
RejoinMaxTries       := 10         ; automatic rejoin attempts before giving up
RejoinBackoffSeconds := 5         ; wait before a retry (the same every time)
RejoinTimeoutSeconds := 600       ; longest one automatic rejoin attempt may take

; ---- Automatic rejoin ----
ModifiersWanted := ["ODDBALL", "INJURY PRONE", "CHRONIC INJURIES", "FOG"]   ; boxes to tick (these four are supported)
GamePlaceId     := "13379208636"  ; optional: the number in the AOTR page address (roblox.com/games/NUMBER/...). With it, a
                              ; closed Roblox is started again by itself, and an error pop-up can be closed that way
; ---------------------------------------------------------------------

IniFile := A_ScriptDir "\mission_failed_f8.ini"
; Values typed into the app window (saved in the ini file) replace the ones in SETTINGS above.
WebhookUrl    := IniRead(IniFile, "app", "WebhookUrl", WebhookUrl)
DiscordUserId := IniRead(IniFile, "app", "DiscordUserId", DiscordUserId)
MainMacroName := IniRead(IniFile, "app", "MainMacroName", MainMacroName)
try ConfirmMs := Integer(IniRead(IniFile, "app", "ConfirmMs", ConfirmMs))   ; a value saved in Settings always wins (80 is fine too)
PrivateServerCode := IniRead(IniFile, "app", "PrivateServerCode", PrivateServerCode)
try StuckMinutes := Integer(IniRead(IniFile, "app", "StuckMinutes", StuckMinutes))
if (StuckMinutes < 1)
    StuckMinutes := 3
StuckSecs := StuckMinutes * 60                 ; the exact limit in seconds (minutes + seconds in Settings)
try StuckSecs := Integer(IniRead(IniFile, "app", "StuckSecs", StuckSecs))
if (StuckSecs < 20)
    StuckSecs := 180
; Which events @ping you (chosen in Settings > Ping options)
PingOnFail       := (IniRead(IniFile, "ping", "Fail", PingOnFail ? "1" : "0") = "1")
PingOnMythic     := (IniRead(IniFile, "ping", "Mythic", PingOnMythic ? "1" : "0") = "1")
PingOnDivine     := (IniRead(IniFile, "ping", "Divine", PingOnDivine ? "1" : "0") = "1")
PingOnScroll     := (IniRead(IniFile, "ping", "Scroll", PingOnScroll ? "1" : "0") = "1")
PingOnDisconnect := (IniRead(IniFile, "ping", "Disconnect", PingOnDisconnect ? "1" : "0") = "1")
PingOnStuck      := (IniRead(IniFile, "ping", "Stuck", PingOnStuck ? "1" : "0") = "1")
PingOnGaveUp     := (IniRead(IniFile, "ping", "GaveUp", PingOnGaveUp ? "1" : "0") = "1")
StatusMsgs       := (IniRead(IniFile, "ping", "Status", StatusMsgs ? "1" : "0") = "1")
; Auto start on the win / fail screen: the script clicks RETRY itself and starts the main macro. Toggle: Ctrl+Shift+F8.
AutoStartEnd := (IniRead(IniFile, "opts", "AutoStartEnd", "1") = "1")
lastRetryClick := 0
; Rejoin through the menu's PLAY button (public servers) instead of CODES + VIP server. Toggle: Ctrl+Shift+F7.
; Rejoin by the normal PLAY button (default) or join a VIP / private server ("Join VIP server" switch, Ctrl+Shift+F7).
UseVip := (IniRead(IniFile, "opts", "UseVip", "0") = "1")
FritzRevive := (IniRead(IniFile, "opts", "FritzRevive", "0") = "1")   ; Fritz has revives: "YOU DIED" -> the macro restarts 1.5 s later
HealInjuries := (IniRead(IniFile, "opts", "HealInjuries", "1") = "1")   ; end screen with injuries: click HEAL until none are left, then RETRY
DuoRaid := (IniRead(IniFile, "opts", "DuoRaid", "0") = "1")      ; duo raids: wait for a 2nd player, host / join, retry only while (0/2) or (1/2)
DuoHost := (IniRead(IniFile, "opts", "DuoHost", "1") = "1")      ; ON = you host, OFF = you join the topmost lobby
ColossalRole := (IniRead(IniFile, "opts", "ColossalRole", "Beast") = "Colossal") ? "Colossal" : "Beast"   ; Colossal raid roles (no function yet)
DuoClicks := 0
LastBorder := ""
LeftBase := 0
LeftDelta := 0
KeyChest := (IniRead(IniFile, "opts", "KeyChest", "1") = "1")   ; raids: also open the second (key) chest when there are keys
RaidWaiting := false        ; true while the script waits for the objectives panel to start the macro
LastRoundRetreat := false   ; the last end screen was RETREAT COMPLETED (counts as a fail)
ChestLastSeen := 0          ; raid chests: when the chests screen was last seen
ChestLeftN := 0             ; how many times the left / key chest were pressed in this raid
ChestRightN := 0
ChestClickT := 0
PlayInsteadOfVip := !UseVip
GuideGui := 0
GuideList := 0
GuideText := 0
; Built-in macro player (no TinyTask): see the BUILT-IN MACRO PLAYER section.
BuiltIn := (IniRead(IniFile, "opts", "BuiltIn", "0") = "1")
HelpMap := Map()
QsGui := ""
QsRows := []
MacroActive := IniRead(IniFile, "macros", "Active", "")
; Missions and raids. [name, kind, available]. An entry with false says "Coming Soon" in the picker.
MapList := [["Outskirts", "Normal mission", true], ["Utgard", "Normal mission", true], ["Shiganshina", "Normal mission", true], ["Forest", "Normal mission", true], ["Attack Titan", "Raid", true], ["Female Titan", "Raid", true], ["Colossal Titan", "Raid", false]]
CurMap := IniRead(IniFile, "maps", "Active", "Outskirts")
if !MapAvail(CurMap)
    CurMap := "Outskirts"
MapGui := 0
MapStatus := 0
if (MapMacroGet(CurMap) != "")             ; every mission / raid remembers its own macro
    MacroActive := MapMacroGet(CurMap)
else if (MacroActive != "")
    try IniWrite(MacroActive, IniFile, "maps", "Macro_" . CurMap)
MacroLoaded := ""
MacroPlaying := false
ForceLink := false                  ; true for the one rejoin started by hand ("Rejoin now"): its first step is always the game link
MacroEv := []
MacroDur := 0
MacroLoop := true
MacroIdx := 1
MacroT0 := 0
MacroHeld := Map()
Recording := false
RecIH := 0
RecEv := []
RecHeld := Map()
RecT0 := 0
RecStart := 0
RecName := ""
MgrGui := 0
MgrList := 0
; Modifiers: chosen with Ctrl+Shift+F6 (saved in the ini file); ModifiersWanted above is only the default.
ModExact := false                                                  ; (the "untick every other modifier" option was removed)
ModSkip  := (IniRead(IniFile, "opts", "ModSkip", "0") = "1")       ; don't open the modifiers screen at all

ScriptPaused := false
pauseMsg := ""
_m := IniRead(IniFile, "opts", "Modifiers", "")
if (_m = "NONE")
    ModifiersWanted := []
else if (_m != "")
    ModifiersWanted := StrSplit(_m, "|")
ModDefault := ModifiersWanted.Clone()       ; used for a mission / raid that has no modifiers saved yet
ModSkipDefault := ModSkip
ModLoadFor(CurMap)
startWaiting := false
LogFile := A_ScriptDir "\mission_failed_f8.log"
RetryX  := Integer(IniRead(IniFile, "pos", "RetryX", 1167))   ; defaults for 1920x1080
RetryY  := Integer(IniRead(IniFile, "pos", "RetryY", 846))

; Points checked on the LEAVE and MODIFIERS buttons, as [dx, dy] from the RETRY button.
; At least MinGold of them must be bright gold at the same time, for 0.5 s in a row.
Points := [[-490, -5], [-490, 5], [-340, 0], [-285, -5], [-285, 5], [-125, 0]]
MinGold := 5
; Screen copy mode for the many small looks (skip box, end screen, objectives ...). Plain SRCCOPY (0x00CC0020): no mouse flicker.
; (0x40CC0020 = with CAPTUREBLT: also copies see-through windows, but makes the mouse cursor flicker on every copy.)
; If a screen look ever sees nothing at all on your PC, set this to 0x40CC0020.
CapRop := 0x00CC0020

fired := false
goneSince := 0
SnapCur := 0                ; when set to a snapshot, the pixel reads below use it instead of the live screen

; state for the Discord / screenshot / disconnect features
ShotDir      := A_ScriptDir "\shots"
RespFile     := A_ScriptDir "\webhook_response.txt"
ErrFile      := A_ScriptDir "\webhook_error.txt"
failCount    := 0
runStart     := 0           ; when the current run's timer started (RETRY pressed / lobby START pressed); 0 = not running
seenRoblox   := false
dcActive     := false
dcLastAlert  := 0
dcCount      := 0

; state for the auto-reconnect
busyReconnect    := false
reconnectTries   := 0
nextReconnectTry := 0

; state for round results and the stuck-mission timer
lastRoundTick := 0          ; 0 = stuck watcher not armed yet (arms on the first end screen)
winCount      := 0

; session stats for the Discord mission report
sessionStart   := A_TickCount
streakKind     := ""
streakLen      := 0
bestWinStreak  := 0
mythicTotal    := 0
scrollTotal    := 0
ScrollRef      := 0        ; the scroll icon template, unpacked from ScrollRefHex on first use
; The scroll icon (16x16 samples, RGB hex), cut from a real end screen at 1920x1080.
ScrollRefHex := "1817171817171817171817171817171817171817171817171817171817171817171817171817171817171E1C17181717171616171616171616171616171616171616171616171616171616171616171616171616171616636557AEAE95917E4A1716161716161716161716161716161716161716161716161716161716161716161716164D5044AFAF9CA99D6B643A1216151517161616151517161616151517161616151517161616151517161616151545483AAEAE98AAA16D5D320B522A0B161515161515161515161515161515161515161515161515161515161515313229AAAA96A698655F330E522B0B221911161515161515161515161515161515161515161515161515161515262620AFAF9DA79C6A5E320D4B26091D16101615151514141514141514141514141514141514141514141514141B1B17ACAC9CABA374592A0950290A1713111514141514141615171615171615171615171615171615171615171816169F9E8CA79D6E5D2E0B4B2509161313161517161517161517161619161619161619161619161619161619181617A0663D9D52305E331145220915141616161916161916161916161917171A17171A17171A17171A17171A191719A15E36AA582E3E09041F100916161917171A17171A17171A17171A17171A16171C16171C16171C16171C1C1D1E9F9B8998321834040224100D15151A16171C16171C16171C16171C16171C16171C17181E17181E17181E272827ACAD9EABA2775B3012170C0816161C17181E17181E17181E17181E17181E17181E17181E171820171820323330AFAFA0ADA77D653712401C0716171E171820171820171820171820171820171820171820171820181A23484A43AAAA9CACA57A63341048210616171E181A23181A23181A23181A23181A23181A23181A23181A23181A234F514BAEAE9FACA4776A3E17471E0516161D171924171924171924171924171924171924171924171924171924171924AFAFA0AEA97D6D4218471E0517161D181B26181B26181B26171A26181B26181B26181B26171A26181B26181B26181B26"
divineTotal    := 0
roundMsSum     := 0
roundIntervals := 0
dcEvents       := 0
stuckEvents    := 0

; TinyTask windows (found from their idle titles; remembered in the ini file)
mainHwnd := 0
try mainHwnd := Integer(IniRead(IniFile, "tinytask", "mainHwnd", 0))   ; (a hand-edited ini can not crash the start)
ttLastScan := 0

; Roblox's error pop-ups (Disconnected 277, Connection Failed 279, kicked, ...) all use the same
; dark-gray box in the middle of the screen. These points are inside it (dx, dy from the screen
; center) and must ALL be that exact gray.
DialogPoints := [[-185, -20], [-185, 20], [-175, 0], [175, 0], [185, -20], [185, 20], [-190, -60], [190, -60], [-190, 70], [190, 70]]

; state for the automatic rejoin
LeaveX := 0
try LeaveX := Integer(IniRead(IniFile, "pos", "LeaveX", 0))   ; (a hand-edited ini can not crash the start)      ; Leave button of the Roblox error pop-up (F7)
LeaveY := 0
try LeaveY := Integer(IniRead(IniFile, "pos", "LeaveY", 0))   ; (a hand-edited ini can not crash the start)
HomeTileX  := 0
HomeTileY  := 0
TileImg    := A_ScriptDir "\rejoin_assets\aotr_tile.png"
IconImg    := A_ScriptDir "\rejoin_assets\aotr_icon.png"
; pixels of the "OUTSKIRTS" title (gold text / not text) used to confirm the map really is selected
TitlePos := ParsePts("634,332;634,333;634,339;634,340;666,324;667,328;667,331;667,335;667,337;667,338;684,318;684,320;709,315;710,316;710,321;735,315;736,315;736,316;736,317;736,318;736,320;736,322;736,325;736,331;736,337;736,338;736,339;736,340;736,341;736,345;736,346;760,322;761,321;761,322;761,324;819,352;836,316;836,317;836,321;836,345;836,346;836,352;837,315;837,316;856,315;856,351;857,315;857,316;857,318;857,349;857,350;857,352;867,335;878,320;878,327;878,352;879,324;902,315;902,327;902,329;902,331;902,333;902,337;902,338;902,340;902,344;902,349;902,350;903,315;927,324")
TitleNeg := ParsePts("606,350;609,334;612,322;613,304;616,355;618,305;618,357;622,326;625,313;628,353;634,305;642,362;646,329;659,303;662,307;670,352;677,342;690,361;697,336;713,307;719,333;720,363;721,344;726,352;731,303;744,339;748,363;750,329;756,338;788,328;789,323;790,360;793,364;805,302;810,306;819,305;834,302;857,360;862,301;864,360;866,363;886,342;890,328;890,362;891,359;904,302;913,325;913,338;913,345;915,364;920,361;922,342;937,323;937,365;949,361;953,328;954,323;957,339;962,332;963,342;966,302;966,356;967,324;969,300;972,340;973,318;975,335;975,364;976,352;979,329")
; The OBJECTIVES header (top right) has a gold border. These points sit on it (1920x1080), same as before.
HudPts := [[1700, 170], [1800, 170], [1900, 170], [1700, 215], [1800, 215], [1900, 215]]
fastStartResult := ""       ; set by WaitMatchReady when it pressed F8 the instant OBJECTIVES appeared
; ===================== WINDOWED MODE + APP WINDOW =====================
; WinMode: Roblox runs in its smallest window (about 800x600). The script pins that window to one spot on the screen
; and every position below is measured from the window's top-left corner (WX, WY).
WinMode := (IniRead(IniFile, "opts", "WinMode", "1") = "1")
WX := 0
WY := 0
WW := 0
WH := 0
LatchX := -1
try LatchX := Integer(IniRead(IniFile, "win", "X", -1))   ; (a hand-edited ini can not crash the start)
LatchY := -1
try LatchY := Integer(IniRead(IniFile, "win", "Y", -1))   ; (a hand-edited ini can not crash the start)
latchMsg := "Roblox window not found"
Points1080 := Points
HudPts1080 := HudPts
RetryX1080 := RetryX
RetryY1080 := RetryY
AutoReconnectCfg := AutoReconnect
StuckCfg := StuckEnabled
AppGui := 0
LeftGui := 0
TopGui := 0
BotGui := 0
SetGui := 0
BtnMap := Map()
Toggles := Map()
AppCtl := Map()
if WinMode
    try LatchRoblox(false)
ApplyProfile()
try BuildApp()
SetTimer(AppTick, 500)

try EnsureAssets()

try TTDiscover()
SetTimer(Watch, CheckEveryMs)
if WatchDisconnect
    SetTimer(DisconnectWatch, DisconnectCheckMs)
SetTimer(StuckWatch, 5000)
SetTimer(SkipTick, 80)
SetTimer(ChestTick, 150)         ; (speeds itself up to 60 ms while the chests screen is showing)
SetTimer(InjuryTick, 300)
SetTimer(DeathTick, 250)
SetTimer(PromptTick, 600)
SetTimer(DpiWarn, -3000)
SetTimer(UpdateAuto, -8000)         ; a quiet look for a new release a few seconds after the start

F6::Calibrate()
F5::TestHere()
^+F9::WebhookTest()
^+F11::ToggleStuck()
^+F8::ToggleAutoStart()
^+F7::TogglePlayMode()
^+F6::ModPicker()
F3::TogglePause()
F9::SetupCheck()
F1::RestartScript()
F4::ShowScreen()
F7::CalibrateLeave()
^+F10::TestAutoRejoin()
F10::RecordToggle()
F2::OpenGuide()
#HotIf BuiltIn
F8::F8Key()
#HotIf

; ======================= WINDOW LATCH + PROFILE + APP WINDOW =======================
; Visible frame of a window (what a screenshot of the window shows): [x, y, width, height], or 0.
WinBounds(h) {
    rc := Buffer(16, 0)
    if DllCall("dwmapi\DwmGetWindowAttribute", "Ptr", h, "UInt", 9, "Ptr", rc, "UInt", 16)
        return 0
    l := NumGet(rc, 0, "Int")
    t := NumGet(rc, 4, "Int")
    r := NumGet(rc, 8, "Int")
    b := NumGet(rc, 12, "Int")
    return [l, t, r - l, b - t]
}

; Finds the Roblox window, makes it as small as it goes and keeps it at one fixed spot (the first spot it was seen at,
; or the one saved with "Pin window here"). Sets WX, WY, WW, WH. Returns true when the window is windowed and readable.
LatchRoblox(pin := false) {
    global WX, WY, WW, WH, LatchX, LatchY, IniFile, latchMsg
    h := WinExist("ahk_exe RobloxPlayerBeta.exe")
    if !h {
        latchMsg := "Roblox window not found"
        WW := 0
        return false
    }
    mm := 0
    try mm := WinGetMinMax("ahk_id " h)
    if (mm != 0) {
        try WinRestore("ahk_id " h)
        Sleep 250
    }
    b := WinBounds(h)
    if !IsObject(b) {
        latchMsg := "can't read the Roblox window position"
        return false
    }
    if (b[3] >= A_ScreenWidth - 8 && b[4] >= A_ScreenHeight - 60) {
        WW := 0
        latchMsg := "Roblox is fullscreen: press F11 in Roblox to make it a window"
        return false
    }
    if (b[3] > 815 || b[4] > 645) {
        try WinMove(, , 400, 300, "ahk_id " h)
        Sleep 300
        b := WinBounds(h)
        if !IsObject(b)
            return false
    }
    if (pin || LatchX < 0 || LatchY < 0) {
        LatchX := b[1]
        LatchY := b[2]
        try IniWrite(LatchX, IniFile, "win", "X")
        try IniWrite(LatchY, IniFile, "win", "Y")
    } else if ((b[1] != LatchX || b[2] != LatchY) && !GetKeyState("LButton", "P")) {
        ox := 0
        oy := 0
        try WinGetPos(&ox, &oy, , , "ahk_id " h)
        try WinMove(LatchX - (b[1] - ox), LatchY - (b[2] - oy), , , "ahk_id " h)
        Sleep 100
        nb := WinBounds(h)
        if IsObject(nb)
            b := nb
    }
    WX := b[1]
    WY := b[2]
    WW := b[3]
    WH := b[4]
    if (Abs(WW - 801) <= 2 && Abs(WH - 629) <= 2)
        latchMsg := "Window pinned at " WX ", " WY
    else
        latchMsg := "Roblox window is " WW "x" WH ": needs 801x629 (the smallest size)"
    return true
}

; Loads the coordinates for the current mode: the small Roblox window, or fullscreen 1920x1080.
ApplyProfile() {
    global WinMode, WX, WY, Points, HudPts, RetryX, RetryY, Points1080, HudPts1080, RetryX1080, RetryY1080
    global AutoReconnect, StuckEnabled, AutoReconnectCfg, StuckCfg
    if WinMode {
        RetryX := WX + 490
        RetryY := WY + 463
        Points := [[-215, -5], [-150, -5], [-125, -5], [-58, -5], [-35, -5], [35, -5]]
        HudPts := [[WX + 700, WY + 123], [WX + 740, WY + 123], [WX + 780, WY + 123], [WX + 700, WY + 142], [WX + 740, WY + 142], [WX + 780, WY + 142]]
        AutoReconnect := AutoReconnectCfg
        StuckEnabled := StuckCfg
    } else {
        RetryX := RetryX1080
        RetryY := RetryY1080
        Points := Points1080
        HudPts := HudPts1080
        AutoReconnect := AutoReconnectCfg
        StuckEnabled := StuckCfg
    }
}

; What the small-window screen looks like right now (used by the app window and F4). Call it inside WithSnap.
WinScreenName() {
    if (GoldCount() >= MinGold)
    {
        if (RoundKind() = "complete")
            return "MISSION COMPLETED screen"
        return LastRoundRetreat ? "RETREAT COMPLETED screen (a fail)" : "MISSION FAILED screen"
    }
    cz := false
    try cz := IsObject(SnapCur) && ChestsOk(SnapCur)
    if cz
        return "raid CHESTS screen"
    if LoadingPx()
        return "loading screen"
    if HudPx()
        return "in a mission"
    sc := ClassifyWin()
    if (sc = "lobby")
        return "AOTR lobby"
    if (sc != "" && sc != "other")
        return "rejoin screen: " sc
    if InLobby()
        return "AOTR lobby"
    return "other / not recognised"
}

; ===================== BUILT-IN MACRO PLAYER (replaces TinyTask) =====================
; Records the keys you press (F10 starts / stops the recording) and plays them back in a loop (F8 starts / stops).
; Several macros can be saved by name (for example "Outskirts", "Female Titan"); the selected one is played.
; They are stored in the ini file ([macro_<name>] sections). Don't use F1, F3..F10 inside a macro: the script uses them.

NowMs() {
    static f := 0
    c := 0
    if !f
        DllCall("QueryPerformanceFrequency", "Int64*", &f)
    DllCall("QueryPerformanceCounter", "Int64*", &c)
    return c * 1000.0 / f
}

EnsureRobloxFocus() {
    if WinActive("ahk_exe " . RobloxExe())
        return
    try WinActivate("ahk_exe " . RobloxExe())
    try WinWaitActive("ahk_exe " . RobloxExe(), , 1)
}

CleanName(s) {
    s := StrReplace(s, "[", "")
    s := StrReplace(s, "]", "")
    s := StrReplace(s, "=", "")
    s := StrReplace(s, "|", "")
    s := StrReplace(s, ",", "")
    s := Trim(s)
    return SubStr(s, 1, 30)
}

MacroNames() {
    out := []
    s := IniRead(IniFile, "macros", "Names", "")
    for n in StrSplit(s, "|") {
        n := Trim(n)
        if (n != "")
            out.Push(n)
    }
    return out
}

MacroSaveNames(arr) {
    s := ""
    for n in arr
        s .= (s = "" ? "" : "|") . n
    try IniWrite(s, IniFile, "macros", "Names")
}

MacroSetActive(name) {
    global MacroActive, MacroLoaded
    MacroActive := name
    MacroLoaded := ""
    try IniWrite(name, IniFile, "macros", "Active")
    try IniWrite(name, IniFile, "maps", "Macro_" . CurMap)     ; the macro belongs to the selected mission / raid
}

; Writes a macro to the ini file: events are "ms:vk:scancode:1(down)/0(up)", cut into pieces of about 5000 characters.
MacroSave(name, ev, dur, lp) {
    sec := "macro_" . name
    try IniDelete(IniFile, sec)
    chunks := 0
    buf := ""
    for e in ev {
        piece := e[1] . ":" . e[2] . ":" . e[3] . ":" . e[4]
        if (StrLen(buf) + StrLen(piece) + 1 > 5000) {
            chunks += 1
            IniWrite(buf, IniFile, sec, "E" . chunks)
            buf := ""
        }
        buf .= (buf = "" ? "" : ",") . piece
    }
    if (buf != "") {
        chunks += 1
        IniWrite(buf, IniFile, sec, "E" . chunks)
    }
    IniWrite(chunks, IniFile, sec, "Chunks")
    IniWrite(ev.Length, IniFile, sec, "Count")
    IniWrite(Round(dur), IniFile, sec, "Dur")
    IniWrite(lp ? 1 : 0, IniFile, sec, "Loop")
}

; Returns Map("ev", [...], "dur", ms, "loop", true/false) or "" when there is nothing saved under that name.
MacroLoad(name) {
    sec := "macro_" . name
    n := 0
    try n := Integer(IniRead(IniFile, sec, "Chunks", "0"))
    ev := []
    Loop n {
        buf := IniRead(IniFile, sec, "E" . A_Index, "")
        for item in StrSplit(buf, ",") {
            p := StrSplit(item, ":")
            if (p.Length = 4)
                ev.Push([Integer(p[1]), Integer(p[2]), Integer(p[3]), Integer(p[4])])
        }
    }
    if (ev.Length = 0)
        return ""
    dur := 0
    try dur := Integer(IniRead(IniFile, sec, "Dur", "0"))
    if (dur < ev[ev.Length][1])
        dur := ev[ev.Length][1]
    lp := (IniRead(IniFile, sec, "Loop", "1") = "1")
    return Map("ev", ev, "dur", dur, "loop", lp)
}

; Makes sure the selected macro is in memory. True when it has events.
MacroEnsureLoaded() {
    global MacroActive, MacroEv, MacroDur, MacroLoop, MacroLoaded
    if (MacroActive = "")
        return false
    if (MacroLoaded != MacroActive) {
        m := MacroLoad(MacroActive)
        MacroLoaded := MacroActive
        if IsObject(m) {
            MacroEv := m["ev"]
            MacroDur := m["dur"]
            MacroLoop := m["loop"]
        } else {
            MacroEv := []
            MacroDur := 0
        }
    }
    return MacroEv.Length > 0
}

; ---- playing ----
PlayStart() {
    global MacroPlaying, MacroIdx, MacroT0, MacroHeld, MacroActive
    if MacroPlaying
        return true
    if !MacroEnsureLoaded() {
        ToolTip("No macro recorded" . (MacroActive != "" ? " under '" . MacroActive . "'" : "") . ": press Record (or F10) first.", TipX(), TipY(10))
        SetTimer(() => ToolTip(), -3500)
        RejoinLog("macro start: nothing recorded under '" . MacroActive . "'")
        return false
    }
    EnsureRobloxFocus()
    MacroHeld := Map()
    MacroIdx := 1
    MacroT0 := NowMs()
    MacroPlaying := true
    SetTimer(PlayStep, -1, 1)
    return true
}

PlayStop() {
    global MacroPlaying, MacroHeld
    if !MacroPlaying
        return
    MacroPlaying := false
    SetTimer(PlayStep, 0)
    for k, v in MacroHeld {
        try Send("{vk" . Format("{:X}", v[1]) . "sc" . Format("{:X}", v[2]) . " up}")
    }
    MacroHeld := Map()
}

PlayToggle() {
    if MacroPlaying
        PlayStop()
    else
        PlayStart()
}

F8Key() {
    PlayToggle()
    ToolTip("Macro " . (MacroPlaying ? "started" : "stopped") . " (" . MacroActive . ")", TipX(), TipY(10))
    SetTimer(() => ToolTip(), -1500)
    KeyWait("F8")
}

SendMacroKey(e) {
    global MacroHeld
    k := e[2] * 1024 + e[3]
    try Send("{vk" . Format("{:X}", e[2]) . "sc" . Format("{:X}", e[3]) . (e[4] ? " down}" : " up}"))
    if e[4] {
        MacroHeld[k] := [e[2], e[3]]
    } else if MacroHeld.Has(k) {
        MacroHeld.Delete(k)
    }
}

PlayStep() {
    global MacroPlaying, MacroEv, MacroDur, MacroLoop, MacroIdx, MacroT0
    static lastChk := 0
    static lastAct := 0
    static lastSkip := 0
    static lastChestLook := 0
    if !MacroPlaying
        return
    if (A_TickCount - lastChestLook >= 60 && IsRaidMap(CurMap)) {   ; raid chests: look from HERE too, so the macro stops the moment they show
        lastChestLook := A_TickCount
        try ChestTick()
        if !MacroPlaying
            return
    }
    if (A_TickCount - lastSkip >= 100) {   ; the macro runs through the cutscenes too: skip them from HERE (this timer never gets starved)
        lastSkip := A_TickCount
        try SkipLook()
        if !MacroPlaying
            return
    }
    if (A_TickCount - lastChk > 2000) {
        lastChk := A_TickCount
        if !RobloxRunning() {              ; the game is gone: never keep typing into other windows
            PlayStop()
            return
        }
    }
    now := NowMs() - MacroT0
    while (MacroIdx <= MacroEv.Length && MacroEv[MacroIdx][1] <= now) {
        e := MacroEv[MacroIdx]
        MacroIdx += 1
        if !WinActive("ahk_exe " . RobloxExe()) {
            if (A_TickCount - lastAct > 1000) {
                lastAct := A_TickCount
                try WinActivate("ahk_exe " . RobloxExe())
            }
            continue                       ; Roblox is not in front: don't type into another window
        }
        SendMacroKey(e)
    }
    if (MacroIdx > MacroEv.Length) {
        if (now >= MacroDur) {
            if MacroLoop {
                MacroT0 += MacroDur
                MacroIdx := 1
                SetTimer(PlayStep, -1, 1)
            } else {
                PlayStop()
            }
            return
        }
        d := MacroDur - now
    } else {
        d := MacroEv[MacroIdx][1] - now
    }
    SetTimer(PlayStep, -Max(1, Min(Floor(d), 50)), 1)   ; (never sleeps longer than 50 ms: the SKIP look above must keep running between key events)
}

; ---- recording ----
RecordToggle() {
    global Recording
    if Recording
        RecordStop()
    else
        RecordBegin()
}

RecordBegin(defName := "") {
    global Recording, RecIH, RecEv, RecHeld, RecT0, RecName, RecStart, MacroActive
    if Recording
        return
    if MacroPlaying
        PlayStop()
    ; instant: no name box and no countdown. A plain F10 / Record makes a NEW macro (named after the selected mission:
    ; "Outskirts", "Outskirts 2" ...) and never replaces one. Only "Re-record selected" in Manage passes a name and replaces it.
    if (defName = "")
        defName := UniqueMacroName(CurMap)
    name := CleanName(defName)
    if (name = "")
        name := "Macro"
    RecName := name
    EnsureRobloxFocus()
    RecEv := []
    RecHeld := Map()
    RecT0 := 0
    RecIH := InputHook("V")
    RecIH.KeyOpt("{All}", "N")
    RecIH.OnKeyDown := RecDown
    RecIH.OnKeyUp := RecUp
    RecIH.Start()
    RecStart := NowMs()
    Recording := true
    SetTimer(RecTip, 400)
    RecTip()
}

RecDown(ih, vk, sc) {
    global RecEv, RecHeld, RecT0
    if (vk = 0x79)                         ; F10 = the stop key, not part of the macro
        return
    k := vk * 1024 + sc
    if RecHeld.Has(k)                      ; key repeat while held
        return
    RecHeld[k] := [vk, sc]
    t := NowMs()
    if (RecT0 = 0)
        RecT0 := t
    RecEv.Push([Round(t - RecT0), vk, sc, 1])
}

RecUp(ih, vk, sc) {
    global RecEv, RecHeld, RecT0
    if (vk = 0x79)
        return
    k := vk * 1024 + sc
    if !RecHeld.Has(k)
        return
    RecHeld.Delete(k)
    RecEv.Push([Round(NowMs() - RecT0), vk, sc, 0])
}

RecTip() {
    global RecEv, RecName, RecStart
    ToolTip(Chr(9679) . " REC '" . RecName . "'   " . RecEv.Length . " key events   " . Round((NowMs() - RecStart) / 1000) . " s   (F10 = stop)", TipX(), TipY(10))
}

RecordStop() {
    global Recording, RecIH, RecEv, RecHeld, RecT0, RecName, MacroActive, MacroLoaded
    if !Recording
        return
    Recording := false
    SetTimer(RecTip, 0)
    try RecIH.Stop()
    endT := (RecT0 = 0) ? 0 : Round(NowMs() - RecT0)
    if (RecEv.Length = 0) {
        ToolTip("Nothing was recorded.", TipX(), TipY(10))
        SetTimer(() => ToolTip(), -3000)
        return
    }
    last := RecEv[RecEv.Length][1]
    dur := Max(last, Min(endT, last + 2000))
    for k, v in RecHeld
        RecEv.Push([dur, v[1], v[2], 0])
    lp := true
    old := MacroLoad(RecName)
    if IsObject(old)
        lp := old["loop"]
    MacroSave(RecName, RecEv, dur, lp)
    names := MacroNames()
    have := false
    for n in names {
        if (n = RecName)
            have := true
    }
    if !have {
        names.Push(RecName)
        MacroSaveNames(names)
    }
    MacroSetActive(RecName)
    RejoinLog("macro '" . RecName . "' recorded: " . RecEv.Length . " key events, " . Round(dur / 1000, 1) . " s")
    ToolTip("Saved macro '" . RecName . "' (" . RecEv.Length . " key events, " . Round(dur / 1000, 1) . " s). It is the selected one now.", TipX(), TipY(10))
    SetTimer(() => ToolTip(), -5000)
}

; "Outskirts", or "Outskirts 2", "Outskirts 3" ... the first name that is not taken yet.
UniqueMacroName(base) {
    base := CleanName(base)
    if (base = "")
        base := "Macro"
    names := MacroNames()
    n := base
    i := 2
    Loop {
        taken := false
        for x in names {
            if (x = n)
                taken := true
        }
        if !taken
            return n
        n := base " " i
        i += 1
    }
}

; ---- share macros: a macro is one small text file (.aotrmacro) ----
MgrExport() {
    n := MgrSel()
    if (n = "")
        return
    m := MacroLoad(n)
    if !IsObject(m)
        return
    MgrFloat(false)
    f := FileSelect("S16", A_ScriptDir "\" n ".aotrmacro", "Save the macro '" n "' to share it", "Macro (*.aotrmacro)")
    MgrFloat(true)
    if (f = "")
        return
    if !RegExMatch(f, "i)\.aotrmacro$")
        f .= ".aotrmacro"
    ev := ""
    for e in m["ev"]
        ev .= (ev = "" ? "" : ",") e[1] ":" e[2] ":" e[3] ":" e[4]
    txt := "AOTRMACRO1`n" "name=" n "`n" "dur=" m["dur"] "`n" "loop=" (m["loop"] ? 1 : 0) "`n" "ev=" ev "`n"
    try FileDelete(f)
    try FileAppend(txt, f, "UTF-8")
    ToolTip("Exported '" n "' to " f, TipX(), TipY(10))
    SetTimer(() => ToolTip(), -4000)
}

MgrImport() {
    MgrFloat(false)
    f := FileSelect(3, A_ScriptDir, "Pick a macro file to import", "Macro (*.aotrmacro)")
    MgrFloat(true)
    if (f = "")
        return
    txt := ""
    try txt := FileRead(f, "UTF-8")
    name := ""
    dur := 0
    lp := true
    evs := ""
    ok := false
    for ln in StrSplit(txt, "`n", "`r") {
        if (ln = "AOTRMACRO1")
            ok := true
        else if (SubStr(ln, 1, 5) = "name=")
            name := SubStr(ln, 6)
        else if (SubStr(ln, 1, 4) = "dur=")
            dur := IsInteger(SubStr(ln, 5)) ? Integer(SubStr(ln, 5)) : 0
        else if (SubStr(ln, 1, 5) = "loop=")
            lp := (SubStr(ln, 6) = "1")
        else if (SubStr(ln, 1, 3) = "ev=")
            evs := SubStr(ln, 4)
    }
    ev := []
    if ok {
        for item in StrSplit(evs, ",") {
            q := StrSplit(item, ":")
            if (q.Length != 4 || !IsInteger(q[1]) || !IsInteger(q[2]) || !IsInteger(q[3]) || !IsInteger(q[4])) {
                ev := []
                break
            }
            ev.Push([Integer(q[1]), Integer(q[2]), Integer(q[3]), Integer(q[4])])
        }
    }
    if (!ok || ev.Length = 0) {
        MsgBox("That file is not a valid macro file.", "Import macro", "Icon! 262144")
        return
    }
    if (dur < ev[ev.Length][1])
        dur := ev[ev.Length][1]
    nn := UniqueMacroName(name != "" ? name : "Imported")
    MacroSave(nn, ev, dur, lp)
    names := MacroNames()
    names.Push(nn)
    MacroSaveNames(names)
    MacroSetActive(nn)
    MgrRefresh(nn)
    ToolTip("Imported '" nn "' (" ev.Length " key events). It is the selected macro now.", TipX(), TipY(10))
    SetTimer(() => ToolTip(), -4000)
}

; ---- choosing / managing macros ----
MacroCycle(dir) {
    global MacroActive
    names := MacroNames()
    if (names.Length = 0)
        return
    idx := 0
    for i, n in names {
        if (n = MacroActive)
            idx := i
    }
    idx += dir
    if (idx < 1)
        idx := names.Length
    if (idx > names.Length)
        idx := 1
    if MacroPlaying
        PlayStop()
    MacroSetActive(names[idx])
}

SetBuiltIn(v) {
    global BuiltIn, IniFile
    BuiltIn := (v = 1)
    try IniWrite(BuiltIn ? "1" : "0", IniFile, "opts", "BuiltIn")
    if !BuiltIn
        PlayStop()
    else if !MacroEnsureLoaded() {
        ToolTip("Built-in player ON, but no macro is recorded yet: press Record.", TipX(), TipY(10))
        SetTimer(() => ToolTip(), -4000)
    }
    RejoinLog("built-in macro player is now " . (BuiltIn ? "ON" : "OFF"))
}

; The "Loop macro" switch: ON = the macro repeats until the round ends, OFF = it plays once per round. Saved with the active macro.
MacroLoopOn() {
    global MacroLoop
    try MacroEnsureLoaded()
    return MacroLoop ? true : false
}

SetMacroLoop(v) {
    global MacroLoop, MacroActive, MacroLoaded
    if (MacroActive = "") {
        MacroLoop := (v = 1)
        return
    }
    try MacroEnsureLoaded()
    m := MacroLoad(MacroActive)
    if IsObject(m)
        MacroSave(MacroActive, m["ev"], m["dur"], v = 1)
    MacroLoop := (v = 1)
    RejoinLog("macro loop for '" MacroActive "' is now " (MacroLoop ? "ON (continuous)" : "OFF (fires once)"))
}

MacroManager() {
    global MgrGui, MgrList, BtnMap, MacroActive
    try MgrGui.Destroy()
    g := Gui("+AlwaysOnTop", "Macros")
    MgrGui := g
    g.BackColor := "11131A"
    g.MarginX := 20
    g.MarginY := 16
    g.SetFont("s10 cE8EAF0", "Segoe UI")
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "UInt", 20, "Int*", 1, "UInt", 4)
    h := g.AddText("w320 c6B7185", "YOUR MACROS")
    h.SetFont("s8 Bold c6B7185", "Segoe UI")
    MgrList := g.AddListBox("xm w320 r8 Background1A1D27 cE8EAF0", MacroNames())
    try MgrList.Choose(MacroActive)
    MgrBtn(g, "Use selected", "xm y+14 w155 h34", MgrUse, true)
    MgrBtn(g, "Record new macro", "x+10 w155 h34", MgrRecordNew)
    MgrBtn(g, "Re-record selected", "xm y+10 w155 h34", MgrRecord)
    MgrBtn(g, "Rename", "x+10 w155 h34", MgrRename)
    MgrBtn(g, "Import (.aotrmacro)", "xm y+10 w155 h34", MgrImport)
    MgrBtn(g, "Export / share", "x+10 w155 h34", MgrExport)
    MgrBtn(g, "Delete", "xm y+10 w155 h34", MgrDelete)
    MgrBtn(g, "Loop on / off", "x+10 w155 h34", MgrLoop)
    MgrBtn(g, "Close", "xm y+10 w320 h34", (*) => g.Destroy())
    g.OnEvent("Close", (*) => g.Destroy())
    g.Show("AutoSize")
}

MgrBtn(g, txt, opt, fn, primary := false) {
    global BtnMap
    bg := primary ? "E9B44C" : "232734"
    fg := primary ? "14161C" : "E8EAF0"
    c := g.AddText(opt . " Center +0x200 +0x100 Background" . bg . " c" . fg, txt)
    c.SetFont("s9 Norm c" . fg, "Segoe UI Semibold")
    c.OnEvent("Click", (*) => fn())
    BtnMap[c.Hwnd] := [c, bg, primary ? "F2C566" : "2E3345"]
}

; The Macros window is always on top, which would hide the dialogs opened from it: it steps back while one is open.
MgrFloat(on) {
    global MgrGui
    try MgrGui.Opt(on ? "+AlwaysOnTop" : "-AlwaysOnTop")
}

MgrSel() {
    global MgrList
    n := ""
    try n := MgrList.Text
    return n
}

MgrRefresh(sel := "") {
    global MgrList
    try MgrList.Delete()
    names := MacroNames()
    if (names.Length > 0)
        try MgrList.Add(names)
    if (sel != "")
        try MgrList.Choose(sel)
}

MgrUse() {
    n := MgrSel()
    if (n = "")
        return
    if MacroPlaying
        PlayStop()
    MacroSetActive(n)
    ToolTip("Selected macro: " . n, TipX(), TipY(10))
    SetTimer(() => ToolTip(), -2000)
}

MgrRecordNew() {
    global MgrGui
    try MgrGui.Destroy()
    RecordBegin()
}

MgrRecord() {
    global MgrGui
    n := MgrSel()
    try MgrGui.Destroy()
    RecordBegin(n)
}

MgrRename() {
    global MacroActive
    n := MgrSel()
    if (n = "")
        return
    MgrFloat(false)
    r := InputBox("New name for '" . n . "':", "Rename macro", "w360 h150", n)
    MgrFloat(true)
    if (r.Result != "OK")
        return
    nn := CleanName(r.Value)
    if (nn = "" || nn = n)
        return
    m := MacroLoad(n)
    if !IsObject(m)
        return
    MacroSave(nn, m["ev"], m["dur"], m["loop"])
    try IniDelete(IniFile, "macro_" . n)
    names := MacroNames()
    out := []
    for x in names {
        if (x = n)
            out.Push(nn)
        else if (x != nn)
            out.Push(x)
    }
    MacroSaveNames(out)
    if (MacroActive = n)
        MacroSetActive(nn)
    MgrRefresh(nn)
}

MgrDelete() {
    global MacroActive
    n := MgrSel()
    if (n = "")
        return
    if (MsgBox("Delete the macro '" . n . "'?", "Delete macro", "YesNo Icon? 262144") != "Yes")
        return
    try IniDelete(IniFile, "macro_" . n)
    out := []
    for x in MacroNames() {
        if (x != n)
            out.Push(x)
    }
    MacroSaveNames(out)
    if (MacroActive = n) {
        if MacroPlaying
            PlayStop()
        MacroSetActive(out.Length > 0 ? out[1] : "")
    }
    MgrRefresh()
}

MgrLoop() {
    global MacroLoaded
    n := MgrSel()
    if (n = "")
        return
    m := MacroLoad(n)
    if !IsObject(m)
        return
    MacroSave(n, m["ev"], m["dur"], !m["loop"])
    MacroLoaded := ""
    ToolTip("'" . n . "': loop is now " . (m["loop"] ? "OFF (plays once)" : "ON (repeats)"), TipX(), TipY(10))
    SetTimer(() => ToolTip(), -2500)
}

; ===================== THE GUIDE (opens on first start, F2 or the Guide button) =====================
GuidePages() {
    static pages := 0
    if IsObject(pages)
        return pages
    p0 := "
(
QUICK START (THE SHORT VERSION)

Do not want to read? Press the 'Quick start' button in the top bar. It shows 6 steps with a dot for each one. Amber = still to do, green = done. Buttons in that window do the step for you.

THE 6 STEPS IN ONE LINE EACH
1. Windows scale 100 percent.
2. Roblox open in its smallest window.
3. Pick your mission or raid (Change).
4. Press F10, play ONE round with your keys, press F10 again.
5. Switch 'Use built-in macro' ON.
6. In the mission press F8. It retries and restarts by itself from then on.

HOVER HELP
Rest the mouse on any button or switch for a moment. A short note says what it does.

THE SHORT VERSION ONLY GETS YOU STARTED
The full guide (the other pages on the left) explains what the short version skips:
 - what to do when something goes wrong (page 11),
 - how the automatic rejoin works and what it needs (page 5),
 - raids, chests and cutscenes (page 7),
 - Discord reports and ping options (page 8),
 - several macros, importing and sharing them (page 4).
Please read at least pages 1 to 5 once. Most 'it does not work' problems are written there.
)"
    p1 := "
(
WELCOME - READ THIS FIRST

WHAT THIS APP DOES
It plays Attack on Titan Revolution (AOTR) for you:
 - It presses the keys you recorded during a mission.
 - When the mission ends it clicks RETRY and starts again.
 - If you get disconnected or the game crashes, it joins back by itself.
 - It sends a report to your Discord (optional).

QUICK START - DO THESE IN ORDER
1. Close the script. Right-click it and choose 'Run as administrator'. If you skip this, NOTHING works.
2. Windows display scale must be 100 percent (Settings > System > Display > Scale).
3. Open Roblox and join AOTR. Make the Roblox window as SMALL as it can go. This app wraps around the window.
4. Press F9. This is the Setup check. Fix every line that says it is wrong.
5. Go into a mission. Press F10, type a name like Outskirts, play one round of the mission with your keys, then press F10 again. (Page 3 explains this.)
6. Turn ON the switch 'Use built-in macro'.
7. Leave 'Auto retry and start' ON.
8. Press F8 in a mission to test your macro. Press F8 again to stop it.
9. Done. From now on it retries and restarts by itself.

Use the list on the left to read the other pages. Use the Next button to go page by page.
)"
    p2 := "
(
2. SETTING UP ROBLOX AND YOUR PC

WINDOW SIZE
 - Roblox must be in a WINDOW, not fullscreen. If it is fullscreen press F11 inside Roblox.
 - Drag the window corner until it cannot get smaller. The app needs the smallest size (801 x 629).
 - The top bar of this app tells you where the window is pinned.

DO NOT:
 - Do not minimize Roblox.
 - Do not put other windows on top of Roblox. The app reads the screen, so anything covering the game breaks it.
 - Do not lock your PC or minimize your remote desktop (RDP). The screen must stay visible.
 - Do not move the window while it runs. The app puts it back to its pinned spot.

IF YOU WANT ROBLOX IN A DIFFERENT SPOT
Move it, then open Settings and press 'Pin window here'. Your recorded macro still works because it only uses keys.

YOUR PC
 - Run as administrator (see page 1).
 - Display scale 100 percent.
 - Screen at least 1280 x 720.
 - The script folder must be writable (do not run it from a protected folder). Documents or Desktop are fine.

Press F9 any time. The Setup check lists every problem in plain words.
)"
    p3 := "
(
3. RECORDING YOUR MACRO

A macro is the list of keys you press during ONE mission. The app repeats it again and again until the mission ends. It records KEYBOARD ONLY (no mouse).

HOW TO RECORD
1. Join a mission and wait until you can move.
2. Press F10 (or click Record).
3. It starts recording at once (no countdown). It saves as a NEW macro (Outskirts, Outskirts 2 ...) and never replaces one.
4. Want it under another name? Record, then use Rename in Manage.
5. Play normally with your keys: move, use skills, whatever you want repeated.
6. Press F10 again to stop. A message says the macro was saved.

TIPS
 - Record about one short round of actions. Do not wait around at the end. It repeats from the start.
 - Do not use the keys F1 to F10. The app uses them.
 - Do not press F10 by accident while recording. It stops the recording.
 - Not happy with it? Press F10 and record again: it is added as a new macro. To replace one, use Manage > Re-record selected.
 - Nothing is recorded if you press no keys.

PLAYING IT
 - F8 starts and stops the macro.
 - The 'Use built-in macro' switch must be ON, or F8 does nothing from this app.
 - When the mission ends the app stops the macro, clicks RETRY and starts it again.
 - The macro only types into Roblox. If Roblox is not the front window it will not type into other programs.
)"
    p4 := "
(
4. SEVERAL MACROS (PRESETS)

You can save one macro for each map or raid. For example: Outskirts, Female Titan.

CHOOSING ONE
 - Use the little arrows on both sides of the macro name in the MACRO box.
 - The name in the middle is the macro that F8 and Play will use.

MANAGE
Click 'Manage' (or the macro name). You can:
 - Use selected: make it the active one.
 - Record new macro: same as F10, a new macro is added.
 - Re-record selected: records over the selected macro.
 - Export / share: saves the macro as a small .aotrmacro file you can send to a friend.
 - Import: loads a .aotrmacro file from someone else (it is added as a new macro).
 - Rename and Delete.
 - Loop on / off: ON repeats forever (normal for missions). OFF plays it once (good for a one-time action).

MISSIONS AND RAIDS
Each mission or raid has its own macro. Click 'Change' in the MISSION / RAID box to pick one. The macro you pick or record afterwards is saved for THAT mission. Switching the mission switches to its macro.
Missions: Outskirts, Utgard, Shiganshina, Forest. Raids: Attack Titan, Female Titan, Colossal Titan. After a disconnect the rejoin goes to the one you picked.
In a RAID the app also does these by itself: it skips the cutscenes (SKIP [E]) and at the end it opens the left chest first, then the KEY chest, then presses FINISH. The key chest is only opened when the switch 'Open key chest' is ON and you still have keys.
)"
    p5 := "
(
5. AUTO RETRY, REJOIN AND STUCK MISSIONS

AUTO RETRY AND START (switch)
When the MISSION COMPLETED or MISSION FAILED screen appears the app:
 1. stops your macro,
 2. clicks RETRY,
 3. waits for the loading screens,
 4. starts your macro again when the mission begins,
 5. sends the report to Discord.

IF YOU GET DISCONNECTED
When an error box appears (Disconnected, Connection Failed) the app ALWAYS clicks the LEFT button, Leave. It never clicks Reconnect. Then it goes: Roblox home > search 'aotr' > the Attack on Titan Revolution result > PLAY > menu > lobby > Outskirts > CREATE > modifiers > START.
If Roblox itself closes, it tells you on Discord.

STUCK MISSION
If no end screen shows up for about 2.5 minutes the app thinks the mission is stuck. It leaves the game and rejoins. You can turn this off with Ctrl+Shift+F11.

WHAT MUST BE TRUE FOR REJOIN TO WORK
 - You are logged in to Roblox.
 - Roblox is in its small window and the app is running as administrator.
 - 'Windowed mode' is ON.
 - The Roblox search for 'aotr' shows the big Attack on Titan Revolution card.

PAUSE
Press F3 (or the Paused switch) to stop everything. Press F3 again to continue.
)"
    p6 := "
(
6. JOINING YOUR VIP / PRIVATE SERVER

By default the app rejoins with the normal PLAY button. That is the easy way.

TO JOIN A VIP SERVER INSTEAD
1. Turn ON the switch 'Join VIP server'.
2. Open Settings and paste your private server code or link in 'Private server code'. Press 'Save settings'.
3. Leave it empty if your VIP server code is already saved in the game's VIP SERVERS box.

WHAT HAPPENS
The app clicks CODES, clicks the VIP SERVERS box, pastes your code and presses Enter. If that does not work 3 times it falls back to the PLAY button.

Switch it OFF to go back to normal PLAY. Hotkey: Ctrl+Shift+F7.
)"
    p7 := "
(
7. MODIFIERS

Modifiers are the boxes you can tick before START (NO PERKS, FOG, FATIGUE ...).

CHOOSING THEM
Click 'Modifiers' (or press Ctrl+Shift+F6). Tick the ones the app should turn ON.
 - 'Don't touch the modifiers at all' = the app skips that screen.

The app opens the modifiers list after a rejoin, ticks what you chose, presses BACK and then START.
)"
    p8 := "
(
8. DISCORD REPORTS (OPTIONAL)

You get a message after every mission: win or fail, drops, scrolls, Mythic and Divine counts, time per round, disconnects.

MAKE A WEBHOOK
1. In Discord open your server settings > Integrations > Webhooks > New Webhook.
2. Pick the channel and press 'Copy Webhook URL'.
3. In this app press Settings. Paste it in 'Discord webhook URL'.
4. Press 'Save settings', then press 'Test webhook'. A message should appear in Discord.

GET PINGED
Discord > Settings > Advanced > turn on Developer Mode. Right-click your own name > 'Copy User ID'. Paste it in 'Your Discord user ID' and save. You are pinged for Mythic, Divine, disconnects and problems.

WHAT THE REPORT SHOWS
The title says Mission or Raid, completed or failed (a retreat counts as failed). Then the map, the drops of that round, round time, average, rounds per hour, record, win rate, streak and your session totals. Problems (disconnect, stuck mission, could not rejoin) arrive as their own coloured messages with a screenshot.

PING OPTIONS
Settings > 'Ping options': tick what should @ping you: Mythic, Divine, Scroll, failed round, disconnect, stuck mission, 'could not rejoin'. The reports are always sent, the ticks only decide the ping. You can also switch off the short 'back in / reconnected' messages.

NEVER share your webhook URL with other people.
)"
    p9 := "
(
9. ALL HOTKEYS

On many laptops the F keys need Fn held down (or turn on "Fn lock"). Every F key also has a button in the app:
Record, Play / Stop, Guide, Setup check ...

F1             Restart the script
F2             Open this guide
F3             Pause / resume everything
F4             Show which screen the app sees (useful for problems)
F5             Test how much of the end screen is detected
F8             Start / stop your macro (built-in macro ON)
F9             Setup check (finds problems)
F10            Start / stop recording a macro
Ctrl+Shift+F6  Choose modifiers
Ctrl+Shift+F7  Join VIP server ON / OFF
Ctrl+Shift+F8  Auto retry and start ON / OFF
Ctrl+Shift+F9  Send a test message to Discord
Ctrl+Shift+F10 Test the whole rejoin now
Ctrl+Shift+F11 Stuck-mission watcher ON / OFF
F7             While hovering the error box's Leave button: remember that spot

Every switch and button in the app also shows its key.
)"
    p10 := "
(
10. WHAT EVERY SWITCH AND BUTTON DOES

SWITCHES
 - Auto retry and start: clicks RETRY and restarts the macro after every mission.
 - Loop macro: ON repeats your macro until the round ends. OFF plays it only once per round (saved for the selected macro).
 - Join VIP server: OFF = normal PLAY. ON = join your private server.
 - Paused: stops the macro and the watchers until you turn it off.
 - Windowed mode: keep it ON. It means the small Roblox window.
 - Use built-in macro: use the recorded keys of this app (no TinyTask).

MACRO BOX
 - Arrows / name: choose the macro.
 - Record: record a new macro. Play: start / stop it. Manage: rename, delete, loop.

TOOLS
 - Modifiers: choose the modifiers for the rejoin.
 - Settings: webhook, user ID, private server code, pin window.
 - Setup check: lists every problem.
 - Open log: opens the log file (send it when asking for help).
 - Guide: this page.

BOTTOM BAR
Shows what the app is doing, the screen it sees and the macro state.
)"
    p11 := "
(
11. PROBLEMS AND ANSWERS

NOTHING HAPPENS AT ALL
 - Run the script as administrator.
 - Press F9 and fix every red line.
 - Check the switch 'Paused' is OFF.

IT COUNTS A WIN WHEN A TITAN TRANSFORMS (FALSE WINS)
 - Open Settings and raise ConfirmMs (default 350). Try 450, then 600. Press Save settings.
 - Too high makes the RETRY click a little slower, so only raise it as much as needed.

IT DOES NOT CLICK RETRY
 - Press F4 while the end screen is showing. It should say MISSION COMPLETED or MISSION FAILED.
 - Make sure nothing covers the Roblox window.
 - Keep Windows display scale at 100 percent.
 - Open the log (Open log) and send it when asking for help.

MY MACRO DOES NOTHING WHEN I PRESS F8
 - Turn ON 'Use built-in macro'.
 - Record a macro first (page 3).
 - Roblox must be the front window.

IT SAYS 'other / not recognised' FOR A LONG TIME
 - Press F4 to see the screen name. Send a screenshot to whoever helps you.
 - Do not resize or move the Roblox window.

IT KEEPS CLICKING CODES
 - Your game window may be covered or not the smallest size. Fix the window and press F9.

IT NEEDS SUPPORT / SOMETHING ELSE IS WRONG
 - Settings > 'Save diagnostics (for support)'. It makes diagnostics.txt (next to the script) and a screenshot. Send both.

MY ROBLOX LOOKS DIFFERENT (LIGHT THEME, EXTRA ICONS)
 - The rejoin finds the search icon by itself and uses the game link when a screen is unknown. If it still gets stuck, send diagnostics.txt and a screenshot.

DISCORD GETS NOTHING
 - Press 'Test webhook'. If nothing shows, copy the webhook again. Do not add spaces.

IT REJOINED BY ITSELF AND I DID NOT DISCONNECT
 - That is the stuck-mission watcher (no end screen for about 2.5 minutes). Turn it off with Ctrl+Shift+F11 if your missions are long.

THE KEYS STOPPED WORKING IN GAME
 - Click the Roblox window once. Check 'Paused' is OFF. Press F8 twice (stop, start).

STILL STUCK?
Press F9, press 'Open log', and send both to the person who gave you this script. Say what you did and what you saw.
)"
    pages := [["0. Quick start (short)", p0], ["1. Start here", p1], ["2. Roblox and PC setup", p2], ["3. Record your macro", p3], ["4. Several macros", p4], ["5. Auto retry and rejoin", p5], ["6. Join VIP server", p6], ["7. Modifiers", p7], ["8. Discord reports", p8], ["9. All hotkeys", p9], ["10. Switches and buttons", p10], ["11. Problems and answers", p11]]
    return pages
}

OpenGuide(page := 2) {
    global GuideGui, GuideList, GuideText
    try GuideGui.Destroy()
    pages := GuidePages()
    g := Gui(, "AOTR Macro - Guide")
    GuideGui := g
    g.BackColor := "11131A"
    g.MarginX := 16
    g.MarginY := 16
    g.SetFont("s10 cE8EAF0", "Segoe UI")
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "UInt", 20, "Int*", 1, "UInt", 4)
    titles := []
    for p in pages
        titles.Push(p[1])
    GuideList := g.AddListBox("x16 y16 w210 h520 Background1A1D27 cE8EAF0", titles)
    GuideList.SetFont("s10 cE8EAF0", "Segoe UI")
    GuideList.OnEvent("Change", (*) => GuideShow())
    GuideText := g.AddEdit("x240 y16 w560 h470 ReadOnly Multi VScroll Background1A1D27 cE8EAF0")
    GuideText.SetFont("s10 cE8EAF0", "Segoe UI")
    nb := g.AddText("x240 y496 w270 h40 Center +0x200 +0x100 BackgroundE9B44C c14161C", "Next page")
    nb.SetFont("s10 Norm c14161C", "Segoe UI Semibold")
    nb.OnEvent("Click", (*) => GuideNext(1))
    BtnMap[nb.Hwnd] := [nb, "E9B44C", "F2C566"]
    cb := g.AddText("x530 y496 w270 h40 Center +0x200 +0x100 Background232734 cE8EAF0", "Close")
    cb.SetFont("s10 Norm cE8EAF0", "Segoe UI Semibold")
    cb.OnEvent("Click", (*) => g.Destroy())
    BtnMap[cb.Hwnd] := [cb, "232734", "2E3345"]
    g.OnEvent("Close", (*) => g.Destroy())
    GuideList.Choose(page)
    GuideShow()
    g.Show("w816 h552")
}

GuideShow() {
    global GuideList, GuideText
    pages := GuidePages()
    i := GuideList.Value
    if (i < 1 || i > pages.Length)
        i := 1
    GuideText.Value := StrReplace(pages[i][2], "`n", "`r`n")
}

GuideNext(dir) {
    global GuideList
    pages := GuidePages()
    i := GuideList.Value + dir
    if (i > pages.Length)
        i := 1
    if (i < 1)
        i := pages.Length
    GuideList.Choose(i)
    GuideShow()
}

; ===================== MISSIONS AND RAIDS =====================
SetKeyChest(v) {
    global KeyChest, IniFile
    KeyChest := (v = 1)
    try IniWrite(KeyChest ? "1" : "0", IniFile, "opts", "KeyChest")
    RejoinLog("key chest (raids) is now " (KeyChest ? "ON" : "OFF"))
}

SetDuo(v) {
    global DuoRaid, IniFile
    DuoRaid := (v = 1)
    try IniWrite(DuoRaid ? "1" : "0", IniFile, "opts", "DuoRaid")
    RejoinLog("duo raid is now " (DuoRaid ? "ON" : "OFF"))
    try LayoutLeft()
}

SetDuoHost(v) {
    global DuoHost, IniFile
    DuoHost := (v = 1)
    try IniWrite(DuoHost ? "1" : "0", IniFile, "opts", "DuoHost")
    RejoinLog("duo raid: you are the " (DuoHost ? "HOST" : "JOINER"))
}

SetRoleBeast(v) {
    SetColossalRole("Beast")               ; only one role can be ticked: clicking the ticked one keeps it
}

SetRoleColossal(v) {
    SetColossalRole("Colossal")
}

SetColossalRole(r) {
    global ColossalRole, IniFile
    if (ColossalRole = r)
        return
    ColossalRole := r
    try IniWrite(r, IniFile, "opts", "ColossalRole")
    RejoinLog("colossal raid role: " r " (no function yet)")
}

; A SOLO raid (Duo switch OFF): the TAB check still runs after the first skip, to catch a 2nd player who joined by mistake.
SoloActive() {
    global DuoRaid, WinMode, CurMap
    return (!DuoRaid && WinMode && IsRaidMap(CurMap))
}

DuoActive() {
    global DuoRaid, WinMode, CurMap
    return (DuoRaid && WinMode && IsRaidMap(CurMap))
}

DuoJoiner() {
    global DuoHost
    return (DuoActive() && !DuoHost)
}

DuoHosting() {
    global DuoHost
    return (DuoActive() && DuoHost)
}

; The 2nd player slot of the host's lobby shows a KICK button (gold pill, right side) once somebody has joined.
DuoKickSeen() {
    gr := GrabRect(WX + 500, WY + 350, 70, 28)
    if !IsObject(gr)
        return false
    n := 0
    for x in [516, 522, 528, 534, 540, 546, 552] {
        for y in [360, 363, 367] {
            if InjGold(gr, x, y)
                n += 1
        }
    }
    FreeGrab(gr)
    return n >= 12
}

; The LOBBIES list (after JOIN): gold frame 277..524 x 221..499 and the gold title LOBBIES.
LobbiesLook() {
    f := 0
    for q in [[300, 221], [350, 221], [400, 221], [450, 221], [500, 221], [300, 499], [350, 499], [400, 499], [450, 499], [500, 499], [277, 250], [277, 300], [277, 350], [277, 400], [277, 450], [524, 250], [524, 300], [524, 350], [524, 400], [524, 450]] {
        if GoldAt(WX + q[1], WY + q[2])
            f += 1
    }
    if (f < 18)
        return false
    t := 0
    y := 226
    while (y <= 245) {
        x := 325
        while (x <= 477) {
            if GoldD(Px(WX + x, WY + y))
                t += 1
            x += 4
        }
        y += 3
    }
    return t >= 30
}

; The RETRY button says (used/2). "2/2" = no retry left. The first digit is compared with the second one (always "2") as a
; picture: the same glyph correlates ~1.0, a 0 or a 1 stays below 0.6. 1 = retry left, 0 = used up, -1 = could not read.
DuoRetryState() {
    gr := GrabRect(WX + 496, WY + 460, 30, 12)
    if !IsObject(gr)
        return -1
    best := -2
    for d1 in [-1, 0, 1] {
        for d2 in [-1, 0, 1] {
            a := []
            b := []
            y := 462
            while (y <= 469) {
                x := 0
                while (x < 6) {
                    a.Push(GrabSum(GrabPx(gr, WX + 503 + d1 + x, WY + y)) / 3.0)
                    b.Push(GrabSum(GrabPx(gr, WX + 514 + d2 + x, WY + y)) / 3.0)
                    x += 1
                }
                y += 1
            }
            r := DuoCorr(a, b)
            if (r > best)
                best := r
        }
    }
    FreeGrab(gr)
    if (best < -1)
        return -1
    return (best >= 0.8) ? 0 : 1
}

DuoCorr(a, b) {
    n := a.Length
    ma := 0.0
    mb := 0.0
    for i, v in a {
        ma += v
        mb += b[i]
    }
    ma /= n
    mb /= n
    sa := 0.0
    sb := 0.0
    sab := 0.0
    for i, v in a {
        da := v - ma
        db := b[i] - mb
        sa += da * da
        sb += db * db
        sab += da * db
    }
    if (Sqrt(sa / n) < 12 || Sqrt(sb / n) < 12)
        return -2
    return sab / Sqrt(sa * sb)
}

; Out of retries (or the button does not work): leave the game and come back as host / joiner, like a stuck mission.
; ---- The TAB list (leaderboard) ----
; Is the leaderboard panel open? Returns the number of players listed, or -1 when the panel is not open.
; (gold frame all around + dark inside; one name per row; window coordinates)
LeaderLook() {
    global WX, WY
    gr := GrabRect(WX + 200, WY + 190, 400, 280)
    if !IsObject(gr)
        return -1
    res := -1
    try {
        g := 0
        t := 0
        for q in LeaderBorderPts() {
            t += 1
            if LbGold(GrabPx(gr, WX + q[1], WY + q[2]))
                g += 1
        }
        dk := 0
        for q in [[300, 420], [500, 420], [400, 440], [250, 380], [550, 380], [300, 330], [500, 330]] {
            if (GrabSum(GrabPx(gr, WX + q[1], WY + q[2])) < 150)
                dk += 1
        }
        if (g >= t * 0.85 && dk >= 5) {
            res := 0
            for band in [[262, 282], [289, 309], [316, 336], [343, 363]] {
                n := 0
                y := band[1]
                while (y < band[2]) {
                    x := 245
                    while (x < 345) {
                        if (GrabSum(GrabPx(gr, WX + x, WY + y)) >= 450)
                            n += 1
                        x += 1
                    }
                    y += 1
                }
                if (n >= 50)
                    res += 1
            }
        }
    }
    FreeGrab(gr)
    return res
}

LeaderBorderPts() {
    pts := []
    y := 215
    while (y <= 445) {
        pts.Push([210, y])
        pts.Push([591, y])
        y += 10
    }
    x := 230
    while (x <= 570) {
        pts.Push([x, 201])
        pts.Push([x, 459])
        x += 20
    }
    return pts
}

LbGold(c) {
    r := (c >> 16) & 0xFF
    g := (c >> 8) & 0xFF
    b := c & 0xFF
    return (r >= 120 && g >= 70 && r - b >= 50 && r >= g)
}

; After the first skip of a duo match: press TAB, read the list, press TAB again. Only ONE player listed = the partner is gone:
; leave and rejoin (otherwise the lone player would keep retrying a duo raid by himself). The macro keeps running meanwhile.
DuoTabCheck() {
    global busyReconnect, ScriptPaused, WinMode
    static lastDone := 0
    static running := false
    if (running || !WinMode || busyReconnect || ScriptPaused || !(DuoActive() || SoloActive()))
        return
    if (A_TickCount - lastDone < 75000)           ; once per match
        return
    running := true
    lastDone := A_TickCount
    players := -1
    try {
        try WinActivate("ahk_exe " RobloxExe())
        Loop 2 {
            PressKey("Tab")
            t0 := A_TickCount
            while (A_TickCount - t0 < 900) {
                Sleep 100
                players := LeaderLook()
                if (players >= 0)
                    break
            }
            if (players >= 0)
                break
        }
        if (players >= 0) {
            Sleep 200
            p2 := LeaderLook()                    ; read it twice
            if (p2 >= 0)
                players := p2
            PressKey("Tab")                       ; close it again
            Sleep 300
            if (LeaderLook() >= 0)
                PressKey("Tab")
        } else {
            RejoinLog("duo: TAB list did not open (will look again after the next skip)")
            lastDone := 0
        }
    }
    running := false
    if (players >= 0)
        RejoinLog("duo: TAB list shows " players " player(s)")
    if (players = 1 && DuoActive() && !busyReconnect && !ScriptPaused)
        SetTimer(DuoLeaveGone, -1)
    else if (players >= 2 && SoloActive() && !busyReconnect && !ScriptPaused)
        SetTimer(SoloLeaveFound, -1)
}

SoloLeaveFound() {
    DuoLeave("a 2nd player was found in your solo raid", true)
}

DuoLeaveGone() {
    DuoLeave("the 2nd player is gone")
}

DuoLeave(why := "", solo := false) {
    global busyReconnect, lastRoundTick, dcActive, dcCount, reconnectTries, runStart, StuckLeaveWaitSeconds, DuoHost, StatusMsgs
    runStart := 0
    busyReconnect := true
    ok := false
    try {
        why := (why = "" || !IsSet(why)) ? "no retry left" : why
        RejoinLog((solo ? "solo: " : "duo: ") why ": leaving the game and " (solo ? "rejoining" : (DuoHost ? "hosting" : "joining")) " a new raid")
        if solo {
            try SendAlert("warn", "Rejoining: 2nd player found", "Another player is in your solo raid. Leaving AOTR and starting a new raid.", Ping(true))
        } else if StatusMsgs {
            try SendAlert("warn", "Duo raid: " why, "Leaving AOTR and " (DuoHost ? "hosting a new raid" : "joining the host's new raid") ".")
        }
        StopMainHard(true)
        try WinActivate("ahk_exe " RobloxExe())
        Sleep 500
        PressKey("Esc")
        Sleep 800
        PressKey("l")
        Sleep 800
        PressKey("Enter")
        endT := A_TickCount + StuckLeaveWaitSeconds * 1000
        while (A_TickCount < endT) {
            if (TTState("main") = 1)
                EnsureMain(false)
            Sleep 500
        }
        ok := RejoinSequence(false)
    }
    busyReconnect := false
    ToolTip()
    lastRoundTick := A_TickCount
    dcActive := false
    dcCount := 0
    reconnectTries := 0
    if !ok {
        RejoinLog("duo: could not get back into a raid")
        shot := ""
        try shot := TakeShot("duo_failed")
        try SendAlert("fatal", "Duo raid: could not get back in", "The macro is **OFF**. Fix it by hand.", Ping(PingOnGaveUp), shot)
    }
}

; Waits (up to 25 minutes) in the lobby until the host starts: the objectives panel shows, the cutscene is skipped and the macro starts.
JoinerWait(st) {
    t0 := A_TickCount
    while (A_TickCount - t0 < 1500000) {
        if ScriptPaused {
            Sleep 250
            t0 += 250
            continue
        }
        if !RobloxRunning()
            return "left"
        ToolTip("Duo raid: in the lobby, waiting for the host to start", TipX(), TipY(70))
        r := WaitMatchReady(15000, false, true)
        if (r = "objectives")
            return "started"
        scr := DetectScreen()
        for nm in ["lobby", "modes", "home", "search", "gamepage", "slots", "slotshover", "menu", "vip", "popup", "daily", "dialog", "lobbies", "map", "raid", "raidok", "mapok", "mapwrong", "modifiers"] {
            if (scr = nm)
                return "left"
        }
    }
    return "left"
}

MapKindOf(name) {
    for m in MapList {
        if (m[1] = name)
            return m[2]
    }
    return "Normal mission"
}

IsRaidMap(name) {
    return (MapKindOf(name) = "Raid")
}

; Place of the mission / raid in the game's list (0 = first row).
; Missions: Shiganshina, Trost, Outskirts, Forest, (scroll) Utgard, Docks, Stohess, Chapel. Raids: Attack, Armored, Female, Colossal.
MapRowIdx(name) {
    switch name {
        case "Shiganshina": return 0
        case "Outskirts": return 2
        case "Forest": return 3
        case "Utgard": return 4
        case "Attack Titan": return 0
        case "Female Titan": return 2
        case "Colossal Titan": return 3
    }
    return 2
}

; ---- the mission / raid list (windowed). Rows are 61 px apart; the list scrolls by 240 px (4 rows visible of 8).
; The scroll handle sits right of the list: "top", "bottom", or "none" (raids list has none; or the middle).
ListThumb() {
    t := GoldAt(WX + 624, WY + 300, 1)
    b := GoldAt(WX + 624, WY + 445, 1)
    if (t && !b)
        return "top"
    if (b && !t)
        return "bottom"
    return "none"
}

RowTopY(idx, state) {
    return 252 + 61 * idx - ((state = "bottom") ? 240 : 0)
}

; The thin bright gold frame around the selected row.
FrameGold(c) {
    r := (c >> 16) & 0xFF
    g := (c >> 8) & 0xFF
    b := c & 0xFF
    return r >= 225 && g >= 160 && b <= 110 && (r - b) >= 130
}

; y (window-relative) where the frame of the selected row starts, -1 when no row is selected. Call inside WithSnap.
SelectedRowTop() {
    run := 0
    start := -1
    y := 250
    while (y <= 497) {
        hit := false
        for dx in [-1, 0, 1] {
            if FrameGold(Px(WX + 505 + dx, WY + y)) {
                hit := true
                break
            }
        }
        if hit {
            if (run = 0)
                start := y
            run += 1
            if (run >= 45)
                return start
        } else {
            run := 0
        }
        y += 1
    }
    return -1
}

; The list's header: "MAPS" (missions) or "RAID".
MapsHdr() {
    static mp := ParsePts("539,229;586,239;538,241;576,233;585,229;539,235;585,236;539,232")
    static rp := ParsePts("544,229;575,241;572,239;572,241;573,240;545,229;573,239;572,240")
    a := SigHits(mp)
    b := SigHits(rp)
    if (a >= 6 && b <= 3)
        return "maps"
    if (b >= 6 && a <= 3)
        return "raid"
    return ""
}

; Which screen of the mission / raid picker is this, for the mission / raid that is selected in the app?
;   map / mapok = missions list (wanted one not / is selected), raid / raidok = same for the raids list,
;   mapwrong = the other kind of list is open (press BACK).
MapScreenKind() {
    global CurMap
    wantRaid := IsRaidMap(CurMap)
    hdr := MapsHdr()
    if (hdr = "")
        hdr := wantRaid ? "raid" : "maps"
    if (wantRaid != (hdr = "raid"))
        return "mapwrong"
    idx := MapRowIdx(CurMap)
    low := (!wantRaid && idx >= 4)
    th := ListThumb()
    top := SelectedRowTop()
    state := low ? "bottom" : "top"
    ok := (top >= 0 && Abs(top - RowTopY(idx, state)) <= 14 && (low ? (th = "bottom") : (th != "bottom")))
    if (!ok && CurMap = "Outskirts" && TitleOkWin())
        ok := true
    if wantRaid
        return ok ? "raidok" : "raid"
    return ok ? "mapok" : "map"
}

; Gold buttons along the bottom of the left panel: [[x1, x2], ...] (window-relative), left to right. Call inside WithSnap.
PillRuns() {
    out := []
    y := WY + 476
    s := 0
    x := WX + 190
    xe := WX + 640
    while (x <= xe) {
        if GoldD(Px(x, y)) {
            if !s
                s := x
        } else if s {
            if (x - s >= 50)
                out.Push([s - WX, x - 1 - WX])
            s := 0
        }
        x += 1
    }
    if (s && xe - s >= 50)
        out.Push([s - WX, xe - WX])
    ; A dark pill (the mouse is on it) shows white letters instead: find those too and treat the letters' middle as the pill's.
    s := 0
    last := 0
    x := WX + 190
    while (x <= xe + 12) {
        w := false
        if (x <= xe) {
            yy := WY + 478
            while (yy <= WY + 486) {
                if (ColorSum(Px(x, yy)) > 650) {
                    w := true
                    break
                }
                yy += 1
            }
        }
        if w {
            if !s
                s := x
            last := x
        } else if (s && x - last > 10) {
            if (last - s >= 18 && last - s <= 60) {
                mid := (s + last) // 2 - WX
                dup := false
                for r in out {
                    if (mid >= r[1] - 4 && mid <= r[2] + 4)
                        dup := true
                }
                if !dup
                    out.Push([mid - 36, mid + 36])
            }
            s := 0
        }
        x += 1
    }
    ; left to right
    n := out.Length
    i := 1
    while (i < n) {
        k := 1
        while (k <= n - i) {
            if (out[k][1] > out[k + 1][1]) {
                t := out[k]
                out[k] := out[k + 1]
                out[k + 1] := t
            }
            k += 1
        }
        i += 1
    }
    return out
}

; Clicks the wanted mission / raid in its list (scrolling the missions list first when it is one of the lower ones).
SelectMapRow() {
    global CurMap
    raid := IsRaidMap(CurMap)
    idx := MapRowIdx(CurMap)
    need := (!raid && idx >= 4) ? "bottom" : "top"
    th := WithSnap(ListThumb)
    if (th = "")
        th := "none"
    if (!raid && th != need) {
        RejoinLog("map list is at '" th "', scrolling to '" need "'")
        MouseMove WX + 562, WY + 380, 0
        Sleep 80
        MouseMove WX + 566, WY + 384, 0
        Sleep 60
        keys := (need = "bottom") ? "{WheelDown 10}" : "{WheelUp 10}"
        Send keys
        Sleep 400
        return
    }
    ClickAt(WX + 562, WY + RowTopY(idx, need) + 28)
    RejoinLog("clicked " CurMap " in the list")
}

; BACK = the left-most gold button of the left panel.
BackPill() {
    runs := WithSnap(PillRuns)
    if (IsObject(runs) && runs.Length >= 1) {
        r := runs[1]
        ClickAt(WX + (r[1] + r[2]) // 2, WY + 481)
    } else {
        ClickAt(WX + 244, WY + 481)
    }
}

; Raid list: CREATE is the right-most gold button. With only BACK on screen it is not there (yet).
RaidCreate(st) {
    runs := WithSnap(PillRuns)
    n := IsObject(runs) ? runs.Length : 0
    if (n < 2) {
        st["noCreate"] += 1
        RejoinLog("raid: no CREATE button yet (" n " button(s) on screen, try " st["noCreate"] ")")
        if (st["noCreate"] = 1 || Mod(st["noCreate"], 3) = 0)
            SelectMapRow()                 ; click the raid again: the buttons may only show after a click
        return
    }
    r := runs[n]
    ClickAt(WX + (r[1] + r[2]) // 2, WY + 481)
    st["raidCreated"] := A_TickCount
    st["rl"] := 0
    RejoinLog("raid: pressed the right-most button (CREATE)")
}

; ---- small screen grabs (about 1 ms): used by the cutscene skipper and the chest handler ----
GrabRect(x0, y0, w, h) {
    sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    mdc := DllCall("CreateCompatibleDC", "Ptr", sdc, "Ptr")
    bi := Buffer(40, 0)
    NumPut("UInt", 40, bi, 0)
    NumPut("Int", w, bi, 4)
    NumPut("Int", -h, bi, 8)
    NumPut("UShort", 1, bi, 12)
    NumPut("UShort", 32, bi, 14)
    bits := 0
    hbm := DllCall("CreateDIBSection", "Ptr", mdc, "Ptr", bi, "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
    if !hbm {
        DllCall("DeleteDC", "Ptr", mdc)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
        return 0
    }
    obm := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
    ok := DllCall("BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", w, "Int", h
        , "Ptr", sdc, "Int", x0, "Int", y0, "UInt", CapRop)
    DllCall("SelectObject", "Ptr", mdc, "Ptr", obm)
    DllCall("DeleteDC", "Ptr", mdc)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
    if !ok {
        DllCall("DeleteObject", "Ptr", hbm)
        return 0
    }
    return {hbm: hbm, bits: bits, w: w, h: h, x0: x0, y0: y0}
}

FreeGrab(gr) {
    if IsObject(gr)
        DllCall("DeleteObject", "Ptr", gr.hbm)
}

GrabPx(gr, x, y) {
    cx := x - gr.x0
    cy := y - gr.y0
    if (cx < 0 || cy < 0 || cx >= gr.w || cy >= gr.h)
        return 0
    return NumGet(gr.bits, (cy * gr.w + cx) * 4, "UInt") & 0xFFFFFF
}

GrabSum(c) {
    return ((c >> 16) & 0xFF) + ((c >> 8) & 0xFF) + (c & 0xFF)
}

; gold pixel within rad of (x, y)?
GrabGold(gr, x, y, rad := 1) {
    dx := -rad
    while (dx <= rad) {
        dy := -rad
        while (dy <= rad) {
            if GoldD(GrabPx(gr, x + dx, y + dy))
                return true
            dy += 1
        }
        dx += 1
    }
    return false
}

; any dark pixel in columns xa..xb of row y (button text on the gold)?
GrabDarkAny(gr, xa, xb, y) {
    x := xa
    while (x <= xb) {
        if (GrabSum(GrabPx(gr, WX + x, WY + y)) < 330)
            return true
        x += 1
    }
    return false
}

; ---- raid cutscene: the "SKIP [E]" box (bottom right): a thin gold frame around a black box ----
; The SKIP [E] frame pulses: at its dimmest it is a greyish gold such as (122,116,88), so the test is loose.
SkipGold(gr, x, y, rad := 1) {
    dx := -rad
    while (dx <= rad) {
        dy := -rad
        while (dy <= rad) {
            c := GrabPx(gr, x + dx, y + dy)
            r := (c >> 16) & 0xFF
            g := (c >> 8) & 0xFF
            b := c & 0xFF
            if (r >= 100 && g >= 85 && r - b >= 28 && r >= g)
                return true
            dy += 1
        }
        dx += 1
    }
    return false
}

SkipDim(c) {
    r := (c >> 16) & 0xFF
    g := (c >> 8) & 0xFF
    b := c & 0xFF
    return (r >= 85 && g >= 70 && r - b >= 25 && r >= g - 6)
}

; Structure only, no colours (the frame colour changes with the pulse and the compression): a black box with a brighter line just
; outside both sides, black corners and the grey text SKIP [E] inside. Checked on every cutscene screenshot, no false hit elsewhere.
SkipOkShape(gr) {
    L := 0
    R := 0
    y := 596
    while (y <= 612) {
        if (GrabSum(GrabPx(gr, WX + 711, WY + y)) < 90) {
            x := 704
            while (x <= 709) {
                if (GrabSum(GrabPx(gr, WX + x, WY + y)) >= 190) {
                    L += 1
                    break
                }
                x += 1
            }
        }
        if (GrabSum(GrabPx(gr, WX + 784, WY + y)) < 90) {
            x := 786
            while (x <= 791) {
                if (GrabSum(GrabPx(gr, WX + x, WY + y)) >= 190) {
                    R += 1
                    break
                }
                x += 1
            }
        }
        y += 2
    }
    if (L < 7 || R < 7)
        return false
    d := 0
    for q in [[720, 598], [770, 598], [715, 610], [780, 610], [745, 597], [745, 612]] {
        if (GrabSum(GrabPx(gr, WX + q[1], WY + q[2])) < 90)
            d += 1
    }
    if (d < 4)
        return false
    t := 0
    y := 597
    while (y <= 611) {
        x := 722
        while (x <= 771) {
            if (GrabSum(GrabPx(gr, WX + x, WY + y)) >= 230)
                t += 1
            x += 1
        }
        y += 1
    }
    return t >= 40
}

SkipOk(gr) {
    if SkipOkShape(gr)
        return true
    ; The frame pulses and the picture is often blurry, so the test uses the two SIDE lines (any gold in a 4 px wide strip,
    ; per row) and only needs most rows; the top and bottom lines are not used (the word SKIP and the glow break them up).
    L := 0
    R := 0
    y := 596
    while (y <= 612) {
        x := 706
        while (x <= 709) {
            if SkipGold(gr, WX + x, WY + y, 0) {
                L += 1
                break
            }
            x += 1
        }
        x := 787
        while (x <= 790) {
            if SkipGold(gr, WX + x, WY + y, 0) {
                R += 1
                break
            }
            x += 1
        }
        y += 2
    }
    if (L < 7 || R < 7) {
        ; dim frame (the pulse): still the same picture - a black box (dark 3 px inside both sides) with a faint tan rim just outside
        L := 0
        R := 0
        y := 596
        while (y <= 612) {
            if (GrabSum(GrabPx(gr, WX + 711, WY + y)) < 90) {
                x := 705
                while (x <= 709) {
                    if SkipDim(GrabPx(gr, WX + x, WY + y)) {
                        L += 1
                        break
                    }
                    x += 1
                }
            }
            if (GrabSum(GrabPx(gr, WX + 784, WY + y)) < 90) {
                x := 786
                while (x <= 790) {
                    if SkipDim(GrabPx(gr, WX + x, WY + y)) {
                        R += 1
                        break
                    }
                    x += 1
                }
            }
            y += 2
        }
        if (L < 7 || R < 7)
            return false
    }
    d := 0
    for q in [[720, 598], [770, 598], [715, 610], [780, 610], [745, 597], [745, 612]] {
        if (GrabSum(GrabPx(gr, WX + q[1], WY + q[2])) < 90)
            d += 1
    }
    return d >= 4
}

; Looks for the SKIP [E] box; when it is there: E, a click on the button, E again. Used by the timer AND by the rejoin's wait loop
; (so the skip never depends on a timer getting its turn while the rejoin is busy).
; E three ways at once (normal send, hardware-style send, straight into the Roblox window): one of them always gets through.
SkipKey() {
    ex := "ahk_exe " RobloxExe()
    Send "{e down}"
    try ControlSend("{e down}", , ex)
    SendEvent "{e down}"
    Sleep 20
    Send "{e up}"
    try ControlSend("{e up}", , ex)
    SendEvent "{e up}"
}

SkipLook() {
    global WinMode, WW, WX, WY, CurMap
    static lastPress := 0
    static n := 0
    if (!WinMode || WW <= 0)       ; no map / paused / rejoin checks: if the button is on screen it gets pressed, whatever the state
        return false
    gr := GrabRect(WX + 700, WY + 590, 96, 30)
    if !IsObject(gr)
        return false
    ok := false
    try ok := SkipOk(gr)
    FreeGrab(gr)
    if !ok {
        if (n > 0)
            RejoinLog("SKIP [E] box gone after " n " look(s)")
        if (n > 0 && (DuoActive() || SoloActive()))
            SetTimer(DuoTabCheck, -700)        ; duo: after the skip, look at the TAB list: is the 2nd player still here?
        n := 0
        return false
    }
    n += 1
    if (A_TickCount - lastPress >= 150) {
        lastPress := A_TickCount
        try {
            if !WinActive("ahk_exe " RobloxExe())    ; the key only works while Roblox has the focus
                WinActivate("ahk_exe " RobloxExe())
        }
        if (n = 1 || n = 6)
            RejoinLog("SKIP [E] seen (" n "): pressing E and clicking the button; Roblox in front: " (WinActive("ahk_exe " RobloxExe()) ? "yes" : "no"))
        try SkipKey()                        ; ONE quick E (about 25 ms): the macro keeps its timing
        ; The click is only a back-up when E did not work (3rd look on): a click lands in the game if the cutscene is already over,
        ; so the box is checked again right before it.
        if (n >= 3 && n <= 5) {
            g2 := GrabRect(WX + 700, WY + 590, 96, 30)
            ok2 := false
            if IsObject(g2) {
                try ok2 := SkipOk(g2)
                FreeGrab(g2)
            }
            if ok2
                try FastClick(WX + 748, WY + 605)
        }
    }
    return true
}

SkipTick() {
    global WinMode, WW, WX, WY, CurMap, ScriptPaused, busyReconnect, AutoStartEnd, RaidWaiting, MacroPlaying
    static lastPress := 0
    static seenN := 0
    if (!WinMode || WW <= 0) {   ; nothing else blocks it (not the map, not pause, not a rejoin in progress)
        seenN := 0
        return
    }
    ok := false
    try ok := SkipLook()
    if ok {
        seenN += 1
        return
    }
    if (seenN >= 2 && RaidWaiting && !ScriptPaused && IsRaidMap(CurMap)) {       ; the cutscene is over and the macro is still waiting for OBJECTIVES: start it NOW
        seenN := 0
        r := ""
        try r := FastStartMain()
        RejoinLog("cutscene skipped: macro started at once (F8: " r ")")
        return
    }
    seenN := 0
}

; ---- "Would you like to rejoin the last match you disconnected from?" -> NO, always ----
PromptGold(gr, x, y, rad) {
    dx := -rad
    while (dx <= rad) {
        dy := -rad
        while (dy <= rad) {
            if InjGold(gr, x + dx, y + dy)
                return true
            dy += 1
        }
        dx += 1
    }
    return false
}

; True while the "Would you like to rejoin the last match you disconnected from?" pop-up is showing.
PromptVisible() {
    global WinMode, WW, WX, WY
    if (!WinMode || WW <= 0)
        return false
    gr := GrabRect(WX + 280, WY + 308, 245, 104)
    if !IsObject(gr)
        return false
    fr := 0
    for q in [[300, 314], [350, 314], [400, 314], [450, 314], [500, 314], [300, 406], [350, 406], [400, 406], [450, 406], [500, 406], [286, 340], [286, 380], [516, 340], [516, 380]] {
        if PromptGold(gr, q[1], q[2], 1)
            fr += 1
    }
    pl := 0
    if (fr >= 13) {
        for q in [[340, 391], [360, 391], [380, 391], [420, 391], [440, 391], [460, 391]] {
            if InjGold(gr, q[1], q[2])
                pl += 1
        }
    }
    FreeGrab(gr)
    return (fr >= 13 && pl >= 5)
}

PromptTick() {
    global ScriptPaused
    static last := 0
    if (ScriptPaused || A_TickCount - last < 2500)
        return
    if PromptVisible() {
        last := A_TickCount
        RejoinLog("popup 'rejoin the last match?': pressing NO")
        ClickAt(WX + 361, WY + 391)
    }
}

; ---- injuries: after a round the end panel can move up ~12 px and a gold HEAL button appears under it ----
; Plan: click HEAL, then click the TOP heal button of the INJURIES list again and again (a "Healed ..." text pops up, clicking closes it)
; until the list is empty, press the X, then the normal RETRY logic takes over. All positions are window coordinates.
InjGold(gr, x, y) {
    c := GrabPx(gr, WX + x, WY + y)
    r := (c >> 16) & 0xFF
    g := (c >> 8) & 0xFF
    b := c & 0xFF
    return (r >= 110 && g >= 70 && r - b >= 45 && r >= g)
}

InjWhiteN(gr, x1, y1, x2, y2) {
    n := 0
    y := y1
    while (y <= y2) {
        x := x1
        while (x <= x2) {
            c := GrabPx(gr, WX + x, WY + y)
            r := (c >> 16) & 0xFF
            g := (c >> 8) & 0xFF
            b := c & 0xFF
            lo := Min(r, g, b)
            hi := Max(r, g, b)
            if (lo >= 190 && hi - lo < 45)
                n += 1
            x += 1
        }
        y += 1
    }
    return n
}

; 0 = nothing, 1 = end panel with the gold HEAL button, 2 = end panel with HEAL under the mouse (dark), 3 = INJURIES list (row1: has a heal button)
; Only small pieces of the screen are copied (a few thousand pixels), so this never slows the end-screen watcher down.
InjuryLook(&row1) {
    row1 := false
    ; the INJURIES list: gold frame of the X box (top right)
    gx := GrabRect(WX + 760, WY + 44, 34, 32)
    if !IsObject(gx)
        return 0
    xs := 0
    for q in [[765, 55], [765, 65], [788, 55], [788, 65], [772, 48], [782, 48], [772, 71], [782, 71]] {
        if InjGold(gx, q[1], q[2])
            xs += 1
    }
    FreeGrab(gx)
    if (xs >= 7) {
        g2 := GrabRect(WX + 460, WY + 204, 95, 24)
        if IsObject(g2) {
            g1 := 0
            for x in [470, 480, 490, 500, 510, 520, 530, 540] {
                for y in [209, 215, 221] {
                    if InjGold(g2, x, y)
                        g1 += 1
                }
            }
            row1 := (g1 >= 12 || InjWhiteN(g2, 495, 206, 551, 225) >= 30)   ; (the "No injuries to display..." text ends left of x 490)
            FreeGrab(g2)
        }
        return 3
    }
    ; the end panel: the three gold buttons in a row (y 452) and HEAL below them
    g3 := GrabRect(WX + 222, WY + 448, 306, 52)
    if !IsObject(g3)
        return 0
    res := 0
    rb := 0
    for x in [290, 320, 380, 410, 470, 500] {
        if InjGold(g3, x, 452)
            rb += 1
    }
    if (rb >= 3) {
        hg := 0
        for x in [240, 248, 256, 264, 272, 280, 288, 296, 304] {
            for y in [478, 483, 488] {
                if InjGold(g3, x, y)
                    hg += 1
            }
        }
        per := 0
        for q in [[226, 483], [322, 483], [250, 471], [290, 471], [250, 496], [290, 496]] {
            if InjGold(g3, q[1], q[2])
                per += 1
        }
        if (hg >= 24 && per <= 1)
            res := 1
        else if (per <= 1 && InjWhiteN(g3, 240, 477, 309, 489) >= 35)
            res := 2
    }
    FreeGrab(g3)
    return res
}

; "YOU DIED" (big dark-red text in the middle of the screen). With the Fritz setting ON the macro is restarted 1.5 s after it shows
; (Fritz comes back with a revive, but the running macro is out of step by then).
DeathLook() {
    global WX, WY
    gr := GrabRect(WX + 240, WY + 298, 320, 64)
    if !IsObject(gr)
        return false
    n := 0
    y := WY + 300
    while (y <= WY + 360) {
        x := WX + 244
        while (x <= WX + 556) {
            c := GrabPx(gr, x, y)
            r := (c >> 16) & 0xFF
            g := (c >> 8) & 0xFF
            b := c & 0xFF
            if (r >= 60 && r <= 150 && g <= 35 && b <= 50 && r - g >= 45 && r - b >= 35)
                n += 1
            x += 2
        }
        y += 2
    }
    FreeGrab(gr)
    if (n < 700)             ; the text gives about 900 of these points on the sampled grid
        return false
    ; the end / chest / injury screens have a dark-red background too: here the rest of the window must NOT be red
    red := 0
    for q in [[100, 200], [700, 200], [100, 500], [700, 500], [400, 560], [400, 200], [150, 350], [650, 350]] {
        c := Px(WX + q[1], WY + q[2])
        r := (c >> 16) & 0xFF
        g := (c >> 8) & 0xFF
        b := c & 0xFF
        if (r >= 35 && r - g >= 22 && r - b >= 22)
            red += 1
    }
    return red <= 1
}

DeathTick() {
    global WinMode, WW, FritzRevive, ScriptPaused, busyReconnect
    static seenAt := 0
    static lastRestart := 0
    if (!FritzRevive || !WinMode || WW <= 0 || ScriptPaused || busyReconnect) {
        seenAt := 0
        return
    }
    if (A_TickCount - lastRestart < 12000)       ; the text lingers: one restart per death
        return
    d := false
    try d := DeathLook()
    if (seenAt = 0) {
        if d {
            seenAt := A_TickCount
            RejoinLog("YOU DIED seen: Fritz setting is ON, restarting the macro in 1.5 s")
        }
        return
    }
    if (!d && A_TickCount - seenAt < 500) {      ; a flicker, not the real thing
        seenAt := 0
        return
    }
    if (A_TickCount - seenAt >= 1500) {          ; 1.5 s after it showed up (even if the text is gone by now: the revive happened)
        seenAt := 0
        lastRestart := A_TickCount
        try {
            if EndScreen()                       ; the round is over: the normal retry flow handles it
                return
        }
        RejoinLog("YOU DIED: restarting the macro now")
        try RestartMain()
    }
}

InjuryTick() {
    global WinMode, WW, WX, WY, ScriptPaused, busyReconnect, AutoStartEnd, HealInjuries
    static st := 0            ; 0 idle, 1 healing
    static clicks := 0
    static lastClick := 0
    static emptyN := 0
    static blind := 0
    static startT := 0
    static lastSeen := 0
    static retryT := 0
    if (!WinMode || WW <= 0 || ScriptPaused || busyReconnect || !AutoStartEnd || !HealInjuries)
        return
    now := A_TickCount
    SetTimer(InjuryTick, (st = 1) ? 90 : 300)   ; quiet while nothing is wrong, fast while healing
    kind := 0
    row1 := false
    try kind := InjuryLook(&row1)
    if (kind > 0)
        lastSeen := now
    if (st = 1 && now - startT > 40000) {         ; far too long: stop healing, press RETRY straight away
        st := 0
        RejoinLog("injuries: gave up after " clicks " clicks")
        if (kind >= 1 && kind <= 2)
            ClickAt(WX + 491, WY + 452)
        return
    }
    if (st = 0 && kind = 0) {
        if (lastSeen && now - lastSeen > 20000) {
            clicks := 0
            lastSeen := 0
        }
        return
    }
    if (now - lastClick < 220)
        return
    if (kind = 1 || kind = 2) {
        if (clicks >= 16) {                       ; healing does not work: just retry
            if (now - retryT > 3000) {
                retryT := now
                RejoinLog("injuries: too many clicks, pressing RETRY")
                ClickAt(WX + 491, WY + 452)
            }
            return
        }
        if (st = 0) {
            st := 1
            startT := now
            emptyN := 0
            blind := 0
            RejoinLog("injuries: end screen with HEAL button, healing")
        }
        clicks += 1
        lastClick := now
        HealClick(WX + 275, WY + 483)
        return
    }
    if (kind = 3) {
        if (st = 0) {
            st := 1
            startT := now
            blind := 0
        }
        blind := 0
        if row1 {
            emptyN := 0
            if (clicks >= 16) {                   ; healing never ends: close the list
                RejoinLog("injuries: too many clicks, closing the list (X)")
                lastClick := now
                st := 0
                ClickAt(WX + 777, WY + 60)
                return
            }
            clicks += 1
            lastClick := now
            HealClick(WX + 507, WY + 215)
            return
        }
        emptyN += 1
        if (emptyN >= 2) {
            RejoinLog("injuries: none left, closing the list (X)")
            lastClick := now
            emptyN := 0
            st := 0
            ClickAt(WX + 777, WY + 60)
        }
        return
    }
    ; healing, but neither the list nor the end panel is visible: most likely the "Healed ..." text; a click closes it
    if (st = 1) {
        if (blind < 3) {
            blind += 1
            lastClick := now
            HealClick(WX + 507, WY + 215)
        } else if (blind >= 3 && now - lastClick > 2500) {
            st := 0
        }
    }
}

; A click for the healing buttons. The same spot is clicked again and again: when the mouse is already there the hover is done, so only
; the press is needed (about 55 ms instead of ~250 ms). From anywhere else the normal click with a hover is used.
HealClick(x, y) {
    MouseGetPos(&mx, &my)
    if (Abs(mx - x) <= 3 && Abs(my - y) <= 3) {
        Click "Down"
        Sleep 20
        Click "Up"
        Sleep 20
    } else {
        ClickAt(x, y)
    }
}

; ---- raid chests: two chests with a gold OPEN button each and FINISH at the bottom ----
ChestsOk(gr) {
    ; the gold line under the word CHESTS ...
    t := 0
    for x in [340, 360, 380, 400, 420, 440, 460] {
        if GrabGold(gr, WX + x, WY + 95, 0)
            t += 1
    }
    if (t < 6)
        return false
    ; ... the dark red background between the chests. A bright flash over the whole screen (a titan transformation, a nuke) turns the
    ; gold points on as well, but never leaves this background dark.
    dk := 0
    for q in [[300, 180], [500, 180], [400, 300], [400, 400], [600, 200], [200, 200]] {
        c := GrabPx(gr, WX + q[1], WY + q[2])
        if (((c >> 16) & 0xFF) < 130 && ((c >> 8) & 0xFF) < 80)
            dk += 1
    }
    if (dk < 5)
        return false
    ; ... and the FINISH button at the bottom
    b := 0
    for y in [600, 617] {
        for x in [370, 390, 410, 430] {
            if GrabGold(gr, WX + x, WY + y, 0)
                b += 1
        }
    }
    return (b >= 7 || WhiteText(gr, 372, 600, 430, 618) >= 20)   ; FINISH is gold, or dark with white letters while the mouse is on it
}

; White letters on a dark button (a hovered pill): how many white pixels are in the area (window coordinates).
WhiteText(gr, x1, y1, x2, y2) {
    n := 0
    y := y1
    while (y <= y2) {
        x := x1
        while (x <= x2) {
            if (GrabSum(GrabPx(gr, WX + x, WY + y)) > 600)
                n += 1
            x += 1
        }
        y += 1
    }
    return n
}

; The gold OPEN button of the left chest (it disappears once that chest is opened).
ChestLeftOn(gr) {
    n := 0
    for y in [443, 458] {
        for x in [220, 235, 250, 262] {
            if GrabGold(gr, WX + x, WY + y, 0)
                n += 1
        }
    }
    return (n >= 7 || WhiteText(gr, 212, 444, 270, 456) >= 25)
}

ChestRightOn(gr) {
    n := 0
    for y in [443, 458] {
        for x in [540, 555, 570, 582] {
            if GrabGold(gr, WX + x, WY + y, 0)
                n += 1
        }
    }
    return (n >= 6 || WhiteText(gr, 532, 444, 590, 456) >= 25)
}

; True when the right button says OPEN (0): one single digit left of the ")" and it is a "0" (a ring: dark left and
; right edges, empty middle, dark top and bottom). Anything unclear counts as "has keys" (False).
KeysZero(gr) {
    cols := []
    x := 533
    while (x <= 589) {
        d := false
        y := 446
        while (y <= 457) {
            if (GrabSum(GrabPx(gr, WX + x, WY + y)) < 330) {
                d := true
                break
            }
            y += 1
        }
        cols.Push(d)
        x += 1
    }
    i := cols.Length                       ; cols[i] is the screen column 532 + i
    while (i >= 1 && !cols[i])
        i -= 1
    if (i < 12)
        return false
    while (i >= 1 && cols[i])              ; the ")" glyph
        i -= 1
    while (i >= 1 && !cols[i])
        i -= 1
    dEnd := i
    while (i >= 1 && cols[i])
        i -= 1
    dStart := i + 1
    if (dEnd < 1)
        return false
    bx1 := 532 + dEnd
    bx0 := bx1 - 6
    if (dEnd - dStart + 1 < 8) {            ; narrow: a digit standing apart. Alone only if a "(" (narrow, with a tail) is left of it
        while (i >= 1 && !cols[i])
            i -= 1
        pEnd := i
        while (i >= 1 && cols[i])
            i -= 1
        pStart := i + 1
        if (pEnd < 1 || pEnd - pStart + 1 > 4)
            return false
        tail := false
        x := 532 + pStart
        while (x <= 532 + pEnd) {
            if (GrabSum(GrabPx(gr, WX + x, WY + 457)) < 330 || GrabSum(GrabPx(gr, WX + x, WY + 456)) < 330)
                tail := true
            x += 1
        }
        if !tail
            return false
        bx0 := 532 + dStart
        if (bx1 - bx0 < 5)
            return false
    }
    left := 0
    right := 0
    y := 446
    while (y <= 455) {
        if GrabDarkAny(gr, bx0, bx0 + 1, y)
            left += 1
        if GrabDarkAny(gr, bx1 - 1, bx1, y)
            right += 1
        y += 1
    }
    if (left < 7 || right < 7)
        return false
    y := 449
    while (y <= 452) {
        if GrabDarkAny(gr, bx0 + 2, bx1 - 2, y)
            return false
        y += 1
    }
    top := GrabDarkAny(gr, bx0 + 2, bx1 - 2, 446) || GrabDarkAny(gr, bx0 + 2, bx1 - 2, 447)
    bot := GrabDarkAny(gr, bx0 + 2, bx1 - 2, 454) || GrabDarkAny(gr, bx0 + 2, bx1 - 2, 455)
    return top && bot
}

; Runs every 250 ms in a raid and just follows what is on screen: left OPEN button there = press it; then the key chest
; (switch ON, button gold, not "(0)"); nothing left to open = FINISH right away. Waits 2.5 s after each press (reveal).
ChestTick() {
    global WinMode, WW, WX, WY, CurMap, ScriptPaused, busyReconnect, AutoStartEnd, KeyChest
    global ChestLastSeen, ChestLeftN, ChestRightN, ChestClickT
    static lastFinish := 0
    static busy := false                   ; (PlayStep calls this too: never two at once)
    static seenN := 0                      ; how many looks in a row showed the chests (2 looks since the last raid = sure, then the macro is stopped; a look without chests does NOT reset it, the chests flicker while they open)
    static stopped := false
    if (busy || !WinMode || WW <= 0 || ScriptPaused || busyReconnect || !AutoStartEnd || !IsRaidMap(CurMap))
        return
    busy := true
    try ChestTickBody(&seenN, &stopped, &lastFinish)
    busy := false
}

ChestTickBody(&seenN, &stopped, &lastFinish) {
    global WinMode, WW, WX, WY, CurMap, KeyChest
    global ChestLastSeen, ChestLeftN, ChestRightN, ChestClickT
    seen := false
    leftOn := false
    rightOn := false
    zero := false
    gr := GrabRect(WX + 200, WY + 60, 400, 566)
    if IsObject(gr) {
        try {
            seen := ChestsOk(gr)
            if seen {
                leftOn := ChestLeftOn(gr)
                rightOn := ChestRightOn(gr)
                if rightOn
                    zero := KeysZero(gr)
            }
        }
        FreeGrab(gr)
    }
    now := A_TickCount
    SetTimer(ChestTick, seen ? 50 : 150)   ; quiet while there are no chests: the app's own buttons must stay responsive
    if !seen {
        if (ChestLastSeen && now - ChestLastSeen > 25000) {
            seenN := 0                       ; a new raid: the stop works again
            stopped := false
            ChestLastSeen := 0               ; a new raid: start counting again
            ChestLeftN := 0
            ChestRightN := 0
        }
        return
    }
    ChestLastSeen := now
    seenN += 1
    if (seenN >= 1 && !stopped) {          ; the round is over: the macro's keys are useless now, stop it before anything else
        stopped := true
        try {
            if MacroPlaying
                PlayStop()
            else
                StopMainForRetry()         ; TinyTask: F8 if it is running
        }
        RejoinLog("chests: macro stopped")
    }
    if (now - ChestClickT < 800)
        return
    if (leftOn && ChestLeftN < 4) {
        ChestLeftN += 1
        RejoinLog("chests: opening the left chest (" ChestLeftN ")")
        ChestClick(WX + 241, WY + 450)
        ChestClickT := A_TickCount
        return
    }
    if (rightOn && KeyChest && !zero && ChestRightN < 4) {
        ChestRightN += 1
        RejoinLog("chests: opening the key chest (" ChestRightN ")")
        ChestClick(WX + 561, WY + 450)
        ChestClickT := A_TickCount
        return
    }
    if (now - lastFinish < 450)
        return
    lastFinish := now
    RejoinLog("chests: pressing FINISH" (rightOn ? (!KeyChest ? " (key chest switch is OFF)" : (zero ? " (0 keys)" : "")) : ""))
    ChestClick(WX + 401, WY + 609)
}

MapAvail(name) {
    for m in MapList {
        if (m[1] = name)
            return m[3]
    }
    return false
}

MapMacroGet(name) {
    return IniRead(IniFile, "maps", "Macro_" . name, "")
}

; Selects a mission / raid. Returns false (and says Coming Soon) when it is not supported yet.
MapSelect(name) {
    global CurMap
    if !MapAvail(name) {
        ToolTip("Coming Soon: " . name . " is not supported yet.", TipX(), TipY(10))
        SetTimer(() => ToolTip(), -2500)
        return false
    }
    CurMap := name
    try IniWrite(name, IniFile, "maps", "Active")
    ModLoadFor(name)                       ; each mission / raid keeps its own modifiers
    try LayoutLeft()
    m := MapMacroGet(name)
    if (m != "") {
        if MacroPlaying
            PlayStop()
        MacroSetActive(m)
    } else if (MacroActive != "") {
        MacroSetActive(MacroActive)        ; first time: use the macro that is selected now
    }
    RejoinLog("mission / raid selected: " . name)
    return true
}

MapPicker() {
    global MapGui, MapStatus, CurMap, BtnMap
    try MapGui.Destroy()
    g := Gui("+AlwaysOnTop", "Choose mission / raid")
    MapGui := g
    g.BackColor := "11131A"
    g.MarginX := 0
    g.MarginY := 0
    g.SetFont("s10 cE8EAF0", "Segoe UI")
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "UInt", 20, "Int*", 1, "UInt", 4)
    y := 20
    for kind in ["Normal mission", "Raid"] {
        h := g.AddText(Format("x24 y{1} w380 h16 Background11131A c6B7185", y), (kind = "Raid") ? "RAIDS" : "NORMAL MISSIONS")
        h.SetFont("s8 Bold c6B7185", "Segoe UI")
        y += 26
        for m in MapList {
            if (m[2] = kind) {
                MapRow(g, m, y)
                y += 70
            }
        }
        y += 10
    }
    MapStatus := g.AddText(Format("x24 y{1} w380 h22 Background11131A c8A90A2", y), "Click a mission or raid to select it. Each one keeps its own macro.")
    MapStatus.SetFont("s9 Norm c8A90A2", "Segoe UI")
    y += 34
    cb := g.AddText(Format("x24 y{1} w380 h38 Center +0x200 +0x100 Background232734 cE8EAF0", y), "Close")
    cb.SetFont("s9 Norm cE8EAF0", "Segoe UI Semibold")
    cb.OnEvent("Click", (*) => g.Destroy())
    BtnMap[cb.Hwnd] := [cb, "232734", "2E3345"]
    g.OnEvent("Close", (*) => g.Destroy())
    g.Show(Format("w428 h{1}", y + 38 + 24))
}

MapRow(g, m, y) {
    global CurMap
    name := m[1]
    avail := m[3]
    sel := (CurMap = name)
    bg := sel ? "2A2417" : "1A1D27"
    mac := MapMacroGet(name)
    sub := avail ? ("Macro: " . (mac != "" ? mac : "none yet (record one)")) : "Not available yet"
    card := g.AddText(Format("x24 y{1} w380 h60 +0x100 Background{2}", y, bg), "")
    t1 := g.AddText(Format("x40 y{1} w230 h22 +0x100 Background{2} cE8EAF0", y + 9, bg), name)
    t1.SetFont("s10 Norm cE8EAF0", "Segoe UI Semibold")
    t2 := g.AddText(Format("x40 y{1} w250 h18 +0x100 Background{2} c8A90A2", y + 33, bg), sub)
    t2.SetFont("s8 Norm c8A90A2", "Segoe UI")
    bt := sel ? "SELECTED" : (avail ? "SELECT" : "COMING SOON")
    bc := sel ? "E9B44C" : (avail ? "4ADE80" : "FBBF24")
    t3 := g.AddText(Format("x290 y{1} w98 h22 Right +0x200 +0x100 Background{2} c{3}", y + 9, bg, bc), bt)
    t3.SetFont("s8 Bold c" . bc, "Segoe UI")
    for c in [card, t1, t2, t3]
        c.OnEvent("Click", (*) => MapClick(name))
}

MapClick(name) {
    global MapStatus
    if !MapAvail(name) {
        try MapStatus.Text := "Coming Soon: " . name . " is not supported yet."
        try MapStatus.SetFont("s9 Bold cFBBF24", "Segoe UI")
        ToolTip("Coming Soon", TipX(), TipY(10))
        SetTimer(() => ToolTip(), -2000)
        return
    }
    MapSelect(name)
    SetTimer(MapPicker, -30)               ; draw the list again with the new selection
}

; ===================== THE APP WINDOW (dark UI that wraps around the Roblox window) =====================
; Three panels: a bar above Roblox, a bar below it and a side panel next to it. They follow the Roblox window and never
; cover it (the script reads the screen, so nothing may sit on top of the game).
BuildApp() {
    global AppGui, LeftGui, TopGui, BotGui, SetGui, AppCtl, BtnMap, Toggles, HelpMap
    global AutoStartEnd, WinMode, PlayInsteadOfVip, ScriptPaused
    BtnMap := Map()
    Toggles := Map()
    HelpMap := Map()
    ; ---------- right panel: session, switches, macro ----------
    g := NewPanel()
    AppGui := g
    PanelLabel(g, "SESSION", 18, 14)
    AddTile(g, "t_wins", "WINS", 14, 34, 82, 58, "4ADE80")
    AddTile(g, "t_fails", "FAILS", 104, 34, 82, 58, "F87171")
    AddTile(g, "t_rate", "WIN RATE", 194, 34, 82, 58, "E8EAF0")
    AddTile(g, "t_scroll", "SCROLLS", 14, 100, 82, 58, "60A5FA")
    AddTile(g, "t_mythic", "MYTHIC", 104, 100, 82, 58, "FB7185")
    AddTile(g, "t_divine", "DIVINE", 194, 100, 82, 58, "C084FC")
    AddTile(g, "t_time", "SESSION", 14, 166, 82, 58, "E8EAF0")
    AddTile(g, "t_avg", "AVG ROUND", 104, 166, 82, 58, "E8EAF0")
    AddTile(g, "t_rph", "ROUNDS / H", 194, 166, 82, 58, "E8EAF0")
    sl := g.AddText("x14 y234 w262 h18 Center Background11131A cA3ABBE", "")
    sl.SetFont("s8 Norm cA3ABBE", "Segoe UI")
    AppCtl["s_line"] := sl
    PanelLabel(g, "SWITCHES  (click to turn ON / OFF)", 18, 268)
    AddToggle(g, "auto", "Auto retry and start", "Clicks RETRY for you  |  Ctrl+Shift+F8", 288, () => AutoStartEnd, SetAutoStart, 42)
    AddToggle(g, "play", "Join VIP server", "Joins your private server  |  Ctrl+Shift+F7", 334, () => UseVip, SetUseVip, 42, "Normal PLAY (public)", "Not your VIP server  |  Ctrl+Shift+F7")
    AddToggle(g, "pause", "Paused", "Stops everything  |  F3", 380, () => ScriptPaused, SetPaused, 42, "Running", "Press to pause everything  |  F3")
    AddToggle(g, "win", "Windowed mode", "Keep ON (small Roblox window)  |  no key", 426, () => WinMode, SetWinMode, 42, "Fullscreen mode (old)", "Turn ON for the small Roblox window")
    AddToggle(g, "built", "Use built-in macro", "Your recorded keys  |  F8 start / stop", 472, () => BuiltIn, SetBuiltIn, 42)
    AddToggle(g, "loop", "Loop macro: continuous", "Repeats until the round ends", 518, () => MacroLoopOn(), SetMacroLoop, 42, "Loop macro: fires once", "Plays one time per round")
    AppCtl["macro_lbl"] := PanelLabel(g, "MACRO FOR THIS MISSION", 18, 566)
    AddCard(g, 14, 586, 262, 38)
    AddBtn(g, Chr(9664), 14, 586, 38, 38, () => MacroCycle(-1))
    nm := g.AddText("x56 y586 w180 h38 Center +0x200 +0x100 Background1A1D27 cE8EAF0", "")
    nm.SetFont("s10 Norm cE8EAF0", "Segoe UI Semibold")
    nm.OnEvent("Click", (*) => MacroManager())
    AppCtl["m_name"] := nm
    AddBtn(g, Chr(9656), 238, 586, 38, 38, () => MacroCycle(1))
    AppCtl["m_rec"] := AddBtn(g, Chr(9679) . " Record", 14, 640, 82, 56, () => RecordToggle(), false, "F10")
    AppCtl["m_play"] := AddBtn(g, Chr(9654) . " Play", 104, 640, 82, 56, () => PlayToggle(), true, "F8")
    AddBtn(g, "Manage", 194, 640, 82, 56, () => MacroManager(), false, "presets")
    ; ---------- left panel: mission / raid, tools, what's new, guide ----------
    L := NewPanel()
    LeftGui := L
    PanelLabel(L, "MISSION / RAID", 18, 14)
    AddCard(L, 14, 34, 262, 46)
    mn := L.AddText("x14 y34 w176 h46 Center +0x200 +0x100 Background1A1D27 cE9B44C", "")
    mn.SetFont("s11 Norm cE9B44C", "Segoe UI Semibold")
    mn.OnEvent("Click", (*) => MapPicker())
    AppCtl["map_name"] := mn
    AddBtn(L, "Change", 196, 34, 80, 46, () => MapPicker())
    AddToggle(L, "key", "Open key chest", "Raids only: chest 2, if you have keys", 90, () => KeyChest, SetKeyChest, 44, "Skip key chest", "Chest 2 is not opened")
    AddToggle(L, "duo", "Duo raid", "Waits for a 2nd player. Same macro for both", 142, () => DuoRaid, SetDuo, 44, "Solo raid", "Turn ON to wait for a 2nd player")
    AddToggle(L, "host", "Duo: you are the Host", "You create the raid and press START", 194, () => DuoHost, SetDuoHost, 44, "Duo: you are the Joiner", "You join the topmost lobby")
    AddToggle(L, "role1", "Role: Beast (Kill Colossal)", "Only one role can be ON (no function yet)", 246, () => (ColossalRole = "Beast"), SetRoleBeast, 44)
    AddToggle(L, "role2", "Role: Colossal (Defend Eren)", "Only one role can be ON (no function yet)", 298, () => (ColossalRole = "Colossal"), SetRoleColossal, 44)
    PanelLabel(L, "TOOLS", 18, 152)
    AddBtn(L, "Modifiers", 14, 172, 127, 48, () => ModPicker(), false, "Ctrl+Shift+F6")
    AddBtn(L, "Settings", 149, 172, 127, 48, () => OpenSettings(), false, "webhook, VIP code")
    AddBtn(L, "Setup check", 14, 228, 127, 48, () => SetupCheck(), false, "F9")
    AddBtn(L, "Open log", 149, 228, 127, 48, () => OpenLog(), false, "for bug reports")
    PanelLabel(L, "WHAT'S NEW", 18, 296)
    AddCard(L, 14, 316, 262, 326)
    ct := L.AddText("x28 y328 w236 h304 +0x100 Background1A1D27 cE8EAF0", ChangelogText())
    ct.SetFont("s9 Norm cE8EAF0", "Segoe UI")
    AddBtn(L, "How to use  (full guide)", 14, 658, 262, 48, () => OpenGuide(), true, "F2")
    ; ---------- top bar ----------
    t := NewPanel()
    TopGui := t
    AddCard(t, 0, 0, 801, 38, "1A1D27")
    b := t.AddText("x16 y0 w240 h36 +0x200 Background1A1D27 cE9B44C", "THY HOZ's AOTR MACRO")
    b.SetFont("s11 Norm cE9B44C", "Segoe UI Semibold")
    t.AddText("x1 y36 w799 h2 Background6B5420")                  ; thin gold line under the title bar
    i := t.AddText("x262 y0 w172 h36 +0x200 Background1A1D27 cA3ABBE", "")
    i.SetFont("s9 Norm cA3ABBE", "Segoe UI")
    AppCtl["top_info"] := i
    AddBtn(t, "Rejoin now (Ctrl+Shift+F10)", 262, 6, 172, 26, () => TestAutoRejoin())
    AddBtn(t, "Quick start", 440, 6, 78, 26, () => QuickStart())
    AddBtn(t, "Guide (F2)", 525, 6, 94, 26, () => OpenGuide(), true)
    AddBtn(t, "Settings", 627, 6, 90, 26, () => OpenSettings())
    AddBtn(t, "Exit", 725, 6, 60, 26, () => ExitApp())
    ; ---------- bottom bar ----------
    u := NewPanel()
    BotGui := u
    AddCard(u, 0, 0, 801, 40, "1A1D27")
    s1 := u.AddText("x16 y0 w270 h40 +0x200 Background1A1D27 c4ADE80", "")
    s1.SetFont("s9 Norm c4ADE80", "Segoe UI Semibold")
    AppCtl["b_state"] := s1
    s2 := u.AddText("x290 y0 w230 h40 Center +0x200 Background1A1D27 cE8EAF0", "")
    s2.SetFont("s9 Norm cE8EAF0", "Segoe UI")
    AppCtl["b_screen"] := s2
    s3 := u.AddText("x525 y0 w260 h40 Right +0x200 Background1A1D27 c8A90A2", "")
    s3.SetFont("s9 Norm cA3ABBE", "Segoe UI")
    AppCtl["b_macro"] := s3
    BuildSettings()
    for p in [g, L, t, u]
        p.Show("NoActivate x0 y0 w" . ((p = g || p = L) ? 290 : 801) . " h" . ((p = g || p = L) ? 719 : (p = t ? 38 : 40)))
    for p in [g, L, t, u]
        RoundCorners(p)
    SetTimer(HoverTick, 100)
    try DockApp()
    try RecordLeft()
    try LayoutLeft()
    if (IniRead(IniFile, "app", "GuideSeen", "0") != "1") {   ; first start: show the guide
        try IniWrite("1", IniFile, "app", "GuideSeen")
        SetTimer(() => OpenGuide(1), -800)
    }
}

; ===================== QUICK START (the short version, for people who do not read) =====================
; Six steps, each with a live dot: green = done, amber = still to do. Buttons do the step for you where they can.
; The full guide is one click away and says so: this window is only the short version.
QuickStart() {
    global QsGui, QsRows
    try QsGui.Destroy()
    g := Gui("+AlwaysOnTop", "Quick start")
    QsGui := g
    g.BackColor := "11131A"
    g.MarginX := 0
    g.MarginY := 0
    g.SetFont("s10 cE8EAF0", "Segoe UI")
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "UInt", 20, "Int*", 1, "UInt", 4)
    h := g.AddText("x20 y14 w520 h30", "QUICK START")
    h.SetFont("s16 Bold cE9B44C", "Segoe UI")
    sub := g.AddText("x20 y46 w520 h22 cA3ABBE", "Do the amber steps from the top. Each dot turns green by itself when it is done.")
    sub.SetFont("s9 Norm cA3ABBE", "Segoe UI")
    QsRows := []
    steps := [
        ["Windows scale is 100%", "ok", ""],
        ["Roblox is open in its small window", "ok", ""],
        ["Pick your mission or raid", "ok", "Change"],
        ["Record your keys (one round)", "ok", "Record"],
        ["Turn on 'Use built-in macro'", "ok", "Turn on"],
        ["Press Play in the mission", "ok", "Play"]]
    y0 := 76
    for st in steps {
        dot := g.AddText(Format("x20 y{1} w28 h34 +0x200 Center cFBBF24", y0), Chr(9679))
        dot.SetFont("s16 Norm cFBBF24", "Segoe UI")
        ti := g.AddText(Format("x58 y{1} w350 h22 +0x200", y0), st[1])
        ti.SetFont("s11 Bold cE8EAF0", "Segoe UI")
        de := g.AddText(Format("x58 y{1} w350 h36 cA3ABBE", y0 + 22), "")
        de.SetFont("s9 Norm cA3ABBE", "Segoe UI")
        bt := ""
        if (st[3] != "") {
            bt := g.AddText(Format("x420 y{1} w120 h36 Center +0x200 +0x100 Background232734 cE8EAF0", y0 + 8), st[3])
            bt.SetFont("s9 Norm cE8EAF0", "Segoe UI Semibold")
            bt.OnEvent("Click", QsAction.Bind(st[3]))
            BtnMap[bt.Hwnd] := [bt, "232734", "2E3345"]
        }
        QsRows.Push([dot, ti, de, bt])
        y0 += 66
    }
    pr := g.AddText(Format("x20 y{1} w520 h20 cA3ABBE", y0 + 4), "")
    pr.SetFont("s9 Bold cA3ABBE", "Segoe UI")
    QsRows.Push(pr)
    note := g.AddText(Format("x20 y{1} w520 h58 cA3ABBE", y0 + 30), "This is only the short version. The full guide explains what to do when something goes wrong, how raids and the automatic rejoin work, and what every button does. Read it at least once.")
    note.SetFont("s9 Norm cA3ABBE", "Segoe UI")
    gb := g.AddText(Format("x20 y{1} w255 h40 Center +0x200 +0x100 BackgroundE9B44C c14161C", y0 + 96), "Read the full guide")
    gb.SetFont("s10 Norm c14161C", "Segoe UI Semibold")
    gb.OnEvent("Click", (*) => OpenGuide())
    BtnMap[gb.Hwnd] := [gb, "E9B44C", "F2C566"]
    cb := g.AddText(Format("x285 y{1} w255 h40 Center +0x200 +0x100 Background232734 cE8EAF0", y0 + 96), "Close")
    cb.SetFont("s10 Norm cE8EAF0", "Segoe UI Semibold")
    cb.OnEvent("Click", (*) => QsClose())
    BtnMap[cb.Hwnd] := [cb, "232734", "2E3345"]
    g.OnEvent("Close", (*) => QsClose())
    QsTick()
    SetTimer(QsTick, 1000)
    g.Show("w560 h" (y0 + 150))
}

QsClose() {
    global QsGui
    SetTimer(QsTick, 0)
    try QsGui.Destroy()
}

QsAction(which, *) {
    switch which {
        case "Change":
            MapPicker()
        case "Record":
            RecordToggle()
        case "Turn on":
            try SetBuiltIn(1)
            try RefreshToggles()
        case "Play":
            PlayToggle()
    }
    SetTimer(QsTick, -300)
}

; Works out each step: [done?, plain-words detail].
QsState() {
    global CurMap, MacroActive, BuiltIn, WinMode, MacroPlaying
    out := []
    sc := Round(A_ScreenDPI / 96 * 100)
    out.Push([sc = 100, sc = 100 ? "Good." : "It is " sc "%. Windows Settings > System > Display > Scale = 100%, then sign out and in."])
    rr := false
    try rr := RobloxRunning()
    okSize := false
    detail := "Open Roblox, join AOTR and make the window as small as it goes."
    if rr {
        h := 0
        try h := WinExist("ahk_exe RobloxPlayerBeta.exe")
        vb := 0
        try vb := WinBounds(h)
        if IsObject(vb) {
            okSize := (Abs(vb[3] - 801) <= 3 && Abs(vb[4] - 629) <= 3)
            detail := okSize ? "Good. The app is wrapped around it." : "The window is " vb[3] "x" vb[4] ". Drag its corner until it cannot get smaller (801x629)."
        } else {
            okSize := true
            detail := "Roblox is running."
        }
    }
    out.Push([rr && okSize, detail])
    out.Push([true, "Selected: " CurMap "  (press Change to pick another)"])
    n := 0
    try {
        m := MacroLoad(MacroActive)
        if IsObject(m)
            n := m["ev"].Length
    }
    out.Push([n > 0, n > 0 ? "Macro '" MacroActive "' has " n " key events." : "Press F10 (or Record), play ONE round with your keys, press F10 again."])
    out.Push([BuiltIn ? true : false, BuiltIn ? "It is ON." : "It is OFF: press Turn on."])
    out.Push([MacroPlaying ? true : false, MacroPlaying ? "Your macro is playing now." : "Go into the mission and press F8 (or Play). From then on it retries by itself."])
    return out
}

QsTick() {
    global QsGui, QsRows
    if !IsObject(QsGui)
        return
    st := []
    try st := QsState()
    if (st.Length < 6)
        return
    done := 0
    i := 1
    while (i <= 6) {
        r := QsRows[i]
        ok := st[i][1]
        if ok
            done += 1
        try r[1].SetFont("s16 Norm c" (ok ? "4ADE80" : "FBBF24"), "Segoe UI")
        try r[3].Value := st[i][2]
        i += 1
    }
    try QsRows[7].Value := done " of 6 steps done" (done = 6 ? "  -  you are all set" : "")
}

; Text for the "What's new" box on the left panel. Edit this when you ship an update.
; ===================== UPDATES =====================
; The version number on the page is compared with ScriptVersion. A newer one: the person is asked, the new script is downloaded next to
; this one, checked (size, version number, and the end marker, so a cut-off download is never used), the old script is kept as a
; .bak copy, and the macro restarts. Any problem along the way leaves the current script as it is.
UpdateAuto() {
    global busyReconnect, MacroPlaying
    if (busyReconnect || MacroPlaying) {
        SetTimer(UpdateAuto, -300000)             ; busy playing: look again in 5 minutes
        return
    }
    UpdateCheck(false)
}

; The automatic look never opens a window (it would take the keyboard focus, and F1 etc. would go to it): a short tooltip, and the
; "Check for updates" button in Settings tells you. The question only opens when you click that button.
UpdateNotice(newV) {
    global AppCtl
    try {
        AppCtl["upd_btn"].Text := "UPDATE " newV " is available - click to install"
        AppCtl["upd_btn"].SetFont("s9 Bold cE9B44C", "Segoe UI Semibold")
    }
    ToolTip("UPDATE " newV " is available (Settings > Check for updates)", TipX(), TipY(40))
    SetTimer(() => ToolTip(), -7000)
    RejoinLog("update " newV " is available (shown quietly)")
}

; Gets a web page as text. Tries Windows' own HTTP object first, then Download. Returns "" and sets err when both fail.
UpdateGet(url, &err) {
    err := ""
    txt := ""
    try {
        h := ComObject("WinHttp.WinHttpRequest.5.1")
        h.SetTimeouts(8000, 8000, 15000, 15000)
        h.Open("GET", url "?t=" A_TickCount, false)
        h.SetRequestHeader("User-Agent", "AOTR-Macro-Updater")
        h.Send()
        if (h.Status = 200) {
            txt := h.ResponseText
            return txt
        }
        err := "HTTP " h.Status
    } catch as e {
        err := "WinHttp: " e.Message
    }
    try {
        tmp := A_Temp "\aotr_dl.tmp"
        try FileDelete(tmp)
        Download(url, tmp)
        txt := FileRead(tmp, "UTF-8")
        try FileDelete(tmp)
        err := ""
        return txt
    } catch as e2 {
        err .= " | Download: " e2.Message
    }
    return ""
}

UpdateFetchNumber(&err) {
    global UpdateVerUrl
    txt := Trim(UpdateGet(UpdateVerUrl, &err), " `t`r`n" Chr(0xFEFF))
    if (txt = "")
        return ""
    if RegExMatch(txt, "^\d{1,4}(\.\d{1,3})?$")
        return txt                         ; kept as text ("5.1"), compared as a number
    err := "version.txt must contain only a number like 5.1, it says: " SubStr(txt, 1, 40)
    return ""
}

UpdateCheck(manual := false) {
    global ScriptVersion
    static busy := false
    if busy
        return
    busy := true
    err := ""
    newV := UpdateFetchNumber(&err)
    busy := false
    if (newV = "") {
        RejoinLog("update check failed: " err)
        if manual
            MsgBox("Could not check for updates.`n`nReason: " err "`n`nCheck your internet and try again.", "THY HOZ's AOTR MACRO", "Icon! 4096")
        return
    }
    if (Number(newV) <= Number(ScriptVersion)) {
        if manual
            MsgBox("You have the newest version (UPDATE " ScriptVersion ").", "THY HOZ's AOTR MACRO", "Iconi 4096")
        return
    }
    if !manual {
        UpdateNotice(newV)
        return
    }
    r := MsgBox("UPDATE " newV " is available (you have UPDATE " ScriptVersion ").`n`nUpdate now? The macro restarts by itself.", "THY HOZ's AOTR MACRO", "YesNo Iconi 4096")
    if (r = "Yes")
        UpdateInstall(newV)
}

UpdateInstall(newV) {
    global UpdateScriptUrl
    nf := A_ScriptFullPath ".new"
    ok := false
    why := "the download failed."
    try {
        try FileDelete(nf)
        err := ""
        body := UpdateGet(UpdateScriptUrl, &err)
        if (StrLen(body) <= 100000)
            why := "the download is too small or empty (" StrLen(body) " characters). " err
        else if !InStr(body, "ScriptVersion := " Chr(34) newV Chr(34))
            why := "the script on GitHub does not say ScriptVersion := " Chr(34) newV Chr(34) " near the top. Change that number in the script, upload it again, and keep version.txt the same."
        else if !InStr(body, "; END OF SCRIPT")
            why := "the download was cut off (the end marker is missing)."
        else if !InStr(body, "#Requires AutoHotkey v2.0")
            why := "the file on GitHub is not the macro script."
        else {
            FileAppend(body, nf, "UTF-8-RAW")
            ok := true
        }
    }
    if !ok {
        try FileDelete(nf)
        RejoinLog("update not installed: " why)
        MsgBox("The update was not installed. Nothing was changed.`n`nReason: " why, "THY HOZ's AOTR MACRO", "Icon! 4096")
        return
    }
    try FileCopy(A_ScriptFullPath, A_ScriptFullPath ".bak", 1)
    try {
        FileMove(nf, A_ScriptFullPath, 1)
    } catch {
        MsgBox("The update could not replace the script file. Nothing was changed.", "THY HOZ's AOTR MACRO", "Icon! 4096")
        return
    }
    RejoinLog("updated to UPDATE " newV ": restarting")
    Reload()
}

ChangelogText() {
    return "UPDATE " ScriptVersion "`n`n"
        . "NEW`n"
        . "- New look: easier to read, hover any button for help.`n"
        . "- Quick start (top bar): 6 steps with green ticks.`n"
        . "- Record makes a NEW macro. Manage can import and export macros to share.`n"
        . "- Ping options: choose what pings you.`n"
        . "- New Discord reports and alerts.`n"
        . "- Save diagnostics (Settings) for support.`n"
        . "- Injuries: clicks HEAL until none are left, then RETRY.`n"
        . "- Settings: choose how many minutes until stuck.`n"
        . "- Modifiers are saved per mission / raid.`n"
        . "- Duo raids (host or joiner), 2nd player check with TAB.`n"
        . "- Loop macro switch: repeat or fire once.`n"
        . "- Updates: Settings > Check for updates.`n"
        . "- Switch texts follow the switch.`n"
        . "- Colossal Titan: coming soon.`n`n"
        . "FIXED`n"
        . "- RETREAT COMPLETED counts as a fail.`n"
        . "- Works when a button is dark (hovered).`n"
        . "- Rejoin: other Roblox looks, game link fallback.`n"
        . "- Cutscene skip more reliable (every cutscene).`n"
        . "- Rejoin: game link first, faster steps.`n"
        . "- Raid chests, RETRY with HEAL button, wrong WIN / DEFEAT report."
}

NewPanel() {
    g := Gui("-Caption +ToolWindow +E0x08000000", "AOTR Macro")
    g.BackColor := "11131A"
    g.MarginX := 0
    g.MarginY := 0
    g.SetFont("s9 cE8EAF0", "Segoe UI")
    return g
}

RoundCorners(g) {
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "UInt", 33, "Int*", 2, "UInt", 4)
}

AddCard(g, x, y, w, h, col := "1A1D27") {
    ; a thin lighter outline (1 px) around the card makes the panels read as separate, calm blocks
    global LastBorder
    LastBorder := ""
    if (w > 8 && h > 8)
        LastBorder := g.AddText(Format("x{1} y{2} w{3} h{4} Background{5}", x, y, w, h, "2A3045"))
    return g.AddText(Format("x{1} y{2} w{3} h{4} Background{5}", x + 1, y + 1, w - 2, h - 2, col))
}

PanelLabel(g, txt, x, y) {
    g.AddText(Format("x{1} y{2} w3 h11 BackgroundE9B44C", x - 4, y + 2))        ; small gold marker before each section name
    l := g.AddText(Format("x{1} y{2} w230 h16 Background11131A cA3ABBE", x + 6, y), txt)
    l.SetFont("s8 Bold cA3ABBE", "Segoe UI")
    return l
}

; A number with a small caption under it. AppCtl[key] is the number (updated by AppTick).
AddTile(g, key, label, x, y, w, h, col) {
    global AppCtl
    AddCard(g, x, y, w, h)
    g.AddText(Format("x{1} y{2} w{3} h2 Background{4}", x + 1, y + 1, w - 2, col))   ; coloured top edge: tells the tiles apart at a glance
    n := g.AddText(Format("x{1} y{2} w{3} h28 Center +0x200 Background1A1D27 c{4}", x + 1, y + 6, w - 2, col), "0")
    n.SetFont("s15 Norm c" col, "Segoe UI Semibold")
    l := g.AddText(Format("x{1} y{2} w{3} h16 Center Background1A1D27 cA3ABBE", x + 1, y + h - 20, w - 2), label)
    l.SetFont("s7 Bold cA3ABBE", "Segoe UI")
    AppCtl[key] := n
}

; A flat button made from text controls. primary = gold. cap = small second line (the hotkey).
AddBtn(g, txt, x, y, w, h, fn, primary := false, cap := "") {
    global BtnMap
    bg := primary ? "E9B44C" : "232734"
    fg := primary ? "14161C" : "E8EAF0"
    hv := primary ? "F2C566" : "2E3345"
    if (cap = "") {
        c := g.AddText(Format("x{1} y{2} w{3} h{4} Center +0x200 +0x100 Background{5} c{6}", x, y, w, h, bg, fg), txt)
        c.SetFont("s9 Norm c" fg, "Segoe UI Semibold")
        c.OnEvent("Click", (*) => fn())
        BtnMap[c.Hwnd] := [c, bg, hv]
        HelpAdd(c, txt)
        return c
    }
    top := h - 17
    c := g.AddText(Format("x{1} y{2} w{3} h{4} Center +0x200 +0x100 Background{5} c{6}", x, y, w, top, bg, fg), txt)
    c.SetFont("s9 Norm c" fg, "Segoe UI Semibold")
    d := g.AddText(Format("x{1} y{2} w{3} h17 Center +0x200 +0x100 Background{4} c{5}", x, y + top, w, bg, primary ? "4A3A10" : "A9B0C2"), cap)
    d.SetFont("s7 Norm c" . (primary ? "4A3A10" : "A9B0C2"), "Segoe UI")
    c.OnEvent("Click", (*) => fn())
    d.OnEvent("Click", (*) => fn())
    BtnMap[c.Hwnd] := [[c, d], bg, hv]
    BtnMap[d.Hwnd] := [[c, d], bg, hv]
    HelpAdd(c, txt)
    HelpAdd(d, txt)
    return c
}

; A row with a label, a small description + hotkey line, and an ON / OFF pill. getFn() says whether it is on, setFn(1 or 0) changes it.
AddToggle(g, key, label, desc, y, getFn, setFn, h := 40, offLabel := "", offDesc := "") {
    global Toggles
    global LastBorder
    ex := (h - 40) // 2
    card := AddCard(g, 14, y, 262, h)
    bd := LastBorder
    t := g.AddText(Format("x28 y{1} w190 h22 +0x200 +0x100 Background1A1D27 cE8EAF0", y + 2 + ex), label)
    t.SetFont("s9 Norm cE8EAF0", "Segoe UI Semibold")
    bar := g.AddText(Format("x15 y{1} w3 h{2} Background2A2E3B", y + 1, h - 2), "")   ; status stripe on the left: green when ON
    d := g.AddText(Format("x28 y{1} w196 h15 +0x100 Background1A1D27 cA9B0C2", y + 23 + ex), desc)
    d.SetFont("s7 Norm cA9B0C2", "Segoe UI")
    p := g.AddText(Format("x222 y{1} w44 h22 Center +0x200 +0x100 Background2A2E3B cA9B0C2", y + 9 + ex), "OFF")
    p.SetFont("s8 Bold cA9B0C2", "Segoe UI")
    fn := () => ToggleClick(getFn, setFn)
    t.OnEvent("Click", (*) => fn())
    d.OnEvent("Click", (*) => fn())
    p.OnEvent("Click", (*) => fn())
    Toggles[key] := Map("pill", p, "get", getFn, "state", -1, "bar", bar, "t", t, "d", d, "label", label, "desc", desc, "offLabel", offLabel, "offDesc", offDesc, "ctrls", (IsObject(bd) ? [bd, card, t, bar, d, p] : [card, t, bar, d, p]))
    for c in [t, d, p]
        HelpAdd(c, label)
}

; ---- the left panel: key chest / duo toggles only show for raids; everything below moves up or down to match ----
RecordLeft() {
    global LeftGui, LeftBase, Toggles
    LeftBase := Map()
    skip := Map()
    for k in ["key", "duo", "host", "role1", "role2"] {
        if Toggles.Has(k) {
            for c in Toggles[k]["ctrls"]
                skip[c.Hwnd] := 1
        }
    }
    for hwnd in WinGetControlsHwnd("ahk_id " LeftGui.Hwnd) {
        if skip.Has(hwnd)
            continue
        c := GuiCtrlFromHwnd(hwnd)
        if !IsObject(c)
            continue
        c.GetPos(&x, &y, &w, &h)
        LeftBase[hwnd] := [c, x, y, w, h]
    }
}

LayoutLeft() {
    global LeftGui, LeftBase, Toggles, CurMap, DuoRaid, LeftDelta
    if !IsObject(LeftBase)
        return
    raid := IsRaidMap(CurMap)
    colo := (raid && DuoRaid && CurMap = "Colossal Titan")
    for k, on in Map("key", raid, "duo", raid, "host", (raid && DuoRaid), "role1", colo, "role2", colo) {
        if Toggles.Has(k) {
            for c in Toggles[k]["ctrls"]
                c.Visible := on ? true : false
        }
    }
    rows := raid ? (DuoRaid ? (colo ? 5 : 3) : 2) : 0
    delta := (rows - 1) * 52               ; the layout was drawn with one toggle row (the key chest)
    if (delta = LeftDelta)
        return
    LeftDelta := delta
    for hwnd, b in LeftBase {
        c := b[1]
        y := b[3]
        h := b[5]
        if (y < 150 || y >= 650)
            continue                       ; the map card above and the guide button stay where they are
        if (h >= 250)                      ; the What's new card: its top moves, its bottom stays
            c.Move(b[2], y + delta, b[4], h - delta)
        else
            c.Move(b[2], y + delta, b[4], h)
    }
    try DllCall("RedrawWindow", "Ptr", LeftGui.Hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x185)
}

ToggleClick(getFn, setFn) {
    setFn(getFn() ? 0 : 1)
    RefreshToggles()
}

RefreshToggles() {
    global Toggles
    for key, t in Toggles {
        on := t["get"]() ? 1 : 0
        if (on = t["state"])
            continue
        t["state"] := on
        p := t["pill"]
        p.Text := on ? "ON" : "OFF"
        p.Opt("Background" . (on ? "1F4D36" : "2A2E3B"))
        p.SetFont("s8 Bold c" . (on ? "4ADE80" : "A9B0C2"), "Segoe UI")
        p.Redraw()
        try t["bar"].Opt("Background" . (on ? "4ADE80" : "2A2E3B"))
        try t["bar"].Redraw()
        if (t["offLabel"] != "") {          ; the text follows the switch (for example "Duo: you are the Host" / "... the Joiner")
            try t["t"].Text := on ? t["label"] : t["offLabel"]
            try t["d"].Text := on ? t["desc"] : t["offDesc"]
        }
    }
}

; Short plain-words help for every button and switch: it appears after the mouse rests on it for a moment.
HelpAdd(ctrl, label) {
    global HelpMap
    static texts := Map(
        "Change", "Pick which mission or raid the macro plays.",
        "Modifiers", "Choose which modifier boxes the rejoin ticks before START.",
        "Settings", "Webhook, your Discord ID, VIP code, ping options and diagnostics.",
        "Setup check", "Lists everything that is wrong with your setup, in plain words.",
        "Open log", "Opens the log file. Send it when you ask for help.",
        "Guide (F2)", "The full guide: every page, every button, every problem.",
        "Quick start", "The short version: 6 steps with green ticks. No reading.",
        "How to use  (full guide)", "The full guide. Read it if anything does not work.",
        "Rejoin now (Ctrl+Shift+F10)", "Same as Ctrl+Shift+F10: runs the automatic rejoin right now, from whatever screen is showing.",
        "Exit", "Closes the macro.",
        "Manage", "Rename, delete, import, export and record macros.",
        "Record", "Records the keys you press (a NEW macro each time). Press again to stop.",
        "Play", "Starts or stops your macro in the mission.",
        "Stop", "Stops your macro.",
        "Auto retry and start", "At the end of a mission: clicks RETRY and starts the macro again.",
        "Join VIP server", "ON: rejoin through your private server code. OFF: normal PLAY.",
        "Paused", "Stops everything until you turn it off again.",
        "Windowed mode", "Keep ON. The macro works with the small Roblox window.",
        "Use built-in macro", "ON: plays your recorded keys. OFF: it presses F8 for TinyTask.",
        "Loop macro: continuous", "ON: the macro repeats until the round ends. OFF: it plays once per round. Saved for the selected macro.",
        "Loop macro: fires once", "ON: the macro repeats until the round ends. OFF: it plays once per round. Saved for the selected macro.",
        "Open key chest", "Raids only: opens chest 2 when you still have keys.",
        "Duo raid", "Two players, same macro. The host waits for the 2nd player, RETRY only while it says (0/2) or (1/2).",
        "Duo: you are the Host", "ON: you create the raid and press START. OFF: you join the topmost lobby.",
        "Role: Beast (Kill Colossal)", "Colossal raid, duo: your role. Only one role can be ticked. No function yet.",
        "Role: Colossal (Defend Eren)", "Colossal raid, duo: your role. Only one role can be ticked. No function yet.")
    key := label
    if InStr(label, "Record")
        key := "Record"
    else if InStr(label, "Play")
        key := "Play"
    else if InStr(label, "Stop")
        key := "Stop"
    if texts.Has(key) {
        try HelpMap[ctrl.Hwnd] := texts[key]
    }
}

; Highlights the button under the mouse, and shows its help text after a short rest.
HoverTick() {
    global BtnMap, HelpMap
    static cur := 0
    static since := 0
    static shown := 0
    h := 0
    mx := 0
    my := 0
    try MouseGetPos(&mx, &my, , &h, 2)
    if (h != cur) {
        if (cur && BtnMap.Has(cur))
            HoverSet(BtnMap[cur], 2)
        if (h && BtnMap.Has(h))
            HoverSet(BtnMap[h], 3)
        if shown {
            ToolTip(, , , 2)
            shown := 0
        }
        cur := h
        since := A_TickCount
        return
    }
    if (h && !shown && HelpMap.Has(h) && A_TickCount - since >= 500) {
        shown := 1
        ToolTip(HelpMap[h], mx + 16, my + 22, 2)
    }
}

HoverSet(entry, idx) {
    cs := entry[1]
    if !IsObject(cs) || (Type(cs) != "Array")
        cs := [cs]
    for c in cs {
        try c.Opt("Background" . entry[idx])
        try c.Redraw()
    }
}

; The settings window: the typed-in values (webhook, user ID ...). Opened from the Settings button.
BuildSettings() {
    global SetGui, AppCtl, BtnMap, WebhookUrl, DiscordUserId, MainMacroName, ConfirmMs, PrivateServerCode, StuckMinutes, StuckSecs, HealInjuries, FritzRevive
    g := Gui("+AlwaysOnTop", "AOTR Macro settings")
    SetGui := g
    g.BackColor := "11131A"
    g.MarginX := 20
    g.MarginY := 16
    g.SetFont("s9 cE8EAF0", "Segoe UI")
    g.OnEvent("Close", (*) => g.Hide())
    try DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "UInt", 20, "Int*", 1, "UInt", 4)
    h := g.AddText("w340 c6B7185", "SETTINGS")
    h.SetFont("s8 Bold c6B7185", "Segoe UI")
    SField(g, "Discord webhook URL (optional: for reports. Guide page 8)", "hook", WebhookUrl, "Password")
    SField(g, "Your Discord user ID (optional: to get pinged. Guide page 8)", "uid", DiscordUserId)
    SField(g, "TinyTask macro name (ignore this unless 'Use built-in macro' is OFF)", "macro", MainMacroName)
    SField(g, "ConfirmMs (leave at 350. Raise it if a transformation still counts as a win)", "conf", ConfirmMs, "Number")
    SField(g, "Private server code / link (only used when 'Join VIP server' is ON)", "psc", PrivateServerCode)
    SField(g, "Stuck after: minutes without an end screen (default 3)", "stuck", StuckSecs // 60, "Number")
    SField(g, "Stuck after: plus this many seconds (0 to 59)", "stucks", Mod(StuckSecs, 60), "Number")
    hc := g.AddCheckbox("xm y+12 w340 cE8EAF0 " (HealInjuries ? "Checked" : ""), "Heal injuries on the end screen before RETRY")
    AppCtl["heal"] := hc
    fc := g.AddCheckbox("xm y+8 w340 cE8EAF0 " (FritzRevive ? "Checked" : ""), "I play Fritz (has revives): restart the macro 1.5 s after YOU DIED")
    AppCtl["fritz"] := fc
    AppCtl["upd_btn"] := SBtn(g, "Check for updates (you have UPDATE " ScriptVersion ")", "xm y+18 w340 h34", () => UpdateCheck(true))
    SBtn(g, "Ping options (what pings you)", "xm y+10 w340 h34", () => PingPicker())
    SBtn(g, "Save diagnostics (for support)", "xm y+10 w340 h34", () => SaveDiagnostics())
    SBtn(g, "Pin window here", "xm y+10 w165 h34", () => PinHere())
    SBtn(g, "Test webhook", "x+10 w165 h34", () => WebhookTest())
    sv := g.AddText("xm y+12 w340 h36 Center +0x200 +0x100 BackgroundE9B44C c14161C", "Save settings")
    sv.SetFont("s9 Norm c14161C", "Segoe UI Semibold")
    sv.OnEvent("Click", (*) => SaveAppSettings())
    BtnMap[sv.Hwnd] := [sv, "E9B44C", "F2C566"]
}

SBtn(g, txt, opt, fn) {
    global BtnMap
    c := g.AddText(opt . " Center +0x200 +0x100 Background232734 cE8EAF0", txt)
    c.SetFont("s9 Norm cE8EAF0", "Segoe UI Semibold")
    c.OnEvent("Click", (*) => fn())
    BtnMap[c.Hwnd] := [c, "232734", "2E3345"]
    return c
}

SField(g, label, key, val, opt := "") {
    global AppCtl
    l := g.AddText("xm w340 y+12 c8A90A2", label)
    l.SetFont("s8 Norm c8A90A2", "Segoe UI")
    e := g.AddEdit("xm w340 Background1A1D27 cE8EAF0 " opt, val)
    AppCtl[key] := e
}

OpenSettings() {
    global SetGui
    try {
        SetGui.Show("AutoSize")
    }
}

; Puts the three panels around the Roblox window: bar above, bar below, side panel on the right (on the left if there is no room).
DockApp() {
    global AppGui, LeftGui, TopGui, BotGui, WX, WY, WW, WH
    static last := ""
    if (!IsObject(AppGui) || WW <= 0)
        return
    key := WX "," WY "," WW "," WH
    if (key = last)
        return
    last := key
    topY := Max(0, WY - 44)
    rx := WX + WW + 6
    lx := WX - 290 - 6
    if (rx + 290 <= A_ScreenWidth && lx >= 0) {
        sx := rx
        lsx := lx
    } else if (rx + 290 <= A_ScreenWidth) {
        sx := rx
        lsx := (rx + 296 + 290 <= A_ScreenWidth) ? rx + 296 : 0
    } else {
        sx := Max(0, lx)
        lsx := Max(0, sx - 296)
    }
    AppGui.Move(sx, topY)
    LeftGui.Move(lsx, topY)
    TopGui.Move(WX, topY)
    BotGui.Move(WX, WY + WH + 6)
}

SetTxt(key, txt) {
    global AppCtl
    try {
        c := AppCtl[key]
        if (c.Text != txt)
            c.Text := txt
    }
}

AppTick() {
    global WinMode, WX, WY, latchMsg, AppCtl, ScriptPaused, AutoStartEnd, busyReconnect
    global winCount, failCount, sessionStart, mythicTotal, divineTotal, scrollTotal, dcEvents, stuckEvents, roundMsSum, roundIntervals
    static n := 0
    static scr := "-"
    static lastState := ""
    n += 1
    if WinMode {
        ox := WX
        oy := WY
        try LatchRoblox(false)
        if (WX != ox || WY != oy)
            ApplyProfile()
        try DockApp()
    }
    if (!IsObject(AppCtl) || !AppCtl.Has("b_state"))
        return
    if ((n = 1 || Mod(n, 4) = 0) && !busyReconnect) {
        s := ""
        fn := WinMode ? WinScreenName : ClassifyScreen
        if (WinMode && WW > 0)
            try s := WithRegion(fn, WX, WY, 801, 630)      ; only the Roblox window (4x fewer pixels than the whole screen)
        if (s = "")
            try s := WithSnap(fn)
        scr := (s = "") ? "unknown" : s
    }
    tt := -1
    try tt := TTState("main")
    total := winCount + failCount
    elapsed := A_TickCount - sessionStart
    hours := elapsed / 3600000
    SetTxt("t_wins", winCount)
    SetTxt("t_fails", failCount)
    SetTxt("t_rate", (total > 0) ? Round(winCount * 100.0 / total) "%" : "-")
    SetTxt("t_scroll", scrollTotal)
    SetTxt("t_mythic", mythicTotal)
    SetTxt("t_divine", divineTotal)
    SetTxt("t_time", Clock(elapsed))
    SetTxt("t_avg", (roundIntervals > 0) ? Clock(roundMsSum // roundIntervals) : "-")
    SetTxt("t_rph", (hours >= 0.02 && total > 0) ? Format("{:.1f}", total / hours) : "-")
    SetTxt("s_line", "Disconnects " . dcEvents . "     |     Stuck restarts " . stuckEvents)
    state := busyReconnect ? "R" : (ScriptPaused ? "P" : "W")
    if (state != lastState) {
        lastState := state
        col := (state = "R") ? "60A5FA" : ((state = "P") ? "FBBF24" : "4ADE80")
        msg := (state = "R") ? "Rejoining" : ((state = "P") ? "Paused" : "Watching for the end screen")
        SetTxt("b_state", Chr(9679) . "  " . msg)
        try AppCtl["b_state"].SetFont("s9 Norm c" col, "Segoe UI Semibold")
        try AppCtl["b_state"].Redraw()
    }
    SetTxt("b_screen", "Screen:  " scr)
    SetTxt("b_macro", "Main macro:  " . (BuiltIn && MacroActive != "" ? MacroActive . "  -  " : "") . TTName(tt))
    SetTxt("m_name", (MacroActive != "") ? MacroActive : "(no macro yet)")
    SetTxt("map_name", CurMap)
    SetTxt("macro_lbl", "MACRO FOR " . StrUpper(CurMap))
    SetTxt("m_play", MacroPlaying ? Chr(9632) . " Stop" : Chr(9654) . " Play")
    SetTxt("m_rec", Recording ? Chr(9632) . " Stop rec" : Chr(9679) . " Record")
    ; (the label sits under the "Rejoin now" button: it stays empty while all is fine, so it never repaints over the button)
    SetTxt("top_info", WinMode ? (SubStr(latchMsg, 1, 13) = "Window pinned" ? "" : latchMsg) : "fullscreen mode")
    RefreshToggles()
}

SetAutoStart(v) {
    global AutoStartEnd, IniFile
    AutoStartEnd := (v = 1)
    try IniWrite(AutoStartEnd ? "1" : "0", IniFile, "opts", "AutoStartEnd")
    RejoinLog("auto retry/start on win/fail screen is now " (AutoStartEnd ? "ON" : "OFF") " (app window)")
}

SetPaused(v) {
    global ScriptPaused
    if (ScriptPaused != (v = 1))
        TogglePause()
}

SetWinMode(v) {
    global WinMode, IniFile
    WinMode := (v = 1)
    try IniWrite(WinMode ? "1" : "0", IniFile, "opts", "WinMode")
    if WinMode
        try LatchRoblox(false)
    ApplyProfile()
    RejoinLog("windowed mode is now " (WinMode ? "ON" : "OFF"))
}

PinHere() {
    try LatchRoblox(true)
    ApplyProfile()
    ToolTip("Roblox window pinned at " WX ", " WY " (" WW "x" WH "). Record your macro with the window here.", TipX(), TipY(10))
    SetTimer(() => ToolTip(), -4000)
}

OpenLog() {
    global LogFile
    if FileExist(LogFile)
        try Run('notepad.exe "' LogFile '"')
}

SaveAppSettings() {
    global AppCtl, WebhookUrl, DiscordUserId, MainMacroName, ConfirmMs, IniFile, mainHwnd, PrivateServerCode, StuckMinutes, StuckSecs, HealInjuries, FritzRevive, lastRoundTick
    sm := 0
    ss := 0
    try sm := Integer(AppCtl["stuck"].Value)
    try ss := Integer(AppCtl["stucks"].Value)
    if (sm < 0)
        sm := 0
    if (sm > 120)
        sm := 120
    if (ss < 0)
        ss := 0
    if (ss > 59)
        ss := 59
    total := sm * 60 + ss
    if (total < 20)                        ; shorter than 20 s would "leave" during normal play
        total := 20
    StuckSecs := total
    StuckMinutes := Max(1, total // 60)
    try IniWrite(StuckMinutes, IniFile, "app", "StuckMinutes")
    try IniWrite(StuckSecs, IniFile, "app", "StuckSecs")
    if (lastRoundTick != 0)
        lastRoundTick := A_TickCount
    HealInjuries := AppCtl["heal"].Value ? true : false
    try IniWrite(HealInjuries ? "1" : "0", IniFile, "opts", "HealInjuries")
    FritzRevive := AppCtl["fritz"].Value ? true : false
    try IniWrite(FritzRevive ? "1" : "0", IniFile, "opts", "FritzRevive")
    PrivateServerCode := Trim(AppCtl["psc"].Value)
    try IniWrite(PrivateServerCode, IniFile, "app", "PrivateServerCode")
    WebhookUrl := Trim(AppCtl["hook"].Value)
    DiscordUserId := Trim(AppCtl["uid"].Value)
    newMacro := Trim(AppCtl["macro"].Value)
    if (newMacro != MainMacroName) {
        MainMacroName := newMacro
        mainHwnd := 0                      ; look for the TinyTask window again with the new name
    }
    c := 0
    try c := Integer(AppCtl["conf"].Value)
    if (c < 20)
        c := 80
    ConfirmMs := c
    try IniWrite(WebhookUrl, IniFile, "app", "WebhookUrl")
    try IniWrite(DiscordUserId, IniFile, "app", "DiscordUserId")
    try IniWrite(MainMacroName, IniFile, "app", "MainMacroName")
    try IniWrite(ConfirmMs, IniFile, "app", "ConfirmMs")
    ToolTip("Settings saved", TipX(), TipY(10))
    SetTimer(() => ToolTip(), -2000)
}

Watch() {
    global fired, goneSince, lastRoundTick, AutoStartEnd, lastRetryClick, startWaiting, runStart, busyReconnect, DuoClicks
    static lastSk := 0
    if (busyReconnect || ScriptPaused)
        return
    if (A_TickCount - lastSk >= 100) {     ; the watcher runs the SKIP look too, so a busy / delayed SkipTick can never leave a cutscene unskipped
        lastSk := A_TickCount
        try SkipLook()
    }
    if EndScreen() {
        goneSince := 0
        if !fired {
            seenT := A_TickCount           ; the moment the end screen was first seen = the end of the run
            ry := RetryY
            if AutoStartEnd {
                try ry := RetryClickY()    ; the panel sits ~11 px higher when the HEAL button is under it: aim at where RETRY really is
                MouseMove RetryX, ry, 0       ; already on the button while the confirm looks run, so the click needs no travel
            }
            Loop 2 {                       ; still there after about 0.1 s = not a flash (nuke / transformation); was 0.35 s
                Sleep Min(ConfirmMs, 100) // 2
                if !EndScreen()
                    return
            }
            fired := true
            roundMs := (runStart > 0) ? seenT - runStart : 0   ; length of the run that just ended
            runStart := 0
            snap := 0
            try snap := CaptureSnap()      ; frozen copy of the end screen FIRST (a few ms): the click below takes ~0.7 s
            t0 := A_TickCount
            lastRoundTick := t0            ; restarts the stuck-mission timer
            SetTimer(PostRound.Bind(t0, snap, roundMs), -1) ; screenshot, drops and Discord run on their own
            if (AutoStartEnd && DuoActive()) {
                left := DuoRetryState()
                RejoinLog("duo: RETRY counter read: " ((left = 0) ? "no retry left (2/2)" : (left = 1 ? "retry left (0/2 or 1/2)" : "unreadable, pressing RETRY")))
                if (left = 0) {
                    busyReconnect := true
                    SetTimer(DuoLeave, -1)
                    return
                }
                DuoClicks := 0
            }
            if AutoStartEnd {
                try StopMainForRetry()     ; the macro stops first, so it can't move the mouse during the click
                if (WinMode && !WinActive("ahk_exe " RobloxExe()))
                    try WinActivate("ahk_exe " RobloxExe())   ; a click on a window that is not in front often only focuses it
                try FastClick(RetryX, ry) ; press RETRY: a short jiggle + click (~0.1 s instead of ~0.7 s)
                lastRetryClick := A_TickCount
                runStart := lastRetryClick       ; the next run's timer starts when RETRY is pressed
                SetTimer(StartMainAfterLoading, -1)   ; the macro starts again once the loading screens are over
            }
        } else if (AutoStartEnd && A_TickCount - lastRetryClick > (DuoActive() ? 8000 : 1200)) {
            if DuoActive() {                   ; (a duo retry may wait for the other player: do not click again too soon)
                DuoClicks += 1
                if (DuoClicks >= 4) {
                    RejoinLog("duo: RETRY did not work 4 times: leaving to host / join a new raid")
                    busyReconnect := true
                    SetTimer(DuoLeave, -1)
                    return
                }
            }
            lastRetryClick := A_TickCount  ; the screen is still there: the click didn't take, press RETRY again
            ry2 := RetryY
            try ry2 := RetryClickY()
            try ClickAt(RetryX, ry2)
            runStart := A_TickCount        ; the earlier click didn't count: the timer starts from this one
            if !startWaiting
                SetTimer(StartMainAfterLoading, -1)
        }
    } else if fired {
        if !goneSince {
            goneSince := A_TickCount
        } else if (A_TickCount - goneSince >= RearmAfterGoneMs) {
            fired := false
            goneSince := 0
        }
    }
}

; Height of the RETRY button right now. The end panel moves up ~11 px when the HEAL button appears under it, so the fixed
; position can miss the button by a pixel or two. Finds the gold run of the button (a column right of its text).
RetryClickY() {
    if !WinMode
        return RetryY
    gr := GrabRect(RetryX + 36, WY + 434, 6, 39)
    if !IsObject(gr)
        return RetryY
    top := 0
    bot := 0
    y := WY + 434
    while (y <= WY + 472) {
        if IsGoldC(GrabPx(gr, RetryX + 38, y)) {
            if !top
                top := y
            bot := y
        }
        y += 1
    }
    FreeGrab(gr)
    if (top && bot - top >= 8 && bot - top <= 26)
        return (top + bot) // 2
    return RetryY
}

; A fast click (used on the win / fail screen where every millisecond counts).
; Quick click for the win/fail screen: the mouse is already on the button, a tiny jiggle makes Roblox notice it, then click.
FastClick(x, y) {
    MouseMove x + 4, y, 0
    Sleep 12
    MouseMove x - 3, y + 1, 0
    Sleep 12
    MouseMove x, y, 0
    Sleep 15
    Click "Down"
    Sleep 35
    Click "Up"
}

; A click for the chest screen's buttons: Roblox needs to see the mouse arrive (hover) before the press, so a little slower than FastClick.
ChestClick(x, y) {
    MouseMove x - 5, y - 2, 0
    Sleep 30
    MouseMove x + 3, y + 1, 0
    Sleep 30
    MouseMove x, y, 0
    Sleep 70
    Click "Down"
    Sleep 60
    Click "Up"
}

QuickClick(x, y) {
    MouseMove x, y, 0
    Sleep 40
    Click "Down"
    Sleep 50
    Click "Up"
}

ToggleAutoStart() {
    global AutoStartEnd, IniFile
    AutoStartEnd := !AutoStartEnd
    try IniWrite(AutoStartEnd ? "1" : "0", IniFile, "opts", "AutoStartEnd")
    ToolTip("Auto retry/start on win/fail screen: " (AutoStartEnd ? "ON" : "OFF"), TipX(), TipY(10))
    SetTimer(() => ToolTip(), -2500)
    RejoinLog("auto retry/start on win/fail screen is now " (AutoStartEnd ? "ON" : "OFF"))
}

; ===================== SETUP CHECK (F9) =====================
; Checks everything a new user can get wrong and shows one list. The list is also copied to the clipboard, so it can be
; pasted to whoever is helping. It never prints your webhook.
SetupCheck() {
    global WebhookUrl, DiscordUserId, MainMacroName, TileImg, IconImg, ConfirmMs, MinGold, PrivateServerCode
    L := []
    ; script and Windows
    Chk(L, 1, "AutoHotkey " A_AhkVersion)
    Chk(L, A_IsAdmin ? 1 : 0, A_IsAdmin ? "Running as administrator" : "NOT running as administrator: right-click the script > Run as administrator")
    okRes := WinMode ? (A_ScreenWidth >= 1280 && A_ScreenHeight >= 720) : (A_ScreenWidth = 1920 && A_ScreenHeight = 1080)
    Chk(L, okRes ? 1 : 0, "Screen " A_ScreenWidth "x" A_ScreenHeight . (okRes ? "" : (WinMode ? " : too small for the app window next to Roblox" : " : needs 1920x1080")))
    scale := Round(A_ScreenDPI / 96 * 100)
    Chk(L, scale = 100 ? 1 : 0, "Windows display scale " scale "%" (scale = 100 ? "" : " : set it to 100% (Settings > Display > Scale)"))
    ; Roblox
    if RobloxRunning() {
        Chk(L, 1, "Roblox is running")
        h := WinExist("ahk_exe RobloxPlayerBeta.exe")
        if h {
            mm := 0
            try mm := WinGetMinMax("ahk_id " h)
            ww := 0
            wh := 0
            try WinGetPos(, , &ww, &wh, "ahk_id " h)
            if (mm = -1)
                Chk(L, 0, "The Roblox window is minimized")
            else if WinMode {
                ; the size you see (without Windows' invisible resize border, which adds about 15 x 9 px)
                vw := WW
                vh := WH
                vb := 0
                try vb := WinBounds(h)
                if IsObject(vb) {
                    vw := vb[3]
                    vh := vb[4]
                }
                sizeOk := (Abs(vw - 801) <= 3 && Abs(vh - 629) <= 3)
                szTxt := sizeOk ? " (pinned, right size)" : " : needs 801x629, the smallest size: shrink it, or press F11 if it is fullscreen"
                Chk(L, sizeOk ? 1 : 0, "Roblox window " vw "x" vh " at " WX ", " WY szTxt)
            }
            else if (ww >= A_ScreenWidth - 16 && wh >= A_ScreenHeight - 16)
                Chk(L, 1, "Roblox is fullscreen")
            else
                Chk(L, 0, "Roblox is not fullscreen (" ww "x" wh "): press F11 in Roblox")
        }
    } else {
        Chk(L, -1, "Roblox is not running (start the game to check the rest)")
    }
    ; can the script really see the screen?
    lit := ""
    try lit := WithSnap(ScreenLit)
    if (lit = "")
        Chk(L, 0, "The screen could not be read (screen capture failed)")
    else if (lit < 5)
        Chk(L, 0, "The screen looks completely black: minimized / locked remote session, or Roblox isn't on screen")
    else
        Chk(L, 1, "The script can read the screen")
    scr := ""
    try scr := DetectScreen()
    Chk(L, -1, "The script currently sees: " (scr = "" ? "unknown" : scr))
    ; TinyTask
    tt := -1
    try tt := TTState("main")
    if BuiltIn {
        ok := MacroEnsureLoaded()
        Chk(L, ok ? 1 : 0, ok ? "Built-in macro '" MacroActive "': " MacroEv.Length " key events, " Round(MacroDur / 1000, 1) " s, " (MacroLoop ? "loops" : "plays once") : "Built-in player is ON but no macro is recorded (press Record, or F10 in the game)")
    } else if (tt = -1)
        Chk(L, 0, "TinyTask window with '" MainMacroName "' in its title NOT found: open your macro in TinyTask (keep the window visible) or fix MainMacroName")
    else
        Chk(L, 1, "TinyTask main macro found (" (tt = 1 ? "playing" : "stopped") ")")
    ; Discord
    if (WebhookUrl = "")
        Chk(L, -1, "No Discord webhook set (fine if you don't want reports)")
    else if RegExMatch(WebhookUrl, "i)^https://(\w+\.)?discord(app)?\.com/api/webhooks/\d+/[\w-]+$")
        Chk(L, 1, "Discord webhook looks valid (press Ctrl+Shift+F9 to send a test message)")
    else
        Chk(L, 0, "The Discord webhook doesn't look right: copy it again from Discord, nothing else on the line")
    if (DiscordUserId != "" && !RegExMatch(DiscordUserId, "^\d{15,21}$"))
        Chk(L, 0, "DiscordUserId should be only the long number (15-21 digits)")
    ; files
    files := [TileImg, IconImg]
    miss := 0
    for f in files {
        if !FileExist(f)
            miss += 1
    }
    Chk(L, miss = 0 ? 1 : 0, miss = 0 ? "Image files in rejoin_assets are all there" : miss " image file(s) missing in rejoin_assets: restart the script (it recreates them) and make sure its folder is writable")
    w := false
    tf := A_ScriptDir "\_write_test.tmp"
    try {
        FileAppend("x", tf)
        FileDelete(tf)
        w := true
    }
    Chk(L, w ? 1 : 0, w ? "The script folder is writable (log, screenshots)" : "The script folder is NOT writable: move the script to a normal folder (e.g. Documents)")
    if WinMode
        Chk(L, -1, "Windowed mode: the rejoin follows search > AOTR > PLAY (AOTR must be the FIRST tile under Recently Visited). Re-record your main macro with the window pinned.")
    Chk(L, -1, "ConfirmMs " ConfirmMs ", MinGold " MinGold ", private server code " (PrivateServerCode = "" ? "not set (VIP / current code)" : "set"))
    bad := 0
    txt := ""
    for ln in L {
        txt .= ln "`n"
        if (SubStr(ln, 1, 7) = "[ FIX ]")
            bad += 1
    }
    txt := "AOTR macro - setup check`n`n" txt "`n" (bad ? bad " problem(s) to fix (marked [ FIX ])." : "No problems found.") "`n`n(This list was copied to your clipboard.)"
    try A_Clipboard := txt
    try RejoinLog("setup check: " bad " problem(s)")
    MsgBox(txt, "AOTR macro - setup check", (bad ? "Icon!" : "Iconi") " 262144")
}

Chk(L, lvl, txt) {
    L.Push((lvl = 1 ? "[ OK ]  " : (lvl = 0 ? "[ FIX ] " : "[ info ]")) " " txt)
}

; Number of lit (not black) points over the screen, to tell a black screen from a real one.
ScreenLit() {
    n := 0
    if WinMode {
        y := WY + 60
        while (y <= WY + 600) {
            x := WX + 40
            while (x <= WX + 760) {
                if (ColorSum(Px(x, y)) > 45)
                    n += 1
                x += 120
            }
            y += 100
        }
        return n
    }
    y := 40
    while (y <= 1040) {
        x := 40
        while (x <= 1880) {
            if (ColorSum(Px(x, y)) > 45)
                n += 1
            x += 120
        }
        y += 100
    }
    return n
}

; F3: pause / resume. Pausing stops the main macro (TinyTask) and keeps a small "PAUSED" tooltip in the top left
; (its own tooltip, so it doesn't get in the way of anything) until you resume.
TogglePause() {
    global ScriptPaused, lastRoundTick, pauseMsg, WinMode, WX, WY, WW
    if !ScriptPaused {
        ScriptPaused := true
        try EnsureMain(false)
        st := -1
        try st := TTState("main")
        pauseMsg := (st = 0) ? "PAUSED - main macro stopped - F3 to resume" : "PAUSED - could NOT confirm the main macro is stopped, stop it yourself - F3 to resume"
        RejoinLog("script PAUSED (main macro state: " st ")")
        PauseTip()
        SetTimer(PauseTip, 700)
    } else {
        ScriptPaused := false
        SetTimer(PauseTip, 0)
        lastRoundTick := A_TickCount       ; the stuck-mission timer starts fresh
        ToolTip("Resumed. The main macro is still OFF: it starts on the next run, or press F8.", TipX(), TipY(40), 5)
        SetTimer(HidePauseTip, -4000)
        RejoinLog("script RESUMED")
    }
}

; Status messages are drawn inside the Roblox window (screen coordinates), not on the active window and not at the screen corner.
TipX() {
    global WinMode, WX, WW
    return (WinMode && WW > 0) ? WX + 10 : 10
}

TipY(dy := 10) {
    global WinMode, WY, WW
    return (WinMode && WW > 0) ? WY + dy : dy + 30
}

PauseTip() {
    global pauseMsg
    ToolTip(pauseMsg, TipX(), TipY(40), 5)
}

HidePauseTip() {
    global ScriptPaused
    if !ScriptPaused
        ToolTip(, , , 5)
}

SetUseVip(v) {
    global UseVip, PlayInsteadOfVip, IniFile
    UseVip := (v = 1)
    PlayInsteadOfVip := !UseVip
    try IniWrite(UseVip ? "1" : "0", IniFile, "opts", "UseVip")
    RejoinLog("rejoin route is now " (UseVip ? "VIP server" : "PLAY button"))
}

TogglePlayMode() {
    global UseVip
    SetUseVip(UseVip ? 0 : 1)
    ToolTip("Join VIP server: " (UseVip ? "ON (CODES + VIP server)" : "OFF (normal PLAY button)"), TipX(), TipY(10))
    SetTimer(() => ToolTip(), -2500)
}

; Runs separately from Watch, so the slow parts never hold up the restart above.
PostRound(t0, snap := 0, roundMs := 0) {
    kind := "fail"
    try kind := RoundKindSnap(snap)
    try Notify()
    try AfterRound("", kind, t0, snap, roundMs)   ; AfterRound frees the snapshots
}

; ---- frozen copy of the screen, so the report reads the end screen as it was at detection ----
CaptureSnap() {
    w := A_ScreenWidth
    h := A_ScreenHeight
    hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    mdc := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
    bi := Buffer(40, 0)
    NumPut("UInt", 40, bi, 0)
    NumPut("Int", w, bi, 4)
    NumPut("Int", -h, bi, 8)               ; negative = top-down rows
    NumPut("UShort", 1, bi, 12)
    NumPut("UShort", 32, bi, 14)
    bits := 0
    hbm := DllCall("CreateDIBSection", "Ptr", mdc, "Ptr", bi, "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
    if !hbm {
        DllCall("DeleteDC", "Ptr", mdc)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
        return 0
    }
    obm := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
    DllCall("BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", w, "Int", h
        , "Ptr", hdc, "Int", 0, "Int", 0, "UInt", CapRop)
    DllCall("SelectObject", "Ptr", mdc, "Ptr", obm)
    DllCall("DeleteDC", "Ptr", mdc)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
    return {hbm: hbm, bits: bits, w: w, h: h, x0: 0, y0: 0}
}

FreeSnap(snap) {
    if IsObject(snap)
        DllCall("DeleteObject", "Ptr", snap.hbm)
}

; Pixel color (0xRRGGBB) from the snapshot if one is active, otherwise from the live screen.
Px(x, y) {
    global SnapCur
    if IsObject(SnapCur) {
        cx := x - SnapCur.x0                ; (a snapshot of only a part of the screen starts at x0, y0)
        cy := y - SnapCur.y0
        if (cx < 0 || cy < 0 || cx >= SnapCur.w || cy >= SnapCur.h)
            return 0
        return NumGet(SnapCur.bits, (cy * SnapCur.w + cx) * 4, "UInt") & 0xFFFFFF
    }
    return PixelGetColor(x, y)
}

ScanSnap(snap) {
    global SnapCur
    Critical "On"                          ; no timer may run while the snapshot is "active"
    SnapCur := snap
    r := ""
    try r := ScanDrops()
    SnapCur := 0
    Critical "Off"
    return r
}

; Number of gold end-screen points (of 6) found inside a snapshot.
SnapGold(snap) {
    global SnapCur
    Critical "On"
    SnapCur := snap
    g := 0
    try g := GoldCount()
    SnapCur := 0
    Critical "Off"
    return g
}

RoundKindSnap(snap) {
    global SnapCur
    if !IsObject(snap)
        return RoundKind()
    Critical "On"
    SnapCur := snap
    r := "fail"
    try r := RoundKind()
    SnapCur := 0
    Critical "Off"
    return r
}

SaveSnapPng(file, snap) {
    static pngClsid := "{557CF406-1A04-11D3-9A73-0000F81EF32E}"
    DllCall("LoadLibrary", "Str", "gdiplus")
    si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut("UInt", 1, si, 0)
    token := 0
    if DllCall("gdiplus\GdiplusStartup", "Ptr*", &token, "Ptr", si, "Ptr", 0)
        return false
    pBitmap := 0
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", snap.hbm, "Ptr", 0, "Ptr*", &pBitmap)
    if (WinMode && pBitmap && WW > 0 && WX >= 0 && WY >= 0 && WX + WW <= snap.w && WY + WH <= snap.h) {
        pCrop := 0                         ; only the Roblox window goes into the screenshot
        if (!DllCall("gdiplus\GdipCloneBitmapAreaI", "Int", WX, "Int", WY, "Int", WW, "Int", WH, "Int", 0x26200A, "Ptr", pBitmap, "Ptr*", &pCrop) && pCrop) {
            DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
            pBitmap := pCrop
        }
    }
    ok := false
    if pBitmap {
        clsid := Buffer(16, 0)
        DllCall("ole32\CLSIDFromString", "WStr", pngClsid, "Ptr", clsid)
        ok := !DllCall("gdiplus\GdipSaveImageToFile", "Ptr", pBitmap, "WStr", file, "Ptr", clsid, "Ptr", 0)
        DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
    }
    DllCall("gdiplus\GdiplusShutdown", "Ptr", token)
    return ok
}

PressF8() {
    if BuiltIn {
        PlayToggle()
        return
    }
    Send "{F8 down}"
    Sleep 60
    Send "{F8 up}"
}

Notify() {
    s := ""
    for p in Points
        s .= Format("{:06X} ", PixelGetColor(RetryX + p[1], RetryY + p[2]))
    FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  Round end detected" (AutoStartEnd ? ", retry pressed, main macro restarted" : " (auto start is OFF)") ". Colors: " s "`n", LogFile)
    ToolTip("Mission end detected" (AutoStartEnd ? " - retry pressed, main macro restarted" : " (auto start OFF)"), TipX(), TipY(10))
    SetTimer(() => ToolTip(), -3000)
}

EndScreen() {
    if (WinMode && WW <= 0)
        return false
    if (GoldCount() < MinGold)
        return false
    if !WinMode
        return true
    ; PanelOk reads ~300 pixels. One by one over RDP that took about a second per look (and there are 4 looks), so it
    ; reads them from one frozen copy of the screen instead (a few ms).
    return PanelOkFast()
}

; The win / fail panel as a whole: its thin gold frame (12 spots along the edges) and its dark inside (8 spots). A
; transformation or nuke flash can light up the button spots, but it can't draw the frame and keep the inside dark.
PanelOk() {
    edge := 0
    for q in [[300, 181], [400, 181], [500, 181], [300, 479], [400, 479], [500, 479], [232, 250], [232, 350], [232, 430], [569, 250], [569, 350], [569, 430]] {
        if GoldAt(WX + q[1], WY + q[2])
            edge += 1
    }
    if (edge < 7)
        return false
    dark := 0
    for q in [[260, 300], [330, 260], [400, 270], [540, 300], [300, 420], [500, 420], [420, 345], [280, 345]] {
        if (ColorSum(Px(WX + q[1], WY + q[2])) < 240)
            dark += 1
    }
    return dark >= 6
}

GoldCount() {
    global SnapCur
    n := 0
    first4 := 0
    ; one small copy of the button row instead of one slow pixel read per point (the watcher looks every 10 ms)
    gg := 0
    if !IsObject(SnapCur)
        gg := GrabRect(RetryX - 496, RetryY - 12, 380, 25)
    dk := 0
    for i, p in Points {
        pc := IsObject(gg) ? GrabPx(gg, RetryX + p[1], RetryY + p[2]) : Px(RetryX + p[1], RetryY + p[2])
        if IsGoldC(pc) {
            n += 1
            if (i <= 4)
                first4 += 1
        } else if DarkBtnC(pc) {
            dk += 1                        ; a button that is dark brown / black (hovered, pulsing or not usable)
        }
    }
    FreeGrab(gg)
    ; While the mouse is on RETRY (or RETRY can't be used) that button turns dark brown with white text, so its two
    ; points are no longer gold. The LEAVE and MODIFIERS buttons stay bright gold: when all four of their points are
    ; gold the end screen is there, whatever RETRY looks like.
    if (WinMode && first4 = 4)
        return Points.Length
    ; The buttons also pulse: one of LEAVE / MODIFIERS / RETRY goes dark for a moment, which leaves only 4 gold points.
    ; So when at least 3 points are gold, the panel itself (its gold frame and dark inside) decides.
    if (WinMode && n >= 3 && n < MinGold && PanelOkFast())
        return Points.Length
    ; Two buttons dark at once (the mouse is on RETRY AND LEAVE / MODIFIERS pulses dark): only 2 gold points are left, but every
    ; other point sits on a dark button and the panel itself is there: still the end screen.
    if (WinMode && n >= 2 && n < MinGold && n + dk >= Points.Length && PanelOkFast())
        return Points.Length
    return n
}

; The dark brown / black of a button that is not lit (white text on it).
DarkBtnC(c) {
    r := (c >> 16) & 0xFF
    g := (c >> 8) & 0xFF
    b := c & 0xFF
    return (r <= 90 && g <= 75 && b <= 55 && r >= b)
}

; Gold that has been dimmed (a hovered button).
DimGold(c) {
    r := (c >> 16) & 0xFF
    g := (c >> 8) & 0xFF
    b := c & 0xFF
    return r >= 110 && g >= 70 && (r - b) >= 45 && r >= g
}

IsGold(x, y) {
    return IsGoldC(Px(x, y))
}

IsGoldC(c) {
    r := (c >> 16) & 0xFF
    g := (c >> 8) & 0xFF
    b := c & 0xFF
    return r > 200 && g > 130 && b < 175 && (r - b) > 70
}

Calibrate() {
    global RetryX, RetryY, IniFile
    if WinMode {
        ToolTip("Not needed in windowed mode: the RETRY position comes from the pinned window.", TipX(), TipY(10))
        SetTimer(() => ToolTip(), -3000)
        return
    }
    MouseGetPos(&x, &y)
    RetryX := x, RetryY := y
    IniWrite(x, IniFile, "pos", "RetryX")
    IniWrite(y, IniFile, "pos", "RetryY")
    ToolTip("Saved Retry position: " x ", " y)
    SetTimer(() => ToolTip(), -2000)
}

TestHere() {
    d := ScanDrops()
    marks := ""
    for p in Points
        marks .= IsGold(RetryX + p[1], RetryY + p[2]) ? "O " : "X "
    ToolTip("Gold points: " GoldCount() " of " Points.Length "   [" marks "]"
        . (EndScreen() ? "  -> END SCREEN DETECTED" : "  -> not detected")
        . "`nRetry position in use: " RetryX ", " RetryY
        . "`nError pop-up (disconnect) detected: " (DisconnectDialogVisible() ? "YES" : "no")
        . "`nScreen type: " RoundKind() "   Drops -> Mythic: " d[1] "  Divine: " d[2] "  Scrolls: " d[4]
        . "`nIn AOTR lobby (stuck timer paused): " (InLobby() ? "YES" : "no")
        . "`nOBJECTIVES panel (fast detector): " (HudFastOnce() ? "YES" : "no")
        . "`nTinyTask main: " TTName(TTState("main")))
    SetTimer(() => ToolTip(), -4000)
}

; =====================================================================
;  DISCORD / SCREENSHOT / DISCONNECT FEATURES
;  (everything below is additive and wrapped in try, so an error here
;   can never stop the F8 logic above)
; =====================================================================

AfterRound(shot, kind, t0, snap := 0, roundMs := 0) {
    global failCount, winCount, streakKind, streakLen, bestWinStreak, LastRoundRetreat
    global mythicTotal, divineTotal, scrollTotal, roundMsSum, roundIntervals
    ; Everything is read from frozen copies of the screen (snapshots), never from the live screen
    ; after the macro has started moving on. The first snapshot was taken at detection, before the
    ; restart. While the end screen is still showing (strict check on the LIVE screen AND on each
    ; snapshot), a few more snapshots are taken in case the item list was still loading. The
    ; snapshot with the most items wins. A white flash or a loading screen is never accepted,
    ; because every snapshot must itself contain the gold LEAVE / MODIFIERS buttons.
    drops := ""                            ; stays "" if no valid snapshot could be read
    mythic := 0
    divine := 0
    scroll := 0
    bestN := -1
    bestSnap := 0
    stable := 0
    why := "first snapshot only"
    maxMs := Max(ItemScanDelayMs, 3000)
    cand := snap
    Loop {
        if IsObject(cand) {
            g := SnapGold(cand)
            if (g >= MinGold) {
                d := ScanSnap(cand)
                n := 0
                if IsObject(d) {
                    for nm, c in d[3]
                        n += c
                }
                if (IsObject(d) && n > bestN) {
                    if (IsObject(bestSnap) && bestSnap != cand)
                        FreeSnap(bestSnap)
                    bestSnap := cand
                    bestN := n
                    drops := d
                    stable := 0
                } else {
                    FreeSnap(cand)
                    stable += 1
                }
            } else {
                FreeSnap(cand)             ; not an end screen (loading, flash, ...): ignore it
                why := "snapshot rejected (gold=" g ")"
            }
        }
        cand := 0
        if (stable >= 4 && bestN > 0) {
            why := "drops stable"
            break
        }
        if (A_TickCount - t0 >= maxMs) {
            why := "timeout"
            break
        }
        if !EndScreen() {                  ; live screen no longer shows the end screen: stop
            why := "end screen gone"
            break
        }
        Sleep 150
        try cand := CaptureSnap()
    }
    if IsObject(drops) {
        mythic := drops[1]
        divine := drops[2]
        scroll := (drops.Length >= 4) ? drops[4] : 0
    }
    ; The first snapshot can be taken while the panel is still fading in, so the title is read again on the settled one.
    retreatFlag := (kind != "complete" && LastRoundRetreat)
    if IsObject(bestSnap) {
        k2 := ""
        try k2 := RoundKindSnap(bestSnap)
        if (k2 != "") {
            retreatFlag := (k2 != "complete" && LastRoundRetreat)
            if (k2 != kind) {
                rtxt := retreatFlag ? " (retreat)" : ""
                FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  round type corrected on the settled screenshot: " kind " -> " k2 rtxt "`n", LogFile)
                kind := k2
            }
        }
    }
    LastRoundRetreat := retreatFlag
    rareFound := (mythic > 0 && PingOnMythic) || (divine > 0 && PingOnDivine)
    if (IsObject(bestSnap) && (TakeScreenshots || rareFound))
        try shot := TakeShot(kind, bestSnap)
    if (IsObject(bestSnap))
        FreeSnap(bestSnap)
    FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  AfterRound: " why ", items read=" (bestN < 0 ? 0 : bestN) ", after " (A_TickCount - t0) " ms`n", LogFile)

    ; ---- update the session stats ----
    if (kind = "complete")
        winCount += 1
    else
        failCount += 1
    if (kind = streakKind) {
        streakLen += 1
    } else {
        streakKind := kind
        streakLen := 1
    }
    if (kind = "complete" && streakLen > bestWinStreak)
        bestWinStreak := streakLen
    if (roundMs > 0) {                     ; run time = RETRY / START pressed -> end screen seen (measured in Watch)
        roundMsSum += roundMs
        roundIntervals += 1
    }
    mythicTotal += mythic
    divineTotal += divine
    scrollTotal += scroll
    FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " kind "  mythic=" mythic "  divine=" divine "  scrolls=" scroll "  run=" (roundMs > 0 ? Duration(roundMs) : "-") "`n", LogFile)
    PostReport(kind, roundMs, drops, shot)
}

; The title says RETREAT (first word) instead of MISSION: 10 points on the letters of RETREAT, 10 on those of MISSION.
IsRetreatTitle() {
    static rp := ParsePts("291,192;373,195;328,206;350,193;302,207;343,207;364,206;336,194;302,195;361,193")
    static mp := ParsePts("298,192;377,206;339,201;313,207;355,193;313,193;298,206;369,195;349,206;346,195")
    r := SigHits(rp)
    return (r >= 9 && r >= SigHits(mp))
}

; Gold title letters at the far left/right edges: only the long titles (MISSION / RETREAT COMPLETED) reach them,
; RAID COMPLETED and the FAILED title do not.
LongTitleEdges() {
    n := 0
    for xr in [[288, 302], [500, 514]] {
        x := xr[1]
        while (x <= xr[2]) {
            y := 191
            while (y <= 207) {
                if IsGold(WX + x, WY + y)
                    n += 1
                y += 3
            }
            x += 3
        }
    }
    return n
}

; "complete" if the title has gold letters where only MISSION COMPLETED reaches
; (the FAILED title is shorter), otherwise "fail". Positions follow the RETRY calibration.
RoundKind() {
    global LastRoundRetreat, CurMap
    n := 0
    if WinMode {                           ; gold title letters where only MISSION COMPLETED reaches
        for xr in [[284, 308], [494, 514]] {
            x := xr[1]
            while (x <= xr[2]) {
                y := 191
                while (y <= 207) {
                    if IsGold(WX + x, WY + y)
                        n += 1
                    y += 2
                }
                x += 1
            }
        }
        LastRoundRetreat := false
        if (n >= 6) {                      ; dense sampling: RAID COMPLETED (short title) still reaches ~9 hits, a FAILED title gives 0
            edges := LongTitleEdges()
            if ((IsRaidMap(CurMap) && edges >= 6) || (edges >= 3 && IsRetreatTitle())) {   ; RETREAT COMPLETED counts as a loss; raids have no MISSION COMPLETED
                LastRoundRetreat := true
                return "fail"
            }
            return "complete"
        }
        return "fail"
    }
    for box in [[-477, -415], [13, 63]] {
        Loop 13 {
            dx := box[1] + (A_Index - 1) * 5
            if (dx > box[2])
                break
            Loop 9 {
                if IsGold(RetryX + dx, RetryY - 624 + (A_Index - 1) * 5)
                    n += 1
            }
        }
    }
    return (n >= 6) ? "complete" : "fail"
}

; Reads the colored rarity bar under each item in the OBTAINED list. The list wraps onto a
; second row after 9 items (left-aligned, 81 px lower), and the number of items changes, so
; every possible slot position is checked on both rows.
; Returns [mythicCount, divineCount, Map of rarity name -> count, scrollCount].
; A SCROLL is a blue (Rare) bar whose ICON matches the scroll picture (IsScrollIcon). Other blue items stay "Rare".
; Mythic = red bar. Divine = bar that fades from pink to blue (a gradient, unlike the plain
; single-color Epic purple or Rare blue bars).
ScanDrops() {
    if WinMode
        return ScanDropsWin()
    cx := A_ScreenWidth // 2               ; the end-screen panel is centered on the screen
    yBase := A_ScreenHeight // 2 + 154     ; row of the first rarity bars (they are only ~3 px tall)
    mythic := 0
    divine := 0
    scroll := 0
    rar := Map()
    Loop 2 {
        rowY := yBase + 81 * (A_Index - 1) ; the second row of items sits 81 px lower
        Loop 17 {                          ; every possible slot center inside the panel (42 px lattice)
            x := cx + 42 * (A_Index - 9)   ; at most 9 items fit on a row
            found := false
            for dy in [0, -1, -2] {        ; try a few rows in case it's a pixel or two off
                y := rowY + dy
                if BarPresent(x, y) {
                    found := true
                    break
                }
            }
            if !found
                continue
            c := Px(x, y)
            r := (c >> 16) & 0xFF
            g := (c >> 8) & 0xFF
            b := c & 0xFF
            if (r > 150 && g < 70 && b < 70) {
                mythic += 1
                name := "Mythic"
            } else if IsDivineBar(x, y) {
                divine += 1
                name := "Divine"
            } else {
                name := RarityName(r, g, b)
                if (name = "Rare" && IsScrollIcon(x, rowY - 39)) {   ; icon centre is 39 px above the bar row
                    scroll += 1
                    name := "Scroll"
                }
            }
            rar[name] := (rar.Has(name) ? rar[name] : 0) + 1
        }
    }
    return [mythic, divine, rar, scroll]
}

; Small-window version: every item has a 2 px colour bar under its icon (about 32 px wide, 5 px apart). The bar row is
; read for each row of items; every bar found is one item, named by its colour.
ScanDropsWin() {
    mythic := 0
    divine := 0
    scroll := 0
    rar := Map()
    Loop 2 {
        g := A_Index - 1
        dys := (g = 0) ? [1, 0] : [1, 0, -1, 2, -2, 3, -3]
        for dy in dys {
            y := WY + 396 + 37 * g + dy
            found := 0
            for rn in BarRuns(y) {
                nm := BarName(y, rn[1], rn[2])
                if (nm = "")
                    continue
                if (nm = "Rare" && IsScrollWin((rn[1] + rn[2]) // 2, y)) {   ; blue bar + the rolled-up scroll picture
                    nm := "Scroll"
                    scroll += 1
                }
                found += 1
                rar[nm] := (rar.Has(nm) ? rar[nm] : 0) + 1
                if (nm = "Mythic")
                    mythic += 1
                else if (nm = "Divine")
                    divine += 1
            }
            if (found > 0)
                break
        }
    }
    return [mythic, divine, rar, scroll]
}

; The scroll icon in the small window: a thin tan diagonal line (top right to bottom left) on a dark tile. cx = tile
; centre, y = the bar row. The line must be bright along its whole length and dark beside it (a gem or any other
; picture fills more of the tile, so it fails the second test).
IsScrollWin(cx, y) {
    static ln := [[376, 5], [377, 4], [378, 3], [379, 2], [380, 2], [381, 1], [382, 0], [383, -1], [384, -2], [385, -3], [386, -4], [387, -5], [388, -6]]
    for dy in [0, -1, 1] {
        for dx in [0, -1, 1] {
            hit := 0
            for q in ln {
                yy := q[1] + dy + (y - WY - 397) + WY
                for k in [-1, 0, 1] {
                    if (ColorSum(Px(cx + dx + q[2] + k, yy)) > 210) {
                        hit += 1
                        break
                    }
                }
            }
            if (hit < 11)
                continue
            dark := 0
            for ry in [376, 379, 382, 385, 388] {
                xo := 0
                for q in ln {
                    if (q[1] = ry)
                        xo := q[2]
                }
                yy := ry + dy + (y - WY - 397) + WY
                for sd in [-5, 5] {
                    if (ColorSum(Px(cx + dx + xo + sd, yy)) < 150)
                        dark += 1
                }
            }
            if (dark >= 9)
                return true
        }
    }
    return false
}

; Horizontal stretches of bright pixels 26-38 px long on row y inside the panel: [[xStart, xEnd], ...]
BarRuns(y) {
    runs := []
    s := -1
    last := -1
    x := WX + 236
    xEnd := WX + 564
    while (x <= xEnd) {
        if (ColorSum(Px(x, y)) >= 150) {
            if (s < 0)
                s := x
            last := x
        } else if (s >= 0 && x - last > 2) {
            if (last - s + 1 >= 26 && last - s + 1 <= 38)
                runs.Push([s, last])
            s := -1
        }
        x += 1
    }
    if (s >= 0 && last - s + 1 >= 26 && last - s + 1 <= 38)
        runs.Push([s, last])
    return runs
}

; Rarity of the bar between s and e on row y: Divine (pink to blue gradient), Mythic (red) or the nearest plain colour.
BarName(y, s, e) {
    c1 := Px(s + 4, y)
    c2 := Px(e - 4, y)
    if ((c1 & 0xFF) > 150 && (c2 & 0xFF) > 150 && Abs(((c1 >> 16) & 0xFF) - ((c2 >> 16) & 0xFF)) > 50)
        return "Divine"
    votes := Map()
    x := s + 4
    while (x <= e - 4) {
        c := Px(x, y)
        r := (c >> 16) & 0xFF
        g := (c >> 8) & 0xFF
        b := c & 0xFF
        nm := (r > 150 && g < 70 && b < 70) ? "Mythic" : RarityName(r, g, b)
        if (nm != "Other")
            votes[nm] := (votes.Has(nm) ? votes[nm] : 0) + 1
        x += 3
    }
    best := ""
    bestN := 0
    for nm, cnt in votes {
        if (cnt > bestN) {
            bestN := cnt
            best := nm
        }
    }
    return best
}

; Compares the 32x32 area around the icon centre (every 2nd pixel = 16x16 samples, the item count digit is
; outside it) with the stored scroll picture. A few pixels of offset are tried. The average colour difference
; is about 5 for a real scroll and 38 or more for any other item, so the limit of 18 has a wide margin.
IsScrollIcon(cx, cy) {
    global ScrollRef, ScrollRefHex
    if !IsObject(ScrollRef) {
        ScrollRef := []
        Loop 256 {
            i := (A_Index - 1) * 6 + 1
            ScrollRef.Push([Integer("0x" SubStr(ScrollRefHex, i, 2)), Integer("0x" SubStr(ScrollRefHex, i + 2, 2)), Integer("0x" SubStr(ScrollRefHex, i + 4, 2))])
        }
    }
    limit := 18 * 768                      ; 18 per colour channel on average
    for sy in [0, -1, 1, -2, 2] {
        for sx in [0, -1, 1, -2, 2] {
            sum := 0
            k := 0
            bad := false
            Loop 16 {
                dy := (A_Index - 1) * 2 - 16
                Loop 16 {
                    dx := (A_Index - 1) * 2 - 16
                    k += 1
                    c := Px(cx + sx + dx, cy + sy + dy)
                    p := ScrollRef[k]
                    sum += Abs(((c >> 16) & 0xFF) - p[1]) + Abs(((c >> 8) & 0xFF) - p[2]) + Abs((c & 0xFF) - p[3])
                    if (sum > limit) {
                        bad := true
                        break
                    }
                }
                if bad
                    break
            }
            if !bad
                return true
        }
    }
    return false
}


; A real item bar is ~68 px wide, so five points across it must all be bright.
; (Gaps between slots and thin text such as "REWARD BOOST!" fail this.)
BarPresent(x, y) {
    for off in [-30, -15, 0, 15, 30] {
        c := Px(x + off, y)
        if (((c >> 16) & 0xFF) + ((c >> 8) & 0xFF) + (c & 0xFF) < 150)
            return false
    }
    return true
}

; Names a plain single-color bar by its closest known color (names other than Mythic and
; Divine are guesses from the usual rarity colors).
RarityName(r, g, b) {
    best := "Other"
    bestD := 90
    for p in [["Common", 136, 134, 130], ["Uncommon", 95, 197, 80], ["Rare", 86, 119, 216], ["Epic", 147, 93, 193], ["Legendary", 190, 148, 50]] {
        d := Abs(r - p[2]) + Abs(g - p[3]) + Abs(b - p[4])
        if (d < bestD) {
            bestD := d
            best := p[1]
        }
    }
    return best
}

IsDivineBar(x, y) {
    left := Px(x - 27, y)
    right := Px(x + 27, y)
    lr := (left >> 16) & 0xFF
    lb := left & 0xFF
    rr := (right >> 16) & 0xFF
    rb := right & 0xFF
    return lb > 150 && rb > 150 && Abs(lr - rr) > 50
}

Ping(on := true) {
    return (on && DiscordUserId != "") ? "<@" DiscordUserId "> " : ""
}

Duration(ms) {
    s := Round(ms / 1000)
    out := Mod(s, 60) "s"
    if (s >= 60)
        out := Format("{}m {}", s // 60, out)
    return out
}

; Sends a message (and optionally a picture) to the Discord webhook using curl.exe,
; which comes with Windows 10/11. Runs in the background unless wait is true.
SendDiscord(msg, file := "", wait := false) {
    if (WebhookUrl = "")
        return 0
    msg := StrReplace(StrReplace(msg, '"', "'"), "`n", " ")
    try FileDelete(RespFile)
    try FileDelete(ErrFile)
    cmd := 'curl.exe -s -S -m 60 -o "' RespFile '" --stderr "' ErrFile '"'
    cmd .= ' --form-string "username=' BotName '" --form-string "content=' msg '"'
    if (file != "" && FileExist(file))
        cmd .= ' -F "file=@' file '"'
    cmd .= ' "' WebhookUrl '"'
    if wait
        return RunWait(cmd, , "Hide")
    Run(cmd, , "Hide")
    return 0
}

; Ctrl+Shift+F9: sends a test message + screenshot so you can check the webhook works.
WebhookTest() {
    global WebhookUrl, AppCtl
    ; Whatever is typed in the Settings box counts, even if "Save settings" was not pressed yet.
    try {
        v := Trim(AppCtl["hook"].Value)
        if (v != "")
            WebhookUrl := v
    }
    if (WebhookUrl = "") {
        MsgBox("Paste your Discord webhook URL into the 'Discord webhook URL' box in Settings first.", , 262144)
        return
    }
    try {
        shot := ""
        try shot := TakeShot("test")
        code := -1
        sample := Map("Common", 2, "Uncommon", 2, "Epic", 1, "Legendary", 1, "Scroll", 1, "Mythic", 1, "Divine", 1)
        try code := PostReport("complete", 66000, [1, 1, sample, 1], shot, true, true)
        resp := ""
        err := ""
        try resp := FileExist(RespFile) ? Trim(FileRead(RespFile)) : ""
        try err := FileExist(ErrFile) ? Trim(FileRead(ErrFile)) : ""
        if (code = 0 && resp = "" && err = "") {
            ToolTip("Webhook test sent. Check Discord.", TipX(), TipY(10))
            SetTimer(() => ToolTip(), -3000)
        } else {
            MsgBox("The webhook test didn't work.`n`nExit code: " code "`n" err "`n" resp
                . "`n`n(Exit code -1 means curl.exe couldn't be started. It needs Windows 10 or newer.)", , 262144)
        }
    } catch as e {
        RejoinLog("webhook test error: " e.Message " (" e.What " line " e.Line ")")
        MsgBox("The webhook test hit an error instead of crashing:`n`n" e.Message "`n`nSend this text to Thy Hoz.", , 262144)
    }
}

; ------------------------------ SCREENSHOTS -------------------------
TakeShot(kind := "fail", snap := 0) {
    DirCreate(ShotDir)
    file := ShotDir "\" FormatTime(, "yyyyMMdd_HHmmss") "_" kind ".png"
    ok := IsObject(snap) ? SaveSnapPng(file, snap) : SaveScreenshot(file)
    if !ok
        return ""
    if (MaxShots > 0)
        PruneShots()
    return file
}

PruneShots() {
    list := ""
    Loop Files ShotDir "\*.png"
        list .= A_LoopFileName "`n"
    arr := StrSplit(Sort(RTrim(list, "`n")), "`n")
    while (arr.Length > MaxShots)
        try FileDelete(ShotDir "\" arr.RemoveAt(1))
}

; Saves the whole primary screen as a PNG using GDI+.
SaveScreenshot(file) {
    static pngClsid := "{557CF406-1A04-11D3-9A73-0000F81EF32E}"
    DllCall("LoadLibrary", "Str", "gdiplus")
    si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut("UInt", 1, si, 0)
    token := 0
    if DllCall("gdiplus\GdiplusStartup", "Ptr*", &token, "Ptr", si, "Ptr", 0)
        return false
    w := A_ScreenWidth, h := A_ScreenHeight
    hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    mdc := DllCall("CreateCompatibleDC", "Ptr", hdc, "Ptr")
    hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdc, "Int", w, "Int", h, "Ptr")
    obm := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
    DllCall("BitBlt", "Ptr", mdc, "Int", 0, "Int", 0, "Int", w, "Int", h
        , "Ptr", hdc, "Int", 0, "Int", 0, "UInt", 0x40CC0020)   ; SRCCOPY | CAPTUREBLT
    pBitmap := 0
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "Ptr", hbm, "Ptr", 0, "Ptr*", &pBitmap)
    ok := false
    if pBitmap {
        clsid := Buffer(16, 0)
        DllCall("ole32\CLSIDFromString", "WStr", pngClsid, "Ptr", clsid)
        ok := !DllCall("gdiplus\GdipSaveImageToFile", "Ptr", pBitmap, "WStr", file, "Ptr", clsid, "Ptr", 0)
        DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
    }
    DllCall("SelectObject", "Ptr", mdc, "Ptr", obm)
    DllCall("DeleteObject", "Ptr", hbm)
    DllCall("DeleteDC", "Ptr", mdc)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
    DllCall("gdiplus\GdiplusShutdown", "Ptr", token)
    return ok
}

; ------------------------------ DISCONNECT WATCH --------------------
; Alerts when (a) Roblox has closed or crashed, or (b) any Roblox error pop-up is on screen
; (Disconnected, Connection Failed, kicked, ...). For (b) it then runs the auto-reconnect.
RobloxRunning() {
    return ProcessExist("RobloxPlayerBeta.exe") || ProcessExist("Windows10Universal.exe")
}

; True when the dark-gray Roblox error box is showing in the middle of the screen.
DialogCX() {
    return WinMode ? WX + 401 : A_ScreenWidth // 2
}

DialogCY() {
    return WinMode ? WY + 331 : A_ScreenHeight // 2
}

; window-relative position when windowed, the old fullscreen position otherwise
WinPosX(old, w) {
    return WinMode ? WX + w : old
}

WinPosY(old, w) {
    return WinMode ? WY + w : old
}

DisconnectDialogVisible() {
    cx := DialogCX()
    cy := DialogCY()
    for p in DialogPoints {
        c := Px(cx + p[1], cy + p[2])
        r := (c >> 16) & 0xFF
        g := (c >> 8) & 0xFF
        b := c & 0xFF
        if (Abs(r - 57) > 4 || Abs(g - 59) > 4 || Abs(b - 61) > 4)
            return false
    }
    return true
}

DisconnectWatch() {
    global seenRoblox, dcActive, dcLastAlert, dcCount, reconnectTries, dcEvents
    if (busyReconnect || ScriptPaused)
        return
    reason := ""
    isDialog := false
    if RobloxRunning() {
        seenRoblox := true
        if DisconnectDialogVisible() {
            reason := "an error pop-up (Disconnected / Connection Failed) is showing in Roblox"
            isDialog := true
        }
    } else if seenRoblox {
        reason := "Roblox has closed or crashed"
    }

    if (reason = "") {
        dcCount := 0
        if dcActive {                      ; it was down, now it's back
            dcActive := false
            reconnectTries := 0
            if StatusMsgs
            try SendAlert("ok", "Roblox is back up", "The Roblox window is running again.")
            FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  Roblox recovered.`n", LogFile)
        }
        return
    }

    dcCount += 1
    if (dcCount < 3)                       ; must persist for ~3 checks to avoid false alarms
        return

    repeatMs := DisconnectRepeatMin * 60000
    if (!dcActive || (repeatMs > 0 && A_TickCount - dcLastAlert >= repeatMs)) {
        again := dcActive
        if !again
            dcEvents += 1
        dcActive := true
        dcLastAlert := A_TickCount
        shot := ""
        if RobloxRunning()
            try shot := TakeShot("disconnect")
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  DISCONNECT: " reason "`n", LogFile)
        ToolTip("DISCONNECT ALERT: " reason, TipX(), TipY(40))
        SetTimer(() => ToolTip(), -4000)
        dcTitle := again ? "Account disconnected (still down)" : "Account disconnected"
        try SendAlert("bad", dcTitle, "**" reason "**`nThe macro tries to rejoin by itself.", Ping(PingOnDisconnect), shot)
        if (WinMode && !AutoReconnect && !again)   ; rejoin is off: at least stop the main macro
            try EnsureMain(false)
    }

    if (AutoReconnect && (isDialog || (GamePlaceId != "" && !RobloxRunning())) && reconnectTries < ReconnectMaxTries && A_TickCount >= nextReconnectTry)
        RunReconnect()
}

; The ping was already sent. Now: main macro OFF -> automatic rejoin under supervision ->
; main macro ON. If joining AOTR disconnects again, it retries (see RejoinSequence).
RunReconnect() {
    global busyReconnect, dcActive, reconnectTries, nextReconnectTry, lastRoundTick, runStart
    runStart := 0                          ; the run was cut short: its time is not reported
    reconnectTries += 1
    busyReconnect := true                  ; makes the mission-end watcher stand still
    ok := false
    try {
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  Reconnect episode " reconnectTries " started`n", LogFile)
        ToolTip("Reconnecting (episode " reconnectTries "): main macro off, rejoining by itself...", TipX(), TipY(70))
        StopMainHard(true)                 ; main macro OFF (checked, not assumed)
        ok := RejoinSequence(true)
    }
    busyReconnect := false
    ToolTip()
    if ok {
        dcActive := false
        reconnectTries := 0
        lastRoundTick := A_TickCount       ; restart the stuck-mission timer
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  Reconnected, macro running again.`n", LogFile)
        if StatusMsgs
            try SendAlert("ok", "Reconnected", "You are back in and the macro is running again.")
    } else {
        nextReconnectTry := A_TickCount + 300000   ; next episode (if any) in 5 minutes
        shot := ""
        try shot := TakeShot("reconnect_failed")
        left := ReconnectMaxTries - reconnectTries
        try SendAlert("fatal", "Could not rejoin", "Failed after " RejoinMaxTries " attempts (round " reconnectTries "). The main macro is **OFF**.`n"
            . (left > 0 ? "Trying again in 5 minutes." : "Giving up: you need to fix it by hand."), Ping(PingOnGaveUp), shot)
    }
}

PressKey(k) {
    if (BuiltIn && k = "F8") {
        PlayToggle()
        return
    }
    Send "{" k " down}"
    Sleep 60
    Send "{" k " up}"
}

; ------------------------------ STUCK MISSION -----------------------
; If no MISSION FAILED / COMPLETED screen has appeared for StuckMinutes, the mission is stuck
; (e.g. a titan that can't reach you). Leave the game (Esc, L, Enter), then the automatic
; rejoin takes you back to Outskirts and restarts the main macro.
; It only starts counting after the first end screen is seen (or after Ctrl+Shift+F11).
StuckText() {
    m := StuckSecs // 60
    sc := Mod(StuckSecs, 60)
    return (m > 0 ? m " min" : "") . (m > 0 && sc > 0 ? " " : "") . (sc > 0 || m = 0 ? sc " s" : "")
}

StuckWatch() {
    global lastRoundTick
    if (!StuckEnabled || busyReconnect || ScriptPaused || lastRoundTick = 0)
        return
    if !RobloxRunning()
        return
    if (PauseStuckInLobby && InLobby()) {
        lastRoundTick := A_TickCount       ; in the lobby: the timer can't run out
        return
    }
    if (A_TickCount - lastRoundTick >= StuckSecs * 1000)
        try StuckRecovery()
}

; main macro OFF (checked) -> Esc, L, Enter -> automatic rejoin under supervision -> main macro ON
; Windowed: an end screen is on screen. Gold title letters across the MISSION COMPLETED / FAILED title strip.
EndTitleWin() {
    n := 0
    y := WY + 191
    while (y <= WY + 207) {
        x := WX + 215
        while (x <= WX + 590) {
            if IsGold(x, y)
                n += 1
            x += 3
        }
        y += 3
    }
    return n
}

; Never leave the game while a win / fail screen is showing: press RETRY instead, and log what the detector saw.
StuckEndScreenGuard() {
    global lastRoundTick, fired, runStart, startWaiting, lastRetryClick
    if (!WinMode || WW <= 0)
        return false
    g := 0
    t := 0
    cols := ""
    snap := 0
    try snap := CaptureSnap()
    if IsObject(snap) {
        g := SnapGold(snap)
        FreeSnap(snap)
    }
    t := WithSnap(EndTitleWin)
    if (t = "")
        t := 0
    if (g < MinGold && t < 15)
        return false
    try {
        for p in Points
            cols .= Format("{:06X} ", PixelGetColor(RetryX + p[1], RetryY + p[2]))
    }
    RejoinLog("stuck check: an end screen IS showing (gold points " g " of " Points.Length ", title gold " t "). Colours: " cols ". Pressing RETRY instead of leaving.")
    try WinActivate("ahk_exe " RobloxExe())
    try StopMainForRetry()
    try ClickAt(RetryX, RetryY)
    lastRetryClick := A_TickCount
    runStart := A_TickCount
    fired := true
    if !startWaiting
        SetTimer(StartMainAfterLoading, -1)
    lastRoundTick := A_TickCount - Max(0, StuckSecs * 1000 - 25000)   ; look again in 25 s (or right away for a very short limit)
    return true
}

StuckRecovery() {
    global busyReconnect, lastRoundTick, dcActive, dcCount, reconnectTries, stuckEvents, StuckEnabled, runStart
    if StuckEndScreenGuard()
        return
    runStart := 0                          ; the run was cut short: its time is not reported
    stuckEvents += 1
    busyReconnect := true                  ; mission-end and disconnect watchers stand still
    ok := false
    try {
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  STUCK: no end screen for " StuckText() ". Leaving the game.`n", LogFile)
        shot := ""
        try shot := TakeShot("stuck")
        try SendAlert("warn", "Mission looks stuck", "No end screen for **" StuckText() "**.`nStopping the macro, leaving AOTR and rejoining by itself.", Ping(PingOnStuck), shot)
        ToolTip("STUCK MISSION: stopping the main macro...", TipX(), TipY(70))
        StopMainHard(true)                 ; main macro OFF before touching the game
        try WinActivate("ahk_exe " RobloxExe())
        Sleep 500
        ToolTip("STUCK MISSION: leaving the game...", TipX(), TipY(70))
        PressKey("Esc")
        Sleep 800
        PressKey("l")
        Sleep 800
        PressKey("Enter")
        endT := A_TickCount + StuckLeaveWaitSeconds * 1000
        while (A_TickCount < endT) {       ; keep the main macro off while the game closes
            if (TTState("main") = 1)
                EnsureMain(false)
            Sleep 500
        }
        ok := RejoinSequence(false)
    }
    busyReconnect := false
    ToolTip()
    lastRoundTick := A_TickCount           ; start counting again for the new mission
    dcActive := false
    dcCount := 0
    reconnectTries := 0
    if ok {
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  Stuck mission recovered.`n", LogFile)
        if StatusMsgs
            try SendAlert("ok", "Back in after the stuck mission", "The macro is running again.")
    } else {
        StuckEnabled := false              ; don't send Esc, L, Enter again from an unknown screen
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  Stuck recovery FAILED. Stuck watcher turned off.`n", LogFile)
        shot := ""
        try shot := TakeShot("stuck_failed")
        try SendAlert("fatal", "Could not get back in", "The stuck mission could not be recovered.`nThe macro is **OFF** and the stuck watcher is **OFF** (Ctrl+Shift+F11 turns it back on).", Ping(PingOnGaveUp), shot)
    }
}

ToggleStuck() {
    global StuckEnabled, lastRoundTick
    StuckEnabled := !StuckEnabled
    if StuckEnabled
        lastRoundTick := A_TickCount       ; (re)arm: starts counting from now
    ToolTip("Stuck-mission watcher: " (StuckEnabled ? "ON (timer restarted)" : "OFF"), TipX(), TipY(10))
    SetTimer(() => ToolTip(), -2500)
}

RobloxExe() {
    static cached := ""
    static at := 0
    if (cached != "" && A_TickCount - at < 1500)     ; (called many times a second: the process list is only asked every 1.5 s)
        return cached
    cached := ProcessExist("RobloxPlayerBeta.exe") ? "RobloxPlayerBeta.exe" : "Windows10Universal.exe"
    at := A_TickCount
    return cached
}

; ------------------------------ RESTART -----------------------------
; F1: restarts this script from scratch (all counters, timers and states are reset,
; settings are re-read from the top of this file, saved calibration is kept).
RestartScript() {
    ToolTip("Restarting script...", TipX(), TipY(10))
    Sleep 300
    Reload()
}

; ============================ DISCORD MISSION REPORT ====================
; Builds the "AOTR / MISSION REPORT" embed. kind = "complete" or "fail"; roundMs = time since
; the previous end screen (0 = unknown); drops = result of ScanDrops(), or "" if not read.
PostReport(kind, roundMs, drops, shot, wait := false, isTest := false) {
    total := winCount + failCount
    sessionMs := A_TickCount - sessionStart
    mythic := IsObject(drops) ? drops[1] : 0
    divine := IsObject(drops) ? drops[2] : 0

    if (total > 0)
        wrText := RegExReplace(Format("{:.1f}", winCount * 100.0 / total), "\.0$") "%"
    else
        wrText := "-"
    hours := sessionMs / 3600000
    rphText := (hours >= 0.02 && total > 0) ? Format("{:.1f}", total / hours) : "-"
    avgText := (roundIntervals > 0) ? Duration(roundMsSum / roundIntervals) : "-"
    thisText := (roundMs > 0) ? Duration(roundMs) : "-"

    if (streakKind = "complete") {
        streakText := streakLen " win streak"
        if (bestWinStreak > streakLen)
            streakText .= " (best " bestWinStreak ")"
    } else if (streakKind = "fail") {
        streakText := streakLen " loss streak"
    } else {
        streakText := "-"
    }

    ; drops this round, by rarity (Rare and above listed, the rest counted)
    dropText := "Not read"
    if IsObject(drops) {
        rar := drops[3]
        parts := ""
        listed := 0
        all := 0
        for nm, n in rar
            all += n
        for nm in ["Divine", "Mythic", "Scroll", "Legendary", "Epic", "Rare"] {
            n := rar.Has(nm) ? rar[nm] : 0
            if (n > 0) {
                part := nm " x" n
                if (nm = "Divine" || nm = "Mythic")
                    part := "**" part "**"
                if (parts != "")
                    parts .= " | "
                parts .= part
                listed += n
            }
        }
        if (all = 0) {
            dropText := "No drops"
        } else {
            dropText := parts
            if (all > listed) {
                if (dropText != "")
                    dropText .= " "
                dropText .= "(+" (all - listed) " other)"
            }
        }
    }

    scrollN := (IsObject(drops) && drops.Length >= 4) ? drops[4] : 0
    rare := ""
    if (mythic > 0 && PingOnMythic)
        rare := mythic " MYTHIC"
    if (divine > 0 && PingOnDivine) {
        if (rare != "")
            rare .= " + "
        rare .= divine " DIVINE"
    }
    if (scrollN > 0 && PingOnScroll) {
        if (rare != "")
            rare .= " + "
        rare .= scrollN " SCROLL"
    }

    what := IsRaidMap(CurMap) ? "Raid" : "Mission"
    if (kind = "complete") {
        title := Chr(0x2705) "  " what " completed"
        color := 3066993
        tag := "VICTORY"
    } else {
        suffix := LastRoundRetreat ? " failed (retreat)" : " failed"
        title := Chr(0x274C) "  " what suffix
        color := 15548997
        tag := LastRoundRetreat ? "RETREAT" : "DEFEAT"
    }
    content := ""
    desc := "### " CurMap "`n" what " #" total "  " Chr(0x00B7) "  " tag
    if (rare != "") {
        content := Ping() "RARE DROP: " rare "!"
        desc := "### RARE DROP: " rare "`n" CurMap "  " Chr(0x00B7) "  " what " #" total
        color := 16766720
    } else if (PingOnFail && kind = "fail") {
        content := Ping()
    }
    if isTest {
        title := "TEST - " title
        content := Ping() "This is a test report (sample drops). If you can see it, the webhook works."
    }

    ; Layout: the drops first, then three even rows of three boxes (Discord lines them up by itself).
    streakShort := "-"
    plural := (streakLen = 1) ? "" : "s"
    if (streakKind = "complete")
        streakShort := streakLen " win" plural
    else if (streakKind = "fail") {
        lossPl := (streakLen = 1) ? "" : "es"
        streakShort := streakLen " loss" lossPl
    }
    fields := []
    fields.Push(["Drops this round", dropText, false])
    fields.Push(["Round time", Code(thisText), true])
    fields.Push(["Average round", Code(avgText), true])
    fields.Push(["Rounds / hour", Code(rphText), true])
    fields.Push(["Record", Code(winCount " W / " failCount " L"), true])
    fields.Push(["Win rate", Code(wrText), true])
    fields.Push(["Streak", Code(streakShort), true])
    fields.Push(["Scrolls", Code(scrollTotal ""), true])
    fields.Push(["Mythic", Code(mythicTotal ""), true])
    fields.Push(["Divine", Code(divineTotal ""), true])
    issues := dcEvents " disconnects, " stuckEvents " stuck restarts"
    foot := "Thy Hoz's AOTR Macro | " A_ComputerName "  " Chr(0x00B7) "  Session " Clock(sessionMs) "  " Chr(0x00B7) "  " issues

    hasImg := (shot != "" && FileExist(shot)) ? true : false
    return SendPayload(EmbedJson(content, title, desc, color, fields, hasImg, "AOTR  " Chr(0x00B7) "  " StrUpper(what) " REPORT", foot), shot, wait)
}

; A status / problem message as a proper embed (colour bar, title, short text, session line) instead of plain text.
; kind: "bad" (red), "warn" (orange), "ok" (green), "fatal" (dark red).
SendAlert(kind, title, text, ping := "", shot := "") {
    static colors := Map("bad", 15548997, "warn", 16098851, "ok", 3066993, "fatal", 10038562)
    fields := []
    fields.Push([IsRaidMap(CurMap) ? "Raid" : "Mission", CurMap, true])
    fields.Push(["Session", Clock(A_TickCount - sessionStart), true])
    fields.Push(["Record", winCount " W / " failCount " L", true])
    hasImg := (shot != "" && FileExist(shot)) ? true : false
    j := EmbedJson(ping, Chr(0x25CF) "  " title, text, colors[kind], fields, hasImg, "AOTR / ALERT")
    return SendPayload(j, shot, false)
}

Pad(txt, n) {
    while (StrLen(txt) < n)
        txt .= " "
    return txt
}

Clock(ms) {
    t := ms // 1000
    return Format("{:02d}:{:02d}:{:02d}", t // 3600, Mod(t // 60, 60), Mod(t, 60))
}

Code(txt) {
    return Chr(96) txt Chr(96)            ; Discord code formatting
}

JsonEsc(txt) {
    txt := StrReplace(txt, "\", "\\")
    txt := StrReplace(txt, '"', '\"')
    txt := StrReplace(txt, "`r", "")
    txt := StrReplace(txt, "`n", "\n")
    txt := StrReplace(txt, "`t", "\t")
    return txt
}

; fields = array of [name, value, inline]
EmbedJson(content, title, desc, color, fields, hasImage, author := "AOTR / MISSION REPORT", foot := "") {
    f := ""
    for fld in fields {
        if (f != "")
            f .= ","
        f .= '{"name":"' JsonEsc(fld[1]) '","value":"' JsonEsc(fld[2]) '","inline":' (fld[3] ? "true" : "false") '}'
    }
    e := '{"author":{"name":"' JsonEsc("THY HOZ  " Chr(0x00B7) "  " author) '"}'
    e .= ',"title":"' JsonEsc(title) '"'
    if (desc != "")
        e .= ',"description":"' JsonEsc(desc) '"'
    e .= ',"color":' color
    e .= ',"fields":[' f ']'
    if hasImage
        e .= ',"image":{"url":"attachment://report.png"}'
    e .= ',"footer":{"text":"' JsonEsc(foot != "" ? foot : "Thy Hoz's " BotName " | " A_ComputerName) '"}'
    e .= ',"timestamp":"' FormatTime(A_NowUTC, "yyyy-MM-dd'T'HH:mm:ss'Z'") '"}'
    j := '{"username":"' JsonEsc(BotName) '"'
    if (content != "")
        j .= ',"content":"' JsonEsc(content) '"'
    j .= ',"embeds":[' e ']}'
    return j
}

; Sends a JSON payload (and optionally the screenshot) to the webhook with curl.exe.
; The JSON goes through a small temp file so quotes and emoji can't get mangled.
SendPayload(json, file := "", wait := false) {
    if (WebhookUrl = "")
        return 0
    PrunePayloads()
    pf := A_ScriptDir "\payload_" A_TickCount ".json"
    FileAppend(json, pf, "UTF-8-RAW")
    try FileDelete(RespFile)
    try FileDelete(ErrFile)
    cmd := 'curl.exe -s -S -m 60 -o "' RespFile '" --stderr "' ErrFile '"'
    cmd .= ' -F "payload_json=<' pf ';type=application/json"'
    if (file != "" && FileExist(file))
        cmd .= ' -F "files[0]=@' file ';filename=report.png"'
    cmd .= ' "' WebhookUrl '"'
    if wait
        return RunWait(cmd, , "Hide")
    Run(cmd, , "Hide")
    return 0
}

PrunePayloads() {
    Loop Files A_ScriptDir "\payload_*.json" {
        if (DateDiff(A_Now, A_LoopFileTimeModified, "Minutes") > 10)
            try FileDelete(A_LoopFileFullPath)
    }
}

; ============================ AOTR LOBBY ================================
; The lobby has a black menu bar across the top (GEAR UP, QUESTS, EQUIPMENT ...) with a thin
; gold line under it. Missions and end screens don't have it.
InLobby() {
    if WinMode {
        n := 0
        for x in [120, 250, 400, 550, 650, 700, 780] {
            if ((IsGold(WX + x, WY + 104) || IsGold(WX + x, WY + 105)) && ColorSum(Px(WX + x, WY + 101)) < 80)
                n += 1
        }
        return n >= 5
    }
    hits := 0
    for x in [260, 520, 800, 1100, 1350, 1500, 1650, 1850] {
        if (IsGold(x, 136) || IsGold(x, 135)) {
            c := PixelGetColor(x, 124)     ; just above the line: nearly black
            if (((c >> 16) & 0xFF) + ((c >> 8) & 0xFF) + (c & 0xFF) < 80)
                hits += 1
        }
    }
    return hits >= 6
}

; ============================ TINYTASK CONTROL ==========================
; TinyTask's window title shows what it is doing: idle = "[file name].rec", playing = "00:41 (1/0*)".
; F8 is a toggle, so pressing it blindly can start a macro that should be stopped (or the other way
; round). Reading the title lets the script press F8 only when needed.

TTName(st) {
    return (st = 1) ? "playing" : (st = 0) ? "idle" : "not found"
}

; Finds the main TinyTask window from its idle title and remembers it.
TTDiscover() {
    global mainHwnd
    for hwnd in WinGetList() {
        t := ""
        try t := WinGetTitle("ahk_id " hwnd)
        if !InStr(t, ".rec")
            continue
        if (MainMacroName != "" && InStr(t, MainMacroName)) {
            mainHwnd := hwnd
            try IniWrite(hwnd, IniFile, "tinytask", "mainHwnd")
        }
    }
}

; Returns 1 = playing, 0 = idle, -1 = can't tell (window not found). (which is always "main")
TTState(which) {
    global mainHwnd, ttLastScan
    if BuiltIn
        return MacroPlaying ? 1 : 0
    h := mainHwnd
    if (!h || !WinExist("ahk_id " h)) {
        if (A_TickCount - ttLastScan > 5000) {
            ttLastScan := A_TickCount
            try TTDiscover()
        }
        h := mainHwnd
        if (!h || !WinExist("ahk_id " h))
            return -1
    }
    t := ""
    try t := WinGetTitle("ahk_id " h)
    if RegExMatch(t, "^\d+:\d\d\b")
        return 1
    if InStr(t, ".rec")
        return 0
    return -1
}

; Gets the main macro playing (want = true) or idle (want = false), pressing F8 only when needed.
; Returns 1 = done, 0 = couldn't get there, -1 = can't read TinyTask's state.
EnsureMain(want, tries := 3) {
    goal := want ? 1 : 0
    if (TTState("main") = -1)
        return -1
    Loop tries {
        if (TTState("main") = goal)
            return 1
        PressKey("F8")
        endT := A_TickCount + 1500
        while (A_TickCount < endT) {
            Sleep 40
            if (TTState("main") = goal)
                return 1
        }
    }
    return (TTState("main") = goal) ? 1 : 0
}

; Main macro OFF. If TinyTask can't be read, one blind F8 is sent only when allowBlind is true
; (call it with true once per recovery, never repeatedly: F8 is a toggle).
StopMainHard(allowBlind := false) {
    r := EnsureMain(false)
    if (r = -1 && allowBlind && StopMainFirst) {
        PressKey("F8")
        Sleep 1000
    }
    return r
}

; Restarts the main macro after a mission ends: stops it if it's playing, then starts it. Adaptive
; (waits only until TinyTask confirms) instead of a fixed pause, and it can't end up with the
; macro idle because the toggle was in the wrong state.
; Win / fail screen -> next match: the main macro is stopped right away and started again only when the loading
; screens are over (see WaitLoadingCycle).
StopMainForRetry() {
    st := TTState("main")
    if (st = 1 || st = -1)
        PressF8()                          ; stop it right away and DON'T wait: it is checked again just after the click
}

StartMainAfterLoading() {
    global startWaiting, busyReconnect, fastStartResult
    if startWaiting
        return
    startWaiting := true
    try {
        if (TTState("main") = 1)           ; the quick stop before the click didn't take: stop it properly now
            EnsureMain(false)
        r := WaitMatchReady(150000, true, true)   ; presses F8 ITSELF the instant the OBJECTIVES panel shows up
        if (r = "dialog")                  ; an error box: the disconnect watch clicks Leave and rejoins
            return
        if (r = "busy" || busyReconnect || ScriptPaused)   ; a disconnect happened meanwhile: the rejoin takes over
            return
        if (r = "timeout" && EndScreen()) {
            RejoinLog("retry: still on the win/fail screen, no objectives seen; retrying the click")
            return
        }
        if (r = "timeout")                 ; no panel seen, but not on the end screen either: start anyway (as before)
            fastStartResult := FastStartMain()
        res := (fastStartResult = "blind") ? -1 : ConfirmStarted()
        RejoinLog("objectives (" r "), F8: " fastStartResult ", main macro start result: " res)
    } finally {
        startWaiting := false
    }
}

; The match loading screen: gold line under "LOADING" at the bottom (y 1021-1023, x 790-1130), black around it.
LoadingPx() {
    ok := 0
    if WinMode {                           ; the gold line under LOADING (2 px tall), black above and below it
        for x in [335, 355, 375, 395, 415, 435, 455, 465] {
            hit := false
            for yy in [596, 597] {         ; a pixel of slack: either row of the line
                c := Px(WX + x, WY + yy)
                r := (c >> 16) & 0xFF
                g := (c >> 8) & 0xFF
                b := c & 0xFF
                if (r >= 200 && g >= 150 && r - b >= 60)
                    hit := true
            }
            if (hit && ColorSum(Px(WX + x, WY + 593)) < 60 && ColorSum(Px(WX + x, WY + 600)) < 60)
                ok += 1
        }
        return ok >= 6
    }
    for x in [800, 840, 880, 900, 1020, 1060, 1100, 1120] {
        c := Px(x, 1022)
        r := (c >> 16) & 0xFF
        g := (c >> 8) & 0xFF
        b := c & 0xFF
        if (r >= 200 && g >= 150 && r - b >= 60 && ColorSum(Px(x, 1018)) < 60 && ColorSum(Px(x, 1027)) < 60)
            ok += 1
    }
    return ok >= 6
}

LoadingNow() {
    return WithSnap(LoadingPx) = 1
}

; In the match: the objectives panel (top right) is showing. (The skill bar is no longer checked.)
HudPx() {
    return GoldPts(HudPts) >= 5
}

HudNow() {
    return WithSnap(HudPx) = 1
}

; Polls the screen and returns the moment the OBJECTIVES panel (top right) shows. No loading-screen wait, no
; confirmation pass: the panel never shows on the win/fail screen, the lobby or the loading screens, so the first
; sighting is the start. Returns "objectives" when seen, "timeout" if not seen in maxMs, "busy" if a rejoin took over.
WaitMatchReady(maxMs := 150000, abortOnBusy := false, pressOnSight := false) {
    global fastStartResult, RaidWaiting
    fastStartResult := ""
    RaidWaiting := pressOnSight
    if pressOnSight
        try TTState("main")                ; finds TinyTask's window NOW, so nothing slow happens at the critical moment
    hf := HudFastOpen()                    ; small screen strip around the OBJECTIVES header (fast to read)
    lastSk := 0
    lastBk := 0
    lastDlg := 0
    dlgN := 0
    t := A_TickCount
    try {
        while (A_TickCount - t < maxMs) {
            if (abortOnBusy && busyReconnect)
                return "busy"
            if ScriptPaused {              ; paused: never press F8 here
                if abortOnBusy
                    return "busy"
                t += 200
                Sleep 200
                continue
            }
            if (A_TickCount - lastSk >= 40) {           ; cutscene: skip it from here too (this loop never gives the timer a chance to be late)
                lastSk := A_TickCount
                try SkipLook()
            }
            if (A_TickCount - lastDlg >= 1500) {         ; a Roblox error box (Connection Failed 279, Disconnected ...): stop waiting, the rejoin must click it
                lastDlg := A_TickCount
                dl := false
                try dl := WithRegion(DisconnectDialogVisible, DialogCX() - 200, DialogCY() - 80, 400, 160)   ; one small grab, not 10 slow pixel reads
                dlgN := dl ? dlgN + 1 : 0
                if (dlgN >= 2) {
                    RejoinLog("waiting for the objectives panel: an error pop-up is showing, handing over to the rejoin")
                    return "dialog"
                }
            }
            if (A_TickCount - lastBk >= 2000) {          ; black "waiting for players" screen (every coop match): the time limit stands still while it is up
                lastBk := A_TickCount
                bk := false
                try bk := WithRegion(BlackScreenPx, WX, WY, WW, 629)
                if bk
                    t += 2000
            }
            if IsObject(hf) {
                seen := HudFastLook(hf)
                if (seen = -1) {           ; the screen grab failed: open it again
                    HudFastClose(hf)
                    hf := HudFastOpen()
                    seen := 0
                }
            } else {
                seen := HudNow()           ; fallback: the slow full-screen look
            }
            if seen {
                if pressOnSight
                    fastStartResult := FastStartMain()   ; F8 FIRST, logging and checks come after
                RejoinLog("objectives panel seen after " (A_TickCount - t) " ms: starting the macro (F8: " (pressOnSight ? fastStartResult : "not pressed here") ")")
                return "objectives"
            }
            Sleep 1
        }
    } finally {
        RaidWaiting := false
        HudFastClose(hf)
    }
    RejoinLog("objectives panel not seen within " (maxMs // 1000) " s")
    return "timeout"
}

ReleaseTimer(*) {
    DllCall("winmm\timeEndPeriod", "UInt", 1)
    return 0
}

; ---- fast OBJECTIVES detector ------------------------------------------------------------------
; Instead of copying the whole 1920x1080 screen for every look (tens of ms), it copies only the 230x56 strip
; around the header (about 1 ms) into a small bitmap kept for the whole wait. Same 6 points, same "gold" test.
HudFastOpen() {
    x0 := 1690
    y0 := 165
    w := 230
    h := 56
    if WinMode {
        x0 := WX + 660
        y0 := WY + 115
        w := 141
        h := 35
    }
    sdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    mdc := DllCall("CreateCompatibleDC", "Ptr", sdc, "Ptr")
    bi := Buffer(40, 0)
    NumPut("UInt", 40, bi, 0)
    NumPut("Int", w, bi, 4)
    NumPut("Int", -h, bi, 8)               ; negative = top-down rows
    NumPut("UShort", 1, bi, 12)
    NumPut("UShort", 32, bi, 14)
    bits := 0
    hbm := DllCall("CreateDIBSection", "Ptr", mdc, "Ptr", bi, "UInt", 0, "Ptr*", &bits, "Ptr", 0, "UInt", 0, "Ptr")
    if !hbm {
        DllCall("DeleteDC", "Ptr", mdc)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", sdc)
        return 0
    }
    obm := DllCall("SelectObject", "Ptr", mdc, "Ptr", hbm, "Ptr")
    return {sdc: sdc, mdc: mdc, hbm: hbm, obm: obm, bits: bits, w: w, h: h, x0: x0, y0: y0}
}

HudFastClose(hf) {
    if !IsObject(hf)
        return
    DllCall("SelectObject", "Ptr", hf.mdc, "Ptr", hf.obm)
    DllCall("DeleteObject", "Ptr", hf.hbm)
    DllCall("DeleteDC", "Ptr", hf.mdc)
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hf.sdc)
}

; 1 = OBJECTIVES panel showing (at least 5 of the 6 points are gold), 0 = not showing, -1 = the grab failed.
HudFastLook(hf) {
    if !DllCall("BitBlt", "Ptr", hf.mdc, "Int", 0, "Int", 0, "Int", hf.w, "Int", hf.h
        , "Ptr", hf.sdc, "Int", hf.x0, "Int", hf.y0, "UInt", CapRop)
        return -1
    miss := 0
    for p in HudPts {
        cx := p[1] - hf.x0
        cy := p[2] - hf.y0
        hit := false
        y := cy - 2
        while (y <= cy + 2 && !hit) {      ; a pixel or two off is fine (same as GoldAt)
            x := cx - 2
            while (x <= cx + 2) {
                if (x >= 0 && y >= 0 && x < hf.w && y < hf.h
                    && GoldD(NumGet(hf.bits, (y * hf.w + x) * 4, "UInt") & 0xFFFFFF)) {
                    hit := true
                    break
                }
                x += 1
            }
            y += 1
        }
        if !hit {
            miss += 1
            if (miss > 1)                  ; can't reach 5 of 6 any more: stop looking (most looks end here)
                return 0
        }
    }
    return 1
}

; One-off look (used by the F5 test).
HudFastOnce() {
    hf := HudFastOpen()
    if !IsObject(hf)
        return false
    r := HudFastLook(hf)
    HudFastClose(hf)
    return (r = 1)
}

; Presses F8 right now. F8 is a toggle, so if TinyTask says the main macro is ALREADY playing it does nothing.
; It reads TinyTask's title directly (no window search), so it costs about 1 ms.
; Returns "pressed", "already" (was playing, nothing pressed) or "blind" (TinyTask unreadable, one F8 sent).
FastStartMain() {
    global mainHwnd
    if BuiltIn {
        if MacroPlaying
            return "already"
        PlayStart()
        return "pressed"
    }
    st := -1
    try {
        if (mainHwnd && WinExist("ahk_id " mainHwnd)) {
            t := WinGetTitle("ahk_id " mainHwnd)
            st := RegExMatch(t, "^\d+:\d\d\b") ? 1 : InStr(t, ".rec") ? 0 : -1
        }
    }
    if (st = 1)
        return "already"
    PressF8()
    return (st = -1) ? "blind" : "pressed"
}

; After the fast F8: waits until TinyTask shows the macro playing. Only if it still shows idle after 1.5 s
; (the press didn't take) is F8 pressed again, at most twice. Returns 1 = playing, -1 = can't read TinyTask, 0 = failed.
ConfirmStarted() {
    Loop 3 {
        endT := A_TickCount + 1500
        while (A_TickCount < endT) {
            s := TTState("main")
            if (s = 1)
                return 1
            if (s = -1)
                return -1
            Sleep 20
        }
        if (A_Index < 3)
            PressF8()
    }
    return 0
}

; Waits for the loading screen(s) of lobby -> match / end screen -> match. There are two: the screen goes black for
; a moment between them, so the first one ending is NOT the end. Returns "done" (two loading screens, the second one
; is over), "single" (only one was seen, it is over) or "none" (no loading screen showed up within firstWaitMs).
WaitLoadingCycle(firstWaitMs := 45000) {
    t := A_TickCount
    while (!LoadingNow()) {
        if (A_TickCount - t > firstWaitMs)
            return "none"
        Sleep 100
    }
    RejoinLog("loading screen 1 seen")
    WaitLoadingGone(120000, 2)             ; first one over (black flash)
    t := A_TickCount
    while (A_TickCount - t < 12000) {
        if LoadingNow() {
            RejoinLog("loading screen 2 seen")
            WaitLoadingGone(120000, 3)
            return "done"
        }
        Sleep 100
    }
    return "single"
}

; Waits until the loading screen has been gone for `misses` looks in a row (so a flicker doesn't count).
WaitLoadingGone(maxMs, misses) {
    t := A_TickCount
    gone := 0
    while (A_TickCount - t < maxMs) {
        if LoadingNow()
            gone := 0
        else {
            gone += 1
            if (gone >= misses)
                return true
        }
        Sleep 100
    }
    return false
}

RestartMain() {
    if (TTState("main") = -1) {            ; can't read TinyTask: the old blind stop + start
        PressF8()
        Sleep RestartDelayMs
        PressF8()
        return
    }
    if (TTState("main") = 1) {
        EnsureMain(false)
        Sleep 150                          ; let TinyTask settle before starting again
    }
    EnsureMain(true)
}

; ============================ REJOIN SUPERVISION ========================
; Runs the automatic rejoin up to RejoinMaxTries times. Returns true when you're back in and
; the main macro is running.
RejoinSequence(expectDialogFirst) {
    backoff := RejoinBackoffSeconds
    Loop RejoinMaxTries {
        attempt := A_Index
        FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  Rejoin attempt " attempt " of " RejoinMaxTries "`n", LogFile)
        ToolTip("Rejoin attempt " attempt " of " RejoinMaxTries "...", TipX(), TipY(70))
        if RejoinAttempt(expectDialogFirst)
            return true
        if (attempt >= RejoinMaxTries)
            break
        shot := ""
        try shot := TakeShot("rejoin_failed")
        try SendAlert("warn", "Rejoin attempt " attempt " failed", "It got stuck (see the screenshot).`nWaiting **" backoff " s**, then trying again.", "", shot)
        Sleep backoff * 1000
        expectDialogFirst := true          ; on a retry an error pop-up is probably on screen
    }
    return false
}

; ============================ AUTOMATIC REJOIN ==========================
; Replaces the old F12 "disconnected" TinyTask macro. It looks at the screen (a frozen snapshot, so
; nothing moves under it), works out which screen it is, does the action for THAT screen, and repeats
; until the match lobby is set up. Because it re-reads the screen every time, a click that didn't work
; is simply repeated, and it can pick up from wherever the game currently is.
;
;   Roblox home -> click the AOTR tile -> game page: PLAY -> SLOT A: SELECT -> menu: CODES -> VIP
;   SERVERS box: click until the cursor blinks, Enter -> LOBBY -> lobby: PLAY -> MISSIONS -> OUTSKIRTS
;   (checked by its title) -> CREATE -> MODIFIERS -> scroll down, tick the wanted boxes (checked one by
;   one) -> BACK -> F8.
;
; All positions are for a 1920x1080 screen, like the rest of this script.

AutoRejoinOnce() {
    global RejoinTimeoutSeconds, HomeTileX, HomeTileY, runStart, GamePlaceId, ForceLink
    RejoinLog("Automatic rejoin started")
    StopMainHard()                         ; the main macro must be OFF: it would click on its own
    st := Map("typed", 0, "typeTries", 0, "dlg", 0, "vip", 0, "rounds", 0, "starts", 0, "modFail", 0, "enter", false, "mods", (ModSkip || (ModifiersWanted.Length = 0 && !ModExact)), "iconMiss", 0, "noCreate", 0, "raidCreated", 0, "rl", 0)
    RejoinLog("target: " CurMap)
    startT := A_TickCount
    lastScr := ""
    sameSince := A_TickCount
    lastFocus := 0
    ForceLink := false                     ; ("Rejoin now" behaves like an automatic rejoin: it looks at the screen first)
    scr0 := ""
    if (WinMode && GamePlaceId != "" && RobloxRunning())
        try scr0 := DetectScreen()
    ; If the screen is already one of AOTR's own (lobby, raid lists, match lobby, modifiers, slots, menu, VIP box, pop-ups ...), the
    ; rejoin simply carries on from there: restarting the game would throw that progress away. The game link fires at once only
    ; when the screen is NOT one of those (Roblox home / search / a game page, an error box, an unknown screen, a match).
    ; A look-alike screen of another game is caught by the "no progress for 15 s" rule below.
    flow := (scr0 = "lobby" || scr0 = "modes" || scr0 = "lobbies" || scr0 = "raid" || scr0 = "raidok" || scr0 = "map" || scr0 = "mapok" || scr0 = "mapwrong" || scr0 = "matchlobby" || scr0 = "modifiers" || scr0 = "slots" || scr0 = "menu" || scr0 = "vip" || scr0 = "popup" || scr0 = "daily" || scr0 = "custom")
    if (GamePlaceId != "" && RobloxRunning() && !flow) {
        st["deep"] := true
        st["deepT"] := A_TickCount
        RejoinLog("rejoin: starting AOTR with its game link (start of the attempt)")
        try Run("roblox://experiences/start?placeId=" GamePlaceId)
        Sleep 1500
    }
    while (A_TickCount - startT < RejoinTimeoutSeconds * 1000) {
        if ScriptPaused {                  ; paused: wait here, the timeouts stand still
            Sleep 250
            startT += 250
            sameSince += 250
            continue
        }
        if !RobloxRunning() {
            if !LaunchGame()
                return false
            sameSince := A_TickCount
            continue
        }
        if (A_TickCount - lastFocus > 20000) {
            lastFocus := A_TickCount
            try WinActivate("ahk_exe " RobloxExe())
        }
        if (WinMode && Due(st, "t_prompt", 1200) && PromptVisible()) {   ; "rejoin the last match?" -> always NO, from the rejoin loop itself (not only from the timer)
            RejoinLog("popup 'rejoin the last match?': pressing NO (rejoin loop)")
            ClickAt(WX + 361, WY + 391)
            Sleep 300
            continue
        }
        scr := DetectScreen()
        if (scr != lastScr) {
            RejoinLog("screen: " scr)
            ToolTip("Rejoin: " scr, TipX(), TipY(70))
            lastScr := scr
            sameSince := A_TickCount
            for k in ["t_home", "t_card", "t_type", "t_page", "t_slots", "t_play", "t_codes", "t_daily", "t_custom", "t_popup", "t_lobby", "t_modes", "t_oth", "t_rl"]   ; (NOT the raid / lobby / modifiers clicks: a flicker between those screens must never click MODIFIERS or BACK twice)
                if st.Has(k)
                    st.Delete(k)           ; a new screen = the click worked: do the next step at once, no waiting
        }
        ; The pixels of AOTR's lobby / HUD can also look like another game's screen (health bars, buttons ...): ask Roblox's own log
        ; which game this client really joined, and if it is not AOTR, start AOTR by its game link.
        if (GamePlaceId != "" && scr != "home" && scr != "search" && scr != "dialog" && scr != "loading" && Due(st, "t_wrong", 6000)) {
            wg := ""
            try wg := WrongGameId()
            if (wg != "") {
                st["wrongN"] := st.Has("wrongN") ? st["wrongN"] + 1 : 1
                if (st["wrongN"] <= 3) {
                    RejoinLog("rejoin: Roblox is in ANOTHER game (place " wg "), not AOTR: starting AOTR with its game link (" st["wrongN"] ")")
                    try Run("roblox://experiences/start?placeId=" GamePlaceId)
                    st["deep"] := true
                    st["deepT"] := A_TickCount
                    st.Delete("inGame")
                    sameSince := A_TickCount
                    Sleep 6000
                    continue
                }
            }
        }
        limit := (scr = "other" || scr = "loading") ? 80000 : 45000
        if (scr = "lobbies" && DuoJoiner()) {      ; the joiner keeps clicking JOIN until the host's lobby is there
            limit := 1500000
            startT := A_TickCount
        }
        if (DuoJoiner() && st.Has("jc") && scr != "lobbies" && A_TickCount - st["jc"] > 1200
            && (scr = "matchlobby" || scr = "other" || scr = "loading")) {
            RejoinLog("duo: in the host's lobby, waiting for the match to start")
            jr := JoinerWait(st)
            if (jr = "started")
                return FinishRejoin()
            st.Delete("jc")
            continue
        }
        if (GamePlaceId != "" && WinMode && (scr = "menu" || scr = "slots" || scr = "other" || scr = "popup" || scr = "vip" || scr = "home" || scr = "search" || scr = "gamepage")
            && A_TickCount - sameSince > 15000 && A_TickCount - (st.Has("deepT") ? st["deepT"] : 0) > 25000 && RobloxRunning()) {
            ; the same screen for 15 s with no progress: it may be another game that looks like AOTR's menu. The game link fixes that.
            st["deep"] := true
            st["deepT"] := A_TickCount
            RejoinLog("rejoin: no progress on '" scr "' for 15 s: starting AOTR with its game link again")
            try Run("roblox://experiences/start?placeId=" GamePlaceId)
        }
        if (A_TickCount - sameSince > limit) {
            RejoinLog("stuck on screen '" scr "' for " (limit // 1000) " s, giving up this attempt")
            ToolTip()
            return false
        }

        if (scr != "other" && scr != "home" && scr != "search" && scr != "dialog")
            st["inGame"] := true           ; past the Roblox app: from here on an unknown screen is just a loading screen
        switch scr {
            case "dialog":
                st["dlg"] += 1
                HandleDialog(st["dlg"])
            case "home":
                if (WinMode && DeepLinkStep(st)) {
                    ; AOTR's own game link is in charge (no search, no guessing which result is AOTR)
                } else if (WinMode && st["typed"] && A_TickCount - st["typed"] < 40000) {
                    SearchStep(st)             ; the search results page can look like "home"
                } else if Due(st, "t_home", 6000) {
                    st["typed"] := 0
                    if WinMode
                        ClickAt(WX + SearchIconX(), WY + 59)   ; the search icon (3 or 4 icons in the top bar)
                    else
                        ClickAt(HomeTileX + 42, HomeTileY + 35)
                }
            case "search":                     ; type aotr, press Enter, click the Attack on Titan Revolution result
                if (WinMode && DeepLinkStep(st)) {
                    ; the game link is in charge
                } else if WinMode
                    SearchStep(st)
            case "loading":                    ; the game is loading: just wait, never fire the game link
                st["inGame"] := true
            case "other":
                if (WinMode && st["typed"] && A_TickCount - st["typed"] < 40000) {
                    SearchStep(st)
                } else if (WinMode && !st.Has("inGame") && !st["raidCreated"] && !st["typed"] && A_TickCount - sameSince > 2500 && Due(st, "t_oth", 10000)) {
                    ; An unknown screen in the Roblox app (another theme / layout): open the search the generic way
                    if (GamePlaceId != "" && !st.Has("deep")) {
                        st["deep"] := true      ; the game's own link works on any Roblox theme / layout
                        RejoinLog("unknown screen: starting AOTR with its game link")
                        try Run("roblox://experiences/start?placeId=" GamePlaceId)
                    } else if !st.Has("deep") {
                        RejoinLog("unknown screen: trying the search icon / search field")
                        ClickAt(WX + SearchIconX(), WY + 59)
                        Sleep 900
                        SearchStep(st)
                    }
                } else if (WinMode && st["raidCreated"] && st["rl"] < 5 && A_TickCount - st["raidCreated"] > 6000 && Due(st, "t_rl", 4000) && !(DuoHosting() && !DuoKickSeen())) {
                    runs := WithSnap(PillRuns)      ; raid lobby that isn't recognised: press its right-most button (START)
                    if (IsObject(runs) && runs.Length >= 1) {
                        st["rl"] += 1
                        r := runs[runs.Length]
                        RejoinLog("raid lobby not recognised: pressing the right-most button")
                        ClickAt(WX + (r[1] + r[2]) // 2, WY + 481)
                    }
                }
            case "gamepage":
                if (WinMode && DeepLinkStep(st)) {
                    ; the game link is in charge (a game page can be ANY game's page: never click its PLAY blindly)
                } else if Due(st, "t_page", 5000) {
                    if (!WinMode && st["iconMiss"] < 2 && !GameIconOk()) {
                        st["iconMiss"] += 1
                        RejoinLog("game page icon not recognised, going back (" st["iconMiss"] ")")
                        ClickAt(108, 40)
                    } else {
                        ClickAt(WinPosX(906, 435), WinPosY(256, 288))
                    }
                }
            case "slots":
                if Due(st, "t_slots", 2500)
                    ClickAt(WinPosX(629, 257), WinPosY(689, 400))
            case "slotshover":                 ; the mouse is on slot A: its card grows and SELECT moves down a little
                if Due(st, "t_slots", 2500)
                    ClickAt(WinPosX(629, 257), WinPosY(703, 400))
            case "menu":
                if PlayInsteadOfVip {              ; toggle: skip CODES / VIP, press the menu's PLAY button
                    if Due(st, "t_play", 4000)
                        ClickAt(WinPosX(960, 402), WinPosY(610, 361))
                } else if st["enter"] {
                    if Due(st, "t_play", 9000) {
                        RejoinLog("no LOBBY/TRADE pop-up after Enter: clicking PLAY on the menu")
                        ClickAt(WinPosX(960, 402), WinPosY(610, 361))
                    }
                } else if Due(st, "t_codes", 6000) {
                    ClickAt(WinPosX(960, 401), WinPosY(850, 465))
                }
            case "vip":
                HandleVip(st)
            case "daily":                      ; DAILY REWARDS pop-up after joining the lobby: close it with the X (top right)
                if Due(st, "t_daily", 2500)
                    ClickAt(WinPosX(1854, 773), WinPosY(186, 134))
            case "custom":                     ; character customization screen: BACK, then Esc if it is still there
                if Due(st, "t_custom", 2500) {
                    st["cust"] := (st.Has("cust") ? st["cust"] : 0) + 1
                    RejoinLog("customization screen: clicking BACK (try " st["cust"] ")")
                    if (Mod(st["cust"], 3) = 0)
                        PressKey("Esc")
                    else
                        ClickAt(WX + 42, WY + 612)
                }
            case "popup":
                if Due(st, "t_popup", 3000)
                    ClickAt(WinPosX(785, 326), WinPosY(540, 331))
            case "lobby":
                if Due(st, "t_lobby", 4000)
                    ClickAt(WinPosX(1500, 699), WinPosY(1005, 541))    ; bottom-left corner of the PLAY box (the TinyTask windows cover the right side)
            case "modes":
                if Due(st, "t_modes", 3000) {
                    if DuoJoiner()
                        ClickAt(WX + 655, WY + 390)            ; the JOIN card (duo raid, you are the joiner)
                    else if (WinMode && IsRaidMap(CurMap))
                        ClickAt(WX + 316, WY + 378)            ; the RAIDS card
                    else
                        ClickAt(WinPosX(433, 147), WinPosY(630, 379))   ; the MISSIONS card
                }
            case "map":
                if Due(st, "t_map", 1500) {
                    if WinMode
                        SelectMapRow()
                    else
                        ClickAt(1327, 690)
                }
            case "raid":
                if Due(st, "t_map", 1500)
                    SelectMapRow()
            case "raidok":
                if Due(st, "t_create", 3500)
                    RaidCreate(st)
            case "mapwrong":
                if Due(st, "t_back", 2500)
                    BackPill()
            case "mapok":
                if Due(st, "t_create", 3500)
                    ClickAt(WinPosX(977, 409), WinPosY(870, 482))
            case "lobbies":
                if (DuoJoiner() && Due(st, "t_join", 900)) {
                    st["jc"] := A_TickCount
                    ClickAt(WX + 485, WY + 311)                ; JOIN on the topmost lobby, again and again
                }
            case "matchlobby":
                if (DuoHosting() && st["mods"] && !DuoKickSeen()) {
                    ToolTip("Duo raid: waiting for the 2nd player (KICK button)", TipX(), TipY(70))
                    if Due(st, "t_duow", 30000)
                        RejoinLog("duo: waiting for the 2nd player")
                    sameSince := A_TickCount
                    startT += 500
                    Sleep 400
                    continue
                }
                if (DuoJoiner()) {
                    if !st.Has("jc")
                        st["jc"] := A_TickCount - 2000
                    sameSince := A_TickCount
                    continue
                }
                if st["mods"] {
                    ; modifiers are set: press START ourselves (so the macro doesn't click MODIFIERS again), then the macro
                    st["starts"] += 1
                    RejoinLog("pressing START (" st["starts"] ")")
                    ClickAt(WinPosX(1148, 484), WinPosY(870, 482))
                    startT := A_TickCount
                    started := false
                    t0 := A_TickCount
                    while (A_TickCount - t0 < 2500) {         ; leave the moment the lobby is gone
                        Sleep 120
                        sc2 := DetectScreen()
                        if (sc2 != "matchlobby" && sc2 != "modifiers") {   ; (the MODIFIERS box open = START did not work)
                            started := true
                            break
                        }
                    }
                    if (started || st["starts"] >= 4) {
                        runStart := startT                    ; the run's timer starts when START is pressed
                        RejoinLog("run timer started at START press (" (started ? "confirmed" : "not confirmed after 4 tries") ")")
                        ToolTip("Rejoin: waiting for the objectives panel", TipX(), TipY(70))
                        lr := WaitMatchReady(DuoActive() ? 900000 : 150000, false, true)   ; (a duo match waits for the 2nd player's loading)
                        RejoinLog("loading screens: " lr)
                        if (lr = "dialog") {                  ; error box (Connection Failed ...): the loop below clicks Leave and starts over
                            if st.Has("inGame")
                                st.Delete("inGame")      ; (the key must be GONE: the unknown-screen link fallback tests .Has())
                            st["starts"] := 0
                            continue
                        }
                        return FinishRejoin()
                    }
                    continue
                }
                if Due(st, "t_match", 3500)
                    ClickAt(WinPosX(960, 402), WinPosY(870, 482))
            case "modifiers":
                if st["mods"] {
                    if Due(st, "t_back", 2500)
                        ClickAt(WinPosX(960, 401), WinPosY(874, 482))
                } else if HandleModifiers() {
                    ClickAt(WinPosX(960, 401), WinPosY(874, 482))
                    st["mods"] := true
                } else {
                    st["modFail"] += 1       ; couldn't set every box: don't sit there forever, press BACK and go on
                    if (st["modFail"] >= 2) {
                        RejoinLog("modifiers: not every box could be set, pressing BACK anyway")
                        ClickAt(WinPosX(960, 401), WinPosY(874, 482))
                        st["mods"] := true
                    }
                }
        }
        Sleep 80
    }
    RejoinLog("rejoin attempt timed out on screen '" lastScr "'")
    ToolTip()
    return false
}

; Roblox search: types "aotr" into the search bar, presses Enter and clicks the big Attack on Titan Revolution result
; (found by its picture; after 3 tries it clicks the top result anyway).
; The Roblox home top bar has 3 icons (search, bell, panel) or 4 (search, Robux, bell, panel): the search icon is always
; the left-most one. Finds it as the first icon-sized bright blob (14 to 30 px wide) right of the user name; 665 if unsure.
SearchIconX() {
    r := ""
    try r := WithSnap(SearchIconScan)
    return (r = "" || r = 0) ? 665 : r
}

SearchIconScan() {
    cols := []
    x := 596
    while (x <= 780) {
        on := false
        y := 45
        while (y <= 75) {
            if (ColorSum(Px(WX + x, WY + y)) > 450) {
                on := true
                break
            }
            y += 2
        }
        cols.Push(on)
        x += 1
    }
    runs := []
    st := 0
    en := 0
    for i, v in cols {
        if v {
            if (st = 0)
                st := i
            en := i
        } else if (st && i - en > 4) {
            runs.Push([st, en])
            st := 0
        }
    }
    if st
        runs.Push([st, en])
    for k, rn in runs {
        w := rn[2] - rn[1] + 1
        if (w >= 14 && w <= 30)
            return 596 + (rn[1] + rn[2]) // 2 - 1
    }
    return 0
}

; The place id of the game this Roblox client joined last, from Roblox's own log (newest file, last "place NNN" join line).
; Returns that id when it is NOT AOTR's, otherwise "" (also "" when the log can't be read: then nothing changes).
WrongGameId() {
    global GamePlaceId
    dirs := [EnvGet("LOCALAPPDATA") "\Roblox\logs"]
    best := ""
    bestT := ""
    for d in dirs {
        Loop Files, d "\*.log" {
            if (bestT = "" || A_LoopFileTimeModified > bestT) {
                bestT := A_LoopFileTimeModified
                best := A_LoopFileFullPath
            }
        }
    }
    if (best = "") {
        RejoinLog("game check: no Roblox log file found in " dirs[1])
        return ""
    }
    txt := ""
    try {
        f := FileOpen(best, "r", "UTF-8-RAW")
        sz := f.Length
        if (sz > 400000)
            f.Pos := sz - 400000           ; only the end of the file
        txt := f.Read()
        f.Close()
    }
    if (txt = "") {
        RejoinLog("game check: could not read " best)
        return ""
    }
    last := ""
    pos := 1
    while (pos := RegExMatch(txt, "i)(?:Joining game '[^']*' place |placeId\W+)(\d{6,})", &m, pos)) {
        last := m[1]
        pos += StrLen(m[0])
    }
    RejoinLog("game check: " best "  last joined place: " (last = "" ? "(none found)" : last) "  AOTR: " GamePlaceId)
    if (last = "" || last = GamePlaceId)
        return ""
    return last
}

; Rejoin by AOTR's own game link whenever the Roblox app is outside a game (home / search): exact, and it can never open the wrong game.
; Returns true while the link is in charge (just started, or still loading: up to 40 s); after that the old search route takes over.
DeepLinkStep(st) {
    if (GamePlaceId = "")
        return false
    if (!st.Has("deep") || (st.Has("deepT") && A_TickCount - st["deepT"] >= 30000)) {   ; first time, and again every 30 s while still not in the game
        st["deep"] := true
        st["deepT"] := A_TickCount
        RejoinLog("rejoin: starting AOTR with its game link")
        try Run("roblox://experiences/start?placeId=" GamePlaceId)
    }
    return true                            ; with a game link the search is never used
}

SearchStep(st) {
    if (st["typed"] = 0) {
        if !Due(st, "t_type", 4000)
            return
        st["typeTries"] += 1
        ClickAt(WX + 370, WY + 59)
        Sleep 300
        Send "^a"
        Sleep 100
        SendText "aotr"
        Sleep 400
        PressKey("Enter")
        st["typed"] := A_TickCount
        RejoinLog("search: typed aotr (try " st["typeTries"] ")")
        return
    }
    if !Due(st, "t_card", 2500)
        return
    ok := 0
    try ok := WithSnap(CardOkWin)
    if (ok != 1 && st["typeTries"] >= 3 && A_TickCount - st["typed"] > 6000 && GamePlaceId != "" && !st.Has("deep")) {
        ; The top search result is NOT proven to be AOTR (it can be any other game): open AOTR by its own game link instead of guessing.
        st["deep"] := true
        RejoinLog("search: AOTR's picture was not found in the results: starting AOTR with its game link instead of clicking a guess")
        try Run("roblox://experiences/start?placeId=" GamePlaceId)
        return
    }
    if (ok = 1 || (st["typeTries"] >= 3 && A_TickCount - st["typed"] > 6000 && !st.Has("deep"))) {
        RejoinLog("search: clicking the result" . (ok = 1 ? " (recognised by its picture)" : " (picture not recognised, clicking the top result)"))
        ClickAt(WX + 433, WY + 382)
        return
    }
    if (A_TickCount - st["typed"] > 10000)
        st["typed"] := 0                   ; nothing showed up: type it again
}

; The big Attack on Titan Revolution card on the search results page: its picture sampled at 24 smooth spots.
CardOkWin() {
    static pts := [[359, 551, 21, 21, 23], [551, 455, 242, 204, 191], [125, 221, 139, 196, 91], [539, 341, 26, 31, 30], [707, 347, 52, 73, 104], [491, 533, 50, 51, 50], [473, 443, 118, 168, 117], [389, 335, 7, 9, 10], [575, 203, 36, 54, 81], [713, 215, 123, 149, 177], [173, 533, 99, 145, 91], [317, 419, 9, 5, 4], [281, 251, 12, 17, 19], [353, 221, 2, 2, 4], [749, 455, 32, 45, 55], [239, 449, 122, 136, 158], [251, 533, 51, 59, 65], [677, 437, 0, 0, 0], [167, 305, 150, 164, 177], [119, 449, 143, 202, 104], [251, 317, 16, 11, 12], [215, 215, 29, 40, 43], [617, 365, 8, 11, 11], [455, 371, 174, 132, 119]]
    n := 0
    for q in pts {
        hit := false
        for dx in [0, -1, 1] {
            for dy in [0, -1, 1] {
                c := Px(WX + q[1] + dx, WY + q[2] + dy)
                if (Abs(((c >> 16) & 0xFF) - q[3]) + Abs(((c >> 8) & 0xFF) - q[4]) + Abs((c & 0xFF) - q[5]) <= 45) {
                    hit := true
                    break
                }
            }
            if hit
                break
        }
        if hit
            n += 1
    }
    return (n >= 20) ? 1 : 0
}

RejoinLog(msg) {
    try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") "  REJOIN: " msg "`n", LogFile)
}

; True at most once every ms milliseconds per key (so a slow screen isn't spammed with clicks).
Due(st, key, ms) {
    t := st.Has(key) ? st[key] : 0
    if (A_TickCount - t < ms)
        return false
    st[key] := A_TickCount
    return true
}

; Roblox only reacts to a click if it has seen the mouse ARRIVE on the button first, so the mouse comes in
; in a few small steps, rests a moment, and then the button is held down long enough to register.
ClickAt(x, y) {
    MouseMove x - 9, y - 4, 0
    Sleep 25
    MouseMove x + 6, y, 0              ; one jiggle: Roblox has to see the mouse arrive
    Sleep 25
    MouseMove x - 4, y + 1, 0
    Sleep 25
    MouseMove x, y, 0
    Sleep 45
    Click "Down"
    Sleep 60
    Click "Up"
    Sleep 30
}

DragMouse(x1, y1, x2, y2) {
    MouseMove x1, y1, 0
    Sleep 120
    Click "Down"
    Sleep 120
    steps := 12
    Loop steps {
        MouseMove x1 + (x2 - x1) * A_Index // steps, y1 + (y2 - y1) * A_Index // steps, 0
        Sleep 30
    }
    Sleep 100
    Click "Up"
}

; ---- special screens -----------------------------------------------------------------------
; Roblox error pop-up (Disconnected, Connection Failed ...): always click LEAVE (the left button, it takes you back to
; the Roblox home), never Reconnect. The buttons are found by themselves. If that ever clicks the wrong spot, hover the
; Leave button once and press F7: that spot is used instead. If nothing works, Roblox is closed and started again,
; but only if GamePlaceId is set.
HandleDialog(n) {
    global LeaveX, LeaveY, GamePlaceId
    if (LeaveX > 0 && n <= 6) {
        ClickAt(LeaveX, LeaveY)
        Sleep 1500
        return
    }
    if (LeaveX = 0 && n <= 8) {
        btns := WithSnap(FindDialogButtons)
        cx := DialogCX()
        gx := cx - 93                       ; where Leave sits in the usual pop-up (1920x1080: 867, 627)
        gy := DialogCY() + 87
        if (IsObject(btns) && btns.Length >= 2) {
            gx := btns[1][1]                ; leftmost button = Leave
            gy := btns[1][2]
        } else if (IsObject(btns) && btns.Length = 1) {
            if (btns[1][1] > cx)            ; only the bright Reconnect was seen: Leave is the button to its left
                gx := btns[1][1] - 185
            else
                gx := btns[1][1]
            gy := btns[1][2]
        }
        RejoinLog("error pop-up: clicking Leave at " gx ", " gy " (" (IsObject(btns) ? btns.Length : 0) " button(s) found, try " n ")")
        ClickAt(gx, gy)
        Sleep 1800
        return
    }
    if (GamePlaceId != "") {
        RejoinLog("error pop-up: closing Roblox to start the game again")
        try ProcessClose("RobloxPlayerBeta.exe")
        try ProcessClose("Windows10Universal.exe")
        Sleep 3000
        return
    }
    if (n = 9)
        RejoinLog("error pop-up won't go away (hover its Leave button and press F7 to save its position, or set GamePlaceId)")
    Sleep 2000
}

; Finds the buttons of the error pop-up without any calibration. Text is made of thin strokes, but a button is
; a wide flat patch of one colour, so wide flat runs (60 px or more) inside the box are buttons.
; Returns [[x, y, brightness], ...] from left to right (empty if none found).
FindDialogButtons() {
    cx := DialogCX()
    cy := DialogCY()
    yb := cy + 70                          ; bottom edge of the box: walk down while it is still the box gray
    while (yb < cy + 300 && GrayDiff(Px(cx - 185, yb + 1)) <= 8)
        yb += 1
    groups := []
    y := cy - 20
    while (y <= yb - 3) {
        x := cx - 175
        start := 0
        prev := 0
        while (x <= cx + 175) {
            c := Px(x, y)
            off := (GrayDiff(c) >= 60)
            if (off && start && ColorDiff(c, prev) <= 12) {
                prev := c
            } else {
                if (start && x - start >= 60)
                    AddRun(groups, start, x - 1, y, ColorSum(prev))
                start := 0
                if off {
                    start := x
                    prev := c
                }
            }
            x += 1
        }
        if (start && cx + 175 - start >= 60)
            AddRun(groups, start, cx + 175, y, ColorSum(prev))
        y += 2
    }
    out := []
    for g in groups {
        if (g[4] - g[3] >= 20)
            out.Push([(g[1] + g[2]) // 2, (g[3] + g[4]) // 2, g[5]])
    }
    n := out.Length
    Loop n {                               ; left to right
        j := 1
        while (j < n) {
            if (out[j][1] > out[j + 1][1]) {
                t := out[j]
                out[j] := out[j + 1]
                out[j + 1] := t
            }
            j += 1
        }
    }
    return out
}

; groups: each is [x1, x2, firstY, lastY, brightness]. A run joins the group it sits under, otherwise it starts a new one.
AddRun(groups, x1, x2, y, br) {
    for g in groups {
        ox := Min(g[2], x2) - Max(g[1], x1)
        if (ox >= 0.5 * Min(g[2] - g[1], x2 - x1) && y - g[4] <= 40) {
            g[1] := Min(g[1], x1)
            g[2] := Max(g[2], x2)
            g[4] := y
            return
        }
    }
    groups.Push([x1, x2, y, y, br])
}

GrayDiff(c) {
    return Abs(((c >> 16) & 0xFF) - 57) + Abs(((c >> 8) & 0xFF) - 59) + Abs((c & 0xFF) - 61)
}

ColorDiff(c1, c2) {
    return Abs(((c1 >> 16) & 0xFF) - ((c2 >> 16) & 0xFF)) + Abs(((c1 >> 8) & 0xFF) - ((c2 >> 8) & 0xFF)) + Abs((c1 & 0xFF) - (c2 & 0xFF))
}

; Roblox isn't running: start the game directly (only possible with GamePlaceId).
LaunchGame() {
    global GamePlaceId
    if (GamePlaceId = "") {
        RejoinLog("Roblox is not running and GamePlaceId is empty: can't start it")
        return false
    }
    RejoinLog("Roblox is not running: starting the game directly")
    try Run("roblox://experiences/start?placeId=" GamePlaceId)
    endT := A_TickCount + 90000
    while (A_TickCount < endT) {
        if RobloxRunning() {
            Sleep 10000
            return true
        }
        Sleep 1000
    }
    return false
}

; VIP SERVERS box (bottom left): click the text box, CONFIRM the cursor is in it (the cursor blinks, or the box
; changes), then press Enter once. If Enter brings up nothing within ~5 s, the whole thing is done again.
HandleVip(st) {
    if st["enter"] {
        if (A_TickCount - st["enterT"] > 5000) {
            st["rounds"] += 1
            st["enter"] := false
            st["vip"] := 0
            if (st["rounds"] >= 3) {         ; Enter doesn't seem to work: press PLAY on the menu instead
                RejoinLog("no LOBBY/TRADE pop-up after 3 times Enter: clicking PLAY on the menu")
                ClickAt(WinPosX(960, 402), WinPosY(610, 361))
                st["rounds"] := 0
            } else {
                RejoinLog("no LOBBY/TRADE pop-up after Enter: clicking the VIP box again (round " st["rounds"] ")")
            }
        }
        return
    }
    before := WithSnap(DarkPixelsVip)
    ClickAt(WinPosX(168, 74), WinPosY(972, 580))
    st["vip"] += 1
    focused := CursorBlinking(before)
    if (focused || st["vip"] >= 3) {
        RejoinLog("VIP text box: " (focused ? "cursor confirmed" : "cursor not seen after 3 clicks") ", pressing Enter")
        Sleep 200
        if (PrivateServerCode != "") {     ; joiner: put the private server code into the box first
            RejoinLog("VIP text box: pasting the private server code")
            saved := ""
            try saved := ClipboardAll()
            A_Clipboard := PrivateServerCode
            if ClipWait(1) {
                Send "^a"
                Sleep 120
                Send "^v"
                Sleep 350
            }
            try A_Clipboard := saved
        }
        PressKey("Enter")
        st["enter"] := true
        st["enterT"] := A_TickCount
    } else {
        RejoinLog("VIP text box: no cursor yet (click " st["vip"] ")")
    }
}

; The text cursor blinks, so the dark pixels inside the white text box change over ~1.5 s. Also counts as
; "in the box" if the box looks different from just before the click.
CursorBlinking(before := "") {
    mn := 999999
    mx := 0
    Loop 25 {
        n := WithSnap(DarkPixelsVip)
        if (n != "") {
            mn := Min(mn, n)
            mx := Max(mx, n)
        }
        Sleep 50
    }
    if (mx = 0)
        return false
    if ((mx - mn) >= 4)
        return true
    return (before != "" && Abs(mn - before) >= 8)
}

DarkPixelsVip() {
    n := 0
    y := WinMode ? WY + 575 : 963
    yEnd := WinMode ? WY + 586 : 984
    x0 := WinMode ? WX + 29 : 66
    x1 := WinMode ? WX + 121 : 271
    while (y < yEnd) {
        x := x0
        while (x < x1) {
            if (ColorSum(Px(x, y)) < 200)
                n += 1
            x += 1
        }
        y += 1
    }
    return n
}

; Game page: the big game icon (checks it's really AOTR).
GameIconOk() {
    global IconImg
    if !FileExist(IconImg)
        return true
    try {
        if ImageSearch(&fx, &fy, 540, 60, 820, 320, "*80 " IconImg)
            return true
    }
    return false
}

FinishRejoin() {
    global fastStartResult
    while ScriptPaused
        Sleep 250
    ToolTip("Rejoin: lobby ready, starting the main macro", TipX(), TipY(70))
    if (fastStartResult != "") {           ; F8 was already pressed the moment OBJECTIVES showed up
        r := (fastStartResult = "blind") ? 1 : ConfirmStarted()
        fastStartResult := ""
    } else {
        r := EnsureMain(true)
        if (r = -1)
            PressKey("F8")
    }
    RejoinLog("lobby ready, main macro start result: " r)
    ToolTip()
    return (r != 0)
}

; ---- the MODIFIERS list --------------------------------------------------------------------
; The list is LONGER than the four boxes we need (it goes on past FOG: GLASS CANNON, TIME TRIAL, FATIGUE ...), so it
; is never scrolled to the end. Each wanted box is found by its label (a small picture of the text in
; rejoin_assets), the list is scrolled one step at a time until that label is fully in view, and the box is
; clicked only while it is NOT ticked (checked again after every click).
HandleModifiers() {
    global ModifiersWanted, ModExact
    if WinMode
        return HandleModifiersWin()
    want := Map()
    for name in ModifiersWanted
        want[name] := true
    todo := Map()                          ; every modifier that needs a look: all of them when the others must be unticked
    for name in ModList() {
        if (want.Has(name) || ModExact)
            todo[name] := true
    }
    done := Map()
    dir := 1
    stall := 0
    deadWheel := 0
    Loop 40 {
        rows := WithSnap(ModRows)           ; which modifier is on which line right now (read from the text's shape)
        if IsObject(rows) {
            for r in rows {
                name := r[1]
                if (!todo.Has(name) || done.Has(name))
                    continue
                res := TickAt(r[2], want.Has(name))
                if (res = 1) {
                    done[name] := true
                    RejoinLog("modifier " name ": " (want.Has(name) ? "ticked" : "unticked") " (ok)")
                } else {
                    RejoinLog("modifier " name " could not be " (want.Has(name) ? "ticked" : "unticked"))
                    return false
                }
            }
        }
        if (done.Count >= todo.Count)
            return true
        h1 := WithSnap(ListHash)
        ScrollList(dir, deadWheel >= 2)
        Sleep 300
        h2 := WithSnap(ListHash)
        if (h1 != "" && h1 = h2) {          ; nothing moved: end of the list, or the wheel isn't working
            stall += 1
            deadWheel += 1
            if (stall >= 2) {
                dir := -dir
                stall := 0
            }
        } else {
            stall := 0
            deadWheel := 0
        }
    }
    RejoinLog("modifiers: gave up, not every box could be found and set")
    return false
}


; ===================== WINDOWED REJOIN: screen recognition and modifier list =====================
; All points below are relative to the Roblox window (WX, WY).
WinSigs() {
    static sg := 0
    if IsObject(sg)
        return sg
    sg := Map()
    sg["daily"] := ParsePts("514,177;127,474;761,132;112,237;322,177;538,278;409,177;453,177;365,177;112,277")
    sg["maps"] := ParsePts("170,365;631,237;575,497;384,262;327,428;226,223;492,369;208,497;631,373;418,422")
    sg["modes"] := ParsePts("76,395;754,194;467,523;387,259;725,459;255,523;584,336;148,234;245,358;603,523")
    sg["popup"] := ParsePts("411,363;201,425;261,295;540,382;261,375;390,299;411,327;390,384;390,345;261,353")
    sg["vip"] := ParsePts("737,591;14,230;354,452;14,605;636,413;93,415;488,383;330,309;133,551;763,425")
    sg["menu"] := ParsePts("455,322;21,449;696,436;380,452;537,419;351,283;117,413;359,339;411,409;84,383")
    sg["slots"] := ParsePts("545,351;196,404;340,271;406,404;461,287;255,323;279,413;605,404;251,247;508,413")
    sg["lobby"] := ParsePts("791,558;11,501;395,605;187,613;606,493;543,613;672,600;63,613;722,453;125,531")
    return sg
}

PtsHit(pts) {
    return SigHits(pts)
}

SigHits(pts) {
    n := 0
    for p in pts {
        if GoldAt(WX + p[1], WY + p[2])
            n += 1
    }
    return n
}

; The character CUSTOMIZATION screen (gold frame on the right, gold title, gold BACK button bottom left).
; Only the customization screen has a full-height gold frame line at x 578..580 together with a gold BACK at the bottom left.
CustomizeLook() {
    n := 0
    y := 220
    while (y <= 440) {
        if (GoldD(Px(WX + 579, WY + y)) || GoldD(Px(WX + 578, WY + y)) || GoldD(Px(WX + 580, WY + y)))
            n += 1
        y += 8
    }
    if (n < 24)
        return false
    return GoldAt(WX + 42, WY + 612)
}

; dialog, daily, modifiers, matchlobby, mapok, map, raidok, raid, mapwrong, modes, popup, vip, menu, slots, lobby, gamepage, search, home, other
; (call inside WithSnap)
ClassifyWin() {
    sg := WinSigs()
    if CustomizeLook()
        return "custom"
    if DisconnectDialogVisible()
        return "dialog"
    if (SigHits(sg["daily"]) >= 7)
        return "daily"
    frame := 0
    for p in [[230, 360], [572, 360], [401, 224], [401, 497]] {
        if GoldAt(WX + p[1], WY + p[2])
            frame += 1
    }
    if (frame >= 4) {
        leave := GoldAt(WX + 318, WY + 482)
        start := GoldAt(WX + 484, WY + 482)
        back := GoldAt(WX + 401, WY + 482)
        if (!back && !leave && !start)
            back := BackTextWhite()          ; BACK turns dark with white text while the mouse is on it
        if (back && !leave && !start)
            return "modifiers"
        if ((leave || start) && (leave + start + back >= 2))   ; one of the three buttons may be dark (hovered)
            return "matchlobby"
    }
    if LobbiesLook()
        return "lobbies"
    if (SigHits(sg["maps"]) >= 7)
        return MapScreenKind()
    if (SigHits(sg["modes"]) >= 7)
        return "modes"
    if (SigHits(sg["popup"]) >= 7)
        return "popup"
    ; Main menu: the gold-framed community icon in the top right corner (the scene behind the menu is animated, so only
    ; fixed UI is used). With the VIP SERVERS box showing at the bottom left (after CODES) it is the "vip" screen.
    if (PtsHit([[764, 58], [764, 64], [764, 70], [787, 58], [787, 64], [787, 70]]) >= 5) {
        if (PtsHit([[14, 560], [14, 590], [14, 606], [50, 541], [90, 541], [50, 613], [90, 613]]) >= 5)
            return "vip"
        return "menu"
    }
    if (SigHits(sg["slots"]) >= 7)
        return "slots"
    if (SigHits(sg["lobby"]) >= 7)
        return "lobby"
    blue := 0
    bR := []
    bG := []
    bB := []
    for p in [[340, 285], [430, 270], [520, 300], [435, 305], [380, 265]] {
        c := Px(WX + p[1], WY + p[2])
        r := (c >> 16) & 0xFF
        g := (c >> 8) & 0xFF
        b := c & 0xFF
        ; the PLAY button is a flat blue: bright, or dim (window not in focus), or lighter / darker on other Roblox versions
        if (b >= 120 && r <= 95 && g >= 40 && g <= 135 && b - r >= 85 && b - g >= 50) {
            blue += 1
            bR.Push(r)
            bG.Push(g)
            bB.Push(b)
        }
    }
    if (blue >= 4) {
        flat := (Max(bR*) - Min(bR*) <= 14 && Max(bG*) - Min(bG*) <= 14 && Max(bB*) - Min(bB*) <= 14)   ; one flat colour, not a scene
        if flat
            return "gamepage"
    }
    fld := 0
    for x in [200, 300, 450, 560, 620] {
        c := Px(WX + x, WY + 60)
        if (Abs(((c >> 16) & 0xFF) - 33) <= 6 && Abs(((c >> 8) & 0xFF) - 34) <= 6 && Abs((c & 0xFF) - 39) <= 6)
            fld += 1
    }
    if (fld < 4) {                         ; the light theme / new search overlay has a light grey field
        fld := 0
        for x in [200, 300, 450, 560, 620] {
            c := Px(WX + x, WY + 60)
            if (Abs(((c >> 16) & 0xFF) - 237) <= 8 && Abs(((c >> 8) & 0xFF) - 238) <= 8 && Abs((c & 0xFF) - 241) <= 8)
                fld += 1
        }
    }
    if (fld >= 4)
        return "search"
    white := 0
    y := 48
    while (y <= 70) {
        x := 95
        while (x <= 200) {
            if (ColorSum(Px(WX + x, WY + y)) > 600)
                white += 1
            x += 2
        }
        y += 2
    }
    if (white >= 150 && ColorSum(Px(WX + 33, WY + 114)) > 690)
        return "home"
    if LogoLoadingPx()
        return "loading"
    if BlackScreenPx()                      ; the black "waiting for players" screen before the first cutscene
        return "loading"
    return "other"
}

; Nearly everything black (a few spots are left out for the white text in the middle).
BlackScreenPx() {
    n := 0
    for q in [[100, 250], [700, 250], [150, 560], [650, 560], [400, 590], [400, 150], [60, 330], [740, 330], [200, 300], [600, 300], [400, 470], [400, 110], [250, 200], [550, 200], [250, 500], [550, 500]] {
        if (ColorSum(Px(WX + q[1], WY + q[2])) < 40)
            n += 1
    }
    return n >= 14
}

; The game's own loading screen: black all around, the red ATTACK ON TITAN logo in the middle and "Loading Data..." under it.
LogoLoadingPx() {
    dark := 0
    for q in [[100, 250], [700, 250], [150, 560], [650, 560], [400, 590], [400, 150], [60, 330], [740, 330]] {
        if (ColorSum(Px(WX + q[1], WY + q[2])) < 45)
            dark += 1
    }
    if (dark < 7)
        return false
    red := 0
    y := 190
    while (y <= 374) {
        x := 235
        while (x <= 544) {
            c := Px(WX + x, WY + y)
            r := (c >> 16) & 0xFF
            g := (c >> 8) & 0xFF
            b := c & 0xFF
            if (r >= 170 && r - b >= 90 && g <= 170)
                red += 1
            x += 2
        }
        y += 2
    }
    if (red < 600)          ; (counted on every 2nd pixel: about a quarter of the full count)
        return false
    wt := 0
    y := 415
    while (y <= 439) {
        x := 330
        while (x <= 469) {
            c := Px(WX + x, WY + y)
            if (Min((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF) >= 190)
                wt += 1
            x += 1
        }
        y += 1
    }
    return wt >= 60
}

; The map panel's title reads OUTSKIRTS: its gold text fills the title strip (and nothing gold on either side).
TitleOkWin() {
    n := 0
    y := WY + 236
    while (y <= WY + 251) {
        x := WX + 255
        while (x <= WX + 396) {
            if TitleGold(Px(x, y))
                n += 1
            x += 2
        }
        y += 2
    }
    if (n < 90)
        return false
    out := 0
    y := WY + 236
    while (y <= WY + 251) {
        x := WX + 215
        while (x <= WX + 440) {
            if TitleGold(Px(x, y))
                out += 1
            x += 2
            if (x = WX + 245)
                x := WX + 408
        }
        y += 2
    }
    if (out > 0)
        return false
    l := 0
    r := 0
    y := WY + 236
    while (y <= WY + 251) {
        x := WX + 255
        while (x <= WX + 265) {
            if TitleGold(Px(x, y))
                l += 1
            x += 1
        }
        x := WX + 386
        while (x <= WX + 396) {
            if TitleGold(Px(x, y))
                r += 1
            x += 1
        }
        y += 1
    }
    return (l > 0 && r > 0)
}

; ---- modifier list, windowed. Rows are fixed (12, pitch 34.5 px); the scroll handle tells how far the list moved.
HandleModifiersWin() {
    global ModifiersWanted, ModExact
    want := Map()
    for name in ModifiersWanted
        want[name] := true
    todo := Map()
    for i, name in ModList() {
        if (want.Has(name) || ModExact)
            todo[i] := name
    }
    done := Map()
    MouseMove WX + 330, WY + 385, 0
    Sleep 100
    Loop 14 {                              ; all the way to the top first
        Send "{WheelUp}"
        Sleep 60
    }
    Sleep 350
    lastThumb := -999
    same := 0
    first := true
    Loop 30 {
        res := WithSnap(ModScanWin)
        thumb := 309
        tops := []
        if IsObject(res) {
            if (res[1] > 0)
                thumb := res[1]
            else if !first
                thumb := lastThumb
            tops := res[2]
        }
        first := false
        off := (thumb - 309) * 251.5 / 97
        for t in tops {
            c := t + 10
            if (c < 316 || c > 456)
                continue
            r := Round((c + off - 323) / 34.5) + 1
            if (r < 1 || r > 12 || !todo.Has(r) || done.Has(r))
                continue
            if (TickAtWin(c, want.Has(todo[r])) = 1) {
                done[r] := true
                RejoinLog("modifier " todo[r] ": " (want.Has(todo[r]) ? "ticked" : "unticked") " (ok)")
            } else {
                RejoinLog("modifier " todo[r] " could not be " (want.Has(todo[r]) ? "ticked" : "unticked"))
                return false
            }
        }
        if (done.Count >= todo.Count)
            return true
        if (Abs(thumb - lastThumb) < 2) {
            same += 1
            if (same >= 2) {
                if (thumb >= 400) {
                    RejoinLog("modifiers: reached the end of the list but not every box was found")
                    return false
                }
                DragMouse(WX + 560, WY + thumb + 29, WX + 560, WY + thumb + 54)
                same := 0
                Sleep 300
                lastThumb := thumb
                continue
            }
        } else {
            same := 0
        }
        lastThumb := thumb
        MouseMove WX + 330, WY + 385, 0
        Sleep 60
        Send "{WheelDown}"
        Sleep 350
    }
    RejoinLog("modifiers: gave up, not every box could be found and set")
    return false
}

; Returns [thumbTop, [line tops...]] (call inside WithSnap).
ModScanWin() {
    thumb := 0
    start := 0
    y := 300
    while (y <= 470) {
        if (GoldD(Px(WX + 560, WY + y)) || GoldD(Px(WX + 561, WY + y))) {
            if !start
                start := y
        } else if start {
            if (y - start >= 40) {
                thumb := start
                break
            }
            start := 0
        }
        y += 1
    }
    if (!thumb && start && 471 - start >= 40)
        thumb := start
    tops := []
    st := 0
    y := 300
    while (y <= 470) {
        c := 0
        x := 275
        while (x <= 520) {
            if ModMask(Px(WX + x, WY + y))
                c += 1
            x += 1
        }
        if (c >= 4) {
            if !st
                st := y
        } else if st {
            if (y - st >= 8 && y - st <= 13)
                tops.Push(st)
            st := 0
        }
        y += 1
    }
    return [thumb, tops]
}

TickScoreWin(cy) {
    n := 0
    x := 241
    while (x <= 265) {
        y := cy - 12
        while (y <= cy + 12) {
            c := Px(WX + x, WY + y)
            r := (c >> 16) & 0xFF
            g := (c >> 8) & 0xFF
            b := c & 0xFF
            if (r > 120 && g > 110 && b > 60 && b < 130)
                n += 1
            y += 1
        }
        x += 1
    }
    return n
}

TickAtWin(cy, wantTick := true) {
    Loop 4 {
        t := WithSnap(() => TickScoreWin(cy))
        if (t != "" && ((t >= 35) = wantTick))
            return 1
        ClickAt(WX + 253, WY + cy)
        Sleep 450
    }
    t := WithSnap(() => TickScoreWin(cy))
    return (t != "" && ((t >= 35) = wantTick)) ? 1 : -1
}

; All 12 modifiers in the order they appear in the list.
ModList() {
    return ["NO PERKS", "NO SKILLS", "NO MEMORIES", "NIGHTMARE", "ODDBALL", "INJURY PRONE", "CHRONIC INJURIES", "FOG", "GLASS CANNON", "TIME TRIAL", "FATIGUE", "EVOLUTION"]
}

; 1 = the box is now as wanted (ticked if wantTick, unticked if not), -1 = couldn't set it.
; The box is clicked only when it is in the wrong state, and checked again after each click.
TickAt(cy, wantTick := true) {
    Loop 4 {
        ticked := WithSnap(() => TickScore(cy))
        if (ticked != "" && ((ticked >= 60) = wantTick))
            return 1
        ClickAt(624, cy)
        Sleep 450
    }
    ticked := WithSnap(() => TickScore(cy))
    return (ticked != "" && ((ticked >= 60) = wantTick)) ? 1 : -1
}

; ---- reading the modifier list WITHOUT pictures ------------------------------------------------------------
; Roblox draws the names slightly differently from one update to the next, so exact pictures stop matching.
; Instead: find the lines of big gold text in the list, measure how much text sits in each part of the line
; (a coarse "shape"), and compare it with the stored shape of each of the 12 names. Slight shifts and different
; anti-aliasing don't matter. Returns [[name, centreY of its tick box], ...] for the lines that are fully in view.
ModMask(c) {
    r := (c >> 16) & 0xFF
    g := (c >> 8) & 0xFF
    b := c & 0xFF
    return (r >= 100 && g >= 75 && r - b >= 40 && r >= g)
}

ModRows() {
    refs := ModRefs()
    tops := []
    start := 0
    y := 478
    while (y <= 836) {
        c := 0
        x := 672
        while (x < 930) {
            if ModMask(Px(x, y))
                c += 1
            x += 2
        }
        if (c >= 6) {
            if !start
                start := y
        } else if start {
            if (y - start >= 16 && y - start <= 30)
                tops.Push(start)
            start := 0
        }
        y += 2
    }
    if (start && 838 - start >= 16 && 838 - start <= 30)
        tops.Push(start)
    out := []
    for top in tops {
        f := ModFeat(top)
        best := 99999999
        second := 99999999
        bn := ""
        for name, ref in refs {
            d := 0
            for i, v in ref
                d += Abs(v - f[i])
            if (d < best) {
                second := best
                best := d
                bn := name
            } else if (d < second) {
                second := d
            }
        }
        cy := top + 23
        if (bn != "" && best <= 700 && (second + 1) >= 1.15 * (best + 1) && cy >= 506 && cy <= 802)
            out.Push([bn, cy])
    }
    return out
}

; 32 columns (8 px wide) x 4 bands (6 px tall) of "how many text pixels", smoothed sideways.
ModFeat(top) {
    raw := []
    b := 0
    while (b < 32) {
        r := 0
        while (r < 4) {
            c := 0
            y := top + r * 6
            while (y < top + r * 6 + 6) {
                x := 672 + 8 * b
                while (x < 672 + 8 * b + 8) {
                    if ModMask(Px(x, y))
                        c += 1
                    x += 2
                }
                y += 2
            }
            raw.Push(c)
            r += 1
        }
        b += 1
    }
    f := []
    for i, v in raw {
        sm := v * 2
        if (i - 4 >= 1)
            sm += raw[i - 4]
        if (i + 4 <= raw.Length)
            sm += raw[i + 4]
        f.Push(sm)
    }
    return f
}

; The stored shapes of the 12 names (made from the real list).
ModRefs() {
    static refs := Map(
        "NO PERKS", [14, 11, 11, 10, 10, 13, 16, 11, 12, 12, 16, 11, 20, 9, 13, 13, 19, 9, 10, 11, 11, 12, 10, 4, 9, 9, 10, 4, 17, 11, 11, 8, 22, 18, 11, 8, 21, 18, 9, 12, 16, 11, 4, 14, 16, 8, 5, 12, 23, 15, 13, 15, 24, 18, 15, 18, 21, 15, 16, 15, 15, 11, 14, 12, 11, 11, 5, 15, 14, 15, 4, 16, 11, 9, 8, 9, 3, 1, 4, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "NO SKILLS", [14, 11, 11, 10, 10, 13, 16, 11, 12, 12, 16, 11, 20, 9, 13, 13, 19, 9, 10, 11, 11, 12, 10, 4, 9, 12, 6, 5, 15, 14, 6, 12, 18, 13, 13, 13, 19, 12, 17, 12, 16, 11, 14, 12, 11, 7, 8, 13, 14, 9, 10, 15, 15, 9, 11, 17, 10, 6, 7, 18, 8, 6, 6, 18, 9, 10, 3, 18, 13, 15, 4, 16, 11, 9, 8, 9, 3, 1, 4, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "NO MEMORIES", [14, 11, 11, 10, 10, 13, 16, 11, 12, 13, 16, 11, 20, 11, 13, 13, 19, 10, 10, 11, 11, 12, 10, 4, 10, 11, 8, 5, 14, 14, 11, 10, 15, 20, 16, 10, 19, 21, 14, 13, 18, 18, 9, 15, 12, 13, 3, 13, 13, 10, 3, 13, 15, 14, 11, 12, 15, 20, 17, 10, 19, 21, 18, 11, 19, 13, 14, 11, 19, 9, 10, 11, 21, 15, 13, 11, 18, 16, 16, 10, 17, 15, 14, 12, 20, 15, 11, 16, 23, 15, 13, 17, 22, 16, 12, 16, 16, 11, 4, 15, 13, 10, 0, 15, 15, 15, 4, 15, 11, 9, 8, 9, 3, 1, 4, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "NIGHTMARE", [14, 11, 11, 10, 10, 13, 16, 11, 10, 12, 14, 12, 13, 14, 15, 13, 12, 13, 15, 13, 13, 5, 9, 15, 16, 6, 10, 15, 15, 16, 11, 12, 14, 17, 8, 10, 22, 13, 11, 12, 23, 9, 10, 11, 18, 6, 6, 10, 16, 10, 11, 11, 16, 20, 17, 9, 17, 22, 15, 12, 15, 12, 13, 12, 15, 10, 18, 8, 15, 14, 21, 12, 18, 15, 18, 14, 18, 15, 12, 11, 17, 16, 8, 14, 22, 17, 8, 19, 16, 9, 4, 14, 4, 1, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "ODDBALL", [11, 10, 10, 10, 17, 9, 9, 13, 17, 11, 11, 11, 16, 10, 10, 12, 16, 6, 7, 13, 19, 9, 12, 12, 22, 9, 12, 14, 18, 9, 9, 15, 15, 16, 13, 14, 18, 20, 15, 16, 15, 16, 13, 17, 11, 11, 13, 11, 12, 14, 18, 5, 11, 16, 20, 8, 10, 10, 12, 13, 10, 6, 6, 14, 10, 6, 6, 14, 5, 3, 3, 10, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "INJURY PRONE", [14, 9, 9, 9, 16, 14, 11, 9, 15, 16, 13, 6, 13, 11, 14, 9, 11, 9, 12, 12, 17, 15, 16, 11, 16, 12, 14, 11, 10, 6, 8, 12, 15, 9, 11, 11, 20, 13, 14, 11, 20, 13, 11, 10, 17, 15, 7, 7, 14, 17, 6, 5, 12, 9, 3, 2, 11, 4, 5, 3, 16, 11, 12, 6, 21, 16, 13, 7, 22, 13, 16, 10, 17, 12, 18, 10, 13, 15, 13, 11, 18, 11, 8, 16, 18, 7, 7, 13, 15, 15, 11, 7, 19, 22, 17, 9, 18, 18, 20, 11, 16, 15, 16, 12, 19, 15, 9, 15, 14, 9, 3, 11, 4, 2, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "CHRONIC INJURIES", [11, 10, 10, 12, 15, 5, 5, 17, 15, 6, 4, 14, 18, 18, 11, 12, 17, 19, 11, 10, 16, 11, 9, 9, 20, 13, 12, 12, 17, 19, 14, 12, 11, 14, 11, 11, 13, 10, 10, 14, 16, 15, 15, 13, 15, 16, 14, 7, 15, 14, 13, 5, 16, 13, 17, 8, 14, 11, 15, 9, 14, 10, 12, 11, 17, 8, 9, 17, 13, 3, 3, 15, 10, 3, 4, 9, 15, 9, 11, 10, 16, 14, 11, 9, 18, 19, 14, 9, 18, 17, 19, 14, 13, 12, 15, 14, 18, 16, 15, 10, 19, 14, 12, 10, 15, 8, 6, 14, 22, 11, 10, 15, 25, 12, 17, 13, 17, 10, 16, 10, 14, 11, 10, 10, 14, 9, 8, 10],
        "FOG", [15, 11, 7, 6, 16, 14, 10, 4, 11, 11, 11, 7, 13, 10, 11, 14, 13, 17, 17, 12, 11, 16, 16, 10, 16, 5, 7, 15, 15, 0, 4, 13, 5, 0, 2, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "GLASS CANNON", [10, 12, 12, 13, 13, 6, 9, 15, 14, 6, 12, 13, 14, 12, 16, 20, 10, 10, 14, 22, 10, 13, 18, 15, 12, 18, 16, 15, 15, 17, 9, 18, 17, 14, 8, 16, 15, 14, 5, 14, 13, 14, 5, 12, 8, 8, 9, 6, 7, 7, 11, 6, 14, 8, 11, 14, 13, 6, 11, 18, 10, 12, 15, 14, 12, 15, 16, 10, 12, 10, 13, 15, 12, 11, 14, 17, 9, 13, 16, 12, 13, 13, 14, 13, 17, 14, 14, 15, 10, 13, 16, 12, 9, 15, 17, 11, 14, 15, 15, 13, 16, 11, 10, 12, 18, 14, 11, 10, 17, 17, 15, 9, 13, 18, 19, 8, 12, 16, 17, 8, 6, 6, 6, 4, 0, 0, 0, 0],
        "TIME TRIAL", [16, 3, 3, 5, 21, 9, 9, 10, 14, 9, 9, 12, 11, 9, 7, 12, 16, 15, 12, 9, 17, 18, 15, 8, 18, 19, 13, 14, 18, 17, 9, 18, 12, 10, 3, 14, 7, 3, 0, 5, 12, 3, 3, 4, 17, 6, 6, 9, 16, 9, 9, 9, 19, 16, 15, 12, 19, 17, 15, 17, 11, 11, 13, 16, 11, 10, 15, 10, 16, 12, 17, 7, 13, 10, 17, 13, 10, 7, 11, 18, 5, 3, 3, 13, 0, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "FATIGUE", [15, 12, 6, 9, 14, 13, 9, 9, 11, 13, 18, 9, 13, 10, 18, 10, 18, 9, 12, 13, 23, 15, 15, 15, 18, 14, 14, 11, 12, 10, 11, 11, 15, 8, 13, 17, 17, 3, 10, 15, 14, 3, 6, 10, 15, 9, 9, 13, 18, 12, 12, 13, 17, 14, 10, 12, 16, 13, 5, 15, 11, 5, 1, 11, 3, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "EVOLUTION", [15, 13, 6, 14, 16, 15, 3, 13, 11, 12, 7, 9, 8, 8, 14, 10, 14, 9, 12, 9, 21, 10, 10, 12, 19, 10, 10, 13, 15, 15, 13, 11, 11, 12, 11, 14, 10, 6, 6, 15, 15, 9, 9, 14, 16, 9, 9, 10, 17, 6, 6, 7, 18, 6, 6, 8, 14, 6, 6, 8, 15, 10, 11, 10, 18, 11, 13, 12, 17, 10, 10, 12, 18, 15, 13, 12, 17, 16, 14, 10, 11, 14, 13, 9, 7, 10, 11, 10, 3, 3, 4, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
    return refs
}

; Warns once when Windows display scaling is not 100 percent (every position in this script assumes 100).
DpiWarn() {
    global IniFile
    scale := Round(A_ScreenDPI / 96 * 100)
    if (scale = 100)
        return
    seen := IniRead(IniFile, "app", "DpiWarned", "")
    if (seen = scale "")
        return
    try IniWrite(scale "", IniFile, "app", "DpiWarned")
    MsgBox("Windows display scaling is " scale "%.`n`nThe macro only clicks the right places at 100%.`n`nSet it in Windows: Settings > System > Display > Scale = 100%, then sign out and back in (or restart the RDP session) and start the macro again.", "THY HOZ's AOTR MACRO", "Icon! 262144")
}

; Settings > Save diagnostics: one text file + screenshot to send when something does not work.
SaveDiagnostics() {
    global IniFile, LogFile, WinMode, WX, WY, WW, WH, CurMap, ModifiersWanted, KeyChest, BuiltIn, UseVip, AutoStartEnd, WebhookUrl, GamePlaceId, MacroActive
    t := "AOTR MACRO DIAGNOSTICS " FormatTime(, "yyyy-MM-dd HH:mm:ss") "`n"
    t .= "AutoHotkey " A_AhkVersion "   Windows " A_OSVersion "   admin: " (A_IsAdmin ? "yes" : "NO") "`n"
    t .= "Screen " A_ScreenWidth "x" A_ScreenHeight "   display scale " Round(A_ScreenDPI / 96 * 100) "%`n"
    t .= "Roblox window: " WX "," WY " size " WW "x" WH "   WinMode " WinMode "`n"
    t .= "Selected: " CurMap "   macro: " MacroActive "   built-in: " BuiltIn "   VIP join: " UseVip "   auto retry: " AutoStartEnd "`n"
    mods := ""
    for m in ModifiersWanted
        mods .= m ", "
    t .= "Modifiers: " mods "   key chest: " KeyChest "   webhook set: " (WebhookUrl != "" ? "yes" : "no") "   game id: " GamePlaceId "`n"
    t .= "`n---- last log lines ----`n"
    log := ""
    try log := FileRead(LogFile, "UTF-8")
    arr := StrSplit(log, "`n", "`r")
    start := Max(1, arr.Length - 200)
    k := start
    while (k <= arr.Length) {
        t .= arr[k] "`n"
        k += 1
    }
    f := A_ScriptDir "\diagnostics.txt"
    try FileDelete(f)
    FileAppend(t, f, "UTF-8")
    shot := ""
    try shot := TakeShot("diagnostics")
    try Run('explorer.exe /select,"' f '"')
    ToolTip("Saved diagnostics.txt (and a screenshot in the shots folder). Send them with your question.", TipX(), TipY(10))
    SetTimer(() => ToolTip(), -5000)
}

; Settings > Ping options: choose which events @ping you on Discord (the report itself is always sent).
PingPicker() {
    global PingOnMythic, PingOnDivine, PingOnScroll, PingOnFail, PingOnDisconnect, PingOnStuck, PingOnGaveUp, StatusMsgs
    g := Gui("+AlwaysOnTop", "Ping options")
    g.SetFont("s10")
    g.AddText(, "Tick what should @ping you on Discord.`nThe reports are sent either way, this only decides the ping.")
    g.AddText("y+12", "Drops")
    c1 := g.AddCheckbox((PingOnMythic ? "Checked" : ""), "Mythic drop")
    c2 := g.AddCheckbox((PingOnDivine ? "Checked" : ""), "Divine drop")
    c3 := g.AddCheckbox((PingOnScroll ? "Checked" : ""), "Scroll drop")
    g.AddText("y+10", "Rounds")
    c4 := g.AddCheckbox((PingOnFail ? "Checked" : ""), "Mission / raid failed (also a retreat)")
    g.AddText("y+10", "Problems")
    c5 := g.AddCheckbox((PingOnDisconnect ? "Checked" : ""), "Account disconnected")
    c6 := g.AddCheckbox((PingOnStuck ? "Checked" : ""), "Mission looks stuck")
    c7 := g.AddCheckbox((PingOnGaveUp ? "Checked" : ""), "Could not rejoin, macro stopped")
    g.AddText("y+10", "Messages")
    c8 := g.AddCheckbox((StatusMsgs ? "Checked" : ""), "Also post the short 'back in / reconnected' messages")
    b := g.AddButton("y+16 w110 Default", "Save")
    b.OnEvent("Click", PingPickerSave.Bind(g, [c1, c2, c3, c4, c5, c6, c7, c8]))
    c := g.AddButton("x+10 w110", "Cancel")
    c.OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Close", (*) => g.Destroy())
    g.Show()
}

PingPickerSave(g, cs, *) {
    global PingOnMythic, PingOnDivine, PingOnScroll, PingOnFail, PingOnDisconnect, PingOnStuck, PingOnGaveUp, StatusMsgs, IniFile
    PingOnMythic := cs[1].Value ? true : false
    PingOnDivine := cs[2].Value ? true : false
    PingOnScroll := cs[3].Value ? true : false
    PingOnFail := cs[4].Value ? true : false
    PingOnDisconnect := cs[5].Value ? true : false
    PingOnStuck := cs[6].Value ? true : false
    PingOnGaveUp := cs[7].Value ? true : false
    StatusMsgs := cs[8].Value ? true : false
    for k, v in Map("Mythic", PingOnMythic, "Divine", PingOnDivine, "Scroll", PingOnScroll, "Fail", PingOnFail, "Disconnect", PingOnDisconnect, "Stuck", PingOnStuck, "GaveUp", PingOnGaveUp, "Status", StatusMsgs)
        try IniWrite(v ? "1" : "0", IniFile, "ping", k)
    g.Destroy()
    ToolTip("Ping options saved.", TipX(), TipY(10))
    SetTimer(() => ToolTip(), -2500)
}

; Ctrl+Shift+F6: window to choose the modifiers.
ModPicker() {
    global ModifiersWanted, ModExact, ModSkip, CurMap
    g := Gui("+AlwaysOnTop", "Modifiers for " CurMap)
    g.SetFont("s10")
    g.AddText(, "Modifiers for " CurMap " (saved for this mission / raid only).`nTick the ones the rejoin should switch ON:")
    want := Map()
    for n in ModifiersWanted
        want[n] := true
    boxes := []
    for n in ModList()
        boxes.Push(g.AddCheckbox((want.Has(n) ? "Checked" : ""), n))
    cSk := g.AddCheckbox("y+14 " (ModSkip ? "Checked" : ""), "Don't touch the modifiers at all (skip the whole screen)")
    b := g.AddButton("y+14 w100 Default", "Save")
    b.OnEvent("Click", ModPickerSave.Bind(g, boxes, cSk))
    c := g.AddButton("x+10 w100", "Cancel")
    c.OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Close", (*) => g.Destroy())
    g.Show()
}

ModPickerSave(g, boxes, cSk, *) {
    global ModifiersWanted, ModExact, ModSkip, IniFile, CurMap
    arr := []
    for bx in boxes {
        if bx.Value
            arr.Push(bx.Text)
    }
    ModifiersWanted := arr
    ModSkip := cSk.Value ? true : false
    txt := ""
    for n in arr
        txt .= (txt = "" ? "" : "|") n
    try IniWrite(txt = "" ? "NONE" : txt, IniFile, "opts", "Modifiers_" CurMap)
    try IniWrite(ModSkip ? "1" : "0", IniFile, "opts", "ModSkip_" CurMap)
    RejoinLog("modifiers for " CurMap " set to: " (txt = "" ? "none" : txt) "; skip screen: " ModSkip)
    g.Destroy()
    ToolTip("Modifiers saved: " (ModSkip ? "not touched" : (txt = "" ? "none" : txt)), TipX(), TipY(10))
    SetTimer(() => ToolTip(), -3000)
}

; Loads the modifiers saved for this mission / raid (or the defaults when none were saved yet).
ModLoadFor(name) {
    global ModifiersWanted, ModSkip, ModDefault, ModSkipDefault, IniFile
    v := IniRead(IniFile, "opts", "Modifiers_" name, "<unset>")
    if (v = "<unset>") {
        ModifiersWanted := ModDefault.Clone()
        ModSkip := ModSkipDefault
        return
    }
    ModifiersWanted := (v = "NONE" || v = "") ? [] : StrSplit(v, "|")
    ModSkip := (IniRead(IniFile, "opts", "ModSkip_" name, "0") = "1")
}

; A number that changes whenever the list has scrolled (sampled over the whole list area).
ListHash() {
    h := 0
    y := 484
    while (y <= 830) {
        x := 600
        while (x <= 1320) {
            h := Mod(h * 31 + (Px(x, y) & 0xFFFFFF), 1000000007)
            x += 20
        }
        y += 6
    }
    return h
}

; One scroll step: one notch of the mouse wheel over the list, or (when the wheel does nothing) a small drag of the
; scroll bar's handle.
ScrollList(dir, useBar := false) {
    if useBar {
        thumb := WithSnap(FindThumb)
        if (thumb != "" && thumb > 0) {
            DragMouse(1328, thumb, 1328, thumb + dir * 30)
            return
        }
    }
    MouseMove 960, 650, 0
    Sleep 80
    if (dir > 0)
        Send "{WheelDown}"
    else
        Send "{WheelUp}"
}

; Middle of the scroll bar's gold handle (right edge of the list), 0 if not found.
FindThumb() {
    y := 470
    start := 0
    while (y <= 842) {
        hit := GoldD(Px(1327, y)) || GoldD(Px(1328, y)) || GoldD(Px(1329, y))
        if hit {
            if !start
                start := y
        } else if start {
            if (y - start >= 30)
                return (start + y) // 2
            start := 0
        }
        y += 1
    }
    if (start && 842 - start >= 30)
        return (start + 842) // 2
    return 0
}

; Number of tan "tick" pixels inside a box (an empty box is near-black inside).
TickScore(cy) {
    n := 0
    x := 610
    while (x <= 638) {
        y := cy - 18
        while (y <= cy + 18) {
            c := Px(x, y)
            r := (c >> 16) & 0xFF
            g := (c >> 8) & 0xFF
            b := c & 0xFF
            if (r > 120 && g > 110 && b > 60 && b < 130)
                n += 1
            y += 1
        }
        x += 1
    }
    return n
}

; ---- which screen is this? -------------------------------------------------------------------
; Runs fn() against a frozen snapshot of the screen (Px() reads from it) and returns its result.
; Like WithSnap, but copies only a rectangle of the screen (a few ten thousand pixels instead of two million): 10-30 times faster.
WithRegion(fn, x0, y0, w, h) {
    global SnapCur
    snap := GrabRect(x0, y0, w, h)
    if !IsObject(snap)
        return ""
    Critical "On"
    SnapCur := snap
    r := ""
    try r := fn()
    SnapCur := 0
    Critical "Off"
    FreeGrab(snap)
    return r
}

; PanelOk on a copy of just the end panel (windowed mode); the whole-screen copy is the fallback.
PanelOkFast() {
    global SnapCur, WinMode, WX, WY, WW
    if IsObject(SnapCur)
        return PanelOk()
    r := ""
    if (WinMode && WW > 0)
        r := WithRegion(PanelOk, WX + 220, WY + 170, 360, 320)
    else
        r := WithSnap(PanelOk)
    return (r = "") ? PanelOk() : (r ? true : false)
}

WithSnap(fn) {
    global SnapCur
    snap := CaptureSnap()
    if !IsObject(snap)
        return ""
    Critical "On"
    SnapCur := snap
    r := ""
    try r := fn()
    SnapCur := 0
    Critical "Off"
    FreeSnap(snap)
    return r
}

DetectScreen() {
    global HomeTileX, HomeTileY
    if WinMode {
        sw := WithSnap(ClassifyWin)
        return (sw = "") ? "other" : sw
    }
    scr := WithSnap(ClassifyScreen)
    if (scr = "")
        return "other"
    if (scr = "other" && FindTile(&tx, &ty)) {
        HomeTileX := tx
        HomeTileY := ty
        return "home"
    }
    return scr
}

; dialog, modifiers, matchlobby, mapok, map, modes, popup, vip, menu, slots, slotshover, lobby, gamepage, other
; The DAILY REWARDS pop-up: its gold title "DAILY REWARDS" sits in the middle (nothing gold either side of it, unlike
; the wider MISSION COMPLETED title) and its close button (a pale X in a frame) is in the top right corner.
DailyRewardsVisible() {
    t := 0
    y := 205
    while (y <= 241) {
        x := 780
        while (x <= 1140) {
            if TitleGold(Px(x, y))
                t += 1
            x += 2
        }
        y += 2
    }
    if (t < 300)
        return false
    side := 0
    y := 205
    while (y <= 241) {
        x := 640
        while (x <= 1290) {
            if TitleGold(Px(x, y))
                side += 1
            x += 2
            if (x = 742)
                x := 1190
        }
        y += 2
    }
    if (side > 10)
        return false
    pale := 0
    y := 150
    while (y <= 222) {
        x := 1815
        while (x <= 1890) {
            c := Px(x, y)
            r := (c >> 16) & 0xFF
            g := (c >> 8) & 0xFF
            b := c & 0xFF
            if (r >= 150 && g >= 130 && b >= 80 && r - b <= 110)
                pale += 1
            x += 2
        }
        y += 2
    }
    return pale >= 100
}

; The BACK pill when it is dark (hovered): white letters on a dark button.
BackTextWhite() {
    n := 0
    y := 478
    while (y <= 487) {
        x := 390
        while (x <= 412) {
            if (ColorSum(Px(WX + x, WY + y)) > 700)
                n += 1
            x += 1
        }
        y += 1
    }
    return n >= 6
}

ClassifyScreen() {
    if DisconnectDialogVisible()
        return "dialog"
    if DailyRewardsVisible()                ; checked before "menu": the top bar is still showing behind this pop-up
        return "daily"
    frame := GoldPts([[569, 600], [1350, 600], [960, 284], [960, 905]]) >= 4
    leave := GoldAt(770, 870)
    start := GoldAt(1150, 870)
    if (frame && !leave && !start && GoldAt(960, 874))
        return "modifiers"
    if (frame && leave && start)
        return "matchlobby"
    if (GoldPts([[435, 600], [1144, 600], [790, 284], [790, 905], [1169, 600], [1485, 600], [1327, 284], [1327, 905]]) >= 7)
        return TitleOk() ? "mapok" : "map"
    if (GoldPts([[286, 630], [581, 630], [637, 630], [932, 630], [988, 630], [1283, 630], [1339, 630], [1634, 630]]) >= 7)
        return "modes"
    if (GoldPts([[636, 540], [936, 540], [985, 540], [1285, 540], [1306, 317], [1358, 317], [1331, 292], [1331, 342]]) >= 6)
        return "popup"
    onMenu := GoldPts([[1833, 60], [1887, 60], [1860, 32], [1860, 87]]) >= 3
    if (onMenu && GoldPts([[33, 970], [303, 970], [168, 885], [168, 1050]]) >= 3)
        return "vip"
    if onMenu
        return "menu"
    if (GoldPts([[490, 540], [768, 540], [821, 540], [1099, 540], [1152, 540], [1429, 540], [629, 688], [960, 688], [1291, 688]]) >= 7 && ColorSum(Px(900, 200)) < 90)
        return "slots"
    ; mouse resting on slot A: that card grows (476-781) and pushes B and C to the right; its SELECT loses the gold
    if (GoldPts([[477, 540], [780, 540], [835, 540], [1112, 540], [1165, 540], [1442, 540], [974, 689], [1304, 689]]) >= 7 && ColorSum(Px(900, 200)) < 90)
        return "slotshover"
    bar := 0
    for x in [200, 330, 520, 700, 800, 950, 1100, 1250, 1350, 1500, 1650, 1850] {
        hit := false
        Loop 4 {
            if GoldD(Px(x, 133 + A_Index))
                hit := true
        }
        if (hit && ColorSum(Px(x, 125)) < 90)
            bar += 1
    }
    if (bar >= 5)
        return "lobby"
    if (IsBlue(Px(800, 245)) && IsBlue(Px(906, 236)) && IsBlue(Px(1010, 270)) && IsBlue(Px(850, 268)))
        return "gamepage"
    return "other"
}

; Gold of the game's UI borders (bright, or dimmed by a dark overlay).
GoldD(c) {
    r := (c >> 16) & 0xFF
    g := (c >> 8) & 0xFF
    b := c & 0xFF
    return r >= 120 && g >= 85 && (r - b) >= 55 && r >= g
}

; True if any pixel within rad of (x, y) is gold (the screen can be a pixel off from where I measured).
GoldAt(x, y, rad := 2) {
    dx := -rad
    while (dx <= rad) {
        dy := -rad
        while (dy <= rad) {
            if GoldD(Px(x + dx, y + dy))
                return true
            dy += 1
        }
        dx += 1
    }
    return false
}

GoldPts(pts) {
    n := 0
    for p in pts {
        if GoldAt(p[1], p[2])
            n += 1
    }
    return n
}

IsBlue(c) {
    r := (c >> 16) & 0xFF
    g := (c >> 8) & 0xFF
    b := c & 0xFF
    return b >= 220 && r <= 100 && g <= 140
}

ColorSum(c) {
    return ((c >> 16) & 0xFF) + ((c >> 8) & 0xFF) + (c & 0xFF)
}

; The map panel's title must read OUTSKIRTS. TitlePos = points that are gold text in that title,
; TitleNeg = points around it that are NOT. Both must match (90%), so a different map name fails.
TitleGold(c) {
    r := (c >> 16) & 0xFF
    g := (c >> 8) & 0xFF
    b := c & 0xFF
    return r >= 190 && g >= 140 && b <= 160
}

TitleOk() {
    global TitlePos, TitleNeg
    a := 0
    for p in TitlePos {
        if TitleGold(Px(p[1], p[2]))
            a += 1
    }
    b := 0
    for p in TitleNeg {
        if !TitleGold(Px(p[1], p[2]))
            b += 1
    }
    return (a >= TitlePos.Length * 0.9 && b >= TitleNeg.Length * 0.9)
}

ParsePts(s) {
    arr := []
    for item in StrSplit(s, ";") {
        p := StrSplit(item, ",")
        arr.Push([Integer(p[1]), Integer(p[2])])
    }
    return arr
}

; The AOTR tile on the Roblox home screen (same picture on the dark and the white home screen).
FindTile(&x, &y) {
    global TileImg
    x := 0
    y := 0
    if !FileExist(TileImg)
        return false
    try {
        if ImageSearch(&fx, &fy, 0, 0, A_ScreenWidth, A_ScreenHeight, "*80 " TileImg) {
            x := fx
            y := fy
            return true
        }
    }
    return false
}

; ---- the two small pictures (stored inside this script, written next to it on first start) ----
EnsureAssets() {
    global TileImg, IconImg
    try DirCreate(A_ScriptDir "\rejoin_assets")
    if !FileExist(TileImg)
        try WriteB64File(TileImg, TileB64())
    if !FileExist(IconImg)
        try WriteB64File(IconImg, IconB64())
}

WriteB64File(file, b64) {
    b64 := RegExReplace(b64, "\s")
    n := 0
    DllCall("crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0, "UInt", 1, "Ptr", 0, "UInt*", &n, "Ptr", 0, "Ptr", 0)
    buf := Buffer(n)
    DllCall("crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0, "UInt", 1, "Ptr", buf, "UInt*", &n, "Ptr", 0, "Ptr", 0)
    f := FileOpen(file, "w")
    f.RawWrite(buf, n)
    f.Close()
}

; ---- hotkeys for setting up / testing -------------------------------------------------------
; F4 = tell me which screen the script thinks it is looking at
ShowScreen() {
    if WinMode {
        s := ""
        try s := WithSnap(WinScreenName)
        ToolTip("Screen detected: " (s = "" ? "unknown" : s) "`nRoblox window: " WX ", " WY "  " WW "x" WH "  (" latchMsg ")", TipX(), TipY(10))
        SetTimer(() => ToolTip(), -4000)
        return
    }
    scr := DetectScreen()
    extra := ""
    if (scr = "dialog") {
        btns := WithSnap(FindDialogButtons)
        extra := "`nButtons found: "
        if (IsObject(btns) && btns.Length > 0) {
            for b in btns
                extra .= "(" b[1] ", " b[2] ", brightness " b[3] ") "
        } else {
            extra .= "none"
        }
    }
    ToolTip("Screen detected: " scr extra, TipX(), TipY(10))
    SetTimer(() => ToolTip(), -4000)
}

; F7 = hover the LEAVE button of a Roblox error pop-up and press F7 once to save its position
CalibrateLeave() {
    global LeaveX, LeaveY, IniFile
    MouseGetPos(&x, &y)
    LeaveX := x
    LeaveY := y
    IniWrite(x, IniFile, "pos", "LeaveX")
    IniWrite(y, IniFile, "pos", "LeaveY")
    ToolTip("Saved the Leave button position: " x ", " y, TipX(), TipY(10))
    SetTimer(() => ToolTip(), -2500)
}

; Ctrl+Shift+F10 = run the whole automatic rejoin from whatever screen is showing now
TestAutoRejoin() {
    global busyReconnect, ForceLink
    if busyReconnect
        return
    busyReconnect := true
    ForceLink := true
    ok := false
    try ok := AutoRejoinOnce()
    busyReconnect := false
    ToolTip("Automatic rejoin test: " (ok ? "finished, main macro running" : "FAILED (see mission_failed_f8.log)"), TipX(), TipY(10))
    SetTimer(() => ToolTip(), -6000)
}

; One automatic rejoin attempt (kept under this name so RejoinSequence needs no change).
RejoinAttempt(expectDialogFirst := false) {
    return AutoRejoinOnce()
}

TileB64() {
    s := "
(
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
ets0GmDZ2LyYHL3zk+/Hkvuj1BslyWCYnJxk8yRPkt4bX3/1H/5HfkO7tMJH2+bXH0TpcNV37a7p9MxuWgZTe/Ol33n3l8ONTu/M
6ioy+Tn0ouaoGW+d30zy6d7eZ1cePao21wPnnQxOms4dHRweTOYVqAqUKI9U4GyRl4gqyycwHhyvTYYgiIJelkE5l8m0mO8/+PHH
tz/e24ngk3Iyns5FGd8zaZpM5vOHJ0X/ycifT25++cXXv/W1V195ocTqR+89sJGnd9bO8q8+ePmbZ8OWDvd3/bd+XT08OKEV/pN/
79xLNyWOy5Ojx++/99f/5L9/yaY9P+x5gQQUBBQFEYVROj7QyRz8uJpmUYhbVzpvPzh5y8kZzz/balEzv7Hu337/0dWzX9rorFTz
mWcJKurFraNmnLSCZsM7+uxu+vCh68UxU3l80nBcZoXfXTGgGXRhoazAVWlRIqisyGg8GKxNh2BCNKGX5GY62bv/6d79Tz8dz28X
s/2UDp1C1QFEL26mJQ6KYn7C0+So40tx//6rX7nxxnf/4PIfvXr7H//P6cO5Plxp8Kj/jUnAQTHM7ulpqrycocBpH+bnGBUXBZfl
hfbKVtT7FWVjExRZnidZa5w0S3m505rvHvTENxUorf2MJ5V9snd0Mh09PvAubHQurHfu//qd3/1v/oOGH6i8PJrPVzKN03wzXHEQ
Nxr6SbfhfnPQCtbsatpC2Dk8+Hvf/p0//+Vbk9yubZ7LS9U/mrNI4WgaetMiLeYJjMbAYxCUPJU8a2Z4VrpDSk7MbFoZSLUEfqe3
/tyV87NZJ8/zwWSGoAWVhDGH4WR8rNPh6998NR39Sgdfurn7r3eSDw/VNTfy5mgMel7HFXpyJPOxqFjygsuyzSrn7BfD473S14no
lHuh6kXqFZfMdg96QUfpUBnl5YxxTCqa5Ty2JVeTYlq8fvM14xuXZSqv+uOBPzeNLO8EvRIax4PDj5p29Xj/dx6vC2fnO50nfjA4
eHzr+fXb27tr616ee4PBuAQpnJrF3rScLOzPcylyYRAGv9ejrbWrx17jOE8fZfcG+Wg6ZxNuTmeDw93JaJgWIGgrCjmMJQgmo+PI
jV//5quf/uQT9Y+++91092Cw/SS01l2ID9HNpqVC3zNha2VL/IabzU6e7Ox/9H7Ph3ens/EMfW3CRkhYNkJ1YdVshue6jTYAVdl4
/uHtnWax08+zsjBGNxnt8fDG1VtnL18NG2FSJqPHHwxHo0DYy8uQ3fDx7sHR3r0pb3abbS1G6WYQf/T2O6ukb926fufxp2k6y8qZ
rfIobjSN6e8cv7R5fuvcFpHmLD9KJiYrQ+P5a41OFK311iUpq7DYng4Hh5PRdPK0fzSeMyOIkHNg8+yo31fWrl5/Y3tv+5c/+CVd
vnbz/K0v9rVXHc0hUIdoD8bJsMxt/8iNJpzmMs9knubofKWpApk7rUzYazjN6MPczt3+oTsZyjxRDvKkilpUoUlzi6LaQast0dUb
N9p+6Gmajo756ceP9j+dZoMkn5Mxl/0zz1X05mD/02mfB0f5/lHM4X/6d/7+ej87+fCj37p+bq3lPDVElThVpRBOkPNpUjoB43Ml
h8mkmE7h+KQY9d1mz/ze61967eZ/+Ac3r95Y9cQNTsYzq8Fodljkkszszu7opz//ZP9Xb9Le/erhe61Gg862GleuXArXV7ezYv7R
yXmH4uDB4HAyHlfZXLvMSOFBGXhU2Aq1ysryeDh69GSnqqxvNDXNvL+PeeqyVKbz0qfQOrRFwFVbWJfuxrWbFPswnx71nzwePS5G
+cp8fpgeV9NxZqoiLG+tXf4H6+f+xU9+8WGRsC28agihfum1r18N1prvPLle+n/npZdvXb3gtdyRyeYEWoQDSFU2m4+2tw//6ccf
v3m46x8kcjgcqWz1j//tHm3819/5+6+8vtXqgE1yKJ0CpdFo9A1oj2Hj1T/sfOn3r776nY3NVapGg4vPXbr+5VfHfjD/6OR8BeLg
4eBgPBqV6Vy53HDhQRV4qnQWlMpcVToWUnEjDjyjGmZ+uId5wnkqk1kVYGgZbRk42wKnK3fj2i2KfJhP+dGT+M52eydfmc8Ps6Ny
Oolzm4fVOdP7YuaiSy987+6no0EfqxMo5tHGmfNXr126fPl6FXzx0+EfcvPfXT/fibwZgRHgQNyq11tpgYTfm82+p+ePJZGDk43j
dJyOzn/3jy9Z+Mff+trfvXbx3NpqO2pqURqMpsCI9hy0m023/8GZRmdzc02bIgdF1166OXq4c+/NX+a/2buwdW4crGsGNRy7fIrl
3JQJRyTD+lkoDUozqhIkkTJXlfVQDJMRXZQSaBDb9UzTa5+Nw62ti+HaelwK9AdBv9/sH3h5iRkCul95g5tFFntKYfYK8G9Xs/fD
+QeShPONVmwkn7U93V5dK2fHRZJkdj6Ow0ZVPwE2clserZwBzq/Z+PVw5Z/98D3+rek/+sMvNe7+P2brVT5z9cx/9ke9H/+rL//W
2q4LB6PpYDStWJVMRqDRbOQnO8nDo9a5m34Q6OHdO7rR8OPGmReuf/ab+7c/2XuVfO9SS02BTiZVPvWKRFeZRCjHDgBRayDFqAqU
FMpCWesRG0YDuigkUGJtxzdno/BspC9euhSsr4MpbdWMV87E5+Nq76jaP15P3JPhaHDWa5CeNIpgQ76TqVa88qGkt48Pf78bvACA
xRyL1OvE3kuRX5bu1pb3eMDiIY7cpgebWxCMrgWNN2TlsDz76M78T//6nf/qv/x2b/3FVLUHj3Xz5rcvBMH1wYPdPmlTJSWkJagM
ms2GWrkUvPhiXsrh4aFOPt0/fyGClY1zZ3u3bj3/wTvDD07m6+utC+sN3xUyS7FIiTMPsUzLIIj9WAlZ4TKdZ2Xkh8LQ1oXKQl1y
F9ZAP3qa9wJZ6fJqc6v93EXwDKgq77VMu2nc2bzjpas5EmVPsqfFfONMqNDkiQRB+Zq2ZSt8x9r/4ef/6jtf/8p3b30B3v0gv8j5
GW52vbFf4pPkzDlNX3+jde6rs/bGfqMxO5lWNPz6lTPdDRKi2x8m9568P6Oiv10UySApj6Z7qarcqq9aWiqfV6Li1a35jQvrsbP/
0//6p6Ok1P/ne7/4h+Og277cfO2lWzev3fnw9i9Pxt/an7jAy20QTlOUjDg3hGVShJ0VLzLWTp1Nk1lRdSAUxo7OKQt1KT1ZJTO+
l60E3moX1jpb7ecuQmoSpKLX0kGT/KZrr6bNy7TzJJs+Th/tZV+61H3lefjdywZWzsPKizt7d3/21pUvfOn+7uF/tz36yut/cO6y
PXfFeRvVzntzdMXXX7/aN+Mf/dN/kldQVPDw8PDR4cE0g1mOG7q7+XEKNAOaecp42mCAPR8DjSFpEQfAN1987e/94e+pc6/++nt/
6vJsOEn0v+g/bPnd/9yt4M5R1KabL194+v7Rb3YnoOj3NuLz7anonB/s9cLCeuxLUeUJUekp2FptXjrXbbU3Gg2tVtKys+OM43C1
5fm05fvNtnluzVWpOFt5Xu6tDw7uzA8/O9o/7u8f7zwe7GwPlMbzz3ePjxsUxslodz58cHRwktztJ7IP4LTxBu+9s/sgz9rFpbX2
eLva/WzHD/LWUTHPk33O7SxPHIpTdjrZaDa3MKd45ILoueZNE5QmKKNmFDWjaVZMszwkGyh7thnHT4fabnszOdPa6Gw2dDJzbybp
7+rp9WE/PnP29Te+UI4O/pc788Mng+tBc6s1jbais3seetHYcz7nZTYLAvECPLuxevHsWqu13vAy1eoVekPahbTKC+vr8Qtb60nD
XF0/OdqbHWf9vc/6u58d9MuDfpUkNk3s0eQ46jaCAn7wLz/uwP0OhMJOHIsxqyYcjoetbpOKdPD+O1FntdNZO5L53cc7GUwbl3rn
vZW0uzbFERyN3bRKpmWs4LUXLr8yER3Ce9cur7/8De3H2o+VUkrpnmAHkJJjTI6lPH5UHsX3P9z/+NFxMq/WVvSltd5qR002vePL
0LhahLT1vPdHv/PLD5Pxbvi1r/Jz/2Ck99Ors/F0OwsauixjL2v7dGFz5bdvfeHK1ua//r/+7LUvvXSwd9+63Xw+ypORHA22Km82
H4w+eTyblLNpMZtms2lpOQFJiLSKdKRCDKkXe6vnz294tOGpPFRFqFQYqCAoKz+KN5U4BY7JF/QL8NPwRwd3n54Dox88TJvrW198
eeYeW3rMpRpza6XB5u3du2XS3Lz60vUvbJ6/FDTaZZmXRW5IaVRVOq6S8TRLpmky2d/B52f42f3J3YH+T/7jzXxSTXp+/8I5tXVD
BS3jr71cHOZ785E6fvf7f2GLcVWMJ/3Z5FJjuHPc8O3ljc63Xru11ui8/+ZHyYn3V9+/F9JOoCIqEiwSX8vB3f7qSm8+n6qwSUEj
9l1wBlECEh2sngtWzxXIOcrZsIovvZxjWGDYjMK1KPAbcdCITWS82NOgNGqlIqXCw4mr5o9m9+fnIeP84PDK9cs33oA7VuQJTlWm
2isNlunsPd+9yCoKOq3miiUThSaOomqWlLPE9+LGWqfnpuBme6Hnopblt/jJz3T/6XRyPNuthvijDynjyg+Os6KacaRaxv7Csz/2
PQh8yCDIJOiE4dcueleeu6yV+sW7v759Z2ez1Q0ZO7Fqx9bbWPfW281G3GpGqr01hdD4kfYiK9aKNYM9b7DfuvHvyKWrphx51ZD6
v2mfvdU++xzHq8Y3xjdOnGMmjaRRMQBDfTjWMpPhmY1ZD5tpcaxamxevX7t0YQ+++PCTgyzaCadJ7rqRM+ggH4z5pA9rK8qP2GbO
ZZCXXlnOJ6UKokagdNA+1/N6fi96eeIODv5fGqfBzaODyFwAAAAASUVORK5CYII=
)"
    return s
}

IconB64() {
    s := "
(
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
)"
    return s
}

; END OF SCRIPT
