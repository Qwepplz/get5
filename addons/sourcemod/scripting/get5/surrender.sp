void SurrenderMap(Get5Team team) {
  Get5Side side = view_as<Get5Side>(Get5TeamToCSTeam(team));
  CS_TerminateRound(FindConVar("mp_round_restart_delay").FloatValue,
                    side == Get5Side_CT ? CSRoundEnd_CTSurrender : CSRoundEnd_TerroristsSurrender);
}

void EndSurrenderTimers() {
  g_PendingSurrenderTeam = Get5Team_None;
  LOOP_CLIENTS(i) {
    g_SurrenderedPlayers[i] = false;
  }
  LOOP_TEAMS(team) {
    g_SurrenderVotes[team] = 0;
    g_SurrenderFailedAt[team] = 0.0;
    if (g_SurrenderTimers[team] != INVALID_HANDLE) {
      delete g_SurrenderTimers[team];
    }
  }
}
