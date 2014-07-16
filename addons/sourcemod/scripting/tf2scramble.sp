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
 *
 * Portions of this code were inspired by how Source SDK 2013/TF2 does things
 * Source SDK 2013 (c) 2013 Valve Software
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

#include "include/valve.inc"

#pragma semicolon 1

#define VERSION "0.0.1"

// Enable Debug functionality?
// Default: OFF (or it will be once we finish writing the plugin)
#define DEBUG

// Enable Extended Logging?
// Warning: This is very verbose, but will help debug problems
// Default: OFF (or it will be once we finish writing the plugin)
#define LOG

// #define SUPPORT_SDK2013

#define VACCINATOR 998

// Valve Define.  Not sure if it's correct, but eh.
#define HUD_ALERT_SCRAMBLE_TEAMS 0

#define PLAYER_TEAM_1 2
#define PLAYER_TEAM_2 3

new EngineVersion:g_EngineVersion;

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
new Handle:g_Cvar_Scramble_Delay;
new Handle:g_Cvar_Scramble_Round;
new Handle:g_Cvar_Vote_Percent;
new Handle:g_Cvar_Vote_Public;
new Handle:g_Cvar_Vote_Time;
new Handle:g_Cvar_Vote_Change;

// Valve CVars
new Handle:g_Cvar_Mp_Autobalance; // mp_autobalance
new Handle:g_Cvar_Mp_Scrambleteams_Auto; // mp_scrambleteams_auto
new Handle:g_Cvar_Sv_Vote_Scramble; // sv_vote_issue_scramble_teams_allowed
new Handle:g_Cvar_Mp_BonusRoundTime; // mp_bonusroundtime
new Handle:g_Cvar_Mp_TeamsUnbalance; // mp_teams_unbalance_limit
new RoundEndType:g_RoundEndType = RoundEnd_Immediate;
new g_Tcpm = INVALID_ENT_REFERENCE;

// Optional extensions/plugins
new bool:g_bUseNativeVotes = false;
new bool:g_bNativeVotesRegisteredMenus = false;

// We need to track this globally since we shut off on MvM and Arena.
new bool:g_Enabled;

#include "tf2scramble/balance.sp"
#include "tf2scramble/scramble.sp"

public Plugin:myinfo = {
	name			= "TF2 Scramble",
	author			= "Powerlord",
	description		= "Alternative to TF2's Scramble system and GScramble",
	version			= VERSION,
	url				= ""
};

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
	RegPluginLibrary("tf2scramble");
	
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
	g_Cvar_Immunity_Class = CreateConVar("tf2scramble_balance_class_immunity", "1", "Should Medics with 50%+ Uber or Engineers with Level 2+ Buildings be immune to autobalance? Note: Only applies to autobalancing and if we run out of other players, they WILL be balanced.", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_Cvar_Immunity_Duel = CreateConVar("tf2scramble_balance_duel_immunity", "1", "Should dueling players be immune to autobalance? Note: Only applies to autobalancing and if we run out of other players, they WILL be balanced. Scored lower than Engy/Medic", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_Cvar_Immunity_Time = CreateConVar("tf2scramble_balance_time_immunity", "180", "Players will be immune from balancing a second time for this many seconds.  Ignored if all players are marked as immune. Set to 0 to disable.", FCVAR_PLUGIN, true, 0.0, true, 300.0);
	g_Cvar_Timeleft = CreateConVar("tf2scramble_timeleft", "60", "If there is less than this much or less sectonds left on a timer, stop balancing. Ignored on Arena and KOTH. Set to 0 to disable.", FCVAR_PLUGIN, true, 0.0, true, 180.0);
	g_Cvar_Autobalance_Time = CreateConVar("tf2scramble_autobalance_time", "5", "Seconds before autobalance should occur once detected... only for dead players.", FCVAR_PLUGIN, true, 5.0, true, 30.0);
	g_Cvar_Autobalance_ForceTime = CreateConVar("tf2scramble_autobalance_forcetime", "15", "Seconds before autobalance should be forced if no one on a team dies.", FCVAR_PLUGIN, true, 5.0, true, 30.0);
	g_Cvar_Scramble_Percent = CreateConVar("tf2scramble_scramble_percent", "0.50", "What percentage of players should be scrambled?", FCVAR_PLUGIN, true, 0.10, true, 0.90);
	g_Cvar_NativeVotes = CreateConVar("tf2scramble_nativevotes", "1", "Use NativeVotes for votes if available? (Why would you ever disable this?)", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_Cvar_NativeVotes_Menu = CreateConVar("tf2scramble_nativevotes_menu", "1", "Put ScrambleTeams vote in NativeVotes menu?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_Cvar_Scramble_Delay = CreateConVar("tf2scramble_scramble_delay", "300", "How long in seconds after a scramble happens or scramble vote fails should we prevent a scramble vote?", FCVAR_PLUGIN, true, 1.0);
	g_Cvar_Scramble_Round = CreateConVar("tf2scramble_scramble_round", "1", "After a successful scramble vote, require a round change before another scramble vote can happen? 1 = yes, 0 = no", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	g_Cvar_Vote_Percent = CreateConVar("tf2scramble_vote_percent", "0.50", "What percent of people need to vote Yes for scramble vote to pass?", FCVAR_PLUGIN, true, 0.10, true, 1.0);
	g_Cvar_Vote_Public = CreateConVar("tf2scramble_vote_public", "0.30", "What percent of people need to use the votescramble command before a vote starts?", FCVAR_PLUGIN, true, 0.10, true, 1.0);
	g_Cvar_Vote_Time = CreateConVar("tf2scramble_vote_time", "20", "How long should a scramble vote last in seconds?", FCVAR_PLUGIN, true, 5.0, true, 30.0);
	g_Cvar_Vote_Change = CreateConVar("tf2scramble_vote_change", "0", "When should a scramble vote take effect?  0 = Immediate, 1 = At round change?", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	
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
	
	// Commands
#if defined DEBUG
	RegAdminCmd("listimmunity", Cmd_ListImmunity, ADMFLAG_GENERIC, "List immunity values for all players as if \"force\" was on.");
#endif
}

public OnMapStart()
{
	DHookGamerules(g_Hook_HandleScramble, false);
	PrecacheScrambleSounds();
}

public OnMapEnd()
{
	StopScrambleTimer();
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
			// Why are we trying to unregister this when NativeVotes went away?
			//NativeVotes_UnregisterVoteCommand("ScrambleTeams", NativeVotes_Menu);
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
	if (!IsFakeClient(client) && client != 0)
	{
		new ReplySource:old = SetCmdReplySource(SM_REPLY_TO_CHAT);

		InlineScrambleVote(client, true);

		SetCmdReplySource(old);
	}
	
	return Plugin_Handled;
}

public Action:OnClientSayCommand(client, const String:command[], const String:sArgs[])
{
	if (StrEqual(command, "votescramble", false))
	{
		InlineScrambleVote(client, false);
		return Plugin_Handled;
	}
	
	return Plugin_Continue;
}

public OnClientConnected(client)
{
	ClearLastBalancedTime(client);
	SetPlayerConnectTime(client);
}

public OnClientDisconnected(client)
{
	// We don't really need to reset it on both connect AND disconnect, but eh...
	ClearLastBalancedTime(client);
	ClearPlayerConnectTime(client);
	SetScrambleVote(client, false);
	CheckVotes();
}

public TF2_OnWaitingForPlayersStart()
{
	g_bWaitingForPlayers = true;
}

public TF2_OnWaitingForPlayersEnd()
{
	g_bWaitingForPlayers = false;
}

public Event_Round_Start(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!g_Enabled)
	{
		return;
	}
	
	CreateAutobalanceTimer();

	SetScrambledThisRound(false);
}

public Event_Round_End(Handle:event, const String:name[], bool:dontBroadcast)
{
	if (!g_Enabled)
	{
		return;
	}
	
	RemoveAutobalanceTimer();
	
	PostRoundScrambleCheck();
	StopScrambleTimer();
}

// If you're using this, one or both of the last two args should be true,
// or else you should just use ChangeClientTeam
//void CBasePlayer::ChangeTeam( int iTeamNum, bool bAutoTeam, bool bSilent )
stock SwitchTeam(client, iTeamNum, bool:bAutoTeam, bool:bSilent)
{
	SDKCall(g_Call_ChangeTeam, client, iTeamNum, bAutoTeam, bSilent);
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

// Go Fish...er-Yates
// 'cause we want a random ordering of items with the same value
ShuffleArray(array[], count)
{
	for (new i = count - 1; i >= 1; i--)
	{
		new j = GetRandomInt(0, i);
		new temp = array[i];
		array[i] = array[j];
		array[j] = temp;
	}
	
}