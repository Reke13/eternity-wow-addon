-- Mail automations: keep the recipient after sending, to send that player another letter.
-- Blizzard empties the whole send form on MAIL_SEND_SUCCESS (SendMailFrame_Reset); a hook after it
-- puts the last recipient back and moves the cursor to the subject. The name is forgotten when
-- the mailbox closes. Blizzard_MailFrame may load late, so its hook goes in on MAIL_SHOW.

---@type string, EternityUIAutomationNamespace
local _, ns = ...
local Core = ns.Core

local keepRecipient = Core.Add({
    id = "keepRecipient",
    events = { "MAIL_SHOW", "MAIL_CLOSED" },
    Enabled = function()
        return Core.On("mail.keepRecipient")
    end,
})

--- Puts the last recipient back in the emptied send form.
function keepRecipient:Restore()
    local box = _G.SendMailNameEditBox
    if not Core.Active(self) or not self.last or not box then
        return
    end
    box:SetText(self.last)
    local subject = _G.SendMailSubjectEditBox
    if subject then
        subject:SetFocus()
    end
    -- The Send button follows the form (a recipient is one of its checks).
    if _G.SendMailFrame_Update then
        _G.SendMailFrame_Update()
    end
end

-- Blizzard's form reset, once it exists.
function keepRecipient:HookForm()
    if self.formHooked or not _G.SendMailFrame_Reset then
        return
    end
    self.formHooked = true
    hooksecurefunc("SendMailFrame_Reset", function()
        self:Restore()
    end)
end

function keepRecipient:OnApply(on)
    if not on then
        self.last = nil
        return
    end
    if not self.sendHooked then
        self.sendHooked = true
        -- Whoever the letter goes to, however it's sent (Blizzard's button or another addon).
        hooksecurefunc("SendMail", function(name)
            if Core.Active(self) and type(name) == "string" and not Core.Secret(name) and name ~= "" then
                self.last = name
            end
        end)
    end
    self:HookForm()
end

function keepRecipient:OnEvent(event)
    if event == "MAIL_CLOSED" then
        self.last = nil
    else
        self:HookForm()
    end
end
