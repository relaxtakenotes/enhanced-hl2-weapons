
if game.SinglePlayer() then
    util.AddNetworkString("viewmodel_punch_footstep")

    hook.Add("PlayerFootstep", "viewmodel_punch_footstep", function(ply, pos, foot, sound, volume, filter)
        net.Start("viewmodel_punch_footstep")
        net.WriteEntity(ply)
        net.WriteVector(pos)
        net.WriteFloat(foot)
        net.WriteString(sound)
        net.WriteFloat(volume)
        net.Broadcast()
    end)

    hook.Add("PlayerTick", "send_stepsoundtime", function(ply, mv) 
        ply:SetNW2Float( "ehw_stepsoundtime", hook.Run("PlayerStepSoundTime", ply, 0, ply:KeyDown(IN_WALK)) )
    end)
end