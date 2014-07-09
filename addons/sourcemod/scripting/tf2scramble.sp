/**
 * vim: set ts=4 :
 * =============================================================================
 * TF2 Scramble
 * An alternative to GScramble
 * This plugin may work on other games just by editing AskPluginLoad2 to remove
 * the game restriction... hasn't been tested, though.
 * 
 * However, it definitely doesn't work on games that use more than two player
 * teams... sorry Fortress Forever.  Then again, you're looking into moving to
 * a non-Source engine anyway... traitors.
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

#include <tf2_stocks>

#undef REQUIRE_EXTENSIONS
#include <tf2>

#undef REQUIRE_PLUGIN
#include <nativevotes>
// Move these to subplugins
//#include <gameme>
//#include <hlxce-sm-api>

#pragma semicolon 1
#define VERSION "0.0.1"

// #define SUPPORT_SDK2013

#define VACCINATOR 998

// Various Valve defines
#define HUD_ALERT_SCRAMBLE_TEAMS 0

#define HUD_PRINTNOTIFY		1
#define HUD_PRINTCONSOLE	2
#define HUD_PRINTTALK		3
#define HUD_PRINTCENTER		4

new EngineVersion:g_EngineVersion;

// Generic is used for ItemTest and Tutorial maps
// CTF for CTF, SD, MvM, and RD (maybe?)
// CP for A/D CP, 5CP, and TC
// Payload for PL and PLR
// Arena for arena
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

enum
{
	Sorted_TeamNum,
	Sorted_TeamCount
}

enum
{
	Player_Index,
	Player_Value
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
new Handle:g_Cvar_Immunity_Class;
new Handle:g_Cvar_Immunity_Duel;
new Handle:g_Cvar_Immunity_Time;
new Handle:g_Cvar_Timeleft;
new Handle:g_Cvar_Autobalance_Time;
new Handle:g_Cvar_Autobalance_ForceTime;
new Handle:g_Cvar_Scramble_Percent;
new Handle:g_Cvar_NativeVotes;
new Handle:g_Cvar_NativeVotes_Menu;

// Valve CVars
new Handle:g_Cvar_Mp_Autobalance; // mp_autobalance
new Handle:g_Cvar_Mp_Scrambleteams_Auto; // mp_scrambleteams_auto
new Handle:g_Cvar_Sv_Vote_Scramble; // sv_vote_issue_scramble_teams_allowed
new Handle:g_Cvar_Mp_BonusRoundTime; // mp_bonusroundtime
new Handle:g_Cvar_Mp_TeamsUnbalance; // mp_teams_unbalance_limit
new RoundEndType:g_RoundEndType = RoundEnd_Immediate;
new g_Tcpm = INVALID_ENT_REFERENCE;

new Handle:g_Timer_Autobalance;

new bool:g_bWaitingForPlayers = false;
new bool:g_bWeAreBalancing = false;

// Store times from GetTime here
new g_LastBalanced[MAXPLAYERS+1] = { 0, ... };

// Optional extensions/plugins
new bool:g_bUseNativeVotes = false;
new bool:g_bNativeVotesRegisteredMenus = false;

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
	g_Cvar_Immunity_Class = CreateConVar("tf2scramble_class_immunity", "1", "Should Medics with 50%+ Uber or Engineers with Level 2+ Buildings be immune to autobalance? Note: Only applies to autobalancing and if we run out of other players, they WILL be balanced.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_Cvar_Immunity_Duel = CreateConVar("tf2scramble_duel_immunity", "1", "Should dueling players be immune to autobalance? Note: Only applies to autobalancing and if we run out of other players, they WILL be balanced. Scored lower than Engy/Medic", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_Cvar_Immunity_Time = CreateConVar("tf2scramble_time_immunity", "180", "Players will be immune from balancing a second time for this many seconds.  Ignored if all players are marked as immune. Set to 0 to disable.", FCVAR_PLUGIN, true, 0.0, true, 300.0);
	g_Cvar_Timeleft = CreateConVar("tf2scramble_timeleft", "60", "If there is less than this much or less sectonds left on a timer, stop balancing. Ignored on Arena and KOTH. Set to 0 to disable.", FCVAR_PLUGIN, true, 0.0, true, 180.0);
	g_Cvar_Autobalance_Time = CreateConVar("tf2scramble_autobalance_time", "5", "Seconds before autobalance should occur once detected... only for dead players.", FCVAR_PLUGIN, true, 5.0, true, 30.0);
	g_Cvar_Autobalance_ForceTime = CreateConVar("tf2scramble_autobalance_forcetime", "15", "Seconds before autobalance should be forced if no one on a team dies.", FCVAR_PLUGIN, true, 5.0, true, 30.0);
	g_Cvar_Scramble_Percent = CreateConVar("tf2scramble_scramble_percent", "0.55", "What percentage of players should be scrambled?", FCVAR_PLUGIN, true, 0.10, true, 0.90);
	g_Cvar_NativeVotes = CreateConVar("tf2scramble_nativevotes", "1", "Use NativeVotes for votes if available? (Why would you ever disable this?)", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_Cvar_NativeVotes_Menu = CreateConVar("tf2scramble_nativevotes_menu", "1", "Put ScrambleTeams vote in NativeVotes menu?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	
	// Add more cvars
	
	// Valve CVars
	g_Cvar_Mp_Autobalance = FindConVar("mp_autobalance");
	g_Cvar_Mp_Scrambleteams_Auto = FindConVar("mp_scrambleteams_auto");
	g_Cvar_Sv_Vote_Scramble = FindConVar("sv_vote_issue_scramble_teams_allowed");
	g_Cvar_Mp_BonusRoundTime = FindConVar("mp_bonusroundtime");
	g_Cvar_Mp_TeamsUnbalance = FindConVar("mp_teams_unbalance_limit");
	
	// Events
	HookEvent("round_start", Event_Round_Start);
	HookEventEx("teamplay_round_start", Event_Round_Start);
	HookEvent("round_end", Event_Round_End);
	HookEventEx("teamplay_round_win", Event_Round_End);
	
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
	g_bUseNativeVotes = GetConVarBool(g_Cvar_NativeVotes) && LibraryExists("nativevotes");
	
	if (g_EngineVersion == Engine_TF2)
	{
		new bool:isMvM = bool:GameRules_GetProp("m_bPlayingMannVsMachine");
		
		new gameType = GameRules_GetProp("m_nGameType");
		
		// off if we're in Arena, MvM, or if the cvar says we're off
		if (gameType == GameType_Arena || isMvM || !GetConVarBool(g_Cvar_Enabled))
		{
			g_Enabled = false;
			return;
		}
	}
	else
	{
		if (!GetConVarBool(g_Cvar_Enabled))
		{
			g_Enabled = false;
			return;
		}
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

public OnClientConnected(client)
{
	g_LastBalanced[client] = 0;
}

public OnClientDisconnect(client)
{
	// We don't really need to reset it on both connect AND disconnect, but eh...
	g_LastBalanced[client] = 0;
}

public OnLibraryAdded(const String:name[])
{
	if (StrEqual(name, "nativevotes"))
	{
		if (GetConVarBool(g_Cvar_NativeVotes))
		{
			g_bUseNativeVotes = true;
			
			if (g_Enabled)
			{
				// Delay this after experience with DHooks requiring a slight delay before it was "ready"
				CreateTimer(0.2, Timer_CheckNativeVotes);
			}
		}
	}
}

public OnLibraryRemoved(const String:name[])
{
	if (StrEqual(name, "nativevotes"))
	{
		g_bUseNativeVotes = false;
		
		if (g_bNativeVotesRegisteredMenus)
		{
			NativeVotes_UnregisterVoteCommand("ScrambleTeams", NativeVotes_Menu);
			g_bNativeVotesRegisteredMenus = false;
		}
	}
}

public Action:Timer_CheckNativeVotes(Handle:Timer)
{
	if (!g_bUseNativeVotes || g_bNativeVotesRegisteredMenus)
		return Plugin_Stop;

	if (!GetConVarBool(g_Cvar_NativeVotes_Menu) || GetFeatureStatus(FeatureType_Native, "NativeVotes_RegisterVoteCommand") != FeatureStatus_Available)
		return Plugin_Stop;
	
	NativeVotes_RegisterVoteCommand("ScrambleTeams", NativeVotes_Menu);
	
	g_bNativeVotesRegisteredMenus = true;
	
	return Plugin_Stop;
}

public Action:NativeVotes_Menu(client, const String:voteCommand[], const String:voteArgument[], NativeVotesKickType:kickType, target)
{
	if (!IsFakeClient(client))
	{
		new ReplySource:old = SetCmdReplySource(SM_REPLY_TO_CHAT);

		// start vote

		SetCmdReplySource(old);
	}
	
	return Plugin_Handled;
}

public Action:OnClientSayCommand(client, const String:command[], const String:sArgs[])
{
	if (StrEqual(command, "votescramble", false))
	{
		// Do votescramble action
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public TF2_OnWaitingForPlayersStart()
{
	g_bWaitingForPlayers = true;
}

public TF2_OnWaitingForPlayersEnd()
{
	g_bWaitingForPlayers = false;
	//ServerCommand("mp_scrambleteams");
}

public Event_Round_Start(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!g_Enabled)
	{
		return;
	}
	
	g_Timer_Autobalance = CreateTimer(5.0, Timer_Autobalance, _, TIMER_REPEAT);
}

public Event_Round_End(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!g_Enabled)
	{
		return;
	}
	
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
	
	// Logic to start timer before forcing scramble here
}

public Action:Timer_Autobalance(Handle:Timer)
{
	// Are we in a position to allow balancing?
	if (!ShouldAllowBalance())
	{
		return Plugin_Continue;
	}
	
	// We already determined teams were unbalanced and are waiting the delay period
	// This logic should probably move to its OWN timer, which is just checked to see if it needs canceling here.
	if (g_bWeAreBalancing)
	{
		BalanceTeams();
		return Plugin_Continue;
	}
	
	if (!AreTeamsBalanced())
	{
		// Teams are now unbalanced
	}
	
	return Plugin_Continue;
}

bool:ShouldAllowBalance()
{
	if (g_bWaitingForPlayers)
	{
		return false;
	}
	
	// Only run if round is running.  This has a side effect of not running during Sudden Death or Arena (which counts as Sudden Death)
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
			new Float:timeRemaining = GetEntPropFloat(timer, Prop_Send, "m_flTimerEndTime") - GetGameTime();
			if (RoundFloat(timeRemaining) < timelimit)
			{
				return false;
			}
		}
	}
	
	return true;	
}

bool:AreTeamsBalanced()
{
	new unbalanceLimit = GetConVarInt(g_Cvar_Mp_TeamsUnbalance);
	if (unbalanceLimit == 0)
	{
		return true;
	}

	new teamNum = GetTeamCount();
	new teamCounts[teamNum];
	GetTeamCounts(teamCounts, teamNum);
	
	// > 2 is so that we only process where i isn't the last team
	// Since 0 and 1 aren't player teams... unassigned and spectator...
	// For TF2, this will only loop once (for team 3)
	for (new team1 = teamNum - 1; team1 > 2 ; team1--)
	{
		// We need to compare all player teams (in case there are more than two)
		// For TF2 this will only loop once (for team 2)
		for (new team2 = team1 - 1; team2 >= 2; team2--)
		{
			new diff = 0;

			if (teamCounts[team1] > teamCounts[team2])
			{
				diff = teamCounts[team1] - teamCounts[team2];
			}
			else
			{
				diff = teamCounts[team2] - teamCounts[team1];
			}
			
			if (diff > unbalanceLimit)
			{
				return false;
			}
		}
	}
		
	return true;
}

GetTeamCounts(teamCounts[], teamNum)
{
	for (new i = 0; i < teamNum; i++)
	{
		teamCounts[i] = GetTeamClientCount(i);
	}	
}

public SortTeamCountsAsc(elem1[], elem2[], const array[][], Handle:hndl)
{
	if (elem1[Sorted_TeamCount] > elem2[Sorted_TeamCount])
	{
		return -1;
	}
	else if (elem1[Sorted_TeamCount] < elem2[Sorted_TeamCount])
	{
		return 1;
	}
	else
	{
		return 0;
	}
}

public SortTeamCountsDesc(elem1[], elem2[], const array[][], Handle:hndl)
{
	if (elem2[Sorted_TeamCount] > elem1[Sorted_TeamCount])
	{
		return -1;
	}
	else if (elem2[Sorted_TeamCount] < elem1[Sorted_TeamCount])
	{
		return 1;
	}
	else
	{
		return 0;
	}
}

public SortPlayerValuesAsc(elem1[], elem2[], const array[][], Handle:hndl)
{
	if (elem1[Player_Value] > elem2[Player_Value])
	{
		return -1;
	}
	else if (elem1[Player_Value] < elem2[Player_Value])
	{
		return 1;
	}
	else
	{
		return 0;
	}
}

public SortPlayerValuesDesc(elem1[], elem2[], const array[][], Handle:hndl)
{
	if (elem2[Player_Value] > elem1[Player_Value])
	{
		return -1;
	}
	else if (elem2[Player_Value] < elem1[Player_Value])
	{
		return 1;
	}
	else
	{
		return 0;
	}
}

// If we called this, teams were determined to be unbalanced already
BalanceTeams(bool:force = false)
{
	new teamNum = GetTeamCount();
	new teamCounts[teamNum];
	GetTeamCounts(teamCounts, teamNum);
	
	new realTeamNum = teamNum-2;
	new sortedTeamCounts[realTeamNum][2];
	
	for (new i = 2; i < teamNum; i++)
	{
		sortedTeamCounts[i-2][Sorted_TeamNum] = i;
		sortedTeamCounts[i-2][Sorted_TeamCount] = teamCounts[i];
	}
	
	SortCustom2D(sortedTeamCounts, realTeamNum, SortTeamCountsDesc);
	
	if (realTeamNum > 2)
	{
		// Hmm, more than two teams means trickier logic, we'll deal with it later.
	}
	else
	{
		new players[MaxClients+1][2];
		new count = GetPlayerBalanceValues(sortedTeamCounts[0][Sorted_TeamNum], players, force);
		new balanceCount = (sortedTeamCounts[0][Sorted_TeamCount] - sortedTeamCounts[1][Sorted_TeamCount]) / 2; // We switch half as many players
		
		if (count <= balanceCount)
		{
			// Balance everyone we have
			for (new i = 0; i < count; i++)
			{
				BalancePlayer(players[i][Player_Index], sortedTeamCounts[1][Sorted_TeamNum]);
			}
			
			if (count < balanceCount)
			{
				// We didn't have enough players, so we're still balancing
				g_bWeAreBalancing = true;
			}
			else
			{
				// We had exactly enough players
				g_bWeAreBalancing = false;
			}
		}
		else
		{
			// We have more players than we need, so this will stop the balancing
			g_bWeAreBalancing = false;
			SortCustom2D(players, count, SortPlayerValuesDesc);
			
			new last = 132412;
			new collector[count];
			new collate = 0;
			new curStart = 0;
			for (new i = 0; i < count; i++)
			{
				// Never process this block for the first item
				if (players[i][Player_Value] != last && i != 0)
				{
					// This is actually an optimization so that we don't attempt to randomize
					// when we are going to use all the values
					if (i <= balanceCount)
					{
						for (new j = 0; j < collate; j++)
						{
							BalancePlayer(collector[j], sortedTeamCounts[1][Sorted_TeamNum]);
							collector[j] = 0;
						}
						collate = 0;
						
						// Say, if we are on index 4 and we want 4 items, we need to break here
						// because 4 is the fifth index and collector will have 4 items already.
						// (or it could have had 2 and 2, or 1 and 3, etc...)
						if (i == balanceCount)
						{
							break;
						}
					}
					else
					{
						// Go Fish...er-Yates
						// 'cause we want a random ordering of items with the same value
						for (new j = collate - 1; j >= 1; j--)
						{
							new k = GetRandomInt(0, j);
							new temp = collector[j];
							collector[j] = collector[k];
							collector[k] = temp;
						}
						
						for (new j = 0; j < (i - 1 - curStart); j++)
						{
							BalancePlayer(collector[j], sortedTeamCounts[1][Sorted_TeamNum]);
							collector[j] = 0;
						}
						
						// Also, break since we have all the people we need
						break;
					}
					curStart = i;
				}
				collector[collate++] = players[i][Player_Index];
				last = players[i][Player_Value];
			}
		}
	}
}

BalancePlayer(client, team)
{
	SwitchTeam(client, team, true, false);
	g_LastBalanced[client] = GetTime();
	
	new Handle:event = CreateEvent("teamplay_teambalanced_player");
	if (event != INVALID_HANDLE)
	{
		SetEventInt(event, "player", client);
		SetEventInt(event, "team", team);
		FireEvent(event);
	}
	
	decl String:name[MAX_NAME_LENGTH+1];
	GetClientName(client, name, sizeof(name));
	
	PrintValveTranslationToAll(HUD_PRINTTALK, "#game_player_was_team_balanced", name);
}

/*
 * This idea is stolen from GScramble. Higher player value means more likely to be autobalanced.
 * Dead players with no time-based immunity should get the highest value
 * 
 * players should be MaxClients+1 size.  Failure to do so means you're an idiot.
 * Yes, I know mp_teams_unbalance_limit should prevent everyone being on one team. No, that isn't an excuse.
 * (Yes, I'm calling myself an idiot if I change this value later)
 */
GetPlayerBalanceValues(team, players[][], bool:force = false)
{
	new count = 0;

	// Calculate building owners first
	new Handle:buildingOwners = FindBuildingOwners();

	new teamMedicCount = 0;
	
	if (g_EngineVersion == Engine_TF2)
	{
		for (new client = 1; client <= MaxClients; client++)
		{
			if (IsClientInGame(client) && GetClientTeam(client) == team && TF2_GetPlayerClass(client) == TFClass_Medic)
			{
				teamMedicCount++;
			}
		}
	}
	
	for (new client = 1; client <= MaxClients; client++)
	{
		new immunityTime = GetConVarInt(g_Cvar_Immunity_Time);
		
		// Yes, this is meant to be ++, index is the OLD value
		// Dead players are always counted
		if (!IsPlayerAlive(client))
		{
			new index = count++;
			players[index][Player_Index] = client;

			if (g_EngineVersion == Engine_TF2 && GetConVarBool(g_Cvar_Immunity_Class) && TF2_GetPlayerClass(client) == TFClass_Engineer && FindValueInArray(buildingOwners, client) != -1)
			{
				if (!force)
				{
					// Don't balance dead engies with buildings if not forcing
					// Undo counter increment and index assignment
					count--;
					players[index][Player_Index] = 0;
					continue;
				}
				

				// Slightly more likely than living engies with level 2s to be balanced
				players[index][Player_Value] = -25;
			}
			else
			if (g_EngineVersion == Engine_TF2 && GetConVarBool(g_Cvar_Immunity_Class) && TF2_GetPlayerClass(client) == TFClass_Medic && teamMedicCount == 1)
			{
				// They're the only medic on their team, don't balance them unless you have to
				if (!force)
				{
					count--;
					players[index][Player_Index] = 0;
					continue;
				}
				players[index][Player_Value] = -50;
			}
			else
			if (GetConVarBool(g_Cvar_Immunity_Duel) && TF2_IsPlayerInDuel(client))
			{
				// Set their score lower if they're in a duel
				players[index][Player_Value] = -20;
			}
			else
			if (g_LastBalanced[client] - GetTime() > immunityTime)
			{
				// Dead players with no immunity get a very high value
				players[index][Player_Value] = 100;
			}
			// All other dead players
			else
			{
				// Dead players with immunity get a lower value than no immunity,
				// but still higher than living players
				players[index][Player_Value] = 50;
			}
		}
		else if (force)
		{
			// force chooses living players as well.

			new index = count++; 
			players[index][Player_Index] = client;

			if (g_LastBalanced[client] - GetTime() <= immunityTime)
			{
				// Living players in the immunity time get a fair bit of immunity
				players[index][Player_Value] = -20;
			}
			
			if (g_EngineVersion == Engine_TF2)
			{
				if (GetConVarBool(g_Cvar_Immunity_Class) && TF2_GetPlayerClass(client) == TFClass_Engineer && FindValueInArray(buildingOwners, client) != -1)
				{
					// Yes, this is higher than Medic as Medic Uber is transitory while buildings last even after death
					players[index][Player_Value] = -50;
				}
				else
				if (GetConVarBool(g_Cvar_Immunity_Class) && TF2_GetPlayerClass(client) == TFClass_Medic)
				{
					// This totally won't work for Randomizer.  Well, won't be useful at any rate.
					if (teamMedicCount == 1)
					{
						// Only Medic on team, this value is so low they should never be balanced
						players[index][Player_Value] = -100;
					}
					else
					// Medic is ubering, assign them a slightly lower value than they'd have if > 50% uber
					if (TF2_IsPlayerInCondition(client, TFCond_Ubercharged) ||
						TF2_IsPlayerInCondition(client, TFCond_UberchargeFading) ||
						TF2_IsPlayerInCondition(client, TFCond_Kritzkrieged) ||
						TF2_IsPlayerInCondition(client, TFCond_MegaHeal))
					{
						players[index][Player_Value] = -50;
					}
					else
					{
						new medigun = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);

						// Necessary for Medieval
						if (IsValidEntity(medigun))
						{
							new String:classname[64];
							GetEntityClassname(medigun, classname, sizeof(classname));
							if (StrEqual(classname, "tf_weapon_medigun") && GetEntProp(medigun, Prop_Send, "m_iItemDefinitionIndex") != VACCINATOR 
								&& GetEntPropFloat(medigun, Prop_Send, "m_flChargeLevel") > 0.50)
							{
								players[index][Player_Value] = -40;
							}
						}
					}
				}
				else
				// Player is being ubered, assigned them a lower value
				// Note how the Vaccinator uber isn't here?  That's intentional due to how quickly it builds.
				if (TF2_IsPlayerInCondition(client, TFCond_Ubercharged) ||
					TF2_IsPlayerInCondition(client, TFCond_UberchargeFading) ||
					TF2_IsPlayerInCondition(client, TFCond_Kritzkrieged) ||
					TF2_IsPlayerInCondition(client, TFCond_MegaHeal))
				{
					players[index][Player_Value] = -30;
				}
				else
				if (GetConVarBool(g_Cvar_Immunity_Duel) && TF2_IsPlayerInDuel(client))
				{
					// Set their score lower if they're in a duel, too
					players[index][Player_Value] = -20;
				}
			}
		}
	}
	
	CloseHandle(buildingOwners);
	
	return count;
}

Handle:FindBuildingOwners()
{
	new Handle:buildingOwners = CreateArray();
	new building = -1;
	while ((building = FindEntityByClassname(building, "obj_*")) != -1)
	{
		if (TF2_GetObjectType(building) == TFObject_Sapper)
		{
			continue;
		}
		
		new target = GetEntPropEnt(building, Prop_Send, "m_hOwnerEntity");
		if (target > 0 && target <= MaxClients && GetEntProp(building, Prop_Send, "m_iUpgradeLevel") >= 2)
		{
			// We don't care about duplicates
			PushArrayCell(buildingOwners, target);
		}
	}

	return buildingOwners;
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

// Get the amount of time left on a timer
// Adapted from Valve's SDK2013 CTeamRoundTimer::GetTimeRemaining
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
