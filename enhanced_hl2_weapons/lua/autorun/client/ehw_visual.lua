local enabled = CreateConVar("cl_ehw_enabled", 1, FCVAR_ARCHIVE)
local lerp_speed = CreateConVar("cl_ehw_lerp_speed", 10, FCVAR_ARCHIVE)
local clamp_num = CreateConVar("cl_ehw_clamp_mouse", 50, FCVAR_ARCHIVE)
local sprint_anim = CreateConVar("cl_ehw_sprint_animation", 1, FCVAR_ARCHIVE)
local effect_mult = CreateConVar("cl_ehw_effect_mult", 1, FCVAR_ARCHIVE)
local down_offset = CreateConVar("cl_ehw_down_offset_mult", 1, FCVAR_ARCHIVE)
local walk_viewbob_speed_mult = CreateConVar("cl_ehw_walk_bob_speed_mult", 1, FCVAR_ARCHIVE)

local lpos = Vector()
local lang = Angle()

local gx = 0
local gy = 0
local tilt = 0

local zoomed = false

local rate = 1
local lrate = 1

local frac_sprint = 1
local frac_sprint2 = 1
local wait_after_shoot = 0

local frac_zoom = 1

local sprint_curtime = 0

local random_entity = NULL

local lmult = 0

local allowed = {
    weapon_357 = true,
    weapon_pistol = true,
    weapon_bugbait = true,
    weapon_crossbow = true,
    weapon_crowbar = true,
    weapon_frag = true,
    weapon_physcannon = true,
    weapon_ar2 = true,
    weapon_rpg = true,
    weapon_slam = true,
    weapon_shotgun = true,
    weapon_smg1 = true,
    weapon_stunstick = true
}
if not file.Exists("ehw_allowed.json", "DATA") then 
    file.Write("ehw_allowed.json", util.TableToJSON(allowed, true)) 
end
allowed = util.JSONToTable(file.Read("ehw_allowed.json"))

local is_allowed = false

concommand.Add("cl_ehw_toggle_weapon", function(ply, cmd, args, arg_str) 
	_usage = "Usage: cl_ehw_allow_weapon weapon_class\nIf weapon_class isn't provided, the current weapon is used."
	
	print(_usage)

	local weapon_class = args[1] or NULL

	if weapon_class == NULL then
		local weapon = LocalPlayer():GetActiveWeapon()
		if IsValid(weapon) and isfunction(weapon.GetClass) then
			weapon_class = weapon:GetClass()
		end
	end

    if allowed[weapon_class] then
	    allowed[weapon_class] = nil
    else
        allowed[weapon_class] = true
    end

	file.Write("ehw_allowed.json", util.TableToJSON(allowed, true)) 

	print(weapon_class..": toggled")
end)

local function ease(t, downwards)
    if not downwards then
        return math.ease.OutQuad(math.ease.InBack(t))
    else
        return math.ease.InQuad(math.ease.OutBack(t))
    end
end

hook.Add("InputMouseApply", "ehw_mouse", function(cmd, x, y, ang) 
    if not enabled:GetBool() then return end
    if not is_allowed then return end
    local range = clamp_num:GetFloat()
    gx = Lerp(FrameTime() * lerp_speed:GetFloat(), gx, math.Clamp(x / 2, -range, range))
    gy = Lerp(FrameTime() * lerp_speed:GetFloat(), gy, math.Clamp(y / 2, -range, range))
end)

local function set_random_entity()
    if IsValid(random_entity) then return end

    local lp = LocalPlayer()
    for i, ent in ipairs(ents.GetAll()) do
        if ent != lp and IsValid(ent) then random_entity = ent end
    end
end

concommand.Add("+ehw_zoom", function()
    if not enabled:GetBool() then return end
    if not is_allowed then return end

    set_random_entity()

    local lp = LocalPlayer()
    zoomed = true
    lp.ehw_zoomed = true
    net.Start("ehw_player_zoomed")
    net.WriteBool(true)
    net.SendToServer()

    LocalPlayer():SetFOV(70, 0.6, random_entity)
end)

concommand.Add("-ehw_zoom", function()
    if not enabled:GetBool() then return end
    if not is_allowed then return end

    set_random_entity()

    local lp = LocalPlayer()
    zoomed = false
    lp.ehw_zoomed = false
    net.Start("ehw_player_zoomed")
    net.WriteBool(false)
    net.SendToServer()

    LocalPlayer():SetFOV(0, 0.5, random_entity)
end)

hook.Add("CalcViewModelView", "ehw_visual", function(weapon, vm, oldpos, oldang, pos, ang) 
    if not enabled:GetBool() then return end

    is_allowed = allowed[weapon:GetClass()]

    if not is_allowed then return end

    local curtime = UnPredictedCurTime()
    local frametime = FrameTime()
    local up = ang:Up()
    local right = ang:Right()
    local forward = ang:Forward()
    local lp = LocalPlayer()

    // angle offset
    local a = Angle(gy, -gx, (gx + gy) / 2)

    // bob offset
    local v = -gx * right + gy * up
    
    // idle bobbing
    local drunk_view = Angle(math.sin(curtime / 0.9) * 3, math.cos(curtime / 0.8) * 3.6, math.sin(curtime / 0.5) * 3.3) * 0.5
    local drunk_pos = Vector(math.sin(curtime / 1.2) * 3.2, math.cos(curtime / 0.7) * 3, math.sin(curtime / 0.8) * 2) * 0.5
    local _drunk_pos, _ = LocalToWorld(drunk_pos, Angle(), Vector(), ang)

    a:Add(drunk_view)
    v:Add(_drunk_pos)

    // zoom offset
    local fz_later = 0
    if zoomed then
        frac_zoom = math.Clamp(frac_zoom + frametime, 0, 1)
        fz_later = frametime
        a:Mul(0.5) 
        v:Mul(0.5)
    else
        frac_zoom = math.Clamp(frac_zoom - frametime, 0, 1)
        fz_later = -frametime
    end

    v:Add((right * -20 + up * 10) * ease(frac_zoom, zoomed))

    frac_zoom = math.Clamp(frac_zoom + fz_later, 0, 1)

    // walk viewbob
    local vel = lp:GetVelocity():Length()
    local trying_to_move = lp:KeyDown(IN_FORWARD) or lp:KeyDown(IN_BACK) or lp:KeyDown(IN_MOVELEFT) or lp:KeyDown(IN_MOVERIGHT)

    local maxspeed = math.max(1, lp:GetMaxSpeed()) // just in case some evil mod does this...
    local mult = math.Clamp(vel, 0, maxspeed)

    sprint_curtime = sprint_curtime + frametime * mult / 100 * walk_viewbob_speed_mult:GetFloat()

    local walk_pos = Vector(0,
                            math.sin(sprint_curtime * 2),
                            math.cos(sprint_curtime * 2) / 2)
    local walk_view = Angle(-walk_pos.x, -walk_pos.y, 0)
    local _walk_pos, _ = LocalToWorld(walk_pos, Angle(), Vector(), ang)

    lmult = Lerp(frametime * 2, lmult, mult / 100)

    a:Add(walk_view * 2 * lmult)
    v:Add(_walk_pos * 2 * lmult)

    // sprint "anims"
    // i eated glue when writing this
    if sprint_anim:GetBool() then
        local downwards = false
        local in_speed = lp:KeyDown(IN_SPEED)
        local in_attack = lp:KeyDown(IN_ATTACK) or lp:KeyDown(IN_ATTACK2)
        local mult = lerp_speed:GetFloat() / 10

        local fs2_later = 0
        local fs_later = 0
        
        if in_speed and trying_to_move then
            if wait_after_shoot <= 0 then
                frac_sprint = math.Clamp(frac_sprint + frametime * mult, 0, 1)
                fs_later = frametime * mult
            end
            frac_sprint2 = math.Clamp(frac_sprint2 + frametime * mult, 0, 1)
            fs2_later = frametime * mult
            downwards = true
        else
            frac_sprint = math.Clamp(frac_sprint - frametime * mult, 0, 1)
            fs_later = -frametime * mult
            frac_sprint2 = math.Clamp(frac_sprint2 - frametime * mult, 0, 1)
            fs2_later = -frametime * mult
            downwards = false
        end

        if in_attack then
            downwards = false
            frac_sprint = math.Clamp(frac_sprint - frametime * 100 * mult / 2, 0, 1)
            fs_later = -frametime * 100 * mult / 2
            v:Sub(up * 20 * ease(frac_sprint2, downwards))
            if in_speed then
                wait_after_shoot = 1
            end
        else
            v:Sub(up * 10 * ease(frac_sprint2, downwards))
            wait_after_shoot = math.Clamp(wait_after_shoot - frametime * 1.25 * mult, 0, 1)
        end

        a:Add(Angle(30, 20, 0) * ease(frac_sprint, downwards))

        frac_sprint = math.Clamp(frac_sprint + fs_later, 0, 1)
        frac_sprint2 = math.Clamp(frac_sprint2 + fs2_later, 0, 1)
    end

    // down offset
    v:Sub(up * down_offset:GetFloat()) 

    // lerp it and set it
    lpos = LerpVector(frametime * lerp_speed:GetFloat() / 2, lpos, v * 0.1)
    lang = LerpAngle(frametime * lerp_speed:GetFloat() / 2, lang, a * 0.3)
    
    pos:Add(lpos * effect_mult:GetFloat())
    ang:Add(lang * effect_mult:GetFloat())

    lpos = LerpVector(frametime * lerp_speed:GetFloat() / 2, lpos, v * 0.1)
    lang = LerpAngle(frametime * lerp_speed:GetFloat() / 2, lang, a * 0.3)
end)