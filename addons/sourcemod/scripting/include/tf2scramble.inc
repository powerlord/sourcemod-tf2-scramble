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
#if defined _tf2scramble_included_
  #endinput
#endif
#define _tf2scramble_included_

// Plugin 0.1 series

/**
 * Fisher-Yates shuffle an array
 * 
 * This is commonly used in the plugin itself to shuffle players with identical scores
 * 
 * @param array		A 1D array whose elements should be randomly shuffled in place
 * @param count		The number of elements in said array
 * 
 * @noreturn
 */
stock ShuffleArray(array[], count)
{
	for (new i = count - 1; i >= 1; i--)
	{
		new j = GetRandomInt(0, i);
		new temp = array[i];
		array[i] = array[j];
		array[j] = temp;
	}
}

/**
 * Scramble plugins should implement this function.  Note, it will only be called if tf2scramble_mode is set to 4
 * 
 * @param playersToMove		The number of players that should be scrambled.
 * @param playersToBalance		This number of players need to be balanced from the larger team first before scrambling the remaining number
 * 							Ideally this number will be 0.
 * @param teamToBalanceFrom		The larger team, used with playersToBalance
 * @param teamsToBalanceTo		The smaller team, used with playersToBalance
 * @param oddPlayerCount		True if the teams are uneven, determines if one last player should be moved.
 * @param switched			Number of players switched
 * @return					Number of players scrambled
 */
forward TF2Scramble_ScramblePlugin(playersToMove, playersToBalance, teamToBalanceFrom, teamToBalanceTo, bool:oddPlayerCount, &switched);

/**
 * Get a player's balance score 
 * 
 * @param client	Client whose balance score you want
 * 
 * @return		Player score
 */
native TF2Scramble_GetPlayerBalanceScore(client);

/**
 * Get a team's player balance scores
 * 
 * @param team	Team whose scores you want
 * @param scores	An array of size MaxClients to store the scores
 * 
 * @return		Number of players
 */
native TF2Scramble_GetTeamPlayerBalanceScores(team, scores[]);

public SharedPlugin:__pl_tf2scramble = 
{
	name = "tf2scramble",
	file = "tf2scramble.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_tf2scramble_SetNTVOptional()
{
	MarkNativeAsOptional("FunctionWithArg");
	MarkNativeAsOptional("FunctionWithoutArg");
	MarkNativeAsOptional("RegisterCallback");
	MarkNativeAsOptional("UnregisterCallback");
}
#endif
