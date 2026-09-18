import Toybox.Background;
import Toybox.Lang;
import Toybox.System;

//! Background entry point. A device app may only publish complications from here - doing it
//! from the foreground faults - so the three meters are pushed to the complication framework
//! on the periodic temporal event the main app registers (Connect IQ's floor is 5 minutes).
//!
//! It publishes whatever snapshot is in Storage; the watch has no data source of its own, so
//! the numbers are as fresh as the last push the phone delivered. Everything it touches is
//! annotated (:background) so it is compiled into the background memory image.
(:background)
class ClaudeUsageServiceDelegate extends System.ServiceDelegate {

    public function initialize() {
        ServiceDelegate.initialize();
    }

    public function onTemporalEvent() as Void {
        Publisher.publish();
        Background.exit(null);
    }
}
