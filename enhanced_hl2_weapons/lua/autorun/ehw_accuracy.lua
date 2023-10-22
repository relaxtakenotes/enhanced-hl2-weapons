local zoom_spread = CreateConVar("sv_ehw_zoom_spread_mult", 0.5, {FCVAR_ARCHIVE, FCVAR_GAMEDLL})

if SERVER then
    util.AddNetworkString("ehw_player_zoomed")

    net.Receive("ehw_player_zoomed", function(len, ply) 
        ply.ehw_zoomed = net.ReadBool()
    end)
end

hook.Add("InitPostEntity", "ehw_deploy", function() 
    RunConsoleCommand("sv_defaultdeployspeed", "1")
end)

EHW_RUNNING_HOOKS = false
hook.Add("EntityFireBullets", "ehw_accuracy", function(ent, data) 
    if EHW_RUNNING_HOOKS then return end
    if ent.ehw_zoomed then
        EHW_RUNNING_HOOKS = true
        hook.Run("EntityFireBullets", ent, data)
        EHW_RUNNING_HOOKS = false
        data.Spread = data.Spread * zoom_spread:GetFloat()
        return true
    end
end)