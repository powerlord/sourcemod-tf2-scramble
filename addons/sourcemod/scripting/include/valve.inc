/*
 * Functions inspired by Valve's code in the Source SDK 2013
 */
#if defined _valve_included
  #endinput
#endif
#define _valve_included

#define HUD_PRINTNOTIFY		1
#define HUD_PRINTCONSOLE		2
#define HUD_PRINTTALK			3
#define HUD_PRINTCENTER		4

// Print a Valve translation phrase to a group of players
// Adapted from util.h's UTIL_PrintToClientFilter
stock PrintValveTranslation(clients[],
						    numClients,
						    msg_dest,
						    const String:msg_name[],
						    const String:param1[]="",
						    const String:param2[]="",
						    const String:param3[]="",
						    const String:param4[]="")
{
	new Handle:bf = StartMessage("TextMsg", clients, numClients, USERMSG_RELIABLE);
	
	if (GetUserMessageType() == UM_Protobuf)
	{
		PbSetInt(bf, "msg_dest", msg_dest);
		PbAddString(bf, "params", msg_name);
		
		PbAddString(bf, "params", param1);
		PbAddString(bf, "params", param2);
		PbAddString(bf, "params", param3);
		PbAddString(bf, "params", param4);
	}
	else
	{
		BfWriteByte(bf, msg_dest);
		BfWriteString(bf, msg_name);
		
		BfWriteString(bf, param1);
		BfWriteString(bf, param2);
		BfWriteString(bf, param3);
		BfWriteString(bf, param4);
	}
	
	EndMessage();
}

stock PrintValveTranslationToAll(msg_dest,
								const String:msg_name[],
								const String:param1[]="",
								const String:param2[]="",
								const String:param3[]="",
								const String:param4[]="")
{
	new total = 0;
	new clients[MaxClients];
	for (new i=1; i<=MaxClients; i++)
	{
		if (IsClientConnected(i))
		{
			clients[total++] = i;
		}
	}
	PrintValveTranslation(clients, total, msg_dest, msg_name, param1, param2, param3, param4);
}

stock PrintValveTranslationToOne(client,
								msg_dest,
								const String:msg_name[],
								const String:param1[]="",
								const String:param2[]="",
								const String:param3[]="",
								const String:param4[]="")
{
	new players[1];
	
	players[0] = client;
	
	PrintValveTranslation(players, 1, msg_dest, msg_name, param1, param2, param3, param4);
}

// Get the amount of time left on a timer
// Adapted from Valve's SDK2013 CTeamRoundTimer::GetTimeRemaining()
stock GetTimeRemaining(timer)
{
	if (!IsValidEntity(timer))
	{
		return -1;
	}
	
	decl String:classname[64];
	GetEntityClassname(timer, classname, sizeof(classname));
	if (strcmp(classname, "team_round_timer") != 0)
	{
		return -1;
	}
	
	new Float:flSecondsRemaining;
	
	if (GetEntProp(timer, Prop_Send, "m_bStopWatchTimer") && GetEntProp(timer, Prop_Send, "m_bInCaptureWatchState"))
	{
		flSecondsRemaining = GetEntPropFloat(timer, Prop_Send, "m_flTotalTime");
	}
	else
	{
		if (GetEntProp(timer, Prop_Send, "m_bTimerPaused"))
		{
			flSecondsRemaining = GetEntPropFloat(timer, Prop_Send, "m_flTimeRemaining");
		}
		else
		{
			flSecondsRemaining = GetEntPropFloat(timer, Prop_Send, "m_flTimerEndTime") - GetGameTime();
		}
	}
	
	return RoundFloat(flSecondsRemaining);
}
