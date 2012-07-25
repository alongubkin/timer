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
    author      = "alongub | Glite",
    description = "Weapons component for [Timer]",
    version     = PL_VERSION,
    url         = "https://github.com/alongubkin/timer"
};

public OnPluginStart()
{
	RegConsoleCmd("sm_scout", ScoutCommand);
	RegConsoleCmd("sm_usp", USPCommand);
	RegConsoleCmd("sm_awp", AWPCommand);
}

public OnMapStart()
{
	Array_Fill(g_scout, sizeof(g_scout), 0, 0);
	Array_Fill(g_usp, sizeof(g_usp), 0, 0);
	Array_Fill(g_awp, sizeof(g_awp), 0, 0);	
}

public OnClientPutInServer(client)
{
	g_scout[client] = 0;
	g_usp[client] = 0;	
	g_awp[client] = 0;	
}

public Action:ScoutCommand(client, args)
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
	return Plugin_Handled;
}

public Action:USPCommand(client, args)
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
	return Plugin_Handled;
}

public Action:AWPCommand(client, args)
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
	return Plugin_Handled;
}