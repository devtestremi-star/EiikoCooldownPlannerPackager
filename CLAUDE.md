# ECP Packager — guide projet

Addon World of Warcraft **compagnon** d'EiikoCooldownPlanner (ECP), pour l'extension
**Midnight**. C'est un **outil d'AUTEUR** : il compose des *packs* de variantes de plan et
produit la chaîne de **catalogue** que les joueurs importent dans ECP.

Il ne planifie rien, n'affiche rien en combat, et n'a aucun rôle pour un joueur ordinaire.

## Cible client

- **Interface : `120100`**. Doit rester alignée sur celle d'ECP.
- Tester en jeu avec `/reload`. Erreurs Lua : `/console scriptErrors 1`.
- ⚠️ **Aucune infrastructure de test** : pas de tests, pas de CI, pas d'interpréteur Lua sur
  la machine de dev. La seule vérification est le jeu. `/ecpp test` (aller-retour de format)
  est ce qui s'en rapproche le plus.

## Documents qui font foi

- **Le mémo de conception**, HORS DÉPÔT :
  `C:\Users\Remi\.claude\plans\je-veux-ajouter-une-tingly-dove.md`
  Toutes les décisions de format et de structure y sont, avec leur raison. ⚠️ Il s'est
  construit par couches et les sections tardives **révisent** les précédentes : lire
  **§10 → §11 → §12** d'abord. §14 = export boss, §15 = couche de validation (refus acté).
- **`../EiikoCooldownPlannerDev/CLAUDE.md`** : le guide d'ECP. Ses règles s'appliquent ici
  dès qu'on touche à ses données — en particulier la règle absolue sur les SavedVariables.
- ⚠️ **Ce dossier n'est dans AUCUN dépôt git.** Ni le sien, ni celui d'ECP (il est hors
  arborescence). Il n'y a donc ni historique, ni diff, ni filet : tout se relit à la main.

## Structure

```
EiikoCooldownPlannerDev_Packager.toc  # métadonnées + ordre de chargement
                                      #   ⚠️ le .toc doit TOUJOURS s'appeler comme son dossier
Core/
  Constants.lua   # table privée PK, PK.VERSION, PK:Print, et les IDENTIFIANTS OPAQUES
                  #   (PK.NewId / PK.IsValidId). Alphabet SANS caractères ambigus (ni O/0,
                  #   ni I/l/1), 12 caractères : un id doit pouvoir être recopié à la main.
                  #   PK.REQUIRED_BRIDGE_API = version du contrat attendu du pont d'ECP.
  Bridge.lua      # SEUL point de contact avec ECP. `PK.ECP()` rend sa table privée,
                  #   `PK.Components()` sa bibliothèque de widgets, `PK.BridgeError()` la
                  #   raison d'un échec. Résolution PARESSEUSE (la DB d'ECP n'est peuplée
                  #   qu'à PLAYER_LOGIN) et versionnée (apiVersion).
  Database.lua    # SavedVariable ECPPackagerDB + amorçage PLAYER_LOGIN.
                  #   Pas de numéro de schéma, pas de wipe : toute évolution est ADDITIVE.
  Creator.lua     # profil créateur : id opaque immuable + pseudo. Cf. « Identité » plus bas.
  Pack.lua        # LE MODÈLE : packs, composition, empreinte déterministe, état dérivé
                  #   d'une entrée, et PK.CanPackage (le garde de republication).
  Codec.lua       # construction du CONTENEUR publié + enveloppe `ecp;3;catalog`.
                  #   ⚠️ N'encode PAS lui-même : le pipeline appartient à ECP.
  SelfTest.lua    # `/ecpp test` : build → encode → decode → comparaison profonde.
  Diagnose.lua    # `/ecpp status` : à quel ECP suis-je réellement accroché ?
  Commands.lua    # /ecppack, /ecpp
UI/
  Window.lua      # fenêtre principale : rangée de spés, puis UNE LIGNE PAR DONJON avec les
                  #   variantes déjà dans le pack (puces) et un bouton Add.
  CreatorFrame.lua# écran du profil créateur (pseudo seul, cf. « Identité »).
```

### Namespace

Chaque fichier reçoit `local addonName, PK = ...`. `PK` est la table privée **de cet
addon** — aucun rapport avec le `HR` d'ECP, qu'on atteint uniquement par le pont.
On n'expose dans `_G` que `SLASH_ECPPACK*` et `SlashCmdList["ECPPACK"]`.

---

## 🚫 Règles absolues

### 1. On n'écrit JAMAIS dans les tables d'ECP

`PK.ECP()` rend la table **réelle** d'ECP, pas une copie : les deux addons partagent le même
état Lua. Une écriture accidentelle passerait donc **sans la moindre erreur**.

> Si une écriture devient nécessaire, elle ne s'écrit pas ici : **c'est à ECP d'exposer une
> fonction qui la réalise, et on l'appelle.** ECP reste seul gardien de ses invariants
> (compteur d'id monotone, cohérence `dID`/rangement, `canEdit`). Une écriture directe venue
> d'ici les contourne tous, en silence. La fonction doit être écrite dans les termes d'ECP
> (« poser tel champ sur telle variante »), jamais dans les nôtres.

Corollaire de lecture : faire passer les accès par quelques fonctions **nommées**
(`VariantsFor`, `LiveVariant` dans `UI/Window.lua`) plutôt que de se promener dans
`ecp.db2` un peu partout. La surface à relire reste petite.

### 2. Copie profonde obligatoire

`entry.snapshot = variant` garderait une **référence** : le snapshot « gelé » suivrait les
modifications faites ensuite dans ECP, le journal deviendrait un miroir, et plus rien ne
serait jamais détecté comme « modifié ». Un seul point de passage : `Snapshot()` dans
`Core/Pack.lua`, qui fait `ecp.DeepCopy` **et** tamponne le `dID`.

### 3. On ne redéclare PAS les SavedVariables d'ECP

Deux addons qui déclarent la même SavedVariable écrivent chacun leur fichier, et le dernier
chargé écrase l'autre : **perte de données silencieuse**. ECP est le seul propriétaire de
`HealPlannerDB` / `ECPlannerDB` / `ECPDevLog` / `ECPDevScan` / `HealPlannerCharDB`.
Le Packager n'a que `ECPPackagerDB`.

---

## Modèle de données

```
ECPPackagerDB = {
  creator = { id, name, at, twitch, x, discord },   -- réseaux : plus alimentés, cf. Identité
  packs   = {
    [packId] = {
      packId, spec, dID, name, publishedAt,
      entries = {                                    -- TABLEAU : l'ordre porte de l'info
        { catalogVariantId, variantId, name, snapshot, fingerprint },
      },
    },
  },
}
```

- **Un pack = (creatorId, spé, donjon)** (mémo §10.3). Le triplet est la **contrainte
  d'unicité** — il garantit qu'il ne peut jamais exister deux packs pour le même donjon,
  donc qu'aucune variante ne peut être revendiquée deux fois. Le `packId` n'en est que
  l'**adresse** (une valeur à transporter au lieu d'un triplet).
- **`variantId`** = l'id LOCAL de la variante chez ECP. C'est par lui qu'on la retrouve.
- **`snapshot`** = copie gelée de ce qui a été publié. **Jamais** lue comme « le plan
  courant » : la variante vivante d'ECP est seule vérité. Ceci est un journal.
- **`catalogVariantId`** vit ici, et **jamais sur la variante d'ECP** (mémo §12.1). C'est ce
  qui rend ECP totalement ignorant du Packager — et qui fait disparaître sans une ligne de
  code le piège de la duplication : une variante dupliquée a un id neuf, n'est pas dans la
  composition, donc pas dans le pack.

### État d'une entrée : DÉRIVÉ, jamais stocké

`Pack.EntryState(e, liveVariant)` rend `"missing"` / `"modified"` / `"ok"`. Un état dérivé
ne peut pas dériver : pas de drapeau à poser au bon moment, pas d'incohérence possible.

⚠️ **`"missing"` ne retire RIEN tout seul.** L'entrée garde son snapshot, donc elle reste
publiable — le créateur a pu supprimer la variante chez lui sans vouloir la retirer de son
offre. On le signale (puce rouge) et il tranche.

### Un pack vide = « supprime TOUT dans ce donjon »

Geste le plus destructif du système, accepté explicitement (mémo §10.6). D'où deux gardes :

- `Pack.RemoveEntry` **purge** un pack qui devient vide **sans avoir jamais été publié** —
  sinon « ajouter puis retirer » émettrait un ordre de suppression que personne n'a voulu ;
- `Codec.BuildContainer` n'émet un pack à zéro entrée **que s'il a déjà été diffusé**.

---

## L'empreinte (`Pack.Fingerprint`) — deux pièges, pas un

Il n'existe **aucune primitive de hachage** dans l'API (vérifié : `C_EncodingUtil` ne fait
que CBOR / compression / base64). L'empreinte est donc une sérialisation, et elle doit être :

1. **Déterministe** — l'ordre d'itération d'une table Lua n'est pas garanti, d'où la marche
   à **clés triées**. Le tri porte sur `(type, valeur)` : une table mélange clés numériques
   (encounterID) et chaînes (occKey), et comparer un nombre à une chaîne lève une erreur.
2. **Injective** — chaque scalaire est préfixé de son type et les séparateurs `% = ; { }`
   sont échappés. Sans ça le nombre `5` et la chaîne `"5"` donnent le même texte, et un nom
   contenant `;` peut imiter une autre structure : deux contenus **différents** produiraient
   la même empreinte, une vraie modification passerait pour « inchangée », et c'est le
   snapshot **périmé** qui partirait à la publication.

> ⚠️ **L'empreinte se calcule sur la variante VIVANTE, jamais sur le snapshot tamponné.**
> La détection compare `Pack.Fingerprint(liveVariant)` à la valeur stockée. Empreinter la
> copie (qui a reçu un `dID` que l'originale n'a pas) rendrait toute variante sans `dID`
> éternellement « modifiée ». Les deux sites d'appel passent bien la vivante.

---

## Le format publié

```
ecp;3;catalog
<base64 : { v, min, spec, cr, pk }>
```

- `cr` = `{ id, name, at }` — carte créateur, **une seule fois** pour tout le conteneur
  (mémo §10.4). La stocker par pack donnerait N copies divergentes. `at` date le **profil**,
  pas la publication : c'est lui qui arbitre quelle carte gagne chez un destinataire qui
  importe des packs dans le désordre (§7.5).
- `pk[]` = `{ pid, dID, nm, at, ent }`
- `ent[]` = `{ cid, nm, hl, dID, ext, tsp, asg }` — liste blanche du §12.5.
  **Ne voyagent pas** : `id` (compteur LOCAL, collision chez le lecteur), `imported`,
  `synced`, `syncFrom`, `base`, `isTemplate`.

> ⚠️ **Le LECTEUR est `../EiikoCooldownPlannerDev/Core/Catalog.lua`.** Producteur et lecteur
> doivent s'accorder sur **chaque nom de champ** — un désaccord passe en silence (le champ
> arrive `nil`, l'entrée est rejetée ou amputée). Vérifié champ par champ ; toute
> modification ici se fait des deux côtés, en même temps.

### On n'encode pas nous-mêmes

Le pipeline (CBOR → Deflate → Base64) appartient à ECP et n'existe qu'**une fois**, dans
`Share.EncodeRaw` / `Share.DecodeRaw`. Deux implémentations devraient s'accorder sans que
rien ne le vérifie : le jour où l'une change son `Enum.Base64Variant`, l'autre répond
« chaîne corrompue » à une chaîne parfaitement valide, et c'est intraçable.
**Le pipeline est à ECP. Le payload est à nous.**

### Versions : entier de format, PAS version d'addon

`WIRE_FORMAT = 3` est un **entier par route**, bumpé seulement quand le format change
vraiment. C'est ce qui permet à une 1.3.0 dont le format n'a pas bougé d'être lue par une
1.2.1. Le `3` est aussi ce qui déclenche, chez un ECP d'avant le catalogue, le message
« exported by a newer version of the addon » (son test `format > FORMAT` avec `FORMAT = 2`
existe **depuis le commit initial** — c'était le seul levier disponible sur le parc déployé,
mémo §6.1).

⚠️ **`MIN_READER_VERSION` n'est PAS la version de l'auteur** mais celle qui **livre le
lecteur**. L'annoncer trop haut rendrait toute chaîne produite illisible par la seule version
capable de la lire. Elle n'est **lue nulle part** aujourd'hui (aucun comparateur de versions
n'existe côté ECP, et `"1.10.0" < "1.9.0"` est vrai en comparaison de chaînes).

### Bornes (mémo §12.4)

| Borne | Valeur | Où |
|---|---|---|
| Entrées par conteneur | **100** | `Codec.Publish` refuse ; le lecteur refuse aussi |
| Champs de texte libre | **64 caractères** | tronqué par `text()` |
| Charge **décompressée** | **512 Ko** | ⚠️ chez le LECTEUR seulement (`Share.DecodeRaw`) |

⚠️ Le plafond de 512 Ko porte sur le **CBOR décompressé**. Le mesurer sur `#str` (base64 du
flux compressé) ne veut rien dire — Deflate gagne un facteur 3 à 10 sur des tables de plan,
donc un contrôle sur la chaîne encodée ne peut quasiment jamais se déclencher. `SelfTest` se
contente donc de l'afficher.

### Troncature et échappement

- **Troncature sur les CARACTÈRES**, jamais les octets : `s:sub(1, n)` couperait un accent en
  deux, et une séquence UTF-8 invalide peut faire **refuser la sérialisation CBOR** — donc
  échouer toute la publication sur un « Encoding failed » muet. Implémentation unique chez
  ECP : `HR.TruncateUTF8`, atteinte par le pont (repli local si absent).
- **Échappement du markup (`|` → `||`) à l'AFFICHAGE seulement, jamais au stockage.** Une
  chaîne échappée au stockage repartirait échappée et le `||` se composerait à chaque cycle.
  Helper : `esc()` dans `UI/Window.lua`, qui délègue à `ecp.EscapeMarkup`.

---

## Identité du créateur

- **`id`** opaque, généré **une fois à la demande** (pas au login : écrire dans les
  SavedVariables d'un joueur qui n'utilisera jamais la feature n'a pas lieu d'être). C'est
  lui qui **regroupe**.
- **`name`** pseudo modifiable. C'est lui qu'on **cherche et qu'on montre**.

Regrouper sur le nom ferait fusionner deux homonymes ; n'avoir que l'id rendrait la
recherche impossible.

> ⚠️ **Cette identité est falsifiable par construction.** Une chaîne collée n'a aucune
> identité de transport (contrairement au canal Sync d'ECP, où le jeu dit qui parle).
> Elle **range et cherche, elle n'AUTORISE jamais rien.** Ne jamais la brancher sur
> `db2.syncTrust`.

**Décisions en vigueur :**
- L'**identifiant n'est ni affiché ni éditable**. Conséquence assumée : aucun chemin de
  récupération. Une réinstallation ou un second compte WoW produit une **nouvelle** identité
  et les packs déjà diffusés restent sous l'ancienne. `Creator.Restore` existe **sans
  appelant** — elle porte la logique difficile (validation de forme, garde d'orphelinage) ;
  rebrancher la récupération ne demanderait qu'un point d'entrée, pas une refonte.
- Les **réseaux sociaux (twitch / x / discord) sont masqués** : l'écran ne demande que le
  pseudo, et `CreatorCard()` ne les émet plus. Une valeur déjà enregistrée n'est **pas
  effacée** (on ne touche pas aux données du joueur), elle dort en base. Les rouvrir =
  remettre trois `Field()` dans `CreatorFrame` et trois lignes dans le codec.

---

## `PK.CanPackage` — on ne package que son propre travail

Deux conditions, et il faut bien **les deux** :

1. **`v.synced`** — un plan reçu par le canal Sync ne se republie pas sous sa propre
   identité. ⚠️ Testé **ici**, explicitement : côté ECP, `CanEditVariant` ne teste
   volontairement pas `synced` (verrouiller l'édition de plans reçus serait un changement de
   comportement sur des données en production, mis de côté). Mais « ne pas verrouiller
   l'ÉDITION » et « autoriser la RÉPUBLICATION sous mon nom » sont deux questions distinctes.
2. **`ecp.CanEditVariant(v)`** — couvre les variantes promues depuis un catalogue.

Sinon le même plan existerait sous **deux identités de créateur**, avec deux flux de mises à
jour, et un joueur ayant importé les deux catalogues en aurait deux exemplaires vivants.

> **Échouer FERMÉ** : sans le pont, on ne peut pas savoir si la variante est liée → on
> refuse. Un garde qui autorise en cas de doute ne garde rien.

Corollaire d'UI : `VariantsFor` filtre déjà sur `CanPackage`. **On ne propose jamais ce
qu'on refuserait d'ajouter.**

---

## Réutilisation de l'UI d'ECP

On réutilise, on ne duplique pas (mémo §12.6). Tout passe par `PK.Components()` :
`C.Window`, `C.TextButton`, `C.ImageText`, `C.Container`, `C.ModalBackground`… et par les
façades `ecp.Icons.Apply` (icônes de donjon / spé / défensif) et `ecp.VariantIconItems`
(« ce que contient une variante », en images).

Effet de bord voulu : le Packager suit automatiquement le **thème et l'échelle** d'ECP, sans
une ligne de style. Et réécrire ces descripteurs ici donnerait deux définitions qui
divergeraient au premier changement de compo.

---

## Pièges vérifiés

- **Antislashs doubles obligatoires** dans les chemins de texture. `\B` et `\W` ne sont pas
  des échappements connus de Lua : le langage avale l'antislash **sans la moindre erreur**, et
  `"Interface\Buttons\WHITE8x8"` devient `InterfaceButtonsWHITE8x8` — ni fond, ni
  surbrillance, ni message. C'est arrivé sur les puces.
- **La largeur d'un ScrollChild n'est pas héritée** : sans `SetWidth` explicite, tout ce qui
  s'y ancre à droite se retrouve sans largeur (et un FontString à largeur négative n'affiche
  rien).
- **Les deux copies d'ECP** (publiée et Dev) déclarent les **mêmes** SavedVariables. Actives
  ensemble, elles s'écrasent : `/ecpp status` le détecte et le dit.
- **Seule la copie d'ECP qui contient `Core/Bridge.lua` pose le pont.** Une copie live
  antérieure au chantier catalogue ne l'a pas, et le Packager affiche alors
  « EiikoCooldownPlanner is not loaded » — message trompeur : ECP est chargé, mais trop
  vieux.
- **Une puce hébergeant un `C.ImageButton`** avalerait les clics destinés à la puce → les
  pastilles sont des `C.ImageText`, non interactives.

## Checklist d'empaquetage

Le dossier Dev doit être transformé en quatre endroits, et **rien ne le vérifie** :

1. le **nom du dossier** : `EiikoCooldownPlannerDev_Packager` → `EiikoCooldownPlanner_Packager` ;
2. le **nom du `.toc`** — ⚠️ WoW exige `<dossier>/<dossier>.toc`, sinon l'addon ne se charge
   pas du tout (déjà arrivé) ;
3. `## Title:` — retirer le `(Dev)` ;
4. `## Dependencies:` → `EiikoCooldownPlanner` (les `.toc` de dev ne se lient qu'entre eux).

> **Le nom de dossier n'est pas cosmétique : `<parent>_<enfant>` est ce qui IMBRIQUE** le
> Packager sous ECP dans la liste des addons du client. L'imbrication se fait sur le nom de
> dossier avec un **underscore**, jamais sur `Dependencies` — d'où `BigWigs_Core` imbriqué
> alors qu'`EllesmereUIActionBars`, sans underscore, ne l'est pas.
>
> `Core/Diagnose.lua` en dépend aussi : il déduit le nom de l'ECP attendu par
> `addonName:gsub("_Packager$", "")`. Casser la convention casse ce contrôle.

> ⚠️ **`Dependencies` et pas `OptionalDeps`.** `OptionalDeps` ne fait qu'imposer un ORDRE de
> chargement : il est **invisible** dans la liste des addons du client. `Dependencies`, lui,
> s'affiche et s'applique — si ECP n'est pas actif, le client désactive le Packager et
> l'annonce (« dépendance manquante »). C'est ce qu'on veut : le Packager ne sait rien faire
> sans ECP, il ne peut même pas ouvrir sa fenêtre.
>
> Sens de la dépendance : **le Packager dépend d'ECP**, jamais l'inverse. ECP ignore
> complètement l'existence du Packager — c'est lui qui nous lit, via le pont.

## Reste à faire

- **Nom de pack** : `nm` voyage mais n'est posé nulle part — aucune UI ne le saisit.
- **Ordre des packs** dans le conteneur : issu d'un `pairs`, donc arbitraire (l'ordre des
  *entrées*, lui, est préservé et porte de l'information).
- **Forme du `creatorId`** : différée au mémo §7.7.
- **Récupération d'identité** : `Creator.Restore` sans point d'entrée (cf. Identité).
