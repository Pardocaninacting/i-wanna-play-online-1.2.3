/// ONLINE
#if GM8GUI
	// GM8.2: world-anchored notes + off-screen arrows render in the GUI pass
	// (worldDrawGui.gml) - group-8 primitives never rasterize in d3d-started
	// rooms (E1). This Draw event intentionally does nothing there.
#endif
#if not GM8GUI
	@note_render_all();
#endif
