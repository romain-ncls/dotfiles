// A value following its new one (a ring, a meter, a level; Theme.qml's
// motion), as `Behavior on x { enabled: Theme.speed > 0; Follow {} }`: a
// spring, keeping its speed when the value changes again on the way (the
// wheel), there in 300 ms, as SwiftUI's springs with no bounce (spring and
// damping fitted in Qt's units; 0.3 % past it, unseen).
import QtQuick

SpringAnimation {
    spring: 3.9
    damping: 0.39
    epsilon: 0.001
}
