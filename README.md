# Installation / Réinstallation Propre et Optimisée de Windows 11

Bienvenue sur ce guide pour installer ou réinstaller Windows 11 de manière propre, optimisée et sans risques de casser des choses dans votre système. Ce tutoriel vous accompagnera pas à pas, de la préparation de votre support d'installation à la configuration finale de votre système.

Ce repository contient :
*   Ce `README.md` (le guide).
*   Un fichier `autounattend.xml` : Ce fichier permet d'automatiser une grande partie de l'installation de Windows 11, en configurant des paramètres par défaut, en supprimant les logiciels superflus (bloatware), en contournant les vérifications de compatibilité matérielle (TPM, Secure Boot, RAM minimale), en configurant les paramètres de confidentialité et en appliquant diverses optimisations dès l'installation.
*   Un fichier `ublock_filters.txt` : Contient une liste de filtres personnalisés pour l'extension uBlock Origin, notamment pour améliorer l'expérience sur YouTube.
*   Un fichier `optimisations_registre.ps1` : Un script PowerShell regroupant de nombreuses modifications du registre pour optimiser et personnaliser Windows.

**Lien du Repository GitHub :** [https://github.com/tsunooky/InstallationWindows](https://github.com/tsunooky/InstallationWindows)

---

**⚠️ Avertissement :**
Suivez ce guide attentivement et effectuez ces manipulations sous votre propre responsabilité. Pensez à sauvegarder vos données importantes avant toute réinstallation.

---

## Table des Matières

1.  [Prérequis](#prérequis)
2.  [Préparation](#préparation)
    *   [2.1 Sauvegardes (Si Réinstallation)](#21-sauvegardes-si-réinstallation)
    *   [2.2 Création du Support d'Installation de Windows 11](#22-création-du-support-dinstallation-de-windows-11)
    *   [2.3 Ajout du Fichier `autounattend.xml`](#23-ajout-du-fichier-autounattendxml)
3.  [Installation de Windows 11](#installation-de-windows-11)
4.  [Post-Installation et Optimisations](#post-installation-et-optimisations)
    *   [4.1 Mises à Jour Windows Update](#41-mises-à-jour-windows-update)
    *   [4.2 Installation et Configuration du Navigateur](#42-installation-et-configuration-du-navigateur)
    *   [4.3 Mise à Jour des Pilotes (Général)](#43-mise-à-jour-des-pilotes-général)
    *   [4.4 Installation et Configuration des Pilotes Graphiques](#44-installation-et-configuration-des-pilotes-graphiques)
    *   [4.5 Mode de Gestion d'Alimentation (PC Fixe Uniquement)](#45-mode-de-gestion-dalimentation-pc-fixe-uniquement)
    *   [4.6 Optimisations des Paramètres Windows](#46-optimisations-des-paramètres-windows)
    *   [4.7 Installation des Bibliothèques C++](#47-installation-des-bibliothèques-c)
    *   [4.8 Installation Rapide d'Applications (Ninite)](#48-installation-rapide-dapplications-ninite)
    *   [4.9 Optimisations via Registre (Script PowerShell)](#49-optimisations-via-registre-script-powershell)
    *   [4.10 Désactivation de la Virtual Machine Platform (Conditionnel)](#410-désactivation-de-la-virtual-machine-platform-conditionnel)
    *   [4.11 Configuration des Services (`msconfig`)](#411-configuration-des-services-msconfig)
    *   [4.12 Nettoyage Final](#412-nettoyage-final)
5.  [Bonnes Pratiques](#bonnes-pratiques)
6.  [Optionnel](#optionnel)
    *   [6.1 Activer le Profil XMP/EXPO dans le BIOS](#61-activer-le-profil-xmpexpo-dans-le-bios)
    *   [6.2 Utiliser Autoruns pour Gérer les Démarrages](#62-utiliser-autoruns-pour-gérer-les-démarrages)
    *   [6.3 Installer et Configurer WSL2 (Windows Subsystem for Linux)](#63-installer-et-configurer-wsl2-windows-subsystem-for-linux)

---

## 1. Prérequis

Avant de commencer, assurez-vous d'avoir :
*   Une **clé USB vierge** d'au moins **8 Go**.
*   Le fichier `autounattend.xml` téléchargé depuis [ce repository GitHub](https://github.com/tsunooky/InstallationWindows/blob/main/autounattend.xml) (cliquez sur "Raw" puis faites un clic droit "Enregistrer sous").
*   Une connexion Internet pour les téléchargements (pilotes, mises à jour, logiciels).

---

## 2. Préparation

### 2.1 Sauvegardes (Si Réinstallation)

Si vous réinstallez Windows sur un PC déjà utilisé :

*   **Sauvegardez vos fichiers importants** (documents, photos, vidéos, etc.) sur un disque dur externe ou un service de stockage en ligne.
*   **Sauvegardez votre clé d'installation Windows** (si vous en avez une et qu'elle n'est pas liée à votre compte Microsoft ou intégrée au firmware de votre PC) :
    1.  Ouvrez **Windows Terminal** (ou PowerShell / Invite de commandes) en tant qu'administrateur.
    2.  Copiez et collez la commande suivante, puis appuyez sur Entrée :
        ```powershell
        (Get-WmiObject -query 'select * from SoftwareLicensingService').OA3xOriginalProductKey
        ```
    3.  Copiez la clé affichée et conservez-la précieusement.

### 2.2 Création du Support d'Installation de Windows 11

1.  Téléchargez l'outil de création de support d'installation de Windows 11 depuis le site officiel de Microsoft :
    [https://www.microsoft.com/fr-fr/software-download/windows11](https://www.microsoft.com/fr-fr/software-download/windows11)
    (Choisissez l'option "Création d'un support d'installation de Windows 11" et téléchargez l'outil "MediaCreationToolW11.exe").
2.  Lancez l'outil téléchargé (`MediaCreationToolW11.exe`).
3.  Acceptez les termes du contrat de licence.
4.  Décochez la case "Utiliser les options recommandées pour ce PC".
5.  Sélectionnez la langue "Français (France)" et l'édition "Windows 11".
6.  Choisissez "Disque mémoire flash USB" comme support à utiliser.
7.  Sélectionnez votre clé USB dans la liste (assurez-vous qu'elle est bien vide ou que son contenu peut être effacé).
8.  Laissez l'outil télécharger Windows 11 et préparer votre clé USB.

### 2.3 Ajout du Fichier `autounattend.xml`

1.  Une fois votre clé USB d'installation de Windows 11 prête, téléchargez le fichier `autounattend.xml` depuis [ce repository GitHub](https://github.com/tsunooky/InstallationWindows/blob/main/autounattend.xml).
2.  Copiez le fichier `autounattend.xml` que vous venez de télécharger et collez-le **à la racine** de votre clé USB d'installation de Windows 11.

    *Note : Ce fichier `autounattend.xml` va automatiser de nombreuses étapes de l'installation, configurer la langue, le fuseau horaire, accepter l'EULA, ignorer la création d'un compte Microsoft en ligne (proposant un compte local), contourner les exigences matérielles de Windows 11 (TPM 2.0, Secure Boot, RAM), supprimer de nombreux logiciels préinstallés (bloatware) et appliquer des réglages de base pour une expérience plus propre.*

---

## 3. Installation de Windows 11

1.  Branchez la clé USB d'installation sur le PC où vous souhaitez installer Windows 11.
2.  Redémarrez le PC.
3.  Dès le démarrage, appuyez de manière répétée sur la touche permettant d'accéder au **Menu de Démarrage (Boot Menu)** ou au **BIOS/UEFI**. Les touches courantes sont `F11`, `F12`, `F8`, `SUPPR (DEL)`, `ESC`. Consultez le manuel de votre carte mère ou le site du fabricant de votre PC si besoin.
4.  Dans le menu de démarrage (ou dans l'ordre de démarrage du BIOS/UEFI), sélectionnez votre clé USB comme périphérique de démarrage principal.
5.  L'installation de Windows 11 devrait commencer. Grâce au fichier `autounattend.xml`, de nombreuses étapes seront automatisées. Vous pourriez être invité à choisir la partition d'installation ou à entrer le nom de l'ordinateur. Suivez les instructions à l'écran.
6.  L'installation va copier les fichiers et redémarrer le PC plusieurs fois.
7.  **IMPORTANT :** Lors du premier redémarrage demandé par l'installeur (généralement après la phase de copie des fichiers, un compte à rebours de 10 secondes peut apparaître), **retirez la clé USB** pour éviter de redémarrer sur l'installeur.
8.  Laissez Windows terminer l'installation. Vous serez guidé pour la création de votre compte utilisateur local et la configuration finale.

---

## 4. Post-Installation et Optimisations

Une fois Windows 11 installé et le bureau accessible :

### 4.1 Mises à Jour Windows Update

Il est crucial d'installer toutes les mises à jour disponibles :
1.  Ouvrez les **Paramètres** (touche `Win` + `I`).
2.  Allez dans **Windows Update**.
3.  Cliquez sur **Rechercher des mises à jour**.
4.  Installez toutes les mises à jour proposées, y compris les mises à jour facultatives (surtout les pilotes).
5.  Redémarrez votre PC si nécessaire.
6.  Répétez les étapes 3 à 5 jusqu'à ce qu'il n'y ait plus aucune mise à jour disponible.

### 4.2 Installation et Configuration du Navigateur

Nous allons utiliser `winget` (le gestionnaire de paquets Windows) pour installer votre navigateur.

1.  Ouvrez **Windows Terminal** en tant qu'administrateur (clic droit sur le menu Démarrer > Windows Terminal (admin)).
2.  Pour installer **Google Chrome**, tapez :
    ```powershell
    winget install --id=Google.Chrome -e
    ```
    OU pour installer **Mozilla Firefox**, tapez :
    ```powershell
    winget install --id=Mozilla.Firefox -e
    ```
    *(L'option `-e` signifie `exact` pour correspondre précisément à l'ID)*
3.  Une fois le navigateur installé, mettez à jour toutes les applications installées via winget (y compris le gestionnaire de paquets lui-même) :
    ```powershell
    winget upgrade --all --include-unknown --accept-package-agreements
    ```
4.  Définissez votre navigateur fraîchement installé comme navigateur par défaut :
    *   **Paramètres** > **Applications** > **Applications par défaut**.
    *   Recherchez et sélectionnez votre navigateur (Chrome ou Firefox).
    *   Pour chaque type de fichier et de lien (HTTP, HTTPS, .html, .htm, etc.), cliquez dessus et choisissez votre navigateur préféré.

#### 4.2.1 Configuration Spécifique pour Firefox (Si vous l'avez choisi)

1.  **Installez les extensions recommandées** pour améliorer la confidentialité et l'expérience de navigation :
    *   [uBlock Origin](https://addons.mozilla.org/fr/firefox/addon/ublock-origin/)
    *   [ClearURLs](https://addons.mozilla.org/fr/firefox/addon/clearurls/)
    *   [Decentraleyes](https://addons.mozilla.org/fr/firefox/addon/decentraleyes/)
    *   [Privacy Badger](https://addons.mozilla.org/fr/firefox/addon/privacy-badger17/)
2.  **Configuration uBlock Origin pour bloquer les "Shorts" YouTube et autres éléments indésirables :**
    *   Ouvrez le tableau de bord de uBlock Origin (cliquez sur l'icône de l'extension > icône des engrenages).
    *   Allez dans l'onglet **"Mes filtres"**.
    *   Copiez l'intégralité du contenu du fichier `ublock_filters.txt` (disponible [ici](https://github.com/tsunooky/InstallationWindows/blob/main/ublock_filters.txt) dans le repository) et collez-le dans la zone de texte.
    *   Cliquez sur **"Appliquer"**.

### 4.3 Mise à Jour des Pilotes (Général)

Même si Windows Update en installe certains, il est bon de vérifier :
1.  Téléchargez et lancez **UserDiag** : [https://userdiag.com/fr/](https://userdiag.com/fr/)
2.  Installez l'outil, lancez une analyse et cliquez sur **"Afficher la configuration en ligne"**.
3.  Le site vous proposera des liens vers les pilotes les plus récents pour vos composants.
4.  Concentrez-vous sur les **pilotes de la carte mère** (chipset, audio, LAN, etc.). Téléchargez-les depuis le site du fabricant de votre carte mère (pour un PC fixe) ou du fabricant de votre PC (pour un PC portable).

### 4.4 Installation et Configuration des Pilotes Graphiques

#### 4.4.1 Pour les Cartes Graphiques NVIDIA

1.  Téléchargez et installez **NVIDIA App** (qui remplace GeForce Experience) :
    [https://www.nvidia.com/fr-fr/software/nvidia-app/](https://www.nvidia.com/fr-fr/software/nvidia-app/)
2.  Ouvrez NVIDIA App et connectez-vous si vous le souhaitez (ou ignorez). Allez dans la section "Pilotes" et installez la dernière version disponible.
3.  Une fois les pilotes installés, faites un clic droit sur le Bureau > **Plus d’options** (si sous-menu) > **Panneau de configuration NVIDIA**.
4.  Dans le Panneau de configuration NVIDIA :
    *   Menu **Bureau** (en haut) > Décochez **"Afficher l'icône de la zone de notification GPU"**.
    *   Allez dans **Paramètres 3D** > **Régler les paramètres d'image avec aperçu**.
        *   Cochez **"Utiliser mes préférences pour améliorer :"**
        *   Déplacez le curseur complètement vers la gauche sur **"Performances"**.
    *   Allez dans **Paramètres 3D** > **Gérer les paramètres 3D** :
        *   Trouvez l'option **"Mode de faible latence"** et mettez-la sur **"Activé"** (ou "Ultra" si disponible et que vous le souhaitez, mais "Activé" est un bon compromis).
        *   **Si PC fixe :** Trouvez l'option **"Mode de gestion de l'alimentation"** et mettez-la sur **"Privilégier les performances maximales"**.
        *   **Si PC portable :** Il est généralement préférable de laisser le "Mode de gestion de l'alimentation" sur "Normal" ou "Optimisé" pour économiser la batterie. Vous pourrez le régler sur "Privilégier les performances maximales" spécifiquement pour chaque jeu via l'onglet "Paramètres de programmes" dans "Gérer les paramètres 3D", ou via NVIDIA App pour les jeux qui seront joués lorsque le PC est branché sur secteur.

#### 4.4.2 Pour les Cartes Graphiques AMD

1.  Téléchargez les derniers pilotes depuis le site officiel d'AMD :
    [https://www.amd.com/en/support/download/drivers.html](https://www.amd.com/en/support/download/drivers.html)
    (Utilisez l'outil de détection automatique ou sélectionnez votre modèle manuellement).
2.  Installez les pilotes.
3.  Explorez le logiciel Adrenalin Edition pour des optimisations similaires (Anti-Lag, Radeon Boost, etc.).
    *(Section à compléter avec des réglages spécifiques AMD si disponibles)*

### 4.5 Mode de Gestion d'Alimentation (PC Fixe Uniquement)

Pour les PC de bureau, un mode d'alimentation performant peut être bénéfique.
1.  Appuyez sur la touche `Win`, tapez `alimentation` et ouvrez **"Choisir un mode de gestion d'alimentation"**.
2.  Sélectionnez le mode approprié :
    *   **CPU Intel 11ème génération et plus anciens :** Choisissez "Hautes performances" ou "Performances optimales" (si disponible).
    *   **CPU Intel 12ème génération et plus récents :** Choisissez "Hautes performances".
    *   **CPU AMD Ryzen 3000 series et plus anciens :** Recherchez et installez les pilotes du chipset AMD depuis le site d'AMD, qui incluent souvent un mode "AMD Ryzen Balanced". Sinon, "Hautes performances".
    *   **CPU AMD Ryzen 5000 series et plus récents :** Le mode "Utilisation normale" est souvent suffisant. Vous pouvez ajuster le curseur de performance dans **Paramètres > Système > Alimentation et batterie** (si disponible) ou choisir "Hautes performances".

### 4.6 Optimisations des Paramètres Windows

Naviguez dans les paramètres de Windows pour désactiver des fonctionnalités inutiles ou gourmandes.
Ouvrez les **Paramètres** (`Win` + `I`) :

*   **Système > Écran > Graphiques** (tout en bas) > **Modifier les paramètres graphiques par défaut** :
    *   Décochez `Planification de processeur graphique à accélération matérielle`.
    *   Cochez `Optimisations pour les jeux en fenêtre`.
*   **Système > Son > Autres paramètres audio** (ou `Panneau de configuration` > `Son`) :
    *   Pour chaque périphérique de lecture et d'enregistrement, allez dans ses `Propriétés` > onglet `Améliorations` (ou `Effets sonores` / `Traitement du signal audio`).
    *   Cochez **"Désactiver toutes les améliorations"** (ou équivalent).
*   **Système > Notifications** :
    *   Désactivez les notifications pour les applications qui ne vous sont pas utiles. Parcourez la liste et désactivez individuellement.
*   **Personnalisation > Saisie** (ou `Heure et langue > Saisie > Paramètres de clavier avancés` puis cherchez les options de correction) :
    *   Décochez `Corriger automatiquement les fautes d’orthographe`.
    *   Décochez `Mettre en surbrillance les mots mal orthographiés`. (Optionnel, selon préférence)
*   **Personnalisation > Démarrer** :
    *   Désactivez les recommandations, les applications récemment ajoutées, etc., selon vos préférences. Cochez **"Afficher plus d’éléments épinglés"** si vous préférez plus d'espace pour vos icônes.
*   **Personnalisation > Barre des tâches > Éléments de la barre des tâches** :
    *   Décochez `Conversation (Microsoft Teams)`, `Widgets`, `Affichage des tâches`, `Recherche` (peut être remplacé par une icône si vous préférez).
*   **Personnalisation > Utilisation de l’appareil** :
    *   Décochez toutes les catégories si vous ne souhaitez pas que Windows personnalise les suggestions en fonction de votre utilisation.
*   **Applications > Applications pour les sites web** :
    *   Désactivez les applications que vous ne souhaitez pas voir s'ouvrir automatiquement pour certains sites web.
*   **Applications > Démarrage** :
    *   Désactivez les applications inutiles qui se lancent au démarrage de Windows pour accélérer le démarrage.
*   **Jeux > Xbox Game Bar** :
    *   Décochez l'interrupteur principal **"Activer Xbox Game Bar..."** si vous ne l'utilisez pas.
*   **Jeux > Mode Jeu** :
    *   Assurez-vous qu'il est **coché (Activé)**.
*   **Confidentialité et sécurité > Général** :
    *   Décochez toutes les options (identifiant de publicité, suivi de lancement d'applications, etc.).
*   **Confidentialité et sécurité > Entrée manuscrite et personnalisation de la saisie** :
    *   Désactivez si vous n'utilisez pas la reconnaissance d'écriture ou la personnalisation de la saisie.
*   **Confidentialité et sécurité > Diagnostics et commentaires** :
    *   Désactivez `Envoyer des données de diagnostic facultatives`.
    *   Mettez `Fréquence des commentaires` sur **"Jamais"**.
    *   Désactivez `Expériences personnalisées`.
*   **Confidentialité et sécurité > Historique des activités** :
    *   Décochez `Stocker l’historique de mes activités sur cet appareil`.
    *   Cliquez sur `Effacer l'historique des activités`.
*   **Confidentialité et sécurité > Voix** :
    *   Désactivez `Reconnaissance vocale en ligne` si vous n'utilisez pas la dictée vocale de Windows.
*   **Confidentialité et sécurité > Autorisations de recherche** :
    *   Mettez `Filtrage du contenu pour adultes` sur `Strict` ou `Désactivé` selon votre choix.
    *   Plus bas, dans `Recherche dans le cloud`, désactivez les options de recherche de contenu cloud si vous ne le souhaitez pas.
    *   Dans `Plus de paramètres`, désactivez `Afficher les mots clés de recherche`.

N'oubliez pas de personnaliser l'**Apparence** (Thèmes, Couleurs, Fond d'écran) dans **Personnalisation** selon vos goûts.

### 4.7 Installation des Bibliothèques C++

Pour éviter les problèmes de compatibilité avec certains jeux et applications :
1.  Téléchargez le "Visual C++ Redistributable Runtimes All-in-One" de TechPowerUp :
    [https://www.techpowerup.com/download/visual-c-redistributable-runtime-package-all-in-one/](https://www.techpowerup.com/download/visual-c-redistributable-runtime-package-all-in-one/)
    (Prenez la dernière version disponible).
2.  Décompressez l'archive téléchargée.
3.  Faites un clic droit sur le fichier `install_all.bat` et sélectionnez **"Exécuter en tant qu'administrateur"**.
4.  Laissez le script installer toutes les bibliothèques.

### 4.8 Installation Rapide d'Applications (Ninite)

Pour installer rapidement plusieurs applications courantes sans barres d'outils ni logiciels publicitaires :
1.  Allez sur [https://ninite.com/](https://ninite.com/)
2.  Cochez les applications que vous souhaitez installer (ex : 7-Zip, VLC, Steam, Discord, etc.).
3.  Cliquez sur **"Get Your Ninite"**.
4.  Téléchargez et exécutez le programme d'installation personnalisé. Il installera tout automatiquement.

### 4.9 Optimisations via Registre (Script PowerShell)

Un script PowerShell est fourni dans ce repository pour appliquer diverses optimisations et réglages de confidentialité/fonctionnalités.
1.  Téléchargez le fichier `optimisations_registre.ps1` depuis [ce repository GitHub](https://github.com/tsunooky/InstallationWindows/blob/main/optimisations_registre.ps1).
2.  Ouvrez **Windows Terminal** en tant qu'administrateur.
3.  Naviguez jusqu'au dossier où vous avez téléchargé le script. Par exemple, s'il est dans `C:\Users\VotreNom\Downloads` :
    ```powershell
    cd C:\Users\VotreNom\Downloads
    ```
4.  Exécutez le script :
    ```powershell
    .\optimisations_registre.ps1
    ```
    Si vous rencontrez une erreur concernant la politique d'exécution, vous devrez peut-être l'autoriser temporairement :
    ```powershell
    Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process -Force
    .\optimisations_registre.ps1
    ```
    Puis, si vous le souhaitez, remettez la politique par défaut après exécution :
    ```powershell
    Set-ExecutionPolicy -ExecutionPolicy Default -Scope Process -Force
    ```
    Ce script va notamment :
    *   Configurer l'Assistant de stockage.
    *   Désactiver la transparence des fenêtres (pour la performance).
    *   Optimiser le Delivery Optimization.
    *   Désactiver la réduction du volume audio lors des communications.
    *   Améliorer la précision de la souris (désactiver l'accélération).
    *   Appliquer divers paramètres de confidentialité et désactiver des fonctionnalités Windows (télémétrie, suggestions, GameDVR, Copilot, etc.).
    *   Désactiver l'Hibernation et le service SysMain (Superfetch).

### 4.10 Désactivation de la Virtual Machine Platform (Conditionnel)

Si vous ne prévoyez **PAS** d'utiliser de la virtualisation (comme Hyper-V, WSL2, émulateurs Android type WSA, etc.), vous pouvez désactiver cette fonctionnalité pour potentiellement libérer des ressources et éviter des conflits avec certains anti-cheats de jeux.
*   **Attention :** Si vous comptez utiliser WSL2 (voir section Optionnel), **NE PAS FAIRE CETTE ÉTAPE**.

1.  Ouvrez **Windows Terminal** en tant qu'administrateur.
2.  Tapez la commande suivante :
    ```powershell
    DISM /Online /Disable-Feature /FeatureName:VirtualMachinePlatform /NoRestart
    ```
    Un redémarrage sera peut-être nécessaire plus tard pour que le changement soit complet.

### 4.11 Configuration des Services (`msconfig`)

Vous pouvez désactiver certains services non-Microsoft inutiles au démarrage. **Soyez prudent**, ne désactivez que les services que vous connaissez et dont vous êtes sûr qu'ils ne sont pas essentiels.

1.  Appuyez sur `Win` + `R`, tapez `msconfig` et appuyez sur Entrée.
2.  Allez dans l'onglet **"Services"**.
3.  Cochez la case **"Masquer tous les services Microsoft"**.
4.  Parcourez la liste restante et décochez les services liés à des logiciels que vous n'utilisez plus ou dont vous n'avez pas besoin au démarrage (ex: services de mise à jour de logiciels tiers si vous préférez les faire manuellement).
5.  Cliquez sur **"Appliquer"** puis **"OK"**. Un redémarrage sera proposé.

### 4.12 Nettoyage Final

1.  **Redémarrez votre PC** pour que tous les changements prennent effet.
2.  Supprimez les fichiers temporaires et d'installation :
    *   Videz votre dossier **"Téléchargements"** des installeurs et fichiers temporaires.
    *   Appuyez sur `Win`, tapez `Nettoyage de disque` et ouvrez l'application.
    *   Sélectionnez votre disque `C:`.
    *   Cliquez sur **"Nettoyer les fichiers système"**.
    *   Sélectionnez à nouveau votre disque `C:`.
    *   Cochez toutes les cases (en particulier "Nettoyage de Windows Update", "Fichiers d'installation de Windows", etc.).
    *   Cliquez sur **"OK"**.
3.  Ouvrez **Windows Terminal** en tant qu'administrateur et exécutez :
    ```powershell
    Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    ```

---

## 5. Bonnes Pratiques

*   **Pas de logiciels de "nettoyage" ou d'"optimisation" tiers** (type CCleaner, IObit, etc.). Windows possède les outils nécessaires.
*   **Pas d'antivirus tiers.** Microsoft Defender (l'antivirus intégré à Windows) est suffisant pour la majorité des utilisateurs et bien intégré au système.
*   **Gardez Windows et vos pilotes à jour** en permanence.
*   Si vous avez un **PC portable, laissez-le branché sur secteur autant que possible** lorsque vous jouez ou effectuez des tâches gourmandes pour bénéficier des performances maximales et préserver la santé de la batterie sur le long terme (la plupart des portables modernes gèrent bien la charge).

---

## 6. Optionnel

Ces étapes sont facultatives et s'adressent à des utilisateurs plus avertis ou ayant des besoins spécifiques.

<details>
<summary><strong>6.1 Activer le Profil XMP/EXPO dans le BIOS</strong></summary>

Si votre mémoire RAM est compatible XMP (pour Intel) ou EXPO (pour AMD), activez ce profil dans le BIOS/UEFI de votre carte mère pour qu'elle fonctionne à sa fréquence et ses timings optimaux.
1.  Redémarrez votre PC et entrez dans le BIOS/UEFI (généralement touche `SUPPR`, `F2`, `F10`, `F12` ou `ESC` au démarrage).
2.  Cherchez une option nommée "Extreme Memory Profile (X.M.P.)", "AMD EXPO", "D.O.C.P.", ou similaire, souvent dans les sections "Overclocking", "Ai Tweaker", ou "Memory".
3.  Activez le profil correspondant (souvent "Profile 1").
4.  Sauvegardez les changements et quittez le BIOS.
    *Attention : Dans de rares cas, cela peut causer de l'instabilité si la mémoire ou la carte mère ne sont pas totalement compatibles. En cas de problème, retournez dans le BIOS et désactivez le profil.*

</details>

<details>
<summary><strong>6.2 Utiliser Autoruns pour Gérer les Démarrages</strong></summary>

Autoruns est un outil avancé de Microsoft Sysinternals qui montre en détail ce qui se lance au démarrage de votre système. **Utilisez-le avec une extrême prudence.**
1.  Téléchargez Autoruns : [https://learn.microsoft.com/fr-fr/sysinternals/downloads/autoruns](https://learn.microsoft.com/fr-fr/sysinternals/downloads/autoruns)
2.  Décompressez et lancez `Autoruns.exe` ou `Autoruns64.exe` en tant qu'administrateur.
3.  Dans l'onglet "Logon", vous pouvez décocher des entrées pour les empêcher de se lancer. **Ne décochez rien si vous n'êtes pas absolument certain de ce que vous faites, car cela pourrait rendre votre système instable.** Il est recommandé de cacher les entrées Microsoft via le menu "Options" > "Hide Microsoft Entries" et "Hide Windows Entries" pour ne voir que les éléments tiers.

</details>

<details>
<summary><strong>6.3 Installer et Configurer WSL2 (Windows Subsystem for Linux)</strong></summary>

WSL2 vous permet d'exécuter un environnement Linux directement sur Windows. Si vous avez désactivé "VirtualMachinePlatform" à l'étape 4.10, vous devrez le réactiver.

1.  Ouvrez **Windows Terminal** en tant qu'administrateur.
2.  Activez les fonctionnalités nécessaires (si ce n'est pas déjà fait via `autounattend.xml` ou si vous les avez désactivées) :
    ```powershell
    dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
    dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart
    ```
3.  Redémarrez votre PC si invité.
4.  Installez WSL et Ubuntu (la distribution par défaut) :
    ```powershell
    wsl --install
    ```
    Si vous avez déjà WSL1 et que vous voulez passer à WSL2 par défaut pour les nouvelles installations :
    ```powershell
    wsl --set-default-version 2
    ```
    Pour installer une distribution spécifique (par ex. Ubuntu) si `wsl --install` ne le fait pas :
    ```powershell
    wsl --install -d Ubuntu
    ```
5.  Une fois l'installation terminée, une fenêtre de terminal Ubuntu s'ouvrira pour configurer votre nom d'utilisateur et mot de passe Linux.

6.  **Dans le terminal Ubuntu**, mettez à jour votre système :
    ```bash
    sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y && sudo apt autoclean -y
    ```
7.  Installez quelques outils utiles (optionnel) :
    ```bash
    sudo apt-get install -y vim nano build-essential gcc make geany xsel
    ```

8.  **Configuration simple de `~/.vimrc` pour l'éditeur Vim (optionnel) :**
    Ouvrez (ou créez) le fichier avec `vim ~/.vimrc`, appuyez sur `i` pour passer en mode insertion, collez le texte suivant, puis appuyez sur `Esc` et tapez `:wq` puis Entrée pour sauvegarder et quitter.
    ```vimrc
    filetype plugin indent on
    syntax on
    set encoding=utf-8
    set number              " show line numbers
    set wildmenu            " visual autocomplete for command menu
    set lazyredraw          " redraw screen only when we need to
    set showmatch           " show matching brackets
    set cmdheight=1         " height of the command bar

    set ruler               " show line and column number of the cursor on right side of statusline

    set tabstop=4           " width that a <TAB> character displays as
    set shiftwidth=4        " number of spaces to use for each step of (auto)indent
    set softtabstop=4       " backspace after pressing <TAB> will remove up to this many spaces
    set shiftround          " rounds space ident to closest tab number
    set expandtab           " use spaces instead of tabs

    set autoindent          " copy indent from current line when starting a new line
    set smartindent         " even better autoindent (e.g. add indent after '{')

    set incsearch           " search as characters are entered
    set hlsearch            " highlight matches

    " Enable 256 colors palette in Gnome Terminal (or other compatible terminals)
    if $COLORTERM == 'gnome-terminal' || $COLORTERM == 'truecolor' || $TERM_PROGRAM == 'vscode'
        set t_Co=256
    endif

    " Sensible Defaults
    set scrolloff=3         " Keep 3 lines context above/below cursor when scrolling
    set sidescrolloff=7     " Keep 7 columns context left/right of cursor when side-scrolling
    set wrap                " Wrap long lines
    set backspace=indent,eol,start " Allow backspacing over everything in insert mode
    ```

</details>

---
