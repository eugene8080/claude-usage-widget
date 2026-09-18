import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! A terminal/CLI-styled watch face that shows the time plus the three Claude usage meters.
//! The meters are read by subscribing to the complications the companion "Claude Usage"
//! watch-app publishes - a watch face cannot receive phone pushes or read another app's
//! storage, so complications are the only channel for this data.
class ClaudeFaceApp extends Application.AppBase {

    public function initialize() {
        AppBase.initialize();
    }

    public function onStart(state as Dictionary?) as Void {
    }

    public function onStop(state as Dictionary?) as Void {
    }

    public function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new $.ClaudeFaceView()];
    }
}
