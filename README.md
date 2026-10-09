# Installer et optimiser Windows 11 proprement

Une installation de Windows 11 sans compte Microsoft ni applications inutiles, accompagnée d'un script qui applique uniquement les réglages qui ont un effet réel : moins de processus, moins de mémoire utilisée, une latence plus faible, et surtout aucune optimisation risquée. Xbox, l'impression et la virtualisation peuvent être désactivées ou réactivées avec le script.

> [!WARNING]
> L'installation efface le disque choisi. Sauvegardez vos fichiers avant de commencer.

## 1. Préparer la clé USB

1. Télécharger ce dépôt : bouton **Code** > **Download ZIP**, puis extraire le dossier.
2. Télécharger l'outil Microsoft : [Créer un support d'installation de Windows 11](https://www.microsoft.com/fr-fr/software-download/windows11).
3. Lancer l'outil et créer la clé USB (8 Go minimum, son contenu est effacé).
4. Copier les fichiers `autounattend.xml` et `config.ps1` à la racine de la clé, sans les renommer.
5. PC fixe avec plusieurs disques : débrancher tous les disques sauf celui qui recevra Windows.

> [!TIP]
> En cas de réinstallation, notez d'abord votre clé Windows. Ouvrir **Terminal** et lancer :
>
> ```powershell
> (Get-CimInstance SoftwareLicensingService).OA3xOriginalProductKey
> ```

## 2. Installer Windows

1. Brancher la clé et démarrer dessus : menu de démarrage avec <kbd>F8</kbd>, <kbd>F11</kbd> ou <kbd>F12</kbd> selon la marque, ou ordre de démarrage dans le BIOS.
2. Si l'installation demande une édition, choisir celle de votre licence (Famille ou Pro).
3. Supprimer toutes les partitions du disque qui recevra Windows, sélectionner l'espace non alloué, puis **Suivant**. Vérifiez deux fois qu'il s'agit du **bon** disque.
4. Se connecter au Wi-Fi si besoin, puis créer le compte local (nom et mot de passe).
5. Rebrancher les autres disques une fois sur le Bureau.

Si Windows n'est pas activé : **Paramètres** > **Système** > **Activation**, puis entrer votre clé.

> [!TIP]
> Carte réseau non reconnue : branchez votre téléphone en USB et activez le partage de connexion le temps d'installer les pilotes.

## 3. Mettre à jour Windows et installer les pilotes

1. Une fois sur le Bureau, aller dans **Paramètres** > **Windows Update** > **Rechercher des mises à jour**. Installer, redémarrer, et recommencer jusqu'à ce qu'il n'y en ait plus.
2. Installer les pilotes :
   - **Chipset** : [AMD](https://www.amd.com/fr/support/download/drivers.html) ou [Intel](https://www.intel.fr/content/www/fr/fr/support/detect.html).
   - **Carte graphique** : [NVIDIA App](https://www.nvidia.com/fr-fr/software/nvidia-app/) ou [AMD Adrenalin](https://www.amd.com/fr/support/download/drivers.html).
   - **Réseau et audio** : sur le site du fabricant de votre carte mère. Pour connaître son modèle, ouvrir **Terminal** et lancer `Get-CimInstance Win32_BaseBoard` (ligne `Product`).
3. Redémarrer.

> [!NOTE]
> Installez uniquement les pilotes, pas les utilitaires du fabricant (centres de contrôle, RGB, "boosters").

## 4. Lancer le script

1. Copier `config.ps1` de la clé vers le Bureau.
2. Clic droit sur le fichier > **Exécuter avec PowerShell**, puis accepter la demande d'autorisation.
3. Vérifier le matériel détecté, puis cocher ce que vous utilisez avec <kbd>Espace</kbd> et valider avec <kbd>Entrée</kbd> :

```
  Windows Optimization

  Check what you use

  > [ ] Xbox (Game Pass, Xbox app, Game Bar)
    [ ] Printing
    [ ] WSL / Virtualization
    [ ] Install Steam
    [ ] Install Discord

  Up/Down: move   Space: check/uncheck   Enter: confirm
```

4. Laisser le script travailler quelques minutes. Chaque étape s'affiche avec son résultat, et les échecs éventuels sont rappelés à la fin.
5. Redémarrer le PC.

<details>
<summary>Ce que fait le script</summary>

- **Applications** : Firefox avec uBlock Origin, VLC et 7-Zip. Steam et Discord si cochés, sans lancement au démarrage de Windows.
- **Confidentialité** : télémétrie, publicité ciblée, rapport d'erreurs, Copilot, Recall et résultats web de la recherche coupés.
- **Système** : services inutiles arrêtés, applications en arrière-plan coupées, hibernation désactivée, notifications coupées.
- **Latence** (PC fixe) : mode d'alimentation « Meilleures performances », économies d'énergie désactivées.
- **Jeu** : optimisations pour les jeux en fenêtre activées, enregistrement en arrière-plan coupé.
- **Edge** : conservé, mais plus aucun processus en arrière-plan.
- **Modules** : Xbox, impression et WSL / virtualisation retirés si non cochés. Tous se réactivent depuis le menu du script.

</details>

Relancer `config.ps1` de la même façon ouvre un menu : activer ou désactiver un module, faire un bilan de santé, ou réappliquer les optimisations.

## 5. Régler la carte graphique

Les bons réglages dépendent de vos jeux et de vos préférences. Ces vidéos expliquent chaque option clairement :

- **NVIDIA** : [Configure The Nvidia App](https://www.youtube.com/watch?v=j08cAZGMhTM) (Hardware Unboxed)
- **AMD** : [BEST AMD Software Settings (2026)](https://www.youtube.com/watch?v=kJGgMJUueKM) (Ancient Gameplays)

## 6. Bonnes pratiques

- Pas d'overclocking : l'undervolting apporte bien plus, en températures, en durée de vie des composants et même en performances.
- Pas de logiciel de nettoyage ou d'optimisation (CCleaner et autres).
- Pas d'antivirus en plus : Microsoft Defender suffit.
- Garder Windows et les pilotes à jour.

## 7. À tester soi-même

<details>
<summary>Afficher les réglages à tester</summary>

Ces réglages donnent des résultats différents selon le processeur et le jeu. Mesurez le FPS moyen et le 1 % low avant et après, et revenez en arrière s'il n'y a pas de gain.

### Écarter le cœur 0 du jeu

1. Lancer le jeu, puis ouvrir le **Gestionnaire des tâches** > **Détails**.
2. Clic droit sur le jeu > **Définir l'affinité**.
3. Décocher les **deux** premiers processeurs (le cœur 0 et son deuxième thread).

À refaire à chaque lancement du jeu.

### Politique des threads courts (AMD avec PBO activé uniquement)

**À ne pas utiliser** sur Intel 12e génération ou plus récent (les threads du jeu iraient sur les E-cores), ni sur les X3D à deux CCD (7900X3D, 7950X3D, 9900X3D, 9950X3D).

Ouvrir **Terminal** en administrateur, puis activer (« All processors ») :

```powershell
powercfg -attributes SUB_PROCESSOR bae08b81-2d5e-4688-ad6a-13243356654b -ATTRIB_HIDE
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR bae08b81-2d5e-4688-ad6a-13243356654b 0
powercfg /setactive SCHEME_CURRENT
```

Revenir au réglage par défaut (« Prefer performant processors ») :

```powershell
powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR bae08b81-2d5e-4688-ad6a-13243356654b 2
powercfg /setactive SCHEME_CURRENT
```

Si le gain se confirme, écarter le cœur 0 devient en grande partie inutile.

</details>

## 8. Optionnel

<details>
<summary>Afficher l'installation de WSL2</summary>

### Installer WSL2 (Linux dans Windows)

1. Relancer `config.ps1` et activer le module **WSL / Virtualization**, puis redémarrer.
2. Ouvrir **Terminal** et lancer `wsl --install`, puis redémarrer.
3. Créer le nom d'utilisateur et le mot de passe Linux demandés.
4. Dans le terminal Ubuntu, mettre à jour :

   ```bash
   sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y && sudo apt autoclean -y && sudo apt install -y vim nano
   ```
