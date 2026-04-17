#include <string>

#define REMOTE_CONFIG_PATTERN               "remote_config%s.json"
#define CONFIG_MATCHID_DEFAULT              ""  // empty string if no match ID defined in config.
#define CONFIG_MATCHTITLE_DEFAULT           "Map {MAPNUMBER} of {MAXMAPS}"
#define CONFIG_PLAYERSPERTEAM_DEFAULT       5
#define CONFIG_PLAYERSPERTEAM_DEFAULT_WM    2
#define CONFIG_COACHESPERTEAM_DEFAULT       2
#define CONFIG_MINPLAYERSTOREADY_DEFAULT    0
#define CONFIG_MINSPECTATORSTOREADY_DEFAULT 0
#define CONFIG_SPECTATORSNAME_DEFAULT       "casters"
#define CONFIG_NUM_MAPSDEFAULT              1
#define CONFIG_SKIPVETO_DEFAULT             false
#define CONFIG_COACHES_MUST_READY_DEFAULT   false
#define CONFIG_CLINCH_SERIES_DEFAULT        true
#define CONFIG_WINGMAN_DEFAULT              false
#define CONFIG_SCRIM_DEFAULT                false
#define CONFIG_VETOFIRST_DEFAULT            "team1"
#define CONFIG_SIDETYPE_DEFAULT             "standard"

bool LoadMatchConfig(const char[] config, char[] error, bool restoreBackup = false) {
  if (g_GameState != Get5State_None && !restoreBackup) {
    Format(error, PLATFORM_MAX_PATH,
           "已有比赛加载时不能再加载新的比赛配置。(Cannot load a match configuration when a match is already loaded.)");
    return false;
  }

  EndSurrenderTimers();
  ResetForfeitTimer();
  ResetMatchConfigVariables(restoreBackup);
  ResetReadyStatus();

  // If a new match is loaded while there is still a pending cvar restore timer running, we
  // want to make sure that that timer's callback does *not* fire and mess up our game state.
  if (g_ResetCvarsTimer != INVALID_HANDLE) {
    LogDebug("Killing g_ResetCvarsTimer as a new match was loaded.");
    delete g_ResetCvarsTimer;
  }

  g_CvarNames.Clear();
  g_CvarValues.Clear();

  g_LastGet5BackupCvar.SetString("");

  CloseCvarStorage(g_KnifeChangedCvars);
  CloseCvarStorage(g_MatchConfigChangedCvars);


  if (!LoadMatchFile(config, error, restoreBackup)) {
    return false;
  }

  if (g_ActiveSetupMenu != null) {
    LogDebug("Terminating open setup menu as match was loaded.");
    g_ActiveSetupMenu.Cancel();
    g_ActiveSetupMenu = null;
  }

  if (g_NumberOfMapsInSeries > g_MapPoolList.Length) {
    FormatEx(error, PLATFORM_MAX_PATH,
             "地图列表只有 %d 张地图，无法进行 %d 图系列赛。(Cannot play a series of %d maps with a maplist of only %d maps.)",
             g_MapPoolList.Length, g_NumberOfMapsInSeries, g_NumberOfMapsInSeries, g_MapPoolList.Length);
    return false;
  }

  // Copy all the maps into the veto pool.
  bool usesWorkShopMap = false;
  char mapName[PLATFORM_MAX_PATH];
  for (int i = 0; i < g_MapPoolList.Length; i++) {
    g_MapPoolList.GetString(i, mapName, sizeof(mapName));
    // IsMapValid returns true for workshop map *that the server already has*, so we can't rely on that alone
    // to determine if a map is workshop.
    bool workshop = IsMapWorkshop(mapName);
    if (!usesWorkShopMap && workshop) {
      usesWorkShopMap = true;
    }
    if (!workshop && !IsMapValid(mapName)) {
      FormatEx(error, PLATFORM_MAX_PATH, "地图列表包含无效地图 '%s'。(Maplist contains invalid map '%s'.)",
               mapName, mapName);
      return false;
    }
    g_MapsLeftInVetoPool.PushString(mapName);
    g_TeamScoresPerMap.Push(0);
    g_TeamScoresPerMap.Set(g_TeamScoresPerMap.Length - 1, 0, 0);
    g_TeamScoresPerMap.Set(g_TeamScoresPerMap.Length - 1, 0, 1);
  }

  if (usesWorkShopMap && !FindCommandLineParam("-authkey")) {
    FormatEx(error, PLATFORM_MAX_PATH,
             "地图列表包含创意工坊地图，但服务器未提供 Steam Web API Key。(Maplist contains a Workshop map, but no Steam Web API Key was provided to the server.)");
    return false;
  }

  if (!restoreBackup) {
    if (g_SkipVeto) {
      // Copy the first k maps from the maplist to the final match maps.
      for (int i = 0; i < g_NumberOfMapsInSeries; i++) {
        g_MapPoolList.GetString(i, mapName, sizeof(mapName));
        g_MapsToPlay.PushString(mapName);

        // Push a map side if one hasn't been set yet.
        if (g_MapSides.Length < g_MapsToPlay.Length) {
          if (g_MatchSideType == MatchSideType_Standard || g_MatchSideType == MatchSideType_AlwaysKnife) {
            g_MapSides.Push(SideChoice_KnifeRound);
          } else if (g_MatchSideType == MatchSideType_Random) {
            g_MapSides.Push(GetRandomInt(0, 1) == 0 ? SideChoice_Team1CT : SideChoice_Team1T);
          } else {
            g_MapSides.Push(SideChoice_Team1CT);
          }
        }
      }
      ChangeState(Get5State_Warmup);
    } else {
      ChangeState(Get5State_PreVeto);
    }
  } else if (g_GameState == Get5State_None) {
    // Make sure here that we don't run the code below in game state none, but also not overriding
    // PreVeto. Currently, this could happen if you restored a backup with skip_veto:false.
    ChangeState(Get5State_Warmup);
  }

  // Before we run the Get5_OnSeriesInit forward, we want to ensure that as much game state is set
  // as possible, so that any implementation reacting to that event/forward will have all the
  // natives return proper data. ExecuteMatchConfigCvars gets called twice because
  // ExecCfg(g_WarmupCfgCvar) also does it async, but we need it here as the team assigment below
  // depends on it. We set this one first as the others may depend on something changed in the match
  // cvars section.
  ExecuteMatchConfigCvars();
  SetStartingTeams();  // must go before SetMatchTeamCvars as it depends on correct starting teams!
  SetMatchTeamCvars();
  LoadPlayerNames();
  UpdateHostname();

  // Set mp_backup_round_file to prevent backup file collisions
  char serverId[SERVER_ID_LENGTH];
  g_ServerIdCvar.GetString(serverId, sizeof(serverId));
  ServerCommand("mp_backup_round_file backup_%s", serverId);

  if (!restoreBackup) {
    StopRecording();  // Ensure no recording is running when starting a match, as that prevents Get5 from starting one.
    ExecCfg(g_WarmupCfgCvar);
    StartWarmup();
    if (IsPaused()) {
      LogDebug("Match was paused when loading match config. Unpausing.");
      UnpauseGame();
    }

    Get5_MessageToAll("%t", "MatchConfigLoadedInfoMessage");

    Stats_InitSeries();

    Get5TeamWrapper team1 = new Get5TeamWrapper(g_TeamIDs[Get5Team_1], g_TeamNames[Get5Team_1]);
    Get5TeamWrapper team2 = new Get5TeamWrapper(g_TeamIDs[Get5Team_2], g_TeamNames[Get5Team_2]);

    Get5SeriesStartedEvent startEvent = new Get5SeriesStartedEvent(g_MatchID, g_NumberOfMapsInSeries, team1, team2);

    LogDebug("Calling Get5_OnSeriesInit");

    Call_StartForward(g_OnSeriesInit);
    Call_PushCell(startEvent);
    Call_Finish();

    EventLogger_LogAndDeleteEvent(startEvent);

    if (!g_CheckAuthsCvar.BoolValue &&
        (GetTeamPlayers(Get5Team_1).Length != 0 || GetTeamPlayers(Get5Team_2).Length != 0 ||
         GetTeamCoaches(Get5Team_1).Length != 0 || GetTeamCoaches(Get5Team_2).Length != 0)) {
      LogError("Setting player auths in the \"players\" or \"coaches\" section has no impact with get5_check_auths 0");
    }

    // If we veto, the map and game mode will change after veto, otherwise we change it immediately.
    // When restoring from backup, changelevel is called after loading the match config.
    if (g_SkipVeto) {
      g_MapsToPlay.GetString(0, mapName, sizeof(mapName));
      char currentMap[PLATFORM_MAX_PATH];
      GetCurrentMap(currentMap, sizeof(currentMap));
      if (g_MapReloadRequired || !StrEqual(mapName, currentMap) || IsMapReloadRequiredForGameMode(g_Wingman)) {
        // If we do the veto, game mode and map change is done post-veto instead.
        SetCorrectGameMode();
        ChangeMap(mapName);
      } else {
        CheckTeamsPostMatchConfigLoad();
      }
    } else {
      CheckTeamsPostMatchConfigLoad();
    }
  }
  g_Get5OwnsPauseCommands = true;
  strcopy(g_LoadedConfigFile, sizeof(g_LoadedConfigFile), config);
  return true;
}

static void CheckTeamsPostMatchConfigLoad() {
  if (!g_CheckAuthsCvar.BoolValue) {
    return;
  }
  // When the match is loaded, we do not want to assign players on no team, as they may be in the
  // process of joining the server, which is the reason for the timer callback. This has caused
  // problems with players getting stuck on no team when using match config autoload, essentially
  // recreating the "coaching bug". Adding a few seconds seems to solve this problem. We cannot just
  // skip team none, as players may also just be on the team selection menu when the match is
  // loaded, meaning they will never have a joingame hook, as it already happened, and we still
  // want those players placed.
  LOOP_CLIENTS(i) {
    if (IsPlayer(i)) {
      if (GetClientTeam(i) == CS_TEAM_NONE) {
        CreateTimer(2.0, Timer_PlacePlayerFromTeamNone, i, TIMER_FLAG_NO_MAPCHANGE);
      } else {
        CheckClientTeam(i);
      }
    }
  }
}

static Action Timer_PlacePlayerFromTeamNone(Handle timer, int client) {
  if (g_GameState != Get5State_None && IsPlayer(client)) {
    CheckClientTeam(client);
  }
  return Plugin_Handled;
}

static bool LoadMatchFile(const char[] config, char[] error, bool backup) {
  if (!backup) {
    LogDebug("Calling Get5_OnPreLoadMatchConfig()");
    Get5PreloadMatchConfigEvent event = new Get5PreloadMatchConfigEvent(config);
    Call_StartForward(g_OnPreLoadMatchConfig);
    Call_PushCell(event);
    Call_Finish();
    EventLogger_LogAndDeleteEvent(event);
  }

  if (!FileExists(config)) {
    FormatEx(error, PLATFORM_MAX_PATH, "比赛配置文件 '%s' 不存在或无法读取。(Match config file '%s' does not exist or cannot be read.)",
             config, config);
    return false;
  }

  bool success = false;
  if (IsJSONPath(config)) {
    JSON_Object json = LoadMatchFromFileJSON(config, error);
    if (json != null) {
      success = LoadMatchFromJson(json, error);
      json_cleanup_and_delete(json);
    }
  } else {
    // Assume its a key-values file.
    char parseError[PLATFORM_MAX_PATH];
    if (!CheckKeyValuesFile(config, parseError, sizeof(parseError))) {
      FormatEx(error, PLATFORM_MAX_PATH,
               "将比赛配置文件 '%s' 作为 KV 读取失败：%s (Failed to read match config from file '%s' as KV: %s)",
               config, parseError, config, parseError);
    } else {
      KeyValues kv = new KeyValues("Match");
      if (!kv.ImportFromFile(config)) {
        FormatEx(error, PLATFORM_MAX_PATH, "导入比赛配置文件 '%s' 失败。(Failed to import match config from file '%s'.)",
                 config, config);
      } else {
        success = LoadMatchFromKeyValue(kv, error);
      }
      delete kv;
    }
  }
  return success;
}

JSON_Object LoadMatchFromFileJSON(const char[] filepath, char[] error) {
  JSON_Object json = LoadJSONIfFileExists(filepath, error);
  if (json == null) {
    return null;
  }
  if (!ValidateJSONMatchConfig(json, error)) {
    json_cleanup_and_delete(json);
    return null;
  }
  return json;
}

static bool LoadMapListFromFile(const char[] fromFile, char[] error) {
  LogDebug("Loading maplist using fromfile.");
  bool success = false;
  if (IsJSONPath(fromFile)) {
    JSON_Object jsonFromFile = LoadJSONIfFileExists(fromFile, error);
    if (jsonFromFile != null) {
      if (ValidateJSONMapList(jsonFromFile, error, false)) {
        success = LoadMapListJson(jsonFromFile, error);
      }
      json_cleanup_and_delete(jsonFromFile);
    }
  } else {
    char parseError[PLATFORM_MAX_PATH];
    if (!CheckKeyValuesFile(fromFile, parseError, sizeof(parseError))) {
      FormatEx(error, PLATFORM_MAX_PATH,
               "'maplist' -> 'fromfile' 指向无效或不可读的 KV 文件：'%s'。错误：%s ('maplist' -> 'fromfile' points to an invalid or unreadable KV file: '%s'. Error: %s)",
               fromFile, parseError, fromFile, parseError);
    } else {
      KeyValues kvFromFile = new KeyValues("maplist");
      if (kvFromFile.ImportFromFile(fromFile)) {
        success = LoadMapListKeyValue(kvFromFile, error, false);
      } else {
        FormatEx(error, PLATFORM_MAX_PATH, "从 KV 文件读取地图列表失败：'%s'。(Failed to read maplist from KV file: '%s'.)",
                 fromFile, fromFile);
      }
      delete kvFromFile;
    }
  }
  return success;
}

bool LoadTeamDataFromFile(const char[] fromFile, const Get5Team team, char[] error) {
  LogDebug("Loading team data for team %d using fromfile.", team);
  bool success = false;
  if (IsJSONPath(fromFile)) {
    JSON_Object jsonFromFile = LoadJSONIfFileExists(fromFile, error);
    if (jsonFromFile != null) {
      if (ValidateJSONTeam(jsonFromFile, error, team == Get5Team_Spec, false)) {
        success = LoadTeamDataJson(jsonFromFile, team, error);
      }
      json_cleanup_and_delete(jsonFromFile);
    }
  } else {
    char parseError[PLATFORM_MAX_PATH];
    if (!CheckKeyValuesFile(fromFile, parseError, sizeof(parseError))) {
      FormatEx(error, PLATFORM_MAX_PATH, "无法从 KV 文件 '%s' 读取队伍：%s (Cannot read team from KV file '%s': %s)",
               fromFile, parseError, fromFile, parseError);
    } else {
      KeyValues kvFromFile = new KeyValues("Team");
      if (kvFromFile.ImportFromFile(fromFile)) {
        success = LoadTeamDataKeyValue(kvFromFile, team, error, false);
      } else {
        FormatEx(error, PLATFORM_MAX_PATH, "无法从 KV 文件 '%s' 读取队伍。(Cannot read team from KV file '%s'.)",
                 fromFile, fromFile);
      }
      delete kvFromFile;
    }
  }
  return success;
}

void MatchConfigFail(const char[] reason, any...) {
  char buffer[512];
  VFormat(buffer, sizeof(buffer), reason, 2);
  LogError("Failed to load match configuration: %s", buffer);

  Get5LoadMatchConfigFailedEvent event = new Get5LoadMatchConfigFailedEvent(buffer);

  LogDebug("Calling Get5_OnLoadMatchConfigFailed()");

  Call_StartForward(g_OnLoadMatchConfigFailed);
  Call_PushCell(event);
  Call_Finish();

  EventLogger_LogAndDeleteEvent(event);
}

bool LoadMatchFromUrl(const char[] url, const ArrayList paramNames = null, const ArrayList paramValues = null,
                      const ArrayList headerNames = null, const ArrayList headerValues = null, char[] error) {
  if (!LibraryExists("SteamWorks")) {
    FormatEx(error, PLATFORM_MAX_PATH,
             "通过 HTTP 加载比赛配置需要 SteamWorks 扩展。(The SteamWorks extension is required in order to load match configurations over HTTP.)");
    return false;
  }

  Handle request = CreateGet5HTTPRequest(k_EHTTPMethodGET, url, error);
  if (request == INVALID_HANDLE || !SetMultipleHeaders(request, headerNames, headerValues, error) ||
      !SetMultipleQueryParameters(request, paramNames, paramValues, error)) {
    delete request;
    return false;
  }

  DataPack pack = new DataPack();
  pack.WriteString(url);

  SteamWorks_SetHTTPRequestContextValue(request, pack);
  SteamWorks_SetHTTPCallbacks(request, LoadMatchFromUrl_Callback);
  SteamWorks_SendHTTPRequest(request);
  return true;
}

static void LoadMatchFromUrl_Callback(Handle request, bool failure, bool requestSuccessful, EHTTPStatusCode statusCode,
                                      DataPack pack) {

  char loadedUrl[PLATFORM_MAX_PATH];
  pack.Reset();
  pack.ReadString(loadedUrl, sizeof(loadedUrl));
  delete pack;

  if (failure || !requestSuccessful) {
    MatchConfigFail(
      "对 '%s' 的 HTTP 请求因网络或配置错误而失败，请确认 URL 已用引号包裹。(HTTP request for '%s' failed due to a network or configuration error. Make sure you have enclosed your URL in quotes.)",
      loadedUrl, loadedUrl);
  } else if (!CheckForSuccessfulResponse(request, statusCode)) {
    MatchConfigFail("对 '%s' 的 HTTP 请求失败，HTTP 状态码：%d。(HTTP request for '%s' failed with HTTP status code: %d.)",
                    loadedUrl, statusCode, loadedUrl, statusCode);
  } else {
    char remoteConfig[PLATFORM_MAX_PATH];
    char error[PLATFORM_MAX_PATH];
    GetTempFilePath(remoteConfig, sizeof(remoteConfig), REMOTE_CONFIG_PATTERN);
    if (SteamWorks_WriteHTTPResponseBodyToFile(request, remoteConfig)) {
      if (LoadMatchConfig(remoteConfig, error)) {
        // Override g_LoadedConfigFile to point to the URL instead of the local temp file.
        strcopy(g_LoadedConfigFile, sizeof(g_LoadedConfigFile), loadedUrl);
        // We only delete the file if it loads successfully, as it may be used for debugging otherwise.
        if (FileExists(remoteConfig) && !DeleteFile(remoteConfig)) {
          LogError("Unable to delete temporary match config file '%s'.", remoteConfig);
        }
      } else {
        MatchConfigFail(error);
      }
    } else {
      MatchConfigFail("将比赛配置写入文件 '%s' 失败。(Failed to write match configuration to file '%s'.)",
                      remoteConfig, remoteConfig);
    }
  }
  delete request;
}

void WriteMatchToKv(KeyValues kv) {
  kv.SetString("matchid", g_MatchID);
  kv.SetNum("scrim", g_InScrimMode);
  kv.SetNum("skip_veto", g_SkipVeto);
  kv.SetNum("num_maps", g_NumberOfMapsInSeries);
  kv.SetNum("players_per_team", g_PlayersPerTeam);
  kv.SetNum("coaches_per_team", g_CoachesPerTeam);
  kv.SetNum("coaches_must_ready", g_CoachesMustReady);
  kv.SetNum("min_players_to_ready", g_MinPlayersToReady);
  kv.SetNum("min_spectators_to_ready", g_MinSpectatorsToReady);
  kv.SetString("match_title", g_MatchTitle);
  kv.SetNum("clinch_series", g_SeriesCanClinch);
  kv.SetNum("wingman", g_Wingman);

  kv.SetNum("favored_percentage_team1", g_FavoredTeamPercentage);
  kv.SetString("favored_percentage_text", g_FavoredTeamText);

  char sideType[64];
  MatchSideTypeToString(g_MatchSideType, sideType, sizeof(sideType));
  kv.SetString("side_type", sideType);

  kv.JumpToKey("maplist", true);
  for (int i = 0; i < g_MapPoolList.Length; i++) {
    char map[PLATFORM_MAX_PATH];
    g_MapPoolList.GetString(i, map, sizeof(map));
    EscapeKeyValueKeyWrite(map, sizeof(map));
    kv.SetString(map, KEYVALUE_STRING_PLACEHOLDER);
  }
  kv.GoBack();

  char auth[AUTH_LENGTH];
  char name[MAX_NAME_LENGTH];
  AddTeamBackupData("team1", kv, Get5Team_1, auth, name);
  AddTeamBackupData("team2", kv, Get5Team_2, auth, name);
  AddTeamBackupData("spectators", kv, Get5Team_Spec, auth, name);

  kv.JumpToKey("cvars", true);
  char cvarName[MAX_CVAR_LENGTH];
  char cvarValue[MAX_CVAR_LENGTH];
  for (int i = 0; i < g_CvarNames.Length; i++) {
    g_CvarNames.GetString(i, cvarName, sizeof(cvarName));
    g_CvarValues.GetString(i, cvarValue, sizeof(cvarValue));
    kv.SetString(cvarName, strlen(cvarValue) == 0 ? KEYVALUE_STRING_PLACEHOLDER : cvarValue);
  }
  kv.GoBack();
}

static void AddTeamBackupData(const char[] key, const KeyValues kv, const Get5Team team, char[] auth, char[] name) {
  kv.JumpToKey(key, true);
  WritePlayerDataToKV("players", GetTeamPlayers(team), kv, auth, name);
  kv.SetString("name", g_TeamNames[team]);
  if (team != Get5Team_Spec) {
    kv.SetString("id", g_TeamIDs[team]);
    kv.SetString("tag", g_TeamTags[team]);
    kv.SetString("flag", g_TeamFlags[team]);
    kv.SetString("logo", g_TeamLogos[team]);
    kv.SetString("matchtext", g_TeamMatchTexts[team]);
    WritePlayerDataToKV("coaches", GetTeamCoaches(team), kv, auth, name);
  }
  kv.GoBack();
}

static void WritePlayerDataToKV(const char[] key, const ArrayList players, const KeyValues kv, char[] auth,
                                char[] name) {
  kv.JumpToKey(key, true);
  for (int i = 0; i < players.Length; i++) {
    players.GetString(i, auth, AUTH_LENGTH);
    if (!g_PlayerNames.GetString(auth, name, MAX_NAME_LENGTH)) {
      strcopy(name, MAX_NAME_LENGTH, KEYVALUE_STRING_PLACEHOLDER);
    }
    kv.SetString(auth, name);
  }
  kv.GoBack();
}

// JSON load validators
bool ValidateJSONMatchConfig(const JSON_Object json, char[] error) {
  if (json.IsArray) {
    FormatEx(error, PLATFORM_MAX_PATH, "JSON 比赛配置不能是数组，必须是对象。(JSON match config is a JSON array. Must be object.)");
    return false;
  }

  if (!json.HasKey("maplist") || json.GetType("maplist") != JSON_Type_Object) {
    FormatEx(error, PLATFORM_MAX_PATH,
             "JSON 比赛配置中的 'maplist' 为必填项，且必须为数组或对象。(JSON match config 'maplist' property is required and must be an array or object.)");
    return false;
  }

  JSON_Object mapListObject = json.GetObject("maplist");
  if (mapListObject == null) {
    FormatEx(error, PLATFORM_MAX_PATH, "JSON 比赛配置缺少必需的 'maplist' 属性。(JSON match config is missing required property 'maplist'.)");
    return false;
  }

  if (!ValidateJSONMapList(mapListObject, error, true)) {
    return false;
  }

  char stringKeys[][] = {"matchid", "match_title", "veto_first", "side_type", "favored_percentage_text"};
  for (int i = 0; i < 5; i++) {
    if (json.HasKey(stringKeys[i]) && json.GetType(stringKeys[i]) != JSON_Type_String) {
      FormatEx(error, PLATFORM_MAX_PATH,
               "JSON 比赛配置中的 '%s' 属性无效，必须为字符串。(JSON match config has invalid '%s' property. Must be string.)",
               stringKeys[i], stringKeys[i]);
      return false;
    }
  }
  char integerKeys[][] = {"num_maps", "players_per_team", "coaches_per_team", "min_players_to_ready",
                          "min_spectators_to_ready"};
  for (int i = 0; i < 5; i++) {
    if (json.HasKey(integerKeys[i]) &&
        (json.GetType(integerKeys[i]) != JSON_Type_Int || json.GetInt(integerKeys[i]) < 0)) {
      FormatEx(error, PLATFORM_MAX_PATH,
               "JSON 比赛配置中的 '%s' 属性无效，必须为非负整数。(JSON match config has invalid '%s' property. Must be non-negative integer.)",
               integerKeys[i], integerKeys[i]);
      return false;
    }
  }
  char boolKeys[][] = {"clinch_series", "wingman", "coaches_must_ready", "skip_veto", "scrim"};
  for (int i = 0; i < 5; i++) {
    if (json.HasKey(boolKeys[i]) && (json.GetType(boolKeys[i]) != JSON_Type_Bool &&
                                     (json.GetType(boolKeys[i]) != JSON_Type_Int ||
                                      (json.GetInt(boolKeys[i]) != 0 && json.GetInt(boolKeys[i]) != 1)))) {
      FormatEx(error, PLATFORM_MAX_PATH,
               "JSON 比赛配置中的 '%s' 属性无效，必须为布尔值或 0/1。(JSON match config has invalid '%s' property. Must be boolean or 0/1.)",
               boolKeys[i], boolKeys[i]);
      return false;
    }
  }
  char percentageTeam1Key[] = "favored_percentage_team1";
  if (json.HasKey(percentageTeam1Key) && json.GetType(percentageTeam1Key) != JSON_Type_Int &&
      json.GetType(percentageTeam1Key) != JSON_Type_Float) {
    FormatEx(error, PLATFORM_MAX_PATH,
             "JSON 比赛配置中的 '%s' 属性无效，必须为数字。(JSON match config has invalid '%s' property. Must be number.)",
             percentageTeam1Key, percentageTeam1Key);
    return false;
  }

  if (!json.HasKey("team1") || json.GetType("team1") != JSON_Type_Object) {
    FormatEx(error, PLATFORM_MAX_PATH,
             "JSON 比赛配置缺少 'team1' 属性或其格式无效，必须为对象。(JSON match config is missing or has invalid 'team1' property. Must be object.)");
    return false;
  }
  if (!ValidateJSONTeam(json.GetObject("team1"), error, false, true)) {
    return false;
  }

  if (!json.GetBool("scrim")) {
    if (!json.HasKey("team2") || json.GetType("team2") != JSON_Type_Object) {
      FormatEx(error, PLATFORM_MAX_PATH,
               "JSON 比赛配置缺少 'team2' 属性或其格式无效，必须为对象。(JSON match config is missing or has invalid 'team2' property. Must be object.)");
      return false;
    }
    if (!ValidateJSONTeam(json.GetObject("team2"), error, false, true)) {
      return false;
    }
  }

  if (json.HasKey("spectators")) {
    if (json.GetType("spectators") != JSON_Type_Object) {
      FormatEx(error, PLATFORM_MAX_PATH,
               "JSON 比赛配置中的 'spectators' 属性无效，必须为对象。(JSON match config has invalid 'spectators' property. Must be object.)");
      return false;
    }
    if (!ValidateJSONTeam(json.GetObject("spectators"), error, true, true)) {
      return false;
    }
  }

  if (json.HasKey("cvars")) {
    if (json.GetType("cvars") != JSON_Type_Object) {
      FormatEx(error, PLATFORM_MAX_PATH,
               "JSON 比赛配置中的 'cvars' 属性无效，必须为对象。(JSON match config has invalid 'cvars' property. Must be object.)");
      return false;
    }
    if (!ValidateJSONCvars(json.GetObject("cvars"), error)) {
      return false;
    }
  }

  return true;
}

bool ValidateJSONMapList(const JSON_Object json, char[] error, bool allowFromFile) {
  if (json.IsArray) {
    JSON_Array maplist = view_as<JSON_Array>(json);
    if (maplist.Length < 1) {
      FormatEx(error, PLATFORM_MAX_PATH, "'maplist' 属性不能为空数组。('maplist' property must not be empty array.)");
      return false;
    }
  } else {
    if (!allowFromFile) {
      FormatEx(error, PLATFORM_MAX_PATH, "'maplist' 属性必须为数组。('maplist' property must be array.)");
      return false;
    }
    if (!json.HasKey("fromfile") || json.GetType("fromfile") != JSON_Type_String) {
      FormatEx(error, PLATFORM_MAX_PATH,
               "'maplist' 属性若为对象，必须包含字符串类型的 'fromfile'。('maplist' property must contain 'fromfile' as string if object.)");
      return false;
    }
    char fromFile[PLATFORM_MAX_PATH];
    json.GetString("fromfile", fromFile, sizeof(fromFile));
    if (strlen(fromFile) == 0) {
      FormatEx(error, PLATFORM_MAX_PATH, "'maplist' -> 'fromfile' 不能为空字符串。('maplist' -> 'fromfile' cannot be empty string.)");
      return false;
    }
  }
  return true;
}

bool ValidateJSONTeam(const JSON_Object team, char[] error, bool spectators, bool allowFromFile) {
  if (team.IsArray) {
    FormatEx(error, PLATFORM_MAX_PATH, "队伍不能是数组，必须是对象。(Team cannot be an array. Must be object.)");
    return false;
  }

  char keys[][] = {"name", "tag", "flag", "logo", "matchtext", "fromfile", "id"};
  for (int i = 0; i < 7; i++) {
    if (team.HasKey(keys[i]) && team.GetType(keys[i]) != JSON_Type_String) {
      FormatEx(error, PLATFORM_MAX_PATH,
               "队伍配置中的 '%s' 属性无效，必须为字符串。(Team has invalid '%s' property. Must be string.)",
               keys[i], keys[i]);
      return false;
    }
  }

  bool hasFromFile = team.HasKey("fromfile");
  if (hasFromFile) {
    if (!allowFromFile) {
      FormatEx(error, PLATFORM_MAX_PATH, "队伍配置中的 'fromfile' 出现递归引用。(Team has recursive 'fromfile'.)");
      return false;
    }
    char fromFile[PLATFORM_MAX_PATH];
    team.GetString("fromfile", fromFile, sizeof(fromFile));
    if (strlen(fromFile) == 0) {
      FormatEx(error, PLATFORM_MAX_PATH, "队伍配置中的 'fromfile' 不能为空字符串。(Team 'fromfile' must not be empty string.)");
      return false;
    }
    return true;
  }

  bool hasPlayers = team.HasKey("players");
  bool playersValid = hasPlayers && team.GetType("players") == JSON_Type_Object;

  // Player team cannot be empty, coaches optional. Spectator can be totally empty and still be valid.
  if ((!spectators && !playersValid) || (spectators && hasPlayers && !playersValid)) {
    FormatEx(error, PLATFORM_MAX_PATH, "队伍配置缺少有效的 'players' 对象/数组。(Team does not have a valid 'players' object/array.)");
    return false;
  }
  if (team.HasKey("coaches") && team.GetType("coaches") != JSON_Type_Object) {
    FormatEx(error, PLATFORM_MAX_PATH, "队伍配置缺少有效的 'coaches' 对象/数组。(Team does not have a valid 'coaches' object/array.)");
    return false;
  }
  return true;
}

bool ValidateJSONCvars(const JSON_Object cvars, char[] error) {
  if (cvars.IsArray) {
    FormatEx(error, PLATFORM_MAX_PATH, "JSON 'cvars' 不能是数组。(JSON 'cvars' must not be an array.)");
    return false;
  }
  int length = cvars.Length;
  int keyLength = 0;
  for (int i = 0; i < length; i++) {
    keyLength = cvars.GetKeySize(i);
    char[] cVarKey = new char[keyLength];
    cvars.GetKey(i, cVarKey, keyLength);
    JSONCellType type = cvars.GetType(cVarKey);
    if (type == JSON_Type_Object || type == JSON_Type_Invalid) {
      FormatEx(error, PLATFORM_MAX_PATH,
               "JSON 'cvars' 中的键 '%s' 包含无效值。(JSON 'cvars' key '%s' contains invalid value.)",
               cVarKey, cVarKey);
      return false;
    }
  }
  return true;
}

// Load from JSON
static bool LoadMatchFromJson(const JSON_Object json, char[] error) {
  if (!ValidateJSONMatchConfig(json, error)) {
    return false;
  }
  json_object_get_string_safe(json, "matchid", g_MatchID, sizeof(g_MatchID), CONFIG_MATCHID_DEFAULT);
  g_InScrimMode = json_object_get_bool_safe(json, "scrim", CONFIG_SCRIM_DEFAULT);
  g_SeriesCanClinch = json_object_get_bool_safe(json, "clinch_series", CONFIG_CLINCH_SERIES_DEFAULT);
  g_Wingman = json_object_get_bool_safe(json, "wingman", CONFIG_WINGMAN_DEFAULT);
  json_object_get_string_safe(json, "match_title", g_MatchTitle, sizeof(g_MatchTitle), CONFIG_MATCHTITLE_DEFAULT);
  g_PlayersPerTeam = json_object_get_int_safe(
    json, "players_per_team", g_Wingman ? CONFIG_PLAYERSPERTEAM_DEFAULT_WM : CONFIG_PLAYERSPERTEAM_DEFAULT);
  g_CoachesPerTeam = json_object_get_int_safe(json, "coaches_per_team", CONFIG_COACHESPERTEAM_DEFAULT);
  g_MinPlayersToReady = json_object_get_int_safe(json, "min_players_to_ready", CONFIG_MINPLAYERSTOREADY_DEFAULT);
  g_MinSpectatorsToReady =
    json_object_get_int_safe(json, "min_spectators_to_ready", CONFIG_MINSPECTATORSTOREADY_DEFAULT);
  g_SkipVeto = json_object_get_bool_safe(json, "skip_veto", CONFIG_SKIPVETO_DEFAULT);
  g_CoachesMustReady = json_object_get_bool_safe(json, "coaches_must_ready", CONFIG_COACHES_MUST_READY_DEFAULT);
  g_NumberOfMapsInSeries = json_object_get_int_safe(json, "num_maps", CONFIG_NUM_MAPSDEFAULT);
  g_MapsToWin = g_SeriesCanClinch ? MapsToWin(g_NumberOfMapsInSeries) : g_NumberOfMapsInSeries;

  char vetoFirstBuffer[64];
  json_object_get_string_safe(json, "veto_first", vetoFirstBuffer, sizeof(vetoFirstBuffer), CONFIG_VETOFIRST_DEFAULT);
  Get5VetoFirst vetoFirst = VetoFirstFromString(vetoFirstBuffer, error);
  switch (vetoFirst) {
    case Get5VetoFirst_Team1:
      g_LastVetoTeam = Get5Team_2;
    case Get5VetoFirst_Team2:
      g_LastVetoTeam = Get5Team_1;
    case Get5VetoFirst_Random:
      g_LastVetoTeam = view_as<Get5Team>(GetRandomInt(0, 1));
    case Get5VetoFirst_Invalid:
      return false;
  }

  char sideTypeBuffer[64];
  json_object_get_string_safe(json, "side_type", sideTypeBuffer, sizeof(sideTypeBuffer), CONFIG_SIDETYPE_DEFAULT);
  MatchSideType sideType = MatchSideTypeFromString(sideTypeBuffer, error);
  if (sideType == MatchSideType_Invalid) {
    return false;
  }
  g_MatchSideType = sideType;

  json_object_get_string_safe(json, "favored_percentage_text", g_FavoredTeamText, sizeof(g_FavoredTeamText));
  g_FavoredTeamPercentage = json_object_get_int_safe(json, "favored_percentage_team1", 0);

  JSON_Object spec = json.GetObject("spectators");
  if (spec != null && !LoadTeamDataJson(spec, Get5Team_Spec, error)) {
    return false;
  }

  if (!LoadTeamDataJson(json.GetObject("team1"), Get5Team_1, error)) {
    return false;
  }

  if (json.HasKey("team2") && !LoadTeamDataJson(json.GetObject("team2"), Get5Team_2, error)) {
    return false;
  }

  if (!LoadMapListJson(json.GetObject("maplist"), error)) {
    return false;
  }

  if (g_MapPoolList.Length == g_NumberOfMapsInSeries) {
    // If the number of maps is equal to the pool size, veto is impossible, so we force disable it.
    g_SkipVeto = true;
  } else if (g_MapPoolList.Length < g_NumberOfMapsInSeries) {
    FormatEx(error, PLATFORM_MAX_PATH,
             "地图池仅有 %d 张地图，不足以进行 %d 图系列赛。(The map pool (%d) is not large enough to play a series of %d maps.)",
             g_MapPoolList.Length, g_NumberOfMapsInSeries, g_MapPoolList.Length, g_NumberOfMapsInSeries);
    return false;
  }

  JSON_Array array = view_as<JSON_Array>(json.GetObject("map_sides"));
  if (array != null) {
    if (!array.IsArray) {
      FormatEx(error, PLATFORM_MAX_PATH,
               "期望 \"map_sides\" 段为数组，但实际为对象。(Expected \"map_sides\" section to be an array, found object.)");
      return false;
    }
    for (int i = 0; i < array.Length; i++) {
      char buffer[64];
      array.GetString(i, buffer, sizeof(buffer));
      SideChoice sideChoice = SideChoiceFromString(buffer, error);
      if (sideChoice == SideChoice_Invalid) {
        return false;
      }
      g_MapSides.Push(sideChoice);
    }
  }

  if (!g_SkipVeto) {
    // Must go after loading maplist!
    JSON_Object mapVetoOrder = json.GetObject("veto_mode");
    if (mapVetoOrder != null) {
      if (!LoadVetoDataJSON(mapVetoOrder, error)) {
        return false;
      }
    } else {
      GenerateDefaultVetoSetup(g_MapPoolList, g_MapBanOrder, g_NumberOfMapsInSeries, g_LastVetoTeam);
    }
  }

  JSON_Object cvars = json.GetObject("cvars");
  if (cvars != null) {
    char cvarValue[MAX_CVAR_LENGTH];

    int length = cvars.Length;
    int key_length = 0;
    for (int i = 0; i < length; i++) {
      key_length = cvars.GetKeySize(i);
      char[] cvarName = new char[key_length];
      cvars.GetKey(i, cvarName, key_length);
      JSONCellType type = cvars.GetType(cvarName);
      if (type == JSON_Type_Int) {
        IntToString(cvars.GetInt(cvarName), cvarValue, sizeof(cvarValue));
#if SM_INT64_SUPPORTED  // requires SM 1.11 build 6861 according to sm-json
      } else if (type == JSON_Type_Int64) {
        int value[2];
        cvars.GetInt64(cvarName, value);
        Int64ToString(value, cvarValue, sizeof(cvarValue));
#endif
      } else if (type == JSON_Type_Float) {
        FloatToString(cvars.GetFloat(cvarName), cvarValue, sizeof(cvarValue));
      } else {  // String by default; object was already validated.
        cvars.GetString(cvarName, cvarValue, sizeof(cvarValue));
      }
      g_CvarNames.PushString(cvarName);
      g_CvarValues.PushString(cvarValue);
    }
  }

  NormalizeMatchConfigRoundOptions();

  DisableCoachingSupport();

  return true;
}

static bool LoadMapListJson(const JSON_Object json, char[] error) {
  if (json.IsArray) {
    JSON_Array array = view_as<JSON_Array>(json);
    char buffer[PLATFORM_MAX_PATH];
    for (int i = 0; i < array.Length; i++) {
      array.GetString(i, buffer, PLATFORM_MAX_PATH);
      g_MapPoolList.PushString(buffer);
    }
    return true;
  } else {
    char mapFileName[PLATFORM_MAX_PATH];
    json.GetString("fromfile", mapFileName, PLATFORM_MAX_PATH);
    return LoadMapListFromFile(mapFileName, error);
  }
}

static bool LoadVetoDataJSON(const JSON_Object json, char[] error) {
  if (!json.IsArray) {
    FormatEx(error, PLATFORM_MAX_PATH, "'veto_order' 必须为数组。('veto_order' must be array.)");
    return false;
  }

  JSON_Array array = view_as<JSON_Array>(json);
  char buffer[32];
  Get5MapSelectionOption type;
  for (int i = 0; i < array.Length; i++) {
    array.GetString(i, buffer, sizeof(buffer));
    type = MapSelectionStringToMapSelection(buffer, error);
    if (type == Get5MapSelectionOption_Invalid) {
      return false;
    }
    g_MapBanOrder.Push(type);
  }
  return ValidateMapBanLogic(g_MapPoolList, g_MapBanOrder, g_NumberOfMapsInSeries, error);
}

static bool LoadTeamDataJson(const JSON_Object json, const Get5Team matchTeam, char[] error) {
  if (!json.HasKey("fromfile")) {
    GetTeamPlayers(matchTeam).Clear();
    GetTeamCoaches(matchTeam).Clear();
    json_object_get_string_safe(json, "name", g_TeamNames[matchTeam], MAX_CVAR_LENGTH,
                                matchTeam == Get5Team_Spec ? CONFIG_SPECTATORSNAME_DEFAULT : "");
    FormatTeamName(matchTeam);
    AddJsonAuthsToList(json, "players", GetTeamPlayers(matchTeam), AUTH_LENGTH);
    if (matchTeam != Get5Team_Spec) {
      JSON_Object coaches = json.GetObject("coaches");
      if (coaches != null) {
        AddJsonAuthsToList(json, "coaches", GetTeamCoaches(matchTeam), AUTH_LENGTH);
      }
      json_object_get_string_safe(json, "id", g_TeamIDs[matchTeam], MAX_CVAR_LENGTH);
      json_object_get_string_safe(json, "tag", g_TeamTags[matchTeam], MAX_CVAR_LENGTH);
      json_object_get_string_safe(json, "flag", g_TeamFlags[matchTeam], MAX_CVAR_LENGTH);
      json_object_get_string_safe(json, "logo", g_TeamLogos[matchTeam], MAX_CVAR_LENGTH);
      json_object_get_string_safe(json, "matchtext", g_TeamMatchTexts[matchTeam], MAX_CVAR_LENGTH);
      g_TeamSeriesScores[matchTeam] = json_object_get_int_safe(json, "series_score", 0);
    }
    return true;
  } else {
    char fromfile[PLATFORM_MAX_PATH];
    json_object_get_string_safe(json, "fromfile", fromfile, sizeof(fromfile));
    return LoadTeamDataFromFile(fromfile, matchTeam, error);
  }
}

// Load from KeyValues
static bool LoadMatchFromKeyValue(KeyValues kv, char[] error) {
  kv.GetString("matchid", g_MatchID, sizeof(g_MatchID), CONFIG_MATCHID_DEFAULT);
  g_InScrimMode = kv.GetNum("scrim", CONFIG_SCRIM_DEFAULT) != 0;
  g_SeriesCanClinch = kv.GetNum("clinch_series", CONFIG_CLINCH_SERIES_DEFAULT) != 0;
  g_Wingman = kv.GetNum("wingman", CONFIG_WINGMAN_DEFAULT) != 0;
  kv.GetString("match_title", g_MatchTitle, sizeof(g_MatchTitle), CONFIG_MATCHTITLE_DEFAULT);
  g_PlayersPerTeam =
    kv.GetNum("players_per_team", g_Wingman ? CONFIG_PLAYERSPERTEAM_DEFAULT_WM : CONFIG_PLAYERSPERTEAM_DEFAULT);
  g_CoachesPerTeam = kv.GetNum("coaches_per_team", CONFIG_COACHESPERTEAM_DEFAULT);
  g_MinPlayersToReady = kv.GetNum("min_players_to_ready", CONFIG_MINPLAYERSTOREADY_DEFAULT);
  g_MinSpectatorsToReady = kv.GetNum("min_spectators_to_ready", CONFIG_MINSPECTATORSTOREADY_DEFAULT);
  g_SkipVeto = kv.GetNum("skip_veto", CONFIG_SKIPVETO_DEFAULT) != 0;
  g_CoachesMustReady = kv.GetNum("coaches_must_ready", CONFIG_COACHES_MUST_READY_DEFAULT) != 0;
  g_NumberOfMapsInSeries = kv.GetNum("num_maps", CONFIG_NUM_MAPSDEFAULT);
  g_MapsToWin = g_SeriesCanClinch ? MapsToWin(g_NumberOfMapsInSeries) : g_NumberOfMapsInSeries;

  char vetoFirstBuffer[64];
  kv.GetString("veto_first", vetoFirstBuffer, sizeof(vetoFirstBuffer), CONFIG_VETOFIRST_DEFAULT);
  Get5VetoFirst vetoFirst = VetoFirstFromString(vetoFirstBuffer, error);
  switch (vetoFirst) {
    case Get5VetoFirst_Team1:
      g_LastVetoTeam = Get5Team_2;
    case Get5VetoFirst_Team2:
      g_LastVetoTeam = Get5Team_1;
    case Get5VetoFirst_Random:
      g_LastVetoTeam = view_as<Get5Team>(GetRandomInt(0, 1));
    case Get5VetoFirst_Invalid:
      return false;
  }

  char sideTypeBuffer[64];
  kv.GetString("side_type", sideTypeBuffer, sizeof(sideTypeBuffer), CONFIG_SIDETYPE_DEFAULT);
  MatchSideType sideType = MatchSideTypeFromString(sideTypeBuffer, error);
  if (sideType == MatchSideType_Invalid) {
    return false;
  }
  g_MatchSideType = sideType;

  g_FavoredTeamPercentage = kv.GetNum("favored_percentage_team1", 0);
  kv.GetString("favored_percentage_text", g_FavoredTeamText, sizeof(g_FavoredTeamText));

  if (kv.JumpToKey("spectators")) {
    if (!LoadTeamDataKeyValue(kv, Get5Team_Spec, error, true)) {
      return false;
    }
    kv.GoBack();
  }

  if (!LoadTeamsInKeyValueConfig(kv, Get5Team_1, g_InScrimMode, error)) {
    return false;
  }

  if (!LoadTeamsInKeyValueConfig(kv, Get5Team_2, g_InScrimMode, error)) {
    return false;
  }

  if (!kv.JumpToKey("maplist")) {
    FormatEx(error, PLATFORM_MAX_PATH, "比赛配置 KeyValues 缺少 'maplist' 段。(Missing 'maplist' section in match config KeyValues.)");
    return false;
  }
  if (!LoadMapListKeyValue(kv, error, true)) {
    return false;
  }
  kv.GoBack();

  if (g_MapPoolList.Length == g_NumberOfMapsInSeries) {
    // If the number of maps is equal to the pool size, veto is impossible, so we force disable it.
    g_SkipVeto = true;
  } else if (g_MapPoolList.Length < g_NumberOfMapsInSeries) {
    FormatEx(error, PLATFORM_MAX_PATH,
             "地图池仅有 %d 张地图，不足以进行 %d 图系列赛。(The map pool (%d) is not large enough to play a series of %d maps.)",
             g_MapPoolList.Length, g_NumberOfMapsInSeries, g_MapPoolList.Length, g_NumberOfMapsInSeries);
    return false;
  }

  if (kv.JumpToKey("map_sides")) {
    if (kv.GotoFirstSubKey(false)) {
      do {
        char buffer[64];
        kv.GetSectionName(buffer, sizeof(buffer));
        SideChoice sideChoice = SideChoiceFromString(buffer, error);
        if (sideChoice == SideChoice_Invalid) {
          return false;
        }
        g_MapSides.Push(sideChoice);
      } while (kv.GotoNextKey(false));
      kv.GoBack();
    }
    kv.GoBack();
  }

  if (!g_SkipVeto) {
    if (kv.JumpToKey("veto_mode")) {
      if (!LoadVetoDataKeyValues(kv, error)) {
        return false;
      }
      kv.GoBack();
    } else {
      GenerateDefaultVetoSetup(g_MapPoolList, g_MapBanOrder, g_NumberOfMapsInSeries, g_LastVetoTeam);
    }
  }

  if (kv.JumpToKey("cvars")) {
    if (kv.GotoFirstSubKey(false)) {
      char name[MAX_CVAR_LENGTH];
      char value[MAX_CVAR_LENGTH];
      do {
        kv.GetSectionName(name, sizeof(name));
        ReadEmptyStringInsteadOfPlaceholder(kv, value, sizeof(value));
        g_CvarNames.PushString(name);
        g_CvarValues.PushString(value);
      } while (kv.GotoNextKey(false));
      kv.GoBack();
    }
    kv.GoBack();
  }

  NormalizeMatchConfigRoundOptions();

  DisableCoachingSupport();

  return true;
}

// Helper to avoid repeating logic for team1 and team2 above.
static bool LoadTeamsInKeyValueConfig(const KeyValues kv, const Get5Team team, const scrim, char[] error) {
  char key[32];
  FormatEx(key, sizeof(key), team == Get5Team_1 ? "team1" : "team2");
  if (!kv.JumpToKey(key) && !(scrim && team == Get5Team_2)) {
    FormatEx(error, PLATFORM_MAX_PATH,
             "比赛配置 KeyValues 缺少 '%s' 段。(Missing '%s' section in match config KeyValues.)",
             key, key);
    return false;
  }
  if (!LoadTeamDataKeyValue(kv, team, error, true)) {
    return false;
  }
  kv.GoBack();
  return true;
}

static bool LoadMapListKeyValue(const KeyValues kv, char[] error, const bool allowFromFile) {
  if (!kv.GotoFirstSubKey(false)) {
    FormatEx(error, PLATFORM_MAX_PATH,
             "比赛配置 KV 文件中的 \"maplist\" 没有有效子键。(\"maplist\" has no valid subkeys in match config KV file.)");
    return false;
  }
  bool success = false;
  char buffer[PLATFORM_MAX_PATH];
  if (!ReadKeyValueMaplistSection(kv, buffer, error)) {
    return false;
  }
  if (allowFromFile && StrEqual("fromfile", buffer)) {
    kv.GetString(NULL_STRING, buffer, PLATFORM_MAX_PATH);
    success = LoadMapListFromFile(buffer, error);
  } else {
    g_MapPoolList.PushString(buffer);
    while (kv.GotoNextKey(false)) {
      if (!ReadKeyValueMaplistSection(kv, buffer, error)) {
        return false;
      }
      g_MapPoolList.PushString(buffer);
    }
    success = true;
  }
  kv.GoBack();
  return success;
}

static bool LoadVetoDataKeyValues(const KeyValues kv, char[] error) {
  if (!kv.GotoFirstSubKey(false)) {
    FormatEx(error, PLATFORM_MAX_PATH, "'veto_order' 不包含任何子键。('veto_order' contains no subkeys.)");
    return false;
  }
  char buffer[32];
  Get5MapSelectionOption option;
  do {
    kv.GetSectionName(buffer, sizeof(buffer));
    option = MapSelectionStringToMapSelection(buffer, error);
    if (option == Get5MapSelectionOption_Invalid) {
      return false;
    }
    g_MapBanOrder.Push(option);
  } while (kv.GotoNextKey(false));
  kv.GoBack();
  return ValidateMapBanLogic(g_MapPoolList, g_MapBanOrder, g_NumberOfMapsInSeries, error);
}

static bool ReadKeyValueMaplistSection(const KeyValues kv, char[] buffer, char[] error) {
  if (!kv.GetSectionName(buffer, PLATFORM_MAX_PATH)) {
    FormatEx(error, PLATFORM_MAX_PATH,
             "比赛配置 KeyValues 中的 'maplist' 包含无效地图名。('maplist' property contains invalid map name in match config KeyValues.)");
    return false;
  }
  EscapeKeyValueKeyRead(buffer, PLATFORM_MAX_PATH);
  return true;
}

static bool LoadTeamDataKeyValue(const KeyValues kv, const Get5Team matchTeam, char[] error, const bool allowFromFile) {
  char fromfile[PLATFORM_MAX_PATH];
  if (allowFromFile) {
    kv.GetString("fromfile", fromfile, sizeof(fromfile));
  }
  if (StrEqual(fromfile, "")) {
    GetTeamPlayers(matchTeam).Clear();
    GetTeamCoaches(matchTeam).Clear();
    kv.GetString("name", g_TeamNames[matchTeam], MAX_CVAR_LENGTH,
                 matchTeam == Get5Team_Spec ? CONFIG_SPECTATORSNAME_DEFAULT : "");
    FormatTeamName(matchTeam);
    AddSubsectionAuthsToList(kv, "players", GetTeamPlayers(matchTeam));
    if (matchTeam != Get5Team_Spec) {
      AddSubsectionAuthsToList(kv, "coaches", GetTeamCoaches(matchTeam));
      kv.GetString("id", g_TeamIDs[matchTeam], MAX_CVAR_LENGTH, "");
      kv.GetString("tag", g_TeamTags[matchTeam], MAX_CVAR_LENGTH, "");
      kv.GetString("flag", g_TeamFlags[matchTeam], MAX_CVAR_LENGTH, "");
      kv.GetString("logo", g_TeamLogos[matchTeam], MAX_CVAR_LENGTH, "");
      kv.GetString("matchtext", g_TeamMatchTexts[matchTeam], MAX_CVAR_LENGTH, "");
      g_TeamSeriesScores[matchTeam] = kv.GetNum("series_score", 0);
    }
    return true;
  } else {
    return LoadTeamDataFromFile(fromfile, matchTeam, error);
  }
}

// Veto
void GenerateDefaultVetoSetup(const ArrayList mapPool, const ArrayList mapBanOrder, const int numberOfMapsInSeries,
                              const Get5Team lastVetoTeam) {
  Get5Team startingVetoTeam = lastVetoTeam == Get5Team_1 ? Get5Team_2 : Get5Team_1;
  switch (numberOfMapsInSeries) {
    case 1: {
      int numberOfBans = g_MapPoolList.Length - 1;  // Last map either played by default or ignored.
      for (int i = 0; i < numberOfBans; i++) {
        mapBanOrder.Push(
          i % 2 == 0
            ? (startingVetoTeam == Get5Team_1 ? Get5MapSelectionOption_Team1Ban : Get5MapSelectionOption_Team2Ban)
            : (startingVetoTeam == Get5Team_1 ? Get5MapSelectionOption_Team2Ban : Get5MapSelectionOption_Team1Ban));
      }
    }
    case 2: {
      if (mapPool.Length < 5) {
        mapBanOrder.Push(startingVetoTeam == Get5Team_1 ? Get5MapSelectionOption_Team1Pick
                                                        : Get5MapSelectionOption_Team2Pick);
        mapBanOrder.Push(startingVetoTeam == Get5Team_1 ? Get5MapSelectionOption_Team2Pick
                                                        : Get5MapSelectionOption_Team1Pick);
      } else {
        mapBanOrder.Push(startingVetoTeam == Get5Team_1 ? Get5MapSelectionOption_Team1Ban
                                                        : Get5MapSelectionOption_Team2Ban);
        mapBanOrder.Push(startingVetoTeam == Get5Team_1 ? Get5MapSelectionOption_Team2Ban
                                                        : Get5MapSelectionOption_Team1Ban);
        mapBanOrder.Push(startingVetoTeam == Get5Team_1 ? Get5MapSelectionOption_Team1Pick
                                                        : Get5MapSelectionOption_Team2Pick);
        mapBanOrder.Push(startingVetoTeam == Get5Team_1 ? Get5MapSelectionOption_Team2Pick
                                                        : Get5MapSelectionOption_Team1Pick);
      }
    }
    default: {
      // Bo3 with 7 maps as an example.
      // For this to work, a Bo3 requires a map pool of at least 5.
      if (mapPool.Length >= numberOfMapsInSeries + 2) {  // 7 >= 3 + 2
        int numberOfPicks = numberOfMapsInSeries - 1;    // 2 picks in a Bo3
        // Determine how many bans before we start picking (may be 0):
        int numberOfStartBans = mapPool.Length - (numberOfMapsInSeries + 2);  // 7 - (3 + 2) = 2
        if (numberOfStartBans > 0) {                                          // == 2
          for (int i = 0; i < numberOfStartBans; i++) {
            mapBanOrder.Push(
              mapBanOrder.Length % 2 == 0
                ? (startingVetoTeam == Get5Team_1 ? Get5MapSelectionOption_Team1Ban : Get5MapSelectionOption_Team2Ban)
                : (startingVetoTeam == Get5Team_1 ? Get5MapSelectionOption_Team2Ban : Get5MapSelectionOption_Team1Ban));
          }
        }

        // After the initial bans, add the picks:
        for (int i = 0; i < numberOfPicks; i++) {
          mapBanOrder.Push(
            mapBanOrder.Length % 2 == 0
              ? (startingVetoTeam == Get5Team_1 ? Get5MapSelectionOption_Team1Pick : Get5MapSelectionOption_Team2Pick)
              : (startingVetoTeam == Get5Team_1 ? Get5MapSelectionOption_Team2Pick : Get5MapSelectionOption_Team1Pick));
        }

        // Determine how many bans to append to the end (may be 0):
        int numberOfEndBans = mapPool.Length - 1 - numberOfPicks - numberOfStartBans;  // 7 - 2 - 2 - 1 = 2
        if (numberOfEndBans > 0) {                                                     // == 2
          for (int i = 0; i < numberOfEndBans; i++) {
            mapBanOrder.Push(
              mapBanOrder.Length % 2 == 0
                ? (startingVetoTeam == Get5Team_1 ? Get5MapSelectionOption_Team1Ban : Get5MapSelectionOption_Team2Ban)
                : (startingVetoTeam == Get5Team_1 ? Get5MapSelectionOption_Team2Ban : Get5MapSelectionOption_Team1Ban));
          }
        }
      } else {
        // else we just alternate picks and ignore the last map.
        for (int i = 0; i < numberOfMapsInSeries; i++) {
          mapBanOrder.Push(
            i % 2 == 0
              ? (startingVetoTeam == Get5Team_1 ? Get5MapSelectionOption_Team1Pick : Get5MapSelectionOption_Team2Pick)
              : (startingVetoTeam == Get5Team_1 ? Get5MapSelectionOption_Team2Pick : Get5MapSelectionOption_Team1Pick));
        }
      }
    }
  }
}

bool ValidateMapBanLogic(const ArrayList mapPool, const ArrayList mapBanPickOrder, int numberOfMapsInSeries,
                         char[] error) {
  int numberOfPicks = 0;
  Get5MapSelectionOption option;
  for (int i = 0; i < mapBanPickOrder.Length; i++) {
    option = mapBanPickOrder.Get(i);
    if (option == Get5MapSelectionOption_Team1Pick || option == Get5MapSelectionOption_Team2Pick) {
      numberOfPicks++;
    }
    if (numberOfPicks == numberOfMapsInSeries || i == mapPool.Length - 2) {
      // We have all picks we need or enough bans and picks for the map pool. Delete the remaining options.
      mapBanPickOrder.Resize(i + 1);
      break;
    }
  }

  // Example: In a Bo3, at least 2 of the options must be picks to avoid randomly selecting map order of remaining maps.
  if (numberOfMapsInSeries > 1 && numberOfPicks < numberOfMapsInSeries - 1) {
    FormatEx(error, PLATFORM_MAX_PATH,
             "%d 图系列赛中，至少需要 %d 个 veto 选项为 pick，当前仅找到 %d 个。(In a series of %d maps, at least %d veto options must be picks. Found %d pick(s).)",
             numberOfMapsInSeries, numberOfMapsInSeries - 1, numberOfPicks, numberOfMapsInSeries,
             numberOfMapsInSeries - 1, numberOfPicks);
    return false;
  }

  if (mapPool.Length - 1 != mapBanPickOrder.Length && numberOfPicks != numberOfMapsInSeries) {
    // Example: Map pool of 7 requires 6 picks/bans *unless* we have picks for all maps.
    FormatEx(
      error, PLATFORM_MAX_PATH,
      "The number of maps in the pool (%d) must be one larger than the number of map picks/bans (%d), unless the number of picks (%d) matches the series length (%d).",
      mapPool.Length, mapBanPickOrder.Length, numberOfPicks, numberOfMapsInSeries);
    return false;
  }

  return true;
}

void FormatTeamName(const Get5Team team) {
  char color[32];
  char displayName[MAX_CVAR_LENGTH];
  if (team == Get5Team_1) {
    g_Team1NameColorCvar.GetString(color, sizeof(color));
  } else if (team == Get5Team_2) {
    g_Team2NameColorCvar.GetString(color, sizeof(color));
  } else if (team == Get5Team_Spec) {
    g_SpecNameColorCvar.GetString(color, sizeof(color));
  }
  GetTeamDisplayName(team, displayName, sizeof(displayName));
  FormatEx(g_FormattedTeamNames[team], MAX_CVAR_LENGTH, "%s%s{NORMAL}", color, displayName);
}

void SetMatchTeamCvars() {
  // Update mp_teammatchstat_txt with the match title.
  char mapstat[MAX_CVAR_LENGTH];
  strcopy(mapstat, sizeof(mapstat), g_MatchTitle);
  ReplaceStringWithInt(mapstat, sizeof(mapstat), "{MAPNUMBER}", Get5_GetMapNumber() + 1);
  ReplaceStringWithInt(mapstat, sizeof(mapstat), "{MAXMAPS}", g_NumberOfMapsInSeries);
  SetConVarStringSafe("mp_teammatchstat_txt", mapstat);

  SetTeamSpecificCvars(Get5Team_1);
  SetTeamSpecificCvars(Get5Team_2);
  SyncScoreboardTeamNames();
  FormatTeamName(Get5Team_1);
  FormatTeamName(Get5Team_2);

  // Set prediction cvars.
  SetConVarStringSafe("mp_teamprediction_txt", g_FavoredTeamText);
  if (g_TeamSide[Get5Team_1] == CS_TEAM_CT) {
    SetConVarIntSafe("mp_teamprediction_pct", g_FavoredTeamPercentage);
  } else {
    SetConVarIntSafe("mp_teamprediction_pct", 100 - g_FavoredTeamPercentage);
  }
  SetConVarIntSafe("mp_teamscore_max", g_MapsToWin > 1 ? g_MapsToWin : 0);
}

static void SetTeamSpecificCvars(const Get5Team team) {
  char teamText[MAX_CVAR_LENGTH];
  strcopy(teamText, sizeof(teamText), g_TeamMatchTexts[team]);  // Copy as we don't want to modify the original values.
  int teamScore = g_TeamSeriesScores[team];
  if (g_MapsToWin > 1 && strlen(teamText) == 0) {
    // If we play BoX > 1 and no match team text was specifically set, overwrite with the map series score:
    IntToString(teamScore, teamText, sizeof(teamText));
  }
  CaptureScoreboardTeamBranding(team);
  // For this specifically, the starting side is the one to use, as the game swaps _1 and _2 cvars itself after
  // halftime.
  Get5Side side = view_as<Get5Side>(g_TeamStartingSide[team]);
  SetTeamInfo(side, g_TeamNames[team], g_TeamFlags[team], g_TeamLogos[team], teamText, teamScore);
}

static void SetOrAddMatchConfigCvar(const char[] cvarName, const char[] cvarValue) {
  int index = g_CvarNames.FindString(cvarName);
  if (index == -1) {
    g_CvarNames.PushString(cvarName);
    g_CvarValues.PushString(cvarValue);
  } else {
    g_CvarValues.SetString(index, cvarValue);
  }
}

static void NormalizeMatchConfigRoundOptions() {
  int clinchIndex = g_CvarNames.FindString("mp_match_can_clinch");
  if (clinchIndex == -1) {
    return;
  }

  char clinchValue[MAX_CVAR_LENGTH];
  g_CvarValues.GetString(clinchIndex, clinchValue, sizeof(clinchValue));
  if (StringToInt(clinchValue) != 0) {
    return;
  }

  int overtimeIndex = g_CvarNames.FindString("mp_overtime_enable");
  if (overtimeIndex != -1) {
    char overtimeValue[MAX_CVAR_LENGTH];
    g_CvarValues.GetString(overtimeIndex, overtimeValue, sizeof(overtimeValue));
    if (StringToInt(overtimeValue) == 0) {
      return;
    }
  }

  LogDebug("Forcing mp_overtime_enable to 0 because mp_match_can_clinch is 0.");
  SetOrAddMatchConfigCvar("mp_overtime_enable", "0");
}

static void ExecuteMatchConfigCvars() {
  // Save the original match cvar values if we haven't already.
  if (g_MatchConfigChangedCvars == INVALID_HANDLE && g_ResetCvarsOnEndCvar.BoolValue) {
    g_MatchConfigChangedCvars = SaveCvars(g_CvarNames);
  }

  char name[MAX_CVAR_LENGTH];
  char value[MAX_CVAR_LENGTH];
  for (int i = 0; i < g_CvarNames.Length; i++) {
    g_CvarNames.GetString(i, name, sizeof(name));
    g_CvarValues.GetString(i, value, sizeof(value));
    ConVar cvar = FindConVar(name);
    if (cvar == null) {
      ServerCommand("%s %s", name, value);
    } else {
      cvar.SetString(value);
    }
  }

  char demoNameFormat[MAX_CVAR_LENGTH];
  g_DemoNameFormatCvar.GetString(demoNameFormat, sizeof(demoNameFormat));
  if (StrEqual(demoNameFormat, "{TIME}_{MATCHID}_map{MAPNUMBER}_{MAPNAME}") ||
      StrEqual(demoNameFormat, "scrim_{TIME}_{MAPNAME}")) {
    g_DemoNameFormatCvar.SetString("pug_{TIME}_{MAPNAME}", false, false);
    LogMessage("Updated legacy get5_demo_name_format to \"pug_{TIME}_{MAPNAME}\" after match cvars were applied.");
  }

  char timeFormat[64];
  g_TimeFormatCvar.GetString(timeFormat, sizeof(timeFormat));
  if (StrEqual(timeFormat, "%Y-%m-%d_%H-%M-%S")) {
    g_TimeFormatCvar.SetString("%Y-%m-%d_%H%M", false, false);
    LogMessage("%s", "Updated legacy get5_time_format to \"%Y-%m-%d_%H%M\" after match cvars were applied.");
  }
}

Action Command_LoadTeam(int client, int args) {
  char arg1[PLATFORM_MAX_PATH];
  char arg2[PLATFORM_MAX_PATH];
  if (args < 2 || !GetCmdArg(1, arg1, sizeof(arg1)) || !GetCmdArg(2, arg2, sizeof(arg2))) {
    ReplyToCommand(client, "%t", "LoadTeamUsage");
    return Plugin_Handled;
  }

  if (g_GameState == Get5State_None) {
    ReplyToCommand(client, "%t", "MatchConfigMustBeLoadedBeforeLoadTeam");
    return Plugin_Handled;
  }

  Get5Team team = Get5Team_None;
  if (StrEqual(arg1, "team1")) {
    team = Get5Team_1;
  } else if (StrEqual(arg1, "team2")) {
    team = Get5Team_2;
    if (g_InScrimMode) {
      ReplyToCommand(client, "%t", "LoadTeamScrimOnlyTeam1OrSpec");
      return Plugin_Handled;
    }
  } else if (StrEqual(arg1, "spec")) {
    team = Get5Team_Spec;
  } else {
    ReplyToCommand(client, "%t", "LoadTeamUnknownTeamArgument");
    return Plugin_Handled;
  }

  char error[PLATFORM_MAX_PATH];
  if (LoadTeamDataFromFile(arg2, team, error)) {
    ReplyToCommand(client, "%t", "LoadedTeamDataFor", arg1);
    SetMatchTeamCvars();
    if (g_CheckAuthsCvar.BoolValue) {
      LOOP_CLIENTS(i) {
        if (IsPlayer(i)) {
          CheckClientTeam(i);
        }
      }
    }
  } else {
    ReplyToCommand(client, error);
  }
  return Plugin_Handled;
}

Action Command_AddPlayer(int client, int args) {
  if (g_GameState == Get5State_None) {
    ReplyToCommand(client, "%t", "NoMatchConfigurationLoaded");
    return Plugin_Handled;
  } else if (g_InScrimMode) {
    ReplyToCommand(client, "%t", "AddPlayerScrimUseRinger");
    return Plugin_Handled;
  } else if (g_DoingBackupRestoreNow || g_GameState == Get5State_PendingRestore) {
    ReplyToCommand(client, "%t", "CannotAddPlayersWaitingBackup");
    return Plugin_Handled;
  } else if (g_PendingSideSwap || InHalftimePhase()) {
    ReplyToCommand(client, "%t", "CannotAddPlayersDuringHalftime");
    return Plugin_Handled;
  }

  char auth[AUTH_LENGTH];
  char teamString[32];
  char name[MAX_NAME_LENGTH];
  if (args >= 2 && GetCmdArg(1, auth, sizeof(auth)) && GetCmdArg(2, teamString, sizeof(teamString))) {
    if (args >= 3) {
      GetCmdArg(3, name, sizeof(name));
    }

    Get5Team team = Get5Team_None;
    if (StrEqual(teamString, "team1")) {
      team = Get5Team_1;
    } else if (StrEqual(teamString, "team2")) {
      team = Get5Team_2;
    } else if (StrEqual(teamString, "spec")) {
      team = Get5Team_Spec;
    } else {
      ReplyToCommand(client, "%t", "UnknownTeamSpecifier");
      return Plugin_Handled;
    }

    if (AddPlayerToTeam(auth, team, name)) {
      ReplyToCommand(client, "%t", "AddedPlayerToTeam", auth, teamString);
    } else {
      ReplyToCommand(client, "%t", "FailedToAddPlayerToTeam", auth, teamString);
    }

  } else {
    ReplyToCommand(client, "%t", "AddPlayerUsage");
  }
  return Plugin_Handled;
}

Action Command_AddKickedPlayer(int client, int args) {
  if (g_GameState == Get5State_None) {
    ReplyToCommand(client, "%t", "NoMatchConfigurationLoaded");
    return Plugin_Handled;
  } else if (g_InScrimMode) {
    ReplyToCommand(client, "%t", "AddKickedPlayerScrimUseRinger");
    return Plugin_Handled;
  } else if (g_DoingBackupRestoreNow || g_GameState == Get5State_PendingRestore) {
    ReplyToCommand(client, "%t", "CannotAddPlayersWaitingBackup");
    return Plugin_Handled;
  } else if (g_PendingSideSwap || InHalftimePhase()) {
    ReplyToCommand(client, "%t", "CannotAddPlayersDuringHalftime");
    return Plugin_Handled;
  }

  if (StrEqual(g_LastKickedPlayerAuth, "")) {
    ReplyToCommand(client, "%t", "NoPlayerKickedYet");
    return Plugin_Handled;
  }

  char teamString[32];
  char name[MAX_NAME_LENGTH];
  if (args >= 1 && GetCmdArg(1, teamString, sizeof(teamString))) {
    if (args >= 2) {
      GetCmdArg(2, name, sizeof(name));
    }

    Get5Team team = Get5Team_None;
    if (StrEqual(teamString, "team1")) {
      team = Get5Team_1;
    } else if (StrEqual(teamString, "team2")) {
      team = Get5Team_2;
    } else if (StrEqual(teamString, "spec")) {
      team = Get5Team_Spec;
    } else {
      ReplyToCommand(client, "%t", "UnknownTeamSpecifier");
      return Plugin_Handled;
    }

    if (AddPlayerToTeam(g_LastKickedPlayerAuth, team, name)) {
      ReplyToCommand(client, "%t", "AddedKickedPlayerToTeam", g_LastKickedPlayerAuth, teamString);
    } else {
      ReplyToCommand(client, "%t", "FailedToAddPlayerToTeam", g_LastKickedPlayerAuth, teamString);
    }

  } else {
    ReplyToCommand(client, "%t", "AddKickedPlayerUsage");
  }
  return Plugin_Handled;
}

Action Command_RemovePlayer(int client, int args) {
  if (g_GameState == Get5State_None) {
    ReplyToCommand(client, "%t", "NoMatchConfigurationLoaded");
    return Plugin_Handled;
  }

  if (g_InScrimMode) {
    ReplyToCommand(client, "%t", "RemovePlayerScrimUseRinger");
    return Plugin_Handled;
  }

  char auth[AUTH_LENGTH];
  if (args >= 1 && GetCmdArg(1, auth, sizeof(auth))) {
    if (RemovePlayerFromTeams(auth)) {
      ReplyToCommand(client, "%t", "RemovedPlayer", auth);
    } else {
      ReplyToCommand(client, "%t", "PlayerAuthNotFoundOrInvalid", auth);
    }
  } else {
    ReplyToCommand(client, "%t", "RemovePlayerUsage");
  }
  return Plugin_Handled;
}

Action Command_RemoveKickedPlayer(int client, int args) {
  if (g_GameState == Get5State_None) {
    ReplyToCommand(client, "%t", "NoMatchConfigurationLoaded");
    return Plugin_Handled;
  }

  if (g_InScrimMode) {
    ReplyToCommand(client, "%t", "RemoveKickedPlayerScrimUseRinger");
    return Plugin_Handled;
  }

  if (StrEqual(g_LastKickedPlayerAuth, "")) {
    ReplyToCommand(client, "%t", "NoPlayerKickedYet");
    return Plugin_Handled;
  }

  if (RemovePlayerFromTeams(g_LastKickedPlayerAuth)) {
    ReplyToCommand(client, "%t", "RemovedKickedPlayer", g_LastKickedPlayerAuth);
  } else {
    ReplyToCommand(client, "%t", "PlayerAuthNotFoundOrInvalid", g_LastKickedPlayerAuth);
  }
  return Plugin_Handled;
}

Action Command_CreateMatch(int client, int args) {
  if (g_GameState != Get5State_None) {
    ReplyToCommand(client, "%t", "CannotCreateMatchAlreadyLoaded");
    return Plugin_Handled;
  }

  // Input/errors
  char error[PLATFORM_MAX_PATH];
  char parameter[PLATFORM_MAX_PATH];
  char value[PLATFORM_MAX_PATH];

  // Match defaults/init values
  int numMaps = CONFIG_NUM_MAPSDEFAULT;
  int playersPerTeam = 0;  // Set based on wingman value
  int coachesPerTeam = CONFIG_COACHESPERTEAM_DEFAULT;
  int mapCount, sidesCount = 0;  // Set from maps file or input
  int minSpectatorsToReady = CONFIG_MINSPECTATORSTOREADY_DEFAULT;
  int minPlayersToReady = CONFIG_MINPLAYERSTOREADY_DEFAULT;
  bool wingman = CONFIG_WINGMAN_DEFAULT;
  bool skipVeto = CONFIG_SKIPVETO_DEFAULT;
  bool scrim = CONFIG_SCRIM_DEFAULT;
  bool clinchSeries = CONFIG_CLINCH_SERIES_DEFAULT;
  bool coachesMustReady = CONFIG_COACHES_MUST_READY_DEFAULT;
  bool useCurrentMap = false;
  char team1Id[64], team2Id[64], maps[16][PLATFORM_MAX_PATH], mapSides[16][16], matchTitle[64],
    matchId[MATCH_ID_LENGTH], scrimAwayTeamName[32];
  char mapPoolKey[64] = DEFAULT_CONFIG_KEY;
  char cVarsKey[64] = DEFAULT_CONFIG_KEY;
  char vetoFirst[16] = CONFIG_VETOFIRST_DEFAULT;
  char sideType[16] = CONFIG_SIDETYPE_DEFAULT;

  // Check all arguments
  for (int i = 1; i <= args; i++) {
    GetCmdArg(i, parameter, sizeof(parameter));
    if (CheckIfStringIsParameter(parameter)) {
      if (strcmp(parameter, "--num_maps", false) == 0 || strcmp(parameter, "-nm", false) == 0) {
        if (!CheckParameterValue(i, parameter, value, sizeof(value), error)) {
          ReplyToCommand(client, error);
          return Plugin_Handled;
        }
        numMaps = StringToInt(value);
        if (numMaps < 1) {
          ReplyToCommand(client, "%t", "ParameterMustBeGreaterThanZeroInt", parameter);
          return Plugin_Handled;
        }
      } else if (strcmp(parameter, "--min_spectators_to_ready", false) == 0 || strcmp(parameter, "-mstr", false) == 0) {
        if (!CheckParameterValue(i, parameter, value, sizeof(value), error)) {
          ReplyToCommand(client, error);
          return Plugin_Handled;
        }
        minSpectatorsToReady = StringToInt(value);
        if (minSpectatorsToReady < 0) {
          ReplyToCommand(client, "%t", "ParameterMustBeNonNegativeInt", parameter);
          return Plugin_Handled;
        }
      } else if (strcmp(parameter, "--min_players_to_ready", false) == 0 || strcmp(parameter, "-mptr", false) == 0) {
        if (!CheckParameterValue(i, parameter, value, sizeof(value), error)) {
          ReplyToCommand(client, error);
          return Plugin_Handled;
        }
        minPlayersToReady = StringToInt(value);
        if (minPlayersToReady < 0) {
          ReplyToCommand(client, "%t", "ParameterMustBeNonNegativeInt", parameter);
          return Plugin_Handled;
        }
      } else if (strcmp(parameter, "--players_per_team", false) == 0 || strcmp(parameter, "-ppt", false) == 0) {
        if (!CheckParameterValue(i, parameter, value, sizeof(value), error)) {
          ReplyToCommand(client, error);
          return Plugin_Handled;
        }
        playersPerTeam = StringToInt(value);
        if (playersPerTeam < 1) {
          ReplyToCommand(client, "%t", "ParameterMustBeGreaterThanZeroInt", parameter);
          return Plugin_Handled;
        }
      } else if (strcmp(parameter, "--coaches_per_team", false) == 0 || strcmp(parameter, "-cpt", false) == 0) {
        if (!CheckParameterValue(i, parameter, value, sizeof(value), error)) {
          ReplyToCommand(client, error);
          return Plugin_Handled;
        }
        coachesPerTeam = StringToInt(value);
        if (coachesPerTeam < 0) {
          ReplyToCommand(client, "%t", "ParameterMustBeNonNegativeInt", parameter);
          return Plugin_Handled;
        }
      } else if (strcmp(parameter, "--wingman", false) == 0 || strcmp(parameter, "-w", false) == 0) {
        wingman = true;
      } else if (strcmp(parameter, "--no_series_clinch", false) == 0 || strcmp(parameter, "-nsc", false) == 0) {
        clinchSeries = false;
      } else if (strcmp(parameter, "--coaches_must_ready", false) == 0 || strcmp(parameter, "-cmr", false) == 0) {
        coachesMustReady = true;
      } else if (strcmp(parameter, "--scrim", false) == 0 || strcmp(parameter, "-s", false) == 0) {
        scrim = true;
        if (CheckParameterValue(i, parameter, value, sizeof(value), error)) {
          strcopy(scrimAwayTeamName, sizeof(scrimAwayTeamName), value);
        }
      } else if (strcmp(parameter, "--current_map", false) == 0 || strcmp(parameter, "-cm", false) == 0) {
        useCurrentMap = true;
      } else if (strcmp(parameter, "--skip_veto", false) == 0 || strcmp(parameter, "-sv", false) == 0) {
        skipVeto = true;
      } else if (strcmp(parameter, "--matchid", false) == 0 || strcmp(parameter, "-id", false) == 0) {
        if (!CheckParameterValue(i, parameter, value, sizeof(value), error)) {
          ReplyToCommand(client, error);
          return Plugin_Handled;
        }
        strcopy(matchId, sizeof(matchId), value);
      } else if (strcmp(parameter, "--match_title", false) == 0 || strcmp(parameter, "-mt", false) == 0) {
        if (!CheckParameterValue(i, parameter, value, sizeof(value), error)) {
          ReplyToCommand(client, error);
          return Plugin_Handled;
        }
        strcopy(matchTitle, sizeof(matchTitle), value);
      } else if (strcmp(parameter, "--map_pool", false) == 0 || strcmp(parameter, "-mp", false) == 0) {
        if (!CheckParameterValue(i, parameter, value, sizeof(value), error)) {
          ReplyToCommand(client, error);
          return Plugin_Handled;
        }
        strcopy(mapPoolKey, sizeof(mapPoolKey), value);
      } else if (strcmp(parameter, "--cvars", false) == 0 || strcmp(parameter, "-cv", false) == 0) {
        if (!CheckParameterValue(i, parameter, value, sizeof(value), error)) {
          ReplyToCommand(client, error);
          return Plugin_Handled;
        }
        strcopy(cVarsKey, sizeof(cVarsKey), value);
      } else if (strcmp(parameter, "--veto_first", false) == 0 || strcmp(parameter, "-vf", false) == 0) {
        if (!CheckParameterValue(i, parameter, value, sizeof(value), error)) {
          ReplyToCommand(client, error);
          return Plugin_Handled;
        }
        Get5VetoFirst v = VetoFirstFromString(value, error);
        if (v == Get5VetoFirst_Invalid) {
          ReplyToCommand(client, "%t", "CommandParameterError", parameter, error);
          return Plugin_Handled;
        }
        strcopy(vetoFirst, sizeof(vetoFirst), value);
      } else if (strcmp(parameter, "--side_type", false) == 0 || strcmp(parameter, "-st", false) == 0) {
        if (!CheckParameterValue(i, parameter, value, sizeof(value), error)) {
          ReplyToCommand(client, error);
          return Plugin_Handled;
        }
        MatchSideType t = MatchSideTypeFromString(value, error);
        if (t == MatchSideType_Invalid) {
          ReplyToCommand(client, "%t", "CommandParameterError", parameter, error);
          return Plugin_Handled;
        }
        strcopy(sideType, sizeof(sideType), value);
      } else if (strcmp(parameter, "--team1", false) == 0 || strcmp(parameter, "-t1", false) == 0) {
        if (!CheckParameterValue(i, parameter, value, sizeof(value), error)) {
          ReplyToCommand(client, error);
          return Plugin_Handled;
        }
        strcopy(team1Id, sizeof(team1Id), value);
      } else if (strcmp(parameter, "--team2", false) == 0 || strcmp(parameter, "-t2", false) == 0) {
        if (!CheckParameterValue(i, parameter, value, sizeof(value), error)) {
          ReplyToCommand(client, error);
          return Plugin_Handled;
        }
        strcopy(team2Id, sizeof(team2Id), value);
      } else if (strcmp(parameter, "--maplist", false) == 0 || strcmp(parameter, "-ml", false) == 0) {
        if (!CheckParameterValue(i, parameter, value, sizeof(value), error)) {
          ReplyToCommand(client, error);
          return Plugin_Handled;
        }
        mapCount = ExplodeString(value, ",", maps, 16, PLATFORM_MAX_PATH, true);
        for (int mi = 0; mi < mapCount; mi++) {
          if (!IsMapValid(maps[mi]) && !IsMapWorkshop(maps[mi])) {
            ReplyToCommand(client, "%t", "MapIsNotValid", maps[mi]);
            return Plugin_Handled;
          }
        }
      } else if (strcmp(parameter, "--map_sides", false) == 0 || strcmp(parameter, "-ms", false) == 0) {
        if (!CheckParameterValue(i, parameter, value, sizeof(value), error)) {
          ReplyToCommand(client, error);
          return Plugin_Handled;
        }
        sidesCount = ExplodeString(value, ",", mapSides, 16, PLATFORM_MAX_PATH, true);
        for (int mi = 0; mi < sidesCount; mi++) {
          if (SideChoiceFromString(mapSides[mi], error) == SideChoice_Invalid) {
            ReplyToCommand(client, "%t", "CommandParameterError", parameter, error);
            return Plugin_Handled;
          }
        }
      } else {
        ReplyToCommand(client, "%t", "UnknownParameter", parameter);
        return Plugin_Handled;
      }
    }
  }
  if (mapCount > 0 && mapCount < numMaps) {
    ReplyToCommand(client, "%t", "NumMapsCannotExceedMaplist");
    return Plugin_Handled;
  }

  // Veto requires mapCount > numMaps.
  if (numMaps == mapCount) {
    skipVeto = true;
  }

  bool hasTeam1 = strlen(team1Id) > 0;
  bool hasTeam2 = strlen(team2Id) > 0;

  if (hasTeam1 && !scrim && !hasTeam2) {
    ReplyToCommand(client, "%t", "Team2OrScrimRequiredWhenTeam1Provided");
    return Plugin_Handled;
  } else if (!hasTeam1 && (hasTeam2 || scrim)) {
    ReplyToCommand(client, "%t", "Team1RequiredWhenTeam2OrScrimProvided");
    return Plugin_Handled;
  } else if (hasTeam1 && hasTeam2 && scrim) {
    ReplyToCommand(client, "%t", "ScrimCannotCombineBothTeams");
    return Plugin_Handled;
  }

  if (hasTeam1 && hasTeam2 && strcmp(team1Id, team2Id) == 0) {
    ReplyToCommand(client, "%t", "TeamsCannotBeIdentical");
    return Plugin_Handled;
  }

  if (useCurrentMap) {
    if (mapCount > 0) {
      ReplyToCommand(client, "%t", "CurrentMapCannotCombineMaplist");
      return Plugin_Handled;
    }
    if (numMaps > 1) {
      ReplyToCommand(client, "%t", "CurrentMapCannotCombineNumMaps");
      return Plugin_Handled;
    }
  }

  // Default depending on wingman switch.
  if (playersPerTeam == 0) {
    playersPerTeam = wingman ? CONFIG_PLAYERSPERTEAM_DEFAULT_WM : CONFIG_PLAYERSPERTEAM_DEFAULT;
  }

  JSON_Array mapsArray;
  if (mapCount > 0) {
    mapsArray = new JSON_Array();
    for (int i = 0; i < mapCount; i++) {
      mapsArray.PushString(maps[i]);
    }
  } else if (useCurrentMap) {
    mapsArray = new JSON_Array();
    char mapName[PLATFORM_MAX_PATH];
    GetCurrentMap(mapName, sizeof(mapName));
    mapsArray.PushString(mapName);
  } else {
    JSON_Object mapsObject = LoadMapsFile(error);
    if (mapsObject == null) {
      ReplyToCommand(client, "%t", "FailedLoadMapsFile", error);
      return Plugin_Handled;
    }
    // Copy the array under the provided key, then delete the source object.
    JSON_Array mapsFromKey = view_as<JSON_Array>(mapsObject.GetObject(mapPoolKey)).DeepCopy();
    json_cleanup_and_delete(mapsObject);
    mapCount = mapsFromKey.Length;
    if (numMaps > mapCount) {
      ReplyToCommand(client, "%t", "SeriesMapsExceedPool", numMaps, mapCount);
      json_cleanup_and_delete(mapsFromKey);
      return Plugin_Handled;
    }
    mapsArray = mapsFromKey;
  }

  JSON_Object cvars = LoadCvarsFile(error, cVarsKey);
  if (cvars == null) {
    json_cleanup_and_delete(mapsArray);
    ReplyToCommand(client, "%t", "CvarsArgumentError", error);
    return Plugin_Handled;
  }

  JSON_Object matchConfig = new JSON_Object();
  matchConfig.SetObject("maplist", mapsArray);
  if (strlen(matchId) > 0) {
    matchConfig.SetString("matchid", matchId);
  }

  if (cvars.Length > 0) {
    matchConfig.SetObject("cvars", cvars);
  } else {
    json_cleanup_and_delete(cvars);
  }

  if (sidesCount > 0) {
    JSON_Array sidesArray = new JSON_Array();
    for (int i = 0; i < sidesCount; i++) {
      sidesArray.PushString(mapSides[i]);
    }
    matchConfig.SetObject("map_sides", sidesArray);
  }

  // If neither team is provided, use current teams.
  if (!hasTeam1 && !hasTeam2) {
    JSON_Object team1 = GetTeamObjectFromCurrentPlayers(Get5Side_CT);
    JSON_Object team2 = GetTeamObjectFromCurrentPlayers(Get5Side_T);
    matchConfig.SetObject("team1", team1);
    matchConfig.SetObject("team2", team2);
  } else {
    JSON_Object teams = LoadTeamsFile(error);
    if (teams == null) {
      ReplyToCommand(client, "%t", "FailedLoadTeamsError", error);
      json_cleanup_and_delete(matchConfig);
      return Plugin_Handled;
    }
    bool foundTeam1 = false;
    bool foundTeam2 = false;
    int l = teams.Length;
    int keyLength = 0;
    for (int i = 0; i < l; i++) {
      keyLength = teams.GetKeySize(i);
      char[] key = new char[keyLength];
      teams.GetKey(i, key, keyLength);
      JSON_Object team = teams.GetObject(key);
      if (strcmp(key, team1Id) == 0) {
        matchConfig.SetObject("team1", team.DeepCopy());
        foundTeam1 = true;
      } else if (strcmp(key, team2Id) == 0) {
        matchConfig.SetObject("team2", team.DeepCopy());
        foundTeam2 = true;
      }
    }
    json_cleanup_and_delete(teams);
    if (!foundTeam1 || (!scrim && !foundTeam2)) {
      json_cleanup_and_delete(matchConfig);
      ReplyToCommand(client, "%t", "TeamNotFoundInTeamsFile", !foundTeam1 ? team1Id : team2Id);
      return Plugin_Handled;
    }
    if (scrim && strlen(scrimAwayTeamName)) {
      JSON_Object team2 = new JSON_Object();
      team2.SetString("name", scrimAwayTeamName);
      matchConfig.SetObject("team2", team2);
    }
  }
  if (strlen(matchTitle) > 0) {
    matchConfig.SetString("match_title", matchTitle);
  }
  matchConfig.SetString("veto_first", vetoFirst);
  matchConfig.SetString("side_type", sideType);
  matchConfig.SetBool("clinch_series", clinchSeries);
  matchConfig.SetBool("coaches_must_ready", coachesMustReady);
  matchConfig.SetBool("wingman", wingman);
  matchConfig.SetBool("scrim", scrim);
  matchConfig.SetBool("skip_veto", skipVeto);
  matchConfig.SetInt("players_per_team", playersPerTeam);
  matchConfig.SetInt("coaches_per_team", coachesPerTeam);
  matchConfig.SetInt("num_maps", numMaps);
  matchConfig.SetInt("min_spectators_to_ready", minSpectatorsToReady);
  matchConfig.SetInt("min_players_to_ready", minPlayersToReady);

  char serverId[SERVER_ID_LENGTH];
  g_ServerIdCvar.GetString(serverId, sizeof(serverId));
  char path[PLATFORM_MAX_PATH];
  FormatEx(path, sizeof(path), TEMP_MATCHCONFIG_JSON, serverId);

  matchConfig.WriteToFile(path);
  json_cleanup_and_delete(matchConfig);

  if (!LoadMatchConfig(path, error)) {
    ReplyToCommand(client, error);
  } else {
    DeleteFileIfExists(path);
  }
  return Plugin_Handled;
}

static CheckIfStringIsParameter(const char[] string) {
  return StrContains(string, "-", false) == 0;
}

static bool CheckParameterValue(const int index, const char[] parameter, char[] buffer, const int bufferSize,
                                char[] error) {
  if (!GetCmdArg(index + 1, buffer, bufferSize) || CheckIfStringIsParameter(buffer)) {
    FormatEx(error, PLATFORM_MAX_PATH, "参数“%s”需要提供值。(Parameter '%s' expects a value.)", parameter, parameter);
    return false;
  }
  return true;
}

Action Command_CreateScrim(int client, int args) {
  if (g_GameState != Get5State_None) {
    ReplyToCommand(client, "%t", "CannotCreateScrimAlreadyLoaded");
    return Plugin_Handled;
  }

  char matchid[MATCH_ID_LENGTH] = "scrim";
  char matchMap[PLATFORM_MAX_PATH];
  GetCurrentMap(matchMap, sizeof(matchMap));
  char otherTeamName[MAX_CVAR_LENGTH] = "Away";

  if (args >= 1) {
    GetCmdArg(1, otherTeamName, sizeof(otherTeamName));
  }
  if (args >= 2) {
    GetCmdArg(2, matchMap, sizeof(matchMap));
    if (!IsMapValid(matchMap)) {
      ReplyToCommand(client, "%t", "InvalidMap", matchMap);
      return Plugin_Handled;
    }
  }
  if (args >= 3) {
    GetCmdArg(3, matchid, sizeof(matchid));
  }

  char path[PLATFORM_MAX_PATH];
  FormatEx(path, sizeof(path), "get5_%s.cfg", matchid);
  DeleteFileIfExists(path);

  KeyValues kv = new KeyValues("Match");
  kv.SetString("matchid", matchid);
  kv.SetNum("scrim", 1);
  kv.JumpToKey("maplist", true);
  EscapeKeyValueKeyWrite(matchMap, sizeof(matchMap));
  kv.SetString(matchMap, KEYVALUE_STRING_PLACEHOLDER);
  kv.GoBack();

  char templateFile[PLATFORM_MAX_PATH + 1];
  BuildPath(Path_SM, templateFile, sizeof(templateFile), "configs/get5/scrim_template.cfg");
  if (!kv.ImportFromFile(templateFile)) {
    delete kv;
    ReplyToCommand(client, "%t", "FailedReadScrimTemplate", templateFile);
    return Plugin_Handled;
  }
  // Because we read the field and write it again, then load it as a match config, we have to make
  // sure empty strings are not being skipped.
  if (kv.JumpToKey("team1") && kv.JumpToKey("players") && kv.GotoFirstSubKey(false)) {
    char name[MAX_NAME_LENGTH];
    do {
      WritePlaceholderInsteadOfEmptyString(kv, name, sizeof(name));
    } while (kv.GotoNextKey(false));
    kv.Rewind();
  } else {
    delete kv;
    ReplyToCommand(client, "%t", "ScrimTemplateMissingTeam1Players");
    return Plugin_Handled;
  }

  // Allow spectators in scrim template.
  if (kv.JumpToKey("spectators") && kv.JumpToKey("players") && kv.GotoFirstSubKey(false)) {
    char name[MAX_NAME_LENGTH];
    do {
      WritePlaceholderInsteadOfEmptyString(kv, name, sizeof(name));
    } while (kv.GotoNextKey(false));
  }
  kv.Rewind();

  // Also ensure empty string values in cvars get printed to the match config.
  if (kv.JumpToKey("cvars")) {
    if (kv.GotoFirstSubKey(false)) {
      char cVarValue[MAX_CVAR_LENGTH];
      do {
        WritePlaceholderInsteadOfEmptyString(kv, cVarValue, sizeof(cVarValue));
      } while (kv.GotoNextKey(false));
    }
  }
  kv.Rewind();

  kv.JumpToKey("team2", true);
  kv.SetString("name", otherTeamName);
  kv.GoBack();

  if (!kv.ExportToFile(path)) {
    ReplyToCommand(client, "%t", "FailedWriteScrimConfig", path);
  } else {
    char error[PLATFORM_MAX_PATH];
    if (!LoadMatchConfig(path, error)) {
      ReplyToCommand(client, error);
    }
  }
  delete kv;
  return Plugin_Handled;
}

Action Command_Ringer(int client, int args) {
  if (g_GameState == Get5State_None || !g_InScrimMode) {
    ReplyToCommand(client, "%t", "CommandOnlyInScrimMode");
    return Plugin_Handled;
  }

  char arg1[32];
  if (args >= 1 && GetCmdArg(1, arg1, sizeof(arg1))) {
    int target = FindTarget(client, arg1, true, false);
    if (IsAuthedPlayer(target)) {
      SwapScrimTeamStatus(target);
    } else {
      ReplyToCommand(client, "%t", "PlayerNotFound");
    }
  } else {
    ReplyToCommand(client, "%t", "SmRingerUsage");
  }

  return Plugin_Handled;
}

JSON_Object GetTeamObjectFromCurrentPlayers(const Get5Side side, int forcedCaptainClient = 0) {
  JSON_Object teamObject = new JSON_Object();
  JSON_Array players = new JSON_Array();

  bool first = true;
  char teamName[64] = "";
  char auth[AUTH_LENGTH];
  // If forcing a captain, find that player first. We have to loop twice because JSON doesn't support anything
  // that would easily allow us to swap the captain to index 0.
  if (forcedCaptainClient > 0) {
    LOOP_CLIENTS(i) {
      if (i == forcedCaptainClient) {
        if (CheckIfClientIsOnSide(i, side, false) && GetAuth(i, auth, sizeof(auth))) {
          if (g_SetGameTeamNamesCvar.BoolValue) {
            SetTeamNameFromClient(i, teamName, sizeof(teamName));
          }
          players.PushString(auth);
          first = false;
        }
        break;
      }
    }
  }
  LOOP_CLIENTS(i) {
    if (forcedCaptainClient == i) {
      // Already added above.
      continue;
    }
    if (CheckIfClientIsOnSide(i, side, false) && GetAuth(i, auth, sizeof(auth))) {
      players.PushString(auth);
      if (first && side != Get5Side_Spec && g_SetGameTeamNamesCvar.BoolValue) {
        SetTeamNameFromClient(i, teamName, sizeof(teamName));
      }
      first = false;
    }
  }
  if (strlen(teamName) == 0 && side != Get5Side_Spec && g_SetGameTeamNamesCvar.BoolValue) {
    SetTeamNameFromSideClient(side, teamName, sizeof(teamName));
  }
  if (strlen(teamName) > 0) {
    teamObject.SetString("name", teamName);
  }
  teamObject.SetObject("players", players);
  if (side != Get5Side_Spec) {
    AddCoachesToAuthJSON(teamObject, side);
  }
  return teamObject;
}

static void AddCoachesToAuthJSON(const JSON_Object json, const Get5Side side) {
  JSON_Array coaches;
  char auth[AUTH_LENGTH];
  LOOP_CLIENTS(i) {
    if (CheckIfClientIsOnSide(i, side, true) && GetAuth(i, auth, sizeof(auth))) {
      if (coaches == null) {
        coaches = new JSON_Array();
      }
      coaches.PushString(auth);
    }
  }
  if (coaches) {
    json.SetObject("coaches", coaches);
  }
}

static void SetTeamNameFromClient(const int client, char[] teamName, const int teamNameLength) {
  FormatEx(teamName, teamNameLength, "team_%N", client);
}

static void SetTeamNameFromSideClient(const Get5Side side, char[] teamName, const int teamNameLength) {
  LOOP_CLIENTS(i) {
    if (!IsValidClient(i) || IsClientSourceTV(i) || IsClientReplay(i)) {
      continue;
    }
    if (view_as<Get5Side>(GetClientTeam(i)) == side) {
      SetTeamNameFromClient(i, teamName, teamNameLength);
      return;
    }
  }
}

static bool CheckIfClientIsOnSide(const int client, const Get5Side side, const bool coaching) {
  if (!IsAuthedPlayer(client)) {
    return false;
  }
  Get5Side currentSide = coaching ? GetClientCoachingSide(client) : view_as<Get5Side>(GetClientTeam(client));
  return currentSide == side;
}

static int GetTeamConfigIndex(const Get5Side side) {
  return (side == Get5Side_CT) ? 1 : 2;
}

static void FormatTeamConfigCvarNames(const int teamIndex, char[] teamCvarName, int teamCvarNameLength,
                                      char[] textCvarName, int textCvarNameLength, char[] scoreCvarName,
                                      int scoreCvarNameLength) {
  FormatEx(teamCvarName, teamCvarNameLength, "mp_teamname_%d", teamIndex);
  FormatEx(textCvarName, textCvarNameLength, "mp_teammatchstat_%d", teamIndex);
  FormatEx(scoreCvarName, scoreCvarNameLength, "mp_teamscore_%d", teamIndex);
}

static void FormatTeamBrandingCvarNames(const int teamIndex, char[] flagCvarName, int flagCvarNameLength,
                                        char[] logoCvarName, int logoCvarNameLength) {
  FormatEx(flagCvarName, flagCvarNameLength, "mp_teamflag_%d", teamIndex);
  FormatEx(logoCvarName, logoCvarNameLength, "mp_teamlogo_%d", teamIndex);
}

static bool GetScoreboardTeamName(const Get5Team team, char[] buffer, int bufferLength) {
  if (team != Get5Team_1 && team != Get5Team_2) {
    return false;
  }

  Get5Side side = view_as<Get5Side>(g_TeamStartingSide[team]);
  if (side != Get5Side_CT && side != Get5Side_T) {
    side = view_as<Get5Side>(g_TeamSide[team]);
  }
  if (side != Get5Side_CT && side != Get5Side_T) {
    return false;
  }

  char teamCvarName[MAX_CVAR_LENGTH];
  FormatEx(teamCvarName, sizeof(teamCvarName), "mp_teamname_%d", GetTeamConfigIndex(side));
  GetConVarStringSafe(teamCvarName, buffer, bufferLength);
  TrimString(buffer);
  return strlen(buffer) > 0;
}

static bool GetScoreboardTeamBranding(const Get5Team team, char[] flagBuffer, int flagBufferLength,
                                      char[] logoBuffer, int logoBufferLength) {
  if (team != Get5Team_1 && team != Get5Team_2) {
    return false;
  }

  Get5Side side = view_as<Get5Side>(g_TeamStartingSide[team]);
  if (side != Get5Side_CT && side != Get5Side_T) {
    side = view_as<Get5Side>(g_TeamSide[team]);
  }
  if (side != Get5Side_CT && side != Get5Side_T) {
    return false;
  }

  char flagCvarName[MAX_CVAR_LENGTH];
  char logoCvarName[MAX_CVAR_LENGTH];
  FormatTeamBrandingCvarNames(GetTeamConfigIndex(side), flagCvarName, sizeof(flagCvarName), logoCvarName,
                              sizeof(logoCvarName));
  GetConVarStringSafe(flagCvarName, flagBuffer, flagBufferLength);
  GetConVarStringSafe(logoCvarName, logoBuffer, logoBufferLength);
  TrimString(flagBuffer);
  TrimString(logoBuffer);
  return strlen(flagBuffer) > 0 || strlen(logoBuffer) > 0;
}

static void CaptureScoreboardTeamBranding(const Get5Team team) {
  if (team != Get5Team_1 && team != Get5Team_2 ||
      strlen(g_TeamFlags[team]) > 0 && strlen(g_TeamLogos[team]) > 0) {
    return;
  }

  char scoreboardFlag[MAX_CVAR_LENGTH];
  char scoreboardLogo[MAX_CVAR_LENGTH];
  if (!GetScoreboardTeamBranding(team, scoreboardFlag, sizeof(scoreboardFlag), scoreboardLogo,
                                 sizeof(scoreboardLogo))) {
    return;
  }

  if (strlen(g_TeamFlags[team]) == 0 && strlen(scoreboardFlag) > 0) {
    strcopy(g_TeamFlags[team], MAX_CVAR_LENGTH, scoreboardFlag);
  }
  if (strlen(g_TeamLogos[team]) == 0 && strlen(scoreboardLogo) > 0) {
    strcopy(g_TeamLogos[team], MAX_CVAR_LENGTH, scoreboardLogo);
  }
}

static void CaptureScoreboardTeamDisplayName(const Get5Team team) {
  if (g_SetGameTeamNamesCvar.BoolValue || team != Get5Team_1 && team != Get5Team_2 ||
      strlen(g_TeamDisplayNames[team]) > 0) {
    return;
  }

  char scoreboardTeamName[MAX_CVAR_LENGTH];
  if (GetScoreboardTeamName(team, scoreboardTeamName, sizeof(scoreboardTeamName))) {
    strcopy(g_TeamDisplayNames[team], MAX_CVAR_LENGTH, scoreboardTeamName);
  }
}

static void SyncScoreboardTeamNames() {
  if (g_SetGameTeamNamesCvar.BoolValue) {
    return;
  }

  CaptureScoreboardTeamDisplayName(Get5Team_1);
  CaptureScoreboardTeamDisplayName(Get5Team_2);

  LOOP_TEAMS(team) {
    if (strlen(g_TeamDisplayNames[team]) == 0) {
      continue;
    }

    Get5Side side = view_as<Get5Side>(g_TeamStartingSide[team]);
    if (side != Get5Side_CT && side != Get5Side_T) {
      side = view_as<Get5Side>(g_TeamSide[team]);
    }
    if (side != Get5Side_CT && side != Get5Side_T) {
      continue;
    }

    char teamCvarName[MAX_CVAR_LENGTH];
    FormatEx(teamCvarName, sizeof(teamCvarName), "mp_teamname_%d", GetTeamConfigIndex(side));
    SetConVarStringSafe(teamCvarName, g_TeamDisplayNames[team]);
  }
}

void GetTeamDisplayName(const Get5Team team, char[] buffer, int bufferLength) {
  if (!g_SetGameTeamNamesCvar.BoolValue && team != Get5Team_Spec) {
    CaptureScoreboardTeamDisplayName(team);
    if (strlen(g_TeamDisplayNames[team]) > 0) {
      strcopy(buffer, bufferLength, g_TeamDisplayNames[team]);
      return;
    }
  }

  if (GetScoreboardTeamName(team, buffer, bufferLength)) {
    return;
  }

  if (strlen(g_TeamNames[team]) > 0) {
    strcopy(buffer, bufferLength, g_TeamNames[team]);
    return;
  }

  GetTeamString(team, buffer, bufferLength);
}

static void FormatTaggedTeamName(const Get5Side side, const char[] name, char[] taggedName, int taggedNameLength) {
  strcopy(taggedName, taggedNameLength, name);

  if (!g_ReadyTeamTagCvar.BoolValue || !IsReadyGameState()) {
    return;
  }

  Get5Team matchTeam = CSTeamToGet5Team(view_as<int>(side));
  if (IsTeamReady(matchTeam)) {
    FormatEx(taggedName, taggedNameLength, "%s %T", name, "ReadyTag", LANG_SERVER);
  } else {
    FormatEx(taggedName, taggedNameLength, "%s %T", name, "NotReadyTag", LANG_SERVER);
  }

  TrimString(taggedName);
}

static void ResetTeamConfigSlot(const int teamIndex) {
  char teamCvarName[MAX_CVAR_LENGTH];
  char textCvarName[MAX_CVAR_LENGTH];
  char scoreCvarName[MAX_CVAR_LENGTH];
  char flagCvarName[MAX_CVAR_LENGTH];
  char logoCvarName[MAX_CVAR_LENGTH];
  FormatTeamConfigCvarNames(teamIndex, teamCvarName, sizeof(teamCvarName), textCvarName, sizeof(textCvarName),
                            scoreCvarName, sizeof(scoreCvarName));
  FormatTeamBrandingCvarNames(teamIndex, flagCvarName, sizeof(flagCvarName), logoCvarName, sizeof(logoCvarName));

  if (g_SetGameTeamNamesCvar.BoolValue) {
    SetConVarStringSafe(teamCvarName, "");
  }

  SetConVarStringSafe(flagCvarName, "");
  SetConVarStringSafe(logoCvarName, "");
  SetConVarStringSafe(textCvarName, "");
  SetConVarStringSafe(scoreCvarName, "");
}

void SetTeamInfo(const Get5Side side, const char[] name, const char[] flag, const char[] logo, const char[] matchstat,
                 int series_score) {
  int teamIndex = GetTeamConfigIndex(side);

  char teamCvarName[MAX_CVAR_LENGTH];
  char textCvarName[MAX_CVAR_LENGTH];
  char scoreCvarName[MAX_CVAR_LENGTH];
  char flagCvarName[MAX_CVAR_LENGTH];
  char logoCvarName[MAX_CVAR_LENGTH];
  FormatTeamConfigCvarNames(teamIndex, teamCvarName, sizeof(teamCvarName), textCvarName, sizeof(textCvarName),
                            scoreCvarName, sizeof(scoreCvarName));
  FormatTeamBrandingCvarNames(teamIndex, flagCvarName, sizeof(flagCvarName), logoCvarName, sizeof(logoCvarName));

  if (g_SetGameTeamNamesCvar.BoolValue) {
    char taggedName[MAX_CVAR_LENGTH];
    FormatTaggedTeamName(side, name, taggedName, sizeof(taggedName));
    SetConVarStringSafe(teamCvarName, taggedName);
  }

  SetConVarStringSafe(flagCvarName, flag);
  SetConVarStringSafe(logoCvarName, logo);
  SetConVarStringSafe(textCvarName, matchstat);

  // We do this because IntValue = 0 does not consistently set an empty string, relevant for testing.
  if (g_MapsToWin > 1 && series_score > 0) {
    SetConVarIntSafe(scoreCvarName, series_score);
  } else {
    SetConVarStringSafe(scoreCvarName, "");
  }
}

void CheckTeamNameStatus(Get5Team team) {
  if (StrEqual(g_TeamNames[team], "") && team != Get5Team_Spec && g_SetGameTeamNamesCvar.BoolValue) {
    LOOP_CLIENTS(i) {
      if (IsAuthedPlayer(i)) {
        if (GetClientMatchTeam(i) == team) {
          SetTeamNameFromClient(i, g_TeamNames[team], MAX_CVAR_LENGTH);
          if (team == Get5Team_1) {
            if (g_StatsKv.JumpToKey("team1")) {
              g_StatsKv.SetString(STAT_SERIES_TEAM_NAME, g_TeamNames[team]);
              g_StatsKv.GoBack();
            }
          } else if (team == Get5Team_2) {
            if (g_StatsKv.JumpToKey("team2")) {
              g_StatsKv.SetString(STAT_SERIES_TEAM_NAME, g_TeamNames[team]);
              g_StatsKv.GoBack();
            }
          }
          break;
        }
      }
    }
    if (StrEqual(g_TeamNames[team], "")) {
      SetTeamNameFromSideClient(view_as<Get5Side>(Get5TeamToCSTeam(team)), g_TeamNames[team], MAX_CVAR_LENGTH);
      if (!StrEqual(g_TeamNames[team], "")) {
        if (team == Get5Team_1) {
          if (g_StatsKv.JumpToKey("team1")) {
            g_StatsKv.SetString(STAT_SERIES_TEAM_NAME, g_TeamNames[team]);
            g_StatsKv.GoBack();
          }
        } else if (team == Get5Team_2) {
          if (g_StatsKv.JumpToKey("team2")) {
            g_StatsKv.SetString(STAT_SERIES_TEAM_NAME, g_TeamNames[team]);
            g_StatsKv.GoBack();
          }
        }
      }
    }
  }
  FormatTeamName(team);
}

void ExecCfg(ConVar cvar) {
  char cfg[PLATFORM_MAX_PATH];
  cvar.GetString(cfg, sizeof(cfg));
  ServerCommand("exec \"%s\"", cfg);
  g_MatchConfigExecTimer = CreateTimer(0.1, Timer_ExecMatchConfig);
}

static Action Timer_ExecMatchConfig(Handle timer) {
  if (timer != g_MatchConfigExecTimer) {
    LogDebug("Ignoring exec callback as timer handle was incorrect.");
    // This prevents multiple calls to this function from stacking the calls.
    return Plugin_Handled;
  }
  // When we load config files using ServerCommand("exec") above, which is async, we want match
  // config cvars to always override.
  if (g_GameState != Get5State_None) {
    ExecuteMatchConfigCvars();
    SetMatchTeamCvars();
  }
  g_MatchConfigExecTimer = INVALID_HANDLE;
  return Plugin_Handled;
}

void ResetTeamConfigs() {
  for (int teamIndex = 1; teamIndex <= 2; teamIndex++) {
    ResetTeamConfigSlot(teamIndex);
  }

  g_TeamDisplayNames[Get5Team_1] = "";
  g_TeamDisplayNames[Get5Team_2] = "";
}

static bool FormatHostnameString(char[] buffer, int bufferLength) {
  g_SetHostnameCvar.GetString(buffer, bufferLength);
  if (StrEqual(buffer, "")) {
    return false;
  }

  char mapName[PLATFORM_MAX_PATH];
  GetCleanMapName(mapName, sizeof(mapName));

  char timeFormat[64];
  char dateFormat[64];
  g_TimeFormatCvar.GetString(timeFormat, sizeof(timeFormat));
  g_DateFormatCvar.GetString(dateFormat, sizeof(dateFormat));
  int timeStamp = GetTime();
  char formattedTime[64];
  char formattedDate[64];
  FormatTime(formattedTime, sizeof(formattedTime), timeFormat, timeStamp);
  FormatTime(formattedDate, sizeof(formattedDate), dateFormat, timeStamp);

  char team1DisplayName[MAX_CVAR_LENGTH];
  char team2DisplayName[MAX_CVAR_LENGTH];
  GetTeamDisplayName(Get5Team_1, team1DisplayName, sizeof(team1DisplayName));
  GetTeamDisplayName(Get5Team_2, team2DisplayName, sizeof(team2DisplayName));

  char serverId[SERVER_ID_LENGTH];
  g_ServerIdCvar.GetString(serverId, sizeof(serverId));

  ReplaceString(buffer, bufferLength, "{MATCHTITLE}", g_MatchTitle);
  ReplaceString(buffer, bufferLength, "{DATE}", formattedDate);
  ReplaceStringWithInt(buffer, bufferLength, "{MAPNUMBER}", Get5_GetMapNumber() + 1);
  ReplaceStringWithInt(buffer, bufferLength, "{MAXMAPS}", g_NumberOfMapsInSeries);
  ReplaceString(buffer, bufferLength, "{MATCHID}", g_MatchID);
  ReplaceString(buffer, bufferLength, "{MAPNAME}", mapName);
  ReplaceString(buffer, bufferLength, "{SERVERID}", serverId);
  ReplaceString(buffer, bufferLength, "{TIME}", formattedTime);
  ReplaceString(buffer, bufferLength, "{TEAM1}", team1DisplayName);
  ReplaceString(buffer, bufferLength, "{TEAM2}", team2DisplayName);

  int team1Score = 0;
  int team2Score = 0;
  if (g_GameState == Get5State_Live) {
    Get5Side team1Side = view_as<Get5Side>(Get5TeamToCSTeam(Get5Team_1));
    Get5Side team2Side = view_as<Get5Side>(Get5TeamToCSTeam(Get5Team_2));
    if (team1Side != Get5Side_None && team2Side != Get5Side_None) {
      team1Score = CS_GetTeamScore(view_as<int>(team1Side));
      team2Score = CS_GetTeamScore(view_as<int>(team2Side));
    }
  }
  ReplaceStringWithInt(buffer, bufferLength, "{TEAM1_SCORE}", team1Score);
  ReplaceStringWithInt(buffer, bufferLength, "{TEAM2_SCORE}", team2Score);

  return true;
}

void UpdateHostname() {
  char formattedHostname[128];
  if (FormatHostnameString(formattedHostname, sizeof(formattedHostname))) {
    SetConVarStringSafe("hostname", formattedHostname);
  }
}

void SetCorrectGameMode() {
  SetGameMode(g_Wingman ? GAME_MODE_WINGMAN : GAME_MODE_COMPETITIVE);
  SetGameTypeClassic();
}

bool IsMapReloadRequiredForGameMode(bool wingman) {
  int expectedMode = wingman ? GAME_MODE_WINGMAN : GAME_MODE_COMPETITIVE;
  if (GetGameMode() != expectedMode || GetGameType() != GAME_TYPE_CLASSIC) {
    return true;
  }
  return false;
}

JSON_Object LoadTeamsFile(char[] error) {
  char teamsFile[PLATFORM_MAX_PATH];
  g_TeamsFileCvar.GetString(teamsFile, sizeof(teamsFile));
  Format(teamsFile, sizeof(teamsFile), "cfg/%s", teamsFile);

  if (!FileExists(teamsFile)) {
    WriteDefaultTeamsFile(teamsFile);
  }

  JSON_Object json = LoadJSONIfFileExists(teamsFile, error);
  if (json == null) {
    return null;
  }

  if (json.IsArray) {
    FormatEx(error, PLATFORM_MAX_PATH, "队伍文件 '%s' 不能是数组，必须为对象。(Teams file '%s' is an array. Must be object.)",
             teamsFile, teamsFile);
    json_cleanup_and_delete(json);
    return null;
  }

  int length = json.Length;
  int keyLength = 0;
  for (int i = 0; i < length; i += 1) {
    keyLength = json.GetKeySize(i);
    char[] key = new char[keyLength];
    json.GetKey(i, key, keyLength);
    if (json.GetType(key) != JSON_Type_Object) {
      FormatEx(error, PLATFORM_MAX_PATH,
               "队伍文件中的键 '%s' 不包含对象。(Teams file key '%s' does not contain an object.)",
               key, key);
      json_cleanup_and_delete(json);
      return null;
    }
    JSON_Object team = json.GetObject(key);
    if (!ValidateJSONTeam(team, error, false, false)) {
      json_cleanup_and_delete(json);
      return null;
    }
  }
  return json;
}

JSON_Object LoadCvarsFile(char[] error, const char[] key) {
  char cvarsFile[PLATFORM_MAX_PATH];
  g_CvarsFileCvar.GetString(cvarsFile, sizeof(cvarsFile));
  Format(cvarsFile, sizeof(cvarsFile), "cfg/%s", cvarsFile);

  if (!FileExists(cvarsFile)) {
    WriteDefaultCvarsFile(cvarsFile);
  }

  JSON_Object cvars = LoadJSONIfFileExists(cvarsFile, error);
  if (cvars == null) {
    return null;
  }

  if (cvars.IsArray) {
    FormatEx(error, PLATFORM_MAX_PATH, "Cvars 文件 '%s' 不能是数组。(Cvars file '%s' must not be an array.)",
             cvarsFile, cvarsFile);
    json_cleanup_and_delete(cvars);
    return null;
  }

  if (!cvars.HasKey(key)) {
    FormatEx(error, PLATFORM_MAX_PATH,
             "Cvars 文件 '%s' 不包含键 '%s'。(Cvars file '%s' does not contain key '%s'.)",
             cvarsFile, key, cvarsFile, key);
    json_cleanup_and_delete(cvars);
    return null;
  }

  if (cvars.GetType(key) != JSON_Type_Object || cvars.GetObject(key).IsArray) {
    FormatEx(error, PLATFORM_MAX_PATH, "Cvars 文件中的键 '%s' 必须包含对象。(Cvars file key '%s' must contain object.)",
             key, key);
    json_cleanup_and_delete(cvars);
    return null;
  }

  JSON_Object cvarsToLoad = cvars.GetObject(key);
  if (!ValidateJSONCvars(cvarsToLoad, error)) {
    json_cleanup_and_delete(cvars);
    return null;
  }
  JSON_Object jsonCopy = cvarsToLoad.DeepCopy();
  json_cleanup_and_delete(cvars);
  return jsonCopy;
}

JSON_Object LoadMapsFile(char[] error) {
  char mapFile[PLATFORM_MAX_PATH];
  g_MapsFileCvar.GetString(mapFile, sizeof(mapFile));
  Format(mapFile, sizeof(mapFile), "cfg/%s", mapFile);

  if (!FileExists(mapFile)) {
    WriteDefaultMapsFile(mapFile);
  }

  JSON_Object maps = LoadJSONIfFileExists(mapFile, error);
  if (maps == null) {
    return null;
  }

  if (maps.IsArray) {
    FormatEx(error, PLATFORM_MAX_PATH, "地图文件 '%s' 不能是数组。(Maps file '%s' must not be an array.)",
             mapFile, mapFile);
    json_cleanup_and_delete(maps);
    return null;
  }

  char mapName[PLATFORM_MAX_PATH];
  int length = maps.Length;
  if (length == 0) {
    FormatEx(error, PLATFORM_MAX_PATH, "地图文件 '%s' 为空。(Maps file '%s' is empty.)", mapFile, mapFile);
    json_cleanup_and_delete(maps);
    return null;
  }
  int keyLength = 0;
  int mapArrayLength = 0;
  for (int i = 0; i < length; i++) {
    keyLength = maps.GetKeySize(i);
    char[] key = new char[keyLength];
    maps.GetKey(i, key, keyLength);
    if (maps.GetType(key) != JSON_Type_Object) {
      FormatEx(error, PLATFORM_MAX_PATH,
               "地图文件中的键 '%s' 必须包含非空数组。(Maps file key '%s' must contain non-empty array.)",
               key, key);
      json_cleanup_and_delete(maps);
      return null;
    }
    JSON_Array mapArray = view_as<JSON_Array>(maps.GetObject(key));
    if (!mapArray.IsArray || mapArray.Length == 0) {
      FormatEx(error, PLATFORM_MAX_PATH,
               "地图文件中的键 '%s' 必须包含非空数组。(Maps file key '%s' must contain non-empty array.)",
               key, key);
      json_cleanup_and_delete(maps);
      return null;
    }

    mapArrayLength = mapArray.Length;
    for (int j = 0; j < mapArrayLength; j++) {
      if (mapArray.GetType(j) != JSON_Type_String) {
        FormatEx(error, PLATFORM_MAX_PATH,
                 "地图文件中的键 '%s' 只能包含字符串。(Maps file key '%s' must contain only strings.)",
                 key, key);
        json_cleanup_and_delete(maps);
        return null;
      }
      mapArray.GetString(j, mapName, sizeof(mapName));
      if (!IsMapValid(mapName) && !IsMapWorkshop(mapName)) {
        FormatEx(error, PLATFORM_MAX_PATH,
                 "地图文件中的键 '%s' 包含无效地图 '%s'。(Maps file key '%s' contains invalid map '%s'.)",
                 key, mapName, key, mapName);
        json_cleanup_and_delete(maps);
        return null;
      }
    }
  }
  return maps;
}

JSON_Array CreateDefaultMapPool() {
  JSON_Array defaultArray = new JSON_Array();
  defaultArray.PushString("de_ancient");
  defaultArray.PushString("de_anubis");
  defaultArray.PushString("de_inferno");
  defaultArray.PushString("de_mirage");
  defaultArray.PushString("de_nuke");
  defaultArray.PushString("de_overpass");
  defaultArray.PushString("de_vertigo");
  return defaultArray;
}

static void WriteDefaultMapsFile(const char[] file) {
  LogMessage("Generating default maps file at '%s' because the file does not exist.", file);
  JSON_Object maps = new JSON_Object();

  JSON_Array defaultPool = CreateDefaultMapPool();

  JSON_Array extendedPool = new JSON_Array();
  extendedPool.PushString("de_ancient");
  extendedPool.PushString("de_anubis");
  extendedPool.PushString("de_cache");
  extendedPool.PushString("de_dust2");
  extendedPool.PushString("de_inferno");
  extendedPool.PushString("de_mirage");
  extendedPool.PushString("de_nuke");
  extendedPool.PushString("de_overpass");
  extendedPool.PushString("de_train");
  extendedPool.PushString("de_vertigo");

  JSON_Array wingmanPool = new JSON_Array();
  wingmanPool.PushString("de_shortdust");
  wingmanPool.PushString("de_boyard");
  wingmanPool.PushString("de_chalice");
  wingmanPool.PushString("de_cbble");
  wingmanPool.PushString("de_inferno");
  wingmanPool.PushString("de_lake");
  wingmanPool.PushString("de_overpass");
  wingmanPool.PushString("de_shortnuke");
  wingmanPool.PushString("de_train");
  wingmanPool.PushString("de_vertigo");

  maps.SetObject(DEFAULT_CONFIG_KEY, defaultPool);
  maps.SetObject("extended", extendedPool);
  maps.SetObject("wingman", wingmanPool);

  maps.WriteToFile(file, JSON_ENCODE_PRETTY);

  json_cleanup_and_delete(maps);
}

static void WriteDefaultTeamsFile(const char[] file) {
  LogMessage("Generating default teams file at '%s' because the file does not exist.", file);
  JSON_Object teams = new JSON_Object();
  teams.WriteToFile(file, JSON_ENCODE_PRETTY);
  json_cleanup_and_delete(teams);
}

static void WriteDefaultCvarsFile(const char[] file) {
  LogMessage("Generating default cvars file at '%s' because the file does not exist.", file);
  JSON_Object cvars = new JSON_Object();
  cvars.SetObject(DEFAULT_CONFIG_KEY, new JSON_Object());
  cvars.WriteToFile(file, JSON_ENCODE_PRETTY);
  json_cleanup_and_delete(cvars);
}
