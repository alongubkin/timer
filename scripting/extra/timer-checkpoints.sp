#pragma semicolon 1

#include <sourcemod>
#include <loghelper>
#include <smlib>
#include <timer>

#undef REQUIRE_PLUGIN
#include <timer-logging>


enum Checkpoint
{
	Id,
	String:Auth[32],
	String:Map[32],
	Float:Position[3],
	Order
}

/**
 * Global Variables
 */
new Handle:g_hSQL;

new String:g_currentMap[32];
new g_reconnectCounter = 0;

new g_checkpoints[2048][Checkpoint];
new g_checkpointCount = 0;

new bool:g_loadingCheckpoints = false;

new g_currentCheckpoint[MAXPLAYERS+1];

new bool:g_timerLogging = false;

public Plugin:myinfo =
{
    name        = "[Timer] Checkpoints",
    author      = "alongub | Glite",
    description = "Checkpoints component for [Timer]",
    version     = PL_VERSION,
    url         = "https://github.com/alongubkin/timer"
};

public OnPluginStart()
{
	ConnectSQL(true);
	
	g_timerLogging = LibraryExists("timer-logging");

	RegConsoleCmd("sm_clear", ClearCommand);
	RegConsoleCmd("sm_next", NextCommand);
	RegConsoleCmd("sm_prev", PrevCommand);
	RegConsoleCmd("sm_save", SaveCommand);
	RegConsoleCmd("sm_s", SaveCommand);
	RegConsoleCmd("sm_tele", TeleCommand);
	RegConsoleCmd("sm_t", TeleCommand);

	Array_Fill(g_currentCheckpoint, sizeof(g_currentCheckpoint), 0, 0);
}

public OnLibraryAdded(const String:name[])
{
	if (StrEqual(name, "timer-logging"))
	{
		g_timerLogging = true;
	}
}

public OnLibraryRemoved(const String:name[])
{
	if (StrEqual(name, "timer-logging"))
	{
		g_timerLogging = false;
	}

}


public OnMapStart()
{
	GetCurrentMap(g_currentMap, sizeof(g_currentMap));

	LoadCheckpoints();
	Array_Fill(g_currentCheckpoint, sizeof(g_currentCheckpoint), 0, 0);
}

public OnClientPutInServer(client)
{
	g_currentCheckpoint[client] = 0;
}

public Action:ClearCommand(client, args)
{
	ClearCheckpoints(client);
	return Plugin_Handled;
}

public Action:NextCommand(client, args)
{
	GoToCheckpoint(client, g_currentCheckpoint[client] + 1);
	return Plugin_Handled;
}

public Action:PrevCommand(client, args)
{
	GoToCheckpoint(client, g_currentCheckpoint[client] - 1);
	return Plugin_Handled;
}

public Action:SaveCommand(client, args)
{
	SaveCheckpoint(client);
	return Plugin_Handled;
}

public Action:TeleCommand(client, args)
{
	TeleportToLastCheckpoint(client);
	return Plugin_Handled;
}

LoadCheckpoints()
{
	/*if (g_loadingCheckpoints)
		return;*/
	
	g_loadingCheckpoints = true;

	if (g_hSQL == INVALID_HANDLE)
	{
		ConnectSQL(true);
	}
	else
	{	
		decl String:query[384];
		Format(query, sizeof(query), "SELECT id, auth, map, position_x, position_y, position_z, `order` FROM `checkpoints` WHERE map = '%s' ORDER BY `order` ASC", g_currentMap);

		SQL_TQuery(g_hSQL, LoadCheckpointsCallback, query, _, DBPrio_Normal);
	}
}

public LoadCheckpointsCallback(Handle:owner, Handle:hndl, const String:error[], any:client)
{
	g_checkpointCount = 0;

	if (hndl == INVALID_HANDLE)
	{
		if(g_timerLogging)
		{
			Timer_LogError(error);
		}
		return;
	}
	
	while (SQL_FetchRow(hndl))
	{
		g_checkpoints[g_checkpointCount][Id] = SQL_FetchInt(hndl, 0);

		SQL_FetchString(hndl, 1, g_checkpoints[g_checkpointCount][Auth], 32);
		SQL_FetchString(hndl, 2, g_checkpoints[g_checkpointCount][Map], 32);

		g_checkpoints[g_checkpointCount][Position][0] = SQL_FetchFloat(hndl, 3);
		g_checkpoints[g_checkpointCount][Position][1] = SQL_FetchFloat(hndl, 4);
		g_checkpoints[g_checkpointCount][Position][2] = SQL_FetchFloat(hndl, 5);

		g_checkpoints[g_checkpointCount][Order] = SQL_FetchInt(hndl, 6);
	
		g_checkpointCount++;
	}
	
	CloseHandle(hndl);
	
	g_loadingCheckpoints = false;
}

ConnectSQL(bool:refreshCache)
{
    if (g_hSQL != INVALID_HANDLE)
        CloseHandle(g_hSQL);
	
    g_hSQL = INVALID_HANDLE;

    if (SQL_CheckConfig("timer"))
	{
		SQL_TConnect(ConnectSQLCallback, "timer", refreshCache);
	}
    else
	{
		if(g_timerLogging)
		{
			Timer_LogError("PLUGIN STOPPED - Reason: no config entry found for 'timer' in databases.cfg - PLUGIN STOPPED");
		}
	}
}

public ConnectSQLCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (g_reconnectCounter >= 5)
	{
		if(g_timerLogging)
		{
			Timer_LogError("PLUGIN STOPPED - Reason: reconnect counter reached max - PLUGIN STOPPED");
		}
		return;
	}

	if (hndl == INVALID_HANDLE)
	{
		if(g_timerLogging)
		{
			Timer_LogError("Connection to SQL database has failed, Reason: %s", error);
		}

		g_reconnectCounter++;
		ConnectSQL(data);

		return;
	}

	decl String:driver[16];
	SQL_GetDriverIdent(owner, driver, sizeof(driver));

	g_hSQL = CloneHandle(hndl);	

	if (StrEqual(driver, "mysql", false))
	{
		SQL_FastQuery(g_hSQL , "SET NAMES 'utf8'");
		SQL_TQuery(g_hSQL, CreateSQLTableCallback, "CREATE TABLE IF NOT EXISTS `checkpoints` (`id` int(11) NOT NULL AUTO_INCREMENT, `auth` varchar(32) NOT NULL, `map` varchar(32) NOT NULL, `position_x` float NOT NULL, `position_y` float NOT NULL, `position_z` float NOT NULL, `order` int(11) NOT NULL, PRIMARY KEY (`id`));");
	}
	else if (StrEqual(driver, "sqlite", false))
	{
		SQL_TQuery(g_hSQL, CreateSQLTableCallback, "CREATE TABLE IF NOT EXISTS `checkpoints` (`id` INTEGER PRIMARY KEY, `auth` varchar(32) NOT NULL, `map` varchar(32) NOT NULL, `position_x` float NOT NULL, `position_y` float NOT NULL, `position_z` float NOT NULL, `order` INTEGER NOT NULL);");
	}

	
	g_reconnectCounter = 1;
}

public CreateSQLTableCallback(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (owner == INVALID_HANDLE)
	{
		if(g_timerLogging)
		{
			Timer_LogError(error);
		}

		g_reconnectCounter++;
		ConnectSQL(data);
		
		return;
	}
	
	if (hndl == INVALID_HANDLE)
	{
		if(g_timerLogging)
		{
			Timer_LogError(error);
		}
		return;
	}

	
	LoadCheckpoints();
	
	CloseHandle(hndl);
}


ClearCheckpoints(client)
{
	if (g_hSQL == INVALID_HANDLE)
	{
		ConnectSQL(false);
	}
	else
	{
		decl String:auth[32];
		GetClientAuthString(client, auth, sizeof(auth));
			
		decl String:query[384];
		Format(query, sizeof(query), "DELETE FROM checkpoints WHERE auth = '%s' AND map = '%s';", auth, g_currentMap);
	
		SQL_TQuery(g_hSQL, ClearCheckpointsCallback, query, client, DBPrio_Normal);
	}
}

public ClearCheckpointsCallback(Handle:owner, Handle:hndl, const String:error[], any:client)
{
	if (hndl == INVALID_HANDLE)
	{
		if(g_timerLogging)
		{
			Timer_LogError(error);
		}
		return;
	}
	
	PrintToChat(client, "All checkpoints for this map removed successfully.");

	LoadCheckpoints();
	
	CloseHandle(hndl);
	
	g_currentCheckpoint[client] = 0;
}

SaveCheckpoint(client)
{
	if (g_hSQL == INVALID_HANDLE)
	{
		ConnectSQL(false);
	}
	else
	{
		if(GetEntityFlags(client) & FL_ONGROUND)
		{
			new Float:position[3];
			GetClientAbsOrigin(client, position);

			decl String:auth[32];
			GetClientAuthString(client, auth, sizeof(auth));

			new order = 0;

			for (new checkpoint = 0; checkpoint < g_checkpointCount; checkpoint++)
			{
				if (StrEqual(g_checkpoints[checkpoint][Auth], auth))
				{
					order = g_checkpoints[checkpoint][Order];
				}
			}

			order++;

			decl String:query[384];
			Format(query, sizeof(query), "INSERT INTO checkpoints (auth, map, position_x, position_y, position_z, `order`) VALUES ('%s', '%s', %f, %f, %f, %d)", auth, g_currentMap, position[0], position[1], position[2], order);

			SQL_TQuery(g_hSQL, SaveCheckpointCallback, query, client, DBPrio_Normal);
		}
		else
		{
			PrintToChat(client, "You must be on ground to save.");
		}
	}
}

public SaveCheckpointCallback(Handle:owner, Handle:hndl, const String:error[], any:client)
{
	if (hndl == INVALID_HANDLE)
	{
		if(g_timerLogging)
		{
			Timer_LogError(error);
		}
		return;
	}
	
	PrintToChat(client, "Checkpoint saved successfully.");
	LoadCheckpoints();
	
	CloseHandle(hndl);
}

TeleportToLastCheckpoint(client)
{
	new cp = -1;

	decl String:auth[32];
	GetClientAuthString(client, auth, sizeof(auth));

	for (new checkpoint = 0; checkpoint < g_checkpointCount; checkpoint++)
	{
		if (StrEqual(g_checkpoints[checkpoint][Auth], auth))
		{
			cp = checkpoint;
		}
	}

	if (cp == -1)
	{
		PrintToChat(client, "You have no checkpoints saved.");
		return;
	}

	new Float:position[3];
	Array_Copy(g_checkpoints[cp][Position], position, 3);

	Timer_Stop(client);
	TeleportEntity(client, position, NULL_VECTOR, NULL_VECTOR);
	g_currentCheckpoint[client] = g_checkpoints[cp][Order];
}

GoToCheckpoint(client, order)
{
	new cp = -1;

	decl String:auth[32];
	GetClientAuthString(client, auth, sizeof(auth));

	for (new checkpoint = 0; checkpoint < g_checkpointCount; checkpoint++)
	{
		if (StrEqual(g_checkpoints[checkpoint][Auth], auth) && g_checkpoints[checkpoint][Order] == order)
		{
			cp = checkpoint;
			break;
		}
	}

	if (cp == -1)
	{
		return;
	}

	new Float:position[3];
	Array_Copy(g_checkpoints[cp][Position], position, 3);
	
	Timer_Stop(client);
	TeleportEntity(client, position, NULL_VECTOR, NULL_VECTOR);
	g_currentCheckpoint[client] = order;
}