# Installation propre et optimisée de Windows 11 (FR)

Ce guide détaille les étapes pour installer ou réinstaller Windows 11 de manière propre, optimisée et sans risques de tout casser en faisant des manipulation dangereuses.

**⚠️ Avertissement :**
Suivez ce guide attentivement. Ces manipulations sont effectuées sous votre responsabilité. Pensez à sauvegarder vos données importantes avant toute réinstallation.

---

## 1. 🛠️ Préparation

### 1.1 Sauvegarde (si réinstallation)

*   **Sauvegarder tous les fichiers importants** sur un support externe.
*   Ouvrir **Windows Terminal**, copier et conserver la clé d'installation de Windows :
        ```powershell
        (Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKey
        ```

### 1.2 Création du Support d'Installation de Windows 11

1.  Prendre une clé USB d'au minimum 8GB puis **sauvegarder ses fichiers** sur un autre support externe, son contenu sera effacé.
2.  Télécharger l'outil de création de support Microsoft :
    [https://www.microsoft.com/fr-fr/software-download/windows11](https://www.microsoft.com/fr-fr/software-download/windows11)
    (Option "Création d'un support d'installation de Windows 11").
3.  Lancer le logiciel, continuer, choisir "Disque mémoire flash USB" et séléctionner la clé.

### 1.3 Ajout du Fichier `autounattend.xml`

Le fichier `autounattend.xml` présent dans ce repository automatise de nombreuses étapes de l'installation (langue, EULA, compte local, suppression de bloatware, etc.).

1.  Télécharger `autounattend.xml` depuis la racine de ce repository GitHub.
2.  Déplacer `autounattend.xml` **à la racine** de la clé USB d'installation de Windows 11 (ne pas renommer le fichier).

### 1.4 Débrancher les Autres Disques (PC Fixe Uniquement)

Dans le cas où vous possédez plusieurs disques sur votre PC fixe, débrancher tout ceux qui ne sont pas celui sur lequel vous installez Windows.


---

## 2. 🚀 Installation de Windows 11

1.  Brancher la clé USB sur le PC puis redémarrer le PC.
2.  Accéder au **BIOS** au démarrage du PC (touches courantes à spam : `F10`, `F11`, `F12`, `SUPPR`, `ESC`).
3.  Sélectionner la clé USB comme périphérique de démarrage.
4.  L'installation de Windows 11 démarre. Si vous avez bien retiré tous les autres disques que celui sur lequel vous voulez installer Windows, faites un clic droit sur chaque partition du disque 0 puis supprimer, puis finalement séléctionnez la seule partition restante du disque 0 puis continuer.
5.  L'installation peut prendre quelques minutes, vous devrez rentrer un nom et un mot de passe pour créer un compte local.
6.  Rébrancher les autres disques un fois l'installation terminée (PC Fixe Uniquement).

---

## 3. ✨ Post-Installation et Optimisations

### 3.1 🔄 Mises à Jour Windows Update

1.  Ouvrir **Paramètres** > **Windows Update**.
2.  Cliquer sur **Rechercher des mises à jour** et installer.
3.  Redémarrer le PC.
4.  Répéter ces opérations jusqu'à ce qu'il n'y ait plus de mises à jour.

### 3.2 🌐 Installation et Configuration du Navigateur

1.  Ouvrir **Windows Terminal**.
2.  Installer un navigateur : 

    **Firefox** (Recommandé):
    ```powershell
    winget install --id=Mozilla.Firefox -e --accept-package-agreements
    ```
    **Google Chrome** :
    ```powershell
    winget install --id=Google.Chrome -e --accept-package-agreements
    ```
4.  Mettre à jour les paquets de toutes les applications :
    ```powershell
    winget upgrade --all --include-unknown --accept-package-agreements
    ```

#### 3.2.1 Configuration Spécifique pour Firefox

1.  **Installer les extensions :**
    *   [uBlock Origin](https://addons.mozilla.org/fr/firefox/addon/ublock-origin/)
    *   [ClearURLs](https://addons.mozilla.org/fr/firefox/addon/clearurls/)
    *   [Decentraleyes](https://addons.mozilla.org/fr/firefox/addon/decentraleyes/)
    *   [Privacy Badger](https://addons.mozilla.org/fr/firefox/addon/privacy-badger17/)
2.  **(Optionnel) Configurer uBlock Origin pour enlever les Shorts sur YouTube :**
    *   Ouvrir tableau de bord uBlock Origin (icône extension > engrenages).
    *   Onglet **"Mes filtres"**.
    *   Copier le contenu du fichier `ublock_filters.txt` (disponible dans ce repository) et coller.
    *   Cliquer sur **"Appliquer"**.

### 3.3 🧩 Mise à Jour des Pilotes

1.  Télécharger et lancer **UserDiag** : [https://userdiag.com/fr/](https://userdiag.com/fr/)
2.  Aller dans `Configuration PC` puis `Créer le rapport` et attendre.
3.  Repérer et copier `Model :`, le coller sur Google et aller sur le site du fabricant (carte mère ou PC portable).
4.  Installer les pilotes : prioriser les **pilotes de la carte mère** (chipset, audio, LAN), pas les utilitaires.

### 3.4 ⚙️ Installation et Configuration des Pilotes Graphiques

#### 3.4.1 Cartes NVIDIA

1.  Télécharger et installer **NVIDIA App** : [https://www.nvidia.com/fr-fr/software/nvidia-app/](https://www.nvidia.com/fr-fr/software/nvidia-app/)
2.  Ouvrir, aller à "Pilotes" et installer la dernière version.
3.  Clic droit Bureau > **Plus d’options** > **Panneau de configuration NVIDIA**.
    *   Menu **Bureau** > Décochez **"Afficher l'icône de la zone de notification GPU"**.
    *   **Paramètres 3D > Régler les paramètres d'image...** > Cocher **"Utiliser mes préférences..."** > Curseur sur **"Performances"**.
    *   **Paramètres 3D > Gérer les paramètres 3D** :
        *   **Mode de faible latence** > **"Activé"**.
        *   **PC fixe : Mode de gestion de l'alimentation** > **"Privilégier les performances maximales"**.
        *   **PC portable :** Laisser "Normal" ou "Optimisé". Configurer "Privilégier les performances maximales" par jeu (dans l'onglet "Paramètres de programmes" ou NVIDIA App) si joué sur secteur.

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
*   **Système > Notifications** : Tout désactiver dans chaque catégories.
*   **Personnalisation > Parametres de saisie** :
    *   Décocher `Corriger automatiquement les fautes d’orthographe`.
    *   Décocher `Mettre en surbrillance les mots mal orthographiés`.
*   **Personnalisation > Démarrer** : Cocher **"Autres éléments épinglés"**.
*   **Personnalisation > Utilisation des appareils** : Décocher tout.
*   **Applications > Démarrage** : Désactiver les applications inutiles.
*   **Jeux > Xbox Game Bar** : Décocher.
*   **Confidentialité et sécurité > Général** : Décocher tout.
*   **Confidentialité et sécurité > Entrée manuscrite et personnalisation de la saisie** : Décocher.
*   **Confidentialisation et sécurité > Diagnostics et commentaires** :
    *   `Fréquence des commentaires` > **"Jamais"**.
*   **Confidentialité et sécurité > Autorisations de recherche** :
    *   Tout décocher

Personnaliser l'**Apparence** (Thèmes, Couleurs, Fond d'écran) dans **Personnalisation**.

### 3.7 📚 Installation des Bibliothèques C++

1.  Télécharger "Visual C++ Redistributable Runtimes All-in-One" de TechPowerUp :
    [https://www.techpowerup.com/download/visual-c-redistributable-runtime-package-all-in-one/](https://www.techpowerup.com/download/visual-c-redistributable-runtime-package-all-in-one/)
2.  Décompresser le dossier.
3.  **Exécuter en tant qu'administrateur** `install_all.bat`.

### 3.8 📜 Optimisations de paramètres

Ouvrir **Windows Terminal** (admin) et copier puis coller le texte ci-dessous :

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
    reg add "HKCU\Control Panel\Mouse" /v MouseSpeed /t REG_SZ /d "0" /f
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

### 3.9 🖥️ Désactivation de la Virtual Machine Platform (Conditionnel)

⚠️ **A faire seulement si n'est pas utilisé :** WSL2, virtualisation, Hyper-V, émulateurs Android (WSA, Bluestack...).

Ouvrir **Windows Terminal** (admin) et Exécuter : 
    ```powershell
    DISM /Online /Disable-Feature /FeatureName:VirtualMachinePlatform /NoRestart
    ```

### 3.10 ⚙️ Configuration des Services au Démarrage

Après avoir installé toutes vos applications, désactivez les services inutiles au démarrage. **Attention.**

1.  **Paramètres > Applications > Démarrage > Décocher toutes les applications connues non nécéssaires au démarrage de l'ordinateur** :
2.  `Win`, recherchez `Configuration du système`.
3.  Onglet **"Services"**.
4.  Cocher en bas **"Masquer tous les services Microsoft"**.
5.  Décochez les services **CONNUS** non nécessaires au démmarage. (Ne décochez pas les services inconnus, la colonne `Fabricant` peut vous aider)
6.  **"Appliquer"** > **"Redémarrer"**.

### 3.11 🧹 Nettoyage Final

1. Vider le dossier **"Téléchargements"**.
2.  `Win`, recherchez `Nettoyage de disque`.
    *   Cochez toutes les catégories
    *   Cliquez sur *"Nettoyer les fichiers système"**.
    *   Cochez toutes les catégories
    *   Cliquez sur **"OK"**.
3.  Ouvrir **Windows Terminal** (admin), exécuter :
    ```powershell
    Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    ```

---

## 4. 👍 Bonnes Pratiques

*   **Pas de logiciels de "nettoyage/optimisation" tiers** (CCleaner, etc.).
*   **Pas d'antivirus**, Microsoft Defender suffit.
*   **Garder Windows et les pilotes à jour.**

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
