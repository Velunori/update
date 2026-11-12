pragma Singleton
import QtQuick

// Owned by this plugin only: lets the window and the bar widget reach the
// service without the host handing either a reference to the other.
QtObject {
    property QtObject backend: null
    property bool windowOpen: false
}
