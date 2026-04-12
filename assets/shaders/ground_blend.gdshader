shader_type canvas_item;
/// Passthrough — used to verify CanvasGroup is compositing correctly.
/// Replace with blur logic once rendering is confirmed.

void fragment() {
	COLOR = texture(TEXTURE, UV);
}
