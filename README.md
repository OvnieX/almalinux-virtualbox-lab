# Lab AlmaLinux / Ansible — version 26

Création automatisée de VM AlmaLinux 9 minimal x86_64 depuis Windows PowerShell
5.1 ou supérieur, avec VirtualBox 7.2.x. Le pack configure Linux, applique les mises
à jour, redémarre puis vérifie le rôle et les partages demandés.

Ce projet cible **VirtualBox uniquement**. Il n'inclut pas de créateur VMware ni
AWX. Le même script accepte les réponses interactives, les paramètres explicites
ou un mélange des deux ; aucun second lanceur n'est nécessaire.

## Sommaire

- [Prérequis](#prérequis)
- [Démarrage simple](#démarrage-simple)
- [Les cinq exemples](#les-cinq-exemples-de-lancement)
- [Paramètres](#paramètres) et [lots](#lots)
- [Réseau et accès](#réseau-et-accès)
- [Partages et Guest Additions](#dossiers-partagés-et-guest-additions)
- [Déroulement Linux](#déroulement-linux)
- [Résultat et journaux](#résultat-et-journaux)
- [Dépannage](#dépannage)
- [Tests](#tests-du-pack)
- [Publication sur GitHub](#publication-sur-github)

## Prérequis

- Hôte Windows avec Windows PowerShell 5.1 et VirtualBox 7.2.x installé.
  PowerShell 7 sous Windows est également ciblé ; voir la portée des tests dans
  [REVUE-CODE.md](REVUE-CODE.md).
- ISO AlmaLinux 9 minimal x86_64 téléchargée séparément. L'ISO n'est pas incluse,
  téléchargée ni recherchée automatiquement par le script. Son existence et son
  extension sont contrôlées, pas sa somme de contrôle.
- Ressources suffisantes pour toutes les VM lancées : CPU, RAM et espace disque.
  Un disque dynamique peut atteindre la capacité configurée.
- Carte Ethernet ou Wi-Fi connectée avec IPv4 et route par défaut ; pilote de pont
  VirtualBox disponible. Autorisation d'utiliser ce réseau pour les VM.
- Accès des VM aux dépôts AlmaLinux et EPEL. Aucun proxy n'est configuré par le pack.
- Pour les partages : dossier Windows existant et `VBoxGuestAdditions.iso` fourni
  avec VirtualBox, ou chemin explicite via `-GuestAdditionsIsoPath`.

Les exemples supposent l'ISO dans `C:\Lab-Ansible\ISO` et un partage existant
`C:\Lab-Partage`. Adapter ces chemins à chaque PC. Les adresses `192.168.1.53`
à `.55` sont des exemples à réserver sur un réseau compatible.

## Fichiers du pack

| Fichier | Usage |
|---|---|
| `New-AnsibleLab.ps1` | Création des nouvelles VM et génération de leur installation |
| `Test-LabScript.ps1` | Tests PowerShell sans création ni accès réseau réel |
| `Test-KernelPolicy.py` | Tests Linux/Bash isolés du classement des alertes noyau |
| `README.md` | Utilisation, paramètres, vérifications et limites |
| `REVUE-CODE.md` | Revue et résultats de validation de cette livraison |
| `partages.json` | Exemple de partage temp ; adapter le chemin Windows |
| `.gitignore` | Exclusions des VM, ISO, supports et configurations privées |
| `.gitattributes` | Fins de ligne des fichiers texte du dépôt |

## Démarrage simple

Extraire le pack dans `C:\Lab-Ansible`. Utiliser une console PowerShell classique,
avec le compte Windows qui utilise VirtualBox. Adapter le chemin de l'ISO :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Lab-Ansible\New-AnsibleLab.ps1" -IsoPath "C:\Lab-Ansible\ISO\AlmaLinux-9.8-x86_64-minimal.iso"
```

Le script demande le nombre de VM, puis tous leurs noms dans une même section.
Il propose ensuite les réglages de chaque VM. Entrée accepte la proposition.
Les arguments fournis évitent les questions correspondantes. Les mots de passe absents sont saisis et confirmés au clavier. Ceux fournis
en arguments sont validés et utilisés sans question.
`ExecutionPolicy Bypass` est limité au processus ; il ne contourne pas une stratégie
imposée par l'entreprise.

Pour vérifier les choix sans créer de VM ni saisir de mots de passe, ajouter
`-CheckOnly`. Ce mode ne teste pas l'installation Linux, la disponibilité des dépôts
ou l'absence de conflit d'IP sur le réseau.

## Les cinq exemples de lancement

Les mêmes exemples figurent dans l’aide commentée du script principal.
Les noms et IP doivent être libres ; adapter les chemins et mots de passe fictifs.
Le cinquième exemple est une alternative aux trois créations entièrement paramétrées.

Exemple 1/5 : ouvrir cette session une fois, puis choisir un exemple ci-dessous.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass
```

Exemple 2/5 : creation de ansible (controleur) sans question si tous les arguments sont valides.

```powershell
& 'C:\Lab-Ansible\New-AnsibleLab.ps1' -IsoPath 'C:\Lab-Ansible\ISO\AlmaLinux-9.8-x86_64-minimal.iso' -VmCount 1 -VmName 'ansible' -HostName 'ansible.lab.test' -LinuxUser 'ansible' -UserPassword 'Exemple-Ansible-123!' -LoginShell '/bin/bash' -VmRole Controller -RootAccess Enabled -RootPassword 'Exemple-Root-123!' -RootSshPassword Enabled -CpuCount 2 -MemoryMB 2048 -DiskGB 20 -NetworkMode Static -IpAddress '192.168.1.53' -PrefixLength 24 -Gateway '192.168.1.254' -DnsServers '192.168.1.254' -SharedFoldersMode Enabled -SharedFoldersFile 'C:\Lab-Ansible\partages.json' -AdditionalUsersJson '[]'
```

Exemple 3/5 : creation de uvms (noeud) sans question si tous les arguments sont valides.

```powershell
& 'C:\Lab-Ansible\New-AnsibleLab.ps1' -IsoPath 'C:\Lab-Ansible\ISO\AlmaLinux-9.8-x86_64-minimal.iso' -VmCount 1 -VmName 'uvms' -HostName 'uvms.lab.test' -LinuxUser 'uvms' -UserPassword 'Exemple-Uvms-123!' -LoginShell '/bin/bash' -VmRole Node -RootAccess Enabled -RootPassword 'Exemple-Root-123!' -RootSshPassword Enabled -CpuCount 2 -MemoryMB 2048 -DiskGB 20 -NetworkMode Static -IpAddress '192.168.1.54' -PrefixLength 24 -Gateway '192.168.1.254' -DnsServers '192.168.1.254' -SharedFoldersMode Enabled -SharedFoldersFile 'C:\Lab-Ansible\partages.json' -AdditionalUsersJson '[]'
```

Exemple 4/5 : creation de duas (noeud avec batchlab et sudo) sans question si tous les arguments sont valides.

```powershell
& 'C:\Lab-Ansible\New-AnsibleLab.ps1' -IsoPath 'C:\Lab-Ansible\ISO\AlmaLinux-9.8-x86_64-minimal.iso' -VmCount 1 -VmName 'duas' -HostName 'duas.lab.test' -LinuxUser 'duas' -UserPassword 'Exemple-Duas-123!' -LoginShell '/bin/bash' -VmRole Node -RootAccess Enabled -RootPassword 'Exemple-Root-123!' -RootSshPassword Enabled -CpuCount 2 -MemoryMB 2048 -DiskGB 20 -NetworkMode Static -IpAddress '192.168.1.55' -PrefixLength 24 -Gateway '192.168.1.254' -DnsServers '192.168.1.254' -SharedFoldersMode Enabled -SharedFoldersFile 'C:\Lab-Ansible\partages.json' -AdditionalUsersJson '[{"Name":"batchlab","Shell":"/bin/bash","Sudo":true,"Password":"Exemple-Batch-123!"}]'
```

Exemple 5/5 : lancement interactif, sans parametre de configuration.
PowerShell demande d abord IsoPath, puis le script demande les choix du lab.
Les questions conditionnelles suivent les reponses : IP si Static, mot de passe
root si active, comptes supplementaires et partages si demandes.
Les chemins techniques et la carte de pont conservent leur detection automatique.

```powershell
& 'C:\Lab-Ansible\New-AnsibleLab.ps1'
```

Les secrets littéraux peuvent rester dans l’historique PowerShell. Les omettre
conserve la saisie masquée avec confirmation. Les arguments invalides sont refusés
avant création ; ils ne sont pas remplacés silencieusement par des questions.

`AdditionalUsersJson` attend un tableau de comptes avec Name, Shell et Sudo
(booléen JSON), et Password facultatif. `[]` signifie aucun compte supplémentaire.
Sans Password, seul le mot de passe manquant est demandé. Si AdditionalUserCount
est fourni aussi, il doit correspondre au nombre de comptes. Les doublons et champs
inconnus sont refusés. Sans JSON, les comptes sont demandés au clavier.

Les tableaux de comptes et de partages sont lus comme propriétés JSON pour conserver
leur cardinalité sous PowerShell 5.1 et 7. Pour les partages, un objet unique est
également accepté ; chaque entrée doit contenir Name, HostPath et ReadOnly booléen.

## Choix proposés

- 1 à 16 VM ; première proposition `ansible01`.
- CPU : 2, modifiable de 1 à 16. RAM : 2048 Mo, de 2048 à 32768.
- Disque dynamique : 30 Go, de 20 à 500. Ces limites sont par VM ; le script ne
  réserve pas les ressources et ne vérifie pas la capacité totale disponible.
- Hostname : `<nom-VM>.lab.test`, indépendant du nom VirtualBox.
- Compte principal : nom de la VM, modifiable ; shell `/bin/bash` ou `/bin/sh`.
- Rôle : `Controller` (Ansible) ou `Node` (Linux cible), défaut Controller.
- 0 à 10 comptes supplémentaires : nom, shell, droit sudo et mot de passe individuels.
- Mot de passe root et accès SSH root par mot de passe : désactivés par défaut.
- IPv4 : DHCP par défaut. En statique, préfixe 24 et passerelle/DNS
  `192.168.1.254`, modifiables. Ces valeurs sont des propositions du lab, pas une
  détection automatique du réseau Windows.
- Partages Windows facultatifs ; lecture seule proposée par défaut.

Le compte principal dispose de sudo avec son mot de passe et appartient à wheel.
Les comptes supplémentaires ont sudo seulement si demandé. Les deux règles sudo
(wheel et fichier dédié) peuvent apparaître dans `sudo -l` ; ce n'est pas un échec.
Le shell root n'est pas modifié. Les noms de comptes système connus sont refusés.

## Paramètres

| Paramètre | Signification |
|---|---|
| `-IsoPath` | Chemin obligatoire de l'ISO téléchargée complètement |
| `-VmName` | Nom VirtualBox ou premier nom du lot, défaut `ansible01` |
| `-VmCount` | Nombre demandé si absent : 1 par défaut, de 1 à 16 |
| `-IpAddresses` | Liste IPv4 ordonnée pour un lot statique |
| `-HostName` | Nom Linux court ou FQDN ; indépendant du nom VirtualBox |
| `-UserPassword` | Mot de passe principal ; saisie masquée si absent |
| `-RootPassword` | Mot de passe root ; exige RootAccess Enabled ; saisie si absent |
| `-AdditionalUsersJson` | Tableau JSON de comptes Name, Shell, Sudo, Password facultatif |
| `-LinuxUser` | Compte Linux à créer, avec droits sudo |
| `-AdditionalUserCount` | 0 à 10 comptes supplémentaires par VM ; question si absent |
| `-LoginShell` | `/bin/bash` ou `/bin/sh` ; demandé si absent |
| `-RootAccess Enabled` | Demander et configurer un mot de passe root séparé |
| `-RootAccess Disabled` | Verrouiller le mot de passe root |
| `-RootSshPassword Enabled` | Autoriser root par mot de passe en SSH, exige root activé |
| `-RootSshPassword Disabled` | Interdire le SSH root par mot de passe |
| `-VmRole Controller` | Installer Ansible Core, Git, Python et le playbook de test |
| `-VmRole Node` | Installer Linux avec SSH, Python et sudo, sans installer Ansible |
| `-NetworkMode Dhcp` | IP, passerelle et DNS obtenus automatiquement |
| `-NetworkMode Static` | Configuration IPv4 manuelle complète |
| `-IpAddress` | Adresse IPv4 de la VM en mode statique |
| `-PrefixLength` | Préfixe 1–30 ; proposition interactive 24 |
| `-Gateway` | Passerelle du même sous-réseau ; proposition 192.168.1.254 |
| `-DnsServers` | 1 à 3 DNS IPv4 séparés par des virgules ; proposition 192.168.1.254 |
| `-CpuCount` | CPU virtuels ; si absent, question avec proposition 2 |
| `-MemoryMB` | RAM en Mo ; si absent, question avec proposition 2048 |
| `-DiskGB` | Disque en Go ; si absent, question avec proposition 30 |
| `-VmBasePath` | Dossier des nouvelles VMs, défaut `VirtualBox VMs` dans le profil Windows |
| `-BridgeAdapter` | Facultatif : imposer le nom Windows ou la description VirtualBox d'une carte |
| `-VBoxManagePath` | Facultatif : chemin de l'exécutable en installation non standard |
| `-SharedFoldersMode` | Enabled ou Disabled ; question si absent |
| `-SharedFoldersFile` | Fichier JSON de partages communs au lot |
| `-GuestAdditionsIsoPath` | ISO Additions facultative ; détection près de VBoxManage |
| `-CheckOnly` | Vérifier et afficher les choix sans créer de VM ni demander de mots de passe |


`DisplayIndex` et `DisplayTotal` sont internes à l'affichage des lots.
Le nom VirtualBox accepte 1 à 31 caractères minuscules, chiffres et tirets,
en commençant par une lettre. Le hostname accepte des labels DNS de 1 à 63
caractères, sur 253 caractères maximum ; il ne crée aucune entrée DNS.
Les comptes acceptent jusqu'à 32 caractères minuscules, chiffres, `_` et `-`,
en commençant par une lettre ou `_`.

Les mots de passe acceptent 12 à 128 caractères : lettres ASCII, chiffres et
`! @ % _ = + . , : -`. En cas de confirmation différente, de longueur invalide ou de caractère interdit,
les deux saisies du compte concerné sont redemandées sans perdre la configuration.
Une annulation ou une erreur technique interrompt toujours le traitement.
Les autres caractères sont refusés pour conserver un
quoting non ambigu dans VirtualBox et Kickstart.

## Lots

Les créations et questions se suivent, mais les installations Linux déjà lancées
continuent en parallèle. Les secrets fournis en arguments sont communs au lot ; ceux qui manquent sont
demandés séparément pour chaque VM.

Sans `-VmName`, tous les noms sont demandés dans une même section. Avec
`-VmName linux10 -VmCount 3`, les noms deviennent linux10, linux11, linux12.
Sans suffixe numérique, `-VmName worker` génère worker01, worker02, etc.
Pour fournir un hostname commun sous forme de modèle, utiliser
`-HostName "{vm}.lab.test"`. Sinon le hostname est demandé pour chaque VM.
Les autres arguments explicites s'appliquent à tout le lot ; les choix omis sont
redemandés par VM, sauf le mode IPv4 choisi pour le lot.

En statique, utiliser `-IpAddresses "192.168.1.60,192.168.1.61,192.168.1.62"`
dans l'ordre des noms. `-IpAddress` est réservé à une VM. Le nombre d'IP et leur
unicité sont contrôlés. Les collisions avec d'autres machines ne sont pas détectées.

Un échec arrête le lot et laisse les VM déjà lancées intactes. Il n'y a pas de
transaction globale : les conflits de noms existants sont vérifiés au traitement
de chaque VM. Reprendre seulement les VM restantes après diagnostic.

## Réseau et accès

Le pont utilise une carte physique connectée reconnue par Windows et VirtualBox,
avec une IPv4 et une route par défaut : Ethernet prioritaire, puis Wi-Fi. À type
égal, la métrique route + interface départage les cartes. Un nom peut être imposé
avec `-BridgeAdapter`. Il n'y a pas de bascule automatique après création.

Les réseaux Wi-Fi invités ou d'entreprise peuvent limiter le pont. Le script ne
configure aucun proxy et ne change aucune protection Windows (VBS, Credential Guard,
intégrité mémoire). Toutes les VM doivent accéder aux dépôts pour leurs mises à jour,
y compris les nœuds sans partage. Les IP statiques doivent être libres, hors plage
DHCP ou réservées par l'administrateur du réseau. Le script vérifie le format,
le masque et la cohérence IP/passerelle, pas l'accessibilité réelle.
Le Kickstart demande la désactivation IPv6 en mode statique ; le mode DHCP conserve
le comportement IPv6 de la distribution. Une réponse DNS AAAA ne démontre pas à elle
seule une connexion IPv6.

| Mot de passe root | SSH root par mot de passe | Effet |
|---|---|---|
| Disabled | Disabled | Mot de passe root verrouillé ; administrer via sudo |
| Enabled | Disabled | Console et `su -` possibles ; SSH root par mot de passe interdit |
| Enabled | Enabled | Connexions root par mot de passe autorisées en console et SSH |
| Disabled | Enabled | Configuration refusée |

SSH root désactivé signifie `PermitRootLogin prohibit-password` : les clés root
ne sont pas interdites, mais aucune clé n'est distribuée par le script.
Le contrôle `sshd -T` est local, pas un test de connexion depuis Windows.

## Dossiers partagés et Guest Additions

Saisir un dossier Windows existant et un nom seul, comme `temp`, jamais `/mnt/temp`.
Le montage Linux est `/mnt/<nom>`. Il est accessible au compte principal et à root,
avec les modes 0700/0600 et l'UID/GID du compte principal. Les comptes supplémentaires
sans sudo n'y accèdent pas automatiquement. Les droits Windows continuent de s'appliquer.
En lecture/écriture, une suppression depuis Linux supprime aussi le fichier Windows.

Le fichier `C:\Lab-Ansible\partages.json` est inclus dans le pack. Adapter son chemin Windows si nécessaire :

```json
[
  {"Name":"temp","HostPath":"C:\\Lab-Partage","ReadOnly":false}
]
```

Puis ajouter `-SharedFoldersMode Enabled -SharedFoldersFile "C:\Lab-Ansible\partages.json"`.
`ReadOnly` doit être un booléen JSON, pas une chaîne. Sans JSON, les dossiers sont
demandés par VM. `Disabled` n'installe pas les Guest Additions via ce script.

L'ISO des Additions est recherchée près de VBoxManage, ou fournie avec
`-GuestAdditionsIsoPath`. Elle est attachée après la préparation unattended, sur
un port SATA libre, puis copiée dans Linux avant éjection. L'installation se fait
après mise à jour et redémarrage, avec `kernel-devel` correspondant au noyau actif.
Les outils d'extraction tar/gzip/bzip2/xz sont installés. Une reprise réutilise les
outils et modules s'ils sont disponibles, sans exiger un partage déjà monté.

Les partages utilisent fstab et `/etc/modules-load.d/lab-vbox.conf`, sans `nofail`
ni `x-systemd.automount`. Leur source Windows doit rester disponible au démarrage.
Le contrôle vérifie le montage vboxsf et la lecture par le compte principal,
pas l'écriture. Le code 2 des outils Oracle n'est toléré qu'avec réussite des
contrôles suivants ; les autres codes non nuls sont bloquants.

## Déroulement Linux

1. Installation minimale BIOS/SATA/LVM, clavier français, locale anglaise,
   fuseau Europe/Paris et horloge matérielle UTC. SELinux enforcing et firewalld
   activés, service SSH autorisé.
2. Activation CRB/EPEL, `dnf upgrade --refresh` et installation de kernel,
   kernel-devel, kernel-headers, make, gcc, perl, dkms, bzip2, tar, gzip, xz,
   elfutils-libelf-devel et grubby. Controller reçoit aussi Ansible Core et Git.
3. Sélection du noyau installé le plus récent par tri des versions, installation
   de son kernel-devel et définition du noyau par défaut avec grubby.
4. Enregistrement du boot courant, redémarrage automatique, reprise du service.
5. Vérification du noyau attendu, de SSH, des modules/partages éventuels et du rôle.
6. Publication du résultat et création du marqueur `done`.

La durée limite est de deux heures par exécution du service. Une mauvaise version
de noyau après reboot provoque un échec sans boucle de redémarrage. Les mises à jour
sont celles disponibles dans les dépôts activés au moment de la création ; aucune
mise à jour périodique n'est configurée. DKMS installé ne garantit pas que les
modules Oracle soient enregistrés dans DKMS. Après une future mise à jour noyau,
leur fonctionnement doit être revérifié.

## Résultat et journaux

`INSTALLATION LANCEE` dans PowerShell signifie seulement que VirtualBox a démarré
la VM. Lire les deux fichiers Linux :

```bash
cat /var/lib/lab-bootstrap/status
cat /var/lib/lab-bootstrap/kernel-status
```

| Statut de préparation | Signification |
|---|---|
| `BOOTSTRAP_PENDING` | Installation préparée, bootstrap pas encore exécuté |
| `BOOTSTRAP_UPDATING` | Mises à jour en cours |
| `BOOTSTRAP_REBOOT_PENDING` | Redémarrage demandé, reprise attendue |
| `BOOTSTRAP_RUNNING` | Préparation et contrôles en cours |
| `ANSIBLE_READY` / `NODE_READY` | Contrôles du rôle terminés avec succès |
| `BOOTSTRAP_FAILED` | Préparation échouée ; consulter les journaux |

Le fichier `kernel-status` n'existe qu'après le premier contrôle noyau en phase 2 :

| État noyau | Traitement |
|---|---|
| `KERNEL_ERROR` | Signature grave détectée : préparation bloquée |
| `KERNEL_WARNINGS` | Avertissement conservé ; poursuite des contrôles fonctionnels |
| `KERNEL_NO_ALERT_DETECTED` | Aucune des signatures surveillées détectée |

Les signatures graves comprennent BUG, Oops, kernel panic, general protection
fault, unable to handle kernel, soft lockup et hard LOCKUP. WARNING, Call Trace
ou rcu/stall seuls sont signalés sans bloquer. Le journal complet est conservé
sous `/var/lib/lab-bootstrap/kernel-current-boot.log`. Un READY ne signifie pas
qu'un avertissement noyau est résolu. Ce filtrage ne garantit pas la santé complète
du système et n'est pas une surveillance permanente après la préparation.

```bash
systemctl show lab-bootstrap.service -p Result -p ExecMainStatus -p ActiveState -p SubState
systemctl --failed --no-pager
journalctl -u lab-bootstrap --no-pager -n 100
tail -n 100 /var/log/lab-bootstrap.log
```

Après succès, `active/exited`, `Result=success`, `ExecMainStatus=0` sont attendus
pour ce service oneshot. Après correction d'un échec, `systemctl restart lab-bootstrap`
retente la préparation. Le marqueur `done` empêche une nouvelle exécution après succès.
Ces statuts décrivent la dernière préparation, pas un contrôle continu des VM.

## Vérifications utiles après installation

En root, sur chaque VM :

```bash
hostnamectl
ip -br -4 address
ip -4 route
cat /etc/resolv.conf
timedatectl
uname -r
cat /var/lib/lab-bootstrap/expected-kernel
rpm -q "kernel-devel-$(uname -r)"
/usr/sbin/sshd -t
systemctl is-active sshd
rpm -q epel-release make gcc kernel-headers kernel-devel perl dkms bzip2 tar gzip xz
```

Avec un partage demandé :

```bash
VBoxControl --version
lsmod | grep -E '^vbox(guest|sf)\b'
findmnt --mountpoint /mnt/temp
# Remplacer ansible par le compte principal de CETTE VM.
LAB_USER="ansible"
id "$LAB_USER"
sudo -l -U "$LAB_USER"
runuser -u "$LAB_USER" -- test -r /mnt/temp && echo "OK : partage lisible"
```

Sur le contrôleur, connecté avec le compte principal :

```bash
cd ~/lab
ansible-playbook test.yml
```

Attendre `unreachable=0` et `failed=0`. Ce test cible seulement localhost.
Les nœuds ne sont pas inscrits automatiquement dans cet inventaire. AWX, les clés
SSH, les politiques applicatives comme le blocage d'un port et le NTP personnalisé
ne sont pas configurés par le pack. Le bootstrap ne valide pas la synchronisation NTP.

## VM existantes

Le créateur accepte seulement une VM nouvelle ou totalement vide, arrêtée, sans
contrôleur de stockage ni instantané. Il ne supprime ni ne redimensionne un disque.
Remplacer les fichiers Windows ne modifie pas les VM déjà installées.

Le lanceur séparé et le correctif historique destiné aux VM v16 ont été retirés du pack.
Si une ancienne extraction les contient encore, supprimer les fichiers suivants :

- `Start-MyLab.ps1` : ancien lanceur séparé, remplacé par les exemples du script principal.
- `Repair-Bootstrap-v17.py` : correctif historique pour les VM v16, inutile pour les nouvelles créations.
- `LISEZ-MOI.md` : ancien guide remplacé par `README.md`.

Ces suppressions concernent uniquement les copies dans le dossier du package Windows.
Ils ne sont plus utilisés ; aucun nettoyage des VM n'est nécessaire pour cette révision.

## Nettoyage des supports après validation

Les fichiers temporaires de saisie sont supprimés après préparation des supports.
Les secrets restent toutefois dans les fichiers Kickstart/supports sous `LabSetup`,
protégés par ACL Windows (compte courant et SYSTEM), sans chiffrement. Les copies
conservées par l'installateur Linux doivent rester réservées à root.

Après validation, éteindre la VM (`sudo poweroff`), retirer ses médias optiques et
son éventuelle disquette dans VirtualBox, conserver le VDI, puis supprimer uniquement
le dossier `LabSetup`. Ne pas le supprimer pendant l'installation. Changer ensuite
les mots de passe des comptes concernés pour invalider les anciennes copies.
Ne pas partager les supports contenant les secrets.

## Tests du pack

Sans création de VM ni réseau réel :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\Lab-Ansible\Test-LabScript.ps1"
```

`-OutputDirectory` permet de conserver les 14 Kickstarts de test, avec seulement
des secrets fictifs. Sous Linux, le test noyau utilise Python 3 et Bash :

```bash
python3 Test-KernelPolicy.py
```

Le détail des contrôles, des observations réelles et des limites est dans
`REVUE-CODE.md`. Les tests locaux ne remplacent pas un déploiement Windows/VirtualBox.

## Dépannage

| Symptôme | Vérification / action |
|---|---|
| Scripts désactivés | Ouvrir la session de l'exemple 1 ; une stratégie d'entreprise reste prioritaire. |
| ISO introuvable | Adapter `-IsoPath` au fichier local, sans déduire le chemin du nom de la VM. |
| Aucun pont admissible | Vérifier la carte physique, IPv4, route par défaut et pilote de pont VirtualBox. |
| VM existante non vide | Choisir un autre nom ou examiner la VM existante ; le script refuse de l'écraser. |
| Mot de passe refusé | Respecter longueur et caractères autorisés ; en interactif, ressaisir et confirmer. |
| JSON de partage refusé | Fournir `Name`, `HostPath` existant et `ReadOnly: true/false`, sans guillemets autour du booléen. |
| Nom de partage refusé | Saisir `temp`, pas `/mnt/temp` ; le point de montage est généré. |
| Mise à jour ou compilation échouée | Consulter le journal bootstrap, vérifier accès aux dépôts et kernel-devel du noyau actif. |
| `KERNEL_WARNINGS` | Lire le journal noyau du démarrage courant ; READY n'efface pas cet avertissement. |

Pour collecter le diagnostic sans modifier le système, en root dans la VM :

```bash
uname -r
cat /var/lib/lab-bootstrap/status
cat /var/lib/lab-bootstrap/kernel-status
systemctl status lab-bootstrap.service --no-pager -l
journalctl -u lab-bootstrap.service -b --no-pager -n 100
journalctl -k -b --no-pager
```

Le fichier archivé `kernel-current-boot.log` reflète le démarrage pendant lequel
le bootstrap l'a écrit ; après un autre redémarrage, utiliser `journalctl -k -b`.
L'avertissement RCU observé avec les Guest Additions n'a pas de cause confirmée
ni de correctif validé dans ce package. Aucune modification de GRUB, aucun
blacklistage de module et aucune désactivation des protections Windows ne sont
ajoutés pour le masquer.
