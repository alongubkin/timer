#pragma semicolon 1

#include <sourcemod>
#include <timer>
#include <sdkhooks>
#include <cstrike>


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
	
	HookUserMessage(GetUserMessageId("VGUIMenu"), UserMessageHook_VGUIMenu, true);
}

public OnClientPutInServer(client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
}

public Action:OnTakeDamage(client, &attacker, &inflictor, &Float:damage, &damagetype)
{
	if(attacker == 0 && attacker == client && IsPlayerAlive(client))
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(1 <= client <= MaxClients)
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
	
	if (sArg[0] == '2')
	{
		if (IsClientInGame(client))
		{
			FakeClientCommand(client, "jointeam 0");
		}
		return Plugin_Handled;
	}
	else if (sArg[0] == '3')
	{
		if (IsClientInGame(client))
		{
			FakeClientCommand(client, "jointeam 0");
		}
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public Action:UserMessageHook_VGUIMenu(UserMsg:msg_id, Handle:bf, const players[], playersNum, bool:reliable, bool:init) 
{
	decl String:type[16];
	BfReadString(bf, type, sizeof(type));
	
	if (StrEqual(type, "class_ct") || StrEqual(type, "class_ter")) 
	{
		for (new i = 0; i < playersNum; i++) 
		{
			FakeClientCommand(players[i], "joinclass %i", GetRandomInt(0, 4));
			CS_RespawnPlayer(players[i]);
		}
		return Plugin_Handled;
	}

	return Plugin_Continue;
}