-- ECP Packager - Core/Pack.lua
-- Le MODELE de pack. Un pack = (creatorId, spe, donjon), cf. memo §10.3. Le `packId` en
-- est l'ADRESSE (une valeur a transporter au lieu d'un triplet) ; c'est le triplet qui
-- reste la CONTRAINTE D'UNICITE -- c'est lui qui garantit qu'il ne peut jamais exister
-- deux packs pour le meme donjon, donc qu'aucune entree ne peut etre revendiquee deux fois.
--
-- Ce fichier ne LIT ECP que par le pont, et n'y ECRIT jamais (cf. Core/Bridge.lua).
local addonName, PK = ...

PK.Pack = PK.Pack or {}
local Pack = PK.Pack

--------------------------------------------------------------------------------
-- Identifiants : deleguees a Core/Constants.lua (PK.NewId / PK.IsValidId). Le creatorId
-- partage le meme alphabet -- une seule definition, un seul validateur.
--------------------------------------------------------------------------------

Pack.NewId = PK.NewId

--------------------------------------------------------------------------------
-- Empreinte deterministe (memo §12.8)
--------------------------------------------------------------------------------

-- ⚠️ LE PIEGE : l'ordre d'iteration d'une table Lua n'est PAS garanti. Serialiser deux
-- fois le MEME contenu peut produire deux chaines differentes -- et on afficherait
-- « modifiee » a tort. L'essentiel n'est donc pas le hachage (aucune primitive n'existe
-- dans l'API) mais la marche a CLES TRIEES. Une fois qu'on l'a, elle sert aussi bien a
-- comparer qu'a produire un checksum destine a voyager.
local function walk(v, out)
    local t = type(v)
    if t == "table" then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        -- Tri sur (type, valeur) : une table peut melanger cles numeriques et chaines,
        -- et comparer un nombre a une chaine leve une erreur.
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta ~= tb then return ta < tb end
            return tostring(a) < tostring(b)
        end)
        out[#out + 1] = "{"
        for _, k in ipairs(keys) do
            out[#out + 1] = tostring(k)
            out[#out + 1] = "="
            walk(v[k], out)
            out[#out + 1] = ";"
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = tostring(v)
    end
end

-- Empreinte stable du CONTENU DE PLAN d'une variante. On ne prend que ce qui voyage
-- (memo §12.5) : le reste (id local, marqueurs) n'a pas a declencher un « modifiee ».
function Pack.Fingerprint(v)
    if type(v) ~= "table" then return "" end
    local out = {}
    walk({
        name         = v.name,
        healer       = v.healer,
        dID          = v.dID,
        externals    = v.externals,
        talentSpells = v.talentSpells,
        assignments  = v.assignments,
    }, out)
    return table.concat(out)
end

--------------------------------------------------------------------------------
-- Acces aux packs
--------------------------------------------------------------------------------

-- Le pack de (spe, donjon), ou nil. Balayage plutot qu'un index : quelques dizaines de
-- packs au maximum, et le balayage EST ce qui fait respecter la contrainte d'unicite.
function Pack.Find(spec, dID)
    local db = PK.db
    if not db then return nil end
    for _, p in pairs(db.packs) do
        if p.spec == spec and p.dID == dID then return p end
    end
    return nil
end

-- Le pack de (spe, donjon), cree a la demande. Le `packId` est frappe A LA CREATION
-- (memo §12.1), pas a la premiere publication.
function Pack.GetOrCreate(spec, dID)
    local p = Pack.Find(spec, dID)
    if p then return p end
    local db = PK.db
    if not db or not spec or not dID then return nil end
    p = {
        packId  = Pack.NewId(),
        spec    = spec,
        dID     = dID,
        entries = {},          -- TABLEAU : l'ordre porte de l'information (memo §12.5)
    }
    db.packs[p.packId] = p
    return p
end

-- L'entree qui pointe la variante locale `variantId`, et son index. nil sinon.
function Pack.FindEntry(p, variantId)
    if not p then return nil end
    for i, e in ipairs(p.entries) do
        if e.variantId == variantId then return e, i end
    end
    return nil
end

--------------------------------------------------------------------------------
-- Composition
--------------------------------------------------------------------------------

-- Instantane GELE d'une variante, pour un pack de donjon donne. UN SEUL endroit, parce que
-- les deux sites qui figent un plan (ajout et resynchro) doivent faire exactement pareil.
--
-- Deux gestes :
--   * COPIE PROFONDE -- une reference suivrait les modifications faites ensuite dans ECP,
--     le journal deviendrait un miroir et plus rien ne serait jamais detecte « modifie ».
--   * TAMPON du `dID` -- la variante vivante n'en porte peut-etre pas : celles creees avant
--     le correctif §9.1 n'ont jamais eu le champ, et ECP ne le leur ajoutera JAMAIS (aucune
--     migration au login, regle absolue du projet). Le donjon, lui, on le connait : c'est
--     celui du pack qu'on construit. On le pose donc sur la COPIE -- jamais sur l'original,
--     qui appartient a ECP (regle du §12.1 : le Packager n'ecrit pas chez lui).
--     Sans ce tampon l'entree part sans donjon, et l'import ne s'en sort que par le repli du
--     lecteur sur le `dID` du pack. Ce repli DOIT rester (des packs sans `dID` circulent
--     deja), mais il cesse d'etre le seul filet.
--
-- ⚠️ Le FINGERPRINT, lui, se calcule sur la variante VIVANTE et surtout pas sur cette copie.
-- La detection compare `Pack.Fingerprint(liveVariant)` a la valeur stockee : empreinter la
-- copie tamponnee rendrait toute variante sans `dID` eternellement « modifiee ».
local function Snapshot(ecp, variant, dID)
    local snap = ecp.DeepCopy(variant)
    if snap and dID then snap.dID = dID end
    return snap
end

-- Ajoute une variante d'ECP au pack. Frappe un `catalogVariantId` NEUF (memo §12.1 : il
-- ne vit que dans la composition du Packager, jamais sur la variante d'ECP) et fige une
-- copie du plan.
-- ⚠️ Refuse ce que le joueur n'a pas ecrit (memo §12.3) : on ne republie pas le travail
-- d'un autre sous sa propre identite.
function Pack.AddVariant(spec, dID, variant)
    local ecp = PK.ECP()
    if not (ecp and variant) then return nil end
    if not PK.CanPackage(variant) then return nil end

    local p = Pack.GetOrCreate(spec, dID)
    if not p then return nil end
    if Pack.FindEntry(p, variant.id) then return nil end     -- deja dedans

    local e = {
        catalogVariantId = Pack.NewId(),
        variantId        = variant.id,
        name             = variant.name,
        snapshot         = Snapshot(ecp, variant, dID),
        fingerprint      = Pack.Fingerprint(variant),   -- la VIVANTE, cf. Snapshot
    }
    p.entries[#p.entries + 1] = e
    return e
end

-- Nombre d'entrees du pack. Toutes voyagent : il n'y a plus de marqueur de suppression.
-- Retirer une entree de la composition EST la suppression -- son absence de l'instantane
-- du donjon suffit a la dire (memo §10.5), et le rayon d'action reste borne a ce donjon
-- puisque chaque pack est l'instantane d'UN donjon.
function Pack.LiveCount(p)
    return #((p and p.entries) or {})
end

-- Ce pack a-t-il deja ete diffuse ? Determine si le vider veut dire quelque chose.
function Pack.WasPublished(p)
    return (p and p.publishedAt) and true or false
end

-- Supprime un pack de la base du Packager.
function Pack.Delete(p)
    local db = PK.db
    if db and p and p.packId then db.packs[p.packId] = nil end
end

-- Retire une entree. Suppression FRANCHE de la composition : tant que rien n'a ete
-- publie, il n'y a aucune raison de garder une trace.
--
-- ⚠️ ET ON PURGE LE PACK S'IL DEVIENT VIDE SANS AVOIR JAMAIS ETE PUBLIE. Sans ca :
-- `AddVariant` cree le pack, on retire la variante, le pack subsiste a zero entree, et
-- `BuildContainer` le publierait -- or un pack vide signifie « supprime TOUT dans ce
-- donjon » (memo §10.6). Ajouter puis retirer une variante suffirait donc a emettre un
-- ordre de suppression que personne n'a voulu.
--   Un pack DEJA publie qui se vide, lui, exprime une intention reelle (« retire tout ce
--   que j'avais diffuse la ») : on le garde, et la publication l'annonce distinctement.
function Pack.RemoveEntry(p, variantId)
    local _, i = Pack.FindEntry(p, variantId)
    if not i then return false end
    table.remove(p.entries, i)
    if #p.entries == 0 and not Pack.WasPublished(p) then Pack.Delete(p) end
    return true
end

-- Action 3 : refiger le snapshot depuis la variante VIVANTE d'ECP.
-- « Elle etait deja dans le pack, je l'ai modifiee, je veux publier la nouvelle version. »
-- ⚠️ On evite le mot « sync » : dans ECP il designe le canal reseau qui pousse un plan d'un
-- JOUEUR A UN AUTRE. Ici c'est une copie LOCALE, a sens unique, entre deux tables du meme
-- client -- aucun rapport. Deux mecanismes qui portent le meme nom finissent confondus.
function Pack.RefreshEntry(p, variant)
    local ecp = PK.ECP()
    local e = Pack.FindEntry(p, variant and variant.id)
    if not (ecp and e) then return false end
    e.name        = variant.name
    e.snapshot    = Snapshot(ecp, variant, p and p.dID)
    e.fingerprint = Pack.Fingerprint(variant)       -- la VIVANTE, cf. Snapshot
    return true
end

--------------------------------------------------------------------------------
-- Etat d'une entree, DERIVE (jamais stocke)
--------------------------------------------------------------------------------

-- Un etat derive ne peut pas deriver : pas de drapeau a poser au bon moment, pas
-- d'incoherence possible entre le drapeau et la realite (meme raisonnement qu'au memo
-- §10.9 pour « liee / orpheline »).
--   "missing"  : la variante n'existe plus dans ECP
--   "modified" : le plan vivant differe de ce qui a ete fige
--   "ok"
--
-- ⚠️ « missing » ne retire RIEN tout seul. L'entree garde son snapshot, donc elle reste
-- parfaitement publiable -- le createur a pu supprimer la variante chez lui sans vouloir
-- la retirer de son offre. On le SIGNALE (puce rouge) et on le laisse trancher : c'est ce
-- signalement qui remplace l'ancien marqueur comme point de controle. Retirer d'office
-- serait irreversible et silencieux.
function Pack.EntryState(e, liveVariant)
    if not liveVariant then return "missing" end
    if Pack.Fingerprint(liveVariant) ~= e.fingerprint then return "modified" end
    return "ok"
end

-- Peut-on packager cette variante ? (memo §12.3 : on ne republie pas le travail d'un
-- autre sous sa propre identite -- sinon le meme plan existerait sous DEUX identites de
-- createur, avec deux flux de mises a jour.)
--
-- ⚠️ DEUX conditions, et il faut bien les DEUX -- `canEdit` ne suffit pas.
-- Cote ECP, `CanEditVariant` ne teste volontairement PAS `v.synced` : verrouiller
-- l'edition des plans recus par le canal Sync serait un changement de comportement sur
-- des donnees deja en production, mis de cote (cf. Core/Plan2.lua). Mais « ne pas
-- verrouiller l'EDITION d'un plan recu » et « autoriser sa REPUBLICATION sous mon nom »
-- sont deux questions distinctes :
--   * l'edition touche des donnees vivantes chez des joueurs -> prudence, on differe ;
--   * la publication est une feature NEUVE, rien n'existe encore -> aucune raison de
--     l'ouvrir, et toutes les raisons de la fermer.
-- On teste donc `synced` ICI, explicitement, independamment du verrou d'ECP.
function PK.CanPackage(v)
    if type(v) ~= "table" then return false end          -- echouer FERME
    if v.synced then return false end                    -- plan recu d'un tiers : jamais
    local ecp = PK.ECP()
    if ecp and type(ecp.CanEditVariant) == "function" then
        return ecp.CanEditVariant(v) and true or false   -- couvre les variantes promues
    end
    return true
end
