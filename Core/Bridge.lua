-- ECP Packager - Core/Bridge.lua
-- SEUL point de contact avec ECP. Tout le reste de l'addon passe par `PK.ECP`, jamais
-- par une globale d'ECP en direct : le jour ou le pont change, il n'y a qu'ici a toucher.
--
-- POURQUOI UN PONT EXPLICITE, et pas la table privee via `AllowAddOnTableAccess` :
-- aucune API de lecture de table privee n'a pu etre confirmee sur ce client, et TOUTE la
-- reutilisation de l'UI en depend. Un pont declare par ECP est garanti de marcher, il est
-- versionnable, et c'est deja le pattern qu'ECP utilise pour EllesmereUI (duck-typing sur
-- _G, pcall, no-op si absent).
--
-- REGLE : echouer FERME et le DIRE. Un addon d'auteur qui ne se charge pas en silence
-- est pire qu'un message d'erreur -- on ne relie jamais l'absence a sa cause.
--
-- 🚫 REGLE ABSOLUE : ON N'ECRIT JAMAIS DANS LES TABLES D'ECP.
-- `PK.ECP()` rend la table REELLE d'ECP, pas une copie : les deux addons partagent le meme
-- etat Lua. Une ecriture accidentelle passerait donc sans la moindre erreur. C'est une
-- discipline, pas une barriere -- d'ou cette regle ecrite ici, en tete du SEUL fichier qui
-- donne acces a ECP.
--   Si une ecriture devient necessaire, elle ne s'ecrit PAS ici : c'est a ECP d'exposer une
--   fonction qui la realise, et on l'appelle. ECP reste seul gardien de ses propres
--   invariants (compteur d'id monotone, coherence dID / rangement, canEdit) ; une ecriture
--   directe venue d'ici les contourne tous, en silence.
--
-- ⚠️ COPIE PROFONDE OBLIGATOIRE, pour la meme raison. `entry.snapshot = variant` garde une
-- REFERENCE : le snapshot « gele » suivrait les modifications faites ensuite dans ECP, le
-- journal deviendrait un miroir, et plus rien ne serait jamais detecte comme « modifie ».
-- Passer par `PK.ECP().DeepCopy(variant)`.
--
-- Corollaire de lecture : faire passer les acces par quelques fonctions NOMMEES (cf.
-- `VariantsFor` dans UI/Window.lua) plutot que de se promener dans `ecp.db2` un peu partout.
-- La surface a relire reste petite.
local addonName, PK = ...

-- Etat du pont, resolu PARESSEUSEMENT : `_G.ECPBridge` existe des le chargement d'ECP,
-- mais sa DB (HR.db) n'est peuplee qu'a PLAYER_LOGIN. Rien ne doit donc etre lu au
-- chargement de ce fichier.
local resolved, failure

-- Renvoie (ecp, nil) ou (nil, message). `ecp` = la table privee d'ECP.
local function Resolve()
    if resolved then return resolved, nil end
    if failure then return nil, failure end

    local b = _G.ECPBridge
    if type(b) ~= "table" then
        failure = "EiikoCooldownPlanner is not loaded. Enable it, then /reload."
        return nil, failure
    end
    if b.apiVersion ~= PK.REQUIRED_BRIDGE_API then
        failure = ("Version mismatch: ECP exposes bridge v%s, the Packager expects v%s. "
                .. "Update both addons."):format(tostring(b.apiVersion),
                                                          tostring(PK.REQUIRED_BRIDGE_API))
        return nil, failure
    end
    if type(b.private) ~= "table" or type(b.private.UI) ~= "table"
       or type(b.private.UI.Components) ~= "table" then
        failure = "ECP's bridge is incomplete (UI components missing)."
        return nil, failure
    end

    resolved = b.private
    return resolved, nil
end

-- Table privee d'ECP, ou nil. Ne PRINT rien : c'est a l'appelant de decider quoi dire.
function PK.ECP()
    local ecp = Resolve()
    return ecp
end

-- Raison de l'echec, ou nil si le pont est bon.
function PK.BridgeError()
    local _, err = Resolve()
    return err
end

-- Raccourci vers la bibliotheque de composants d'ECP (C.Window, C.TextButton, ...).
-- C'est elle qui donne au Packager le meme look, la meme echelle et le meme theme
-- qu'ECP, sans une ligne de style a dupliquer (cf. memo §12.6).
function PK.Components()
    local ecp = Resolve()
    return ecp and ecp.UI and ecp.UI.Components or nil
end

-- Quel ECP nous a repondu ? Les DEUX dossiers peuvent coexister (publie + Dev) et ils
-- declarent les MEMES SavedVariables -- ils ne devraient jamais etre actifs ensemble.
-- Savoir lequel parle evite de developper contre la mauvaise copie sans s'en rendre compte.
function PK.ECPIdentity()
    local b = _G.ECPBridge
    if type(b) ~= "table" then return nil end
    return b.addonName, b.version
end
