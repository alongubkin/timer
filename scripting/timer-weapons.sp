#pragma semicolon 1

#include <sourcemod>
#include <loghelper>
#include <smlib>
#include <timer>

/**
 * Global Variables
 */
new g_scout[MAXPLAYERS+1];
new g_usp[MAXPLAYERS+1];
new g_awp[MAXPLAYERS+1];

public Plugin:myinfo =
{
    name        = "[Timer] Weapons",
    author      = "alongub",
    description = "Weapons component for [Timer]",
    version     = PL_VERSION,
    url         = "http://steamcommunity.com/id/alon"
};

public OnPluginStart()
{
	HookEvent("player_connect", Event_PlayerConnect);

	AddCommandListener(SayCommand, "say");
	AddCommandListener(SayCommand, "say_team");	

	AddCommandListener(ScoutCommand, "sm_scout");
	AddCommandListener(USPCommand, "sm_usp");
	AddCommandListener(AWPCommand, "sm_usp");
}

public OnMapStart()
{
	Array_Fill(g_scout, sizeof(g_scout), 0, 0);
	Array_Fill(g_usp, sizeof(g_usp), 0, 0);
	Array_Fill(g_awp, sizeof(g_awp), 0, 0);	
}

public Action:Event_PlayerConnect(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	g_scout[client] = 0;
	g_usp[client] = 0;	
	g_awp[client] = 0;	
}

public Action:SayCommand(client, const String:command[], args)
{
	decl String:buffer[128];
	GetCmdArg(1, buffer, sizeof(buffer));

	new bool:hidden = StrEqual(buffer, "/scout", true);
	if (StrEqual(buffer, "!scout", true) || hidden)
	{
		Scout(client);

		if (hidden)
			return Plugin_Handled;
	}

	hidden = StrEqual(buffer, "/usp", true);
	if (StrEqual(buffer, "!usp", true) || hidden)
	{
		USP(client);

		if (hidden)
			return Plugin_Handled;
	}

	hidden = StrEqual(buffer, "/awp", true);
	if (StrEqual(buffer, "!awp", true) || hidden)
	{
		AWP(client);

		if (hidden)
			return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action:ScoutCommand(client, const String:command[], args)
{
	Scout(client);
	return Plugin_Handled;
}

public Action:USPCommand(client, const String:command[], args)
{
	USP(client);
	return Plugin_Handled;
}

public Action:AWPCommand(client, const String:command[], args)
{
	AWP(client);
	return Plugin_Handled;
}

Scout(client)
{
	if (g_scout[client] < 7)
	{
		Client_GiveWeapon(client, "weapon_scout");
		g_scout[client]++;
	}
	else
	{
		PrintToChat(client, "You have already took 7 scouts.");
	}
}

USP(client)
{
	if (g_usp[client] < 7)
	{
		Client_GiveWeapon(client, "weapon_usp");
		g_usp[client]++;
	}
	else
	{
		PrintToChat(client, "You have already took 7 USPs.");
	}
}

AWP(client)
{
	if (g_awp[client] < 7)
	{
		Client_GiveWeapon(client, "weapon_awp");
		g_awp[client]++;
	}
	else
	{
		PrintToChat(client, "You have already took 7 AWPs.");
	}
}