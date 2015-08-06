-- Author      : Potdisc
-- Create Date : 12/15/2014 8:54:35 PM
-- DefaultModule
--	votingFrame.lua	Displays everything related to handling loot for all members.
--		Will only show certain aspects depending on addon.isMasterLooter, addon.isCouncil and addon.mldb.observe

-- IDEA We're not sorting by guild rank, would require a change to how guild rank is sent

local addon = LibStub("AceAddon-3.0"):GetAddon("RCLootCouncil")
RCVotingFrame = addon:NewModule("RCVotingFrame", "AceComm-3.0")
local LibDialog = LibStub("LibDialog-1.0")
local L = LibStub("AceLocale-3.0"):GetLocale("RCLootCouncil")

local ROW_HEIGHT = 20;
local NUM_ROWS = 15;
local db
local session = 1 -- The session we're viewing
local lootTable = {} -- lib-st compatible, extracted from addon's lootTable
local sessionButtons = {}
local moreInfo = false -- Show more info frame?
local active = false -- Are we currently in session?
local candidates = {} -- Candidates for the loot, initial data from the ML
local keys = {} -- Lookup table for cols
local menuFrame -- Right click menu frame
local filterMenu -- Filter drop down menu
local enchanters -- Enchanters drop down menu frame

--@debug@
function LOOTTABLE()
	printtable(lootTable)
end
--@end-debug@

function RCVotingFrame:OnInitialize()
	self.scrollCols = {
		{ name = "",															sortnext = 2,		width = 20, },	-- 1 Class
		{ name = L["Name"],																			width = 130,},	-- 2 Candidate Name
		{ name = L["Rank"],													sortnext = 5,		width = 100,},	-- 3 Guild rank
		{ name = L["Role"],													sortnext = 5,		width = 60, },	-- 4 Role
		{ name = L["Response"],	comparesort = self.ResponseSort, sortnext = 13,		width = 250,},	-- 5 Response
		{ name = L["ilvl"],													sortnext = 7,		width = 40, },	-- 6 Total ilvl
		{ name = L["Diff"],																			width = 40, },	-- 7 ilvl difference
		{ name = L["g1"],			align = "CENTER",						sortnext = 5,		width = 20, },	-- 8 Current gear 1
		{ name = L["g2"],			align = "CENTER",						sortnext = 5,		width = 20, },	-- 9 Current gear 2
		{ name = L["Votes"], 	align = "CENTER",						sortnext = 7,		width = 40, },	-- 10 Number of votes
		{ name = L["Vote"],		align = "CENTER",						sortnext = 10,		width = 60, },	-- 11 Vote button
		{ name = L["Notes"],		align = "CENTER",												width = 40, },	-- 12 Note icon
		{ name = L["Roll"],		align = "CENTER", 					sortnext = 11,		width = 30, },	-- 13 Roll
	}
	menuFrame = CreateFrame("Frame", "RCLootCouncil_VotingFrame_RightclickMenu", UIParent, "Lib_UIDropDownMenuTemplate")
	filterMenu = CreateFrame("Frame", "RCLootCouncil_VotingFrame_FilterMenu", UIParent, "Lib_UIDropDownMenuTemplate")
	enchanters = CreateFrame("Frame", "RCLootCouncil_VotingFrame_EnchantersMenu", UIParent, "Lib_UIDropDownMenuTemplate")
	Lib_UIDropDownMenu_Initialize(menuFrame, self.RightClickMenu, "MENU")
	Lib_UIDropDownMenu_Initialize(filterMenu, self.FilterMenu)
	Lib_UIDropDownMenu_Initialize(enchanters, self.EnchantersMenu)
end

function RCVotingFrame:OnEnable()
	self:RegisterComm("RCLootCouncil")
	db = addon:Getdb()
	active = true
	self.frame = self:GetFrame()
end

function RCVotingFrame:OnDisable() -- We never really call this
	self:Hide()
	self.frame:SetParent(nil)
	self.frame = nil
	wipe(lootTable)
	active = false
	session = 1
	self:UnregisterAllComm()
end

function RCVotingFrame:Hide()
	self.frame:Hide()
end

function RCVotingFrame:Show()
	if self.frame  then
		self.frame:Show()
		self:SwitchSession(session)
	else
		addon:Print(L["No session running"])
	end
end

function RCVotingFrame:EndSession(hide)
	active = false -- The session has ended, so deactivate
	self:Update()
	if hide then self:Hide() end -- Hide if need be
end

function RCVotingFrame:OnCommReceived(prefix, serializedMsg, distri, sender)
	if prefix == "RCLootCouncil" then
		-- data is always a table to be unpacked
		local test, command, data = addon:Deserialize(serializedMsg)

		if test then
			if command == "vote" then
				if tContains(addon.council, addon:UnitName(sender)) or addon:UnitIsUnit(sender, addon.masterLooter) then
					local s, name, vote = unpack(data)
					self:HandleVote(s, name, vote, sender)
				else
					addon:Debug("Non-council member (".. tostring(sender) .. ") sent a vote!")
				end

			elseif command == "change_response" and addon:UnitIsUnit(sender, addon.masterLooter) then
				local ses, name, response = unpack(data)
				self:SetCandidateData(ses, name, "response", response)
				self:Update()

			elseif command == "lootAck" then
				local name = unpack(data)
				for i = 1, #lootTable do
					self:SetCandidateData(i, name, "response", "WAIT")
				end
				self:Update()

			elseif command == "awarded" and addon:UnitIsUnit(sender, addon.masterLooter) then
				lootTable[unpack(data)].awarded = true
				self:SwitchSession(session) -- Use switch session to update awardstring

			elseif command == "candidates" and addon:UnitIsUnit(sender, addon.masterLooter) then
				candidates = unpack(data)

			elseif command == "offline_timer" and addon:UnitIsUnit(sender, addon.masterLooter) then
				for i = 1, #lootTable do
					for name in pairs(lootTable[i].candidates) do
						if self:GetCandidateData(i, name, "response") == "ANNOUNCED" then
							self:SetCandidateData(i, name, "response", "NOTHING")
						end
					end
				end
				self:Update()

			elseif command == "lootTable" and addon:UnitIsUnit(sender, addon.masterLooter) then
				active = true
				self:Setup(unpack(data))
				if not addon.enabled then return end -- We just want things ready
				if db.autoOpen then
					self:Show()
				else
					addon:Print(L['A new session has begun, type "/rc open" to open the voting frame.'])
				end

			elseif command == "response" then
				local session, name, t = unpack(data)
				for k,v in pairs(t) do
					self:SetCandidateData(session, name, k, v)
				end
				self:Update()
			end
		end
	end
end

-- Getter/Setter for candidate data
-- Handles errors
function RCVotingFrame:SetCandidateData(session, candidate, data, val)
	local function Set(session, candidate, data, val)
		lootTable[session].candidates[candidate][data] = val
	end
	local ok, arg = pcall(Set, session, candidate, data, val)
	if not ok then addon:Debug("Error in 'SetCandidateData':", arg) end
end

function RCVotingFrame:GetCandidateData(session, candidate, data)
	local function Get(session, candidate, data)
		return lootTable[session].candidates[candidate][data]
	end
	local ok, arg = pcall(Get, session, candidate, data)
	if not ok then addon:Debug("Error in 'GetCandidateData':", arg)
	else return arg end
end

function RCVotingFrame:Setup(table)
	--lootTable[session] = {bagged, lootSlot, awarded, name, link, quality, ilvl, type, subType, equipLoc, texture, boe}
	lootTable = table -- Extract all the data we get
	for session, t in ipairs(lootTable) do -- and build the rest (candidates)
		lootTable[session].haveVoted = false -- Have we voted for ANY candidate in this session?
		t.candidates = {}
		for name, v in pairs(candidates) do
			t.candidates[name] = {
				class = v.class,
				rank = v.rank,
				role = v.role,
				response = "ANNOUNCED",
				ilvl = "",
				diff = "",
				gear1 = nil,
				gear2 = nil,
				votes = 0,
				note = nil,
				roll = "",
				voters = {},
				haveVoted = false, -- Have we voted for this particular candidate in this session?
			}
		end
		-- Init session toggle
		sessionButtons[session] = self:UpdateSessionButton(session, t.texture, t.link, t.awarded)
		sessionButtons[session]:Show()
	end
	-- Hide unused session buttons
	for i = #lootTable+1, #sessionButtons do
		sessionButtons[i]:Hide()
	end
	session = 1
	self:BuildST()
	self:SwitchSession(session)
end

function RCVotingFrame:HandleVote(session, name, vote, voter)
	-- Do the vote
	lootTable[session].candidates[name].votes = lootTable[session].candidates[name].votes + vote
	-- And update voters names
	if vote == 1 then
		tinsert(lootTable[session].candidates[name].voters, addon.Ambiguate(voter))
	else
		for i, n in ipairs(lootTable[session].candidates[name].voters) do
			if addon:UnitIsUnit(voter, n) then
				tremove(lootTable[session].candidates[name].voters, i)
				break
			end
		end
	end
	self:Update()
end

function RCVotingFrame:DoRandomRolls(ses)
	for _, v in pairs (lootTable[ses].candidates) do
		v.roll = math.random(100)
	end
	self:Update()
end

------------------------------------------------------------------
--	Visuals														--
------------------------------------------------------------------
function RCVotingFrame:Update()
	self.frame.st:SortData()
	-- update awardString
	if lootTable[session] and lootTable[session].awarded then
		self.frame.awardString:Show()
	else
		self.frame.awardString:Hide()
	end
	-- Update close button text
	if addon.isMasterLooter and active then
		self.frame.abortBtn:SetText(L["Abort"])
	else
		self.frame.abortBtn:SetText(L["Close"])
	end
	-- update disenchant button
	if db.disenchant then -- Don't bother if we don't use it
		-- Check if all rows are hidden
		local allHidden = true
		for row in ipairs(self.frame.st.filtered) do
			if row then allHidden = false end
		end
		if allHidden then
			self.frame.disenchant:Show()
		else
			self.frame.disenchant:Hide()
		end
	end
end

function RCVotingFrame:SwitchSession(s)
	addon:DebugLog("SwitchSession", s)
	-- Start with setting up some statics
	local old = session
	session = s
	local t = lootTable[s] -- Shortcut
	self.frame.itemIcon:SetNormalTexture(t.texture)
	self.frame.itemText:SetText(t.link)
	self.frame.itemLvl:SetText(format(L["ilvl: x"], t.ilvl))

	-- Set a proper item type text
	if t.subType and t.subType ~= "Miscellaneous" and t.subType ~= "Junk" and t.equipLoc ~= "" then
		self.frame.itemType:SetText(getglobal(t.equipLoc)..", "..t.subType); -- getGlobal to translate from global constant to localized name
	elseif t.subType ~= "Miscellaneous" and t.subType ~= "Junk" then
		self.frame.itemType:SetText(t.subType)
	else
		self.frame.itemType:SetText(getglobal(t.equipLoc));
	end

	-- Update the session buttons
	sessionButtons[s] = self:UpdateSessionButton(s, t.texture, t.link, t.awarded)
	sessionButtons[old] = self:UpdateSessionButton(old, lootTable[old].texture, lootTable[old].link, lootTable[old].awarded)

	-- Since we switched sessions, we want to sort by response
	for i in ipairs(self.frame.st.cols) do
		self.frame.st.cols[i].sort = nil
	end
	self.frame.st.cols[5].sort = "asc"
	self:Update()
end

function RCVotingFrame:BuildST()
	local rows = {}
	local i = 1
	for name in pairs(candidates) do
		rows[i] = {
			name = name,
			cols = {
				{ value = "",	DoCellUpdate = self.SetCellClass,		name = "class",},
				{ value = "",	DoCellUpdate = self.SetCellName,			name = "name",},
				{ value = "",	DoCellUpdate = self.SetCellRank,			name = "rank",},
				{ value = "",	DoCellUpdate = self.SetCellRole,			name = "role",},
				{ value = "",	DoCellUpdate = self.SetCellResponse,	name = "response",},
				{ value = "",	DoCellUpdate = self.SetCellIlvl,			name = "ilvl",},
				{ value = "",	DoCellUpdate = self.SetCellDiff,			name = "diff",},
				{ value = "",	DoCellUpdate = self.SetCellGear, 		name = "gear1",},
				{ value = "",	DoCellUpdate = self.SetCellGear, 		name = "gear2",},
				{ value = 0,	DoCellUpdate = self.SetCellVotes, 		name = "votes",},
				{ value = 0,	DoCellUpdate = self.SetCellVote,			name = "vote",},
				{ value = 0,	DoCellUpdate = self.SetCellNote, 		name = "note",},
				{ value = "",	DoCellUpdate = self.SetCellRoll,			name = "roll"},
			},
		}
		i = i + 1
	end
	self.frame.st:SetData(rows)
end


function RCVotingFrame:GetFrame()
	if self.frame then return self.frame end

	-- Container and title
	local f = addon:CreateFrame("DefaultRCLootCouncilFrame", "votingframe", L["RCLootCouncil Voting Frame"], 250, 420)
	-- Scrolling table
	local st = LibStub("ScrollingTable"):CreateST(self.scrollCols, NUM_ROWS, ROW_HEIGHT, { ["r"] = 1.0, ["g"] = 0.9, ["b"] = 0.0, ["a"] = 0.5 }, f.content)
	st.frame:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 10)
	st:RegisterEvents({
		["OnClick"] = function(rowFrame, cellFrame, data, cols, row, realrow, column, table, button, ...)
			if button == "RightButton" and row then
				if active then
					menuFrame.name = data[realrow].name
					Lib_ToggleDropDownMenu(1, nil, menuFrame, cellFrame, 0, 0);
				else
					addon:Print(L["You cannot use the menu when the session has ended."])
				end
			end
			-- Return false to have the default OnClick handler take care of left clicks
			return false
		end,
	})
	st:SetFilter(RCVotingFrame.filterFunc)
	st:EnableSelection(true)
	f.st = st
	--[[------------------------------
		Session item icon and strings
	    ------------------------------]]
	local item = CreateFrame("Button", nil, f.content)
	item:EnableMouse()
    item:SetNormalTexture("Interface/ICONS/INV_Misc_QuestionMark")
    item:SetScript("OnEnter", function()
		if not lootTable then return; end
		addon:CreateHypertip(lootTable[session].link)
	end)
	item:SetScript("OnLeave", addon.HideTooltip)
	item:SetScript("OnClick", function()
		if not lootTable then return; end
	    if ( IsModifiedClick() ) then
		    HandleModifiedItemClick(lootTable[session].link);
        end
    end);
	item:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -20)
	item:SetSize(50,50)
	f.itemIcon = item

	local iTxt = f.content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	iTxt:SetPoint("TOPLEFT", item, "TOPRIGHT", 10, -5)
	iTxt:SetText(L["Something went wrong :'("]) -- Set text for reasons
	f.itemText = iTxt

	local ilvl = f.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	ilvl:SetPoint("TOPLEFT", iTxt, "BOTTOMLEFT", 0, -10)
	ilvl:SetTextColor(0.5, 1, 1) -- Turqouise
	ilvl:SetText("")
	f.itemLvl = ilvl

	local iType = f.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	iType:SetPoint("LEFT", ilvl, "RIGHT", 5, 0)
	iType:SetTextColor(0.5, 1, 1) -- Turqouise
	iType:SetText(" ")
	f.itemType = iType
	--#end----------------------------

	-- Abort button
	local b1 = addon:CreateButton(L["Close"], f.content)
	b1:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -50)
	if addon.isMasterLooter then
		b1:SetScript("OnClick", function() if active then LibDialog:Spawn("RCLOOTCOUNCIL_CONFIRM_ABORT") else f:Hide() end end)
	else
		b1:SetScript("OnClick", function() f:Hide() end)
	end
	f.abortBtn = b1

	-- TODO More info button
	--[[local b2 = CreateFrame("Button", nil, f.content, "UIPanelButtonTemplate")
	b2:SetSize(25,25)
	b2:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -20)
	b2:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
	b2:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
	b2:SetScript("OnClick", function(button)
		moreInfo = not moreInfo
		if moreInfo then -- show the more info frame
			button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up");
			button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down");
		else -- hide it
			button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
			button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
		end
	end)
	b2:SetScript("OnEnter", function() addon:CreateTooltip(L["Click to expand/collapse more info"]) end)
	b2:SetScript("OnLeave", addon.HideTooltip)
	f.moreInfoBtn = b2]]

	-- Filter
	local b3 = addon:CreateButton(L["Filter"], f.content)
	b3:SetPoint("RIGHT", b1, "LEFT", -10, 0)
	b3:SetScript("OnClick", function(self) Lib_ToggleDropDownMenu(1, nil, filterMenu, self, 0, 0) end )
	b3:SetScript("OnEnter", function() addon:CreateTooltip(L["Deselect responses to filter them"]) end)
	b3:SetScript("OnLeave", addon.HideTooltip)
	f.filter = b3

	-- Disenchant button
	b4 = addon:CreateButton(L["Disenchant"], f.content)
	b4:SetPoint("RIGHT", b3, "LEFT", -10, 0)
	b4:SetScript("OnClick", function(self) Lib_ToggleDropDownMenu(1, nil, enchanters, self, 0, 0) end )
	b4:Hide() -- hidden by default
	f.disenchant = b4

	-- TODO Number of rolls/votes
	--[[	local rf = CreateFrame("Frame", nil, f.content)
	rf:SetWidth(100)
	rf:SetHeight(20)
	rf:SetPoint("RIGHT", b2, "LEFT", -10, 0)
	rf:SetScript("OnEnter", function()

	end)
	rf:SetScript("OnLeave", function()

	end)
	local rft = rf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	rft:SetPoint("CENTER", rf, "CENTER")
	rft:SetText(L["Everyone have rolled and voted"])
	rft:SetTextColor(0,1,0,1) -- Green
	rf.text = rft
	rf:SetWidth(rft:GetStringWidth())
	f.rollResult = rf]]

	-- Award string
	local awdstr = f.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	awdstr:SetPoint("CENTER", f.content, "TOP", 0, -60)
	awdstr:SetText(L["Item has been awarded"])
	awdstr:SetTextColor(1, 1, 0, 1) -- Yellow
	awdstr:Hide()
	f.awardString = awdstr

	-- Session toggle
	local stgl = CreateFrame("Frame", nil, f.content)
	stgl:SetWidth(40)
	stgl:SetHeight(f:GetHeight())
	stgl:SetPoint("TOPRIGHT", f, "TOPLEFT", -2, 0)
	f.sessionToggleFrame = stgl

	-- Set a proper width
	f:SetWidth(st.frame:GetWidth() + 20)
	return f;
end

function RCVotingFrame:UpdateSessionButton(i, texture, link, awarded)
	local btn = sessionButtons[i]
	if not btn then -- create the button
		btn = CreateFrame("Button", "RCButton"..i, self.frame.sessionToggleFrame)
		btn:SetSize(40,40)
		--btn:SetText(i)
		if i == 1 then
			btn:SetPoint("TOPRIGHT", self.frame.sessionToggleFrame)
		elseif mod(i,10) == 1 then
			btn:SetPoint("TOPRIGHT", sessionButtons[i-10], "TOPLEFT", -2, 0)
		else
			btn:SetPoint("TOP", sessionButtons[i-1], "BOTTOM", 0, -2)
		end
		btn:SetScript("Onclick", function() RCVotingFrame:SwitchSession(i); end)
		btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
		btn:GetHighlightTexture():SetBlendMode("ADD")
	end
	-- then update it
	texture = texture or "Interface\\InventoryItems\\WoWUnknownItem01"
	---- Set the colored border and tooltips
	btn:SetBackdrop({
			bgFile = texture,
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 18,
			insets = { left = 4, right = 4, top = 4, bottom = 4 }
		})
	local lines = { format(L["Click to switch to 'item'"], link) }
	if i == session then
		btn:SetBackdropBorderColor(1,1,0,1) -- yellow
		--btn:GetNormalTexture():SetVertexColor(1,1,1)
		btn:SetBackdropColor(1,1,1,1)
	elseif awarded then
		btn:SetBackdropBorderColor(0,1,0,1) -- green
		--btn:GetNormalTexture():SetVertexColor(0.8,0.8,0.8)
		tinsert(lines, L["This item has been awarded"])
		btn:SetBackdropColor(1,1,1,0.8)
	else
		btn:SetBackdropBorderColor(1,1,1,1) -- white
		--btn:GetNormalTexture():SetVertexColor(0.4,0.4,0.4)
		btn:SetBackdropColor(0.5,0.5,0.5,0.8)
	end
	btn:SetScript("OnEnter", function() addon:CreateTooltip(unpack(lines)) end)
	btn:SetScript("OnLeave", function() addon:HideTooltip() end)
	return btn
end


----------------------------------------------------------
--	Lib-st data functions (not particular pretty, I know)
----------------------------------------------------------
function RCVotingFrame:GetDiffColor(num)
	if num == "" then num = 0 end -- Can't compare empty string
	local green, red, grey = {0,1,0,1},{1,0,0,1},{0.75,0.75,0.75,1}
	if num > 0 then return green end
	if num < 0 then return red end
	return grey
end

function RCVotingFrame.SetCellClass(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	addon.SetCellClassIcon(rowFrame, frame, data, cols, row, realrow, column, fShow, table, lootTable[session].candidates[name].class)
end

function RCVotingFrame.SetCellName(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	frame.text:SetText(addon.Ambiguate(name))
	local c = addon:GetClassColor(lootTable[session].candidates[name].class)
	frame.text:SetTextColor(c.r, c.g, c.b, c.a)
	data[realrow].cols[column].value = name
end

function RCVotingFrame.SetCellRank(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	frame.text:SetText(lootTable[session].candidates[name].rank)
	frame.text:SetTextColor(addon:GetResponseColor(lootTable[session].candidates[name].response))
	data[realrow].cols[column].value = lootTable[session].candidates[name].rank
end

function RCVotingFrame.SetCellRole(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	local role = addon.TranslateRole(lootTable[session].candidates[name].role)
	frame.text:SetText(role)
	frame.text:SetTextColor(addon:GetResponseColor(lootTable[session].candidates[name].response))
	data[realrow].cols[column].value = role
end

function RCVotingFrame.SetCellResponse(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	frame.text:SetText(addon:GetResponseText(lootTable[session].candidates[name].response))
	frame.text:SetTextColor(addon:GetResponseColor(lootTable[session].candidates[name].response))
end

function RCVotingFrame.SetCellIlvl(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	frame.text:SetText(lootTable[session].candidates[name].ilvl)
	data[realrow].cols[column].value = lootTable[session].candidates[name].ilvl
end

function RCVotingFrame.SetCellDiff(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	frame.text:SetText(lootTable[session].candidates[name].diff)
	frame.text:SetTextColor(unpack(RCVotingFrame:GetDiffColor(lootTable[session].candidates[name].diff)))
	data[realrow].cols[column].value = lootTable[session].candidates[name].diff
end

function RCVotingFrame.SetCellGear(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local gear = data[realrow].cols[column].name -- gear1 or gear2
	local name = data[realrow].name
	gear = lootTable[session].candidates[name][gear] -- Get the actual gear
	if gear then
		local texture = select(10, GetItemInfo(gear))
		frame:SetNormalTexture(texture)
		frame:SetScript("OnEnter", function() addon:CreateHypertip(gear) end)
		frame:SetScript("OnLeave", function() addon:HideTooltip() end)
		frame:Show()
	else
		frame:Hide()
	end
end

function RCVotingFrame.SetCellVotes(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	frame:SetScript("OnEnter", function()
		if not addon.mldb.anonymousVoting or (db.showForML and addon.isMasterLooter) then
			addon:CreateTooltip(L["Voters"], unpack(lootTable[session].candidates[name].voters))
		end
	end)
	frame:SetScript("OnLeave", function() addon:HideTooltip() end)
	local val = lootTable[session].candidates[name].votes
	data[realrow].cols[column].value = val -- Set the value for sorting reasons
	frame.text:SetText(val)

	if addon.mldb.hideVotes then
		if not lootTable[session].haveVoted then frame.text:SetText(0) end
	end
end

function RCVotingFrame.SetCellVote(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	if not active or lootTable[session].awarded then -- Don't show the vote button if awarded or not active
		if frame.voteBtn then
			frame.voteBtn:Hide()
		end
		return
	end
	if addon.isCouncil or addon.isMasterLooter then -- Only let the right people vote
		if not frame.voteBtn then -- create it
			frame.voteBtn = addon:CreateButton(L["Vote"], frame)
			frame.voteBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
			frame.voteBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
		end
		frame.voteBtn:SetScript("OnClick", function(btn)
			if lootTable[session].candidates[name].haveVoted then -- unvote
				addon:SendCommand("group", "vote", session, name, -1)
				lootTable[session].candidates[name].haveVoted = false

				-- Check if that was our only vote
				local haveVoted = false
				for _, v in pairs(lootTable[session].candidates) do
					if v.haveVoted then haveVoted = true end
				end
				lootTable[session].haveVoted = haveVoted

			else -- vote
				-- Test if they may vote for themselves
				if not addon.mldb.selfVote and addon:UnitIsUnit("player", name) then
					return addon:Print(L["The Master Looter doesn't allow votes for yourself."])
				end
				-- Test if they're allowed to cast multiple votes
				if not addon.mldb.multiVote then
					if lootTable[session].candidates[name].haveVoted then
						return addon:Print(L["The Master Looter doesn't allow multiple votes."])
					end
				end
				-- Do the vote
				addon:SendCommand("group", "vote", session, name, 1)
				lootTable[session].candidates[name].haveVoted = true
				lootTable[session].haveVoted = true
			end
		end)
		frame.voteBtn:Show()
		if lootTable[session].candidates[name].haveVoted then
			frame.voteBtn:SetText(L["Unvote"])
		else
			frame.voteBtn:SetText(L["Vote"])
		end
	end
end

function RCVotingFrame.SetCellNote(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	local note = lootTable[session].candidates[name].note
	local f = frame.noteBtn or CreateFrame("Button", nil, frame)
	f:SetSize(ROW_HEIGHT, ROW_HEIGHT)
	f:SetPoint("CENTER", frame, "CENTER")
	if note then
		f:SetNormalTexture("Interface/BUTTONS/UI-GuildButton-PublicNote-Up.png")
		f:SetScript("OnEnter", function() addon:CreateTooltip(L["Note"], note)	end)
		f:SetScript("OnLeave", function() addon:HideTooltip() end)
		data[realrow].cols[column].value = 1 -- Set value for sorting compability
	else
		f:SetScript("OnEnter", nil)
		f:SetNormalTexture("Interface/BUTTONS/UI-GuildButton-PublicNote-Disabled.png")
		data[realrow].cols[column].value = 0
	end
	frame.noteBtn = f
end

function RCVotingFrame.SetCellRoll(rowFrame, frame, data, cols, row, realrow, column, fShow, table, ...)
	local name = data[realrow].name
	frame.text:SetText(lootTable[session].candidates[name].roll)
	data[realrow].cols[column].value = lootTable[session].candidates[name].roll
end

function RCVotingFrame.filterFunc(table, row)
	if not db.modules["RCVotingFrame"].filters then return true end -- db hasn't been initialized, so just show it
	local response = lootTable[session].candidates[row.name].response
	if response == "AUTOPASS" or response == "PASS" or type(response) == "number" then
		return db.modules["RCVotingFrame"].filters[response]
	else -- Filter out the status texts
		return db.modules["RCVotingFrame"].filters["STATUS"]
	end
end

function RCVotingFrame.ResponseSort(table, rowa, rowb, sortbycol)
	local column = table.cols[sortbycol]
	rowa, rowb = table:GetRow(rowa), table:GetRow(rowb);
	local a, b = addon:GetResponseSort(lootTable[session].candidates[rowa.name].response), addon:GetResponseSort(lootTable[session].candidates[rowb.name].response)
	if a == b then
		if column.sortnext then
			local nextcol = table.cols[column.sortnext];
			if not(nextcol.sort) then
				if nextcol.comparesort then
					return nextcol.comparesort(table, rowa, rowb, column.sortnext);
				else
					return table:CompareSort(rowa, rowb, column.sortnext);
				end
			end
		end
		return false
	else
		local direction = column.sort or column.defaultsort or "asc";
		if direction:lower() == "asc" then
			return a < b;
		else
			return a > b;
		end
	end
end

----------------------------------------------------
--	Dropdowns
----------------------------------------------------
do
	local info = Lib_UIDropDownMenu_CreateInfo() -- Efficiency :)
	-- NOTE Take care of info[] values when inserting new buttons
	function RCVotingFrame.RightClickMenu(menu, level)
		if not addon.isMasterLooter then return end

		local candidateName = menu.name
		local data = lootTable[session].candidates[candidateName] -- Shorthand

		if level == 1 then
			info.text = addon.Ambiguate(candidateName)
			info.isTitle = true
			info.notCheckable = true
			info.disabled = true
			Lib_UIDropDownMenu_AddButton(info, level)

			info.text = ""
			info.isTitle = false
			Lib_UIDropDownMenu_AddButton(info, level)

			info.text = L["Award"]
			info.func = function()
				LibDialog:Spawn("RCLOOTCOUNCIL_CONFIRM_AWARD", {
					session,
				  	candidateName,
					data.response,
					nil,
					data.votes,
					data.gear1,
					data.gear2,
			}) end
			info.disabled = false
			Lib_UIDropDownMenu_AddButton(info, level)
			info = Lib_UIDropDownMenu_CreateInfo()

			info.text = L["Award for ..."]
			info.value = "AWARD_FOR"
			info.notCheckable = true
			info.hasArrow = true
			Lib_UIDropDownMenu_AddButton(info, level)
			info = Lib_UIDropDownMenu_CreateInfo()

			info.text = ""
			info.notCheckable = true
			info.disabled = true
			Lib_UIDropDownMenu_AddButton(info, level)

			info.text = L["Change Response"]
			info.value = "CHANGE_RESPONSE"
			info.hasArrow = true
			info.disabled = false
			Lib_UIDropDownMenu_AddButton(info, level)

			info.text = L["Reannounce ..."]
			info.value = "REANNOUNCE"
			Lib_UIDropDownMenu_AddButton(info, level)
			info = Lib_UIDropDownMenu_CreateInfo()

			info.text = L["Remove from consideration"]
			info.notCheckable = true
			info.func = function()
				addon:SendCommand("group", "change_response", session, candidateName, "REMOVED")
			end
			Lib_UIDropDownMenu_AddButton(info, level)

			info.text = L["Add rolls"]
			info.notCheckable = true
			info.func = function() RCVotingFrame:DoRandomRolls(session) end
			Lib_UIDropDownMenu_AddButton(info, level)

		elseif level == 2 then
			local value = LIB_UIDROPDOWNMENU_MENU_VALUE
			info = Lib_UIDropDownMenu_CreateInfo()
			if value == "AWARD_FOR" then
				for k,v in ipairs(db.awardReasons) do
					if k > db.numAwardReasons then break end
					info.text = v.text
					info.notCheckable = true
					info.func = function()
						LibDialog:Spawn("RCLOOTCOUNCIL_CONFIRM_AWARD", {
							session,
						  	candidateName,
							nil,
							v,
							data.votes,
							data.gear1,
							data.gear2,
				}) end
					Lib_UIDropDownMenu_AddButton(info, level)
				end

			elseif value == "CHANGE_RESPONSE" then
				for i = 1, db.numButtons do
					local v = db.responses[i]
					info.text = v.text
					info.colorCode = "|cff"..addon:RGBToHex(unpack(v.color))
					info.notCheckable = true
					info.func = function()
							addon:SendCommand("group", "change_response", session, candidateName, i)
					end
					Lib_UIDropDownMenu_AddButton(info, level)
				end

			elseif value == "REANNOUNCE" then
				info.text = addon.Ambiguate(candidateName)
				info.isTitle = true
				info.notCheckable = true
				info.disabled = true
				Lib_UIDropDownMenu_AddButton(info, level)
				info = Lib_UIDropDownMenu_CreateInfo()

				info.text = L["This item"]
				info.notCheckable = true
				info.func = function()
					local t = {
						{	name = lootTable[session].name,
							link = lootTable[session].link,
							ilvl = lootTable[session].ilvl,
							texture = lootTable[session].texture,
							session = session,
						}
					}
					addon:SendCommand(candidateName, "reroll", t)
				end
				Lib_UIDropDownMenu_AddButton(info, level);
				info = Lib_UIDropDownMenu_CreateInfo()

				info.text = L["All items"]
				info.notCheckable = true
				info.func = function()
					local t = {}
					for k,v in ipairs(lootTable) do
						if not v.awarded then
							tinsert(t, {
								name = v.name,
								link = v.link,
								ilvl = v.ilvl,
								texture = v.texture,
								session = k,
							})
						end
					end
					addon:SendCommand(candidateName, "reroll", t)
				end
				Lib_UIDropDownMenu_AddButton(info, level);
			end
		end
	end

	function RCVotingFrame.FilterMenu(menu, level)
		if level == 1 then -- Redundant
			-- Build the data table:
			local data = {["STATUS"] = true, ["PASS"] = true, ["AUTOPASS"] = true}
			for i = 1, db.numButtons do
				data[i] = i
			end
			if not db.modules["RCVotingFrame"].filters then -- Create the db entry
				addon:DebugLog("Created VotingFrame filters")
				db.modules["RCVotingFrame"].filters = {}
			end
			for k in pairs(data) do -- Update the db entry to make sure we have all buttons in it
				if type(db.modules["RCVotingFrame"].filters[k]) ~= "boolean" then
					addon:Debug("Didn't contain "..k)
					db.modules["RCVotingFrame"].filters[k] = true -- Default as true
				end
			end
			info.text = L["Filter"]
			info.isTitle = true
			info.notCheckable = true
			info.disabled = true
			Lib_UIDropDownMenu_AddButton(info, level)
			info = Lib_UIDropDownMenu_CreateInfo()

			for k in ipairs(data) do -- Make sure normal responses are on top
				info.text = db.responses[k].text
				info.colorCode = "|cff"..addon:RGBToHex(unpack(db.responses[k].color))
				info.func = function() db.modules["RCVotingFrame"].filters[k] = not db.modules["RCVotingFrame"].filters[k]; RCVotingFrame.frame.st:SortData() end
				info.checked = db.modules["RCVotingFrame"].filters[k]
				Lib_UIDropDownMenu_AddButton(info, level)
			end
			for k in pairs(data) do -- A bit redundency, but it makes sure these "specials" comes last
				if type(k) == "string" then
					if k == "STATUS" then
						info.text = L["Status texts"]
						info.colorCode = "|cffde34e2" -- purpleish
					else
						info.text = db.responses[k].text
						info.colorCode = "|cff"..addon:RGBToHex(unpack(db.responses[k].color))
					end
					info.func = function() db.modules["RCVotingFrame"].filters[k] = not db.modules["RCVotingFrame"].filters[k]; RCVotingFrame.frame.st:SortData() end
					info.checked = db.modules["RCVotingFrame"].filters[k]
					Lib_UIDropDownMenu_AddButton(info, level)
				end
			end
		end
	end

	function RCVotingFrame.EnchantersMenu(menu, level)
		if level == 1 then
			local added = false
			info = Lib_UIDropDownMenu_CreateInfo()
			for name, v in pairs(candidates) do
				if v.enchanter then
					local c = addon:GetClassColor(v.class)
					info.text = "|cff"..addon:RGBToHex(c.r, c.g, c.b)..addon.Ambiguate(name).."|r "..tostring(v.enchant_lvl)
					info.notCheckable = true
					info.func = function()
						for k,v in ipairs(db.awardReasons) do
							if v.disenchant then
								LibDialog:Spawn("RCLOOTCOUNCIL_CONFIRM_AWARD", {
									session,
								  	name,
									nil,
									v,
								})
								return
							end
						end
					end
					added = true
					Lib_UIDropDownMenu_AddButton(info, level)
				end
			end
			if not added then -- No enchanters available
				info.text = L["No (dis)enchanters found"]
				info.notCheckable = true
				info.isTitle = true
				Lib_UIDropDownMenu_AddButton(info, level)
			end
		end
	end
end