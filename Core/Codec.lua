-- ECP Packager - Core/Codec.lua
-- Fabrication et encodage du CONTENEUR publie (memo §10.4, §12.2, §12.4).
--
-- FORME DU FIL :
--     ecp;3;catalog
--     <base64 du payload>
--
-- L'en-tete texte AVANT le base64 n'est pas decoratif : c'est le SEUL levier sur le parc
-- deja installe (memo §6.1). Un ECP actuel reconnait le prefixe `ecp;`, lit le numero de
-- format 3 > 2, et affiche « This plan was exported by a newer version of the addon » --
-- sans qu'on ait eu quoi que ce soit a livrer a l'avance. Avec du base64 nu il aurait dit
-- « invalid or corrupted string » pour une chaine parfaitement saine.
--
-- Le `minVersion` du payload, lui, ne sert qu'aux versions FUTURES : un client deja
-- deploye ne sait pas qu'il existe. Les deux mecanismes ne couvrent pas la meme population,
-- il faut les deux.
--
-- ⚠️ ON N'ENCODE PAS NOUS-MEMES. Le pipeline (CBOR -> Deflate -> Base64) appartient a ECP
-- et n'existe qu'UNE fois, dans `Share.EncodeRaw` / `Share.DecodeRaw`. Raison : le LECTEUR
-- d'une chaine de catalogue, c'est ECP chez le joueur. Deux implementations independantes
-- du meme pipeline devraient s'accorder sans que rien ne le verifie -- le jour ou l'une
-- change son `Enum.Base64Variant`, l'autre repond « chaine corrompue » a une chaine
-- parfaitement valide, et c'est intracable.
--   Le PIPELINE est a ECP. Le PAYLOAD (la forme du conteneur) est a nous.
local addonName, PK = ...

PK.Codec = PK.Codec or {}
local Codec = PK.Codec

local WIRE_KIND   = "catalog"
local WIRE_FORMAT = 3          -- > 2 : declenche le bon message chez les ECP actuels
local PAYLOAD_V   = 1          -- version de la STRUCTURE du payload

-- ⚠️ Constante de FORMAT, surtout PAS `PK.VERSION` (memo §12.2 / §6.2). Stamper la version
-- courante de l'auteur verrouillerait un lecteur en 1.3.0 qui sait pourtant lire le format.
-- A ne bumper que si le format change vraiment.
local MIN_READER_VERSION = "1.2.0"

local TEXT_MAX = 64            -- memo §12.4 : on TRONQUE ce qui s'affiche

-- (Pas d'enum d'encodage ici : ils vivent chez ECP, dans Share.lua. C'est precisement
--  le doublon qu'on evite -- deux jeux d'enum qui divergent = chaines illisibles.)

--------------------------------------------------------------------------------
-- Assainissement
--------------------------------------------------------------------------------

-- « On tronque ce qui s'affiche, on valide ce qui identifie » (memo §12.4).
-- Ceci est la moitie « tronquer ». Un texte trop long est une maladresse, pas une attaque :
-- il ne doit jamais faire echouer une publication.
local function text(s)
    if type(s) ~= "string" then return nil end
    s = strtrim(s)
    if s == "" then return nil end
    return s:sub(1, TEXT_MAX)
end

--------------------------------------------------------------------------------
-- Construction du payload
--------------------------------------------------------------------------------

-- Carte createur, une SEULE fois pour tout le conteneur (memo §10.4). La stocker par pack
-- donnerait N copies divergentes des memes reseaux.
-- `at` date le PROFIL, pas la publication : c'est lui qui arbitre quelle carte gagne chez
-- un destinataire qui importe des packs dans le desordre (memo §7.5).
local function CreatorCard()
    local c = PK.Creator.Get()
    return {
        id      = c.id,                 -- valide : la publication l'exige (Codec.Publish)
        name    = text(c.name),
        at      = c.at,
        twitch  = text(c.twitch),
        x       = text(c.x),
        discord = text(c.discord),
    }
end

-- Une entree du fil = une VARIANTE (memo §2.3), reduite a la liste blanche du §12.5.
-- Ce qui ne voyage pas : `id` (compteur LOCAL, entrerait en collision chez le lecteur),
-- `imported`, `synced`, `syncFrom`, `base`, `isTemplate`.
local function WireEntry(e)
    local v = e.snapshot
    if type(v) ~= "table" then return nil end
    return {
        cid = e.catalogVariantId,       -- identite de l'entree : stable entre publications
        nm  = text(v.name) or "?",
        hl  = v.healer,                 -- de-factorise : chaque entree se valide seule (§12.1)
        dID = v.dID,
        ext = v.externals,
        tsp = v.talentSpells,
        asg = v.assignments,
    }
end

-- Conteneur de tous les packs d'une spe. Renvoie (payload, nbPacks, nbEntrees).
--
-- Il n'y a pas de marqueur de suppression : RETIRER une entree de la composition suffit.
-- Son absence de l'instantane de CE donjon dit au lecteur de la supprimer (memo §10.5), et
-- comme un pack ne couvre qu'un donjon, importer le pack KR ne touche jamais aux entrees de
-- BV -- ce qui serait arrive avec un export global unique.
function Codec.BuildContainer(spec)
    local db = PK.db
    if not (db and spec) then return nil end

    local packs, nEntries = {}, 0
    for _, p in pairs(db.packs) do
        if p.spec == spec then
            local entries = {}
            for _, e in ipairs(p.entries) do
                local w = WireEntry(e)
                if w then entries[#entries + 1] = w end   -- TABLEAU : l'ordre porte de
            end                                           -- l'information (§12.5)
            -- Un pack a ZERO entree veut dire « supprime TOUT dans ce donjon » (memo §10.6) :
            -- le geste le plus destructif du systeme. On ne l'emet que s'il a un sens --
            -- c'est-a-dire si ce pack a DEJA ete diffuse et qu'il y a donc quelque chose a
            -- retirer chez les gens. Un pack vide jamais publie est du bruit : l'emettre
            -- ferait porter un ordre de suppression a un donjon que personne n'a recu.
            if #entries > 0 or PK.Pack.WasPublished(p) then
                packs[#packs + 1] = {
                    pid = p.packId,
                    dID = p.dID,
                    nm  = text(p.name),
                    at  = (GetServerTime and GetServerTime()) or time(),
                    ent = entries,
                }
                nEntries = nEntries + #entries
            end
        end
    end
    if #packs == 0 then return nil end

    return {
        v    = PAYLOAD_V,
        min  = MIN_READER_VERSION,
        spec = spec,
        cr   = CreatorCard(),
        pk   = packs,
    }, #packs, nEntries
end

--------------------------------------------------------------------------------
-- Encodage
--------------------------------------------------------------------------------

-- table -> chaine transportable. On ne fait que POSER L'ENVELOPPE autour de ce qu'ECP
-- encode : le pipeline lui appartient (cf. en-tete), nous ne possedons que la forme du
-- conteneur et l'en-tete texte.
function Codec.Encode(payload)
    local ecp = PK.ECP()
    if not (ecp and ecp.Share and ecp.Share.EncodeRaw) then
        return nil, "ECP's encoding pipeline is unavailable."
    end
    local b64 = ecp.Share.EncodeRaw(payload)
    if type(b64) ~= "string" then return nil, "Encoding failed." end
    return ("ecp;%d;%s\n%s"):format(WIRE_FORMAT, WIRE_KIND, b64)
end

-- Pendant du precedent : enveloppe retiree, puis le pipeline d'ECP. Renvoie (payload, nil)
-- ou (nil, message). Sert au futur import cote joueur et a un aller-retour de test.
function Codec.Decode(str)
    if type(str) ~= "string" then return nil, "Empty string." end
    local fmt, kind, b64 = str:match("^%s*ecp;(%d+);([^\n]*)\n(.*)$")
    if not fmt then return nil, "This is not an ECP string." end
    if tonumber(fmt) ~= WIRE_FORMAT or kind ~= WIRE_KIND then
        return nil, ("Unexpected type: ecp;%s;%s"):format(fmt, tostring(kind))
    end
    local ecp = PK.ECP()
    if not (ecp and ecp.Share and ecp.Share.DecodeRaw) then
        return nil, "ECP's decoding pipeline is unavailable."
    end
    local payload = ecp.Share.DecodeRaw((b64:gsub("%s", "")))
    if type(payload) ~= "table" then return nil, "Unreadable or corrupted string." end
    return payload
end

-- Publie la spe : construit, encode, et DATE les packs publies.
-- Renvoie (chaine, nbPacks, nbEntrees) ou (nil, message).
function Codec.Publish(spec)
    -- Garde d'identite : un pack sans createur ne peut etre ni regroupe, ni cherche, ni
    -- attribue chez le destinataire (memo §7). Le laisser partir mettrait en circulation
    -- des chaines definitivement anonymes -- et une chaine diffusee ne se rattrape pas.
    if not PK.Creator.IsComplete() then
        return nil, "Set your creator profile first (name + ID) -- see the Creator button."
    end
    local payload, nPacks, nEntries = Codec.BuildContainer(spec)
    if not payload then return nil, "No pack to publish for this spec." end

    local str, err = Codec.Encode(payload)
    if not str then return nil, err end

    -- Horodatage APRES un encodage reussi : une publication ratee ne doit pas laisser
    -- croire que quelque chose est parti. Le timestamp remplace le compteur d'increment
    -- (memo §12.2) -- il survit a une perte de base, la ou un compteur repartirait a 1 et
    -- ferait passer la republication pour plus ancienne que ce que les gens ont deja.
    local now = (GetServerTime and GetServerTime()) or time()
    for _, p in pairs(PK.db.packs) do
        if p.spec == spec then p.publishedAt = now end
    end

    return str, nPacks, nEntries
end
