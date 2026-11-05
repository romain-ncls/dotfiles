// Hornet's day planned on a worker thread (DayPlanner.qml), with this thread's own copy of
// life.mjs: given the world's data, her clips and the time, the day's plans (planAhead) back.
import * as Life from "./life.mjs";

WorkerScript.onMessage = function (message) {
    WorkerScript.sendMessage({ planned: Life.planAhead(message.world, message.clips, message.t) });
};
