# ⚔️ Donjon Tactique — version Godot

La base du jeu (première version) refaite avec le moteur **Godot 4.3** : combat tactique en cases, 5 classes,
monstres avec IA, initiative, journal des dés et 5 niveaux de donjon, en pixel art.

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

## Comment le code est organisé

| Fichier | Rôle |
| --- | --- |
| `scripts/data.gd` | **Toutes les données** : classes, capacités, monstres, niveaux. Le meilleur endroit pour commencer à bidouiller ! |
| `scripts/dice.gd` | Les dés (`Dice.roll("2d6+3")`) |
| `scripts/dungeon.gd` | La carte : génération, déplacements, ligne de vue |
| `scripts/unit.gd` | Un personnage (héros ou monstre) et ses statistiques |
| `scripts/combat.gd` | Les règles : tours, initiative, attaques, sorts, IA des monstres |
| `scripts/board.gd` | Le plateau : dessin des cases, des jetons, des effets, la souris |
| `scripts/hud.gd` | L'interface : initiative, journal, barre d'actions |
| `scripts/main.gd` | Le chef d'orchestre : écran de départ, enchaînement des niveaux |
| `assets/sprites/` | Les personnages (images 16×16, remplaçables par tes propres images) |
| `assets/tiles/` | Les sols, murs, eau, gravats (16×16) |

### Prêt pour le multijoueur

Toutes les actions de jeu passent par une seule fonction, `Combat.perform(action)`, avec une action décrite
par un simple dictionnaire, par exemple `{"type": "move", "to": Vector2i(4, 5)}`.
Pour jouer en ligne, il suffira d'envoyer ces dictionnaires aux autres joueurs (avec les RPC de Godot) :
le MJ héberge la partie et contrôle les monstres, chaque joueur contrôle son héros.

## Premiers exercices pour apprendre

1. **Changer un chiffre** — dans `scripts/data.gd`, donne `"hp": 60` au Guerrier, puis relance avec F5.
2. **Créer un monstre** — copie le bloc `"gobelin"` dans `MONSTERS`, renomme-le, change ses stats,
   puis ajoute-le à un niveau dans `LEVELS`. Pour lui donner une image existante, ajoute par exemple
   `"sprite": "gobelin"` ; sinon, crée `assets/sprites/<clé du monstre>.png`.
3. **Redessiner un sprite** — ouvre une image de `assets/sprites/` dans un logiciel de pixel art
   (Aseprite, LibreSprite, Piskel en ligne…) et modifie-la : Godot la recharge automatiquement.

## Options de lancement (pour les tests)

Dans un terminal : `godot --path godot -- --autoplay --fast` fait jouer les héros tout seuls à toute vitesse.
`--start` passe l'écran de départ, `--shot=capture.png` enregistre une capture d'écran.
