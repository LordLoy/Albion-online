# ⚔️ Donjon Tactique — version Godot

Roguelike tactique au tour par tour en pixel art, avec le moteur **Godot 4.3**.
Plateau en cases façon Foundry VTT, journal des dés façon D&D, carte de parcours façon *Slay the Spire*.

## Le jeu

- **5 classes** : Guerrier, Mage, Rôdeur, Clerc, Voleur — chacune avec 3 **pouvoirs** à débloquer en montant de niveau
  (Charge, Cri de guerre, Chaîne d'éclairs, Bouclier arcanique, Tir paralysant, Bouclier de la foi, Assassinat…).
- **3 actes, 3 cartes, 3 boss** :
  | Acte | Carte | Boss et mécaniques |
  | --- | --- | --- |
  | 1. Les Cryptes | pierre, torches, bassins | **Ogre** : rage sous 50 % de PV (2 attaques), **séisme** annoncé un tour à l'avance (cases rouges) |
  | 2. La Forêt maudite | herbe, arbres, rivière et ponts | **Liche** : invulnérable tant que ses **phylactères** tiennent, invoque des squelettes, se téléporte si on la colle |
  | 3. Le Cœur du Volcan | basalte, rivières de lave | **Dragon** : **souffle de feu** annoncé, coup de queue, s'envole à mi-vie (élémentaires + sol en feu) |
- **Roguelike** : carte à embranchements (combat, élite, trésor, marchand, feu de camp, événement, boss), mort définitive.
- **Équipement** : 3 emplacements par héros (arme, armure, accessoire), 20 objets.
- **5 potions** utilisables en combat (soin, feu, vitesse, antidote, force).
- **États** : poison, brûlure, ralenti, étourdi, force, et boucliers de PV temporaires.
- **Élites** avec un trait aléatoire (Enragé, Blindé, Vampirique, Rapide, Géant).
- **Graphismes** : éclairage dynamique (torches, lave, lumière autour des héros), ambiance par biome
  (poussière, lucioles, braises), particules, tremblements d'écran.

## Ouvrir le projet

1. Installe **Godot 4.3** (ou plus récent, version standard, pas « .NET ») : https://godotengine.org/download
2. Lance Godot, clique sur **Importer**, et choisis le fichier `godot/project.godot` de ce dépôt.
3. Appuie sur **F5** (ou le bouton ▶ en haut à droite) pour jouer.

Au premier lancement, Godot met quelques secondes à importer les images : c'est normal.

## Contrôles

| Action | Contrôle |
| --- | --- |
| Se déplacer | Clic sur une case bleue |
| Utiliser une capacité | Bouton ou touches `1`–`5`, puis clic sur la cible |
| Annuler le ciblage | Clic droit ou `Échap` |
| Fin du tour | Bouton ou `Espace` |

## Mode dieu (F1)

Appuie sur **F1** pendant un combat pour ouvrir le panneau de test :

- **Héros invincibles**, **actions illimitées** (plus de recharge, déplacement infini), **je contrôle les monstres**
  (c'est toi qui joues leurs tours, comme un MJ)
- **Dés truqués** : d20 normal, toujours 20 ou toujours 1
- **Vitesse des animations** : normale, rapide ou instantanée
- **Outils à clic** : déplacer n'importe quel jeton, foudroyer ou soigner une unité, faire apparaître un monstre
- **Combat** : tuer tous les monstres, soigner le groupe
- **Partie** : +100 or, +1 niveau, objet au hasard, toutes les potions, aller directement à un acte ou à son boss

## Comment le code est organisé

| Fichier | Rôle |
| --- | --- |
| `scripts/data.gd` | **Toutes les données** : classes, pouvoirs, monstres, boss, actes, objets, potions, talents, événements. Le meilleur endroit pour commencer à bidouiller ! |
| `scripts/dice.gd` | Les dés (`Dice.roll("2d6+3")`) |
| `scripts/dungeon.gd` | La carte : génération, déplacements, ligne de vue |
| `scripts/unit.gd` | Un personnage (héros ou monstre) et ses statistiques |
| `scripts/combat.gd` | Les règles : tours, initiative, attaques, sorts, états, **mécaniques des boss**, IA des monstres |
| `scripts/run_state.gd` | La partie roguelike : carte de parcours, rencontres, récompenses, XP, équipement, événements |
| `scripts/screens.gd` | Les écrans hors combat : départ, carte, récompenses, marchand, feu de camp, événements… |
| `scripts/board.gd` | Le plateau : dessin des cases, des jetons, des effets, la souris |
| `scripts/hud.gd` | L'interface : initiative, journal, barre d'actions |
| `scripts/god_panel.gd` | Le panneau du mode dieu (les outils eux-mêmes sont en bas de `combat.gd`) |
| `scripts/main.gd` | Le chef d'orchestre : enchaîne carte, combats et écrans |
| `assets/sprites/` | Les personnages (images 16×16, remplaçables par tes propres images) |
| `assets/tiles/` | Les tuiles des 3 biomes (16×16) |
| `assets/icons/` | Icônes d'équipement, de potions et de pouvoirs |
| `tools/` | Les dessins pixel art en texte et le script qui génère les PNG |

### Prêt pour le multijoueur

Toutes les actions de jeu passent par une seule fonction, `Combat.perform(action)`, avec une action décrite
par un simple dictionnaire, par exemple `{"type": "move", "to": Vector2i(4, 5)}`.
Pour jouer en ligne, il suffira d'envoyer ces dictionnaires aux autres joueurs (avec les RPC de Godot) :
le MJ héberge la partie et contrôle les monstres, chaque joueur contrôle son héros.

## Premiers exercices pour apprendre

1. **Changer un chiffre** — dans `scripts/data.gd`, donne `"hp": 60` au Guerrier, puis relance avec F5.
2. **Créer un monstre** — copie le bloc `"gobelin"` dans `MONSTERS`, renomme-le, change ses stats,
   puis ajoute-le à la liste `pool` d'un acte dans `ACTS`. Pour lui donner une image existante, ajoute par exemple
   `"sprite": "gobelin"` ; sinon, crée `assets/sprites/<clé du monstre>.png`.
3. **Redessiner un sprite** — ouvre une image de `assets/sprites/` dans un logiciel de pixel art
   (Aseprite, LibreSprite, Piskel en ligne…) et modifie-la : Godot la recharge automatiquement.

## Options de lancement (pour les tests)

Dans un terminal : `godot --path godot -- --autoplay --fast` fait jouer les héros tout seuls à toute vitesse.
`--start` passe l'écran de départ, `--act=2` commence à l'acte 2, `--boss` va directement au boss,
`--god` ouvre le mode dieu, `--shot=capture.png` enregistre une capture d'écran.

Tests automatiques :
- `godot --headless --path godot res://tests/god_test.tscn` — tous les outils du mode dieu
- `godot --headless --path godot res://tests/boss_test.tscn` — les mécaniques des 3 boss
