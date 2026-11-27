# Walks the app's pages in a preview build through UI Automation, as a screen reader would, and says
# ok or FAIL for each thing it checks. It never reaches the service: a preview has made-up machines.
# It drives only the window it starts, through UI Automation's patterns, and closes it at the end.
#
#   cargo build -p guesthouse-app-windows --features preview
#   .\crates\app-windows\test\walk.ps1 -Exe .\target\debug\guesthouse-app.exe
#
# It checks the names the app's controls are found by, that Home's cards go into a machine's page and
# Back comes out, that the sections show what they hold, that the app's Settings opens from the gear
# on every page that has it and Back comes out to where it was opened from, and that the title bar's
# buttons are where the pointer would find them and not under the bar's drag region, wide and narrow,
# and what the Network section says and asks in each case of Windows' Hyper-V feature.
# A preview never writes the person's settings or Windows' Run key, whatever is switched.
param([Parameter(Mandatory)][string]$Exe)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
# In the screen's own pixels, as the window's controls are measured.
Add-Type -TypeDefinition 'public class WalkDpi { [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetWindowPos(System.IntPtr h, System.IntPtr after, int x, int y, int cx, int cy, uint flags); }'
[WalkDpi]::SetProcessDPIAware() | Out-Null
$script:Failed = 0
function Check([bool]$ok, [string]$what) {
  if ($ok) { "ok: $what" } else { "FAIL: $what"; $script:Failed++ }
}

# Starts the preview in a state, and returns its process once its window is up.
function Start-Preview([string]$exe, [string]$state, [string]$section = "") {
  $env:GUESTHOUSE_APP_PREVIEW = $state
  if ($section) { $env:GUESTHOUSE_APP_SECTION = $section } else { Remove-Item Env:GUESTHOUSE_APP_SECTION -ErrorAction SilentlyContinue }
  $p = Start-Process $exe -PassThru
  for ($i = 0; $i -lt 100 -and $p.MainWindowHandle -eq 0; $i++) { Start-Sleep -Milliseconds 200; $p.Refresh() }
  Start-Sleep -Milliseconds 1500
  $script:Root = [Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
  $script:Process = $p
  $p
}
# Makes the preview's window this wide, in the screen's pixels, leaving where it is and its height.
function Set-Width([int]$width) {
  $r = $script:Root.Current.BoundingRectangle
  # SWP_NOMOVE, SWP_NOZORDER and SWP_NOACTIVATE.
  [WalkDpi]::SetWindowPos($script:Process.MainWindowHandle, [IntPtr]::Zero, 0, 0, $width, [int]$r.Height, 0x0002 -bor 0x0004 -bor 0x0010) | Out-Null
  Start-Sleep -Milliseconds 900
}
function Stop-Preview($p) { $p.CloseMainWindow() | Out-Null; if (-not $p.WaitForExit(5000)) { Stop-Process -Id $p.Id } }

# A control by its name, other than plain text, or the text if that's all there is.
function Find([string]$name) {
  $c = New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::NameProperty), $name
  $text = [Windows.Automation.ControlType]::Text
  foreach ($e in $script:Root.FindAll([Windows.Automation.TreeScope]::Descendants, $c)) { if ($e.Current.ControlType -ne $text) { return $e } }
  $script:Root.FindFirst([Windows.Automation.TreeScope]::Descendants, $c)
}
function Has([string]$name) { [bool](Find $name) }
# Whether any control's name has these words in it, for a line that names machines or a reason.
function Says([string]$part) {
  foreach ($e in $script:Root.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)) {
    if ($e.Current.Name.Contains($part)) { return $true }
  }
  $false
}
function Act([string]$name, $pattern) {
  $e = Find $name; $o = $null
  if ($e -and $e.TryGetCurrentPattern($pattern, [ref]$o)) { $o; return }
  $null
}
function Press([string]$name) { $o = Act $name ([Windows.Automation.InvokePattern]::Pattern); if ($o) { $o.Invoke(); Start-Sleep -Milliseconds 700 }; [bool]$o }
function Toggle([string]$name) { $o = Act $name ([Windows.Automation.TogglePattern]::Pattern); if ($o) { $o.Toggle(); Start-Sleep -Milliseconds 700 }; [bool]$o }
function State([string]$name) { $o = Act $name ([Windows.Automation.TogglePattern]::Pattern); if ($o) { "$($o.Current.ToggleState)" } }
# The app's version, and the one after it, as the preview's newer one is.
function This-Version { (Get-Content (Join-Path $PSScriptRoot '..\..\..\windows\version.txt') -Raw).Trim() }
function Next-Version {
  $v = (This-Version).Split('.')
  "$($v[0]).$([int]$v[1] + 1).0"
}
function Choose([string]$name) { $o = Act $name ([Windows.Automation.SelectionItemPattern]::Pattern); if ($o) { $o.Select(); Start-Sleep -Milliseconds 700 }; [bool]$o }

# What the pointer meets at a point of the screen: the window's content, or the title bar's drag
# region, which Windows keeps in a window of its own over the bar. UI Automation finds the content's
# window at a point and not the control in it, so the content is all that can be told.
function Under([double]$x, [double]$y) {
  $hit = [Windows.Automation.AutomationElement]::FromPoint((New-Object Windows.Point $x, $y))
  if ($hit.Current.ProcessId -ne $script:Process.Id) { return "covered" }
  if ($hit.Current.ClassName -eq 'InputNonClientPointerSource') { return "drag" }
  "content"
}

# Whether the pointer at the middle of the control reaches the content, and not the drag region.
# The window must be on top there; if another window covers it, that's said and not counted.
function Reachable([string]$name) {
  $e = Find $name
  if (-not $e) { return $false }
  $r = $e.Current.BoundingRectangle
  $under = Under ($r.X + $r.Width / 2) ($r.Y + $r.Height / 2)
  if ($under -eq "covered") { Write-Warning "Another window covers $name, so it isn't checked."; return $true }
  $under -eq "content"
}

# Whether the title bar's empty space still drags the window: the middle of the widest gap between
# what the bar holds, which is said, as a narrow window leaves little.
function Drags {
  $c = New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ControlTypeProperty), ([Windows.Automation.ControlType]::TitleBar)
  $bar = $script:Root.FindFirst([Windows.Automation.TreeScope]::Descendants, $c)
  $r = $bar.Current.BoundingRectangle
  $edges = @($r.X)
  foreach ($e in $bar.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)) {
    $b = $e.Current.BoundingRectangle
    if ($b.Width -gt 0 -and $b.Width -lt $r.Width * 0.5) { $edges += $b.X; $edges += $b.X + $b.Width }
  }
  # The caption buttons, which Windows keeps at the right, about 46 units each.
  $edges += $r.X + $r.Width - 150 * ($r.Height / 48)
  $edges = $edges | Sort-Object
  $gap = 0; $at = 0
  for ($i = 1; $i -lt $edges.Count; $i++) {
    if ($edges[$i] - $edges[$i - 1] -gt $gap) { $gap = $edges[$i] - $edges[$i - 1]; $at = ($edges[$i] + $edges[$i - 1]) / 2 }
  }
  Write-Information "  the widest gap in the title bar is $([int]$gap) pixels" -InformationAction Continue
  $gap -gt 20 -and (Under $at ($r.Y + $r.Height / 2)) -ne "content"
}

# Home: a card each, named as the sidebar's items were, and New machine and Report a problem.
$p = Start-Preview $Exe home
Check (Has "win11, Windows, Running") "Home has win11's card, by its name, system and state"
Check (Has "Settings") "Home has the app's Settings"
Check (Reachable "Settings") "Settings is outside the title bar's drag region"
Check (Has "build-box, Linux, Starting") "Home has build-box's card"
Check (Has "New machine") "Home has New machine"
Check (Has "Report a problem") "Home has Report a problem"
Check (Reachable "New machine") "New machine is outside the title bar's drag region"
Check (Drags) "Home's title bar still drags the window"
Check (Press "win11, Windows, Running") "win11's card can be pressed"
Check (Has "Switch machine, win11") "its card opens win11's page, with the switcher"
Check (Has "Remote Desktop") "the Overview has Remote Desktop"
Check (Has "Open screen") "the title bar has Open screen"
Check (Has "More for win11") "the title bar has More"
foreach ($name in "Stop", "Open screen", "More for win11", "Switch machine, win11", "Back", "Settings") {
  Check (Reachable $name) "$name is outside the title bar's drag region"
}
Check (Drags) "the machine's title bar still drags the window"
Check (Press "Settings") "Settings can be pressed on a machine's page"
Check (Has "Look for updates by itself") "it opens the app's Settings"
Check (Press "Back") "Back from Settings"
Check (Has "Switch machine, win11") "goes back to win11's page"
Check (Choose "Hardware") "Hardware can be chosen"
Check (Has "Memory (MB)") "Hardware has the memory"
Check (Has "Save") "Hardware has Save"
Check (Choose "Network") "Network can be chosen"
Check (Has "Add a forward") "Network has Add a forward"
Check (Choose "Storage") "Storage can be chosen"
Check (Has "Take a snapshot") "Storage has Take a snapshot"
Check (Has "Move its disks") "Storage has Move"
Check (Choose "Remote View") "Remote View can be chosen"
Check (Has "Allow viewing from other devices") "Remote View has its switch"
Check (Press "Back") "Back can be pressed"
Check (Has "win11, Windows, Running") "Back goes Home"
Check (Press "New machine") "New machine can be pressed"
Check (Has "Image") "New machine has its form"
Check (Press "Back") "Back from New machine"
Check (Has "New machine") "and it's Home again"
Check (Press "Report a problem") "Report a problem can be pressed"
Check (Has "What went wrong") "Report a problem has its form"
Check (Press "Back") "Back from Report a problem"
Check (Press "Settings") "Settings can be pressed on Home"
foreach ($name in "Look for updates now", "Look for updates by itself", "Theme", "Open when I sign in", "Release notes of Guesthouse $(This-Version)", "Open the licences") {
  Check (Has $name) "Settings has $name"
}
Check (Press "Report a problem") "Settings has Report a problem"
Check (Has "What went wrong") "which opens the report page"
Check (Press "Back") "Back from the report page"
Check (Has "Look for updates by itself") "goes back to Settings"
Check (Press "Back") "and Back from Settings"
Check (Has "win11, Windows, Running") "goes Home"
# Narrow, the title bar's buttons are still outside its drag region.
Set-Width 760
foreach ($name in "Report a problem", "Settings", "New machine") {
  Check (Reachable $name) "$name is outside the drag region of a narrow window"
}
Check (Drags) "a narrow Home's title bar still drags the window"
Check (Press "win11, Windows, Running") "win11's card in a narrow window"
foreach ($name in "Stop", "Open screen", "More for win11", "Switch machine, win11", "Back", "Settings") {
  Check (Reachable $name) "$name is outside the drag region of a narrow machine's page"
}
Check (Drags) "a narrow machine's title bar still drags the window"
Stop-Preview $p

# A newer Guesthouse is out: the gear says so, and Settings says what it is.
$p = Start-Preview $Exe update
Check (Has "Settings, an update is out") "the gear says an update is out"
Check (Reachable "Settings, an update is out") "and is outside the drag region"
Check (Press "Settings, an update is out") "it can be pressed"
Check (Has "Download Guesthouse $(Next-Version)") "Settings has Download"
Check (Has "Release notes of Guesthouse $(Next-Version)") "and the newer one's release notes"
Check (Press "Not now") "Not now can be pressed"
Check (Has "Download Guesthouse $(Next-Version)") "the update is still on Settings"
Check (Press "Back") "Back from Settings"
Check ((Has "Settings") -and -not (Has "Settings, an update is out")) "and the gear's dot has gone"
Stop-Preview $p

# The file drop can't be reached: Look again looks, and says so again.
$p = Start-Preview $Exe updates-unreached
Check (Has "Look for updates now") "a look that couldn't tell can look again"
Check (Press "Look for updates now") "Look again can be pressed"
Check (Has "Couldn't tell whether a newer Guesthouse is out") "and it still can't tell"
Check (Toggle "Look for updates by itself") "looking by itself can be switched"
Check ((State "Look for updates by itself") -eq "Off") "and it's off"
$run = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$before = (Get-ItemProperty -Path $run -Name Guesthouse -ErrorAction SilentlyContinue).Guesthouse
Check (Toggle "Open when I sign in") "Open when I sign in can be switched"
Check ((State "Open when I sign in") -eq "On") "and it's on in the preview"
$after = (Get-ItemProperty -Path $run -Name Guesthouse -ErrorAction SilentlyContinue).Guesthouse
Check ($before -eq $after) "and Windows' Run key is as it was, as a preview writes nothing"
Stop-Preview $p

# Updating from inside the app, with the preview's fake: it downloads nothing, its check finds the
# SHA-256 the latest file gave, and its installer ends having done nothing, as a cancelled one does.
$v = Next-Version
$p = Start-Preview $Exe updates-out
Check (Has "When one is out") "Settings has what's done when one is out"
Check (Press "Download Guesthouse $v") "Download can be pressed"
Check (Has "Install Guesthouse $v now") "it downloads, is checked, and is ready to install"
Check (-not (Find "Install Guesthouse $v now").Current.IsEnabled) "but not while a machine is being made"
Check (Has "office is being made. Install once it's done: the installer stops the service, which would leave it half made.") "which is said"
Stop-Preview $p

$p = Start-Preview $Exe updates-downloading
Check (Has "Cancel the download") "a download has Cancel"
Check (Press "Cancel the download") "Cancel can be pressed"
Check (Has "Download Guesthouse $v") "and it's back to Download"
Stop-Preview $p

$p = Start-Preview $Exe updates-mismatch
Check (Has "It didn't match its SHA-256, so it was deleted. Nothing was installed.") "a download that didn't match says so"
Check (Press "Download Guesthouse $v again") "Try again can be pressed"
Check (Has "Install Guesthouse $v now") "and a download that matches is ready"
Stop-Preview $p

$p = Start-Preview $Exe updates-ready-running
Check (Has "Installing stops the service, which asks win11 and build-box to shut down first.") "what installing stops is said before Install"
Check (Press "Install Guesthouse $v now") "Install can be pressed"
Check (Has "Shut them down and install") "it asks first, as machines are running"
Check (Has "Later") "with Later"
Check (Press "Later") "Later can be pressed"
Check (Has "Install Guesthouse $v now") "and nothing was installed"
Check (Press "Install Guesthouse $v now") "Install again"
Check (Press "Shut them down and install") "Shut them down and install can be pressed"
Check (Has "Guesthouse $v wasn't installed") "the fake installer ends with nothing done, and it says so"
Check (Has "Windows' prompt was answered No, or the installer was closed before it installed.") "with why"
Check (Press "Back") "Back from Settings"
Check (Has "Settings, an update is ready") "the gear says an update is ready"
Stop-Preview $p

# With the service not answering, what an install stops can't be known, so it always asks.
$p = Start-Preview $Exe updates-ready-away
Check (Has "The service isn't answering, so the app can't tell which machines are running, or whether one is being made. Installing stops the service, which shuts down any that are running.") "a ready update says it can't tell what installing stops"
Check (Press "Install Guesthouse $v now") "Install can be pressed with the service not answering"
Check (Has "Stop the service and install") "and it asks first"
Check (Press "Later") "Later can be pressed"
Check (Has "Install Guesthouse $v now") "and nothing was installed"
Stop-Preview $p

$p = Start-Preview $Exe updates-installing
Check (Has "Installing Guesthouse $v") "an install going on says so"
Check (-not (Has "Install Guesthouse $v now")) "with no Install"
Check (-not (Find "Look for updates now")) "and nothing to look for meanwhile"
Stop-Preview $p

# A build of the repo isn't offered updates.
$p = Start-Preview $Exe updates-repo
Check (Has "This is a build of the repo") "a build of the repo says so"
Check (-not (Has "Look for updates now")) "and has no Look now"
Stop-Preview $p

# Connects through: Bridged offers the adapters and makes a change to save, and Shared takes both back.
$p = Start-Preview $Exe settings Network
Check (-not (Has "Adapter to bridge onto")) "a shared machine has no adapter to choose"
Check (Choose "Bridged") "Bridged can be chosen"
Check (Has "Adapter to bridge onto") "Bridged offers the adapters"
Check ((Find "Save").Current.IsEnabled) "and Save is there for it"
Check (Choose "Shared") "Shared can be chosen again"
Check (-not (Has "Adapter to bridge onto")) "and the adapters go"
Stop-Preview $p

# Bridging where Windows' Hyper-V feature is off: Turn on asks first and says what changes, Cancel
# changes nothing, and the preview's pretend turning on waits for a restart, which asks again. The
# walk never says yes to a restart, and a preview never restarts Windows or asks the service.
$p = Start-Preview $Exe net-off Network
Check (Has "Turn on Hyper-V") "Hyper-V off offers Turn on Hyper-V"
Check ((Find "Turn on Hyper-V").Current.IsEnabled) "which can be pressed with every machine stopped"
Check (-not (Find "Bridged").Current.IsEnabled) "and Bridged can't be chosen yet"
Check (Press "Turn on Hyper-V") "Turn on Hyper-V can be pressed"
Check (Has "Turn on Hyper-V?") "it asks first"
Check (Says "Microsoft-Hyper-V") "naming the feature"
Check (Says "Turn Windows features on or off") "and how to undo it"
Check (Says "VMware Workstation and VirtualBox") "and what Microsoft says it may change for other virtualization apps"
Check (Press "Cancel") "Cancel can be pressed"
Check ((Has "Turn on Hyper-V") -and -not (Has "Turn on Hyper-V?")) "and nothing changed"
Check (Press "Turn on Hyper-V") "Turn on Hyper-V again"
Check (Press "Turn on") "Turn on can be pressed in the question"
Check (Says "Windows has to restart before a machine can be bridged") "it waits for a restart"
Check (Has "Restart Windows now") "with Restart now"
Check (Press "Restart Windows now") "Restart now can be pressed"
Check (Has "Restart Windows now?") "it asks again"
Check (Says "Nothing is closed without asking") "saying nothing is forced"
Check (Press "Cancel") "Cancel, as the walk never restarts anything"
Check (-not (Has "Restart Windows now?")) "and the question has gone"
Stop-Preview $p

$p = Start-Preview $Exe net-held Network
Check (-not (Find "Turn on Hyper-V").Current.IsEnabled) "running machines hold turning Hyper-V on up"
Check (Says "Stop ubuntu and office first") "which says which ones"
Stop-Preview $p

$p = Start-Preview $Exe net-turning Network
Check (Says "Turning on Hyper-V, 40% done.") "turning it on says how far it has got"
Check (-not (Has "Turn on Hyper-V")) "with nothing to press meanwhile"
Stop-Preview $p

$p = Start-Preview $Exe net-failed Network
Check (Says "Hyper-V couldn't be turned on.") "a try that failed says so"
Check (Says "DISM's log is") "with DISM's log"
Check (Has "Try turning on Hyper-V again") "and can be tried again"
Stop-Preview $p

$p = Start-Preview $Exe net-home Network
Check (Says "Not available in Windows Home") "Windows Home says bridging isn't there"
Check (-not (Has "Turn on Hyper-V")) "with nothing to turn on"
Stop-Preview $p

$p = Start-Preview $Exe net-firmware Network
Check (Says "off in the firmware") "virtualization off in the firmware is said"
Check (-not (Has "Turn on Hyper-V")) "with nothing to turn on"
Stop-Preview $p

$p = Start-Preview $Exe home-restart
Check (Says "Windows has to restart before a machine can be bridged") "Home says a restart is waited for"
Stop-Preview $p

# An Ubuntu machine has no Remote View.
$p = Start-Preview $Exe linux
Check (Has "Switch machine, ubuntu") "linux opens on ubuntu's page"
Check (-not (Has "Remote View")) "an Ubuntu machine has no Remote View"
Stop-Preview $p

# Remote View's states keep the names a device's pairing is driven by.
$p = Start-Preview $Exe rv-waiting
Check (Has "Accept Phone") "a waiting device has Accept"
Check (Has "Decline Phone") "and Decline"
Check (Has "Code 4 8 2 9 1 7") "its code is read digit by digit"
Stop-Preview $p
$p = Start-Preview $Exe rv-devices
Check (Has "Pair a New Device") "pairing closed has Pair a New Device"
Check (Has "Remove Phone") "a paired device has Remove"
Check (Has "Clipboard for Phone") "a paired device has its switches"
Check (-not (Has "Disconnect")) "there's no Disconnect"
Stop-Preview $p

# No machines: the first run's page.
$p = Start-Preview $Exe empty
Check (Has "No machines yet") "no machines shows the first run"
Check (Reachable "Settings") "the first run has Settings outside the drag region"
Check (Press "Windows 11, A Windows 11 ISO, or its install.wim or install.esd") "its Windows 11 can be pressed"
Check (Has "Image") "and opens New machine"
Stop-Preview $p

# The service away: its own page, with Report a problem and Settings, and Back from each.
$p = Start-Preview $Exe away
Check (Reachable "Settings") "the away page has Settings outside the drag region"
Check (Press "Settings") "it can be pressed"
Check (Has "Look for updates by itself") "and opens Settings"
Check (Press "Back") "Back from Settings"
Check (Has "Report a problem") "the away page has Report a problem"
Check (Press "Report a problem") "it can be pressed"
Check (Press "Back") "Back from the report page"
Check (Has "Report a problem") "goes back to the away page"
Stop-Preview $p

Remove-Item Env:GUESTHOUSE_APP_PREVIEW, Env:GUESTHOUSE_APP_SECTION -ErrorAction SilentlyContinue
if ($script:Failed) { "$script:Failed failed"; exit 1 } else { "all passed" }
