-- ECP Packager - Core/Commands.lua
-- Un seul point d'entree. Volontairement distinct de /ecp : ce sont deux addons.
local addonName, PK = ...

SLASH_ECPPACK1 = "/ecppack"
SLASH_ECPPACK2 = "/ecpp"

SlashCmdList["ECPPACK"] = function(msg)
    local cmd = (msg or ""):lower():match("^(%S*)")
    if cmd == "status" then
        PK.Diagnose()
        return
    elseif cmd == "test" then
        -- Aller-retour de format sur la spe selectionnee dans la fenetre.
        PK.SelfTest.RoundTrip(PK.SelectedSpec and PK.SelectedSpec() or nil)
        return
    elseif cmd == "help" then
        PK:Print("/ecpp          - opens the packager window")
        PK:Print("/ecpp status   - which ECP the packager is linked to")
        PK:Print("/ecpp test     - format round-trip on the selected spec (dev)")
        return
    end
    PK.ToggleWindow()
end
