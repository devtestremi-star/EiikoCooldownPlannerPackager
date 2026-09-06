-- ECP Packager - Core/Database.lua
-- SavedVariable PROPRE au Packager (cf. memo §12.1). Le Packager contient tout ce qui le
-- concerne -- packs, composition, profil createur, snapshots -- et ne fait que LIRE ECP.
-- Il n'ecrit JAMAIS dans les SavedVariables d'ECP.
--
-- ⚠️ Pas de numero de schema, pas de wipe. ECP a appris cette lecon a ses depens : chez lui
-- un bump de DB_SCHEMA efface les trois SavedVariables. Ici toute evolution sera ADDITIVE.
local addonName, PK = ...

-- Structure (cf. memo §10.2, §10.3, §12.1) :
--   ECPPackagerDB = {
--     creator = { id, name, at, twitch, x, discord },
--     packs   = {                              -- un pack par (spe, donjon)
--       [packId] = {
--         packId, spec, dID, name, updatedAt,  -- identite (creatorId, spe, donjon)
--         entries = {                          -- TABLEAU : l'ordre porte de l'information
--           { catalogVariantId, variantId, name, snapshot, deleted },
--         },
--       },
--     },
--   }
-- `variantId`  = l'id LOCAL de la variante chez ECP. C'est par lui qu'on la retrouve.
-- `snapshot`   = copie gelee de ce qui a ete publie. JAMAIS lue comme "le plan courant" :
--                la variante vivante d'ECP est seule verite. Ceci est un journal.
-- `deleted`    = marquee pour suppression (a la main, ou auto quand la variante a disparu).

function PK:InitDB()
    ECPPackagerDB = ECPPackagerDB or {}
    ECPPackagerDB.packs = ECPPackagerDB.packs or {}
    -- Le profil createur est mis de cote pour l'instant (decision : on verra plus tard).
    -- La cle est creee vide pour que rien n'ait a la tester ailleurs.
    ECPPackagerDB.creator = ECPPackagerDB.creator or {}
    self.db = ECPPackagerDB
end

-- Amorcage : PLAYER_LOGIN, quand les SavedVariables sont chargees.
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    PK:InitDB()
    -- On ne se plaint PAS ici de l'absence d'ECP : au login, personne ne lit le chat.
    -- Le constat se fait a l'ouverture de la fenetre, ou l'utilisateur regarde.
end)
