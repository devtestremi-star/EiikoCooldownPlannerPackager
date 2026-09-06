-- ECP Packager - UI/Window.lua
-- Fenetre PRINCIPALE, entierement a part de celle d'ECP -- mais batie avec SES composants
-- et SES icones (memo §12.6). On ne duplique ni les widgets ni la resolution d'icones.
--
-- LAYOUT :
--   1. une RANGEE d'icones de spe heal (le choix de spe, en un coup d'oeil) ;
--   2. une LIGNE PAR DONJON : icone + acronyme, les variantes deja dans le pack, et un
--      bouton Add qui ouvre la liste des variantes disponibles.
--
-- Les huit donjons sont donc visibles simultanement : l'ecran EST la check-list de
-- completude du memo §12.7, plutot que de la simuler avec un compteur.
local addonName, PK = ...

local W, H      = 1032, 624   -- +20 % : les puces a deux lignes demandent de la place
local PAD       = 14
local SPEC_ICON = 34      -- icone de spe dans la rangee du haut
local SPEC_GAP  = 8
local DUNG_ICON = 26
local CHIP_H    = 48      -- hauteur d'UNE puce (titre + pastilles)
local CHIP_VGAP = 4       -- ecart vertical entre deux rangees de puces
local CHIP_HGAP = 6
local ROW_PAD   = 8
-- Hauteur d'une ligne de donjon selon le nombre de RANGEES de puces qu'elle porte.
local function RowHeight(lines)
    lines = math.max(lines or 1, 1)
    return ROW_PAD + lines * CHIP_H + (lines - 1) * CHIP_VGAP
end
local ABBR_W    = 52
local ADD_W     = 62

-- Puce de variante
local NAME_MAX  = 25      -- au-dela : ellipse
local CHIP_ICON = 18
local CHIP_GAP  = 3
local CHIP_PADX = 8
local CHIP_MAXI = 8       -- pastilles affichees avant le « +N »

local win
local selSpec, hoverChip

--------------------------------------------------------------------------------
-- Acces a ECP (lecture seule -- cf. Core/Bridge.lua)
--------------------------------------------------------------------------------

-- Tronque a `maxChars` CARACTERES, pas a maxChars octets.
-- ⚠️ `#s` compte des OCTETS : couper dedans un caractere accentue produit un remplacement
-- invalide (le fameux losange noir), et les noms de variantes en portent souvent. On avance
-- donc caractere par caractere -- en UTF-8, un octet de tete est < 0x80 ou >= 0xC0.
local function truncate(s, maxChars)
    if type(s) ~= "string" then return "" end
    local n, i, len = 0, 1, #s
    while i <= len do
        local b = s:byte(i)
        local step = (b < 0x80 and 1) or (b < 0xE0 and 2) or (b < 0xF0 and 3) or 4
        if n == maxChars then return s:sub(1, i - 1) .. "..." end
        n, i = n + 1, i + step
    end
    return s
end

local function esc(s)
    local ecp = PK.ECP()
    if ecp and ecp.EscapeMarkup then return ecp.EscapeMarkup(s) end
    return (type(s) == "string") and (s:gsub("|", "||")) or s
end

-- Variantes d'ECP pour (spe, donjon). Filtre par PK.CanPackage : on ne PROPOSE jamais ce
-- qu'on refuserait d'ajouter (memo §12.3).
local function VariantsFor(specKey, dID)
    local ecp = PK.ECP()
    local store = ecp and ecp.db2 and ecp.db2.dungeons and ecp.db2.dungeons[dID]
    if not store or not store.variants then return {} end
    local out = {}
    for _, v in pairs(store.variants) do
        if v.healer == specKey and PK.CanPackage(v) then out[#out + 1] = v end
    end
    table.sort(out, function(a, b) return (a.id or 0) < (b.id or 0) end)
    return out
end

local function LiveVariant(dID, variantId)
    local ecp = PK.ECP()
    local store = ecp and ecp.db2 and ecp.db2.dungeons and ecp.db2.dungeons[dID]
    return store and store.variants and store.variants[variantId] or nil
end

--------------------------------------------------------------------------------
-- Briques
--------------------------------------------------------------------------------

-- Bouton-icone de spe heal. L'icone vient de la facade d'ECP (HR.Icons) : elle sait
-- qu'un profil se rend par son icone de SPE, avec repli sur la classe, et qu'une planche
-- de classe exige ses TexCoord.
local function BuildSpecButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(SPEC_ICON, SPEC_ICON)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.sel = b:CreateTexture(nil, "OVERLAY")
    b.sel:SetPoint("TOPLEFT", -2, 2); b.sel:SetPoint("BOTTOMRIGHT", 2, -2)
    b.sel:SetColorTexture(1, 0.82, 0, 0.9)
    b.sel:SetDrawLayer("BACKGROUND")
    b.sel:Hide()
    b:SetHighlightTexture("Interface\\Buttons\\WHITE8x8", "ADD")
    local hl = b:GetHighlightTexture(); if hl then hl:SetVertexColor(1, 1, 1, 0.18) end
    return b
end

-- Une « puce » de variante deja dans le pack : DEUX lignes.
--   1. le nom, tronque a NAME_MAX caracteres ;
--   2. la compo defensive de la variante, en pastilles avec la duree dans un bandeau noir.
--
-- Cliquable dans son ensemble : elle ouvre le menu d'actions. Un menu plutot que des
-- boutons par variante -- avec plusieurs variantes par donjon sur une seule ligne, ils
-- deborderaient largement.
--
-- Les pastilles sont des `C.ImageText` (non interactives) et NON des `C.ImageButton` :
-- un bouton imbrique avalerait les clics destines a la puce.
local function BuildChip(parent)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    -- ⚠️ ANTISLASHS DOUBLES, obligatoirement. `\B` et `\W` ne sont pas des echappements
    -- connus de Lua : le langage avale alors l'antislash SANS la moindre erreur, et le
    -- chemin devient "InterfaceButtonsWHITE8x8". Il ne pointe sur rien -- donc ni fond ni
    -- surbrillance, et pas un message pour le signaler. C'etait le cas ici.
    b:SetBackdrop({ bgFile   = "Interface\\Buttons\\WHITE8x8",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
                    insets   = { left = 3, right = 3, top = 3, bottom = 3 } })
    -- Fond nettement plus clair que la modale (qui porte une image sombre + un voile) :
    -- c'est le contraste, pas la couleur, qui detache les puces du fond.
    b:SetBackdropColor(0.20, 0.21, 0.24, 0.96)
    b:SetBackdropBorderColor(0.45, 0.45, 0.50, 1)
    b:SetHighlightTexture("Interface\\Buttons\\WHITE8x8", "ADD")
    local hl = b:GetHighlightTexture(); if hl then hl:SetVertexColor(1, 1, 1, 0.14) end

    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.name:SetPoint("TOPLEFT", CHIP_PADX, -5)
    b.name:SetJustifyH("LEFT")

    b.icons = {}      -- pool de pastilles
    b.more  = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.more:Hide()
    return b
end

-- Remplit la seconde ligne et renvoie la largeur occupee par les pastilles.
-- Les descripteurs viennent d'ECP (`HR.VariantIconItems`) : c'est LA definition de « ce
-- que contient une variante » en images -- icone de spe, CD du heal selon ses talents,
-- puis externals repetes par exemplaire. La reecrire ici donnerait deux definitions qui
-- divergeraient au premier changement de compo.
local function LayoutChipIcons(chip, variantOrSnapshot)
    local C   = PK.Components()
    local ecp = PK.ECP()
    for _, it in ipairs(chip.icons) do it:Hide() end
    chip.more:Hide()
    if not (ecp and ecp.VariantIconItems) then return 0 end

    local items = ecp.VariantIconItems(variantOrSnapshot) or {}
    local shown = math.min(#items, CHIP_MAXI)
    local x = CHIP_PADX
    for i = 1, shown do
        local item = items[i]
        local it = chip.icons[i]
        if not it then
            it = C.ImageText(chip, { size = CHIP_ICON, banner = true, textSize = 8 })
            chip.icons[i] = it
        end
        -- Facade d'icones : elle sait qu'un profil de heal se rend par sa spe (repli
        -- classe, avec TexCoord de planche) et qu'un defensif est une icone carree.
        if item.spec then
            if ecp.Icons then ecp.Icons.Apply(it.image, "healer", item.spec) end
            it:SetText("")
            if it.banner then it.banner:Hide() end
        else
            if ecp.Icons then ecp.Icons.Apply(it.image, "defensive", item.key) end
            -- Bandeau noir avec la duree, uniquement quand elle a un sens.
            local show = item.banner and item.cd and item.cd > 0
            it:SetText(show and ecp.FormatCooldown(item.cd) or "")
            if it.banner then it.banner:SetShown(show and true or false) end
        end
        it:ClearAllPoints()
        it:SetPoint("TOPLEFT", x, -22)
        it:Show()
        x = x + CHIP_ICON + CHIP_GAP
    end

    if #items > shown then
        chip.more:SetText(("+%d"):format(#items - shown))
        chip.more:ClearAllPoints()
        chip.more:SetPoint("LEFT", chip, "TOPLEFT", x, -22 - CHIP_ICON / 2)
        chip.more:Show()
        x = x + 22
    end
    return x - CHIP_GAP
end

--------------------------------------------------------------------------------
-- Menus
--------------------------------------------------------------------------------

local Render

-- Actions sur une entree deja dans le pack.
local function OpenChipMenu(anchor, pack, entry, live, state)
    local Pack = PK.Pack
    MenuUtil.CreateContextMenu(anchor, function(owner, root)
        root:CreateTitle(esc(tostring(entry.name)))
        if state == "modified" then
            -- Ne proposer « Update » que s'il y a effectivement du neuf a figer.
            root:CreateButton("Update from ECP", function()
                Pack.RefreshEntry(pack, live); Render()
            end)
        end
        -- Un seul geste de retrait. Retirer de la composition EST la suppression : l'entree
        -- disparait de l'instantane de ce donjon, et le lecteur la supprime de son
        -- catalogue. Rien ne reste barre a l'ecran une fois le geste fait.
        root:CreateButton("Delete from pack", function()
            Pack.RemoveEntry(pack, entry.variantId); Render()
        end)
    end)
end

-- Variantes disponibles pour ce donjon (celles qui ne sont pas deja dans le pack).
local function OpenAddMenu(anchor, dID)
    local Pack = PK.Pack
    local pack = Pack.Find(selSpec, dID)
    local inPack = {}
    for _, e in ipairs((pack and pack.entries) or {}) do inPack[e.variantId] = true end

    local avail = {}
    for _, v in ipairs(VariantsFor(selSpec, dID)) do
        if not inPack[v.id] then avail[#avail + 1] = v end
    end

    MenuUtil.CreateContextMenu(anchor, function(owner, root)
        root:CreateTitle("Add a variant")
        if #avail == 0 then
            root:CreateTitle("|cff808080No other variant of this spec here|r")
            return
        end
        for _, v in ipairs(avail) do
            root:CreateButton(esc(tostring(v.name)), function()
                Pack.AddVariant(selSpec, dID, v); Render()
            end)
        end
    end)
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local function BuildDungeonRow(parent)
    local C = PK.Components()
    local r = CreateFrame("Frame", nil, parent)
    r:SetHeight(RowHeight(1))

    -- Ancrages en HAUT, pas au centre : une ligne qui grandit (puces sur deux rangees) ne
    -- doit pas faire descendre l'icone, l'acronyme et Add au milieu du vide.
    local topY = -(ROW_PAD / 2) - (CHIP_H - DUNG_ICON) / 2
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(DUNG_ICON, DUNG_ICON)
    r.icon:SetPoint("TOPLEFT", 4, topY)

    r.abbr = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    r.abbr:SetPoint("LEFT", r.icon, "RIGHT", 6, 0)
    r.abbr:SetWidth(ABBR_W); r.abbr:SetJustifyH("LEFT")

    r.add = C.TextButton(r, { text = "Add", width = ADD_W, height = CHIP_H - 12 })
    r.add:SetPoint("TOPRIGHT", -4, -(ROW_PAD / 2) - 6)

    r.chips = {}      -- pool de puces (une par variante du pack)
    return r
end

local function Build()
    if win then return win end
    local C = PK.Components()
    if not C then return nil end

    win = C.Window(UIParent, {
        name = "ECPPackagerWindow",
        title = "ECP Packager" .. (addonName:find("Dev", 1, true) and "  |cffff8080[Dev]|r" or ""),
        width = W, height = H,
        bgTexture = C.ModalBackgroundTexture(),
    })
    -- Cadrage « cover » + voile sombre. Recette d'ECP, extraite en composant plutot que
    -- recopiee ici : elle vivait deja a l'identique dans cinq de ses modales.
    C.ModalBackground(win)
    win:SetFrameStrata("HIGH")
    tinsert(UISpecialFrames, "ECPPackagerWindow")
    win:Hide()

    local c = win.content

    win.status = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    win.status:SetPoint("TOPLEFT", PAD, -PAD)
    win.status:SetPoint("RIGHT", c, "RIGHT", -PAD, 0)
    win.status:SetJustifyH("LEFT")

    win.specBtns = {}
    win.dungRows = {}

    -- Zone DEFILANTE des donjons. La rangee de spes (en haut) et les boutons (en bas)
    -- restent fixes : ce sont des reperes, ils ne doivent pas partir en defilant.
    local listTop = -PAD - 22 - SPEC_ICON - 14
    win.scroll = CreateFrame("ScrollFrame", nil, c, "UIPanelScrollFrameTemplate")
    win.scroll:SetPoint("TOPLEFT", PAD, listTop)
    win.scroll:SetPoint("BOTTOMRIGHT", -PAD - 26, PAD + 34)   -- place scrollbar + rangee du bas

    win.list = CreateFrame("Frame", nil, win.scroll)
    win.list:SetSize(1, 1)
    win.scroll:SetScrollChild(win.list)
    -- ⚠️ La largeur de l'enfant defilant DOIT etre posee explicitement : un ScrollChild n'en
    -- herite pas, et les lignes qui s'y ancrent a droite se retrouveraient sans largeur.
    win.scroll:SetScript("OnSizeChanged", function(self, w) if w and w > 0 then win.list:SetWidth(w) end end)
    win.list:SetWidth(W - PAD * 2 - 26)

    win.hint = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.hint:SetPoint("TOPLEFT", PAD, listTop)

    win.publish = C.TextButton(c, { text = "Publish spec", width = 150, onClick = function()
        PK.PublishCurrent()
    end })
    win.publish:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    win.publish:Hide()

    win.publishHint = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.publishHint:SetPoint("RIGHT", win.publish, "LEFT", -10, 0)
    win.publishHint:SetJustifyH("RIGHT")

    win.creator = C.TextButton(c, { text = "Creator", width = 110, onClick = function()
        PK.ToggleCreator()
    end })
    win.creator:SetPoint("BOTTOMLEFT", PAD, PAD)

    win.creatorHint = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    win.creatorHint:SetPoint("LEFT", win.creator, "RIGHT", 10, 0)
    win.creatorHint:SetJustifyH("LEFT")

    return win
end

function PK.SelectedSpec() return selSpec end

--------------------------------------------------------------------------------
-- Rendu
--------------------------------------------------------------------------------

-- Etiquette et couleur d'une puce selon l'etat DERIVE de l'entree (memo §10.9 : l'etat se
-- recalcule, il ne se stocke pas -- un etat derive ne peut pas deriver).
-- Libelle de la 1re ligne + couleur de fond, selon l'etat DERIVE de l'entree.
-- Le nom est tronque a NAME_MAX caracteres AVANT echappement : on compte les caracteres du
-- nom, pas ceux du markup.
-- Renvoie (libelle, couleur de fond, couleur de bordure). Chaque etat se distingue par le
-- fond ET la bordure : la couleur seule serait illisible pour un daltonien, et le liseré
-- porte le signal meme quand le fond passe derriere une image sombre.
local function ChipLook(entry, state)
    local name = esc(truncate(tostring(entry.name), NAME_MAX))
    if state == "missing" then
        -- La variante n'existe plus dans ECP. On le SIGNALE sans rien retirer : l'entree
        -- garde son snapshot, donc elle reste publiable, et le createur tranche.
        return "|cffff8080" .. name .. "|r",
               { 0.38, 0.16, 0.16, 0.96 }, { 0.85, 0.30, 0.30, 1 }
    elseif state == "modified" then
        return name .. "  |cff33ff99*|r",
               { 0.16, 0.30, 0.20, 0.96 }, { 0.30, 0.80, 0.45, 1 }
    end
    return name, { 0.20, 0.21, 0.24, 0.96 }, { 0.45, 0.45, 0.50, 1 }
end

Render = function()
    local ecp = PK.ECP()
    local c   = win.content
    local Pack = PK.Pack

    for _, b in ipairs(win.specBtns) do b:Hide() end
    for _, r in ipairs(win.dungRows) do r:Hide() end

    if not ecp then
        win.status:SetText("|cffff5555" .. (PK.BridgeError() or "ECP not found.") .. "|r")
        win.hint:SetText("")
        win.scroll:Hide()
        win.publish:Hide()
        return
    end

    local who, ver = PK.ECPIdentity()
    win.status:SetText(("Linked to |cffffd100%s|r v%s"):format(tostring(who), tostring(ver)))

    -- 1. RANGEE DE SPES ---------------------------------------------------------
    local x = PAD
    local specTop = -PAD - 22
    for i, prof in ipairs(ecp.HEAL_PROFILES or {}) do
        local b = win.specBtns[i]
        if not b then b = BuildSpecButton(c); win.specBtns[i] = b end
        -- Facade d'icones d'ECP : elle gere icone de spe / repli classe / TexCoord.
        if ecp.Icons then ecp.Icons.Apply(b.icon, "healer", prof) end
        b:SetScript("OnClick", function() selSpec = prof.key; Render() end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(prof.name or prof.key)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:ClearAllPoints(); b:SetPoint("TOPLEFT", x, specTop)
        b.sel:SetShown(selSpec == prof.key)
        b:Show()
        x = x + SPEC_ICON + SPEC_GAP
    end

    if not selSpec then
        win.hint:SetText("|cff808080Pick a healing spec above.|r")
        win.scroll:Hide()
        win.publish:Hide()
        win.publishHint:SetText("")
        return
    end
    win.hint:SetText("")
    win.scroll:Show()

    -- 2. UNE LIGNE PAR DONJON ---------------------------------------------------
    local y = 0
    for i, d in ipairs(ecp.content or {}) do
        local r = win.dungRows[i]
        if not r then r = BuildDungeonRow(win.list); win.dungRows[i] = r end
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", 0, y)
        r:SetPoint("RIGHT", win.list, "RIGHT", 0, 0)

        if ecp.Icons then ecp.Icons.Apply(r.icon, "dungeon", d) end
        r.abbr:SetText(d.abbr or d.name or "?")

        local dID  = d.id
        r.add:SetOnClick(function(btn) OpenAddMenu(btn, dID) end)

        -- Puces des variantes deja dans le pack, avec RETOUR A LA LIGNE.
        for _, ch in ipairs(r.chips) do ch:Hide() end
        local pack = Pack.Find(selSpec, dID)

        -- Largeur utile : de la fin de l'acronyme jusqu'au bouton Add. Mesuree a chaque
        -- rendu car elle depend de la largeur reelle de l'enfant defilant.
        local x0    = ABBR_W + DUNG_ICON + 16
        local avail = (win.list:GetWidth() or 0) - x0 - ADD_W - 16
        if avail < 80 then avail = 80 end                 -- garde-fou avant le 1er layout

        local cx, cy, lines, ci = x0, 0, 1, 0
        for _, e in ipairs((pack and pack.entries) or {}) do
            ci = ci + 1
            local ch = r.chips[ci]
            if not ch then ch = BuildChip(r); r.chips[ci] = ch end

            local live  = LiveVariant(dID, e.variantId)
            local state = Pack.EntryState(e, live)
            local label, bg, border = ChipLook(e, state)
            ch.name:SetText(label)
            ch:SetBackdropColor(unpack(bg))
            ch:SetBackdropBorderColor(unpack(border))
            ch:SetScript("OnClick", function(btn) OpenChipMenu(btn, pack, e, live, state) end)

            -- Compo affichee : la variante VIVANTE si elle existe, sinon le snapshot fige.
            -- Une entree « gone from ECP » doit montrer ce qu'elle contient encore, pas rien.
            local iconsW = LayoutChipIcons(ch, live or e.snapshot)

            -- Largeur = la plus large des deux lignes internes. Le nom peut depasser les
            -- pastilles (ou l'inverse) : mesurer les deux evite un texte rogne ou des
            -- pastilles qui debordent du cadre. Bornee a la largeur utile.
            local w = math.max((ch.name:GetStringWidth() or 0) + CHIP_PADX * 2,
                               iconsW + CHIP_PADX)
            w = math.max(math.min(w, avail), 60)

            -- Retour a la ligne. La condition `cx > x0` evite de renvoyer a la ligne une
            -- puce qui est DEJA seule en debut de rangee : plus large que l'espace utile,
            -- elle deborderait de toute facon, et la renvoyer laisserait une rangee vide.
            if cx > x0 and (cx - x0) + w > avail then
                cx    = x0
                cy    = cy - (CHIP_H + CHIP_VGAP)
                lines = lines + 1
            end

            ch:SetSize(w, CHIP_H)
            ch:ClearAllPoints()
            ch:SetPoint("TOPLEFT", cx, -(ROW_PAD / 2) + cy)
            ch:Show()
            cx = cx + w + CHIP_HGAP
        end

        local h = RowHeight(lines)
        r:SetHeight(h)
        r:Show()
        y = y - h
    end
    -- Sans cette hauteur, le ScrollFrame croit son contenu vide et la barre reste inerte.
    win.list:SetHeight(math.max(-y, 1))

    -- 3. RECAP DE PUBLICATION ---------------------------------------------------
    local nPacks, nEnt, nWiped = 0, 0, 0
    for _, p in pairs((PK.db and PK.db.packs) or {}) do
        if p.spec == selSpec then
            local live = Pack.LiveCount(p)
            -- Un pack qui partirait VIDE apres avoir ete diffuse ordonne de tout retirer
            -- dans ce donjon : ca se compte a part, c'est destructif.
            if live == 0 and Pack.WasPublished(p) then nWiped = nWiped + 1 end
            if live > 0 or Pack.WasPublished(p) then nPacks = nPacks + 1 end
            nEnt = nEnt + live
        end
    end
    local hint = ("%d dungeon(s), %d variant(s)"):format(nPacks, nEnt)
    if nWiped > 0 then hint = hint .. ("  |cffff5555%d EMPTIED|r"):format(nWiped) end
    win.publishHint:SetText(hint)
    win.publish:SetEnabled(nPacks > 0)
    win.publish:SetAlpha(nPacks > 0 and 1 or 0.4)
    win.publish:Show()

    -- Etat du profil createur : la publication l'exige, autant le montrer AVANT le refus.
    if PK.Creator.IsComplete() then
        win.creatorHint:SetText(("|cff808080%s|r"):format(esc(PK.Creator.Name() or "")))
    else
        win.creatorHint:SetText("|cffffb0b0Required before publishing|r")
    end
end

--------------------------------------------------------------------------------
-- Entrees publiques
--------------------------------------------------------------------------------

function PK.PublishCurrent()
    local spec = PK.SelectedSpec()
    if not spec then return end

    local str, a, b = PK.Codec.Publish(spec)
    if not str then
        PK:Print("|cffff5555" .. tostring(a or "Cannot publish.") .. "|r")
        return
    end

    -- On REUTILISE la modale de copie d'ECP : scroll, selection auto et lecture seule
    -- deja geres (memo §12.6).
    local ecp = PK.ECP()
    if ecp and ecp.UI and ecp.UI.ShowCopyText then
        ecp.UI.ShowCopyText("ECP Packager - " .. tostring(spec), str)
    else
        PK:Print("String generated but ECP's copy window is unavailable.")
    end
    PK:Print(("Published: %d dungeon(s), %d variant(s), %d characters."):format(a or 0, b or 0, #str))
    if win and win:IsShown() then Render() end
end

function PK.RefreshWindow()
    if win and win:IsShown() then Render() end
end

function PK.ToggleWindow()
    if not Build() then
        PK:Print("|cffff5555" .. (PK.BridgeError() or "ECP not found.") .. "|r")
        return
    end
    if win:IsShown() then win:Hide(); return end
    Render()
    win:Show()
    win:Raise()
end
