-- ECP Packager - Core/Diagnose.lua
-- Etat REEL de l'accroche a ECP. Existe parce que « a quel ECP suis-je connecte ? » est
-- une question qui se pose vraiment sur cette machine : la copie publiee et la copie Dev
-- coexistent, portent le meme titre a un suffixe pres, et declarent les MEMES
-- SavedVariables. Se tromper de copie se voit tard, et mal.
local addonName, PK = ...

-- Les deux noms de DOSSIER possibles pour ECP. C'est le dossier qui identifie un addon
-- pour WoW, pas son titre.
local CANDIDATES = { "EiikoCooldownPlanner", "EiikoCooldownPlannerDev" }

local function yn(b) return b and "|cff33ff99oui|r" or "|cffff5555non|r" end

function PK.Diagnose()
    PK:Print(("Packager |cffffd100%s|r v%s"):format(addonName, tostring(PK.VERSION)))

    -- 1. Quelles copies d'ECP sont installees / activees / chargees ?
    local loaded = {}
    for _, name in ipairs(CANDIDATES) do
        local exists = C_AddOns.DoesAddOnExist and C_AddOns.DoesAddOnExist(name)
        if exists then
            local isLoaded = C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(name)
            local state    = C_AddOns.GetAddOnEnableState
                             and C_AddOns.GetAddOnEnableState(name, UnitName("player"))
            PK:Print(("  %-26s installe, charge:%s (enableState=%s)")
                :format(name, yn(isLoaded), tostring(state)))
            if isLoaded then loaded[#loaded + 1] = name end
        else
            PK:Print(("  %-26s |cff808080absent|r"):format(name))
        end
    end

    -- ⚠️ Les deux copies declarent les MEMES SavedVariables (HealPlannerDB, ECPlannerDB...).
    -- Actives ensemble, elles ecrivent le meme fichier et la derniere chargee ecrase
    -- l'autre : perte de donnees silencieuse.
    if #loaded > 1 then
        PK:Print("|cffff5555  DEUX copies d'ECP sont chargees en meme temps. Elles partagent "
            .. "les memes SavedVariables et vont s'ecraser. N'en garde qu'UNE active.|r")
    end

    -- 2. Le pont : qui a effectivement pose la globale ?
    local b = _G.ECPBridge
    if type(b) ~= "table" then
        PK:Print("|cffff5555  _G.ECPBridge absent|r -- aucune copie d'ECP n'expose le pont.")
        PK:Print("  Seule la copie qui contient Core/Bridge.lua le pose (la Dev pour l'instant).")
        return
    end
    PK:Print(("  pont : addon=|cffffd100%s|r version=%s api=%s")
        :format(tostring(b.addonName), tostring(b.version), tostring(b.apiVersion)))

    if b.addonName ~= addonName:gsub("PackagerDev$", "Dev"):gsub("Packager$", "") then
        -- Simple remarque : le Packager Dev s'attend normalement a parler a l'ECP Dev.
        PK:Print("|cffffb0b0  (le pont vient d'une copie differente de celle attendue)|r")
    end

    -- 3. Ce qu'on atteint reellement a travers lui.
    local ecp = PK.ECP()
    if not ecp then
        PK:Print("|cffff5555  resolution refusee :|r " .. tostring(PK.BridgeError()))
        return
    end
    local nDungeons = 0
    for _ in pairs((ecp.db2 and ecp.db2.dungeons) or {}) do nDungeons = nDungeons + 1 end
    PK:Print(("  atteint : Components=%s content=%d donjon(s) db2=%d donjon(s) avec variantes")
        :format(yn(ecp.UI and ecp.UI.Components ~= nil), #(ecp.content or {}), nDungeons))
end
