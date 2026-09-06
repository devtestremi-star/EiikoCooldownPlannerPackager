-- ECP Packager - Core/Creator.lua
-- PROFIL CREATEUR (memo §7). C'est l'identite qui voyage dans chaque pack et qui permet,
-- chez le destinataire, de regrouper (« Eiiko -- 4 packs ») et de chercher par auteur.
--
-- DEUX CHAMPS, DEUX ROLES -- et c'est la distinction qui compte :
--   * `id`   opaque, genere une fois, ne change jamais. C'est lui qui REGROUPE.
--   * `name` pseudo choisi, modifiable. C'est lui qu'on CHERCHE et qu'on MONTRE.
-- Regrouper sur le nom ferait fusionner deux auteurs homonymes ; n'avoir que l'id
-- rendrait la recherche impossible. Meme id + nom different = l'auteur s'est renomme.
--
-- ⚠️ CETTE IDENTITE EST FALSIFIABLE PAR CONSTRUCTION. Une chaine collee n'a aucune
-- identite de transport (contrairement au canal Sync, ou le jeu dit qui parle). Elle
-- RANGE et CHERCHE, elle n'AUTORISE JAMAIS rien.
local addonName, PK = ...

PK.Creator = PK.Creator or {}
local Creator = PK.Creator

local FIELDS = { "name", "twitch", "x", "discord" }

local function store()
    if not PK.db then return nil end
    PK.db.creator = PK.db.creator or {}
    return PK.db.creator
end

--------------------------------------------------------------------------------
-- Identite
--------------------------------------------------------------------------------

-- L'id, cree a la demande. On ne le genere PAS au login : ecrire dans les SavedVariables
-- d'un joueur qui n'utilisera jamais la feature n'a pas lieu d'etre.
function Creator.EnsureId()
    local c = store(); if not c then return nil end
    if not PK.IsValidId(c.id) then
        c.id = PK.NewId()
        c.at = (GetServerTime and GetServerTime()) or time()
    end
    return c.id
end

function Creator.Id()   local c = store(); return c and c.id end
function Creator.Name() local c = store(); return c and c.name end

-- Le profil est-il utilisable pour publier ? Il faut l'id ET un nom : sans nom, le
-- destinataire n'a rien a afficher ni a chercher, et l'auteur est un identifiant opaque.
function Creator.IsComplete()
    local c = store()
    return (c and PK.IsValidId(c.id) and type(c.name) == "string" and strtrim(c.name) ~= "")
           and true or false
end

--------------------------------------------------------------------------------
-- Edition
--------------------------------------------------------------------------------

-- Pose un champ de texte. `at` date le PROFIL, pas la publication : c'est lui qui arbitre
-- quelle carte gagne chez un destinataire qui importe des packs dans le desordre (§7.5).
-- Sans ca, importer un vieux pack apres un recent ecraserait la carte recente.
function Creator.Set(field, value)
    local c = store(); if not c then return false end
    local allowed = false
    for _, f in ipairs(FIELDS) do if f == field then allowed = true break end end
    if not allowed then return false end

    if type(value) == "string" then value = strtrim(value) end
    if value == "" then value = nil end
    if c[field] == value then return false end      -- pas de bump inutile de `at`

    c[field] = value
    c.at = (GetServerTime and GetServerTime()) or time()
    return true
end

-- La carte complete (copie : personne n'edite la base par inadvertance).
function Creator.Get()
    local c = store() or {}
    return { id = c.id, name = c.name, at = c.at,
             twitch = c.twitch, x = c.x, discord = c.discord }
end

--------------------------------------------------------------------------------
-- Restauration d'identite (memo §7.1)
--
-- ⚠️ SANS APPELANT AUJOURD'HUI. L'identifiant n'est ni affiche ni editable (decision) :
-- il n'existe donc aucun moyen, pour un auteur, de recuperer son identite. Une
-- reinstallation ou un second compte WoW en produit une NOUVELLE, et les packs deja
-- diffuses restent sous l'ancienne.
--
-- Cette fonction est CONSERVEE parce qu'elle porte la logique difficile -- validation de
-- forme et garde d'orphelinage. Rebrancher la recuperation ne demanderait qu'un point
-- d'entree (un champ, ou une commande slash), pas une refonte. Ne pas la supprimer sans
-- acter que la recuperation n'aura jamais lieu.
--------------------------------------------------------------------------------

-- Un auteur qui reinstalle, ou qui publie depuis un SECOND compte WoW, perd son id : les
-- SavedVariables sont par compte WoW, pas par Battle.net.
--
-- Le geste se presenterait comme « restaurer mon identite ici », pas « changer mon id ».
-- Il se fait AVANT de publier : une fois des packs diffuses depuis cette installation, en
-- changer les orphelinerait -- d'ou le garde ci-dessous.
--
-- Renvoie (true) ou (false, raison).
function Creator.HasPublished()
    for _, p in pairs((PK.db and PK.db.packs) or {}) do
        if p.publishedAt then return true end
    end
    return false
end

function Creator.Restore(id, force)
    local c = store(); if not c then return false, "Database not ready." end
    id = type(id) == "string" and strtrim(id):upper() or ""
    -- Un identifiant se VALIDE, il ne se tronque pas (memo §12.4) : un id tronque
    -- produirait une donnee plausible mais fausse, qui casserait le regroupement en silence.
    if not PK.IsValidId(id) then
        return false, "Invalid creator ID (12 characters, no O/0 or I/1)."
    end
    if id == c.id then return false, "This is already your creator ID." end
    if Creator.HasPublished() and not force then
        return false, "You have already published from this install. Changing your creator ID "
            .. "would orphan those packs -- they would no longer be grouped under you."
    end
    c.id = id
    c.at = (GetServerTime and GetServerTime()) or time()
    return true
end
