# Revue du package — version 26

Revue du 25 octobre 2026, à partir du package version 25, comparé au créateur version 24.

## Périmètre et changements

- Relecture du créateur PowerShell, des modèles Kickstart/Bash, des tests et du guide.
- Remplacement de `LISEZ-MOI.md` par `README.md`, point d'entrée unique pour GitHub.
- Documentation des prérequis, paramètres, comptes, secrets, lots, partages,
  cycle de mise à jour/redémarrage, statuts, dépannage et publication.
- Conservation des cinq exemples dans l'aide du script et dans le README.
- Remplacement du chemin personnel des exemples par `C:\Lab-Ansible\ISO` pour
  l'ISO et `C:\Lab-Partage` pour le partage. Le dossier partagé doit exister.
- Mise en cohérence du JSON livré et de son assertion dans les tests.
- Correction des commentaires décrivant les tests et de leur numérotation.
- Ajout de `.gitignore` et `.gitattributes`. Le JSON reste du JSON strict sans
  commentaires ; ses champs sont expliqués dans le README.
- Conservation des tests utiles. Aucun ancien lanceur ou correctif manuel n'est
  réintroduit. Les sorties de test et outils de préparation ne sont pas livrés.

Le code exécutable du créateur et les modèles Linux sont identiques à la version 24.
La comparaison exacte du contenu après l'aide PowerShell ne trouve qu'un changement
connu de commentaire de section. Les comportements de déploiement et de diagnostic
noyau ne sont pas modifiés.

## Vérifications exécutées sur cette livraison

| Vérification | Résultat |
|---|---|
| Comparaison du créateur avec le fichier v24 | Aucune modification exécutable |
| `python3 Test-KernelPolicy.py` | Réussite : 18 cas rôle/journal et 2 cas d'échec |
| Suite PowerShell 7.4.6/Linux | Réussite, code retour 0, 14 Kickstarts générés |
| `bash -n` sur les scripts générés | 15 sections post et 14 bootstraps valides |
| Cinq exemples du script présents dans le README | Réussite |
| JSON fourni et chemin attendu dans le test | Cohérents ; `ReadOnly` est un booléen |
| Recherche des chemins personnels et anciennes références | Chemins personnels retirés ; guide remplacé |

La suite `Test-LabScript.ps1` a été exécutée pendant cette revue sous
**PowerShell 7.4.6/Linux**, avec code retour 0. Tous ses contrôles ont réussi.
Elle a produit 14 Kickstarts ; `bash -n` a validé leurs 15 sections post-installation
et 14 scripts bootstrap. Les dépendances Windows/VirtualBox sont simulées.
Ce résultat ne remplace pas un essai sous Windows PowerShell 5.1 avec VirtualBox.
Aucune nouvelle VM n'a été déployée pendant cette revue.

Contrôles supplémentaires :

- Tous les paramètres du créateur figurent dans le README, y compris les deux
  paramètres internes d'affichage.
- Les exemples JSON du README sont valides et le fichier partagé livré passe
  le test PowerShell réel du parseur.
- Les liens locaux du README ciblent des fichiers présents.
- `git check-ignore` confirme les exclusions des supports et configurations privées,
  tout en conservant les huit fichiers du package dans le périmètre publiable.
- L'archive ne contient aucun média, journal de VM, runtime de test ni ancien correctif.

## Fichiers à garder ou à retirer

Les huit fichiers livrés sont utiles : le créateur, le README, le JSON d'exemple,
les deux scripts de tests, cette revue et les deux fichiers de configuration Git.
La revue est facultative pour exécuter le créateur, mais conserve les preuves de
validation et leurs limites ; elle n'est pas obsolète.

À retirer seulement s'ils subsistent dans une ancienne extraction :
`Start-MyLab.ps1`, `Repair-Bootstrap-v17.py` et `LISEZ-MOI.md`.
Leur retrait ne nécessite aucune suppression de VM ou de disque.
Les répertoires LabSetup ne doivent pas être supprimés pendant une installation :
ils sont exclus du dépôt et suivent la procédure de nettoyage du README.

## Avis avant publication

Aucun fichier obsolète ni défaut bloquant n'a été détecté dans le périmètre des
contrôles exécutés. Les sources peuvent être publiées comme outil de lab avec les
limites documentées. Cela ne constitue pas une certification de compatibilité.
Le dépôt ne contient pas de licence choisie par son auteur ; sa publication seule
ne définit pas une licence de réutilisation. Les exemples de mots de passe sont
fictifs et les chemins/IP doivent être adaptés avant une exécution réelle.

## Contrôles à reproduire sur Windows

Depuis le dossier extrait, exécuter :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-LabScript.ps1
```

La suite simule les commandes réseau et VirtualBox. Elle couvre notamment IPv4,
priorité Ethernet/Wi-Fi, paramètres interactifs, lots, comptes, shell, sudo,
mots de passe et nouvelles tentatives, tableaux JSON vides ou multiples,
partages, génération Kickstart et attachement des médias.

Pour conserver les 14 Kickstarts de test dans un dossier ignoré par Git :

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-LabScript.ps1 -OutputDirectory .\test-output
```

Un déploiement réel reste nécessaire pour vérifier les dépendances de l'hôte,
les ACL Windows, la préparation des médias, les dépôts et le démarrage de Linux.

## Limites conservées et connues

- READY décrit les contrôles de préparation ; les statuts ne surveillent pas la VM
  en continu et le journal archivé peut concerner un démarrage antérieur.
- L'avertissement RCU observé précédemment n'a pas de cause ni de correction
  confirmée. Le package conserve sa détection et n'altère pas les protections Windows.
- IP/passerelle : contrôle de cohérence, sans détection des adresses déjà utilisées.
- Partages : contrôle de montage et lecture par le compte principal, sans test d'écriture.
- La présence de DKMS ne garantit pas la reconstruction des modules Oracle après
  une mise à jour ultérieure du noyau.
- Les secrets sous LabSetup sont protégés par ACL, sans chiffrement. Les arguments
  explicites peuvent être conservés dans l'historique ou visibles dans les processus.
- Les droits sudo du compte principal proviennent à la fois de wheel et du fichier
  dédié ; les lignes répétées dans `sudo -l` sont possibles.
- AWX, inventaire distant, clés SSH, règles applicatives et version VMware ne sont
  pas inclus. Aucune synchronisation NTP n'est vérifiée par le bootstrap.
- Remplacer ce package ne met pas à jour les VM déjà installées.

Cette revue améliore la cohérence et la lisibilité ; elle ne garantit pas l'absence
de tout défaut. Aucun résultat historique n'est présenté comme un nouveau test réel.
