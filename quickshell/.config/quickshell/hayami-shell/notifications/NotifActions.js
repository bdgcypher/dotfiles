// One rule for what "activating a notification" means.
//
// Three places have to answer that question -- the card body in NotifCard, the
// panel's cursor in Center, and the command line in NotifState -- and they are
// the same question. They used to answer it separately, and one of the three
// answers was different from the other two, which is how `hayami-notify -a`
// came to activate a notification that pressing Enter on the very same row did
// nothing with.

// The freedesktop notification spec gives one action the identifier "default",
// and that is what a click on a card is meant to run. Plenty of clients never
// send one though -- they send actions under their own names, or none at all --
// and a notification you can read but cannot open is the most common complaint
// there is about notification centres.
//
// Not a setting: a client that names its default action something else is not
// speaking the spec, and the fallback below is what covers that case.
var defaultIdentifier = "default";

// The action activation should run, or null when there is nothing to run.
//
// Falls back to the first action when there is no "default", because that is
// still the client's own idea of what should happen to this notification --
// which is a far better answer than a keypress that visibly does nothing.
function pick(actions) {
	if (!actions || actions.length === 0)
		return null;

	for (var i = 0; i < actions.length; i++) {
		if (actions[i] && actions[i].identifier === defaultIdentifier)
			return actions[i];
	}

	return actions[0];
}