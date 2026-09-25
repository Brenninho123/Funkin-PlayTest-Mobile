package;

import flixel.FlxG;
import flixel.FlxState;
import flixel.math.FlxMath;
import funkin.PlayerSettings;
import funkin.Preferences;
import funkin.save.Save;
import funkin.ui.FullScreenScaleMode;
import funkin.ui.debug.FunkinDebugDisplay;
import funkin.ui.debug.FunkinDebugDisplay.DebugDisplayMode;
import funkin.util.WindowUtil;
import funkin.util.logging.AnsiTrace;
import funkin.util.logging.CrashHandler;
import lime.system.System;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
#if hxvlc
import hxvlc.util.Handle;
#end

class Main extends Sprite
{
  static inline final GAME_WIDTH:Int = 1280;
  static inline final GAME_HEIGHT:Int = 720;
  static inline final SKIP_SPLASH:Bool = true;
  static inline final COUNTER_MARGIN:Float = 10;
  static inline final COUNTER_LERP_SPEED:Float = 3;

  public static var debugDisplay:FunkinDebugDisplay;

  final initialState:Class<FlxState> = funkin.InitState;

  public static function main():Void
  {
    CrashHandler.initialize();
    CrashHandler.queryStatus();
    Lib.current.addChild(new Main());
  }

  public function new()
  {
    super();

    haxe.Log.trace = AnsiTrace.trace;
    AnsiTrace.traceBF();
    openfl.utils._internal.Log.level = openfl.utils._internal.Log.LogLevel.INFO;

    if (stage != null) init();
    else addEventListener(Event.ADDED_TO_STAGE, init);
  }

  function init(?event:Event):Void
  {
    removeEventListener(Event.ADDED_TO_STAGE, init);

    if (!hasHardwareContext())
    {
      showRendererError();
      System.exit(1);
      return;
    }

    setupGame();
  }

  function hasHardwareContext():Bool
  {
    return switch (stage.window.context.type)
    {
      case WEBGL | OPENGL | OPENGLES: true;
      default: false;
    }
  }

  function showRendererError():Void
  {
    var tech:String = #if web 'WebGL' #elseif desktop 'OpenGL' #else 'OpenGL ES' #end;
    var version:String = #if web '1.0' #elseif desktop '3.0' #else '2.0' #end;
    var required:String = '$tech $version or newer';
    var hint:String = #if web
      'Make sure your graphics card supports $required, your graphics drivers are up to date, and hardware acceleration is enabled on your browser.';
    #elseif desktop
      'Make sure your graphics card supports $required, and your graphics drivers are up to date.';
    #else
      'Make sure your device supports $required.';
    #end

    WindowUtil.showError('Failed to initialize $tech', 'Failed to initialize the $tech rendering context!\n\n$hint');
  }

  function setupGame():Void
  {
    #if FEATURE_HAXEUI
    initHaxeUI();
    #end

    debugDisplay = new FunkinDebugDisplay(10, 10, 0xFFFFFF);
    FlxG.signals.postUpdate.add(handleDebugDisplayKeys);

    Save.load();

    #if hxvlc
    Handle.initAsync();
    #end

    WindowUtil.setVSyncMode(Preferences.vsyncMode);

    untyped FlxG.cameras = new funkin.graphics.FunkinCameraFrontEnd();

    var framerate:Int = Preferences.unlockedFramerate ? 0 : Preferences.framerate;
    var game = new funkin.FunkinGame(GAME_WIDTH, GAME_HEIGHT, initialState, framerate, framerate, SKIP_SPLASH, stage.window.fullscreen);

    @:privateAccess
    game._customSoundTray = funkin.ui.options.FunkinSoundTray;

    addChild(game);

    #if FEATURE_DEBUG_FUNCTIONS
    #if !FLX_NO_DEBUG
    game.debugger.interaction.addTool(new funkin.util.TrackerToolButtonUtil());
    #end
    funkin.util.macro.ConsoleMacro.init();
    #end

    #if !html5
    FlxG.scaleMode = new FullScreenScaleMode();
    #end

    #if mobile
    repositionCounters(false);
    FlxG.signals.preUpdate.add(() -> repositionCounters(true));
    #end
  }

  #if FEATURE_HAXEUI
  function initHaxeUI():Void
  {
    haxe.ui.locale.LocaleManager.instance.autoSetLocale = false;
    haxe.ui.Toolkit.init();
    haxe.ui.Toolkit.theme = 'funkin-dark';
    haxe.ui.Toolkit.autoScale = false;
    haxe.ui.focus.FocusManager.instance.autoFocus = false;
    funkin.input.Cursor.setupHaxeUICursors();
    haxe.ui.tooltips.ToolTipManager.defaultDelay = 200;
  }
  #end

  function handleDebugDisplayKeys():Void
  {
    var controls = PlayerSettings.player1.controls;
    if (controls == null || !controls.check(DEBUG_DISPLAY)) return;

    Preferences.debugDisplay = switch (Preferences.debugDisplay)
    {
      case DebugDisplayMode.Off: DebugDisplayMode.Simple;
      case DebugDisplayMode.Simple: DebugDisplayMode.Advanced;
      case DebugDisplayMode.Advanced: DebugDisplayMode.Off;
    }
  }

  #if mobile
  function repositionCounters(lerp:Bool):Void
  {
    if (debugDisplay == null || FlxG.game == null) return;

    var scale:Float = Math.max(Math.min(FlxG.stage.stageWidth / FlxG.width, FlxG.stage.stageHeight / FlxG.height), 1);
    debugDisplay.scaleX = debugDisplay.scaleY = scale;

    var targetX:Float = FlxG.game.x + Math.max(FullScreenScaleMode.notchSize.x, COUNTER_MARGIN);
    var factor:Float = Math.min(FlxG.elapsed * COUNTER_LERP_SPEED, 1);

    debugDisplay.x = lerp ? FlxMath.lerp(debugDisplay.x, targetX, factor) : targetX;
    debugDisplay.y = FlxG.game.y + COUNTER_MARGIN * scale;
  }
  #end
}
