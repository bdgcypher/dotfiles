import QtQuick
import QtQuick.Effects
import Quickshell

// An icon drawn in one colour, the way GTK draws a *symbolic* icon.
//
// This exists because the icons the OSD asks for (`audio-volume-medium`,
// `display-brightness-symbolic`, ...) come out of the theme as coloured artwork --
// the oomox/pywal set in use here paints its status icons in a flat red. GTK
// recolours a symbolic icon to the widget's current colour before drawing it, and
// the OSD would otherwise show red speaker icons where they belong in the
// pywal foreground.
//
// Size it with width/height. There is deliberately no `implicitSize` here: see the
// note on the Image below.
//
// Two things about this component were arrived at by measuring, because both
// failure modes are silent -- the icon simply never appears, and nothing is
// logged to say why:
//
//   * the recolour is MultiEffect's colorization, not a hand-written ShaderEffect.
//     In Qt 6 ShaderEffect.fragmentShader is a URL, not source: assigning GLSL to
//     it makes Qt try to load the string as a shader file and give up, and
//     ShaderEffect cannot load a .frag either ("In Qt 6 shaders must be
//     preprocessed using ... qsb").
//   * the hidden source image is sized with explicit width/height bindings, and
//     this component declares no implicitWidth/implicitHeight. Each of those
//     variants looks equivalent and each one was tried on screen: an
//     `anchors.fill: parent` source, or an implicitSize property on this root
//     item, both leave the effect drawing nothing at all.
Item {
	id: root

	// URL of the icon, usually from Quickshell.iconPath(). See QtQuick.Image.source.
	property string source: ""
	// The colour to draw it in.
	property color color: "white"

	// Never shown directly -- the MultiEffect below renders it offscreen and draws
	// the recoloured result in its place.
	Image {
		id: image

		width: root.width
		height: root.height
		fillMode: Image.PreserveAspectFit

		readonly property real drawSize: Math.min(root.width, root.height)
		sourceSize.width: drawSize
		sourceSize.height: drawSize

		source: root.source
		visible: false
	}

	MultiEffect {
		anchors.fill: parent
		source: image
		// Flatten the artwork to white first: colorization on its own is a
		// multiply, so the icon would come out as the target colour scaled by
		// whatever brightness the theme's artwork happens to have (measured at
		// 40% for this theme's red).
		brightness: 1.0
		// 1.0 is a full replacement. The shape comes from the artwork's alpha,
		// which is all that is kept.
		colorization: 1.0
		colorizationColor: root.color
	}
}
