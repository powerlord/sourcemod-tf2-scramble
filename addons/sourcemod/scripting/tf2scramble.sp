/**
 * vim: set ts=4 :
 * =============================================================================
 * TF2 Scramble
 * An alternative to GScramble
 *
 * TF2 Scramble (C)2014 Powerlord (Ross Bemrose).  All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 *
 * Version: $Id$
 */
#include <sourcemod>
#include <sdktools>
#include <dhooks>
#include <sdkhooks>

#undef REQUIRE_PLUGIN
#include <nativevotes>
#include <gameme>
#include <hlxce-sm-api>

#pragma semicolon 1
#define VERSION "0.0.1"

// #define SUPPORT_SDK2013

// Various Valve defines
#define HUD_ALERT_SCRAMBLE_TEAMS 0

#define HUD_PRINTNOTIFY		1
#define HUD_PRINTCONSOLE	2
#define HUD_PRINTTALK		3
#define HUD_PRINTCENTER		4

new EngineVersion:g_EngineVersion;

enum
{
	GameType_Generic,
	GameType_CTF,
	GameType_CP,
	GameType_Payload,
	GameType_Arena
}

enum RoundEndType
{
	RoundEnd_Immediate,
	RoundEnd_Delay
}

// team_round_timer's m_nState seems to be 0 for Setup or 1 for Running
// Note that Waiting For Players timers will always be Running
enum
{
	TimerState_Setup,
	TimerState_Running
}

//SDKCalls / Hooks
new Handle:g_Call_ChangeTeam;
new Handle:g_Call_SetScramble;
new Handle:g_Hook_HandleScramble;

// CVars
new Handle:g_Cvar_Enabled;
new Handle:g_Cvar_Scramble;
new Handle:g_Cvar_Balance;
new Handle:g_Cvar_VoteScramble;
new Handle:g_Cvar_ScrambleMode;
new Handle:g_Cvar_Immunity;
new Handle:g_Cvar_Timeleft;
new Handle:g_Cvar_Autobalance_Time;
new Handle:g_Cvar_Autobalance_ForceTime;

// Valve CVars
new Handle:g_Cvar_Mp_Autobalance; // mp_autobalance
new Handle:g_Cvar_Mp_Scrambleteams_Auto; // mp_scrambleteams_auto
new Handle:g_Cvar_Sv_Vote_Scramble; // sv_vote_issue_scramble_teams_allowed
new Handle:g_Cvar_Mp_BonusRoundTime; // mp_bonusroundtime

new RoundEndType:g_RoundEndType = RoundEnd_Immediate;
new g_Tcpm = INVALID_ENT_REFERENCE;

new Handle:g_Timer_Autobalance;

public Plugin:myinfo = {
	name			= "TF2 Scramble",
	author			= "Powerlord",
	description		= "Alternative to TF2's Scramble system and GScramble",
	version			= VERSION,
	url				= ""
};

// We need to track this globally since we shut off on MvM and Arena.
new bool:g_Enabled;

// Native Support
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	g_EngineVersion = GetEngineVersion();
	
	if (g_EngineVersion != Engine_TF2)
	{
#if defined SUPPORT_SDK2013
		if (g_EngineVersion != Engine_SDK2013)
		{
			strcopy(error, err_max, "Only supports TF2 and SDK 2013.");
		}
#else
	strcopy(error, err_max, "Only supports TF2.");
#endif
	}

	// might add natives to this
	RegPluginLibrary("tf2-scramble");
	
	return APLRes_Success;
}
  
public OnPluginStart()
{
	CreateConVar("tf2scramble_version", VERSION, "TF2 Scramble version", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY);
	g_Cvar_Enabled = CreateConVar("tf2scramble_enable", "1", "Enable TF2 Scramble?", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	g_Cvar_Scramble = CreateConVar("tf2scramble_scramble", "1", "Enable TF2 Scramble's scramble abilities?", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_Cvar_Balance = CreateConVar("tf2scramble_balance", "1", "Enable TF2 Scramble's balance abilities?", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_Cvar_VoteScramble = CreateConVar("tf2scramble_vote", "1", "Enable our own vote scramble?  Will disable Valve's votescramble.", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_Cvar_ScrambleMode = CreateConVar("tf2scramble_mode", "1", "Scramble Mode: 0 = Random, 1 = Score, 2 = Score Per Minute, 3 = Kill/Death Ratio, 4 = Use Subplugin settings (acts like 0 if no subplugins loaded)", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 4.0);
	g_Cvar_Immunity = CreateConVar("tf2scramble_immunity", "1", "Should Medics with 50%+ Uber or Engineers with Level 2+ Buildings be immune to autobalance?  Note: Only applies to in-round scrambles and if we run out of other players, they WILL be balanced.", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 7.0);
	g_Cvar_Timeleft = CreateConVar("tf2scramble_timeleft", "60", "If there is less than this much or less sectonds left on a timer, stop balancing. Ignored on Arena and KOTH.", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 7.0);
	g_Cvar_Autobalance_Time = CreateConVar("tf2scramble_autobalance_time", "5", "Seconds before autobalance should occur once detected... only for dead players.", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 5.0, true, 30.0);
	g_Cvar_Autobalance_ForceTime = CreateConVar("tf2scramble_autobalance_forcetime", "15", "Seconds before autobalance should be forced if no one on a team dies.", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 5.0, true, 30.0);
	
	// Add more cvars
	
	// Valve CVars
	g_Cvar_Mp_Autobalance = FindConVar("mp_autobalance");
	g_Cvar_Mp_Scrambleteams_Auto = FindConVar("mp_scrambleteams_auto");
	g_Cvar_Sv_Vote_Scramble = FindConVar("sv_vote_issue_scramble_teams_allowed");
	g_Cvar_Mp_BonusRoundTime = FindConVar("mp_bonusroundtime");
	
	LoadTranslations("tf2scramble.phrases");
	LoadTranslations("common.phrases");
	
	new Handle:gamedata = LoadGameConfigFile("tf2scramble");
	
	if (gamedata == INVALID_HANDLE)
	{
		SetFailState("Could not load gamedata");
	}
	
	//void CBasePlayer::ChangeTeam( int iTeamNum, bool bAutoTeam, bool bSilent )
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CBasePlayer::ChangeTeam");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	g_Call_ChangeTeam = EndPrepSDKCall();
	
	//void CTeamplayRules::SetScrambleTeams( bool bScramble )
	StartPrepSDKCall(SDKCall_GameRules);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CTeamplayRules::SetScrambleTeams");
	PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
	g_Call_SetScramble = EndPrepSDKCall();
	
	new handleScrambleOffset = GameConfGetOffset(gamedata, "CTeamplayRules::HandleScrambleTeams");
	
	// void CTeamplayRules::HandleScrambleTeams( void )
	g_Hook_HandleScramble = DHookCreate(handleScrambleOffset, HookType_GameRules, ReturnType_Void, ThisPointer_Ignore, HandleScrambleTeams);
	
	CloseHandle(gamedata);
}

public OnMapStart()
{
	DHookGamerules(g_Hook_HandleScramble, false);
}

public OnConfigsExecuted()
{
	new bool:isMvM = bool:GameRules_GetProp("m_bPlayingMannVsMachine");
	
	new gameType = GameRules_GetProp("m_nGameType");
	
	// off if we're in Arena, MvM, or if the cvar says we're off
	if (gameType == GameType_Arena || isMvM || !GetConVarBool(g_Cvar_Enabled))
	{
		g_Enabled = false;
		return;
	}
	
	g_Enabled = true;
	
	// Disable some Valve CVars based on our CVars.
	if (GetConVarBool(g_Cvar_Balance))
	{
		if (GetConVarBool(g_Cvar_Mp_Autobalance))
		{
			SetConVarBool(g_Cvar_Mp_Autobalance, false);
			LogMessage("Disabled mp_autobalance.");
		}
	}
	
	if (GetConVarBool(g_Cvar_Scramble))
	{
		if (GetConVarBool(g_Cvar_Mp_Scrambleteams_Auto))
		{
			SetConVarBool(g_Cvar_Mp_Scrambleteams_Auto, false);
			LogMessage("Disabled mp_scrambleteams_auto.");
		}
		
		if (GetConVarBool(g_Cvar_VoteScramble) && GetConVarBool(g_Cvar_Sv_Vote_Scramble))
		{
			SetConVarBool(g_Cvar_Sv_Vote_Scramble, false);
			LogMessage("Disabled sv_vote_issue_scramble_teams_allowed.");
		}
	}
}

public TF2_OnWaitingForPlayersEnd()
{
	//ServerCommand("mp_scrambleteams");
}

public Event_Round_Start(Handle:event, const String:name[], bool:dontBroadcast)
{
	g_Timer_Autobalance = CreateTimer(5.0, Timer_Autobalance, _, TIMER_REPEAT);
}

public Event_Round_End(Handle:event, const String:name[], bool:dontBroadcast)
{
	CloseHandle(g_Timer_Autobalance);
	
	if (ShouldScrambleTeams())
	{
		if (g_EngineVersion == Engine_TF2)
		{
			TF2_SendScrambleAlert();
		}
		else
		{
			PrintValveTranslationToAll(HUD_PRINTCENTER, "#game_scramble_onrestart");
			PrintValveTranslationToAll(HUD_PRINTCONSOLE, "#game_scramble_onrestart");
		}
		SetScrambleTeams(true);
		PrintToServer("World triggered \"ScrambleTeams_Auto\"\n");
	}
	
}

TF2_SendScrambleAlert()
{
	new Handle:event = CreateEvent("teamplay_alert");
	if (event != INVALID_HANDLE)
	{
		SetEventInt(event, "alert_type", HUD_ALERT_SCRAMBLE_TEAMS);
		FireEvent(event);
	}
}

bool:ShouldScrambleTeams()
{
	// Logic to determine if we should scramble here
	return false;
}

stock ForceScramble()
{
	new time = 5; // Fix this later, this is just here so we have this code when we need it.
	
	if (time > 1)
	{
		pFormat = "#game_scramble_in_secs";
	}
	else
	{
		pFormat = "#game_scramble_in_sec";
	}
	
	// Valve's idea to use 64 here
	new String:strRestartDelay[64];
	Format(strRestartDelay, sizeof(strRestartDelay), "%d", time);
	PrintValveTranslationToAll(HUD_PRINTCENTER, pFormat, strRestartDelay);
	PrintValveTranslationToAll(HUD_PRINTCONSOLE, pFormat, strRestartDelay);
	
	TF2_SendScrambleAlert();
}

public Action:Timer_Autobalance(Handle:Timer)
{
	if (!ShouldAllowBalance())
	{
		return Plugin_Continue;
	}
	
	return Plugin_Continue;
}

bool:ShouldAllowBalance()
{
	// Only run if round is running.  This has a side effect of not running during waiting for players,
	// Sudden Death, or Arena (which counts as Sudden Death)
	new RoundState:state = GameRules_GetRoundState();
	if (state != RoundState_RoundRunning)
	{
		return false;
	}
	
	new timelimit = GetConVarInt(g_Cvar_Timeleft);
	// CTF / 5CP maps, which end immediately when map time expires
	if (g_RoundEndType == RoundEnd_Immediate)
	{
		new timeleft;
		GetMapTimeLeft(timeleft);
		if (timeleft < timelimit)
		{
			return false;
		}
	}

	new timer = -1;
	new bool:found = false;
	// Maps may have multiple timers, e.g. tc_hydro
	while (!found && (timer = FindEntityByClassname(timer, "team_round_timer")) != -1)
	{
		// Check if this is the active timer
		new bool:bShowInHUD = bool:GetEntProp(timer, Prop_Send, "m_bShowInHUD");
		if (bShowInHUD)
		{
			// It IS the active timer
			// Check if we're in Setup
			if (GetEntProp(timer, Prop_Send, "m_nState") == TimerState_Setup)
			{
				return false;
			}
			
			// Check the time remaining
			found = true;
			new Float:timeRemaining = GetEntPropFloat(timer, Prop_Send, "m_flTimeRemaining");
			if (RoundFloat(timeRemaining) < timelimit)
			{
				return false;
			}
		}
	}
	
	
	return true;	
}

// void CTeamplayRules::HandleScrambleTeams( void )
public MRESReturn:HandleScrambleTeams(Handle:hParams)
{
	if (!GetConVarBool(g_Cvar_Enabled) || !GetConVarBool(g_Cvar_Scramble))
	{
		return MRES_Ignored;
	}
	
	// scramble logic goes here
	
	// As far as I can tell, both these args should be true during a scramble
	// ChangeTeam(client, iTeamNum, true, true);
	return MRES_Supercede;
}

// If you're using this, one or both of the last two args should be true,
// or else you should just use ChangeClientTeam
//void CBasePlayer::ChangeTeam( int iTeamNum, bool bAutoTeam, bool bSilent )
stock SwitchTeam(client, iTeamNum, bool:bAutoTeam, bool:bSilent)
{
	SDKCall(g_Call_ChangeTeam, client, iTeamNum, bAutoTeam, bSilent);
}

//void CTeamplayRules::SetScrambleTeams( bool bScramble )
stock SetScrambleTeams(bool:bScramble)
{
	SDKCall(g_Call_SetScramble, bScramble);
}

public OnEntityCreated(entity, const String:classname[])
{
	if (StrEqual(classname, "team_control_point_master"))
	{
		SDKHook(entity, SDKHook_SpawnPost, Hook_TCPMSpawn);
	}
}

public OnEntityDestroyed(entity)
{
	new tcpm = EntRefToEntIndex(g_Tcpm);
	
	if (entity == tcpm)
	{
		g_Tcpm = INVALID_ENT_REFERENCE;
		g_RoundEndType = RoundEnd_Immediate;
	}
}

public Hook_TCPMSpawn(entity)
{
	g_Tcpm = EntIndexToEntRef(entity);
	
	// As far as I can tell, this is what controls whether a map ends immediately or not.
	// This is why pl_upward used to end immediately despite being payload.
	if (GetEntProp(entity, Prop_Data, "m_bPlayAllRounds"))
	{
		g_RoundEndType = RoundEnd_Delay;
	}
}

// Some stocks that I may move to a .inc later
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