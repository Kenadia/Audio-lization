All code by Ken Schiller.

This is a project from my free time in which I explored algorithmic sound generation from video (the inverse of a music visualizer). It is a sort of musical “instrument” that reacts to image data from a camera. Different colors and combinations of colors in the active area (center rectangle) produce different tones and combinations of tones, in stereo. Overtones are affected by the shades of colors. I envision that with the right set-up, this tool or a future iteration of it could be used in performance.

The directories application.macosx32/ and application.macosx64/ contain executables. They will only work if the program can identify the right camera--it should work for the built-in cameras on recent models of MacBooks.

The Processing code in audio-lization.pde requires the Ess sound library, which can be found here:
http://www.tree-axis.com/Ess/
