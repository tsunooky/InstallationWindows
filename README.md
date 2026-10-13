# Installer et optimiser Windows 11 proprement

Une installation de Windows 11 sans compte Microsoft ni applications inutiles, accompagnée d'un script qui applique uniquement des réglages qui ont un effet réel : moins de processus, moins de mémoire utilisée, une latence plus faible, et aucune optimisation risquée. 

## 1. Préparer la clé USB

1. Télécharger ce dépôt : bouton **Code** > **Download ZIP**, puis extraire le dossier.
2. Télécharger l'outil Microsoft : [Créer un support d'installation de Windows 11](https://www.microsoft.com/fr-fr/software-download/windows11).
3. Lancer l'outil et créer la clé USB (8 Go minimum, son contenu est effacé).
4. Copier les fichiers `autounattend.xml` et `setup.cmd` à la racine de la clé, sans les renommer.
5. Si vous avez peur de vous tromper pendant l'installation, débranchez tous les disques sauf celui qui recevra Windows.

> [!TIP]
> En cas de réinstallation, notez d'abord votre clé Windows. Ouvrez l'application **Terminal** et lancez :
>
> ```powershell
> (Get-CimInstance SoftwareLicensingService).OA3xOriginalProductKey
> ```

## 2. Installer Windows

1. Brancher la clé et démarrer dessus : menu de démarrage avec <kbd>F8</kbd>, <kbd>F11</kbd> ou <kbd>F12</kbd> selon la marque, ou ordre de démarrage dans le BIOS.
2. Si l'installation demande une édition, choisir celle de votre licence (Famille ou Pro).
3. Supprimer TOUTES les partitions du disque qui recevra Windows, sélectionner l'espace non alloué, puis **Suivant**. Vérifiez qu'il s'agit du **bon** disque !
4. Se connecter au Wi-Fi si besoin, puis créer le compte local (nom et mot de passe).

Si Windows n'est pas activé : **Paramètres** > **Système** > **Activation**, puis entrez votre clé.

> [!TIP]
> Carte réseau non reconnue : branchez votre téléphone en USB et activez le partage de connexion le temps d'installer les pilotes.

## 3. Mettre à jour Windows et installer les pilotes

1. Une fois sur le Bureau, aller dans **Paramètres** > **Windows Update** > **Rechercher des mises à jour**. Installer, redémarrer, et recommencer jusqu'à ce qu'il n'y en ait plus.
2. Installer les pilotes :
   - **Chipset** : [AMD](https://www.amd.com/fr/support/download/drivers.html) ou [Intel](https://www.intel.fr/content/www/fr/fr/support/detect.html).
   - **Carte graphique** : [NVIDIA App](https://www.nvidia.com/fr-fr/software/nvidia-app/) ou [AMD Adrenalin](https://www.amd.com/fr/support/download/drivers.html).
   - **Réseau et audio** : sur le site du fabricant de votre carte mère. Pour connaître son modèle, ouvrir **Terminal** et lancer `Get-CimInstance Win32_BaseBoard` (ligne `Product`). Installez uniquement les pilotes, pas les utilitaires du fabricant.
3. Redémarrer.

## 4. Lancer le script

1. Ouvrir la clé USB, double-cliquer sur `setup.cmd`, puis accepter la demande d'autorisation.
2. Cocher ce que vous utilisez avec <kbd>Espace</kbd>, puis valider avec <kbd>Entrée</kbd>. Ce qui n'est pas coché est retiré ou désactivé : Xbox est désinstallé, l'impression, WSL et les notifications sont coupés. Steam et Discord ne sont jamais désinstallés.

```
  Windows Optimization

  Check what you will use

  > [ ] Xbox (Xbox app, Game Pass, Game Bar)
    [ ] Printing
    [ ] WSL / virtualization
    [ ] Notifications
    [ ] Steam
    [ ] Discord

  Up/Down: move   Space: check/uncheck   Enter: confirm
```

Au premier lancement, rien n'est coché. Aux lancements suivants, les cases reprennent l'état du PC.

3. Chaque étape s'affiche avec son résultat, et les échecs éventuels sont rappelés à la fin.
4. Redémarrer le PC.

<details>
<summary>Ce que fait le script</summary>

- **Applications** : Firefox avec uBlock Origin, VLC et 7-Zip. Steam et Discord si cochés, sans lancement au démarrage de Windows.
- **Confidentialité** : télémétrie, publicité ciblée, rapport d'erreurs, Copilot, Recall et résultats web de la recherche coupés.
- **Système** : services inutiles arrêtés, applications en arrière-plan coupées, hibernation désactivée.
- **Latence** (PC fixe) : mode d'alimentation « Meilleures performances », économies d'énergie désactivées.
- **Jeu** : optimisations pour les jeux en fenêtre activées, enregistrement en arrière-plan coupé.
- **Au choix** : Xbox, impression, WSL / virtualisation et notifications restent actifs si leur ligne est cochée, et sont retirés ou désactivés sinon. Les applications retirées par la clé USB et réinstallées depuis par Windows (Outlook, Copilot, Teams…) apparaissent aussi dans la liste : décochées, elles sont supprimées.

</details>

Le script crée le raccourci **Optimisation Windows** sur le Bureau. Le relancer refait les mêmes réglages sans toucher à ce qui est déjà en place : à faire après une grosse mise à jour de Windows, ou pour cocher ou décocher un élément de la liste.

> [!TIP]
> Raccourci supprimé par erreur ? Relancez `setup.cmd` depuis la clé USB : il recrée le raccourci.

## 5. Régler la carte graphique

Les bons réglages dépendent de vos jeux et de vos préférences. Ces vidéos expliquent chaque option clairement :

- **NVIDIA** : [Configure The Nvidia App](https://www.youtube.com/watch?v=j08cAZGMhTM) (Hardware Unboxed)
- **AMD** : [BEST AMD Software Settings (2026)](https://www.youtube.com/watch?v=kJGgMJUueKM) (Ancient Gameplays)

## 6. Bonnes pratiques

- Pas d'overclocking manuel (activer le profil EXPO/XMP de la RAM est OK) : l'undervolting apporte bien plus, en températures, en durée de vie des composants et même en performances.
- Pas de logiciel de nettoyage ou d'optimisation (CCleaner ou autre).
- Pas d'antivirus : Microsoft Defender suffit.
- Garder Windows et les pilotes à jour.

## 7. À tester soi-même

<details>
<summary>Afficher le réglage à tester</summary>

Ce réglage donne des résultats différents selon le processeur et le jeu. Mesurez le FPS moyen et le 1 % low avant et après, et revenez en arrière s'il n'y a pas de gain.

### Écarter le cœur 0 du jeu

1. Lancer le jeu, puis ouvrir le **Gestionnaire des tâches** > **Détails**.
2. Clic droit sur le jeu > **Définir l'affinité**.
3. Décocher les **deux** premiers processeurs (le cœur 0 et son deuxième thread).

À refaire à chaque lancement du jeu. Certains anti-triches refusent ce changement : dans ce cas, laisser l'affinité par défaut.

</details>

## 8. Optionnel

<details>
<summary>Afficher l'installation de WSL2</summary>

### Installer WSL2 (Linux dans Windows)

1. Ouvrir le raccourci **Optimisation Windows** du Bureau, cocher **WSL / virtualization**, puis redémarrer.
2. Ouvrir **Terminal** et lancer `wsl --install`, puis redémarrer.
3. Créer le nom d'utilisateur et le mot de passe Linux demandés.
4. Dans le terminal Ubuntu, mettre à jour :

   ```bash
   sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y && sudo apt autoclean -y && sudo apt install -y vim nano
   ```
