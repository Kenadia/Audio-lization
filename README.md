# Audio-lization

This project explores algorithmic sound generation from video, sort of the inverse of a music visualizer. You can play it like a musical instrument using your webcam. Different colors and combinations of colors in the active area (center rectangle) produce different tones and combinations of tones in stereo. Overtones are affected by the shades of colors.

The directories application.macosx32/ and application.macosx64/ contain executables. They will only work if the program can identify the right camera--it should work for the built-in cameras on recent models of MacBooks.

The Processing code in audio-lization.pde requires the Ess sound library, which can be found here:
http://www.tree-axis.com/Ess/
