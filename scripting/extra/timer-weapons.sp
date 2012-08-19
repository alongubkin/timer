#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <timer>

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

public Action:ScoutCommand(client, args)
{
	if(IsPlayerAlive(client))
	{
		if (GetPlayerWeaponSlot(client, 0) == -1)
		{
			GivePlayerItem(client, "weapon_scout");
		}
		else
		{
			PrintToChat(client, "Drop your primary weapon.");
		}
	}
	return Plugin_Handled;
}

public Action:USPCommand(client, args)
{
	if(IsPlayerAlive(client))
	{
		if (GetPlayerWeaponSlot(client, 1) == -1)
		{
			GivePlayerItem(client, "weapon_usp");
		}
		else
		{
			PrintToChat(client, "Drop your secondary weapon.");
		}
	}
	
	return Plugin_Handled;
}

public Action:AWPCommand(client, args)
{
	if(IsPlayerAlive(client))
	{
		if (GetPlayerWeaponSlot(client, 0) == -1)
		{
			GivePlayerItem(client, "weapon_awp");
		}
		else
		{
			PrintToChat(client, "Drop your primary weapon.");
		}
	}

	return Plugin_Handled;
}