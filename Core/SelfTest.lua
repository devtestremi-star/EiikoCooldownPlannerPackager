-- ECP Packager - Core/SelfTest.lua
-- Aller-retour de format : construit -> encode -> decode -> COMPARE. Sert a valider la
-- chaine AVANT que le cote reception d'ECP existe.
--
-- Pourquoi maintenant : le format est la seule partie du systeme qui, une fois publiee,
-- ne se rattrape plus -- des chaines circuleront chez des gens. Le verifier tant qu'il
-- n'y a qu'un producteur coute quelques lignes ; le verifier apres coute une migration.
--
-- Ce n'est PAS un test unitaire (il n'y a pas de harnais en jeu) : c'est une commande de
-- dev qui exerce le chemin reel sur les vraies donnees du joueur et rapporte au chat.
local addonName, PK = ...

PK.SelfTest = PK.SelfTest or {}
local T = PK.SelfTest

local function ok(msg, ...)   PK:Print("|cff33ff99PASS|r " .. msg:format(...)) end
local function ko(msg, ...)   PK:Print("|cffff5555FAIL|r " .. msg:format(...)) end
local function info(msg, ...) PK:Print("     " .. msg:format(...)) end

-- Compare deux tables en profondeur. Renvoie (true) ou (false, chemin de la divergence).
-- On compare STRUCTURELLEMENT plutot que par serialisation : l'ordre d'iteration d'une
-- table Lua n'etant pas garanti, deux serialisations du meme contenu peuvent differer
-- (c'est le meme piege que pour l'empreinte, cf. Pack.Fingerprint).
local function deepEq(a, b, path)
    path = path or ""
    if type(a) ~= type(b) then return false, path .. " (type)" end
    if type(a) ~= "table" then
        if a ~= b then return false, ("%s (%s ~= %s)"):format(path, tostring(a), tostring(b)) end
        return true
    end
    for k, v in pairs(a) do
        local o, p = deepEq(v, b[k], path .. "." .. tostring(k))
        if not o then return false, p end
    end
    for k in pairs(b) do
        if a[k] == nil then return false, path .. "." .. tostring(k) .. " (en trop)" end
    end
    return true
end

-- Compte les entrees d'un payload (tous packs confondus).
local function countEntries(payload)
    local n = 0
    for _, p in ipairs((payload and payload.pk) or {}) do n = n + #(p.ent or {}) end
    return n
end

-- Aller-retour sur la spe donnee. Renvoie true si tout passe.
function T.RoundTrip(spec)
    if not spec then ko("aucune spe selectionnee (ouvre la fenetre et choisis-en une)."); return false end

    local built, nPacks, nEnt = PK.Codec.BuildContainer(spec)
    if not built then ko("BuildContainer n'a rien produit pour %s.", spec); return false end
    ok("build : %d pack(s), %d entree(s)", nPacks, nEnt)

    local str, err = PK.Codec.Encode(built)
    if not str then ko("encode : %s", tostring(err)); return false end
    ok("encode : %d caracteres", #str)

    -- Borne d'ENTREES (memo §12.4). C'est `Codec.Publish` qui la fait respecter pour de
    -- vrai ; on la rappelle ici parce qu'un build de test ne passe pas par Publish.
    if nEnt > 100 then
        ko("BORNE : %d entrees > 100. Le lecteur refuserait tout le catalogue.", nEnt)
    end

    -- ⚠️ On NE teste PAS le plafond de 512 Ko, et c'est delibere.
    -- Le lecteur borne `#cbor`, la charge DECOMPRESSEE (Share.DecodeRaw, MAX_DECOMPRESSED).
    -- `#str` est le base64 du flux COMPRESSE : sur des tables de plan Deflate gagne un
    -- facteur 3 a 10, donc un payload de 600 Ko decompresses tient dans ~60 a 200 Ko de
    -- base64 et passerait ce controle haut la main -- pendant que le lecteur repondrait
    -- « far too large. Nothing was read. » Un test qui NOMME la borne sans pouvoir se
    -- declencher est pire que pas de test : il rassure a tort.
    info("taille encodee : %d octets (le plafond du lecteur porte sur la charge "
         .. "DECOMPRESSEE, non mesurable d'ici).", #str)

    local back, derr = PK.Codec.Decode(str)
    if not back then ko("decode : %s", tostring(derr)); return false end
    ok("decode : %d pack(s), %d entree(s)", #(back.pk or {}), countEntries(back))

    -- LE controle qui compte : ce qui revient est-il ce qui est parti ?
    local same, where = deepEq(built, back)
    if same then
        ok("aller-retour IDENTIQUE.")
    else
        ko("divergence a %s", tostring(where))
        info("le payload ne survit pas au CBOR : un type n'est pas transporte tel quel.")
        return false
    end

    -- Piege connu du CBOR : une table Lua a cles numeriques peut revenir avec des cles
    -- STRING. Les assignments sont indexes par encounterID (nombre) -> si ca se produit,
    -- le plan serait illisible chez le lecteur, et deepEq l'aura deja signale.
    for _, p in ipairs(back.pk or {}) do
        for _, e in ipairs(p.ent or {}) do
            for encID in pairs(e.asg or {}) do
                if type(encID) ~= "number" then
                    ko("cle d'encounterID revenue en %s (%s) -- a traiter a la lecture.",
                       type(encID), tostring(encID))
                    return false
                end
            end
        end
    end
    ok("cles d'encounterID toujours numeriques apres l'aller-retour.")
    return true
end
