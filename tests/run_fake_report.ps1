$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../tools/fake-report.ps1')
$passed = 0
function Expect($report, $name, $status) {
    $check = @($report.Checks | Where-Object Name -eq $name)
    if ($check.Count -ne 1 -or $check[0].Status -ne $status) { throw "Expected $name=$status`n$($report.Text)" }
    $script:passed++
}
$hostLines = @(
    '0 game speed state: by=client gt=2101800 hb=1 run=4 speed=4 src=gui tg=4 ver=0',
    '1 HOST sets speed 0',
    '2 game speed state: by=host gt=2200000 hb=2 run=0 speed=0 src=gui tg=0 ver=1',
    '3 HOST sets speed 1',
    '4 game speed state: by=host gt=2200200 hb=3 run=1 speed=1 src=gui tg=1 ver=2',
    '5 the game caught up after 83 s',
    '6 checkpoint 40 of the game: money=100 adj=5000 veh=37; host answers with same values',
    '7 recorded build a.1 (100 bytes)',
    '8 host answers with one vehicle more'
)
$gameLines = @(
    '[mp_probe]net state gui by=client gt=2101800 hb=1 run=4 speed=4 src=gui tg=4 ver=0',
    '[mp_probe]world scan ck=60 capture_ms=11 hedge=Cannot_loop hline=Cannot_loop hcargo=Cannot_loop',
    '[mp_probe]sync WARNING: the games differ: veh here 37, in the other game 38',
    '[mp_probe]param[2].errorState.critical = boolean false'
)
$r = Get-FakeHostReport $hostLines $gameLines
foreach ($name in 'Pause','Fortsetzen','Aufholen','Geldkorrektur','Absichtliche Abweichung','Aktionsfehler') { Expect $r $name 'OK' }
Expect $r 'Nachbau' 'OFFEN'
Expect $r 'Weltvergleich' 'LUECKE'
Expect $r 'Zwei-PC-Verfahren' 'UNGETESTET'
if ($r.Text -notmatch 'hedge, hline, hcargo') { throw 'Missing scan errors' }; $passed++
Expect (Get-FakeHostReport @() @()) 'Pause' 'OFFEN'
Expect (Get-FakeHostReport $hostLines @('different game')) 'Spielprotokoll' 'OFFEN'
Expect (Get-FakeHostReport ($hostLines + 'did NOT catch up within 200 s')) 'Aufholen' 'FEHLER'
Expect (Get-FakeHostReport ($hostLines + 'REPLAY TIMEOUT at line 1')) 'Nachbau' 'FEHLER'
Expect (Get-FakeHostReport ($hostLines + 'REPLAY FAILED at line 1')) 'Nachbau' 'FEHLER'
Expect (Get-FakeHostReport $hostLines ($gameLines + '[mp_probe]net skipped token')) 'Aktionsfehler' 'FEHLER'
$reload = @('the game loaded a savegame again', '1 build line(s) of the session before go back to the game')
Expect (Get-FakeHostReport ($hostLines + $reload)) 'Nachbau' 'OFFEN'
Expect (Get-FakeHostReport ($hostLines + $reload + 'game APPLIED line 1 of 1')) 'Nachbau' 'OK'
# A first successful round must not hide a pending second round.
Expect (Get-FakeHostReport ($hostLines + $reload + 'game APPLIED line 1 of 1' + $reload)) 'Nachbau' 'OFFEN'
Expect (Get-FakeHostReport $hostLines @($gameLines[0], '[mp_probe]world scan ck=60 capture_ms=11')) 'Weltvergleich' 'TEILWEISE'
# A response before the injected command does not prove that the command worked.
Expect (Get-FakeHostReport @($hostLines[2], $hostLines[1])) 'Pause' 'OFFEN'
Expect $r 'Spielende' 'OFFEN'
Expect (Get-FakeHostReport $hostLines ($gameLines + 'Normal shutdown. Bye!')) 'Spielende' 'OK'
Expect $r 'Messkosten' 'INFO'
Write-Host "$passed fake-host report checks passed"
