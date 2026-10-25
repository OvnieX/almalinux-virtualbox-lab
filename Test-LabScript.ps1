#requires -Version 5.1
<#
Tests locaux, sans installation, sans reseau reel et sans appel a VirtualBox.
Le script extrait des fonctions et des blocs du createur, puis simule leurs dependances.
Les fichiers generes et les mots de passe de test sont fictifs.
OutputDirectory est facultatif : les Kickstarts de test contiennent seulement des secrets fictifs.
#>
[CmdletBinding()]
param([string]$OutputDirectory)

# 1. Analyser la syntaxe PowerShell sans executer le programme de creation.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$source=Join-Path $PSScriptRoot 'New-AnsibleLab.ps1'
$tokens=$null; $errorsFound=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errorsFound)
if($errorsFound.Count){$errorsFound; throw 'PowerShell syntax failed'}
# 2. Charger les fonctions necessaires sans executer le programme principal aux tests.
foreach($name in @('Assert-LabUserName','Read-LabYesNo','Read-AdditionalUsers','Get-AdditionalUserConfig','Get-FreeLabDvdPort','Read-BatchNames','Get-GuestAdditionsCopyPost','Get-ValidatedShares','Write-LabBanner','Get-SharedFoldersBootstrap','Write-LabSection','Read-Default','Read-IntegerChoice','Convert-IPv4Number','Get-StaticNetwork','Assert-RootSettings','Get-LabKickstart','Get-BatchNames','Get-BatchArguments')){
    $function=$ast.FindAll({param($a) $a -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true) | Where-Object Name -eq $name
    Invoke-Expression $function.Extent.Text
}
# 3. Controler les masques CIDR et rejeter les configurations IPv4 incoherentes.
$net=Get-StaticNetwork '192.168.1.50' 24 '192.168.1.1' '192.168.1.1,1.1.1.1'
if($net.Netmask -ne '255.255.255.0'){throw 'Wrong /24 netmask'}
if((Get-StaticNetwork '10.1.2.10' 16 '10.1.0.1' '1.1.1.1').Netmask -ne '255.255.0.0'){throw 'Wrong /16'}
if((Get-StaticNetwork '10.0.0.1' 30 '10.0.0.2' '1.1.1.1').Netmask -ne '255.255.255.252'){throw 'Wrong /30'}
foreach($invalid in @(
    @('192.168.1.0',24,'192.168.1.1','1.1.1.1'),
    @('192.168.1.255',24,'192.168.1.1','1.1.1.1'),
    @('192.168.1.50',24,'192.168.2.1','1.1.1.1'),
    @('192.168.1.50',24,'192.168.1.50','1.1.1.1'),
    @('192.168.1.50',24,'192.168.1.1','999.1.1.1'),
    @('192.168.1.50',24,'192.168.1.1','1.1.1.1;echo bad')
)){
    $caught=$false
    try{$null=Get-StaticNetwork $invalid[0] $invalid[1] $invalid[2] $invalid[3]}catch{$caught=$true}
    if(-not $caught){throw 'Invalid static settings accepted'}
}
# 4. Verifier les trois choix root/SSH valides et rejeter le quatrieme.
foreach($pair in @(@('Disabled','Disabled'),@('Enabled','Disabled'),@('Enabled','Enabled'))) {
    Assert-RootSettings $pair[0] $pair[1]
}
$caught=$false
try { Assert-RootSettings 'Disabled' 'Enabled' } catch { $caught=$true }
if(-not $caught) { throw 'SSH root accepted with a locked root password' }

# 5. Generer les 12 variantes et verifier la politique SSH et le compte personnalise.
if($OutputDirectory) { [void][IO.Directory]::CreateDirectory($OutputDirectory) }
$count=0
foreach($role in @('Controller','Node')){
    foreach($root in @('Enabled','Disabled')){
        foreach($ssh in @('Disabled','Enabled')){
            if($root -eq 'Disabled' -and $ssh -eq 'Enabled') { continue }
            foreach($mode in @('Dhcp','Static')){
                $line='network --device=link --activate --onboot=yes --hostname=web01.example.test'
                if($mode -eq 'Dhcp'){$line+=' --bootproto=dhcp'}
                else{$line+=' --bootproto=static --ip=192.168.1.50 --netmask=255.255.255.0 --gateway=192.168.1.1 --nameserver=192.168.1.1,1.1.1.1 --noipv6'}
                $ks=Get-LabKickstart 'labadmin' $root $line $role $ssh
                if($ks -match '__LAB_USER__|__NETWORK_LINE__|__ROOT_LINE__|__VM_ROLE__|/home/ansible|--name=ansible'){throw 'Unresolved setting'}
                if($root -eq 'Enabled' -and $ks -notmatch 'rootpw --plaintext @@VBOX_INSERT_ROOT_PASSWORD_SH@@'){throw 'Root password not enabled'}
                if($root -eq 'Disabled' -and $ks -notmatch 'rootpw --lock'){throw 'Root not locked'}
                $policy=[regex]::Match($ks,"(?s)<<'SSH_CONFIG'\r?\n(.*?)\r?\nSSH_CONFIG").Groups[1].Value
                if($ssh -eq 'Enabled') {
                    if($policy -notmatch '(?m)^PermitRootLogin yes$' -or $policy -notmatch '(?m)^PasswordAuthentication yes$') {
                        throw 'SSH password access not enabled in the generated config'
                    }
                } elseif($policy -notmatch '(?m)^PermitRootLogin prohibit-password$') { throw 'Root password SSH not blocked' }
                if($ks -match '__[A-Z_]+__') { throw 'Unresolved template token' }
                $ks=$ks.Replace('@@VBOX_INSERT_ROOT_PASSWORD_SH@@',"'Root-Test-Only-123!'").Replace('@@VBOX_INSERT_USER_PASSWORD_SH@@',"'User-Test-Only-123!'")
                if($OutputDirectory) {
                    [IO.File]::WriteAllText((Join-Path $OutputDirectory "$role-$root-$ssh-$mode.cfg"),$ks)
                }
                $count++
            }
        }
    }
}
if($count -ne 12) { throw 'Missing configuration combinations' }

# 6. Tester le choix du pont avec des commandes Windows et VirtualBox simulees.
# Les commandes ci-dessous ne touchent aucune carte reseau reelle.
$sourceText=Get-Content -LiteralPath $source -Raw
$networkStart=$sourceText.IndexOf('$bridgeText =')
$networkEnd=$sourceText.IndexOf('# ETAPE 5 -')
if($networkStart -lt 0 -or $networkEnd -le $networkStart){throw 'Network block not found'}
$network=$sourceText.Substring($networkStart,$networkEnd-$networkStart)
# Double VirtualBox : deux cartes connues, identifiees par GUID.
function Invoke-VBox {
@'
Name:            Intel Ethernet
GUID:            00000000-0000-0000-0000-000000000001
Status:          Up

Name:            Intel Wi-Fi
GUID:            00000000-0000-0000-0000-000000000002
Status:          Up
'@
}
# Double Windows : retirer Ethernet permet de tester le repli sur Wi-Fi.
function Get-NetAdapter {
param([switch]$Physical)
if (-not $script:WifiOnly) {
[pscustomobject]@{Name='Ethernet';Status='Up';InterfaceGuid='00000000-0000-0000-0000-000000000001';ifIndex=1;NdisPhysicalMedium=14;InterfaceType=6}
}
[pscustomobject]@{Name='Wi-Fi';Status='Up';InterfaceGuid='00000000-0000-0000-0000-000000000002';ifIndex=2;NdisPhysicalMedium=9;InterfaceType=71}
}
# Double de routage : simuler une route presente ou absente.
function Get-NetRoute { param($InterfaceIndex,$AddressFamily,$DestinationPrefix,$ErrorAction)
if ($script:NoRoute) { return }
[pscustomobject]@{NextHop='192.168.1.1';RouteMetric=10}
}
# Double IPv4 : une adresse locale valide, sans detection reseau reelle.
function Get-NetIPAddress { param($InterfaceIndex,$AddressFamily,$ErrorAction)
[pscustomobject]@{AddressState='Preferred';IPAddress='192.168.1.100'}
}
# Donner une meilleure metrique au Wi-Fi pour verifier que la priorite Ethernet reste respectee.
function Get-NetIPInterface { param($InterfaceIndex,$AddressFamily)
[pscustomobject]@{InterfaceMetric= $(if ($InterfaceIndex -eq 1) { 100 } else { 1 })}
}
$script:WifiOnly=$false; $script:NoRoute=$false; $BridgeAdapter=$null
Invoke-Expression $network
if ($selected.Kind -ne 'Ethernet') { throw 'Ethernet priority failed' }
$script:WifiOnly=$true
Invoke-Expression $network
if ($selected.Kind -ne 'Wi-Fi') { throw 'Wi-Fi fallback failed' }
$script:WifiOnly=$false; $BridgeAdapter='Wi-Fi'
Invoke-Expression $network
if ($selected.Kind -ne 'Wi-Fi') { throw 'Override failed' }
$BridgeAdapter=$null; $script:NoRoute=$true
$caught=$false
try { Invoke-Expression $network } catch { $caught=$true }
if (-not $caught) { throw 'Missing route was not rejected' }
Write-Host 'OK : priorite Ethernet, repli Wi-Fi, choix impose, absence de route.'

Write-Host 'OK : syntaxe PowerShell, IPv4, root/SSH et 12 combinaisons de generation.'
Write-Host 'Ces tests ne remplacent pas une installation Windows/VirtualBox reelle.'

# 7. Tester les ressources interactives avec une file de reponses simulees.
# Aucun clavier n est sollicite ; une reponse manquante fait echouer le test.
function Read-Host {
    param([string]$Prompt)
    if ($script:Answers.Count -eq 0) { throw 'Question inattendue pendant le test' }
    return $script:Answers.Dequeue()
}
function Set-TestAnswers {
    param([string[]]$Values)
    $script:Answers = New-Object 'System.Collections.Generic.Queue[string]'
    foreach ($value in $Values) { $script:Answers.Enqueue($value) }
}
Set-TestAnswers @('')
if ((Read-IntegerChoice 'CPU' 2 1 16) -ne 2) { throw 'Default CPU failed' }
Set-TestAnswers @('abc','0','17','4')
if ((Read-IntegerChoice 'CPU' 2 1 16) -ne 4) { throw 'CPU validation/retry failed' }
Set-TestAnswers @('4096')
if ((Read-IntegerChoice 'RAM' 2048 2048 32768) -ne 4096) { throw 'RAM selection failed' }
Set-TestAnswers @('25')
if ((Read-IntegerChoice 'Disk' 30 20 500) -ne 25) { throw 'Disk selection failed' }

# Reutiliser le vrai bloc de selection pour verifier arguments fournis / omis.
$resourceStart = $sourceText.IndexOf("if (-not `$PSBoundParameters.ContainsKey('CpuCount'))")
$resourceEnd = $sourceText.IndexOf('if (-not $HostName)', $resourceStart)
if ($resourceStart -lt 0 -or $resourceEnd -le $resourceStart) { throw 'Resource block not found' }
$resourceBody = $sourceText.Substring($resourceStart, $resourceEnd - $resourceStart)
$resourceTest = [scriptblock]::Create(
    'param([int]$CpuCount=2,[int]$MemoryMB=2048,[int]$DiskGB=30)' + "`n" +
    $resourceBody + "`n" + '[pscustomobject]@{CPU=$CpuCount;RAM=$MemoryMB;Disk=$DiskGB}'
)
Set-TestAnswers @('','','')
$result = & $resourceTest
if ($result.CPU -ne 2 -or $result.RAM -ne 2048 -or $result.Disk -ne 30) { throw 'Interactive defaults failed' }
Set-TestAnswers @()
$result = & $resourceTest -CpuCount 2 -MemoryMB 2048 -DiskGB 30
if ($result.CPU -ne 2 -or $result.RAM -ne 2048 -or $result.Disk -ne 30) { throw 'Explicit defaults failed' }
Set-TestAnswers @('4096')
$result = & $resourceTest -CpuCount 4 -DiskGB 50
if ($result.CPU -ne 4 -or $result.RAM -ne 4096 -or $result.Disk -ne 50 -or $script:Answers.Count -ne 0) {
    throw 'Mixed explicit and interactive resource settings failed'
}
Write-Host 'OK : ressources interactives, valeurs par defaut, nouvelles tentatives et arguments prioritaires.'

# 8. Noms et arguments de lot : aucune execution d un enfant ou de VirtualBox.
$names = @(Get-BatchNames 'linux09' 3)
if (($names -join ',') -ne 'linux09,linux10,linux11') { throw 'Batch numbering failed' }
if ((@(Get-BatchNames 'worker' 2) -join ',') -ne 'worker01,worker02') { throw 'Batch suffix failed' }
$common = @{ NetworkMode='Dhcp'; CpuCount=4; LoginShell='/bin/sh'; VmCount=3 }
$plans = @(Get-BatchArguments $common $names @())
if ($plans.Count -ne 3 -or $plans[1].ContainsKey('HostName') -or $plans[1].VmCount -ne 1 -or $plans[1].CpuCount -ne 4) {
    throw 'DHCP batch arguments failed'
}
$common = @{ NetworkMode='Static'; HostName='{vm}.example.test'; IpAddresses='placeholder' }
$plans = @(Get-BatchArguments $common $names @('192.168.1.50','192.168.1.51','192.168.1.52'))
if ($plans[2].IpAddress -ne '192.168.1.52' -or $plans[2].HostName -ne 'linux11.example.test' -or $plans[2].ContainsKey('IpAddresses')) {
    throw 'Static batch arguments failed'
}
foreach ($invalid in @(
    @{ Common=@{NetworkMode='Dhcp';HostName='same.example.test'}; Addresses=@() },
    @{ Common=@{NetworkMode='Static'}; Addresses=@('192.168.1.50','192.168.1.50','192.168.1.52') },
    @{ Common=@{NetworkMode='Static'}; Addresses=@('192.168.1.50') },
    @{ Common=@{NetworkMode='Dhcp';IpAddress='192.168.1.50'}; Addresses=@() }
)) {
    $caught=$false
    try { $null=Get-BatchArguments $invalid.Common $names $invalid.Addresses } catch { $caught=$true }
    if (-not $caught) { throw 'Invalid batch accepted' }
}
# 9. Les deux shells autorises doivent etre appliques au compte Kickstart.
foreach ($shell in @('/bin/bash','/bin/sh')) {
    $ks=Get-LabKickstart 'labadmin' 'Disabled' 'network --bootproto=dhcp --device=link' 'Node' 'Disabled' $shell
    if (-not $ks.Contains("user --name=labadmin --shell=$shell --groups=wheel")) { throw 'Shell not applied' }
    if (-not $ks.Contains('labadmin ALL=(ALL) ALL')) { throw 'Sudo rights lost' }
}
Write-Host 'OK : lots DHCP/statiques, noms distincts, rejet des doublons, shells et droits sudo.'

# 10. Questions initiales : arguments explicites prioritaires et aucun prompt dans un enfant.
$start=$sourceText.IndexOf('# Questions initiales seulement')
$end=$sourceText.IndexOf('# ETAPE 2a - Lot')
$initial=[scriptblock]::Create('param([int]$VmCount=1,[string]$VmName="ansible01")' + "`n" +
    $sourceText.Substring($start,$end-$start) + "`n" + '[pscustomobject]@{Count=$VmCount;Name=$VmName}')
Set-TestAnswers @('3','linux10')
$r=& $initial
if($r.Count -ne 3 -or $r.Name -ne 'linux10' -or $script:Answers.Count){throw 'Initial prompts failed'}
Set-TestAnswers @()
$r=& $initial -VmCount 1 -VmName linux11
if($r.Count -ne 1 -or $r.Name -ne 'linux11'){throw 'Child explicit settings failed'}
Set-TestAnswers @('','INVALID','linux20')
$r=& $initial
if($r.Count -ne 1 -or $r.Name -ne 'linux20'){throw 'Initial default/retry failed'}

# 11. Partages : chemins existants, noms distincts, booleens et generation RO/RW.
$shares=@(Get-ValidatedShares @(
    [pscustomobject]@{Name='documents';HostPath=$PSScriptRoot;ReadOnly=$true},
    [pscustomobject]@{Name='echange';HostPath=$PSScriptRoot;ReadOnly=$false}
))
$ks=Get-LabKickstart 'labadmin' 'Disabled' 'network --bootproto=dhcp --device=link' 'Node' 'Disabled' '/bin/bash' $shares
foreach($expected in @('documents /mnt/documents vboxsf ro,','echange /mnt/echange vboxsf rw,',
    'kernel-devel-$(uname -r)','/sbin/rcvboxadd setup','%post --nochroot',
    'runuser -u labadmin -- test -r /mnt/echange')) {
    if(-not $ks.Contains($expected)){throw "Missing shared folder config: $expected"}
}
if($ks -match '__[A-Z_]+__'){throw 'Unresolved share token'}
if($OutputDirectory){[IO.File]::WriteAllText((Join-Path $OutputDirectory 'shares.cfg'),$ks)}
foreach($item in @(
    [pscustomobject]@{Name='../bad';HostPath=$PSScriptRoot;ReadOnly=$true},
    [pscustomobject]@{Name='valid';HostPath=$PSScriptRoot;ReadOnly='false'},
    [pscustomobject]@{Name='valid';HostPath=(Join-Path $PSScriptRoot 'missing-test-directory');ReadOnly=$true}
)) {
    $caught=$false
    try{$null=Get-ValidatedShares @($item)}catch{$caught=$true}
    if(-not $caught){throw 'Invalid share accepted'}
}
$caught=$false
try{$null=Get-ValidatedShares @($shares[0],$shares[0])}catch{$caught=$true}
if(-not $caught){throw 'Duplicate share accepted'}
Write-Host 'OK : questions nombre/nom, appels enfants, partages RO/RW et validation.'

# 12. Defaults reseau : tester le vrai bloc de saisie sans execution VirtualBox.
$start=$sourceText.IndexOf('    # Propositions propres au lab')
$end=$sourceText.IndexOf('    $static = Get-StaticNetwork', $start)
$networkQuestions=[scriptblock]::Create(
    'param([int]$PrefixLength=0,[string]$Gateway,[string]$DnsServers)' + "`n" +
    $sourceText.Substring($start,$end-$start) + "`n" +
    '[pscustomobject]@{Prefix=$PrefixLength;Gateway=$Gateway;Dns=$DnsServers}')
Set-TestAnswers @('','','')
$r=& $networkQuestions
if($r.Prefix -ne 24 -or $r.Gateway -ne '192.168.1.254' -or $r.Dns -ne '192.168.1.254') {
    throw 'Static defaults failed'
}
$null=Get-StaticNetwork '192.168.1.95' $r.Prefix $r.Gateway $r.Dns
Set-TestAnswers @('abc','31','16','10.1.0.1','1.1.1.1,9.9.9.9')
$r=& $networkQuestions
if($r.Prefix -ne 16 -or $r.Gateway -ne '10.1.0.1' -or $r.Dns -ne '1.1.1.1,9.9.9.9') {
    throw 'Static custom choices/retry failed'
}
Set-TestAnswers @()
$r=& $networkQuestions -PrefixLength 24 -Gateway '192.168.1.1' -DnsServers '1.1.1.1'
if($r.Gateway -ne '192.168.1.1' -or $r.Dns -ne '1.1.1.1') {throw 'Static explicit parameters failed'}
Write-Host 'OK : defauts IPv4, valeurs modifiables, prefixe redemande et arguments prioritaires.'

# 13. Reproduire le contexte reel : IpAddresses est un parametre de type string.
# PowerShell ignore la casse : une variable locale ipAddresses entrait en collision.
$script:WifiOnly=$false; $script:NoRoute=$false; $BridgeAdapter=$null
$bridgeTypedTest=[scriptblock]::Create(
    'param([string]$IpAddresses)' + "`n" + $network + "`n" +
    '[pscustomobject]@{Kind=$selected.Kind;BatchAddresses=$IpAddresses}')
$r=& $bridgeTypedTest -IpAddresses '192.168.1.77,192.168.1.78,192.168.1.79'
if($r.Kind -ne 'Ethernet' -or $r.BatchAddresses -ne '192.168.1.77,192.168.1.78,192.168.1.79') {
    throw 'Bridge detection corrupted the typed batch parameter'
}
$script:WifiOnly=$true
$r=& $bridgeTypedTest
if($r.Kind -ne 'Wi-Fi' -or $r.BatchAddresses){throw 'Single VM bridge with typed parameter failed'}
Write-Host 'OK : pont avec parametre IpAddresses type, lot et VM unitaire.'

# 14. Noms independants : propositions, personnalisation, rejet des doublons et noms invalides.
Set-TestAnswers @('ansible01','BAD/name','dollaru01','dollaru02')
$names=@(Read-BatchNames 'ansible01' 3)
if(($names -join ',') -ne 'ansible01,dollaru01,dollaru02' -or $script:Answers.Count) {
    throw 'Independent names/retries failed'
}
Set-TestAnswers @('','')
if((@(Read-BatchNames 'linux01' 3) -join ',') -ne 'linux01,linux02,linux03') {
    throw 'Name suggestions failed'
}
$plans=@(Get-BatchArguments @{NetworkMode='Static'} $names @('192.168.1.77','192.168.1.78','192.168.1.79'))
if($plans[1].VmName -ne 'dollaru01' -or $plans[1].IpAddress -ne '192.168.1.78') {
    throw 'Custom name/IP mapping failed'
}
foreach($plan in $plans){if($plan.ContainsKey('HostName')){throw 'Hostname prompt suppressed'}}
# Executer la vraie question de hostname avec une reponse personnalisee puis Entree.
$hostnameLine=($sourceText -split "`n" | Where-Object {$_ -like 'if (-not $HostName) *'})
$hostnameQuestion=[scriptblock]::Create('param([string]$VmName,[string]$HostName)' + "`n" +
    $hostnameLine + "`n" + '$HostName')
Set-TestAnswers @('batch01.lab.test')
if((& $hostnameQuestion -VmName dollaru01) -ne 'batch01.lab.test'){throw 'Custom hostname failed'}
Set-TestAnswers @('')
if((& $hostnameQuestion -VmName dollaru02) -ne 'dollaru02.lab.test'){throw 'Hostname default failed'}
Set-TestAnswers @()
if((& $hostnameQuestion -VmName dollaru01 -HostName explicit.lab.test) -ne 'explicit.lab.test') {
    throw 'Explicit hostname priority failed'
}
Write-Host 'OK : noms independants, ordre des IP, hostname demande par VM et modele explicite conserve.'

# 15. Ne pas ecraser le DVD auxiliaire eventuellement place par unattended.
if((Get-FreeLabDvdPort '"LabSATA-2-0"="emptydrive"') -ne 2){throw 'Empty DVD selection failed'}
if((Get-FreeLabDvdPort '"LabSATA-2-0"="auxiliary.iso"') -ne 3){throw 'Occupied DVD overwritten'}
$caught=$false
try{$null=Get-FreeLabDvdPort ("`"LabSATA-2-0`"=`"aux.iso`"`n`"LabSATA-3-0`"=`"other.iso`"")}catch{$caught=$true}
if(-not $caught){throw 'Full controller accepted'}
$prepareIndex=$sourceText.IndexOf('        Invoke-VBox $installArguments')
$attachIndex=$sourceText.IndexOf('        $additionsPort = Get-FreeLabDvdPort')
$startIndex=$sourceText.IndexOf("Invoke-VBox @('startvm'")
if($prepareIndex -ge $attachIndex -or $attachIndex -ge $startIndex){throw 'Wrong Additions attachment order'}
Write-Host 'OK : CD Additions apres preparation, avant demarrage, sans remplacer les medias occupes.'

# 16. Comptes supplementaires : noms, droits et secrets fictifs seulement.
Set-TestAnswers @('ansible','root','reader','/bin/sh','n','admin2','','o')
$extra=@(Read-AdditionalUsers 'ansible' 2)
if($extra.Count -ne 2 -or $extra[0].Sudo -or -not $extra[1].Sudo -or $extra[0].Shell -ne '/bin/sh') {
    throw 'Additional account choices failed'
}
foreach($account in $extra){$account.Password='Test-Only-123!'}
$ks=Get-LabKickstart 'ansible' 'Disabled' 'network --bootproto=dhcp --device=link' 'Node' 'Disabled' '/bin/bash' @() $extra
if($ks -notmatch "user --name=reader --shell=/bin/sh --password='Test-Only-123!' --plaintext" -or
   $ks -notmatch 'user --name=admin2 --shell=/bin/bash --groups=wheel' -or
   $ks -notmatch 'admin2 ALL=\(ALL\) ALL' -or $ks -match 'reader ALL=') {throw 'Additional users generation failed'}
if($ks -match '__[A-Z_]+__'){throw 'Unresolved extra user token'}
if($OutputDirectory){[IO.File]::WriteAllText((Join-Path $OutputDirectory 'extra-users.cfg'),$ks)}
$caught=$false
try{$null=Get-AdditionalUserConfig 'reader' $extra}catch{$caught=$true}
if(-not $caught){throw 'Primary account duplicate accepted'}
Write-Host 'OK : comptes multiples, refus des doublons/reserves, shell et sudo individuels.'

# Un secret ressemblant a un marqueur ne doit pas etre transforme par le generateur.
$extra[0].Password='__LAB_USER__123!'
$ks=Get-LabKickstart 'ansible' 'Disabled' 'network --bootproto=dhcp --device=link' 'Node' 'Disabled' '/bin/bash' @() $extra
if(-not $ks.Contains("--password='__LAB_USER__123!'")){throw 'Additional password was altered'}

# 17. Prevenir les regressions observees sur AlmaLinux minimal et vboxsf 7.2.
$shareBootstrap = Get-SharedFoldersBootstrap @([pscustomobject]@{Name='temp';ReadOnly=$false})
if ($shareBootstrap -notmatch 'install tar gzip bzip2 xz') { throw 'Missing extraction prerequisites' }
if ($shareBootstrap -match 'nofail|x-systemd.automount') { throw 'Unsupported vboxsf mount options' }
if ($shareBootstrap -notmatch 'lab_additions_ready' -or $shareBootstrap -notmatch 'modules-load.d/lab-vbox.conf') { throw 'Missing module readiness/persistence checks' }
if ($shareBootstrap -notmatch 'lab_install_rc' -or $shareBootstrap -notmatch 'runuser -u __LAB_USER__ -- test -r') { throw 'Missing installer/access checks' }
Write-Host 'OK : prerequis extraction, options vboxsf, reprise et controles des partages.'

# 18. Mise a jour et reprise : jamais de done sur la simple sortie avant reboot.
$updatedKs = Get-LabKickstart 'labadmin' 'Disabled' 'network --bootproto=dhcp --device=link --activate --hostname=lab.test' 'Controller' 'Disabled'
foreach ($required in @('config-manager --set-enabled crb','install epel-release','upgrade','kernel-headers','dkms','updated-boot-id','expected-kernel','systemctl reboot --no-block','BOOTSTRAP_REBOOT_PENDING','lab_check_kernel')) {
    if (-not $updatedKs.Contains($required)) { throw "Missing update/reboot control: $required" }
}
if ($updatedKs.Contains('ExecStartPost=/usr/bin/touch')) { throw 'Premature done marker during reboot phase' }
if ($updatedKs.IndexOf('# PHASE 1') -gt $updatedKs.IndexOf('# Verifier la syntaxe SSH')) { throw 'Update phase ordered incorrectly' }
Write-Host 'OK : mise a jour, EPEL/CRB, reprise apres reboot, noyau attendu et erreurs noyau.'

# 19. PowerShell compare les choix sans tenir compte de la casse ; Linux y est sensible.
$upperShellKs = Get-LabKickstart 'labadmin' 'Disabled' 'network --bootproto=dhcp --device=link' 'Node' 'Disabled' '/BIN/BASH'
if (-not $upperShellKs.Contains('user --name=labadmin --shell=/bin/bash')) {
    throw 'Primary shell was not normalized'
}
$upperExtra = @([pscustomobject]@{Name='reader';Shell='/BIN/SH';Sudo=$false;Password='Test-Only-123!'})
$extraConfig = Get-AdditionalUserConfig 'labadmin' $upperExtra
if (-not $extraConfig.Users.Contains('--shell=/bin/sh')) { throw 'Additional shell was not normalized' }
Write-Host 'OK : casse des chemins de shell Linux normalisee.'

# 20. Mots de passe : reessai sans arret, aucun secret affiche et nettoyage a chaque tentative.
$passwordFunction = $ast.FindAll({param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
}, $true) | Where-Object Name -eq 'Read-LabPassword'
Invoke-Expression $passwordFunction.Extent.Text
function Read-Host {
    param([string]$Prompt, [switch]$AsSecureString)
    if (-not $AsSecureString) { throw 'Saisie de secret non masquee' }
    if ($script:Answers.Count -eq 0) { throw 'Saisie interrompue pendant le test' }
    $value = $script:Answers.Dequeue()
    $secret = New-Object Security.SecureString
    foreach ($character in $value.ToCharArray()) { $secret.AppendChar($character) }
    $secret.MakeReadOnly()
    [void]$script:TestSecrets.Add($secret)
    return $secret
}
$script:TestSecrets = New-Object 'System.Collections.Generic.List[System.Security.SecureString]'
$tooLong = 'a' * 129
Set-TestAnswers @('Test-Only-123!','Test-Only-456!', 'short','short',
    'Invalid$Test123','Invalid$Test123', '', '', $tooLong,$tooLong,
    'Valid-Test-123!','Valid-Test-123!')
$output = @(Read-LabPassword 'fictif' 6>&1)
$messages = @($output | Where-Object { $_ -is [System.Management.Automation.InformationRecord] })
$values = @($output | Where-Object { $_ -isnot [System.Management.Automation.InformationRecord] })
if ($script:Answers.Count -ne 0 -or $values.Count -ne 1 -or $values[0] -cne 'Valid-Test-123!') {
    throw 'Password retry or success output failed'
}
if (($messages -join ' ') -match 'Test-Only|Invalid\$Test|Valid-Test') { throw 'Secret exposed in messages' }
foreach ($secret in $script:TestSecrets) {
    $disposed = $false
    try { $copy = $secret.Copy(); $copy.Dispose() } catch { $disposed = $true }
    if (-not $disposed) { throw 'SecureString was not disposed' }
}
# Erreur de lecture a la confirmation : propager, sans boucle infinie ; nettoyer la premiere saisie.
$script:TestSecrets.Clear()
Set-TestAnswers @('Valid-Test-123!')
$caught = $false
try { $null = Read-LabPassword 'fictif' } catch { $caught = $true }
if (-not $caught) { throw 'Input failure swallowed' }
$disposed = $false
try { $copy = $script:TestSecrets[0].Copy(); $copy.Dispose() } catch { $disposed = $true }
if (-not $disposed) { throw 'First input not disposed after confirmation failure' }
Write-Host 'OK : confirmation, longueur, caracteres, reessais, secrets masques et nettoyage.'

# 21. Comptes et secrets fournis : validation avant creation et aucune question complete.
foreach ($functionName in @('Assert-LabPassword','Get-ConfiguredUsers')) {
    $function = $ast.FindAll({param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true) | Where-Object Name -eq $functionName
    Invoke-Expression $function.Extent.Text
}
$configured = @(Get-ConfiguredUsers '[{"Name":"batchlab","Shell":"/bin/bash","Sudo":true,"Password":"Batch-Test-123!"}]' 'duas')
if ($configured.Count -ne 1 -or $configured[0].Password -cne 'Batch-Test-123!' -or -not $configured[0].Sudo) {
    throw 'Configured account failed'
}
if (@(Get-ConfiguredUsers '[]' 'duas').Count -ne 0) { throw 'Empty users failed' }
$missing = @(Get-ConfiguredUsers '[{"Name":"reader","Shell":"/bin/sh","Sudo":false}]' 'duas')
if ($null -ne $missing[0].Password) { throw 'Absent password must stay interactive' }
foreach ($invalid in @(
    '[{"Name":"duas","Shell":"/bin/sh","Sudo":false}]',
    '[{"Name":"reader","Shell":"/bin/sh","Sudo":"false"}]',
    '[{"Name":"reader","Shell":"/bin/sh","Sudo":false,"Password":"short"}]',
    '[{"Name":"reader","Shell":"/bin/sh","Sudo":false,"Password":null}]',
    '[{"Name":"reader","Shell":"/bin/sh","Sudo":false,"Pasword":"secret"}]',
    'not-json'
)) {
    $caught=$false
    try { $null=Get-ConfiguredUsers $invalid 'duas' } catch { $caught=$true }
    if (-not $caught) { throw 'Invalid configured user accepted' }
}
# Executer le vrai bloc de selection des secrets avec tous les arguments fournis.
$start = $sourceText.IndexOf('    $password = if ($PSBoundParameters.ContainsKey(')
$end = $sourceText.IndexOf('    # Generer apres la saisie', $start)
$selectSecrets = [scriptblock]::Create(
    'param([string]$UserPassword,[string]$RootPassword)' + "`n" +
    $sourceText.Substring($start, $end-$start) + "`n" +
    '[pscustomobject]@{User=$password;Root=$rootPasswordPlain;Extra=$additionalUsers[0].Password}')
$RootAccess='Enabled'; $LinuxUser='duas'; $additionalUsers=$configured
Set-TestAnswers @()
$result = & $selectSecrets -UserPassword 'User-Test-123!' -RootPassword 'Root-Test-123!'
if ($result.User -cne 'User-Test-123!' -or $result.Root -cne 'Root-Test-123!' -or $result.Extra -cne 'Batch-Test-123!') {
    throw 'Provided secrets not selected'
}
# Sans UserPassword, seule cette question et sa confirmation doivent etre posees.
Set-TestAnswers @('Mixed-Test-123!','Mixed-Test-123!')
$result = & $selectSecrets -RootPassword 'Root-Test-123!'
if ($result.User -cne 'Mixed-Test-123!' -or $script:Answers.Count) { throw 'Mixed password selection failed' }
Write-Host 'OK : comptes JSON, secrets fournis sans question et saisie des seuls secrets absents.'

# 22. Le parseur objet preserve les cardinalites, independamment du pipeline 5.1/7.
foreach ($emptyJson in @('[]', '[ ]', " [ `n ] ")) {
    if (@(Get-ConfiguredUsers $emptyJson 'duas').Count -ne 0) {
        throw 'Empty JSON array must produce no accounts'
    }
}
$twoUsers = @(Get-ConfiguredUsers '[{"Name":"reader","Shell":"/bin/sh","Sudo":false},{"Name":"admin2","Shell":"/bin/bash","Sudo":true}]' 'duas')
if ($twoUsers.Count -ne 2 -or $twoUsers[1].Name -ne 'admin2') { throw 'JSON array cardinality lost' }
foreach ($invalid in @('[null]', '[[{"Name":"reader","Shell":"/bin/sh","Sudo":false}]]')) {
    $caught = $false
    try { $null = Get-ConfiguredUsers $invalid 'duas' } catch { $caught = $true }
    if (-not $caught) { throw 'Null or nested user accepted' }
}
Write-Host 'OK : tableaux JSON vides, un/deux comptes, rejet de null et des tableaux imbriques.'

# 23. Lire le fichier livre via le vrai bloc du programme, sans pont ni VirtualBox.
$start = $sourceText.IndexOf('        # JSON PARTAGES')
$end = $sourceText.IndexOf('        # FIN JSON PARTAGES', $start)
$readShares = [scriptblock]::Create('param([string]$SharedFoldersFile)' + "`n" +
    $sourceText.Substring($start,$end-$start) + "`n" + '$items')
$fromPack = @(& $readShares (Join-Path $PSScriptRoot 'partages.json'))
if ($fromPack.Count -ne 1 -or $fromPack[0].Name -ne 'temp' -or
    $fromPack[0].HostPath -ne 'C:\Lab-Partage' -or
    $fromPack[0].ReadOnly -isnot [bool] -or $fromPack[0].ReadOnly) {
    throw 'Pack shared folder JSON incorrectly parsed'
}
$tempJson = [IO.Path]::GetTempFileName()
try {
    $fixture = [pscustomobject]@{Name='temp';HostPath=$PSScriptRoot;ReadOnly=$false}
    foreach ($json in @(
        (ConvertTo-Json -InputObject $fixture),
        (ConvertTo-Json -InputObject @($fixture))
    )) {
        [IO.File]::WriteAllText($tempJson,$json)
        $parsed = @(& $readShares $tempJson)
        $validated = @(Get-ValidatedShares $parsed)
        if ($validated.Count -ne 1 -or $validated[0].Name -ne 'temp') { throw 'Single share parsing failed' }
    }
    $fixture2 = [pscustomobject]@{Name='documents';HostPath=$PSScriptRoot;ReadOnly=$true}
    [IO.File]::WriteAllText($tempJson,(ConvertTo-Json -InputObject @($fixture,$fixture2)))
    $validated = @(Get-ValidatedShares @(& $readShares $tempJson))
    if ($validated.Count -ne 2 -or -not $validated[1].ReadOnly) { throw 'Multiple shares parsing failed' }
    [IO.File]::WriteAllText($tempJson,'[]')
    if (@(& $readShares $tempJson).Count -ne 0) { throw 'Empty shares not preserved' }
    foreach ($invalid in @('[null]', '[[{}]]', '[{"Name":"temp"}]', 'not-json')) {
        [IO.File]::WriteAllText($tempJson,$invalid)
        $caught=$false
        try { $null=Get-ValidatedShares @(& $readShares $tempJson) } catch { $caught=$true }
        if (-not $caught) { throw 'Invalid shared folder JSON accepted' }
    }
} finally { Remove-Item -LiteralPath $tempJson -Force }
Write-Host 'OK : fichier partages.json livre, objet unique, tableaux vide/simple/multiple et validations.'
