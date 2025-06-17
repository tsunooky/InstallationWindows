# Installation / Réinstallation Propre et Optimisée de Windows 11

Ce guide détaille les étapes pour installer ou réinstaller Windows 11 de manière propre, optimisée et sans risques de tout casser à cause des optimisations.

**⚠️ Avertissement :**
Suivez ce guide attentivement. Ces manipulations sont effectuées sous votre responsabilité. Pensez à sauvegarder vos données importantes avant toute réinstallation.

---

## 1. 🛠️ Préparation

### 1.1 Sauvegardes (Si Réinstallation)

Si réinstallation sur un PC déjà utilisé :

*   **Sauvegarder les fichiers importants** sur un support externe.
*   **Sauvegarder la clé d'installation Windows** (si non liée au compte Microsoft ou firmware) :
    1.  Ouvrir **Windows Terminal** (admin).
    2.  Exécuter :
        ```powershell
        (Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKey
        ```
    3.  Copier et conserver la clé.

### 1.2 Création du Support d'Installation de Windows 11

0.  **Sauvegarder les fichiers importants** de la clé USB utilisée sur un autre support externe.
1.  Télécharger l'outil de création de support Microsoft :
    [https://www.microsoft.com/fr-fr/software-download/windows11](https://www.microsoft.com/fr-fr/software-download/windows11)
    (Option "Création d'un support d'installation de Windows 11").
2.  Lancer l'outil et accepter les termes.
3.  Choisir "Disque mémoire flash USB".
4.  Sélectionner la clé USB (8Go min, le contenu de la clé sera effacée).

### 1.3 Ajout du Fichier `autounattend.xml`

Le fichier `autounattend.xml` présent dans ce repository automatise de nombreuses étapes d'installation (langue, EULA, compte local, contournement des exigences matérielles, suppression de bloatware, etc.).

1.  Télécharger `autounattend.xml` depuis ce repository GitHub.
2.  Copier `autounattend.xml` **à la racine** de la clé USB d'installation.

---

## 2. 🚀 Installation de Windows 11

1.  Brancher la clé USB sur le PC.
2.  Redémarrer le PC.
3.  Accéder au **Menu de Démarrage (Boot Menu)** ou au **BIOS** (touches courantes à spam : `F11`, `F12`, `F8`, `SUPPR (DEL)`, `ESC`).
4.  Sélectionner la clé USB comme périphérique de démarrage.
5.  L'installation de Windows 11 démarre. Suivre les instructions pour le choix de la partition et le nom de l'ordinateur.
6.  **IMPORTANT :** Lors du premier redémarrage automatique après la copie des fichiers (compte à rebours de 10s), **retirer la clé USB**.
7.  Terminer l'installation.

---

## 3. ✨ Post-Installation et Optimisations

### 3.1 🔄 Mises à Jour Windows Update

1.  Ouvrir **Paramètres** > **Windows Update**.
2.  Cliquer sur **Rechercher des mises à jour** et installer.
3.  Redémarrer le PC.
4.  Répéter jusqu'à ce qu'il n'y ait plus de mises à jour.

### 3.2 🌐 Installation et Configuration du Navigateur

1.  Ouvrir **Windows Terminal** (admin).
2.  Installer **Firefox** :
    ```powershell
    winget install --id=Mozilla.Firefox -e
    ```
    OU **Google Chrome** :
    ```powershell
    winget install --id=Google.Chrome -e
    ```
    
4.  Mettre à jour tous les paquets des applications :
    ```powershell
    winget upgrade --all --include-unknown --accept-package-agreements
    ```
5.  Définir comme navigateur par défaut :
    *   **Paramètres > Applications > Applications par défaut**.
    *   Rechercher et sélectionner le navigateur installé.
    *   Assigner tous les types de fichiers et protocoles (HTTP, HTTPS, .html, etc.) au navigateur.

#### 3.2.1 Configuration Spécifique pour Firefox

1.  **Installer les extensions :**
    *   [uBlock Origin](https://addons.mozilla.org/fr/firefox/addon/ublock-origin/)
    *   [ClearURLs](https://addons.mozilla.org/fr/firefox/addon/clearurls/)
    *   [Decentraleyes](https://addons.mozilla.org/fr/firefox/addon/decentraleyes/)
    *   [Privacy Badger](https://addons.mozilla.org/fr/firefox/addon/privacy-badger17/)
2.  **(Optionnel) Configurer uBlock Origin pour enlever les Shorts sur YouTube:**
    *   Ouvrir tableau de bord uBlock Origin (icône extension > engrenages).
    *   Onglet **"Mes filtres"**.
    *   Copier le contenu du fichier `ublock_filters.txt` (disponible dans ce repository) et coller.
    *   Cliquer sur **"Appliquer"**.

### 3.3 🧩 Mise à Jour des Pilotes (Général)

1.  Télécharger et lancer **UserDiag** : [https://userdiag.com/fr/](https://userdiag.com/fr/)
2.  Installer, lancer analyse, cliquer **"Afficher la configuration en ligne"**.
3.  Prioriser les **pilotes de la carte mère** (chipset, audio, LAN). Télécharger depuis le site du fabricant (carte mère ou PC portable).

### 3.4 🚗 Installation et Configuration des Pilotes Graphiques

#### 3.4.1 Cartes NVIDIA

1.  Télécharger et installer **NVIDIA App** : [https://www.nvidia.com/fr-fr/software/nvidia-app/](https://www.nvidia.com/fr-fr/software/nvidia-app/)
2.  Ouvrir, aller à "Pilotes" et installer la dernière version.
3.  Clic droit Bureau > **Plus d’options** > **Panneau de configuration NVIDIA**.
    *   Menu **Bureau** > Décochez **"Afficher l'icône de la zone de notification GPU"**.
    *   **Paramètres 3D > Régler les paramètres d'image...** > Cocher **"Utiliser mes préférences..."** > Curseur sur **"Performances"**.
    *   **Paramètres 3D > Gérer les paramètres 3D** :
        *   **Mode de faible latence** > **"Activé"**.
        *   **Si PC fixe : Mode de gestion de l'alimentation** > **"Privilégier les performances maximales"**.
        *   **Si PC portable :** Laisser "Normal" ou "Optimisé". Configurer "Privilégier les performances maximales" par jeu (dans l'onglet "Paramètres de programmes" ou NVIDIA App) si joué sur secteur.

#### 3.4.2 Cartes AMD

1.  Télécharger pilotes : [https://www.amd.com/en/support/download/drivers.html](https://www.amd.com/en/support/download/drivers.html)
2.  Installer les pilotes.
    *(Section à compléter pour les réglages spécifiques à AMD)*

### 3.5 ⚡ Mode de Gestion d'Alimentation (PC Fixe Uniquement)

1.  Touche `Win`, taper `alimentation`, ouvrir **"Choisir un mode de gestion d'alimentation"**.
2.  Sélectionner :
    *   **CPU Intel ≤ 11ème gen :** "Hautes performances" ou "Performances optimales".
    *   **CPU Intel ≥ 12ème gen :** "Hautes performances".
    *   **CPU AMD Ryzen ≤ 3000 series :** "AMD Ryzen Balanced" (via pilotes chipset AMD) ou "Hautes performances".
    *   **CPU AMD Ryzen ≥ 5000 series :** "Utilisation normale" ou "Hautes performances". Ajuster via **Paramètres > Système > Alimentation et batterie** si curseur disponible.

### 3.6 🔧 Optimisations des Paramètres Windows

Ouvrir **Paramètres** :

*   **Système > Écran > Graphiques > Modifier les paramètres graphiques par défaut** :
    *   Décocher `Planification de processeur graphique à accélération matérielle`.
    *   Cocher `Optimisations pour les jeux en fenêtre`.
*   **Système > Son > Autres paramètres audio** (ou `Panneau de configuration > Son`) :
    *   Pour chaque périphérique (lecture/enregistrement) > `Propriétés` > `Améliorations` (ou équivalent) > Cocher **"Désactiver toutes les améliorations"**.
*   **Système > Notifications** : Désactiver les notifications inutiles.
*   **Personnalisation > Saisie** :
    *   Décocher `Corriger automatiquement les fautes d’orthographe`.
    *   Décocher `Mettre en surbrillance les mots mal orthographiés`.
*   **Personnalisation > Démarrer** : Cocher **"Afficher plus d’éléments épinglés"**.
*   **Personnalisation > Barre des tâches > Éléments de la barre des tâches** : Décocher tout (Conversation, Widgets, etc.).
*   **Personnalisation > Utilisation de l’appareil** : Décocher tout.
*   **Applications > Applications pour les sites web** : Décocher tout.
*   **Applications > Démarrage** : Désactiver les applications inutiles.
*   **Jeux > Xbox Game Bar** : Décocher l'interrupteur principal.
*   **Jeux > Mode Jeu** : Cocher (Activé).
*   **Confidentialité et sécurité > Général** : Décocher tout.
*   **Confidentialité et sécurité > Entrée manuscrite et personnalisation de la saisie** : Décocher.
*   **Confidentialisation et sécurité > Diagnostics et commentaires** :
    *   Désactiver `Envoyer des données de diagnostic facultatives`.
    *   `Fréquence des commentaires` > **"Jamais"**.
    *   Désactiver `Expériences personnalisées`.
*   **Confidentialité et sécurité > Historique des activités** :
    *   Décocher `Stocker l’historique...`.
    *   Cliquer `Effacer l'historique...`.
*   **Confidentialité et sécurité > Voix** : Désactiver `Reconnaissance vocale en ligne`.
*   **Confidentialité et sécurité > Autorisations de recherche** :
    *   `Filtrage du contenu pour adultes` > `Désactivé`.
    *   Plus bas, désactiver les options de recherche cloud et `Afficher les mots clés de recherche`.

Personnaliser l'**Apparence** (Thèmes, Couleurs, Fond d'écran) dans **Personnalisation**.

### 3.7 📚 Installation des Bibliothèques C++

1.  Télécharger "Visual C++ Redistributable Runtimes All-in-One" de TechPowerUp :
    [https://www.techpowerup.com/download/visual-c-redistributable-runtime-package-all-in-one/](https://www.techpowerup.com/download/visual-c-redistributable-runtime-package-all-in-one/)
2.  Décompresser.
3.  Clic droit `install_all.bat` > **"Exécuter en tant qu'administrateur"**.

### 3.8 📦 Installation Rapide d'Applications (Ninite)

1.  Aller sur [https://ninite.com/](https://ninite.com/)
2.  Cocher les applications souhaitées.
3.  Télécharger et exécuter l'installeur.

### 3.9 📜 Optimisations de paramètres

Ouvrir **Windows Terminal** (admin), et copier puis coller le texte ci-dessous :
    ```powershell
    # Assistant de stockage
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" /v 01 /t REG_DWORD /d 1 /f
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" /v 2002 /t REG_DWORD /d 7 /f
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" /v 2004 /t REG_DWORD /d 1 /f
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" /v 2005 /t REG_DWORD /d 60 /f
    # Amelioration de la precision de la souris
    reg add "HKCU\Control Panel\Mouse" /v MouseSpeed /t REG_SZ /d "0" /f
    reg add "HKCU\Control Panel\Mouse" /v MouseThreshold1 /t REG_SZ /d "0" /f
    reg add "HKCU\Control Panel\Mouse" /v MouseThreshold2 /t REG_SZ /d "0" /f
    # Parametres de confidentialite
    reg add "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowSyncProviderNotifications /t REG_DWORD /d 00000000 /f
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v RotatingLockScreenOverlayEnabled /t REG_DWORD /d 00000000 /f
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338387Enabled /t REG_DWORD /d 00000000 /f
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-338393Enabled /t REG_DWORD /d 00000000 /f
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353694Enabled /t REG_DWORD /d 00000000 /f
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353696Enabled /t REG_DWORD /d 00000000 /f
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" /v ScoobeSystemSettingEnabled /t REG_DWORD /d 00000000 /f
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-310093Enabled /t REG_DWORD /d 00000000 /f
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" /v Enabled /t REG_DWORD /d 00000000 /f
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Privacy" /v TailoredExperiencesWithDiagnosticDataEnabled /t REG_DWORD /d 00000000 /f
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v Start_IrisRecommendations /t REG_DWORD /d 00000000 /f
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\DataCollection" /v AllowTelemetry /t REG_DWORD /d 0 /f
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\DiagTrack" /v Start /t REG_DWORD /d 4 /f
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent" /v DisableWindowsConsumerFeatures /t REG_DWORD /d 1 /f
    reg add "HKLM\SOFTWARE\Microsoft\PolicyManager\default\ADID\AllowAdId" /v value /t REG_DWORD /d 0 /f
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SoftLandingEnabled /t REG_DWORD /d 0 /f
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" /v ShowSuggestedAppsInMenu /t REG_DWORD /d 0 /f
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" /v SubscribedContent-353698Enabled /t REG_DWORD /d 0 /f
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Search" /v BingSearchEnabled /t REG_DWORD /d 0 /f
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Search" /v AllowSearchToUseLocation /t REG_DWORD /d 0 /f
    reg add "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Search" /v CortanaConsent /t REG_DWORD /d 0 /f
    # Parametres de Windows
    reg add "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" /f /ve
    reg add "HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" /v AppCaptureEnabled /t REG_DWORD /d 00000000 /f
    reg add "HKEY_CURRENT_USER\System\GameConfigStore" /v GameDVR_Enabled /t REG_DWORD /d 00000000 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge" /v HubsSidebarEnabled /t REG_DWORD /d 00000000 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge" /v ShowRecommendationsEnabled /t REG_DWORD /d 00000000 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge" /v SpotlightExperiencesAndRecommendationsEnabled /t REG_DWORD /d 00000000 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Edge" /v DefaultBrowserSettingEnabled /t REG_DWORD /d 00000000 /f
    reg add "HKEY_CURRENT_USER\SOFTWARE\Policies\Microsoft\Windows\Explorer" /v DisableSearchBoxSuggestions /t REG_DWORD /d 00000001 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Dsh" /v AllowNewsAndInterests /t REG_DWORD /d 00000000 /f
    reg add "HKLM\System\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" /v Enabled /t REG_DWORD /d 0 /f
    reg add "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\DeviceGuard" /v EnableVirtualizationBasedSecurity /t REG_DWORD /d 0 /f
    reg add "HKEY_CURRENT_USER\Software\Policies\Microsoft\Windows\WindowsCopilot" /v TurnOffWindowsCopilot /t REG_DWORD /d 1 /f
    reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR" /v HistoricalCaptureEnabled /t REG_DWORD /d 0 /f
    # Parametres supplementaires
    reg add "HKLM\SYSTEM\Maps" /v AutoUpdateEnabled /t REG_DWORD /d 0 /f
    reg add "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize" /v EnableTransparency /t REG_DWORD /d 0 /f
    reg add "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" /v DODownloadMode /t REG_DWORD /d 0 /f
    reg add "HKCU\Software\Microsoft\Multimedia\Audio" /v "UserDuckingPreference" /t REG_DWORD /d 3 /f
    reg add "HKEY_LOCAL_MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System" /v DisableAutomaticRestartSignOn /t REG_DWORD /d 1 /f
    reg add "HKCU\Keyboard Layout\Toggle" /v "Language Hotkey" /t REG_SZ /d 3 /f
    reg add "HKCU\Keyboard Layout\Toggle" /v "Layout Hotkey" /t REG_SZ /d 3 /f
    # Desactiver l'hibernation
    REG ADD "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Power" /v HiberbootEnabled /t REG_DWORD /d 00000000 /f
    powercfg -h off
    # Desactiver SysMain (Superfetch)
    sc.exe stop "SysMain"
    sc.exe config "SysMain" start=disabled
    
    Write-Host "Parametres appliques avec succes." -ForegroundColor Green
    pause
    ```

### 3.10 🖥️ Désactivation de la Virtual Machine Platform (Conditionnel)

Si **A faire seulement si n'est pas utilisé :** virtualisation, Hyper-V, WSL2, émulateurs Android (WSA).

1.  Ouvrir **Windows Terminal** (admin).
2.  Exécuter :
    ```powershell
    DISM /Online /Disable-Feature /FeatureName:VirtualMachinePlatform /NoRestart
    ```

### 3.11 ⚙️ Configuration des Services (`msconfig`)

Désactiver des services non-Microsoft inutiles. **Attention.**

1.  `Win` + `R`, taper `msconfig`, Entrée.
2.  Onglet **"Services"**.
3.  Cocher **"Masquer tous les services Microsoft"**.
4.  Décochez les services **CONNUS** non nécessaires.
5.  **"Appliquer"** > **"OK"**.

### 3.12 🧹 Nettoyage Final

1.  **Redémarrer le PC**.
2.  Vider le dossier **"Téléchargements"**.
3.  `Win`, taper `Nettoyage de disque`, ouvrir.
    *   Sélectionner `C:`.
    *   Cliquer **"Nettoyer les fichiers système"**.
    *   Sélectionner `C:`.
    *   Cocher toutes les cases.
    *   Cliquer **"OK"**.
4.  Ouvrir **Windows Terminal** (admin), exécuter :
    ```powershell
    Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    ```

---

## 4. 👍 Bonnes Pratiques

*   **Pas de logiciels de "nettoyage/optimisation" tiers** (CCleaner, etc.).
*   **Pas d'antivirus tiers.** Microsoft Defender suffit.
*   **Garder Windows et les pilotes à jour.**
*   **PC portable :** Le laisser le plus possible branché sur secteur.

---

## 5. 💡 Optionnel

<details>
<summary><strong>5.1 Activer le Profil XMP/EXPO dans le BIOS</strong></summary>

Si RAM compatible XMP (Intel) ou EXPO (AMD) :
1.  Redémarrer, entrer BIOS/UEFI (`SUPPR`, `F2`, etc.).
2.  Chercher "Extreme Memory Profile (X.M.P.)", "AMD EXPO", "D.O.C.P.".
3.  Activer le profil.
4.  Sauvegarder et quitter.

</details>

<details>
<summary><strong>5.2 Utiliser Autoruns pour gérer les applications au démarrage</strong></summary>

Outil avancé. **Utiliser avec prudence.**
1.  Télécharger Autoruns : [https://learn.microsoft.com/fr-fr/sysinternals/downloads/autoruns](https://learn.microsoft.com/fr-fr/sysinternals/downloads/autoruns)
2.  Lancer `Autoruns.exe` (admin).
3.  Onglet "Logon". Décocher entrées non souhaitées. **Ne rien décocher sans être sûr.**
    (Menu "Options" > "Hide Microsoft Entries" et "Hide Windows Entries" recommandé).

</details>

<details>
<summary><strong>5.3 Installer et Configurer WSL2 (Windows Subsystem for Linux)</strong></summary>

1.  Ouvrir **Windows Terminal** (admin).
2.  Activer les fonctionnalités :
    ```powershell
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
    ```
3.  Redémarrer si c'est demandé.
4.  Installer WSL et Ubuntu : `wsl --install`
    Définir WSL2 par défaut : `wsl --set-default-version 2`
5.  Configurer nom d'utilisateur/mot de passe Linux.

6.  **Dans terminal Ubuntu**, mettre à jour :
    ```bash
    sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y && sudo apt autoclean -y
    ```
7.  Installer outils utiles (optionnel) :
    ```bash
    sudo apt-get install -y vim nano build-essential gcc make xsel
    ```

8.  **Configuration simple `~/.vimrc` (éditeur Vim) :**
    Ouvrir/créer `vim ~/.vimrc`, `i`, coller, `Esc`, `:wq`, Entrée.
    ```vimrc
    filetype plugin indent on
    syntax on
    set encoding=utf-8
    set number
    set wildmenu
    set lazyredraw
    set showmatch
    set cmdheight=1
    set ruler
    set tabstop=4
    set shiftwidth=4
    set softtabstop=4
    set shiftround
    set expandtab
    set autoindent
    set smartindent
    set incsearch
    set hlsearch
    if $COLORTERM == 'gnome-terminal' || $COLORTERM == 'truecolor' || $TERM_PROGRAM == 'vscode'
        set t_Co=256
    endif
    set scrolloff=3
    set sidescrolloff=7
    set wrap
    set backspace=indent,eol,start
    ```

</details>

---
