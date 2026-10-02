# ⚔️ Donjon Tactique

Jeu de rôle tactique au tour par tour dans le navigateur, inspiré des tables virtuelles comme Foundry VTT :
plateau en cases, jetons, ordre d'initiative, journal des jets de dés.

## Lancer le jeu

Aucune installation : ouvre simplement `index.html` dans ton navigateur.

## Principe

- Compose un groupe de **1 à 4 héros** parmi 5 classes : Guerrier, Mage, Rôdeur, Clerc, Voleur.
- Traverse **5 niveaux** générés aléatoirement (gobelins, squelettes, loups, orcs, chamans… et l'Ogre final).
- À chaque niveau terminé, les héros gagnent un niveau (+PV, +dégâts, +toucher) et récupèrent leurs PV.

## Règles (style D&D 5e simplifié)

- **Initiative** : 1d20 + Dex au début de chaque combat.
- **Tour d'un héros** : un déplacement (fractionnable), une action et une action bonus.
- **Attaque** : 1d20 + bonus ≥ CA. 20 naturel = critique (dés doublés), 1 naturel = échec.
- **Sauvegardes** : certains sorts demandent un jet de Dex contre un DD.
- **Terrain** : murs (bloquent passage et vue), gravats (coût 2), eau (infranchissable, ne bloque pas la vue).
- **0 PV** : un héros tombe inconscient ; un soin le relève.

## Contrôles

| Action | Contrôle |
| --- | --- |
| Se déplacer | Clic sur une case bleue |
| Utiliser une capacité | Bouton ou touches `1`–`5`, puis clic sur la cible |
| Annuler le ciblage | Clic droit ou `Échap` |
| Fin du tour | Bouton ou `Espace` |

## Structure du code

- `js/data.js` — classes, capacités, monstres, niveaux (facile à modifier pour équilibrer ou ajouter du contenu)
- `js/engine.js` — dés, génération de carte, déplacement (Dijkstra), ligne de vue
- `js/game.js` — déroulement des tours, résolution des capacités, IA des monstres
- `js/render.js` — rendu du plateau sur canvas
- `js/ui.js` — interface (initiative, journal, barre d'actions, écrans)
