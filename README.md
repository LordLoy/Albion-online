# ⚔️ Donjon Tactique

Roguelike tactique au tour par tour dans le navigateur, en pixel art, inspiré des tables virtuelles comme Foundry VTT
(plateau en cases, initiative, journal des jets de dés) et de *Slay the Spire* (carte de parcours à embranchements).

## Lancer le jeu

Aucune installation : ouvre simplement `index.html` dans ton navigateur.

## Principe

- Compose un groupe de **1 à 4 héros** parmi 5 classes : Guerrier, Mage, Rôdeur, Clerc, Voleur.
- Traverse **2 actes** (Les Cryptes, Les Profondeurs). Sur la carte, choisis ta route :
  ⚔️ combat, 💀 élite, 💎 trésor, 💰 marchand, 🔥 feu de camp, ❓ événement… jusqu'au 👑 boss (l'Ogre, puis la Liche).
- **Mort définitive** : les PV ne remontent pas tout seuls entre les combats, et si tout le groupe tombe, la partie est perdue.
- **Butin** : or, potions, objets à équiper sur un héros.
- **Progression** : l'XP fait monter le groupe de niveau ; chaque héros choisit alors 1 talent parmi 3.

## En combat

- Le donjon est généré (salles + couloirs) et plongé dans le noir : **brouillard de guerre**, torches, monstres endormis 💤 qui se réveillent en vous voyant.
- **Initiative** : 1d20 + Dex. **Ton tour** : un déplacement (fractionnable), une action et une action bonus.
- **Attaque** : 1d20 + bonus ≥ CA. 20 naturel = critique (dés doublés), 1 naturel = échec.
- **États** : 🟢 poison, 🔥 brûlure, 🧊 ralenti, 💫 étourdi.
- **Terrain** : murs (bloquent passage et vue), gravats (coût 2), eau (infranchissable, ne bloque pas la vue).
- Monstres d'**élite** avec un trait aléatoire (Enragé, Blindé, Vampirique, Rapide, Géant).

## Contrôles

| Action | Contrôle |
| --- | --- |
| Se déplacer | Clic sur une case bleue |
| Utiliser une capacité ou une potion | Bouton ou touches `1`–`9`, puis clic sur la cible |
| Annuler le ciblage | Clic droit ou `Échap` |
| Fin du tour | Bouton ou `Espace` |

## Structure du code

- `js/data.js` — classes, monstres, actes, objets, potions, talents, événements (tout l'équilibrage est ici)
- `js/sprites.js` — sprites pixel art 16×16 (dessinés en texte, un caractère = un pixel) et tuiles générées
- `js/engine.js` — dés, génération du donjon, déplacement (Dijkstra), ligne de vue, champ de vision
- `js/game.js` — déroulement des combats, capacités, états, IA des monstres
- `js/run.js` — la partie roguelike : carte, récompenses, boutique, camp, événements, fin de partie
- `js/render.js` — rendu : couche pixel art + lumière, surbrillances, particules
- `js/ui.js` — interface : initiative, journal, barre d'actions, écran de départ
