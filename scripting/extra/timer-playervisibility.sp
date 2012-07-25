#pragma semicolon 1

#include <sourcemod>
#include <loghelper>
#include <sdkhooks>
#include <smlib>
#include <timer>

new bool:g_hide[MAXPLAYERS+1];

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
	Array_Fill(g_hide, sizeof(g_hide), false, 0);

	AddCommandListener(SayCommand, "say");
	AddCommandListener(SayCommand, "say_team");	
	AddCommandListener(HideCommand, "sm_hide");	
}

public OnMapStart()
{
	Array_Fill(g_hide, sizeof(g_hide), false, 0);
}

public OnClientPutInServer(client) 
{ 
    g_hide[client] = false; 
    SDKHook(client, SDKHook_SetTransmit, Hook_SetTransmit); 
}

public Action:Hook_SetTransmit(entity, client) 
{ 
    if (client != entity && (0 < entity <= MaxClients) && g_hide[client]) 
        return Plugin_Handled; 
     
    return Plugin_Continue; 
}

public Action:SayCommand(client, const String:command[], args)
{
	decl String:buffer[128];
	GetCmdArg(1, buffer, sizeof(buffer));

	new bool:hidden = StrEqual(buffer, "/hide", true);
	if (StrEqual(buffer, "!hide", true) || hidden)
	{
		ToggleVisibility(client);

		if (hidden)
			return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action:HideCommand(client, const String:command[], args)
{
	ToggleVisibility(client);
	return Plugin_Handled;
}

ToggleVisibility(client)
{
	g_hide[client] = !g_hide[client];
	PrintToChat(client, "Toggled player visibility.");
}