#requires -Version 5.1
<#
.SYNOPSIS
Version 26 : cree une VM AlmaLinux 9 configurable, controleur Ansible ou noeud Linux.
.DESCRIPTION
Execution depuis Windows avec VirtualBox 7.2 ; Ethernet prioritaire, puis Wi-Fi.
Choix interactifs : noms, CPU, RAM, disque, hostname, comptes, shells, sudo, root, SSH, reseau, role, partages.
Seules les VMs nouvelles ou totalement vides sont acceptees ; aucun disque n'est efface.
Les valeurs absentes sont demandees ; les mots de passe peuvent aussi etre fournis en arguments.
Lire README.md pour l'usage et REVUE-CODE.md pour les controles et limites.
.NOTES
Extraire TOUS les fichiers dans C:\Lab-Ansible, y compris partages.json fourni.
Le dossier partage C:\Lab-Partage doit exister.
Adapter chemins, noms/IP disponibles et mots de passe fictifs ci-dessous.
Les secrets litteraux peuvent rester dans l historique PowerShell.
.EXAMPLE
powershell.exe -NoProfile -ExecutionPolicy Bypass
Exemple 1/5 : ouvrir cette session une fois, puis choisir un exemple ci-dessous.
.EXAMPLE
& 'C:\Lab-Ansible\New-AnsibleLab.ps1' -IsoPath 'C:\Lab-Ansible\ISO\AlmaLinux-9.8-x86_64-minimal.iso' -VmCount 1 -VmName 'ansible' -HostName 'ansible.lab.test' -LinuxUser 'ansible' -UserPassword 'Exemple-Ansible-123!' -LoginShell '/bin/bash' -VmRole Controller -RootAccess Enabled -RootPassword 'Exemple-Root-123!' -RootSshPassword Enabled -CpuCount 2 -MemoryMB 2048 -DiskGB 20 -NetworkMode Static -IpAddress '192.168.1.53' -PrefixLength 24 -Gateway '192.168.1.254' -DnsServers '192.168.1.254' -SharedFoldersMode Enabled -SharedFoldersFile 'C:\Lab-Ansible\partages.json' -AdditionalUsersJson '[]'
Exemple 2/5 : creation de ansible (controleur) sans question si tous les arguments sont valides.
.EXAMPLE
& 'C:\Lab-Ansible\New-AnsibleLab.ps1' -IsoPath 'C:\Lab-Ansible\ISO\AlmaLinux-9.8-x86_64-minimal.iso' -VmCount 1 -VmName 'uvms' -HostName 'uvms.lab.test' -LinuxUser 'uvms' -UserPassword 'Exemple-Uvms-123!' -LoginShell '/bin/bash' -VmRole Node -RootAccess Enabled -RootPassword 'Exemple-Root-123!' -RootSshPassword Enabled -CpuCount 2 -MemoryMB 2048 -DiskGB 20 -NetworkMode Static -IpAddress '192.168.1.54' -PrefixLength 24 -Gateway '192.168.1.254' -DnsServers '192.168.1.254' -SharedFoldersMode Enabled -SharedFoldersFile 'C:\Lab-Ansible\partages.json' -AdditionalUsersJson '[]'
Exemple 3/5 : creation de uvms (noeud) sans question si tous les arguments sont valides.
.EXAMPLE
& 'C:\Lab-Ansible\New-AnsibleLab.ps1' -IsoPath 'C:\Lab-Ansible\ISO\AlmaLinux-9.8-x86_64-minimal.iso' -VmCount 1 -VmName 'duas' -HostName 'duas.lab.test' -LinuxUser 'duas' -UserPassword 'Exemple-Duas-123!' -LoginShell '/bin/bash' -VmRole Node -RootAccess Enabled -RootPassword 'Exemple-Root-123!' -RootSshPassword Enabled -CpuCount 2 -MemoryMB 2048 -DiskGB 20 -NetworkMode Static -IpAddress '192.168.1.55' -PrefixLength 24 -Gateway '192.168.1.254' -DnsServers '192.168.1.254' -SharedFoldersMode Enabled -SharedFoldersFile 'C:\Lab-Ansible\partages.json' -AdditionalUsersJson '[{"Name":"batchlab","Shell":"/bin/bash","Sudo":true,"Password":"Exemple-Batch-123!"}]'
Exemple 4/5 : creation de duas (noeud avec batchlab et sudo) sans question si tous les arguments sont valides.
.EXAMPLE
& 'C:\Lab-Ansible\New-AnsibleLab.ps1'
Exemple 5/5 : lancement interactif, sans parametre de configuration.
PowerShell demande d abord IsoPath, puis le script demande les choix du lab.
Les questions conditionnelles suivent les reponses : IP si Static, mot de passe
root si active, comptes supplementaires et partages si demandes.
Les chemins techniques et la carte de pont conservent leur detection automatique.
#>
# ETAPE 1 - Parametres : valeurs par defaut et validation avant toute action.
# Les ETAPES de code decrivent le flux interne ; les sections 1/9 a 9/9 guident la saisie.
[CmdletBinding()]
param(
    # Media source et ressources VirtualBox ; ces valeurs ne redimensionnent pas une VM existante.
    [Parameter(Mandatory=$true)][string]$IsoPath,
    [ValidatePattern('^[a-z][a-z0-9-]{0,30}$')][string]$VmName = 'ansible01',
    # Lot : noms interactifs independants ; numerotation automatique si VmName est fourni.
    [ValidateRange(1,16)][int]$VmCount = 1,
    # Adresses IPv4 du lot statique, dans l ordre des VMs, separees par des virgules.
    [string]$IpAddresses,
    # Sans argument explicite, ces valeurs sont proposees a la saisie (Entree les conserve).
    # RAM en Mo : 2048 = 2 Go, 4096 = 4 Go ; disque en Go, allocation dynamique.
    [ValidateRange(2048,32768)][int]$MemoryMB = 2048,
    [ValidateRange(1,16)][int]$CpuCount = 2,
    [ValidateRange(20,500)][int]$DiskGB = 30,
    # Dossier VM par defaut dans le profil ; carte physique et executable detectes si omis.
    [string]$VmBasePath = (Join-Path $env:USERPROFILE 'VirtualBox VMs'),
    [string]$BridgeAdapter,
    [string]$VBoxManagePath,
    # Identite Linux, distincte du nom de la VM dans VirtualBox.
    [string]$HostName,
    [string]$LinuxUser,
    # Facultatifs : absents, saisie masquee ; presents, validation sans confirmation.
    # Les secrets litteraux peuvent rester dans l historique et les arguments du processus.
    [string]$UserPassword,
    [string]$RootPassword,
    # Tableau JSON : Name, Shell, Sudo (booleen), Password facultatif pour chaque compte.
    [string]$AdditionalUsersJson,
    # -1 signifie question interactive ; 0 conserve seulement le compte principal.
    [ValidateRange(-1,10)][int]$AdditionalUserCount = -1,
    # Shells fournis par la base minimale ; aucun paquet supplementaire requis.
    [ValidateSet('/bin/bash','/bin/sh')][string]$LoginShell,
    # Choix separes ; SSH root par mot de passe exige RootAccess Enabled.
    [ValidateSet('Enabled','Disabled')][string]$RootAccess,
    [ValidateSet('Enabled','Disabled')][string]$RootSshPassword,
    # Configuration IPv4 appliquee dans la VM, sans modifier celle du PC Windows.
    [ValidateSet('Dhcp','Static')][string]$NetworkMode,
    [string]$IpAddress,
    [ValidateRange(0,30)][int]$PrefixLength = 0,
    [string]$Gateway,
    [string]$DnsServers,
    # Le controleur recoit Ansible ; le noeud recoit uniquement les prerequis Linux.
    [ValidateSet('Controller','Node')][string]$VmRole,
    # Partages optionnels : fichier JSON pour un lot identique, sinon questions par VM.
    [ValidateSet('Enabled','Disabled')][string]$SharedFoldersMode,
    [string]$SharedFoldersFile,
    [string]$GuestAdditionsIsoPath,
    [switch]$CheckOnly,
    # Contexte visuel transmis aux appels enfants ; ne change aucune configuration VM.
    [Parameter(DontShow=$true)][ValidateRange(1,16)][int]$DisplayIndex = 1,
    [Parameter(DontShow=$true)][ValidateRange(1,16)][int]$DisplayTotal = 1
)
# Les variables non initialisees et les erreurs PowerShell interrompent le traitement.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# FONCTIONS UTILITAIRES - Definitions chargees avant les validations du programme principal.

# PRESENTATION - Write-Host garde le flux de donnees libre pour les fonctions appelantes.
# Couleurs natives PowerShell : pas de sequences ANSI, pas de module a installer.
# Aucun effacement de console : les messages et erreurs restent consultables.
function Write-LabBanner {
    param([string]$Title, [string]$Subtitle)
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    if ($Subtitle) { Write-Host "  $Subtitle" -ForegroundColor Gray }
    Write-Host ('=' * 72) -ForegroundColor Cyan
}
function Write-LabSection {
    param([string]$Title)
    Write-Host ''
    Write-Host "  --- $Title ---" -ForegroundColor Cyan
}
function Write-LabField {
    param([string]$Label, [string]$Value)
    Write-Host ('  {0,-20} : {1}' -f $Label, $Value)
}

# Question oui/non reutilisable ; une erreur de saisie repose la question.
function Read-LabYesNo {
    param([string]$Label, [string]$Default = 'n')
    while ($true) {
        $answer = Read-Default "$Label o/n" $Default
        if ($answer -in @('o','oui','y','yes')) { return $true }
        if ($answer -in @('n','non','no')) { return $false }
        Write-Host '  Reponse attendue : o ou n.' -ForegroundColor Yellow
    }
}
# Les noms limites rendent les points de montage et les insertions shell non ambigus.
# Le chemin Windows n est jamais injecte dans le shell Linux.
function Get-ValidatedShares {
    param([object[]]$Items)
    $seen = @{}
    foreach ($item in $Items) {
        if ($null -eq $item -or $item -is [array]) { throw 'Chaque partage doit etre un objet JSON non nul.' }
        $properties = @($item.PSObject.Properties.Name)
        if ('Name' -notin $properties -or 'HostPath' -notin $properties -or 'ReadOnly' -notin $properties) {
            throw 'Chaque partage exige Name, HostPath et ReadOnly (booleen JSON).'
        }
        $name = [string]$item.Name
        if ($name -cnotmatch '^[a-z][a-z0-9_-]{0,31}$' -or $seen.ContainsKey($name)) {
            throw "Nom de partage invalide ou duplique : $name"
        }
        if ($item.ReadOnly -isnot [bool]) { throw 'ReadOnly doit etre true ou false, sans guillemets en JSON.' }
        if (-not (Test-Path -LiteralPath $item.HostPath -PathType Container)) {
            throw "Dossier Windows introuvable : $($item.HostPath)"
        }
        $resolved = (Resolve-Path -LiteralPath $item.HostPath).ProviderPath
        $seen[$name] = $true
        [pscustomobject]@{Name=$name; HostPath=$resolved; ReadOnly=$item.ReadOnly}
    }
}
# Installation optionnelle des Guest Additions et montage persistant des partages.
# Tout echec remonte au trap du bootstrap : aucun READY si un montage echoue.
function Get-SharedFoldersBootstrap {
    param([object[]]$Shares)
    if ($Shares.Count -eq 0) { return '# Aucun dossier partage demande.' }
    $body = @'
# Installer aussi les outils d extraction absents de certaines images minimales.
lab_stage='Guest Additions : prerequis'
echo 'Installing Guest Additions prerequisites and shared folders...'
dnf -y --setopt=timeout=30 --setopt=retries=2 install tar gzip bzip2 xz gcc make perl elfutils-libelf-devel "kernel-devel-$(uname -r)"
# La presence des outils ET des modules chargeables permet une reprise sans reinstallation.
# Aucun partage deja monte n est requis pour ce controle.
lab_additions_ready() {
    command -v VBoxControl >/dev/null &&
    VBoxControl --version >/dev/null &&
    test -x /sbin/rcvboxadd &&
    modprobe vboxguest && modprobe vboxsf
}
if lab_additions_ready; then
    echo 'Guest Additions deja disponibles : installation ignoree.'
else
    lab_stage='Guest Additions : installation'
    # Le CD a ete copie avant son ejection. Conserver et journaliser le code retour.
    # Compatibilite avec les echecs observes sur les images minimales : le code 2
    # est tolere seulement si les controles outils/modules/montages reussissent.
    lab_install_rc=0
    sh /var/lib/lab-bootstrap/guest-additions/VBoxLinuxAdditions.run no_setup || lab_install_rc=$?
    echo "Guest Additions installer exit code: $lab_install_rc"
    if [ "$lab_install_rc" -ne 0 ] && [ "$lab_install_rc" -ne 2 ]; then
        exit "$lab_install_rc"
    fi
    if ! lab_additions_ready; then
        lab_stage='Guest Additions : compilation des modules'
        lab_setup_rc=0
        /sbin/rcvboxadd setup || lab_setup_rc=$?
        echo "Guest Additions setup exit code: $lab_setup_rc"
        if [ "$lab_setup_rc" -ne 0 ] && [ "$lab_setup_rc" -ne 2 ]; then
            exit "$lab_setup_rc"
        fi
    fi
    lab_additions_ready
fi
# Charger le pilote avant les montages fstab lors des prochains demarrages.
printf '%s\n' vboxguest vboxsf > /etc/modules-load.d/lab-vbox.conf
# Montage via fstab, independant du service d automontage VirtualBox.
lab_uid=$(id -u __LAB_USER__)
lab_gid=$(id -g __LAB_USER__)
'@
    foreach ($share in $Shares) {
        $name = $share.Name
        $mode = if ($share.ReadOnly) { 'ro' } else { 'rw' }
        $body += "`n" + @'
# Partage __SHARE_NAME__ : montage classique, sans options systemd transmises a vboxsf.
lab_stage='Montage du partage __SHARE_NAME__'
install -d -m 0755 /mnt/__SHARE_NAME__
share_entry="__SHARE_NAME__ /mnt/__SHARE_NAME__ vboxsf __SHARE_MODE__,uid=${lab_uid},gid=${lab_gid},dmode=0700,fmode=0600 0 0"
grep -Fqx "$share_entry" /etc/fstab || printf '%s\n' "$share_entry" >> /etc/fstab
systemctl daemon-reload
mountpoint -q /mnt/__SHARE_NAME__ || mount /mnt/__SHARE_NAME__
findmnt -rn -t vboxsf --mountpoint /mnt/__SHARE_NAME__
runuser -u __LAB_USER__ -- test -r /mnt/__SHARE_NAME__
'@.Replace('__SHARE_NAME__',$name).Replace('__SHARE_MODE__',$mode)
    }
    return $body
}

# Copier les Additions avant reboot --eject : ne pas dependre d un DVD encore insere.
# Le %post hors chroot voit les lecteurs virtuels et /mnt/sysroot du systeme installe.
function Get-GuestAdditionsCopyPost {
    param([object[]]$Shares)
    if ($Shares.Count -eq 0) { return '' }
    return @'
%post --nochroot --erroronfail --log=/mnt/sysroot/root/ks-additions-copy.log
set -eu
mkdir -p /tmp/lab-additions-cd /mnt/sysroot/var/lib/lab-bootstrap/guest-additions
found_additions=0
for device in /dev/sr*; do
    [ -b "$device" ] || continue
    if mount -o ro "$device" /tmp/lab-additions-cd; then
        if [ -f /tmp/lab-additions-cd/VBoxLinuxAdditions.run ]; then
            cp -a /tmp/lab-additions-cd/. /mnt/sysroot/var/lib/lab-bootstrap/guest-additions/
            found_additions=1
            umount /tmp/lab-additions-cd
            break
        fi
        umount /tmp/lab-additions-cd
    fi
done
[ "$found_additions" -eq 1 ] || { echo 'Guest Additions ISO missing' >&2; exit 1; }
%end
'@
}

# Choisir un port libre apres unattended, qui peut reorganiser les DVD.
# Ports 0/1 reserves au disque et au media OS ; ne jamais remplacer un media occupe.
function Get-FreeLabDvdPort {
    param([string]$MachineInfo)
    foreach ($port in @(2,3)) {
        $entry = [regex]::Match($MachineInfo, ('(?m)^"LabSATA-' + $port + '-0"="([^"\r\n]*)"\r?$'))
        if (-not $entry.Success -or $entry.Groups[1].Value -in @('none','emptydrive')) { return $port }
    }
    throw 'Aucun port DVD libre sur LabSATA ; aucun support existant ne sera remplace.'
}

# Validation commune aux comptes principal et supplementaires.
function Assert-LabUserName {
    param([string]$UserName)
    if ($UserName -cnotmatch '^[a-z_][a-z0-9_-]{0,31}$' -or $UserName -in @(
        'root','bin','daemon','adm','lp','sync','shutdown','halt','mail','operator','games','ftp',
        'nobody','dbus','sshd','chrony','systemd-network','systemd-resolve','polkitd','tss','rpc','apache')) {
        throw 'Nom utilisateur invalide ou reserve. Choisir un compte utilisateur personnel.'
    }
}
# Recueillir les identites sans mot de passe ; secrets demandes apres le recapitulatif.
function Read-AdditionalUsers {
    param([string]$PrimaryName,[int]$Count)
    $chosen = @($PrimaryName)
    for ($i = 1; $i -le $Count; $i++) {
        Write-LabSection "COMPTE SUPPLEMENTAIRE $i/$Count"
        while ($true) {
            $name = Read-Default 'Nom du compte Linux' "labuser$i"
            try { Assert-LabUserName $name } catch {
                Write-Host $_.Exception.Message -ForegroundColor Yellow
                continue
            }
            if ($name -in $chosen) {
                Write-Host '  Ce compte est deja defini pour cette VM.' -ForegroundColor Yellow
                continue
            }
            break
        }
        while ($true) {
            $shell = Read-Default 'Shell : /bin/bash ou /bin/sh' '/bin/bash'
            if ($shell -in @('/bin/bash','/bin/sh')) { break }
            Write-Host '  Choisir /bin/bash ou /bin/sh.' -ForegroundColor Yellow
        }
        $shell = $shell.ToLowerInvariant()
        $sudo = Read-LabYesNo "Autoriser sudo pour $name ?" 'n'
        $chosen += $name
        [pscustomobject]@{Name=$name;Shell=$shell;Sudo=$sudo;Password=$null}
    }
}
# Construire uniquement les directives de comptes ; le mot de passe valide ne contient
# ni apostrophe ni retour a la ligne, ce qui permet le quoting Kickstart ci-dessous.
function Get-AdditionalUserConfig {
    param([string]$PrimaryName,[object[]]$Users)
    $names = @($PrimaryName)
    $userLines = @()
    $sudoLines = @()
    foreach ($account in $Users) {
        Assert-LabUserName $account.Name
        if ($account.Name -in $names) { throw 'Compte supplementaire duplique.' }
        if ($account.Shell -notin @('/bin/bash','/bin/sh') -or $account.Sudo -isnot [bool]) {
            throw 'Shell ou droits sudo invalides pour le compte supplementaire.'
        }
        if ($account.Password -cnotmatch '^[A-Za-z0-9!@%_=+.,:-]{12,128}$') {
            throw 'Mot de passe de compte supplementaire absent ou invalide.'
        }
        $names += $account.Name
        $accountShell = $account.Shell.ToLowerInvariant()
        $groups = if ($account.Sudo) { ' --groups=wheel' } else { '' }
        $userLines += "user --name=$($account.Name) --shell=$accountShell$groups --password='$($account.Password)' --plaintext"
        if ($account.Sudo) { $sudoLines += "$($account.Name) ALL=(ALL) ALL" }
    }
    [pscustomobject]@{Users=($userLines -join "`n");Sudo=($sudoLines -join "`n")}
}

# Valider un secret fourni sans l afficher ni demander de nouvelle saisie.
function Assert-LabPassword {
    param([string]$Value)
    if ($Value -cnotmatch '^[A-Za-z0-9!@%_=+.,:-]{12,128}$') {
        throw 'Mot de passe fourni invalide : utiliser 12-128 caracteres, lettres, chiffres et ! @ % _ = + . , : -'
    }
}

# Copier les comptes JSON dans des objets internes pour ne pas modifier les arguments du lot.
# Password omis declenche la saisie masquee ; present, il doit respecter les memes regles.
function Get-ConfiguredUsers {
    param([string]$Json, [string]$PrimaryName)
    if (-not $Json.TrimStart().StartsWith('[')) { throw 'AdditionalUsersJson doit etre un tableau JSON.' }
    # Une propriete objet conserve le tableau JSON, y compris [], sans dependre
    # de son enumeration dans le pipeline (differente entre PowerShell 5.1 et 7).
    try {
        $document = ConvertFrom-Json -InputObject ('{"Accounts":' + $Json + '}')
        $items = @($document.Accounts)
    }
    catch { throw 'AdditionalUsersJson : JSON invalide.' }
    if ($items.Count -gt 10) { throw 'Maximum 10 comptes supplementaires.' }
    $seen = @($PrimaryName)
    foreach ($item in $items) {
        if ($null -eq $item) { throw 'Compte JSON nul interdit.' }
        $fields = @($item.PSObject.Properties.Name)
        if ('Name' -notin $fields -or 'Shell' -notin $fields -or 'Sudo' -notin $fields) {
            throw 'Chaque compte JSON exige Name, Shell et Sudo.'
        }
        if (@($fields | Where-Object { $_ -notin @('Name','Shell','Sudo','Password') }).Count) {
            throw 'Champ de compte JSON inconnu.'
        }
        Assert-LabUserName $item.Name
        if ($item.Name -in $seen) { throw 'Compte supplementaire duplique.' }
        if ($item.Shell -notin @('/bin/bash','/bin/sh') -or $item.Sudo -isnot [bool]) {
            throw 'Shell ou booleen Sudo invalide.'
        }
        $secret = $null
        if ('Password' -in $fields) {
            if ($item.Password -isnot [string]) { throw 'Password doit etre une chaine.' }
            Assert-LabPassword $item.Password
            $secret = $item.Password
        }
        $seen += $item.Name
        [pscustomobject]@{Name=$item.Name;Shell=$item.Shell.ToLowerInvariant();Sudo=$item.Sudo;Password=$secret}
    }
}

# Executer VBoxManage, verifier son code retour et retirer ses lignes affichant un mot de passe.
function Invoke-VBox {
    param([Parameter(Mandatory=$true)][string[]]$Arguments)
    # Windows PowerShell transforme parfois stderr en NativeCommandError.
    # Le code retour natif reste la reference pour distinguer succes et echec.
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $lines = @(& $script:VBoxManagePath @Arguments 2>&1 | ForEach-Object { "$_" })
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    # VBoxManage affiche les mots de passe meme avec --password-file : ne pas relayer ces lignes.
    $safeLines = @($lines | Where-Object { $_ -notmatch '(?i)password\s*=' })
    if ($code -ne 0) {
        throw "VBoxManage $($Arguments[0]) failed (exit $code).`n$($safeLines -join "`n")"
    }
    return $safeLines
}

# Ecrire les fichiers Linux en UTF-8 sans BOM, avec fins de ligne LF.
function Write-LinuxFile {
    param([string]$Path, [string]$Content)
    [IO.File]::WriteAllText($Path, ($Content -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
}

# Restreindre le dossier de preparation au compte Windows courant et a SYSTEM.
function Protect-Directory {
    param([string]$Path)
    # Poser les ACL NTFS avant toute ecriture de secret.
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $systemSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
    foreach ($principal in @($sid, $systemSid)) {
        $rule = New-Object Security.AccessControl.FileSystemAccessRule(
            $principal, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $acl.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $acl
}

# Poser une question ; Entree conserve la proposition affichee entre crochets.
function Read-Default {
    param([string]$Label, [string]$Default)
    $value = Read-Host "$Label [$Default]"
    if ([string]::IsNullOrWhiteSpace($value)) { return $Default }
    return $value.Trim()
}

# Demander une ressource numerique et reposer la question si la saisie est invalide.
# Les bornes sont les memes que celles des parametres : aucun changement de limite.
function Read-IntegerChoice {
    param([string]$Label, [int]$Default, [int]$Minimum, [int]$Maximum)
    while ($true) {
        $answer = Read-Default "$Label ($Minimum a $Maximum)" ([string]$Default)
        [int]$value = 0
        if ([int]::TryParse($answer, [ref]$value) -and $value -ge $Minimum -and $value -le $Maximum) {
            return $value
        }
        Write-Host "Saisir un nombre entier entre $Minimum et $Maximum." -ForegroundColor Yellow
    }
}
# Redemander les deux saisies si le secret est invalide ou si elles different.
# Les erreurs techniques et l annulation restent propagees ; aucun secret n est journalise.
# Liberer les SecureString et les buffers natifs a CHAQUE tentative, meme en erreur.
function Read-LabPassword {
    param([string]$Account)
    while ($true) {
        $first = $null
        $second = $null
        $plain = $null
        $confirmation = $null
        $ptr1 = [IntPtr]::Zero
        $ptr2 = [IntPtr]::Zero
        try {
            $first = Read-Host "Mot de passe de $Account (12-128 caracteres)" -AsSecureString
            $second = Read-Host 'Confirmer le mot de passe' -AsSecureString
            $ptr1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($first)
            $ptr2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($second)
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr1)
            $confirmation = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr2)
            if ($plain -cne $confirmation) {
                Write-Host '  Les mots de passe sont differents. Recommencer les deux saisies.' -ForegroundColor Yellow
                continue
            }
            if ($plain -cnotmatch '^[A-Za-z0-9!@%_=+.,:-]{12,128}$') {
                Write-Host '  Utiliser 12-128 caracteres : lettres, chiffres et ! @ % _ = + . , : -' -ForegroundColor Yellow
                Write-Host '  Recommencer les deux saisies pour ce compte.' -ForegroundColor Yellow
                continue
            }
            return $plain
        } finally {
            if ($ptr1 -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr1) }
            if ($ptr2 -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr2) }
            if ($null -ne $first) { $first.Dispose() }
            if ($null -ne $second) { $second.Dispose() }
            $plain = $null
            $confirmation = $null
        }
    }
}
# Convertir une IPv4 stricte en entier 64 bits pour comparer les sous-reseaux sans overflow.
function Convert-IPv4Number {
    param([string]$Value)
    if ($Value -notmatch '^(0|[1-9][0-9]{0,2})(\.(0|[1-9][0-9]{0,2})){3}$') {
        throw "Adresse IPv4 invalide : $Value"
    }
    [long]$number = 0
    foreach ($octet in $Value.Split('.')) {
        if ([int]$octet -gt 255) { throw "Adresse IPv4 invalide : $Value" }
        $number = $number * 256 + [int]$octet
    }
    if ($Value -match '^(0|127|169\.254)\.' -or [int]$Value.Split('.')[0] -ge 224) {
        throw "Adresse IPv4 non utilisable pour ce lab : $Value"
    }
    return $number
}
# Verifier IP/passerelle/DNS et calculer le masque a partir du prefixe CIDR.
function Get-StaticNetwork {
    param([string]$Address,[int]$Prefix,[string]$Router,[string]$Dns)
    if ($Prefix -lt 1 -or $Prefix -gt 30) { throw 'Le prefixe IPv4 doit etre compris entre 1 et 30.' }
    $ipNumber = Convert-IPv4Number $Address
    $gatewayNumber = Convert-IPv4Number $Router
    [long]$blockSize = [math]::Pow(2,32-$Prefix)
    [long]$network = [math]::Floor($ipNumber / $blockSize) * $blockSize
    [long]$broadcast = $network + $blockSize - 1
    if ($ipNumber -eq $network -or $ipNumber -eq $broadcast) { throw 'IP reseau ou broadcast interdite.' }
    if ($gatewayNumber -le $network -or $gatewayNumber -ge $broadcast -or $gatewayNumber -eq $ipNumber) {
        throw 'La passerelle doit etre une autre adresse hote du meme sous-reseau.'
    }
    $servers = @($Dns.Split(',') | ForEach-Object { $_.Trim() })
    if ($servers.Count -lt 1 -or $servers.Count -gt 3) { throw 'Indiquer 1 a 3 DNS IPv4 separes par des virgules.' }
    foreach ($server in $servers) { $null = Convert-IPv4Number $server }
    [long]$mask = 4294967296 - $blockSize
    $octets = foreach ($shift in @(24,16,8,0)) { (($mask -shr $shift) -band 255) }
    return [pscustomobject]@{ Netmask=($octets -join '.'); Dns=($servers -join ',') }
}

# Verifier les choix root ; SSH par mot de passe exige un mot de passe root actif.
function Assert-RootSettings {
    param([string]$RootMode,[string]$SshMode)
    if ($RootMode -notin @('Enabled','Disabled') -or $SshMode -notin @('Enabled','Disabled')) {
        throw 'Les choix root et SSH root doivent etre Enabled ou Disabled.'
    }
    if ($SshMode -eq 'Enabled' -and $RootMode -ne 'Enabled') {
        throw 'Le SSH root par mot de passe exige -RootAccess Enabled.'
    }
}

# Nettoyer un secret temporaire sans masquer une erreur principale deja survenue.
function Remove-SecretFile {
    param([string]$Path)
    if (-not $Path) { return }
    try {
        if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Force -ErrorAction Stop }
    } catch {
        Write-Warning "Suppression du secret temporaire impossible : $Path. Supprimez-le apres diagnostic."
    }
}

# Generer un Kickstart autonome ; seules les valeurs deja validees y sont inserees.
function Get-LabKickstart {
    param([string]$UserName,[string]$RootMode,[string]$NetworkLine,[string]$Role,
          [string]$RootSshMode = 'Disabled',
          [ValidateSet('/bin/bash','/bin/sh')][string]$UserShell = '/bin/bash',
          [object[]]$Shares = @(), [object[]]$AdditionalUsers = @())
    $UserShell = $UserShell.ToLowerInvariant()
    $extraConfig = Get-AdditionalUserConfig $UserName $AdditionalUsers
    Assert-RootSettings $RootMode $RootSshMode
    $RootSshMode = if ($RootSshMode -eq 'Enabled') { 'Enabled' } else { 'Disabled' }
    $template = @'
# AlmaLinux 9 minimal - BIOS / SATA / configurable network
# KS 1 - Installer depuis le media local, en mode texte.
text
cdrom
# KS 2 - Langue, clavier et fuseau ; aucune politique NTP personnalisee.
lang en_US.UTF-8
keyboard --vckeymap=fr --xlayouts=fr
timezone Europe/Paris --utc
# KS 3 - Reseau et comptes ; VirtualBox substitue les secrets principal/root.
# Les comptes supplementaires sont inseres par PowerShell apres validation.
__NETWORK_LINE__
__ROOT_LINE__
user --name=__LAB_USER__ --shell=__LOGIN_SHELL__ --groups=wheel --password=@@VBOX_INSERT_USER_PASSWORD_SH@@ --plaintext
__EXTRA_USER_LINES__
# KS 4 - Services et protections du serveur.
firewall --enabled --service=ssh
selinux --enforcing
services --enabled=sshd,NetworkManager,firewalld
firstboot --disable
skipx
# KS 5 - Partitionner seulement le disque neuf de cette VM.
ignoredisk --only-use=sda
zerombr
clearpart --all --initlabel --drives=sda
bootloader --location=mbr --boot-drive=sda
autopart --type=lvm
reboot --eject

# KS 6 - Paquets disponibles sur le media minimal, communs aux deux roles.
%packages
@core
openssh-server
sudo
python3
NetworkManager
firewalld
%end

# KS 7 - Preparer les fichiers dans le systeme installe (chroot Anaconda).
%post --erroronfail --log=/root/ks-post.log
set -eu
install -d -m 0755 /etc/ssh/sshd_config.d
# La politique SSH est generee selon le choix explicite fait sur Windows.
cat > /etc/ssh/sshd_config.d/00-lab-root.conf <<'SSH_CONFIG'
# Politique du lab : mot de passe root et SSH root sont configures separement.
__SSH_POLICY__
SSH_CONFIG
chmod 0600 /etc/ssh/sshd_config.d/00-lab-root.conf
install -d -m 0755 /var/lib/lab-bootstrap
printf '%s\n' 'BOOTSTRAP_PENDING' > /var/lib/lab-bootstrap/status
# Autoriser sudo avec le mot de passe du compte choisi ; valider avant le premier boot.
cat > /etc/sudoers.d/ansible-lab <<'SUDOEOF'
# Administration du lab : authentification par le mot de passe utilisateur.
__LAB_USER__ ALL=(ALL) ALL
__EXTRA_SUDO_LINES__
SUDOEOF
chmod 0440 /etc/sudoers.d/ansible-lab
visudo -cf /etc/sudoers.d/ansible-lab

# KS 8 - Preparation en deux phases, avec mise a jour puis redemarrage automatique.
cat > /usr/local/sbin/lab-bootstrap <<'BOOTSTRAP'
#!/bin/bash
# Journaliser l execution, signaler les erreurs et publier un statut lisible.
set -Eeuo pipefail
exec > >(tee -a /var/log/lab-bootstrap.log) 2>&1
lab_stage='Initialisation du bootstrap'
# EXIT couvre aussi les sorties explicites ; journaliser l etape et le code retour.
# LINENO dans ce trap ne designe pas toujours la ligne fautive : ne pas l afficher.
trap 'lab_rc=$?; if [ "$lab_rc" -ne 0 ]; then echo BOOTSTRAP_FAILED > /var/lib/lab-bootstrap/status; echo "Bootstrap failed: stage=$lab_stage exit=$lab_rc; see /var/log/lab-bootstrap.log"; fi' EXIT
echo BOOTSTRAP_RUNNING > /var/lib/lab-bootstrap/status
# PHASE 1 - Mise a jour complete avant compilation des modules VirtualBox.
# Le marqueur n est ecrit qu apres toutes les transactions et le choix du noyau.
# Un redemarrage systematique applique aussi les mises a jour systemd/glibc.
lab_stage='Mise a jour AlmaLinux, EPEL et outils'
if [ ! -f /var/lib/lab-bootstrap/updated-boot-id ]; then
    echo BOOTSTRAP_UPDATING > /var/lib/lab-bootstrap/status
    dnf -y --setopt=timeout=30 --setopt=retries=2 install dnf-plugins-core
    dnf config-manager --set-enabled crb
    dnf -y --setopt=timeout=30 --setopt=retries=2 install epel-release
    dnf -y --refresh --setopt=timeout=30 --setopt=retries=2 upgrade
    dnf -y --setopt=timeout=30 --setopt=retries=2 install kernel kernel-devel kernel-headers make gcc perl dkms bzip2 tar gzip xz elfutils-libelf-devel grubby
    if [ '__VM_ROLE__' = 'Controller' ]; then
        dnf -y --setopt=timeout=30 --setopt=retries=2 install ansible-core git python3
    fi
    # Trier les versions fournies par RPM ; ne pas choisir le noyau ISO encore actif.
    lab_kernel=$(rpm -q kernel-core --qf '%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort -V | tail -n 1)
    test -n "$lab_kernel"
    test -f "/boot/vmlinuz-$lab_kernel"
    dnf -y --setopt=timeout=30 --setopt=retries=2 install "kernel-devel-$lab_kernel"
    grubby --set-default "/boot/vmlinuz-$lab_kernel"
    test "$(grubby --default-kernel)" = "/boot/vmlinuz-$lab_kernel"
    printf '%s\n' "$lab_kernel" > /var/lib/lab-bootstrap/expected-kernel
    cat /proc/sys/kernel/random/boot_id > /var/lib/lab-bootstrap/updated-boot-id
fi
# Aucune publication READY ni marqueur done avant le redemarrage effectif.
if [ "$(cat /proc/sys/kernel/random/boot_id)" = "$(cat /var/lib/lab-bootstrap/updated-boot-id)" ]; then
    echo BOOTSTRAP_REBOOT_PENDING > /var/lib/lab-bootstrap/status
    echo 'Mises a jour terminees. Redemarrage automatique, puis reprise de la preparation.'
    systemctl reboot --no-block
    exit 0
fi
# PHASE 2 - Refuser un demarrage sur un ancien noyau au lieu de boucler en reboot.
lab_stage='Verification du noyau apres redemarrage'
lab_expected_kernel=$(cat /var/lib/lab-bootstrap/expected-kernel)
if [ "$(uname -r)" != "$lab_expected_kernel" ]; then
    echo "Noyau attendu: $lab_expected_kernel ; noyau actif: $(uname -r)" >&2
    exit 1
fi
rpm -q "kernel-devel-$(uname -r)"
echo BOOTSTRAP_RUNNING > /var/lib/lab-bootstrap/status
# Archiver le journal du boot ; distinguer erreurs graves et avertissements.
# Un WARNING seul ne prouve ni un echec fonctionnel ni l innocuite du probleme.
# Aucun changement des protections Windows ; la cause reste a diagnostiquer.
lab_check_kernel() {
    lab_stage='Verification des erreurs noyau'
    journalctl -k -b --no-pager > /var/lib/lab-bootstrap/kernel-current-boot.log
    if grep -Eiq 'BUG:|Oops:|kernel panic|general protection fault|unable to handle kernel|soft lockup|hard LOCKUP' /var/lib/lab-bootstrap/kernel-current-boot.log; then
        echo KERNEL_ERROR > /var/lib/lab-bootstrap/kernel-status
        echo 'Erreur noyau grave : /var/lib/lab-bootstrap/kernel-current-boot.log' >&2
        return 1
    fi
    if grep -Eiq 'WARNING:|Call Trace:|rcu.*stall' /var/lib/lab-bootstrap/kernel-current-boot.log; then
        echo KERNEL_WARNINGS > /var/lib/lab-bootstrap/kernel-status
        echo 'AVERTISSEMENT NOYAU : controles fonctionnels poursuivis ; cause non resolue.' >&2
        echo 'Journal : /var/lib/lab-bootstrap/kernel-current-boot.log' >&2
    else
        echo KERNEL_NO_ALERT_DETECTED > /var/lib/lab-bootstrap/kernel-status
    fi
    return 0
}
# Publier le resultat seulement apres tous les tests ; done est ecrit en dernier.
# READY valide la preparation, pas l absence de defaut du noyau ou des pilotes.
# Les statuts sont un instantane de la preparation, pas une surveillance continue.
lab_publish_ready() {
    lab_check_kernel
    if [ "$(cat /var/lib/lab-bootstrap/kernel-status)" = KERNEL_WARNINGS ]; then
        printf '%s\n' 'AVERTISSEMENT NOYAU : VM configuree, diagnostic noyau encore necessaire.' \
            'Journal : /var/lib/lab-bootstrap/kernel-current-boot.log' >> /etc/motd
    fi
    printf '%s\n' "$1" > /var/lib/lab-bootstrap/status
    touch /var/lib/lab-bootstrap/done
    if [ "$(cat /var/lib/lab-bootstrap/kernel-status)" = KERNEL_WARNINGS ]; then
        echo "$1 AVEC AVERTISSEMENTS NOYAU (KERNEL_WARNINGS)"
    else
        echo "$1"
    fi
}
lab_check_kernel
# Verifier la syntaxe SSH et les valeurs effectives avant de declarer la VM prete.
# Cette verification locale ne constitue pas un test de connexion depuis Windows.
lab_stage='Verification SSH'
/usr/sbin/sshd -t
systemctl is-active --quiet sshd
ssh_effective=$(/usr/sbin/sshd -T -C user=root,host=localhost,addr=127.0.0.1)
if [ '__ROOT_SSH_MODE__' = 'Enabled' ]; then
    printf '%s\n' "$ssh_effective" | grep -qx 'permitrootlogin yes'
    printf '%s\n' "$ssh_effective" | grep -qx 'passwordauthentication yes'
else
    printf '%s\n' "$ssh_effective" | grep -Eq '^permitrootlogin (prohibit-password|without-password)$'
fi
__SHARED_FOLDERS_BOOTSTRAP__
lab_check_kernel
# Noeud : verifier les prerequis sans installer le moteur Ansible.
if [ '__VM_ROLE__' = 'Node' ]; then
    lab_stage='Verification du noeud Linux'
    python3 --version
    command -v sudo
    printf '%s\n' 'Linux node ready. User: __LAB_USER__. Address: hostname -I' > /etc/motd
    echo 'SSH et Python verifies. Adresses de la VM :'
    hostname -I
    lab_publish_ready NODE_READY
    exit 0
fi
# Controleur : installer les outils, avec trois tentatives limitees en cas d erreur reseau.
lab_stage='Installation et verification Ansible'
echo 'Installing Ansible Core, Git and Python from AlmaLinux repositories...'
installed=0
for attempt in 1 2 3; do
    if dnf -y --setopt=timeout=30 --setopt=retries=2 install ansible-core git python3; then
        installed=1
        break
    fi
    sleep 10
done
test "$installed" -eq 1
install -d -o __LAB_USER__ -g __LAB_USER__ -m 0750 /home/__LAB_USER__/lab
# Inventaire de demonstration : seule cette VM est ciblee, en connexion locale.
cat > /home/__LAB_USER__/lab/inventory.ini <<'INVENTORY'
# Ajouter les autres machines dans un groupe distinct apres avoir prepare leurs acces SSH.
[controller]
localhost ansible_connection=local ansible_python_interpreter=/usr/bin/python3
INVENTORY
# Configuration Ansible locale au projet ; verifier les cles des futurs serveurs SSH.
cat > /home/__LAB_USER__/lab/ansible.cfg <<'CONFIG'
# Lancer les commandes depuis ce dossier pour charger cet inventaire relatif.
[defaults]
inventory = ./inventory.ini
host_key_checking = True
CONFIG
# Playbook de validation local : aucune connexion a une autre VM.
cat > /home/__LAB_USER__/lab/test.yml <<'PLAYBOOK'
---
# ansible.builtin.ping valide Python et Ansible ; ce n est pas un ping ICMP.
- name: Verify the Ansible controller
  hosts: controller
  gather_facts: false
  tasks:
    - name: Verify Python and local execution
      ansible.builtin.ping:
PLAYBOOK
chown __LAB_USER__:__LAB_USER__ /home/__LAB_USER__/lab/*
runuser -u __LAB_USER__ -- bash -c 'cd /home/__LAB_USER__/lab && ansible-playbook test.yml'
ansible --version
# Preparer le message de connexion ; lab_publish_ready effectue le controle noyau final.
cat > /etc/motd <<'MOTD'
Ansible controller ready. Test: cd ~/lab && ansible-playbook test.yml
IP address: hostname -I
Bootstrap log: sudo journalctl -u lab-bootstrap
MOTD
echo 'Test Ansible reussi. Compte SSH : __LAB_USER__. Adresses de la VM :'
hostname -I
lab_publish_ready ANSIBLE_READY
BOOTSTRAP
chmod 0750 /usr/local/sbin/lab-bootstrap
# KS 9 - Attendre le reseau et SSH ; ne pas recommencer apres un succes.
cat > /etc/systemd/system/lab-bootstrap.service <<'SERVICE'
# Service en deux phases : done est cree par le script apres les controles finaux.
[Unit]
Description=Prepare the Linux lab VM
Wants=network-online.target sshd.service
After=network-online.target sshd.service
ConditionPathExists=!/var/lib/lab-bootstrap/done

# Limiter la duree, conserver les journaux et ne pas masquer un echec.
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/lab-bootstrap
TimeoutStartSec=7200
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console

# Activation au demarrage en mode serveur, sans interface graphique.
[Install]
WantedBy=multi-user.target
SERVICE
systemctl enable lab-bootstrap.service
systemctl set-default multi-user.target
# Restaurer les contextes SELinux des fichiers crees par le script.
restorecon -RF /usr/local/sbin /etc/systemd/system /etc/sudoers.d /etc/ssh /var/lib/lab-bootstrap
%end
'@
    $rootLine = 'rootpw --lock'
    if ($RootMode -eq 'Enabled') { $rootLine = 'rootpw --plaintext @@VBOX_INSERT_ROOT_PASSWORD_SH@@' }
    # Le mode refuse ne bloque pas les cles root ; il bloque le mot de passe et le clavier interactif.
    $sshPolicy = 'PermitRootLogin prohibit-password'
    if ($RootSshMode -eq 'Enabled') { $sshPolicy = "PermitRootLogin yes`nPasswordAuthentication yes" }
    $template += "`n" + (Get-GuestAdditionsCopyPost $Shares)
    # Inserer les comptes supplementaires en dernier : ne pas substituer de texte dans leurs secrets.
    $template = $template.Replace('__SHARED_FOLDERS_BOOTSTRAP__', (Get-SharedFoldersBootstrap $Shares))
    $template = $template.Replace('__LOGIN_SHELL__', $UserShell)
    $template = $template.Replace('__SSH_POLICY__', $sshPolicy)
    $template = $template.Replace('__ROOT_SSH_MODE__', $RootSshMode)
    $template = $template.Replace('__NETWORK_LINE__', $NetworkLine)
    $template = $template.Replace('__ROOT_LINE__', $rootLine)
    $template = $template.Replace('__LAB_USER__', $UserName)
    $template = $template.Replace('__VM_ROLE__', $Role)
    $template = $template.Replace('__EXTRA_SUDO_LINES__', $extraConfig.Sudo)
    return $template.Replace('__EXTRA_USER_LINES__', $extraConfig.Users)
}
# Construire des noms uniques pour le lot, sans modifier les VMs existantes.
function Get-BatchNames {
    param([string]$FirstName,[int]$Count)
    $match = [regex]::Match($FirstName, '^(.*?)([0-9]+)$')
    if ($match.Success) {
        $prefix = $match.Groups[1].Value
        [long]$start = 0
        if (-not [long]::TryParse($match.Groups[2].Value, [ref]$start) -or $start -gt ([long]::MaxValue - $Count)) {
            throw 'Suffixe numerique trop grand pour le nom de VM.'
        }
        $width = $match.Groups[2].Value.Length
    } else { $prefix = $FirstName; [long]$start = 1; $width = 2 }
    for ($i = 0; $i -lt $Count; $i++) {
        $name = $prefix + ($start + $i).ToString("D$width")
        if ($name -cnotmatch '^[a-z][a-z0-9-]{0,30}$') { throw "Nom genere invalide : $name" }
        $name
    }
}

# Le premier nom a deja ete choisi ; demander les suivants avec une proposition.
# Conserver l ordre de saisie pour l association des adresses IP du lot.
function Read-BatchNames {
    param([string]$FirstName,[int]$Count)
    $suggested = @(Get-BatchNames $FirstName $Count)
    $chosen = @($FirstName)
    for ($i = 1; $i -lt $Count; $i++) {
        while ($true) {
            $candidate = Read-Default "Nom VirtualBox de la VM $($i + 1)/$Count" $suggested[$i]
            if ($candidate -cnotmatch '^[a-z][a-z0-9-]{0,30}$') {
                Write-Host '  Nom invalide : minuscules, chiffres et tirets ; commencer par une lettre.' -ForegroundColor Yellow
                continue
            }
            if ($candidate -in $chosen) {
                Write-Host '  Ce nom est deja utilise dans ce lot. Choisir un autre nom.' -ForegroundColor Yellow
                continue
            }
            $chosen += $candidate
            break
        }
    }
    return $chosen
}

# Preparer les arguments de chaque VM ; ne jamais recopier une seule IP sur tout le lot.
function Get-BatchArguments {
    param([hashtable]$Common,[string[]]$Names,[string[]]$Addresses)
    if ($Common.ContainsKey('IpAddress')) {
        throw 'Pour plusieurs VMs, utiliser -IpAddresses (une IP par VM), pas -IpAddress.'
    }
    if ($Common.ContainsKey('HostName') -and $Common.HostName -notlike '*{vm}*') {
        throw 'Pour un lot, -HostName doit contenir {vm}, par exemple {vm}.lab.test.'
    }
    if ($Common.NetworkMode -eq 'Static') {
        if ($Addresses.Count -ne $Names.Count) { throw 'Fournir exactement une adresse IPv4 par VM.' }
        if (@($Addresses | Select-Object -Unique).Count -ne $Names.Count) { throw 'Les adresses du lot doivent etre distinctes.' }
        foreach ($address in $Addresses) { $null = Convert-IPv4Number $address }
    } elseif ($Addresses.Count -gt 0) { throw 'Ne pas fournir IpAddresses avec DHCP.' }
    for ($i = 0; $i -lt $Names.Count; $i++) {
        $child = $Common.Clone()
        $child.Remove('IpAddresses')
        $child.VmCount = 1
        $child.VmName = $Names[$i]
        # Ne pas injecter un hostname par defaut : l enfant doit poser la question.
        # Un modele explicite reste prioritaire et remplace {vm} par le nom choisi.
        if ($Common.ContainsKey('HostName')) {
            $child.HostName = $Common.HostName.Replace('{vm}', $Names[$i])
        }
        if ($Common.NetworkMode -eq 'Static') { $child.IpAddress = $Addresses[$i] }
        Write-Output -NoEnumerate $child
    }
}

# ETAPE 2 - Recueillir et valider les choix non fournis en arguments.
if ($env:OS -ne 'Windows_NT') { throw 'Run this script on your Windows VirtualBox host.' }

# Questions initiales seulement si absentes ; les enfants recoivent ces deux arguments.
if (-not $PSBoundParameters.ContainsKey('VmCount') -or -not $PSBoundParameters.ContainsKey('VmName')) {
    Write-LabBanner 'LAB ALMALINUX | NOUVEAU DEPLOIEMENT' 'Nombre et nom des machines'
}
if (-not $PSBoundParameters.ContainsKey('VmCount')) {
    $VmCount = Read-IntegerChoice 'Nombre de VMs a creer' 1 1 16
}
if (-not $PSBoundParameters.ContainsKey('VmName')) {
    Write-LabSection 'NOMS DES MACHINES'
    $label = if ($VmCount -gt 1) { "Nom VirtualBox de la VM 1/$VmCount" } else { 'Nom VirtualBox de la VM' }
    while ($true) {
        $VmName = Read-Default $label 'ansible01'
        if ($VmName -cmatch '^[a-z][a-z0-9-]{0,30}$') { break }
        Write-Host '  Utiliser 1 a 31 caracteres : minuscules, chiffres et tirets ; commencer par une lettre.' -ForegroundColor Yellow
    }
}

# ETAPE 2a - Lot : lancer les preparations successivement, sans attendre la fin des OS.
# Les installations deja lancees continuent en parallele dans VirtualBox.
# Les arguments fournis sont communs au lot, y compris les secrets explicites.
# Les secrets absents sont demandes separement dans chaque VM.
if ($VmCount -gt 1) {
    # VmName explicite conserve le mode numerote pour les commandes parametrees.
    # Sans cet argument, chacun des noms suivants est propose puis modifiable.
    $names = if ($PSBoundParameters.ContainsKey('VmName')) {
        @(Get-BatchNames $VmName $VmCount)
    } else { @(Read-BatchNames $VmName $VmCount) }
    Write-LabBanner "LAB ALMALINUX | LOT DE $VmCount VMs" 'Configuration reseau commune'
    Write-Host "Ordre des VMs pour les adresses IP : $($names -join ', ')" -ForegroundColor Cyan
    if (-not $NetworkMode) { $NetworkMode = Read-Default 'Reseau IPv4 du lot : Dhcp ou Static' 'Dhcp' }
    if ($NetworkMode -notin @('Dhcp','Static')) { throw 'Mode reseau attendu : Dhcp ou Static.' }
    if ($NetworkMode -eq 'Static' -and -not $IpAddresses) {
        $IpAddresses = Read-Host "Les $VmCount adresses IPv4, dans l ordre, separees par des virgules"
    }
    $addresses = @()
    if ($IpAddresses) { $addresses = @($IpAddresses.Split(',') | ForEach-Object { $_.Trim() }) }
    $common = @{}
    foreach ($key in $PSBoundParameters.Keys) { $common[$key] = $PSBoundParameters[$key] }
    $common.NetworkMode = $NetworkMode
    $plans = @(Get-BatchArguments $common $names $addresses)
    Write-Host "VMs du lot : $($names -join ', ')"
    Write-Host 'Les arguments fournis sont communs ; les choix manquants seront demandes pour chaque VM.'
    $completed = New-Object 'System.Collections.Generic.List[string]'
    $position = 0
    foreach ($plan in $plans) {
        $position++
        # Le bandeau sera affiche par l enfant avant sa premiere question.
        $plan.DisplayIndex = $position
        $plan.DisplayTotal = $plans.Count
        try {
            & $PSCommandPath @plan
            $completed.Add([string]$plan.VmName)
        } catch {
            Write-Warning "Lot interrompu sur $($plan.VmName). VMs deja traitees : $($completed -join ', '). Aucune suppression automatique."
            throw
        }
    }
    Write-LabBanner 'BILAN DU LOT' "$($completed.Count) / $($plans.Count) VMs traitees"
    foreach ($name in $completed) {
        $state = if ($CheckOnly) { 'VERIFICATION OK - aucune creation' } else { 'LANCEMENT OK - disponibilite a verifier dans Linux' }
        Write-LabField $name $state
    }
    if (-not $CheckOnly) {
        Write-Host '  Attendre ANSIBLE_READY ou NODE_READY dans CHAQUE VM.' -ForegroundColor Yellow
        Write-Host '  Commande Linux : cat /var/lib/lab-bootstrap/status'
    }
    return
}
if ($IpAddresses) { throw 'IpAddresses est reserve aux lots ; utiliser IpAddress pour une seule VM.' }

Write-LabBanner "VM $DisplayIndex/$DisplayTotal | $VmName" 'AlmaLinux 9 | Configuration et lancement'
Write-Host '  Entree conserve la valeur entre crochets. Les arguments fournis sont repris.' -ForegroundColor Gray
Write-LabSection '1/9 | RESSOURCES - CPU, RAM, DISQUE'
# Ressources interactives : ContainsKey distingue un argument fourni d une valeur par defaut.
# Ainsi, -CpuCount 2 ne repose pas la question, meme si 2 est aussi la valeur proposee.
if (-not $PSBoundParameters.ContainsKey('CpuCount')) {
    $CpuCount = Read-IntegerChoice 'Nombre de CPU virtuels' 2 1 16
}
if (-not $PSBoundParameters.ContainsKey('MemoryMB')) {
    $MemoryMB = Read-IntegerChoice 'RAM en Mo (2048 = 2 Go, 4096 = 4 Go)' 2048 2048 32768
}
if (-not $PSBoundParameters.ContainsKey('DiskGB')) {
    $DiskGB = Read-IntegerChoice 'Capacite du disque dynamique en Go' 30 20 500
}

Write-LabSection '2/9 | IDENTITE - HOSTNAME, UTILISATEUR, SHELL, ROLE'
if (-not $HostName) { $HostName = Read-Default 'Hostname Linux (court ou FQDN)' "$VmName.lab.test" }
if ($HostName.Length -gt 253) { throw 'Hostname trop long.' }
foreach ($label in $HostName.Split('.')) {
    if ($label -cnotmatch '^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$') {
        throw 'Hostname invalide : lettres minuscules, chiffres et tirets ; labels de 1 a 63 caracteres.'
    }
}
if ($HostName -match '^\d+(\.\d+)*$' -or $HostName -eq 'localhost') { throw 'Choisir un hostname autre qu une adresse IP ou localhost.' }
# VirtualBox exige un FQDN technique ; Linux recevra exactement le hostname demande.
$VBoxHostName = $HostName
if (-not $HostName.Contains('.')) { $VBoxHostName = "$HostName.lab.test" }
# Proposer le nom VirtualBox propre a cette VM ; Entree accepte, une saisie le remplace.
# Un argument LinuxUser explicite garde la priorite. Les noms reserves restent refuses.
if (-not $LinuxUser) { $LinuxUser = Read-Default 'Compte utilisateur Linux principal' $VmName }
Assert-LabUserName $LinuxUser
# Le shell est applique au compte utilisateur ; le shell root reste celui de la distribution.
if (-not $LoginShell) { $LoginShell = Read-Default 'Shell utilisateur : /bin/bash ou /bin/sh' '/bin/bash' }
if ($LoginShell -notin @('/bin/bash','/bin/sh')) { throw 'Shell pris en charge : /bin/bash ou /bin/sh.' }
$LoginShell = $LoginShell.ToLowerInvariant()
if (-not $VmRole) { $VmRole = Read-Default 'Role : Controller (Ansible) ou Node (Linux cible)' 'Controller' }
if ($VmRole -notin @('Controller','Node')) { throw 'Role attendu : Controller ou Node.' }
$VmRole = if ($VmRole -eq 'Node') { 'Node' } else { 'Controller' }
# Compte principal : sudo conserve ; les comptes supplementaires ont un choix individuel.
if ($PSBoundParameters.ContainsKey('AdditionalUsersJson')) {
    $additionalUsers = @(Get-ConfiguredUsers $AdditionalUsersJson $LinuxUser)
    if ($AdditionalUserCount -ge 0 -and $AdditionalUserCount -ne $additionalUsers.Count) {
        throw 'AdditionalUserCount ne correspond pas au nombre de comptes JSON.'
    }
} else {
    if ($AdditionalUserCount -lt 0) {
        $AdditionalUserCount = Read-IntegerChoice 'Nombre de comptes supplementaires (hors compte principal et root)' 0 0 10
    }
    $additionalUsers = @(Read-AdditionalUsers $LinuxUser $AdditionalUserCount)
}
Write-LabSection '3/9 | ACCES - ROOT ET SSH'
if (-not $RootAccess) {
    $answer = Read-Default 'Activer le mot de passe root ? o/n' 'n'
    if ($answer -in @('o','oui','y','yes')) { $RootAccess = 'Enabled' }
    elseif ($answer -in @('n','non','no')) { $RootAccess = 'Disabled' }
    else { throw 'Reponse attendue : o ou n.' }
}
# Le mot de passe root n implique pas automatiquement son ouverture sur SSH.
if (-not $RootSshPassword) {
    if ($RootAccess -eq 'Enabled') {
        $answer = Read-Default 'Autoriser root par mot de passe en SSH ? o/n' 'n'
        if ($answer -in @('o','oui','y','yes')) { $RootSshPassword = 'Enabled' }
        elseif ($answer -in @('n','non','no')) { $RootSshPassword = 'Disabled' }
        else { throw 'Reponse attendue : o ou n.' }
    } else { $RootSshPassword = 'Disabled' }
}
Assert-RootSettings $RootAccess $RootSshPassword
# Verifier aussi les arguments secrets en CheckOnly, sans les afficher.
if ($PSBoundParameters.ContainsKey('UserPassword')) { Assert-LabPassword $UserPassword }
if ($PSBoundParameters.ContainsKey('RootPassword')) {
    if ($RootAccess -ne 'Enabled') { throw 'RootPassword exige RootAccess Enabled.' }
    Assert-LabPassword $RootPassword
}
# Normaliser la casse avant de transmettre ce choix aux scripts shell sensibles a la casse.
$RootSshPassword = if ($RootSshPassword -eq 'Enabled') { 'Enabled' } else { 'Disabled' }
Write-LabSection '4/9 | RESEAU IPv4'
if (-not $NetworkMode) { $NetworkMode = Read-Default 'Reseau IPv4 : Dhcp ou Static' 'Dhcp' }
if ($NetworkMode -notin @('Dhcp','Static')) { throw 'Mode reseau attendu : Dhcp ou Static.' }
if ($NetworkMode -eq 'Static') {
    if (-not $IpAddress) { $IpAddress = Read-Host 'Adresse IPv4 de la VM' }
    # Propositions propres au lab : Entree les conserve ; toute autre saisie les remplace.
    # Appliquer ces valeurs uniquement en mode statique, jamais aux parametres DHCP.
    # Les arguments deja fournis restent prioritaires. Le prefixe invalide est redemande.
    if (-not $PrefixLength) { $PrefixLength = Read-IntegerChoice 'Prefixe IPv4 (24 = 255.255.255.0)' 24 1 30 }
    if (-not $Gateway) { $Gateway = Read-Default 'Passerelle IPv4' '192.168.1.254' }
    if (-not $DnsServers) { $DnsServers = Read-Default 'DNS IPv4, separes par des virgules' '192.168.1.254' }
    $static = Get-StaticNetwork $IpAddress $PrefixLength $Gateway $DnsServers
    $networkLine = "network --bootproto=static --ip=$IpAddress --netmask=$($static.Netmask) --gateway=$Gateway --nameserver=$($static.Dns) --device=link --activate --onboot=yes --hostname=$HostName --noipv6"
} else {
    if ($IpAddress -or $Gateway -or $DnsServers -or $PrefixLength) { throw 'Parametres statiques fournis avec le mode DHCP.' }
    $networkLine = "network --bootproto=dhcp --device=link --activate --onboot=yes --hostname=$HostName"
}

Write-LabSection '5/9 | DOSSIERS PARTAGES WINDOWS / LINUX'
$shares = @()
if ($SharedFoldersFile -and $SharedFoldersMode -eq 'Disabled') {
    throw 'SharedFoldersFile est incompatible avec SharedFoldersMode Disabled.'
}
if (-not $SharedFoldersMode) {
    if ($SharedFoldersFile -or (Read-LabYesNo 'Ajouter des dossiers partages ?')) { $SharedFoldersMode = 'Enabled' }
    else { $SharedFoldersMode = 'Disabled' }
}
if ($SharedFoldersMode -eq 'Enabled') {
    if ($SharedFoldersFile) {
        # JSON PARTAGES - Une propriete objet preserve le tableau sous PowerShell 5.1/7.
        # Accepter aussi l objet unique produit par certains anciens lanceurs.
        $sharesJson = Get-Content -LiteralPath $SharedFoldersFile -Raw
        try {
            $sharesDocument = ConvertFrom-Json -InputObject ('{"Shares":' + $sharesJson + '}')
        } catch { throw 'Le fichier des partages ne contient pas un JSON valide.' }
        $items = @($sharesDocument.Shares)
        # FIN JSON PARTAGES
    } else {
        $items = @()
        do {
            $path = Read-Host 'Chemin du dossier Windows existant (exemple C:\Lab-Partage)'
            $name = Read-Default 'Nom seul du partage, sans / (exemple : temp -> /mnt/temp)' "partage$($items.Count + 1)"
            $readOnly = Read-LabYesNo 'Lecture seule ?' 'o'
            $items += [pscustomobject]@{Name=$name;HostPath=$path;ReadOnly=$readOnly}
        } while (Read-LabYesNo 'Ajouter un autre dossier ?')
    }
    if ($items.Count -eq 0) { throw 'Au moins un dossier est requis lorsque les partages sont actives.' }
    $shares = @(Get-ValidatedShares $items)
    Write-Host '  Les Guest Additions seront installees ; acces aux depots AlmaLinux requis.' -ForegroundColor Yellow
}

Write-LabSection '6/9 | VERIFICATIONS - ISO, VIRTUALBOX, PONT, VM'
# ETAPE 3 - Verifier le media et trouver VirtualBox (PowerShell 32 ou 64 bits).
if (-not (Test-Path -LiteralPath $IsoPath -PathType Leaf)) { throw "ISO not found: $IsoPath" }
$IsoPath = (Resolve-Path -LiteralPath $IsoPath).ProviderPath
if ([IO.Path]::GetExtension($IsoPath) -ne '.iso') { throw 'Select a completed .iso download.' }
if (-not $VBoxManagePath) {
    $candidates = @(
        "${env:ProgramW6432}\Oracle\VirtualBox\VBoxManage.exe"
        "${env:ProgramFiles}\Oracle\VirtualBox\VBoxManage.exe"
        "${env:ProgramFiles(x86)}\Oracle\VirtualBox\VBoxManage.exe"
    )
    $VBoxManagePath = $candidates | Select-Object -Unique |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $VBoxManagePath) {
        $command = Get-Command VBoxManage.exe -ErrorAction SilentlyContinue
        if ($command) { $VBoxManagePath = $command.Source }
    }
}
if (-not $VBoxManagePath -or -not (Test-Path -LiteralPath $VBoxManagePath -PathType Leaf)) {
    throw 'VirtualBox not found. Supply -VBoxManagePath with its full executable path.'
}
# L ISO fournie par la meme installation VirtualBox est utilisee pour les Additions.
if ($shares.Count -gt 0) {
    if (-not $GuestAdditionsIsoPath) {
        $GuestAdditionsIsoPath = Join-Path (Split-Path -Parent $VBoxManagePath) 'VBoxGuestAdditions.iso'
    }
    if (-not (Test-Path -LiteralPath $GuestAdditionsIsoPath -PathType Leaf)) {
        throw "ISO Guest Additions introuvable : $GuestAdditionsIsoPath"
    }
    $GuestAdditionsIsoPath = (Resolve-Path -LiteralPath $GuestAdditionsIsoPath).ProviderPath
}
$version = (Invoke-VBox @('--version')) -join ''
Write-Host "VirtualBox: $version"
if ($version -notmatch '^7\.2\.') { throw 'This script targets VirtualBox 7.2.x.' }

# ETAPE 4 - Relier les GUID Windows aux cartes de pont proposees par VirtualBox.
# Ne retenir que les cartes physiques connectees avec une IPv4 et une route par defaut.
$bridgeText = (Invoke-VBox @('list','bridgedifs')) -join "`n"
$bridges = @(
    foreach ($block in ($bridgeText -split '(?:\r?\n){2,}')) {
        $n = [regex]::Match($block, '(?m)^Name:\s*(.+)$')
        $g = [regex]::Match($block, '(?m)^GUID:\s*\{?([a-fA-F0-9-]+)\}?\s*$')
        if ($n.Success -and $g.Success) {
            [pscustomobject]@{ Name=$n.Groups[1].Value.Trim(); Guid=$g.Groups[1].Value.ToLowerInvariant() }
        }
    }
)
$adapters = @(Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' })
# Construire la liste des candidats : Ethernet avant Wi-Fi, puis metrique de routage.
$eligible = @(
    foreach ($adapter in $adapters) {
        $guid = ([string]$adapter.InterfaceGuid).Trim('{}').ToLowerInvariant()
        $bridge = $bridges | Where-Object { $_.Guid -eq $guid } | Select-Object -First 1
        if (-not $bridge) { continue }
        $routes = @(Get-NetRoute -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 `
            -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
            Where-Object { $_.NextHop -ne '0.0.0.0' })
        # Nom distinct du parametre string IpAddresses : PowerShell ignore la casse.
        # Conserver une collection d objets reseau pour le controle Count.
        $adapterIPv4Addresses = @(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 `
            -ErrorAction SilentlyContinue | Where-Object {
                $_.AddressState -eq 'Preferred' -and $_.IPAddress -notlike '169.254.*'
            })
        if ($routes.Count -eq 0 -or $adapterIPv4Addresses.Count -eq 0) { continue }
        $ipInterface = Get-NetIPInterface -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 |
            Select-Object -First 1
        $routeMetric = ($routes | Measure-Object -Property RouteMetric -Minimum).Minimum
        $metric = [long]$routeMetric + [long]$ipInterface.InterfaceMetric
        $medium = [int]$adapter.NdisPhysicalMedium
        $interfaceType = [int]$adapter.InterfaceType
        if ($medium -in @(1,9) -or $interfaceType -eq 71) {
            $rank = 1; $kind = 'Wi-Fi'
        } elseif ($medium -eq 14 -or $interfaceType -eq 6) {
            $rank = 0; $kind = 'Ethernet'
        } else { continue }
        [pscustomobject]@{
            Name=$adapter.Name; VBoxName=$bridge.Name; Kind=$kind
            Rank=$rank; Metric=$metric; Index=$adapter.ifIndex
        }
    }
)
if ($BridgeAdapter) {
    $matchingBridges = @($eligible | Where-Object { $_.Name -eq $BridgeAdapter -or $_.VBoxName -eq $BridgeAdapter })
    if ($matchingBridges.Count -ne 1) {
        throw 'The requested bridge is not a unique connected physical IPv4 adapter with a default route.'
    }
    $selected = $matchingBridges[0]
} else {
    $selected = $eligible | Sort-Object Rank,Metric,Index | Select-Object -First 1
}
if (-not $selected) {
    throw 'No eligible Ethernet/Wi-Fi bridge. Check the physical IPv4 connection, default route and VirtualBox bridge driver.'
}
Write-Host "Bridge selected: $($selected.Kind) / $($selected.Name) / $($selected.VBoxName)"

# ETAPE 5 - Refuser toute VM avec stockage ou instantane ; ne jamais ecraser un disque.
$vms = Invoke-VBox @('list','vms')
$exists = @($vms | Where-Object { $_ -match ('^"' + [regex]::Escape($VmName) + '"\s') }).Count -gt 0
if ($exists) {
    $info = (Invoke-VBox @('showvminfo',$VmName,'--machinereadable')) -join "`n"
    if ($info -notmatch '(?m)^VMState="poweroff"$') { throw "VM $VmName must be powered off." }
    $cfgMatch = [regex]::Match($info, '(?m)^CfgFile="(.+)"$')
    if (-not $cfgMatch.Success) { throw 'Cannot identify VM configuration file.' }
    $cfgPath = $cfgMatch.Groups[1].Value.Replace('\\','\')
    [xml]$config = Get-Content -LiteralPath $cfgPath -Raw
    $devices = $config.SelectNodes('//*[local-name()="AttachedDevice"]')
    $snapshots = $config.SelectNodes('//*[local-name()="Snapshot"]')
    $controllers = $config.SelectNodes('//*[local-name()="StorageController"]')
    if ($devices.Count -gt 0 -or $snapshots.Count -gt 0 -or $controllers.Count -gt 0) {
        throw 'Existing VM is not completely empty. No reinstall performed. Use another -VmName.'
    }
    $vmFolder = Split-Path -Parent $cfgPath
    Write-Host "Reusing empty VM: $VmName"
} else {
    # Resoudre les chemins relatifs depuis le dossier PowerShell courant, pas celui du processus .NET.
    $VmBasePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($VmBasePath)
    $vmFolder = Join-Path $VmBasePath $VmName
    if (Test-Path -LiteralPath $vmFolder) { throw "Target directory already exists: $vmFolder" }
}
$diskPath = Join-Path $vmFolder "$VmName.vdi"
$setupFolder = Join-Path $vmFolder 'LabSetup'
if ((Test-Path -LiteralPath $diskPath) -or (Test-Path -LiteralPath $setupFolder)) {
    throw 'Disk or LabSetup already exists. No overwrite attempted. Use another VM name or inspect the previous attempt.'
}
# ETAPE 6 - Afficher le recapitulatif sans secret ; CheckOnly ne demande aucun mot de passe.
# Les secrets deja fournis sont toutefois valides avant ce point.
Write-LabSection '7/9 | RECAPITULATIF'
Write-LabField 'VM' $VmName
Write-LabField 'CPU / RAM / disque' "$CpuCount vCPU / $MemoryMB Mo / $DiskGB Go (dynamique)"
Write-LabField 'Hostname / role' "$HostName / $VmRole"
Write-LabField 'Utilisateur / shell' "$LinuxUser / $LoginShell"
Write-LabField 'Droits sudo' 'Administrateur avec mot de passe utilisateur'
foreach ($account in $additionalUsers) {
    $rights = if ($account.Sudo) { 'sudo avec son mot de passe' } else { 'sans sudo' }
    Write-LabField "Compte $($account.Name)" "$($account.Shell) / $rights"
}
Write-LabField 'Mot de passe root'  $RootAccess
Write-LabField 'SSH root par mdp' $RootSshPassword
Write-LabField 'Pont reseau' "$($selected.Kind) / $($selected.Name)"
Write-LabField 'Mode IPv4' $NetworkMode
if ($NetworkMode -eq 'Static') {
    Write-LabField 'Adresse IPv4' "$IpAddress/$PrefixLength"
    Write-LabField 'Passerelle / DNS' "$Gateway / $($static.Dns)"
}
Write-LabField 'Dossiers partages' ([string]$shares.Count)
foreach ($share in $shares) {
    $access = if ($share.ReadOnly) { 'lecture seule' } else { 'lecture/ecriture' }
    Write-LabField $share.Name "$($share.HostPath) -> /mnt/$($share.Name) ($access)"
}
Write-LabField 'ISO' $IsoPath
Write-LabField 'Dossier VM' $vmFolder
if ($CheckOnly) {
    Write-Host '  [OK] Verification terminee. Aucune creation ; aucun mot de passe demande.' -ForegroundColor Green
    return
}

# ETAPE 7 - Initialiser les secrets de travail et chemins avant leur selection.
$kickstart = $null
$password = $null
$rootPasswordPlain = $null
$passwordPath = $null
$rootPasswordPath = $null

try {
    # Utiliser les secrets fournis ou demander ceux qui manquent avant toute creation.
    Write-LabSection '8/9 | MOTS DE PASSE - SAISIE MASQUEE'
    Write-Host '  Les mots de passe absents des arguments seront demandes avec confirmation.' -ForegroundColor Yellow
    $password = if ($PSBoundParameters.ContainsKey('UserPassword')) { $UserPassword } else { Read-LabPassword $LinuxUser }
    if ($RootAccess -eq 'Enabled') {
        $rootPasswordPlain = if ($PSBoundParameters.ContainsKey('RootPassword')) { $RootPassword } else { Read-LabPassword 'root' }
    }
    foreach ($account in $additionalUsers) {
        if ($null -eq $account.Password) { $account.Password = Read-LabPassword $account.Name }
    }
    # Generer apres la saisie de tous les secrets et avant toute creation VirtualBox.
    $kickstart = Get-LabKickstart $LinuxUser $RootAccess $networkLine $VmRole $RootSshPassword $LoginShell $shares $additionalUsers

    Write-LabSection '9/9 | CREATION ET LANCEMENT'
    Write-Host '  [1/4] Definition de la VM et fichiers de preparation...' -ForegroundColor Gray
    # ETAPE 8 - Creer ou reprendre la definition vide, puis proteger les fichiers de preparation.
    if (-not $exists) {
        Invoke-VBox @('createvm',"--name=$VmName",'--ostype=RedHat_64',"--basefolder=$VmBasePath",'--register') | Out-Null
    }
    New-Item -ItemType Directory -Path $setupFolder | Out-Null
    Protect-Directory $setupFolder
    $ksPath = Join-Path $setupFolder 'almalinux9-ks.cfg'
    $postPath = Join-Path $setupFolder 'unused-vbox-post.sh'
    $passwordPath = Join-Path $setupFolder 'install-password.txt'
    $rootPasswordPath = Join-Path $setupFolder 'root-password.txt'
    Write-LinuxFile $ksPath $kickstart
    $kickstart = $null
    foreach ($account in $additionalUsers) { $account.Password = $null }
    # Le Kickstart contient toutes les actions post-installation. Ce modele neutre
    # evite le bug VirtualBox : GUEST_OS_MAJOR_VERSION refuse la version brute "9".
    Write-LinuxFile $postPath "#!/bin/sh`n# Modele neutre : les actions utiles sont deja dans le Kickstart.`nexit 0`n"
    Write-LinuxFile $passwordPath ($password + "`n")
    $password = $null
    $rootArguments = @()
    if ($RootAccess -eq 'Enabled') {
        Write-LinuxFile $rootPasswordPath ($rootPasswordPlain + "`n")
        $rootPasswordPlain = $null
        $rootArguments = @("--admin-password-file=$rootPasswordPath")
    }
    Write-Host '  [2/4] Materiel virtuel et disque dynamique...' -ForegroundColor Gray
    # ETAPE 9 - Appliquer les ressources, creer le VDI dynamique et attacher les lecteurs.
    Invoke-VBox @('modifyvm',$VmName,"--memory=$MemoryMB","--cpus=$CpuCount",'--ioapic=on',
        '--firmware=bios','--rtc-use-utc=on','--graphicscontroller=vmsvga','--vram=16',
        '--boot1=disk','--boot2=dvd','--boot3=none','--boot4=none',
        '--nic1=bridged',"--bridge-adapter1=$($selected.VBoxName)",'--nic-type1=82540EM',
        '--cable-connected1=on','--nic2=none') | Out-Null
    Invoke-VBox @('createmedium','disk',"--filename=$diskPath",("--size=" + ($DiskGB * 1024)),
        '--format=VDI','--variant=Standard') | Out-Null
    Invoke-VBox @('storagectl',$VmName,'--name=LabSATA','--add=sata','--controller=IntelAhci','--portcount=4','--bootable=on') | Out-Null
    Invoke-VBox @('storageattach',$VmName,'--storagectl=LabSATA','--port=0','--device=0','--type=hdd',"--medium=$diskPath") | Out-Null
    Invoke-VBox @('storageattach',$VmName,'--storagectl=LabSATA','--port=1','--device=0','--type=dvddrive','--medium=emptydrive') | Out-Null
    # Definir les partages permanents avant le demarrage ; montage gere par Linux/fstab.
    foreach ($share in $shares) {
        $shareArgs = @('sharedfolder','add',$VmName,"--name=$($share.Name)","--hostpath=$($share.HostPath)")
        if ($share.ReadOnly) { $shareArgs += '--readonly' }
        Invoke-VBox $shareArgs | Out-Null
    }
    # ETAPE 10 - Construire les supports sans demarrer ; retirer les secrets temporaires.
    Write-Host '  [3/4] Construction des supports AlmaLinux automatiques...' -ForegroundColor Gray
    try {
        $installArguments = @('unattended','install',$VmName,"--iso=$IsoPath","--user=$LinuxUser",
            "--user-password-file=$passwordPath","--hostname=$VBoxHostName",'--locale=en_US',
            '--country=FR','--time-zone=Europe/Paris','--no-install-additions','--no-install-txs',
            '--package-selection-adjustment=minimal',"--script-template=$ksPath",
            "--post-install-template=$postPath",
            "--auxiliary-base-path=$(Join-Path $setupFolder 'Unattended-')",
            '--extra-install-kernel-parameters=inst.ks=cdrom:/ks.cfg', '--start-vm=none') + $rootArguments
        Invoke-VBox $installArguments | Out-Null
    } finally {
        Remove-SecretFile $passwordPath
        Remove-SecretFile $rootPasswordPath
    }
    # Attacher APRES unattended : sa preparation peut retirer ou remplacer les DVD.
    # La VM est encore arretee (--start-vm=none). Ne toucher a aucun media occupe.
    if ($shares.Count -gt 0) {
        $preparedInfo = (Invoke-VBox @('showvminfo',$VmName,'--machinereadable')) -join "`n"
        $additionsPort = Get-FreeLabDvdPort $preparedInfo
        Invoke-VBox @('storageattach',$VmName,'--storagectl=LabSATA',"--port=$additionsPort",'--device=0',
            '--type=dvddrive',"--medium=$GuestAdditionsIsoPath") | Out-Null
        $attachedInfo = (Invoke-VBox @('showvminfo',$VmName,'--machinereadable')) -join "`n"
        $attached = [regex]::Match($attachedInfo, ('(?m)^"LabSATA-' + $additionsPort + '-0"="(.+)"\r?$'))
        if (-not $attached.Success -or $attached.Groups[1].Value.Replace('\\','\') -ne $GuestAdditionsIsoPath) {
            throw 'Le CD Guest Additions n est pas confirme dans la configuration ; demarrage annule.'
        }
        Write-Host "  [OK] CD Guest Additions attache et verifie (port $additionsPort)." -ForegroundColor Green
    }
    Write-Host '  [4/4] Demarrage de la VM dans VirtualBox...' -ForegroundColor Gray
    # ETAPE 11 - Demarrer : disque vierge vers DVD, puis OS installe apres redemarrage.
    Invoke-VBox @('modifyvm',$VmName,'--boot1=disk','--boot2=dvd','--boot3=none','--boot4=none') | Out-Null
    Invoke-VBox @('startvm',$VmName,'--type=gui') | Out-Null
    Write-Host ''
    Write-LabBanner "VM $DisplayIndex/$DisplayTotal | $VmName | INSTALLATION LANCEE" 'Linux poursuit son installation dans VirtualBox.'
    Write-Host '  [A VERIFIER] La VM n est pas encore confirmee prete.' -ForegroundColor Yellow
    Write-Host "  Apres redemarrage, se connecter avec : $LinuxUser"
    Write-Host '  Mise a jour complete + EPEL/outils ; redemarrage automatique avant les Additions.'
    Write-Host '  Statut Linux : cat /var/lib/lab-bootstrap/status'
    if ($VmRole -eq 'Controller') {
        Write-Host '  Attendu : ANSIBLE_READY | Test : cd ~/lab && ansible-playbook test.yml'
    } else { Write-Host '  Attendu : NODE_READY | Ajout a l inventaire Ansible a effectuer ensuite.' }
    Write-Host '  Etat noyau : cat /var/lib/lab-bootstrap/kernel-status'
    Write-Host '  KERNEL_WARNINGS : VM configuree avec avertissement noyau a diagnostiquer.' -ForegroundColor Yellow
    Write-Host '  Adresse SSH : hostname -I'
    Write-Host "  Supports contenant les secrets : $setupFolder" -ForegroundColor Gray
    Write-Host '  Apres validation, suivre le guide pour retirer les supports et LabSetup.' -ForegroundColor Gray
} catch {
    Write-Host "  [ECHEC] VM $DisplayIndex/$DisplayTotal | $VmName" -ForegroundColor Red
    Write-Warning 'Traitement arrete. Toute VM ou disque deja cree est conserve pour diagnostic.'
    throw
} finally {
    $password = $null
    $rootPasswordPlain = $null
    $kickstart = $null
    foreach ($account in $additionalUsers) { $account.Password = $null }
    # ETAPE 12 - Toujours nettoyer les fichiers de saisie ; les supports generes restent
    # necessaires pendant l installation et doivent etre retires apres validation.
    Remove-SecretFile $passwordPath
    Remove-SecretFile $rootPasswordPath
}
