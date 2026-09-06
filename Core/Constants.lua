-- ECP Packager - Core/Constants.lua
-- Table privee partagee entre tous les fichiers de CET addon. Rien a voir avec le `HR`
-- d'ECP, qu'on atteint separement via le pont (cf. Core/Bridge.lua).
local addonName, PK = ...

PK.ADDON_NAME = addonName
PK.VERSION    = C_AddOns.GetAddOnMetadata(addonName, "Version") or "0.0.0"

-- Version du CONTRAT attendu du pont d'ECP. A ne bumper que si le pont change de forme.
-- Le Bridge refuse de s'accrocher a un ECP qui n'annonce pas cette version -> un decalage
-- entre les deux addons produit un message clair au lieu d'une erreur Lua incomprehensible.
PK.REQUIRED_BRIDGE_API = 1

PK.CHAT_PREFIX = "|cff33ff99ECP-Pack|r: "

function PK:Print(...)
    print(PK.CHAT_PREFIX .. strjoin(" ", tostringall(...)))
end

--------------------------------------------------------------------------------
-- Identifiants opaques (packId, catalogVariantId, creatorId)
--------------------------------------------------------------------------------

-- Alphabet SANS caracteres ambigus : ni O/0, ni I/l/1. Un id doit pouvoir etre recopie
-- A LA MAIN sans erreur -- c'est ce qui permet a un auteur de restaurer son identite sur
-- une autre machine (memo §7.1).
local ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
local ID_LEN   = 12

-- Id facon nanoid. ⚠️ La forme exacte est DIFFEREE au memo §7.7 -- si elle change un jour,
-- les id DEJA emis font foi : on ne les regenere jamais, et le validateur doit rester
-- tolerant aux anciens.
function PK.NewId()
    local t = {}
    for i = 1, ID_LEN do
        local n = math.random(#ALPHABET)
        t[i] = ALPHABET:sub(n, n)
    end
    return table.concat(t)
end

-- « On tronque ce qui s'affiche, on VALIDE ce qui identifie » (memo §12.4). Un identifiant
-- tronque produirait une donnee plausible mais fausse, qui casse le lien en silence.
function PK.IsValidId(s)
    return type(s) == "string" and #s == ID_LEN and s:match("^[" .. ALPHABET .. "]+$") ~= nil
end
