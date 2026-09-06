-- ECP Packager - UI/CreatorFrame.lua
-- Ecran du PROFIL CREATEUR (memo §7). Batie avec les composants d'ECP, comme le reste.
--
-- ⚠️ Les champs RESEAUX (twitch / x / discord) sont MASQUES : on ne demande plus que le
-- pseudo. Le modele les garde (`Creator.FIELDS`, `Creator.Set/Get`) -- meme statut que
-- `Creator.Restore` : de la logique deja ecrite qu'on ne jette pas -- mais plus rien ne les
-- saisit, et `Codec.CreatorCard` ne les emet plus.
--
-- Une valeur deja enregistree n'est PAS effacee : on ne touche pas aux donnees du joueur,
-- elle dort dans la base. Les rouvrir = remettre les trois `Field()` ici et les trois
-- lignes dans la carte du codec. Rien d'autre.
local addonName, PK = ...

local W, H   = 460, 210
local PAD    = 16
local ROW    = 30
local LBL_W  = 90
local BOX_W  = 300

local m       -- modale, construite a la demande

-- Une ligne « libelle + champ de saisie ».
local function Field(parent, y, label, placeholder)
    local l = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    l:SetPoint("TOPLEFT", PAD, y)
    l:SetWidth(LBL_W); l:SetJustifyH("LEFT")
    l:SetText(label)

    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetPoint("TOPLEFT", PAD + LBL_W, y + 4)
    eb:SetSize(BOX_W, 22)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- Borne de saisie alignee sur la troncature du codec (memo §12.4) : autant empecher
    -- de taper ce qui serait coupe a la publication, plutot que de le couper en silence.
    eb:SetMaxLetters(64)
    eb._ph = placeholder
    return eb
end

local function Build()
    if m then return m end
    local C = PK.Components()
    if not C then return nil end

    m = C.Window(UIParent, { name = "ECPPackagerCreator", title = "Creator profile",
                             width = W, height = H,
                             bgTexture = C.ModalBackgroundTexture() })
    C.ModalBackground(m)
    m:SetFrameStrata("FULLSCREEN_DIALOG"); m:SetToplevel(true)
    tinsert(UISpecialFrames, "ECPPackagerCreator")
    m:Hide()

    local c = m.content
    local y = -PAD

    m.intro = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    m.intro:SetPoint("TOPLEFT", PAD, y)
    m.intro:SetPoint("RIGHT", c, "RIGHT", -PAD, 0)
    m.intro:SetJustifyH("LEFT"); m.intro:SetWordWrap(true)
    m.intro:SetText("This travels with every pack you publish, so readers can find you. "
        .. "It is a declared identity, not a proof.")
    y = y - 44

    m.name = Field(c, y, "Name", "public handle");  y = y - ROW

    -- ⚠️ L'identifiant de createur n'est NI AFFICHE NI EDITABLE (decision). Il est genere
    -- une fois, en silence, et voyage dans chaque pack -- mais il ne se montre pas.
    -- Consequence assumee : plus de chemin de recuperation. Une reinstallation ou un second
    -- compte WoW produit une NOUVELLE identite, et les packs deja diffuses restent sous
    -- l'ancienne (deux « Eiiko » distincts chez les lecteurs). `Creator.Restore` existe
    -- toujours dans le modele, sans aucun appelant : rebrancher la recuperation ne
    -- demanderait qu'un point d'entree, pas une refonte.

    m.save = C.TextButton(c, { text = "Save", width = 110, onClick = function()
        PK.Creator.Set("name", m.name:GetText())
        PK.Creator.EnsureId()      -- genere l'identifiant au premier enregistrement
        PK.RenderCreator()
        if PK.RefreshWindow then PK.RefreshWindow() end
        PK:Print("Creator profile saved.")
    end })
    m.save:SetPoint("BOTTOMRIGHT", -PAD, PAD)

    local close = C.TextButton(c, { text = "Close", width = 110,
                                    onClick = function() m:Hide() end })
    close:SetPoint("RIGHT", m.save, "LEFT", -8, 0)

    return m
end

function PK.RenderCreator()
    if not m then return end
    local c = PK.Creator.Get()
    m.name:SetText(c.name or "")
end

function PK.ToggleCreator()
    if not Build() then
        PK:Print("|cffff5555" .. (PK.BridgeError() or "ECP not found.") .. "|r")
        return
    end
    if m:IsShown() then m:Hide(); return end
    PK.RenderCreator()
    m:Show(); m:Raise()
end
