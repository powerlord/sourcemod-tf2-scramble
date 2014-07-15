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

new String:g_ScrambleSounds[][] = { "vo/announcer_AM_TeamScramble01.wav", "vo/announcer_AM_TeamScramble02.wav", "vo/announcer_AM_TeamScramble03.wav" };
#define SCRAMBLE_CHANNEL SNDCHAN_VOICE2
#define SCRAMBLE_VOLUME SNDVOL_NORMAL
#define SCRAMBLE_LEVEL SNDLEVEL_NORMAL
#define SCRAMBLE_PITCH SNDPITCH_NORMAL

enum ScrambleType
{
	Scramble_Random,
	Scramble_Points,
	Scramble_PointsPerMin,
	Scramble_KillDeathRatio,
	Scramble_Plugin
}

enum ScrambleResponse
{
	ScrambleResponse_Waiting,
	ScrambleResponse_Time,
	ScrambleResponse_Round,
	ScrambleResponse_Failed,
	ScrambleResponse_AlreadyVoted,
	ScrambleResponse_Pending,
	ScrambleResponse_Disabled,
	
}

enum ScrambleVoteTime
{
	ScrambleVote_Immediate,
	ScrambleVote_Round
}

new g_PlayerConnectTime[MAXPLAYERS+1];

new bool:g_bScrambleVotes[MAXPLAYERS+1]; // This is for in-line scramble votes
new g_LastScrambleTime = 0;
new bool:g_bScrambledThisRound = false;
new bool:g_bScramblePending = false;

stock SetPlayerConnectTime(client)
{
	g_PlayerConnectTime[client] = GetTime();
}
 
stock ClearPlayerConnectTime(client)
{
	g_PlayerConnectTime[client] = 0;
}
 
stock GetPlayerConnectTime(client)
{
	return g_PlayerConnectTime[client];
}

stock SetScrambledThisRound(bool:scrambled)
{
	g_bScrambledThisRound = scrambled;
}

stock bool:GetScrambledThisRound()
{
	return g_bScrambledThisRound;
}

stock SetLastScrambleTime()
{
	g_LastScrambleTime = GetTime();
}

stock GetLastScrambleTime()
{
	return g_LastScrambleTime;
}

stock GetScramblePending()
{
	return g_bScramblePending;
}

stock SetScrambleVote(client, bool:vote)
{
	g_bScrambleVotes[client] = vote;
}

stock GetScrambleVote(client)
{
	return g_bScrambleVotes[client];
}

bool:InlineScrambleVote(client, bool:bNativeVotes)
{
	if (!GetConVarBool(g_Cvar_Enabled))
	{
		return false;
	}
	
	if (g_bWaitingForPlayers)
	{
		if (bNativeVotes)
		{
			NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_Waiting);
		}
		
		ReplyToCommand(client, "%t", "CallVote_WaitingForPlayers");
		return false;
	}

	if ((g_bUseNativeVotes && NativeVotes_IsVoteInProgress()) || (!g_bUseNativeVotes && IsVoteInProgress()))
	{
		// No Nativevotes panel here as it'd hide the vote panel if showing
		ReplyToCommand(client, "%t", "Vote in Progress");
		return false;
	}
	
	if (!GetConVarBool(g_Cvar_Scramble) || !GetConVarBool(g_Cvar_VoteScramble))
	{
		if (bNativeVotes)
		{
			NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_Disabled);
		}
		ReplyToCommand(client, "%t", "ScrambleVote_Disabled");
		return false;
	}
	
	if (GetScramblePending())
	{
		if (bNativeVotes)
		{
			NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_ScramblePending);
		}
		ReplyToCommand(client, "%t", "CallVote_Pending");
		return false;
	}
	
	if (GetScrambledThisRound())
	{
		if (bNativeVotes)
		{
			NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_Disabled);
		}
		ReplyToCommand(client, "%t", "CallVote_DisabledRound");
		return false;
	}
	
	new remaining = GetLastScrambleTime() + GetConVarInt(g_Cvar_Scramble_Delay) - GetTime();
	if (remaining > 0)
	{
		if (bNativeVotes)
		{
			NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_Failed, remaining);
		}
		ReplyToCommand(client, "%t", "CallVote_DisabledTime");
		return false;
	}
	
	if (g_bScrambleVotes[client] == true)
	{
		if (bNativeVotes)
		{
			NativeVotes_DisplayCallVoteFail(client, NativeVotesCallFail_Generic);
		}
		ReplyToCommand(client, "%t", "CallVote_Already");
		return false;
	}
	
	g_bScrambleVotes[client] = true;
	
	CheckVotes();
	
	return true;
}

CheckVotes()
{
	new count = 0;
	new votes = 0;
	
	new Float:percent = GetConVarFloat(g_Cvar_Vote_Public);
	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientConnected(client))
		{
			count++;
			if (g_bScrambleVotes[client])
			{
				votes++;
			}
		}
	}

	if (count == 0)
	{
		return false;
	}
	
	new Float:total = float(votes) / float(count);
	// Subtract 0.01 for float rounding stuffs
	if (total >= (percent - 0.01))
	{
		new ScrambleVoteTime:when = ScrambleVoteTime:GetConVarInt(g_Cvar_Vote_Change);
		new Handle:vote;
		if (g_bUseNativeVotes)
		{
			new NativeVotesType:voteType;
			switch (when)
			{
				case ScrambleVote_Immediate:
				{
					voteType = NativeVotesType_ScrambleNow;
				}
				
				case ScrambleVote_Round:
				{
					voteType = NativeVotesType_ScrambleEnd;
				}
			}
			
			vote = NativeVotes_Create(Handler_NativeScrambleMenu, voteType, NATIVEVOTES_ACTIONS_DEFAULT);
			NativeVotes_SetResultCallback(vote, Handler_NativeScrambleVote);
			NativeVotes_DisplayToAll(vote, GetConVarInt(g_Cvar_Vote_Time));
		}
		else
		{
			vote = CreateMenu(Handler_ScrambleMenu, MENU_ACTIONS_DEFAULT|MenuAction_Display|MenuAction_DisplayItem);
			SetVoteResultCallback(vote, Handler_ScrambleVote);
			AddMenuItem(vote, "#yes", "Yes");
			AddMenuItem(vote, "#no", "No");
			switch (when)
			{
				case ScrambleVote_Immediate:
				{
					SetMenuTitle(vote, "Scramble_Immediate");
				}
				
				case ScrambleVote_Round:
				{
					SetMenuTitle(vote, "Scramble_Round");
				}
			}
			VoteMenuToAll(vote, GetConVarInt(g_Cvar_Vote_Time));
		}
	}
}

public Handler_NativeScrambleMenu(Handle:vote, MenuAction:action, param1, param2)
{
}

public Handler_NativeScrambleVote(Handle:vote,
							num_votes, 
							num_clients,
							const client_indexes[],
							const client_votes[],
							num_items,
							const item_indexes[],
							const item_votes[])
{
	new bool:yesWon = false;
	if (item_indexes[0] == NATIVEVOTES_VOTE_YES)
	{
		new Float:minimum = GetConVarFloat(g_Cvar_Vote_Percent);
		
	}
	
	if (yesWon)
	{
		NativeVotes_DisplayPass(vote);
	}
	else
	{
		NativeVotes_DisplayFail(vote, NativeVotesFail_Loses);
	}
}

public Handler_ScrambleMenu(Handle:vote, MenuAction:action, param1, param2)
{
	
}

public Handler_ScrambleVote(Handle:vote,
							num_votes, 
							num_clients,
							const client_info[][2], 
							num_items,
							const item_info[][2])
{
	new bool:yesWon = false;
	
	decl String:winner[5];
	GetMenuItem(vote, item_info[0][VOTEINFO_ITEM_VOTES], winner, sizeof(winner));
	
	if (StrEqual(winner, "#yes"))
	{
		new Float:minimum = GetConVarFloat(g_Cvar_Vote_Percent);
		
	}
	
	if (yesWon)
	{
	}
	else
	{
	}
}

PostRoundScrambleCheck()
{
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

//void CTeamplayRules::SetScrambleTeams( bool bScramble )
stock SetScrambleTeams(bool:bScramble)
{
	g_bScramblePending = true;
	SDKCall(g_Call_SetScramble, bScramble);
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
	if (!GetConVarBool(g_Cvar_Scramble))
	{
		return false;
	}
	
	// Logic to determine if we should scramble here
	return false;
}

stock ForceScramble()
{
	SetLastScrambleTime();
	SetScrambledThisRound(true);
	
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

// void CTeamplayRules::HandleScrambleTeams( void )
public MRESReturn:HandleScrambleTeams(Handle:hParams)
{
	if (!GetConVarBool(g_Cvar_Enabled) || !GetConVarBool(g_Cvar_Scramble))
	{
		return MRES_Ignored;
	}
	
	new switched = 0;

	SetLastScrambleTime();
	
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
	
	if (realTeamNum == 2)
	{
		new totalPlayers = teamCounts[2] + teamCounts[3];
		new playersToMove = RoundFloat(totalPlayers * GetConVarFloat(g_Cvar_Scramble_Percent));
		// If may seem odd getting the balance count, but this is how many players we MUST move to one team in addition to moving equal(ish) numbers from both teams.
		new balanceCount = (sortedTeamCounts[0][Sorted_TeamCount] - sortedTeamCounts[1][Sorted_TeamCount]) / 2;
		
		new bool:oddPlayerCount = (totalPlayers % 2 != 0);
		
		if (playersToMove >= balanceCount)
		{
			// Since we're already moving the balanced players, we need to move that many LESS players afterwards
			playersToMove -= balanceCount;
		}
		
		switch (GetConVarInt(g_Cvar_ScrambleMode))
		{
			case Scramble_Random:
			{
				switched = ScrambleByRandom(playersToMove, balanceCount, sortedTeamCounts[0][Sorted_TeamNum], sortedTeamCounts[1][Sorted_TeamNum], oddPlayerCount);
			}
			
			case Scramble_Points:
			{
				switched = ScrambleByPoints(playersToMove, balanceCount, sortedTeamCounts[0][Sorted_TeamNum], sortedTeamCounts[1][Sorted_TeamNum], oddPlayerCount);
			}
			
			case Scramble_PointsPerMin:
			{
				switched = ScrambleByPointsPerMinute(playersToMove, balanceCount, sortedTeamCounts[0][Sorted_TeamNum], sortedTeamCounts[1][Sorted_TeamNum], oddPlayerCount);
			}
			
			case Scramble_KillDeathRatio:
			{
				switched = ScrambleByKDR(playersToMove, balanceCount, sortedTeamCounts[0][Sorted_TeamNum], sortedTeamCounts[1][Sorted_TeamNum], oddPlayerCount);
			}
			
			case Scramble_Plugin:
			{
				switched = ScrambleByPlugin(playersToMove, balanceCount, sortedTeamCounts[0][Sorted_TeamNum], sortedTeamCounts[1][Sorted_TeamNum], oddPlayerCount);
			}
		}
	}
	else
	{
		// Worry about more teams later
	}

	

	// As far as I can tell, the last arg should be true during a balance/scramble
	// SwitchTeam(client, iTeamNum, false, true);
	return MRES_Supercede;
}

ScrambleByRandom(playersToMove, playersToBalance, teamToBalanceFrom, teamToBalanceTo, bool:oddPlayerCount)
{
	new switched = 0;
	new teamPlayers[2][MaxClients];
	new teamCounts[2];
	
	for (new i = 0; i < sizeof(teamPlayers); i++)
	{
		teamCounts[i] = GetPlayers(i+2, teamPlayers[i]);
		ShuffleArray(teamPlayers[i], teamCounts[i]);
	}
	
	new teamMoved[2] = { 0, ... };
	
	for (new i = 0; i < playersToBalance; i++)
	{
		SwitchTeam(teamPlayers[teamToBalanceFrom][i], teamToBalanceTo, false, true);
		switched++;
	}
	
	teamMoved[teamToBalanceFrom] = playersToBalance;
	
	new playerEachToMove = playersToMove / 2;
	
	for (new i = 0; i < sizeof(teamPlayers); i++)
	{
		new team = i + 2;
		new otherteam = team == 2 ? 3 : 2;

		for (new j = 0; j < playerEachToMove; j++)
		{
			// We don't need the value of j, it's just to loop the correct number of times
			SwitchTeam(teamPlayers[team][teamMoved[team]++], otherteam, false, true);
			switched++;
		}
	}
	
	// balanceCount was an odd number, so teams were uneven after balancing
	if (switched < playersToMove && oddPlayerCount)
	{
		SwitchTeam(teamPlayers[teamToBalanceFrom][teamMoved[teamToBalanceFrom]++], teamToBalanceTo, false, true);
		switched++;
	}
	
	return switched;
}

ScrambleByPoints(playersToMove, playersToBalance, teamToBalanceFrom, teamToBalanceTo, bool:oddPlayerCount)
{
	new switched;
	
	return switched;
}

ScrambleByPointsPerMinute(playersToMove, playersToBalance, teamToBalanceFrom, teamToBalanceTo, bool:oddPlayerCount)
{
	new switched;

	return switched;
}

ScrambleByKDR(playersToMove, playersToBalance, teamToBalanceFrom, teamToBalanceTo, bool:oddPlayerCount)
{
	new switched;
	
	return switched;
}

ScrambleByPlugin(playersToMove, playersToBalance, teamToBalanceFrom, teamToBalanceTo, bool:oddPlayerCount)
{
	new switched;
	
	return switched;
}

GetPlayers(team, players[])
{
	new count = 0;
	
	for (new client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client) && GetClientTeam(client) == team)
		{
			players[count++] = client;
		}
	}
	
	return count;
}

GetPlayerPoints(points[], const players[], count)
{
	for (new i = 0; i < count; i++)
	{
		points[i] = GetEntProp(i, Prop_Send, "m_iScore");
	}
}

GetPlayerKDR(Float:kdr[], const players[], count)
{
	for (new i = 0; i < count; i++)
	{
		new kills = GetEntProp(i, Prop_Send, "");
		// Avoid divide by 0 by adding 1
		// This works because suicides subtract 1 from kills, not deaths
		new deaths = GetEntProp(i, Prop_Send, "") + 1;
				
		kdr[i] = float(kills) / float(deaths);
	}
}

PrecacheScrambleSounds()
{
#if SOURCEMOD_V_MAJOR > 1 || (SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR >= 7)
	PrecacheScriptScound("Announcer.AM_TeamScrambleRandom");
#else
	for (new i = 0; i < sizeof(g_ScrambleSounds); i++)
	{
		PrecacheSound(g_ScrambleSounds[i]);
	}
#endif
}

PlayScrambleSound()
{
#if SOURCEMOD_V_MAJOR > 1 || (SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR >= 7)
	EmitGameSoundToAll("Announcer.AM_TeamScrambleRandom");
#else		
	new random = GetRandomInt(0, sizeof(g_ScrambleSounds) - 1);
	EmitSoundToAll(g_ScrambleSounds[random], SOUND_FROM_PLAYER, SCRAMBLE_CHANNEL, SCRAMBLE_LEVEL, SND_NOFLAGS, SCRAMBLE_VOLUME, SCRAMBLE_PITCH);
#endif
}