#pragma semicolon 1

#include <sourcemod>
#include <loghelper>
#include <sdkhooks>
#include <smlib>
#include <timer>

new bool:g_hide[MAXPLAYERS+1];
new g_iWeaponOwner[2048];

public Plugin:myinfo =
{
    name        = "[Timer] Player Visibility",
    author      = "alongub | Glite",
    description = "Player visibility component for [Timer]",
    version     = PL_VERSION,
    url         = "https://github.com/alongubkin/timer"
};

public OnPluginStart()
{
	LoadTranslations("timer.phrases");
	
	Array_Fill(g_hide, sizeof(g_hide), false, 0);
	RegConsoleCmd("sm_hide", HideCommand);
}

public OnMapStart()
{
	Array_Fill(g_hide, sizeof(g_hide), false, 0);
}

public OnClientPutInServer(client) 
{ 
	g_hide[client] = false; 
	SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit);
	SDKHook(client, SDKHook_WeaponEquip, Hook_WeaponEquip);
	SDKHook(client, SDKHook_WeaponDrop, Hook_WeaponDrop);
}

public OnEntityCreated(entity, const String:classname[])
{
	if (entity > MaxClients && entity < 2048)
	{
		g_iWeaponOwner[entity] = 0;
	}
}

public OnEntityDestroyed(entity)
{
	if (entity > MaxClients && entity < 2048)
	{
		g_iWeaponOwner[entity] = 0;
	}
}

public Hook_WeaponEquip(client, weapon)
{
	if (weapon > MaxClients && weapon < 2048)
	{
		g_iWeaponOwner[weapon] = client;
		SDKHook(weapon, SDKHook_SetTransmit, Hook_SetTransmitWeapon);
	}
}

public Hook_WeaponDrop(client, weapon)
{
	if (weapon > MaxClients && weapon < 2048)
	{
		g_iWeaponOwner[weapon] = 0;
		SDKUnhook(weapon, SDKHook_SetTransmit, Hook_SetTransmitWeapon);
	}
}

public Action:Hook_SetTransmit(entity, client) 
{ 
    return !(client != entity && (0 < entity <= MaxClients) && g_hide[client]) ? Plugin_Continue : Plugin_Handled; 
}

public Action:Hook_SetTransmitWeapon(entity, client) 
{ 
    return !(g_iWeaponOwner[entity] && g_iWeaponOwner[entity] != client && g_hide[client]) ? Plugin_Continue : Plugin_Handled; 
}

public Action:HideCommand(client, args)
{
	g_hide[client] = !g_hide[client];
	PrintToChat(client, "%s%t", PLUGIN_PREFIX, "Toggle visibilty");
	return Plugin_Handled;
}