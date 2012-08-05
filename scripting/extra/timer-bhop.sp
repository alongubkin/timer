#pragma semicolon 1

#include <sourcemod>
#include <timer>
#include <sdkhooks>
#include <cstrike>

new tsCount, ctsCount;

public Plugin:myinfo =
{
    name        = "[Timer] Bhop",
    author      = "alongub | Glite",
    description = "Bhop component for [Timer]",
    version     = PL_VERSION,
    url         = "https://github.com/alongubkin/timer"
};

public OnPluginStart()
{
	HookEvent("player_spawn", Event_PlayerSpawn);
	
	AddCommandListener(Command_JoinTeam, "jointeam");
	RegConsoleCmd("sm_r", Command_Respawn);
	RegConsoleCmd("sm_respawn", Command_Respawn);	
}

public OnMapStart()
{
	new maxEnt = GetMaxEntities();
	decl String:sClassName[64];
	for (new i = MaxClients; i < maxEnt; i++)
	{
		if (IsValidEdict(i) && IsValidEntity(i) && GetEdictClassname(i, sClassName, sizeof(sClassName)))
		{
			if (StrEqual(sClassName, "info_player_terrorist"))
			{
				tsCount++;
			}
			else if (StrEqual(sClassName, "info_player_counterterrorist"))
			{
				ctsCount++;
			}
		}
	}
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action:OnTakeDamage(client, &attacker, &inflictor, &Float:damage, &damagetype)
{
	if(attacker == 0 && IsPlayerAlive(client))
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new col = GetEntProp(client, Prop_Data, "m_CollisionGroup");
	if(1 <= client <= MaxClients && col == 5)
	{
		SetEntProp(client, Prop_Data, "m_CollisionGroup", 2);
	}
}

public Action:Command_Respawn(client, args)
{
	if(IsClientInGame(client) && GetClientTeam(client) > CS_TEAM_SPECTATOR)
	{ 
		CS_RespawnPlayer(client);
	}
	return Plugin_Handled;
}


public Action:Command_JoinTeam(client, const String:command[], argc)
{
	decl String:sArg[16];
	GetCmdArg(1, sArg, sizeof(sArg));
	
	if (sArg[0] == '2' && ctsCount == 0 && tsCount > 0)
	{
		if (IsClientInGame(client))
		{
			CS_SwitchTeam(client, 2);
			CS_RespawnPlayer(client);
		}
		return Plugin_Handled;
	}
	else if (sArg[0] == '2' && tsCount == 0 && ctsCount > 0)
	{
		if (IsClientInGame(client))
		{
			CS_SwitchTeam(client, 3);
			CS_RespawnPlayer(client);
		}
		return Plugin_Handled;
	}
	else if (sArg[0] == '3' && tsCount == 0 && ctsCount > 0)
	{
		if (IsClientInGame(client))
		{
			CS_SwitchTeam(client, 3);
			CS_RespawnPlayer(client);
		}
		return Plugin_Handled;
	}
	else if (sArg[0] == '3' && ctsCount == 0 && tsCount > 0)
	{
		if (IsClientInGame(client))
		{
			CS_SwitchTeam(client, 2);
			CS_RespawnPlayer(client);
		}
		return Plugin_Handled;
	}
	else if (sArg[0] == '0' && ctsCount == 0 && tsCount > 0)
	{
		if (IsClientInGame(client))
		{
			CS_SwitchTeam(client, 2);
			CS_RespawnPlayer(client);
		}
		return Plugin_Handled;
	}
	else if (sArg[0] == '0' && tsCount == 0 && ctsCount > 0)
	{
		if (IsClientInGame(client))
		{
			CS_SwitchTeam(client, 3);
			CS_RespawnPlayer(client);
		}
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}