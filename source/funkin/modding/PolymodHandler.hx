package funkin.modding;

import funkin.data.character.CharacterData.CharacterDataParser;
import funkin.data.dialogue.ConversationRegistry;
import funkin.data.dialogue.DialogueBoxRegistry;
import funkin.data.dialogue.SpeakerRegistry;
import funkin.data.event.SongEventRegistry;
import funkin.data.freeplay.album.AlbumRegistry;
import funkin.data.freeplay.player.PlayerRegistry;
import funkin.data.freeplay.style.FreeplayStyleRegistry;
import funkin.data.notestyle.NoteStyleRegistry;
import funkin.data.song.SongRegistry;
import funkin.data.stage.StageRegistry;
import funkin.data.stickers.StickerRegistry;
import funkin.data.story.level.LevelRegistry;
import funkin.modding.module.ModuleHandler;
import funkin.play.notes.notekind.NoteKindManager;
import funkin.save.Save;
import funkin.util.FileUtil;
import funkin.util.SortUtil;
import funkin.util.macro.ClassMacro;
import lime.app.Future;
import polymod.Polymod;
import polymod.format.ParseRules;
import polymod.format.ParseRules.TextFileFormat;
import polymod.fs.ZipFileSystem;
import polymod.hscript._internal.PolymodScriptClass;

typedef ScriptLoadResult =
{
  success:Int,
  total:Int
}

@:nullSafety
class PolymodHandler
{
  public static final API_VERSION:String = '0.8.5';

  public static final API_VERSION_RULE:String = '>=0.8.5 <0.8.6';

  public static var MOD_FOLDER(get, never):String;

  static function get_MOD_FOLDER():String
  {
    #if (REDIRECT_ASSETS_FOLDER && mac)
    return '../../../../../../../example_mods';
    #elseif REDIRECT_ASSETS_FOLDER
    return '../../../../example_mods';
    #elseif mobile
    return lime.system.System.applicationStorageDirectory + '/mods';
    #else
    return 'mods';
    #end
  }

  public static final CORE_FOLDER:Null<String> = #if (REDIRECT_ASSETS_FOLDER && mac) '../../../../../../../assets' #elseif REDIRECT_ASSETS_FOLDER '../../../../assets' #else null #end;

  static final IGNORED_FILES:Array<String> = [
    '.vscode',
    '.idea',
    '.git',
    '.gitignore',
    '.gitattributes',
    '.jj',
    '.DS_Store',
    'README.md',
    'cppia-src',
    'build.sh',
    'build.ps1'
  ];

  public static var loadedModDirs(default, null):Array<String> = [];

  public static var loadedModIds(default, null):Array<String> = [];

  static var modFileSystem:Null<ZipFileSystem> = null;

  public static function createModRoot():Void
  {
    FileUtil.createDirIfNotExists(MOD_FOLDER);
  }

  public static function loadAllMods():Void
  {
    prepareModRoot();
    loadModsById(getAllModIds());
  }

  public static function loadEnabledMods():Void
  {
    prepareModRoot();
    loadModsById(Save.instance.enabledModIds.value);
  }

  public static function loadNoMods():Void
  {
    prepareModRoot();
    loadModsById([]);
  }

  static inline function prepareModRoot():Void
  {
    #if sys
    createModRoot();
    #end
  }

  public static function loadModsById(modIds:Array<String>):Void
  {
    buildImports();
    ScriptGuard.clear();

    var fileSystem:Null<ZipFileSystem> = tryGetFileSystem();
    var availableIds:Array<String> = getAllModIds();
    var validIds:Array<String> = modIds.filter(id -> availableIds.contains(id));

    var loadedModList:Null<Array<ModMetadata>> = Polymod.init({
      modRoot: MOD_FOLDER,
      modIds: validIds,
      framework: OPENFL,
      apiVersionRule: API_VERSION_RULE,
      errorCallback: PolymodErrorHandler.onPolymodError,
      customFilesystem: fileSystem,
      frameworkParams: buildFrameworkParams(),
      ignoredFiles: buildIgnoreList(),
      parseRules: buildParseRules(),
      skipDependencyErrors: true,
      useScriptedClasses: false,
      loadScriptsAsync: false
    });

    var ids:Array<String> = [];
    var dirs:Array<String> = [];

    if (loadedModList != null)
    {
      for (mod in loadedModList)
      {
        ids.push(mod.id);
        dirs.push(mod.dirName);
      }
    }

    loadedModIds = ids;
    loadedModDirs = dirs;
  }

  public static function loadScripts(async:Bool = true):Future<ScriptLoadResult>
  {
    #if FEATURE_CPPIA
    polymod.hscript._internal.PolymodCppiaClassReference.expectedVersion = lime.app.Application.current.meta.get('version');
    #end

    if (async)
    {
      return Polymod.registerAllScriptClassesAsync().then(result -> {
        var success:Int = 0;
        for (future in result)
        {
          if (future.isComplete) success++;
        }
        return Future.withValue({success: success, total: result.length});
      });
    }

    var result = Polymod.registerAllScriptClasses();
    var success:Int = result.values().filter(v -> v == true).length;
    return Future.withValue({success: success, total: result.size()});
  }

  static function buildFileSystem():ZipFileSystem
  {
    Polymod.onError = PolymodErrorHandler.onPolymodError;
    return new ZipFileSystem({modRoot: MOD_FOLDER, autoScan: true});
  }

  static function getFileSystem(force:Bool = false):ZipFileSystem
  {
    var fileSystem:Null<ZipFileSystem> = modFileSystem;
    if (fileSystem == null || force)
    {
      fileSystem = buildFileSystem();
      modFileSystem = fileSystem;
    }
    return fileSystem;
  }

  static function tryGetFileSystem():Null<ZipFileSystem>
  {
    try
    {
      return getFileSystem();
    }
    catch (e:Dynamic)
    {
      return null;
    }
  }

  static function buildImports():Void
  {
    buildConvenienceAliases();
    buildCompatAliases();
    buildBlacklist();
  }

  static function buildConvenienceAliases():Void
  {
    final defaultImports:Array<Class<Dynamic>> = [
      funkin.Assets,
      funkin.Paths,
      funkin.Preferences,
      funkin.util.Constants,
      flixel.FlxG
    ];

    for (cls in defaultImports)
    {
      Polymod.addDefaultImport(cls);
    }
  }

  static function buildCompatAliases():Void
  {
    Polymod.addImportAlias('funkin.data.dialogue.conversation.ConversationRegistry', funkin.data.dialogue.ConversationRegistry);
    Polymod.addImportAlias('funkin.data.dialogue.dialoguebox.DialogueBoxRegistry', funkin.data.dialogue.DialogueBoxRegistry);
    Polymod.addImportAlias('funkin.data.dialogue.speaker.SpeakerRegistry', funkin.data.dialogue.SpeakerRegistry);
    Polymod.addImportAlias('funkin.play.character.CharacterDataParser', funkin.data.character.CharacterData.CharacterDataParser);
    Polymod.addImportAlias('funkin.play.character.CharacterData.CharacterDataParser', funkin.data.character.CharacterData.CharacterDataParser);

    Polymod.addImportAlias('funkin.modding.base.ScriptedFunkinSprite', funkin.graphics.FunkinSprite);
    Polymod.addImportAlias('funkin.modding.base.ScriptedMusicBeatState', funkin.ui.MusicBeatState);
    Polymod.addImportAlias('funkin.modding.base.ScriptedMusicBeatSubState', funkin.ui.MusicBeatSubState);
    Polymod.addImportAlias('funkin.graphics.adobeanimate.FlxAtlasSprite', funkin.graphics.FunkinSprite);
    Polymod.addImportAlias('funkin.modding.base.ScriptedFlxAtlasSprite', funkin.graphics.FunkinSprite);
    Polymod.addImportAlias('funkin.play.cutscene.VideoCutscene', funkin.modding.compat.VideoCutscene);
    Polymod.addImportAlias('funkin.FunkinMemory', funkin.memory.FunkinMemory);

    Polymod.addImportAlias('funkin.modding.base.ScriptedFlxBasic', flixel.FlxBasic);
    Polymod.addImportAlias('funkin.modding.base.ScriptedFlxObject', flixel.FlxObject);
    Polymod.addImportAlias('funkin.modding.base.ScriptedFlxRuntimeShader', flixel.addons.display.FlxRuntimeShader);
    Polymod.addImportAlias('funkin.modding.base.ScriptedFlxSprite', flixel.FlxSprite);
    Polymod.addImportAlias('funkin.modding.base.ScriptedFlxState', flixel.FlxState);
    Polymod.addImportAlias('funkin.modding.base.ScriptedFlxSubState', flixel.FlxSubState);
    Polymod.addImportAlias('funkin.modding.base.ScriptedFlxStrip', flixel.FlxStrip);
    Polymod.addImportAlias('funkin.modding.base.ScriptedFlxTransitionableState', flixel.addons.transition.FlxTransitionableState);
    Polymod.addImportAlias('funkin.modding.base.ScriptedFlxSpriteGroup', flixel.group.FlxSpriteGroup.FlxTypedSpriteGroup);
    Polymod.addImportAlias('funkin.modding.base.ScriptedFlxTypedGroup', flixel.group.FlxGroup.FlxTypedGroup);

    Polymod.addImportAlias('funkin.graphics.ScriptedFunkinSprite', funkin.graphics.FunkinSprite);
    Polymod.addImportAlias('funkin.group.ScriptedFunkinGroup', funkin.group.FunkinGroup);
    Polymod.addImportAlias('funkin.graphics.video.ScriptedFunkinVideoSprite', funkin.graphics.video.FunkinVideoSprite);
    Polymod.addImportAlias('funkin.play.character.ScriptedBaseCharacter', funkin.play.character.BaseCharacter);
    Polymod.addImportAlias('funkin.play.character.ScriptedSparrowCharacter', funkin.play.character.SparrowCharacter);
    Polymod.addImportAlias('funkin.play.character.ScriptedMultiSparrowCharacter', funkin.play.character.MultiSparrowCharacter);
    Polymod.addImportAlias('funkin.play.character.ScriptedMultiAnimateAtlasCharacter', funkin.play.character.MultiAnimateAtlasCharacter);
    Polymod.addImportAlias('funkin.play.character.ScriptedPackerCharacter', funkin.play.character.PackerCharacter);
    Polymod.addImportAlias('funkin.play.character.ScriptedAnimateAtlasCharacter', funkin.play.character.AnimateAtlasCharacter);
    Polymod.addImportAlias('funkin.play.cutscene.dialogue.ScriptedConversation', funkin.play.cutscene.dialogue.Conversation);
    Polymod.addImportAlias('funkin.play.cutscene.dialogue.ScriptedDialogueBox', funkin.play.cutscene.dialogue.DialogueBox);
    Polymod.addImportAlias('funkin.play.cutscene.dialogue.ScriptedSpeaker', funkin.play.cutscene.dialogue.Speaker);
    Polymod.addImportAlias('funkin.play.event.ScriptedSongEvent', funkin.play.event.SongEvent);
    Polymod.addImportAlias('funkin.play.notes.ScriptedStrumline', funkin.play.notes.Strumline);
    Polymod.addImportAlias('funkin.play.notes.notekind.ScriptedNoteKind', funkin.play.notes.notekind.NoteKind);
    Polymod.addImportAlias('funkin.play.notes.notestyle.ScriptedNoteStyle', funkin.play.notes.notestyle.NoteStyle);
    Polymod.addImportAlias('funkin.play.song.ScriptedSong', funkin.play.song.Song);
    Polymod.addImportAlias('funkin.play.stage.ScriptedBopper', funkin.play.stage.Bopper);
    Polymod.addImportAlias('funkin.play.stage.ScriptedStage', funkin.play.stage.Stage);
    Polymod.addImportAlias('funkin.play.stage.ScriptedStageProp', funkin.play.stage.StageProp);
    Polymod.addImportAlias('funkin.ui.ScriptedMusicBeatState', funkin.ui.MusicBeatState);
    Polymod.addImportAlias('funkin.ui.ScriptedMusicBeatSubState', funkin.ui.MusicBeatSubState);
    Polymod.addImportAlias('funkin.ui.freeplay.ScriptedAlbum', funkin.ui.freeplay.Album);
    Polymod.addImportAlias('funkin.ui.freeplay.ScriptedFreeplayStyle', funkin.ui.freeplay.FreeplayStyle);
    Polymod.addImportAlias('funkin.ui.freeplay.backcards.ScriptedBackingCard', funkin.ui.freeplay.backcards.BackingCard);
    Polymod.addImportAlias('funkin.ui.freeplay.charselect.ScriptedPlayableCharacter', funkin.ui.freeplay.charselect.PlayableCharacter);
    Polymod.addImportAlias('funkin.ui.freeplay.dj.ScriptedAnimateAtlasFreeplayDJ', funkin.ui.freeplay.dj.AnimateAtlasFreeplayDJ);
    Polymod.addImportAlias('funkin.ui.freeplay.dj.ScriptedBaseFreeplayDJ', funkin.ui.freeplay.dj.BaseFreeplayDJ);
    Polymod.addImportAlias('funkin.ui.freeplay.dj.ScriptedSparrowFreeplayDJ', funkin.ui.freeplay.dj.SparrowFreeplayDJ);
    Polymod.addImportAlias('funkin.ui.freeplay.dj.ScriptedMultiSparrowFreeplayDJ', funkin.ui.freeplay.dj.MultiSparrowFreeplayDJ);
    Polymod.addImportAlias('funkin.ui.freeplay.dj.ScriptedPackerFreeplayDJ', funkin.ui.freeplay.dj.PackerFreeplayDJ);
    Polymod.addImportAlias('funkin.ui.story.ScriptedLevel', funkin.ui.story.Level);
    Polymod.addImportAlias('funkin.ui.transition.stickers.ScriptedStickerPack', funkin.ui.transition.stickers.StickerPack);

    Polymod.addImportAlias('funkin.graphics.framebuffer.FixedBitmapData', openfl.display.BitmapData);
  }

  static function buildBlacklist():Void
  {
    Polymod.addImportAlias('lime.utils.Assets', funkin.Assets);
    Polymod.addImportAlias('openfl.utils.Assets', funkin.Assets);
    Polymod.addImportAlias('openfl.Assets', funkin.Assets);
    Polymod.addImportAlias('funkin.util.FileUtil', funkin.util.FileUtilSandboxed);

    #if FEATURE_NEWGROUNDS
    Polymod.addImportAlias('funkin.api.newgrounds.Leaderboards', funkin.api.newgrounds.Leaderboards.LeaderboardsSandboxed);
    Polymod.addImportAlias('funkin.api.newgrounds.Medals', funkin.api.newgrounds.Medals.MedalsSandboxed);
    Polymod.addImportAlias('funkin.api.newgrounds.NewgroundsClient', funkin.api.newgrounds.NewgroundsClient.NewgroundsClientSandboxed);
    #end

    Polymod.addImportAlias('funkin.api.discord.DiscordClient', funkin.api.discord.DiscordClient.DiscordClientSandboxed);
    Polymod.addImportAlias('Reflect', funkin.util.ReflectUtil);
    Polymod.addImportAlias('Type', funkin.util.ReflectUtil);

    final blockedImports:Array<String> = [
      'Sys',
      'cpp.Lib',
      'haxe.Http',
      'haxe.Unserializer',
      'lime.system.CFFI',
      'lime.system.JNI',
      'lime.system.System',
      'lime.utils.AssetLibrary',
      'lime.utils.Assets',
      'openfl.utils.Assets',
      'openfl.Lib',
      'openfl.system.ApplicationDomain',
      'openfl.net.SharedObject',
      'openfl.desktop.NativeProcess',
      'funkin.external.android.CallbackUtil',
      'funkin.external.android.DataFolderUtil',
      'funkin.external.android.JNIUtil'
    ];

    for (name in blockedImports)
    {
      Polymod.blacklistImport(name);
    }

    blacklistClasses(ClassMacro.listClassesInPackage('funkin.mobile.util'));
    blacklistClasses(ClassMacro.listClassesInPackage('extension'));
    blacklistClasses(ClassMacro.listClassesInPackage('funkin.api'), true);
    blacklistClasses(ClassMacro.listClassesInPackage('polymod'));
    blacklistClasses(ClassMacro.listClassesInPackage('hscript'));
    blacklistClasses(ClassMacro.listClassesInPackage('io.newgrounds'));
    blacklistClasses(ClassMacro.listClassesInPackage('sys'));
    blacklistClasses(ClassMacro.listClassesInPackage('funkin.util.macro'));

    Polymod.blacklistStaticFields(flixel.util.FlxSave, ['resolveFlixelClasses']);
    Polymod.blacklistStaticFields(flixel.FlxG, ['save']);
    Polymod.blacklistStaticFields(haxe.Unserializer, ['run']);
    Polymod.blacklistStaticFields(funkin.Assets, ['getLibrary']);

    Polymod.blacklistInstanceFields(lime.utils.AssetLibrary, ['classTypes']);
    Polymod.blacklistInstanceFields(haxe.Unserializer, ['unserialize']);
    Polymod.blacklistInstanceFields(funkin.save.Save, ['data', 'clearData', 'setLevelScore', 'setSongScore', 'applySongRank']);
    #if !html5
    Polymod.blacklistInstanceFields(openfl.filesystem.FileStream, ['readObject']);
    #end
    Polymod.blacklistInstanceFields(openfl.net.Socket, ['readObject']);
    Polymod.blacklistInstanceFields(openfl.utils.ByteArray.ByteArrayData, ['readObject']);
    Polymod.blacklistInstanceFields(PolymodScriptClass, ['_interp']);

    Polymod.blacklistDynamicFieldNames([
      'resolveFlixelClasses',
      'classTypes',
      'unserialize',
      'getLibrary',
      'readObject',
      'clearData',
      'setLevelScore',
      'setSongScore',
      'applySongRank',
      '_interp'
    ]);
  }

  static function blacklistClasses(classes:Iterable<Null<Class<Dynamic>>>, skipOverrides:Bool = false):Void
  {
    for (cls in classes)
    {
      if (cls == null) continue;
      var className:String = Type.getClassName(cls);
      if (skipOverrides && PolymodScriptClass.importOverrides.exists(className)) continue;
      Polymod.blacklistImport(className);
    }
  }

  static function buildIgnoreList():Array<String>
  {
    return Polymod.getDefaultIgnoreList().concat(IGNORED_FILES);
  }

  static function buildParseRules():ParseRules
  {
    var output:ParseRules = ParseRules.getDefault();
    output.addType('txt', TextFileFormat.LINES);
    return output;
  }

  static inline function buildFrameworkParams():FrameworkParams
  {
    return {
      assetLibraryPaths: ['default' => ''],
      coreAssetRedirect: CORE_FOLDER
    };
  }

  public static function getAllMods(force:Bool = false):Array<ModMetadata>
  {
    return scanMods(false, force);
  }

  public static function getAllModsIncludingIncompatible(force:Bool = false):Array<ModMetadata>
  {
    return scanMods(true, force);
  }

  static function scanMods(includeIncompatible:Bool, force:Bool):Array<ModMetadata>
  {
    try
    {
      var result:Null<Array<ModMetadata>> = Polymod.scan({
        modRoot: MOD_FOLDER,
        fileSystem: getFileSystem(force),
        errorCallback: PolymodErrorHandler.onPolymodError,
        apiVersionRule: includeIncompatible ? null : API_VERSION_RULE
      });
      return result ?? [];
    }
    catch (e:Dynamic)
    {
      return [];
    }
  }

  public static function isModCompatible(mod:Null<ModMetadata>):Bool
  {
    return mod != null && mod.isCompatible(API_VERSION_RULE);
  }

  public static function getAllModIds():Array<String>
  {
    return [for (mod in getAllMods()) mod.id];
  }

  public static function getAllModDirs():Array<String>
  {
    return [for (mod in getAllMods()) mod.dirName];
  }

  public static function enableMod(modId:String):Void
  {
    var enabledModIds:Array<String> = Save.instance.enabledModIds.value.copy();
    if (enabledModIds.contains(modId)) return;
    enabledModIds.push(modId);
    saveEnabledModIds(enabledModIds);
  }

  public static function disableMod(modId:String):Void
  {
    var enabledModIds:Array<String> = Save.instance.enabledModIds.value;
    if (!enabledModIds.contains(modId)) return;
    saveEnabledModIds(enabledModIds.filter(id -> id != modId));
  }

  public static function disableAllMods():Void
  {
    saveEnabledModIds([]);
  }

  public static function pruneIncompatibleMods():Void
  {
    var availableIds:Array<String> = getAllModIds();
    var enabledModIds:Array<String> = Save.instance.enabledModIds.value;
    var validIds:Array<String> = enabledModIds.filter(id -> availableIds.contains(id));
    if (validIds.length != enabledModIds.length) saveEnabledModIds(validIds);
  }

  static function saveEnabledModIds(modIds:Array<String>):Void
  {
    Save.instance.enabledModIds.value = modIds;
    Save.system.flush();
  }

  public static function getEnabledMods():Array<ModMetadata>
  {
    var enabledModIds:Array<String> = Save.instance.enabledModIds.value;
    var enabledMods:Array<ModMetadata> = getAllMods().filter(mod -> enabledModIds.contains(mod.id));
    enabledMods.sort((a, b) -> enabledModIds.indexOf(a.id) - enabledModIds.indexOf(b.id));
    return enabledMods;
  }

  public static function getDisabledMods():Array<ModMetadata>
  {
    var enabledModIds:Array<String> = Save.instance.enabledModIds.value;
    var disabledMods:Array<ModMetadata> = getAllMods().filter(mod -> !enabledModIds.contains(mod.id));
    disabledMods.sort((a, b) -> SortUtil.alphabetically(a.title, b.title));
    return disabledMods;
  }

  public static function getDisabledModsIncludingIncompatible(force:Bool = false):Array<ModMetadata>
  {
    var enabledModIds:Array<String> = Save.instance.enabledModIds.value;
    var disabledMods:Array<ModMetadata> = getAllModsIncludingIncompatible(force).filter(mod -> !enabledModIds.contains(mod.id));

    disabledMods.sort((a, b) -> {
      var aCompatible:Bool = isModCompatible(a);
      var bCompatible:Bool = isModCompatible(b);
      if (aCompatible != bCompatible) return aCompatible ? -1 : 1;
      return SortUtil.alphabetically(a.title, b.title);
    });

    return disabledMods;
  }

  public static function forceReloadAssets():Void
  {
    ModuleHandler.clearModuleCache();
    Polymod.clearScripts();

    loadEnabledMods();

    SongEventRegistry.loadEventCache();

    SongRegistry.instance.loadEntries();
    LevelRegistry.instance.loadEntries();
    NoteStyleRegistry.instance.loadEntries();
    PlayerRegistry.instance.loadEntries();
    ConversationRegistry.instance.loadEntries();
    DialogueBoxRegistry.instance.loadEntries();
    SpeakerRegistry.instance.loadEntries();
    AlbumRegistry.instance.loadEntries();
    StageRegistry.instance.loadEntries();
    StickerRegistry.instance.loadEntries();
    FreeplayStyleRegistry.instance.loadEntries();

    CharacterDataParser.loadCharacterCache();
    NoteKindManager.initialize();
    ModuleHandler.loadModuleCache();
    ModuleHandler.callOnCreate();
  }
}
