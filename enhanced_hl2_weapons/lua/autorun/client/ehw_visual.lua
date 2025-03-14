local enabled = CreateConVar("cl_ehw_enabled", 1, FCVAR_ARCHIVE)
local effect_mult = CreateConVar("cl_ehw_effect_mult", 1, FCVAR_ARCHIVE)
local lerp_speed = CreateConVar("cl_ehw_interp_mult", 1, FCVAR_ARCHIVE)

local clamp_num = CreateConVar("cl_ehw_clamp_mouse", 50, FCVAR_ARCHIVE)

local sprint_mult = CreateConVar("cl_ehw_tilt_vm_mult", 1, FCVAR_ARCHIVE)

local sprint_anim = CreateConVar("cl_ehw_sprint_animation", 1, FCVAR_ARCHIVE)

local down_offset = CreateConVar("cl_ehw_down_offset_mult", 1, FCVAR_ARCHIVE)

local land_mult = CreateConVar("cl_ehw_land_mult", 1, FCVAR_ARCHIVE)

local use_calcview = CreateConVar("cl_ehw_use_calcview", 1, FCVAR_ARCHIVE)

local tilt_vm = CreateConVar("cl_ehw_tilt_vm", 1, FCVAR_ARCHIVE)
local tilt_vm_mult = CreateConVar("cl_ehw_tilt_vm_mult", 1, FCVAR_ARCHIVE)

local use_viewpunch = CreateConVar("cl_ehw_use_viewpunch_walk", 0, FCVAR_ARCHIVE)
local viewpunch_strength = CreateConVar("cl_ehw_viewpunch_strength", 1, FCVAR_ARCHIVE)
local override = CreateConVar("cl_ehw_override", 0, FCVAR_ARCHIVE)

local sp = game.SinglePlayer()

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
local frac_land = 0
local lerped_frac_land = 0

local sprint_curtime = 0

local prev_on_ground = true
local current_on_ground = true

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
    gx = Lerp(FrameTime() * lerp_speed:GetFloat() * 10, gx, math.Clamp(x / 2, -range, range))
    gy = Lerp(FrameTime() * lerp_speed:GetFloat() * 10, gy, math.Clamp(y / 2, -range, range))
end)

concommand.Add("+ehw_zoom", function()
    if not enabled:GetBool() then return end
    if not is_allowed then return end

    local lp = LocalPlayer()
    zoomed = true
    lp.ehw_zoomed = true
    net.Start("ehw_player_zoomed")
    net.WriteBool(true)
    net.SendToServer()

    if use_calcview:GetBool() then return end

    LocalPlayer():SetFOV(GetConVar("fov_desired"):GetFloat() - 20, 0.6)
end)

concommand.Add("-ehw_zoom", function()
    if not enabled:GetBool() then return end
    if not is_allowed then return end

    local lp = LocalPlayer()
    zoomed = false
    lp.ehw_zoomed = false
    net.Start("ehw_player_zoomed")
    net.WriteBool(false)
    net.SendToServer()

    if use_calcview:GetBool() then return end

    LocalPlayer():SetFOV(0, 0.6)
end)

local vp_punch_angle = Angle()
local vp_punch_angle_velocity = Angle()

local vp_punch_angle2 = Angle()
local vp_punch_angle_velocity2 = Angle()

hook.Add("Think", "ehw_detect_land", function()
    // onplayerhitground is predicted so it's gae
    prev_on_ground = current_on_ground
    current_on_ground = LocalPlayer():OnGround()
    if prev_on_ground != current_on_ground and current_on_ground then
        frac_land = 1
    end

    if prev_on_ground != current_on_ground and !current_on_ground and LocalPlayer():KeyDown(IN_JUMP) then
        vp_punch_angle_velocity = vp_punch_angle_velocity + Angle(-20, 0, 0) * viewpunch_strength:GetFloat()
        vp_punch_angle_velocity2 = vp_punch_angle_velocity2 + Angle(-30, 0, 0) * viewpunch_strength:GetFloat()
    end
end)

local function process_viewpunch(ang, vel, damp, spring)
    if not ang:IsZero() or not vel:IsZero() then
        ang:Add(vel * FrameTime())
        local damping = 1 - (damp * FrameTime())

        if damping < 0 then damping = 0 end

        vel:Mul(damping)

        local spring_force_magnitude = math.Clamp(spring * FrameTime(), 0, 0.2 / FrameTime())

        vel:Sub(ang * spring_force_magnitude)

        local x, y, z = ang:Unpack()
        ang.x = math.Clamp(x, -89, 89)
        ang.y = math.Clamp(y, -179, 179)
        ang.z = math.Clamp(z, -89, 89)
    else
        ang:Zero()
        vel:Zero()
    end

    if ang:IsZero() and vel:IsZero() then return end

    if LocalPlayer():InVehicle() then return end
end

hook.Add("Think", "vm_viewpunch_think", function()
    process_viewpunch(vp_punch_angle, vp_punch_angle_velocity, 15, 50)
    process_viewpunch(vp_punch_angle2, vp_punch_angle_velocity2, 10, 70)
end)

local vm_last_realtime = 0
local vm_realtime = 0

local lerped_add_sprint_curtime = 0
local add_sprint_curtime = 0

local lerped_walk_bob_pos = Vector()
local lerped_walk_bob_ang = Angle()

local lerped_tilt_pos = Vector()
local lerped_tilt_ang = Angle()

local yaw_90 = Angle(0, 90, 0)

local tilt = Angle()

local p30_y20 = Angle(30, 20, 0)

hook.Add("CalcViewModelView", "ehw_visual", function(weapon, vm, oldpos, oldang, pos, ang)
    if not enabled:GetBool() then return end

    is_allowed = allowed[weapon:GetClass()]

    if not is_allowed then return end

    if override:GetBool() then
        pos:Set(oldpos)
        ang:Set(oldang)
    end

    local frametime = RealFrameTime()

    local curtime = UnPredictedCurTime()
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
    if zoomed then
        frac_zoom = math.Clamp(frac_zoom + frametime * 2, 0, 1)
        a:Mul(0.5)
        v:Mul(0.5)
    else
        frac_zoom = math.Clamp(frac_zoom - frametime * 2, 0, 1)
    end

    if frac_zoom > 0 then
        v:Add((right * -20 + up * 10) * ease(frac_zoom, zoomed))
    end

    // land offset
    frac_land = math.max(0, frac_land - frametime * 2)
    if frac_land > 0 then
        local eased_frac_land = math.ease.InOutQuad(frac_land) * land_mult:GetFloat()
        v:Sub(up * eased_frac_land * 2.5)
        v:Sub(forward * eased_frac_land * 5)
        a:Add(Angle(5, 0, 10) * eased_frac_land)
    end

    // walk viewbob
    local trying_to_move = lp:KeyDown(IN_FORWARD) or lp:KeyDown(IN_BACK) or lp:KeyDown(IN_MOVELEFT) or lp:KeyDown(IN_MOVERIGHT)

    if !use_viewpunch:GetBool() then
        local ms = 0

        if sp then
            ms = lp:GetNW2Float("ehw_stepsoundtime")
        else
            if bm_vars and bm_vars.enabled:GetBool() then
                ms = BmGetStepSoundTime(lp, 0, lp:KeyDown(IN_WALK))
            else
                ms = hook.Run("PlayerStepSoundTime", lp, 0, lp:KeyDown(IN_WALK))
            end
        end

        if ms != 0 and ms != math.huge then
            local maxspeed = math.max(1, lp:GetMaxSpeed()) // just in case some evil mod does this...
            local vel = lp:GetVelocity():Length()
            local mult = math.Clamp(vel, 0, maxspeed)

            local coof = math.pi / (ms / 1000)

            add_sprint_curtime = math.abs(frametime * coof - frametime * ms / 2000 - frametime)
            if not trying_to_move then
                add_sprint_curtime = 0
            end
            
            lerped_add_sprint_curtime = Lerp(frametime * 5, lerped_add_sprint_curtime, add_sprint_curtime)
            sprint_curtime = sprint_curtime + lerped_add_sprint_curtime
            lerped_add_sprint_curtime = Lerp(frametime * 5, lerped_add_sprint_curtime, add_sprint_curtime)

            local walk_pos = Vector(math.cos(sprint_curtime * 2) / 2, math.cos(sprint_curtime), math.cos(sprint_curtime) / 4) + 
                Vector(math.sin(sprint_curtime * 2) / 4, math.sin(sprint_curtime) / 2, math.sin(sprint_curtime / 2) / 16)

            local walk_view = Angle(-walk_pos.x, -walk_pos.y, 0)
            local _walk_pos, _ = LocalToWorld(walk_pos, Angle(), Vector(), ang)

            lerped_walk_bob_pos = LerpVector(math.min(frametime * 35 * lerp_speed:GetFloat(), 1), lerped_walk_bob_pos, _walk_pos)
            lerped_walk_bob_ang = LerpAngle(math.min(frametime * 35 * lerp_speed:GetFloat(), 1), lerped_walk_bob_ang, walk_view)
            
            lmult = Lerp(frametime * 15 * lerp_speed:GetFloat(), lmult, mult / 100)
            a:Add(lerped_walk_bob_ang * 2 * lmult)
            v:Add(lerped_walk_bob_pos * 2 * lmult)
            lmult = Lerp(frametime * 15 * lerp_speed:GetFloat(), lmult, mult / 100)

            lerped_walk_bob_pos = LerpVector(math.min(frametime * 35 * lerp_speed:GetFloat(), 1), lerped_walk_bob_pos, _walk_pos)
            lerped_walk_bob_ang = LerpAngle(math.min(frametime * 35 * lerp_speed:GetFloat(), 1), lerped_walk_bob_ang, walk_view)
        end
    end

    // process viewpunch stuff
    ang:Add(vp_punch_angle * 2 * viewpunch_strength:GetFloat())

    local fwd = vp_punch_angle2:Forward()

    fwd.x = fwd.x - 1
    fwd:Rotate(ang)

    pos:Add(fwd * -30 * viewpunch_strength:GetFloat())

    // sprint "anims"
    // i eated glue when writing this
    local in_attack = lp:KeyDown(IN_ATTACK) or lp:KeyDown(IN_ATTACK2)
    if sprint_anim:GetBool() then
        local downwards = false
        local in_speed = lp:KeyDown(IN_SPEED)
        local mult = lerp_speed:GetFloat()

        if in_speed and trying_to_move then
            if wait_after_shoot <= 0 then
                frac_sprint = math.Clamp(frac_sprint + frametime * mult * 2, 0, 1)
            end
            frac_sprint2 = math.Clamp(frac_sprint2 + frametime * mult * 2, 0, 1)
            downwards = true
        else
            frac_sprint = math.Clamp(frac_sprint - frametime * mult * 2, 0, 1)
            frac_sprint2 = math.Clamp(frac_sprint2 - frametime * mult * 2, 0, 1)
            downwards = false
        end

        if in_attack then
            downwards = false
            frac_sprint = math.Clamp(frac_sprint - frametime * 100 * mult, 0, 1)
            v:Sub(up * 20 * ease(frac_sprint2, downwards))
            if in_speed then
                wait_after_shoot = 1
            end
        else
            v:Sub(up * 10 * ease(frac_sprint2, downwards))
            wait_after_shoot = math.Clamp(wait_after_shoot - frametime * 1.25 * mult, 0, 1)
        end

        a:Add(p30_y20 * ease(frac_sprint, downwards))
    end

    // tilt
    if tilt_vm:GetBool()  then
        local vel = lp:GetVelocity()
        vel.z = 0

        local eye = lp:EyeAngles():Forward()
        eye.z = 0

        local diff = vel - eye 

        if not trying_to_move or in_attack then 
            diff:Zero()
            vel:Zero() 
            eye:Zero() 
        end

        diff:Normalize()

        tilt:Zero()

        tilt.z = vel:Cross(eye).z / 20 * tilt_vm_mult:GetFloat()
        eye:Rotate(yaw_90)
        tilt.x = tilt.x + vel:Cross(eye).z / 80 * tilt_vm_mult:GetFloat()

        lerped_tilt_pos = LerpVector( frametime * 10 * lerp_speed:GetFloat(), lerped_tilt_pos, diff )
        lerped_tilt_ang = LerpAngle( frametime * 7 * lerp_speed:GetFloat(), lerped_tilt_ang, tilt )
        
        v:Add(lerped_tilt_pos)
        a:Add(lerped_tilt_ang)

        lerped_tilt_pos = LerpVector( frametime * 10 * lerp_speed:GetFloat(), lerped_tilt_pos, diff )
        lerped_tilt_ang = LerpAngle( frametime * 7 * lerp_speed:GetFloat(), lerped_tilt_ang, tilt )
    end

    // down offset
    v:Sub(up * down_offset:GetFloat())

    // lerp it and set it
    lpos = LerpVector(frametime * lerp_speed:GetFloat() / 2 * 10, lpos, v * 0.1)
    lang = LerpAngle(frametime * lerp_speed:GetFloat() / 2 * 10, lang, a * 0.3)

    pos:Add(lpos * effect_mult:GetFloat())
    ang:Add(lang * effect_mult:GetFloat())

    lpos = LerpVector(frametime * lerp_speed:GetFloat() / 2 * 10, lpos, v * 0.1)
    lang = LerpAngle(frametime * lerp_speed:GetFloat() / 2 * 10, lang, a * 0.3)
end)

local last_realtime = 0
local realtime = 0

hook.Add("CalcView", "ehw_idontlikethisatall", function(ply, origin, angles, fov, znear, zfar)
    if not enabled:GetBool() or not use_calcview:GetBool() or not is_allowed or frac_zoom <= 0 then return end

    local base_view = {}
    local need_to_run = false

    for name, func in pairs(hook.GetTable()["CalcView"]) do
        if name == "ehw_idontlikethisatall" then
            need_to_run = true
            continue
        end
        if not need_to_run then
            continue
        end
        local ret = func(ply, base_view.origin or origin, base_view.angles or angles, base_view.fov or fov, base_view.znear or znear, base_view.zfar or zfar, base_view.drawviewer or false)
        base_view = ret or base_view
    end

    local weapon = ply:GetActiveWeapon()

    if IsValid(weapon) then
        local func = weapon.CalcView
        if func then
            local origin, angles, fov = func(weapon, ply, base_view.origin or origin, base_view.angles or angles, base_view.fov or fov)
            base_view.origin, base_view.angles, base_view.fov = origin or base_view.origin, angles or base_view.angles, fov or base_view.fov
        end
    end

    if base_view then
        origin, angles, fov, znear, zfar, drawviewer = base_view.origin or origin, base_view.angles or angles, base_view.fov or fov, base_view.znear or znear, base_view.zfar or zfar, base_view.drawviewer or false
    end

    local view = {
        origin = origin,
        angles = angles,
        fov = fov - 20 * math.ease.InOutQuad(frac_zoom),
        drawviewer = drawviewer
    }

    return view
end)

local function footstep(ply, pos, foot, sound, volume, rf, jumped)
    if ply != LocalPlayer() then return end

    local speed = ply:GetMaxSpeed()
    local typee = "normal"
    local side = 0
    if ply:KeyDown(IN_WALK) then typee = "slow" end
    if ply:KeyDown(IN_SPEED) then typee = "run" end

    if foot == 0 then
        -- left foot
        side = 1
    elseif foot == 1 then
        -- right foot
        side = -1
    end

    local angle = Angle()
    local mult = 1

    if typee == "slow" then mult = mult * 0.2 end
    if typee == "normal" then mult = mult * 0.3 end
    if typee == "run" then mult = mult * 0.5 end

    if ply:KeyDown(IN_FORWARD) then
        angle = angle + Angle(2, side, side)
    end

    if ply:KeyDown(IN_BACK) then
        angle = angle + Angle(-2, side, side)
    end

    if ply:KeyDown(IN_MOVELEFT) then
        angle = angle + Angle(side, side, -2)
    end

    if ply:KeyDown(IN_MOVERIGHT) then
        angle = angle + Angle(side, side, 2)
    end

    angle = angle * mult

    if !use_viewpunch:GetBool() then angle:Zero() end

    if ply:KeyPressed(IN_JUMP) then
        angle = angle + Angle(-3, 0, 0)
    end

    if angle:IsZero() then return end

    angle.x = angle.x * 0.5
    angle.y = angle.y * 0.7
    angle.z = angle.z * 1.1

    vp_punch_angle_velocity = vp_punch_angle_velocity + angle * 20 * math.Clamp(ply:GetMaxSpeed() / ply:GetRunSpeed() * 1.25, 0.5, 1)

    angle.x = angle.x * 1.2
    angle.y = angle.y * 2
    angle.z = angle.z * 1.2

    vp_punch_angle_velocity2 = vp_punch_angle_velocity2 + angle * 20 * math.Clamp(ply:GetMaxSpeed() / ply:GetRunSpeed() * 1.25, 0.5, 1)
end

if game.SinglePlayer() then
    net.Receive("viewmodel_punch_footstep", function()
        footstep(net.ReadEntity(), net.ReadVector(), net.ReadFloat(), net.ReadString(), net.ReadFloat(), NULL)
    end)
else
    hook.Add("PlayerFootstep", "viewmodel_punch_footstep", footstep)
end