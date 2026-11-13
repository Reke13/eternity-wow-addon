-- Remember the name when sending: the recipient stays in the form after a letter goes out, to
-- send that player another one. Blizzard empties the whole send form on MAIL_SEND_SUCCESS
-- (SendMailFrame_Reset); a hook after it puts the last recipient back and moves the cursor to the
-- subject. The name is forgotten when the mailbox closes. Blizzard_MailFrame may load late, so its
-- hook goes in on MAIL_SHOW. Hooks can't be removed: they do nothing while it's off.

---@type string, EternityUIMailNamespace
local _, ns = ...
local opt = ns.opt

---@class EternityUIMailRecipient
---@field running boolean?
---@field last string? the last recipient while the mailbox is open
local Recipient = {}
ns.Recipient = Recipient

local function active()
    return Recipient.running and opt("send.keepRecipient")
end

--- Puts the last recipient back in the emptied send form.
function Recipient.Restore()
    local box = _G.SendMailNameEditBox
    if not active() or not Recipient.last or not box then
        return
    end
    box:SetText(Recipient.last)
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
function Recipient.HookForm()
    if Recipient.formHooked or not _G.SendMailFrame_Reset then
        return
    end
    Recipient.formHooked = true
    hooksecurefunc("SendMailFrame_Reset", Recipient.Restore)
end

--- Whoever the letter goes to, however it's sent (Blizzard's button or another addon).
function Recipient.OnSendMail(name)
    if active() and type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name ~= "" then
        Recipient.last = name
    end
end

function Recipient.OnEvent(event)
    if event == "MAIL_CLOSED" then
        Recipient.last = nil
    elseif event == "MAIL_SHOW" then
        Recipient.HookForm()
    end
end

function Recipient.Start()
    Recipient.running = true
    if not Recipient.sendHooked and _G.SendMail then
        Recipient.sendHooked = true
        hooksecurefunc("SendMail", Recipient.OnSendMail)
    end
    Recipient.HookForm()
end

function Recipient.Stop()
    Recipient.running = false
    Recipient.last = nil
end

--- The option changed: off forgets the name.
function Recipient.Apply()
    if not opt("send.keepRecipient") then
        Recipient.last = nil
    end
end
