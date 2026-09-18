import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! "Claude Grid" - an Iron Grit-style data face. This first version lays out the grid (big
//! time, date, weekday strip, battery arc, and eight data-field positions) in JetBrains Mono;
//! making the eight fields user-editable via the native complication editor is the next step.
class ClaudeGridApp extends Application.AppBase {

    public function initialize() {
        AppBase.initialize();
    }

    public function onStart(state as Dictionary?) as Void {
    }

    public function onStop(state as Dictionary?) as Void {
    }

    public function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new $.ClaudeGridView()];
    }
}
