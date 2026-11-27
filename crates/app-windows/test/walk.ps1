# Walks the app's pages in a preview build through UI Automation, as a screen reader would, and says
# ok or FAIL for each thing it checks. It never reaches the service: a preview has made-up machines.
# It drives only the window it starts, through UI Automation's patterns, and closes it at the end.
#
#   cargo build -p guesthouse-app-windows --features preview
#   .\crates\app-windows\test\walk.ps1 -Exe .\target\debug\guesthouse-app.exe
#
# It checks the names the app's controls are found by, that Home's cards go into a machine's page and
# Back comes out, that the sections show what they hold, and that the title bar's buttons are where
# the pointer would find them and not under the bar's drag region.
param([Parameter(Mandatory)][string]$Exe)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
# In the screen's own pixels, as the window's controls are measured.
Add-Type -TypeDefinition 'public class WalkDpi { [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
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
function Stop-Preview($p) { $p.CloseMainWindow() | Out-Null; if (-not $p.WaitForExit(5000)) { Stop-Process -Id $p.Id } }

# A control by its name, other than plain text, or the text if that's all there is.
function Find([string]$name) {
  $c = New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::NameProperty), $name
  $text = [Windows.Automation.ControlType]::Text
  foreach ($e in $script:Root.FindAll([Windows.Automation.TreeScope]::Descendants, $c)) { if ($e.Current.ControlType -ne $text) { return $e } }
  $script:Root.FindFirst([Windows.Automation.TreeScope]::Descendants, $c)
}
function Has([string]$name) { [bool](Find $name) }
function Act([string]$name, $pattern) {
  $e = Find $name; $o = $null
  if ($e -and $e.TryGetCurrentPattern($pattern, [ref]$o)) { $o; return }
  $null
}
function Press([string]$name) { $o = Act $name ([Windows.Automation.InvokePattern]::Pattern); if ($o) { $o.Invoke(); Start-Sleep -Milliseconds 700 }; [bool]$o }
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

# Whether the title bar's empty middle still drags the window.
function Drags {
  $c = New-Object Windows.Automation.PropertyCondition ([Windows.Automation.AutomationElement]::ControlTypeProperty), ([Windows.Automation.ControlType]::TitleBar)
  $r = $script:Root.FindFirst([Windows.Automation.TreeScope]::Descendants, $c).Current.BoundingRectangle
  (Under ($r.X + $r.Width * 0.55) ($r.Y + $r.Height / 2)) -ne "content"
}

# Home: a card each, named as the sidebar's items were, and New machine and Report a problem.
$p = Start-Preview $Exe home
Check (Has "win11, Windows, Running") "Home has win11's card, by its name, system and state"
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
foreach ($name in "Stop", "Open screen", "More for win11", "Switch machine, win11", "Back") {
  Check (Reachable $name) "$name is outside the title bar's drag region"
}
Check (Drags) "the machine's title bar still drags the window"
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
Check (Press "Windows 11, A Windows 11 ISO, or its install.wim or install.esd") "its Windows 11 can be pressed"
Check (Has "Image") "and opens New machine"
Stop-Preview $p

# The service away: its own page, with Report a problem, and Back from that.
$p = Start-Preview $Exe away
Check (Has "Report a problem") "the away page has Report a problem"
Check (Press "Report a problem") "it can be pressed"
Check (Press "Back") "Back from the report page"
Check (Has "Report a problem") "goes back to the away page"
Stop-Preview $p

Remove-Item Env:GUESTHOUSE_APP_PREVIEW, Env:GUESTHOUSE_APP_SECTION -ErrorAction SilentlyContinue
if ($script:Failed) { "$script:Failed failed"; exit 1 } else { "all passed" }
