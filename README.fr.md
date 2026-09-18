# Écran tactile Surface sur Omarchy

Faire fonctionner l'écran tactile des anciens Microsoft Surface avec le noyau par défaut
d'[Omarchy](https://omarchy.org), `linux-omarchy`, sans passer au noyau `linux-surface`.

[English version](README.md)

## État

Testé sur :

| Quoi | Version |
|---|---|
| Appareil | Surface Pro 6 |
| Omarchy | 4.0.4 |
| Noyau | `linux-omarchy` 7.2.5-3 |
| iptsd | 3.1.0 |
| dkms | 3.4.3 |

L'appui court, le double appui, l'appui long, le défilement à 2 doigts, le pincement et 5 doigts
simultanés fonctionnent. Le stylet n'a pas été testé.

Ces appareils utilisent le même contrôleur tactile et devraient fonctionner, mais **n'ont pas été
testés**. Si tu en essaies un, ouvre une issue avec la sortie de `verify.sh` :
Surface Pro 4, Surface Pro 5, Surface Book 1, Surface Book 2, Surface Laptop 1, Surface Laptop 2.

**Non pris en charge :** Surface Pro 7 et plus récents. Leur contrôleur tactile demande d'autres
correctifs du noyau.

## Pourquoi c'est nécessaire

Sur une Surface Pro 6, le tactile a besoin de trois choses que `linux-omarchy` ne fournit pas :

1. **Un pilote.** Le pilote IPTS n'est pas dans le noyau officiel, seulement dans les correctifs
   [linux-surface](https://github.com/linux-surface/linux-surface). Ce projet le compile comme
   module externe avec DKMS, qui le recompile automatiquement à chaque mise à jour du noyau.
2. **Une correction pour Linux 7.2.** Linux 7.2 rejette les rapports HID plus courts que leur
   descripteur. Le pilote linux-surface 6.19 envoie de tels rapports, et chaque trame tactile
   échoue avec `Failed to process buffer: -22`. [Le correctif](patches/0001-ipts-adapt-to-linux-7.2-hid-input-report-checks.patch)
   transmet la vraie taille du tampon à `hid_safe_input_report()`, et le noyau complète le rapport
   au lieu de le rejeter. Sur les noyaux plus anciens, le module est compilé sans ce changement.
3. **L'IOMMU en mode passthrough pour le contrôleur tactile.** `linux-omarchy` active l'IOMMU
   Intel par défaut, ce qui bloque les tampons mémoire du contrôleur (erreurs DMAR). linux-surface
   corrige le noyau pour ça. Ici, un crochet `modprobe` passe uniquement le groupe IOMMU du
   contrôleur tactile en `identity`, juste avant le chargement de son pilote `mei_me`.

Les données tactiles sont ensuite traitées par [iptsd](https://github.com/linux-surface/iptsd),
le démon de linux-surface.

## Installation

```bash
git clone https://github.com/dplancy/omarchy-surface-touch.git
cd omarchy-surface-touch
sudo ./install.sh --dry-run   # facultatif : affiche ce qui sera fait
sudo ./install.sh
```

Redémarre ensuite sur `linux-omarchy` et vérifie que tout fonctionne :

```bash
sudo ./verify.sh
```

`verify.sh` contrôle d'abord le démarrage, puis te demande quelques gestes, 6 secondes chacun, et
affiche ce que libinput a reçu. Les messages du script sont en anglais. `--no-gestures` saute les
gestes. Les journaux sont enregistrés dans `logs/`.

### Ce que fait l'installeur

1. Il installe `dkms`, `linux-omarchy-headers` et `libinput-tools`.
2. Il installe `iptsd`, qui n'existe que dans le dépôt linux-surface. Si besoin, l'installeur
   demande avant d'ajouter ce dépôt. Il vérifie l'empreinte de la clé de signature
   (`87DEFA4AB94A99A4C8C3112556C464BAAC421453`) et ajoute le dépôt à `/etc/pacman.conf`, comme dans
   les [instructions linux-surface](https://github.com/linux-surface/linux-surface/wiki/Installation-and-Setup#arch).
   Il lance ensuite `pacman -Syu iptsd`, une mise à jour complète du système, car les mises à jour
   partielles ne sont pas prises en charge sur Arch. Seul `iptsd` vient de ce dépôt, ton noyau
   reste `linux-omarchy`.
3. Il installe un crochet Omarchy dans `~/.config/omarchy/hooks/pre-refresh-pacman.d/linux-surface-repo`.
   `omarchy refresh pacman` réécrit `/etc/pacman.conf`, et ce crochet y remet le dépôt
   linux-surface pour qu'`iptsd` continue d'être mis à jour.
4. Il copie le pilote dans `/usr/src/ipts-6.19.8.2` et le compile avec DKMS pour `linux-omarchy`.
   Les anciennes versions DKMS d'`ipts` ne sont supprimées qu'une fois la nouvelle compilation réussie.
5. Il installe le crochet IOMMU : `/etc/modprobe.d/ipts-iommu.conf` et
   `/usr/local/sbin/ipts-iommu-passthrough`.
6. Il vérifie que `mei_me` n'est pas dans l'initramfs, où le crochet ne pourrait pas s'exécuter.

Options : `--yes` (aucune question), `--force` (ignore les contrôles de l'appareil et du système),
`--dry-run`.

## Clavier virtuel (optionnel)

Sans le Type Cover, impossible de taper : `osk/` ajoute un clavier à l'écran.

- Quand un champ de texte prend le focus et qu'aucun clavier physique n'est branché, une petite
  icône clavier apparaît en bas à droite. **Touche-la** pour ouvrir ou fermer le clavier,
  **appuie longuement** pour passer de **AZERTY** à **QWERTY**. Le clavier se ferme quand le champ
  disparaît.
- Un bouton clavier dans la barre fait la même chose (clic droit : changer de disposition). Il sert
  pour les applis qui ne signalent pas leurs champs de texte.
- Sur **l'écran de verrouillage**, le clavier s'ouvre directement pour taper le mot de passe au doigt.
- Chaque touche montre ce qu'elle tape : le caractère Maj en haut à gauche, le caractère AltGr en
  haut à droite. Verrouiller AltGr (ou Maj) affiche ces caractères sur les touches. La touche
  **123** ouvre les chiffres, les symboles et Début/Fin/PgPréc/PgSuiv.
- Garder le doigt sur une touche la répète, comme sur un clavier physique.
- **Un appui** sur un modificateur (Maj, Ctrl, Super, Alt, AltGr) ne vaut que pour la touche
  suivante, **deux appuis** le verrouillent (un point l'indique), un appui de plus le relâche.
- Les couleurs suivent le thème Omarchy.

```bash
./osk/install.sh      # en tant qu'utilisateur, pas avec sudo
```

Fonctionnement : Omarchy fait déjà tourner fcitx5 (pour les séquences Compose), et fcitx5 sait quel
champ de texte a le focus. Le service utilisateur `omarchy-surface-osk` s'enregistre comme clavier
virtuel de fcitx5, surveille la présence d'un clavier et pilote
[wvkbd](https://github.com/jjsullivan5196/wvkbd), compilé avec des dispositions AZERTY et QWERTY générées depuis
les vraies dispositions xkb (`fr` et `us(altgr-intl)`, voir `osk/wvkbd/gen-layers.py`) et un petit
patch qui dessine les caractères Maj et AltGr sur les touches. L'icône et le bouton de la barre
sont un plugin du shell Omarchy.

L'installeur modifie, pour ton utilisateur seulement :

| Quoi | Où |
|---|---|
| wvkbd compilé et démon | `~/.local/lib/omarchy-surface-osk/`, `~/.local/bin/omarchy-surface-osk` |
| service utilisateur | `~/.config/systemd/user/omarchy-surface-osk.service` |
| plugin du shell `surface-touch.osk` | `~/.config/omarchy/plugins/surface-touch.osk/` |
| règle pour utiliser le clavier sur l'écran de verrouillage | `~/.config/hypr/surface-osk.lua`, une ligne `require` dans `hyprland.lua` |
| options IME pour que Chromium signale ses champs, seulement si ce fichier existe déjà | `~/.config/chromium-flags.conf` (redémarre Chromium) |
| les options ajoutées, pour que la désinstallation n'enlève que celles-là | `~/.config/omarchy-surface-osk/added-chromium-flags` |

Réglages dans `~/.config/omarchy-surface-osk/config.json` : `layout`, `height`,
`landscape_height`, `hide_on_blur`, `ignore_keyboards` (regex des claviers à ignorer).
Commandes : `omarchy-surface-osk show|hide|toggle|status`, `omarchy-surface-osk layout azerty|qwerty|toggle`.
Lancer le service avec `OSK_DEBUG=1` trace les événements de focus et les frappes dans le journal.

À savoir :
- Le Type Cover replié derrière l'écran compte toujours comme branché (Linux ne voit pas le pliage
  sans un autre correctif linux-surface). Dans cette position, utilise le bouton de la barre.
- Tant que le mode clavier virtuel est actif, les fenêtres de suggestions de fcitx5 (émojis, unicode)
  ne s'affichent pas.
- N'importe quel programme peut nommer sa surface `wvkbd` et serait alors aussi affiché au-dessus de
  l'écran de verrouillage.
- La phrase de passe du chiffrement au démarrage demande toujours un clavier physique.

Désinstallation : `./osk/uninstall.sh`.

## Rotation de l'écran (optionnel)

`rotate/` tourne l'écran selon la façon dont tu tiens la tablette, grâce à l'accéléromètre intégré :

- L'écran suit la tablette dans les quatre orientations, et ne bouge pas quand elle est à plat.
- Le tactile et le stylet tournent avec.
- La rotation se met en pause quand un clavier physique est branché (mode portable) et revient
  quand tu le détaches.
- Un bouton dans la barre verrouille la rotation, ou la réactive malgré le clavier branché. Un clic
  droit dessus revient en paysage.

```bash
./rotate/install.sh   # en tant qu'utilisateur, pas avec sudo
```

Fonctionnement : le service utilisateur `omarchy-surface-rotate` lit l'accéléromètre HID en sysfs
(`/sys/bus/iio/devices/*/name` = `accel_3d`), donc ni root ni `iio-sensor-proxy` ne sont
nécessaires. Il écrit la rotation, et la transformation correspondante du tactile et du stylet,
dans `~/.config/hypr/surface-rotate.lua` puis recharge Hyprland : sur la configuration Lua
d'Omarchy, `hyprctl keyword` et les appels `hl.monitor()` / `hl.config()` à chaud ne tiennent pas.

L'installeur modifie, pour ton utilisateur seulement :

| Quoi | Où |
|---|---|
| démon | `~/.local/lib/omarchy-surface-rotate/`, `~/.local/bin/omarchy-surface-rotate` |
| service utilisateur | `~/.config/systemd/user/omarchy-surface-rotate.service` |
| bouton de barre | `~/.config/omarchy/plugins/surface-touch.rotate/` |
| rotation courante | `~/.config/hypr/surface-rotate.lua`, une ligne `require` dans `hyprland.lua` |

Réglages dans `~/.config/omarchy-surface-rotate/config.json` : `output`, `mode`, `position`,
`scale` (ils doivent correspondre à ta configuration d'écran), `allow` (orientations autorisées),
`tilt_threshold`, `settle_ms`, `poll_ms`, `suspend_with_keyboard`, `ignore_keyboards`,
`transform_touch` (Hyprland ne tourne que l'image : le tactile et le stylet sont tournés aussi),
`touch_transforms` (si le tactile se retrouve tourné dans le mauvais sens) et `quarters`.
Commandes : `omarchy-surface-rotate status|toggle|enable|disable`,
`omarchy-surface-rotate normal|left|right|inverted` (tourner et verrouiller),
`omarchy-surface-rotate sensor` (afficher ce que rapporte l'accéléromètre).
Lancer le service avec `ROTATE_DEBUG=1` trace chaque décision dans le journal.

**Calibration.** `quarters` indique comment la tablette est tenue pour chaque axe sur lequel
l'accéléromètre trouve la gravité, dans l'ordre `[-y, +x, +y, -x]`. Lance
`omarchy-surface-rotate sensor` et tiens la tablette dans chaque orientation : la commande affiche
les trois axes et l'orientation retenue, ce qui montre quelle mesure correspond à quelle position.
Si l'écran tourne dans le mauvais sens, réordonne cette liste.

Désinstallation : `./rotate/uninstall.sh`.

## Luminosité automatique (optionnel)

`light/` fait suivre au rétroéclairage le capteur de lumière ambiante :

- L'écran s'éclaircit dehors et s'assombrit dans le noir, selon une courbe réglable.
- Ton réglage manuel gagne : le service se tait ensuite jusqu'à ce que la lumière change vraiment
  (un facteur deux par défaut), comme sur un téléphone.
- Un bouton dans la barre coupe ou réactive le tout.

```bash
./light/install.sh   # en tant qu'utilisateur, pas avec sudo
```

Fonctionnement : le service utilisateur `omarchy-surface-light` lit le capteur en sysfs
(`/sys/bus/iio/devices/*/name` = `als`) et pilote le rétroéclairage avec `brightnessctl` : ni root
ni `iio-sensor-proxy` ne sont nécessaires. La luminosité bouge par petits pas, ce qui évite qu'elle
clignote au moindre passage d'ombre.

L'installeur modifie, pour ton utilisateur seulement :

| Quoi | Où |
|---|---|
| démon | `~/.local/lib/omarchy-surface-light/`, `~/.local/bin/omarchy-surface-light` |
| service utilisateur | `~/.config/systemd/user/omarchy-surface-light.service` |
| bouton de barre | `~/.config/omarchy/plugins/surface-touch.light/` |

Réglages dans `~/.config/omarchy-surface-light/config.json` : `curve` (liste de points
`[lux, pourcentage]`), `bias` (décale toute la courbe, à ton goût), `min_percent`, `max_percent`,
`device`, `poll_ms`, `smoothing`, `jump_ratio`, `step_percent`, `deadband_percent` et
`resume_ratio` (de combien la lumière doit changer avant que le service reprenne la main).
Commandes : `omarchy-surface-light status|toggle|enable|disable`, et `omarchy-surface-light sensor`
pour voir le niveau de lumière à côté de la luminosité demandée par la courbe — c'est comme ça
qu'on vérifie la courbe.
Lancer le service avec `LIGHT_DEBUG=1` trace chaque décision dans le journal.

Désinstallation : `./light/uninstall.sh`.

## Gestes tactiles (optionnel)

Les gestes propres à Hyprland (`hl.gesture`, à trois doigts, etc.) ne fonctionnent **que sur pavé
tactile**. Sur écran tactile, il n'en offre qu'un : le balayage depuis le bord gauche ou droit pour
changer de bureau. Il s'active dans `~/.config/hypr/input.lua` :

```lua
hl.config({
  gestures = {
    workspace_swipe_touch = true,
    workspace_swipe_distance = 400,
    workspace_swipe_cancel_ratio = 0.3,
    workspace_swipe_forever = true,
  },
})
```

`gestures/` ajoute les deux qui manquent sur une tablette, sous forme de fines bandes le long des
bords :

- **Glisser vers le haut depuis le bord bas** : appelle le clavier virtuel. Quand il est ouvert, la
  bande se place juste au-dessus : un glissement vers le **bas** le referme.
- **Glisser vers le bas depuis le coin haut gauche** : ouvre le menu Omarchy.

```bash
./gestures/install.sh   # en tant qu'utilisateur, pas avec sudo
```

Les bandes font 12 px d'épaisseur et ne réagissent qu'à un glissement d'au moins 40 px : un appui
près d'un bord atteint toujours l'application en dessous. C'est un plugin du shell, installé dans
`~/.config/omarchy/plugins/surface-touch.gestures/` ; modifie `EdgeGestures.qml` (là ou dans
`gestures/plugin/`) pour changer l'épaisseur, la distance ou l'action des glissements.

Désinstallation : `./gestures/uninstall.sh`.

## Appui long = clic droit (optionnel)

Un écran tactile n'a pas de second bouton, et Hyprland n'offre rien pour ça : ses gestes sont
réservés au pavé tactile et `input.touchdevice` ne connaît que `enabled`, `output` et `transform`.
En dehors du compositeur, il faudrait lire `/dev/input` et écrire dans `/dev/uinput`, donc
appartenir au groupe `input` — c'est-à-dire laisser tout programme que tu lances lire ton clavier.
`longpress/` est donc un petit plugin Hyprland, là où les événements tactiles se trouvent déjà.

- Un doigt maintenu immobile une demi-seconde déclenche un clic droit là où il se trouve.
- Un déplacement de plus de 2 % de l'écran, ou un deuxième doigt, annule le geste : le défilement,
  les balayages et le pincement ne changent pas.

```bash
./longpress/install.sh   # en tant qu'utilisateur, pas avec sudo
```

Hyprland passe des objets C++ à ses plugins sans garantir la moindre stabilité d'ABI : le plugin est
donc **compilé sur ta machine, contre le Hyprland que tu utilises**, et doit être recompilé à chaque
mise à jour de Hyprland. L'installeur s'en charge : il garde la source à côté du binaire et installe
un hook `post-update` qui recompile après chaque `omarchy update`, en te disant ce qu'il en est. Tant
qu'il n'est pas recompilé, le plugin refuse simplement de se charger (il compare l'empreinte de
compilation) : une incompatibilité ne peut donc pas faire tomber le compositeur.

L'installeur modifie, pour ton utilisateur seulement :

| Quoi | Où |
|---|---|
| plugin, sa source et son script de compilation | `~/.local/lib/omarchy-surface-longpress/` |
| recompilation après une mise à jour | `~/.config/omarchy/hooks/post-update.d/omarchy-surface-longpress` |
| chargement au démarrage | `~/.config/hypr/surface-longpress.lua`, une ligne `require` dans `hyprland.lua` |

Le délai et la tolérance sont `LONG_PRESS_MS` et `MOVE_TOLERANCE` en haut de
`longpress/src/main.cpp` ; modifie-les et relance l'installeur.

Désinstallation : `./longpress/uninstall.sh`.

## À savoir

- **Sécurité.** L'IOMMU protège normalement la mémoire contre les périphériques défaillants ou
  malveillants. Seul le groupe du contrôleur tactile passe en `identity`, tous les autres
  périphériques restent protégés. Le noyau linux-surface fait la même chose.
- **Noyau « tainted ».** Au chargement du module, le noyau affiche
  `module verification failed ... tainting kernel`. C'est normal pour tout module externe et sans
  conséquence.
- **Secure Boot.** DKMS signe le module avec sa propre clé. Si le Secure Boot est activé, le module
  ne se charge que si cette clé est enregistrée (par exemple avec
  `mokutil --import /var/lib/dkms/mok.pub`).
- **Mises à jour du noyau.** DKMS recompile le module automatiquement quand `linux-omarchy` est mis à
  jour. Si un futur noyau change une API utilisée par le pilote, la compilation échoue et le tactile
  ne marche plus jusqu'à une mise à jour de ce projet. En attendant, tu peux démarrer sur un
  instantané précédent depuis le menu Limine.
- **Sensibilité.** Les réglages d'iptsd sont dans `/etc/iptsd.conf`. Si un doigt décroche brièvement
  pendant un pincement (colonne `drops` de `verify.sh`), baisser `ActivationThreshold` et
  `DeactivationThreshold` dans la section `[Contacts]` peut aider.

## Dépannage

| Symptôme | Où regarder |
|---|---|
| Module non compilé | `dkms status ipts`, puis `/var/lib/dkms/ipts/6.19.8.2/build/make.log` |
| Module non chargé | `modinfo -n ipts` doit pointer vers `updates/dkms` |
| Groupe IOMMU pas en `identity` | `cat /sys/bus/pci/devices/0000:00:16.4/iommu_group/type` (adresse sur une Surface Pro 6), `sudo dmesg \| grep DMAR` |
| `Failed to process buffer: -22` | le module chargé n'a pas la correction Linux 7.2 : réinstalle et redémarre |
| Aucun événement tactile | `journalctl -b -u 'iptsd@*'` |

## Désinstallation

```bash
sudo ./uninstall.sh
```

Le script supprime le module, le crochet IOMMU et le crochet Omarchy. `iptsd` et le dépôt
linux-surface sont conservés, le script indique comment les retirer. Redémarre ensuite.

## Organisation du dépôt

```
install.sh, uninstall.sh, verify.sh
src/ipts/     sources du pilote, Makefile et dkms.conf
patches/      modifications apportées au pilote linux-surface
files/        crochet IOMMU, règle modprobe, crochet pacman Omarchy
osk/          clavier virtuel optionnel (install.sh, uninstall.sh, service, plugin, disposition wvkbd)
rotate/       rotation de l'écran optionnelle (install.sh, uninstall.sh, service, bouton de barre)
light/        luminosité automatique optionnelle (install.sh, uninstall.sh, service, bouton de barre)
gestures/     gestes de bord optionnels (install.sh, uninstall.sh, plugin du shell)
longpress/    appui long = clic droit, optionnel (install.sh, uninstall.sh, plugin Hyprland)
```

## Crédits et licence

- Pilote IPTS de Dorian Stoll et du projet [linux-surface](https://github.com/linux-surface/linux-surface),
  tiré de `patches/6.19/0005-ipts.patch`.
- L'idée du passthrough IOMMU vient du correctif linux-surface de Liban Hannan.
- [iptsd](https://github.com/linux-surface/iptsd), du projet linux-surface.
- [wvkbd](https://github.com/jjsullivan5196/wvkbd) (GPL-3.0), compilé par `osk/wvkbd/build.sh` avec les fichiers de disposition de `osk/wvkbd/`, dérivés de sa disposition `deskintl`.

Le pilote est sous licence GPL-2.0-or-later. Le reste de ce dépôt est publié sous la même licence,
voir [LICENSE](LICENSE), sauf les fichiers de disposition wvkbd de `osk/wvkbd/`, sous GPL-3.0 comme wvkbd.

Ce projet n'est affilié ni à Microsoft, ni à Omarchy, ni à linux-surface.
