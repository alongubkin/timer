#pragma semicolon 1

#include <sourcemod>
#include <timer>

public Plugin:myinfo =
{
	name        = "[Timer] Menu",
	author      = "alongub | Glite",
	description = "Menu component for [Timer]",
	version     = PL_VERSION,
	url         = "https://github.com/alongubkin/timer"
};

public OnPluginStart()
{
	RegConsoleCmd("sm_menu", MenuCommand);
}

public Action:MenuCommand(client, args)
{
	OpenMenu(client);
	return Plugin_Handled;
}

OpenMenu(client)
{
	new Handle:menu = CreateMenu(MenuHandler);

	SetMenuTitle(menu, "Timer\n \n");
	SetMenuExitButton(menu, true);

	AddMenuItem(menu, "sm_clear", "!clear - Erase all checkpoints");
	AddMenuItem(menu, "sm_next", "!next - Next checkpoint");
	AddMenuItem(menu, "sm_prev", "!prev - Previous checkpoint");
	AddMenuItem(menu, "sm_save", "!save (!s) - Saves a checkpoint");
	AddMenuItem(menu, "sm_tele", "!tele (!t) - Teleports you to last checkpoint");
	AddMenuItem(menu, "sm_hide", "!hide - Toogles player visibility");
	AddMenuItem(menu, "sm_scout", "!scout - Spawns a scout");
	AddMenuItem(menu, "sm_usp", "!usp - Spawns a usp");
	AddMenuItem(menu, "sm_awp", "!awp - Spawns a awp");
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}

public MenuHandler(Handle:menu, MenuAction:action, param1, param2)
{
	if (action == MenuAction_End) 
	{
		CloseHandle(menu);
	}
	else if (action == MenuAction_Select) 
	{
		decl String:info[32];		
		GetMenuItem(menu, param2, info, sizeof(info));
		
		FakeClientCommand(param1, info);
		OpenMenu(param1);
	}
}