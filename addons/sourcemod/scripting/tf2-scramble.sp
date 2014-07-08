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

#undef REQUIRE_PLUGIN
#include <nativevotes>
#include <gameme>
#include <hlxce-sm-api>

#pragma semicolon 1
#define VERSION "0.0.1"

// #define SUPPORT_SDK2013

//SDKCalls / Hooks
new Handle:g_Call_ChangeTeam;
new Handle:g_Call_SetScramble;
new Handle:g_Hook_HandleScramble;

// CVars
new Handle:g_Cvar_Enabled;
new Handle:g_Cvar_Scramble;
new Handle:g_Cvar_Balance;

// Valve CVars
new Handle:g_Cvar_Mp_Autobalance; // mp_autobalance
new Handle:g_Cvar_Mp_Scrambleteams_Auto; // mp_scrambleteams_auto
new Handle:g_Cvar_Sv_Vote_Scramble; // sv_vote_issue_scramble_teams_allowed

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
	new EngineVersion:engine = GetEngineVersion();
	
	if (engine != Engine_TF2)
	{
#if defined SUPPORT_SDK2013
		if (engine != Engine_SDK2013)
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
	CreateConVar("tf2_scramble_version", VERSION, "TF2 Scramble version", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY);
	g_Cvar_Enabled = CreateConVar("tf2_scramble_enable", "1", "Enable TF2 Scramble?", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_DONTRECORD, true, 0.0, true, 1.0);
	g_Cvar_Scramble = CreateConVar("tf2_scramble_scramble", "1", "Enable TF2 Scramble's scramble abilities?", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_Cvar_Balance = CreateConVar("tf2_scramble_balance", "1", "Enable TF2 Scramble's balance abilities?", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0);
	
	// Add more cvars
	
	LoadTranslations("tf2-scramble.phrases");
	LoadTranslations("common.phrases");
	
	new Handle:gamedata = LoadGameConfigFile("tf2-scramble");
	
	if (gamedata == INVALID_HANDLE)
	{
		SetFailState("Could not load gamedata");
	}
	
	//void CTFPlayer::ChangeTeam(int team, bool bAutoBalance, bool bSilent)
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(gamedata, SDKConf_Virtual, "CTFPlayer::ChangeTeam3Arg");
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

// void CTeamplayRules::HandleScrambleTeams( void )
public MRESReturn:HandleScrambleTeams(Handle:hParams)
{
	if (!GetConVarBool(g_Cvar_Enabled) || !GetConVarBool(g_Cvar_Scramble))
	{
		return MRES_Ignored;
	}
	
	// scramble logic goes here
	
	// As far as I can tell, both these args should be true during a scramble
	// ChangeTeam(client, team, true, true); 
	return MRES_Supercede;
}

// If you're using this, one or both of the last two args should be true,
// or else you should just use ChangeClientTeam
stock SwitchTeam(client, team, bool:bAutoBalance, bool:bSilent)
{
	SDKCall(g_Call_ChangeTeam, client, team, bAutoBalance, bSilent);
}

stock SetScrambleTeams(bool:bScrambleTeams)
{
	SDKCall(g_Call_SetScramble, bScrambleTeams);
}
