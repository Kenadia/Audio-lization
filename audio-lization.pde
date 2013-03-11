// Added smooth panning and complex waves, also with smooth transitioning.

import processing.video.*;
import krister.Ess.*;

// Image input from camera
// NOTE width and height must be set here and in size() in accordance
  // with the dimensions of the camera used.
Capture cam;
final int cam_w = 640;
final int cam_h = 480;

/* The synthesizer instrument is an array of voices.
 *   Each voice is panned differently and corresponds to a vertical section of the image.
 *   Each voice consists of an AudioStream and an array of synth units.
 *   Version 1:
 *     Each synth unit corresponds to a rectangle within the voice's part of the image
 *       and is pitched according to location on the y-axis.
 *   Version 2:
 *     Each synth unit corresponds to a particular shade and corresponding overtone of a hue.
 *   Each synth unit contains a set of basic Ess generators and effects.
 */
final int voice_count = 2;
final boolean smooth_pan = true;
final boolean complex_wave = false;
Synth synth;

// Audio output
final int SAMPLE_RATE = 44100;
AudioStream [] output_streams;

void setup() {
  size(640, 480);
  frameRate(30);
  
  // Initialize camera
  // cam = new Capture(this, "name=FaceTime HD Camera (Built-in),size=1280x720,fps=30");
  // cam = new Capture(this, "name=Logitech Camera,size=400x300,fps=30");
  cam = new Capture(this, "name=FaceTime HD Camera (Built-in),size=640x480,fps=30");
  try {
    cam.start();
  } catch (NullPointerException e) {
    println("Camera not found. Your available cameras are:");
    String[] cameras = Capture.list();
    for (String cam : cameras) {
      println("  " + cam);
    }
    println("\nPlease modify the code to use an available camera.");
    exit();
  }
  
  // Audio output
  Ess.start(this);
  output_streams = new AudioStream[voice_count];
  for (int i = 0; i < voice_count; i++) {
    output_streams[i] = new AudioStream();
    output_streams[i].start();
  }
  
  // Initialize the instrument
  synth = new Synth(output_streams);
}

public void stop() {
  Ess.stop();
  super.stop();
}

color [] crop(color [] pix, int image_w, int x, int y, int w, int h) {
  color [] cropped = new color[w * h];
  for (int i = 0; i < w; i++) {
    for (int j = 0; j < h; j++) {
      cropped[i + j * w] = pix[x + i + (y + j) * image_w];
    }
  }
  return cropped;
}

void draw() {
  if (cam.available() == true) {
    cam.read();
    // FLIP
    pushMatrix();
    scale(-1.0, 1.0);
    image(cam, -cam.width, 0);
    popMatrix();
    //
    color [] pix = cam.pixels;
    int cropX = cam.width * 3 / 8;
    int cropY = cam.height * 3 / 8;
    int cropW = cam.width / 4;
    int cropH = cam.height / 4;
    color [] cropped = crop(pix, cam.width, cropX, cropY, cropW, cropH);
    synth.playImage(cropped, cropW);
    noFill();
    stroke(255, 180);
    rect(cropX - 1, cropY - 1, cropW + 1, cropH + 1);
    stroke(127, 180);
    rect(cropX - 2, cropY - 2, cropW + 3, cropH + 3);
  }
}

void audioStreamWrite(AudioStream stream) {
  synth.writeStream(stream);
}

class Synth {
  final float [] hue_set = {0.0, 0.097, 0.164, 0.309, 0.490, 0.652, 0.730, 0.838};
//  final float [] fundamentals = {58.2705, 65.4064, 69.2957, 77.7817, 82.4069, 43.6535, 48.9994, 51.9131};
  final float [] fundamentals = {65.4064, 48.9994, 73.4162, 58.2705, 38.8909, 51.9131, 77.7817, 87.3071};
    // red, orange, yellow, green, cyan, blue, purple, magenta
    // Bb,  C,      C#,     D#,    E,    F,    G,      G#
    // C,   G,      D,      Bb,    Eb,   G#,   D#,     F
    // Fundamentals are in range F1 to E2, blue is lowest
  AudioStream [] output_streams;
  int voice_count;
  Voice [] voices;
  Synth(AudioStream [] output_streams) {
    this.output_streams = output_streams;
    this.voice_count = output_streams.length;
    this.voices = new Voice[voice_count];
    for (int i = 0; i < voice_count; i++) {
      float pan = voice_count == 1? 0.0 : i * 2. / (voice_count - 1) - 1;
      output_streams[i].pan(pan);
      // this.voices[i] = new Voice(output_streams[i], a_minor);
      this.voices[i] = new Voice(output_streams[i], hue_set, fundamentals);
    }
  }
  void playImage(color [] pix, int image_w) {
    int pixel_count = pix.length;
    for (int i = 0; i < voice_count; i++) {
      voices[i].startFrame(pixel_count);
    }
    for (int i = 0; i < pixel_count; i++) {
      color c = pix[i];
      int x = image_w - (i % image_w) - 1; // FLIP
      int image_h = pixel_count / image_w;
      int test = image_h - i / image_w - 1;
      float height_fraction = float(image_h - i / image_w - 1) / image_h;
      if (smooth_pan) { // if pan smoothing
        float regions_x = float((voice_count - 1) * x) / image_w;
        int left_voice_id = int(regions_x);
        int right_voice_id = left_voice_id + 1;
        float right_voice_amt = regions_x % 1;
        float left_voice_amt = 1.0 - right_voice_amt;
        voices[left_voice_id].addPoint(height_fraction, c, left_voice_amt);
        voices[right_voice_id].addPoint(height_fraction, c, right_voice_amt);
      } else {
        int voice_id = voice_count * x / image_w;
        voices[voice_id].addPoint(height_fraction, c, 1.0);
      }
    }
    println();
    for (int i = 0; i < voice_count; i++) {
      voices[i].endFrame();
    }
  }
  void writeStream(AudioStream stream) {
    int stream_id = -1;
    for (int i = 0; i < voice_count; i++) {
      if (output_streams[i] == stream) {
        stream_id = i;
      }
    }
    if (stream_id == -1) {
      println("ERROR: Unknown AudioStream");
    } else {
      voices[stream_id].write();
    }
  }
}

class Voice {
  AudioStream stream;
  float [] hue_set;
  int hue_count;
  final int shade_count = 5;
  final int waveform_count = 2;
  SynthUnit [] [] synth_units;
  float [] [] [] powers;
  // First dimension: hue
  // Second dimension: shade/overtone
  float noise_level;
  float last_noise_level;
  Silence silence;
  PinkNoise pink_noise;
  int pixel_count;
  Voice(AudioStream stream, float [] hue_set, float [] fundamentals) {
    this.stream = stream;
    this.hue_set = hue_set;
    this.hue_count = hue_set.length;
    this.synth_units = new SynthUnit[hue_count][shade_count];
    this.powers = new float[hue_count][shade_count][waveform_count];
    for (int i = 0; i < hue_count; i++) {
      for (int j = 0; j < shade_count; j++) {
        float freq = fundamentals[i] * pow(2, j);
        this.synth_units[i][j] = new SynthUnit(freq);
      }
    }
    this.noise_level = 0.0;
    this.last_noise_level = 0.0;
    this.silence = new Silence();
    this.pink_noise = new PinkNoise(0.0);
    this.pixel_count = 0;
  }
  void startFrame(int pixel_count) {
    this.pixel_count = pixel_count;
    if (complex_wave) {
      for (int i = 0; i < hue_count; i++) {
        for (int j = 0; j < shade_count; j++) {
          for (int k = 0; k < waveform_count; k++) {
            powers[i][j][k] = 0.0;
          }
        }
      }
    } else {
      for (int i = 0; i < hue_count; i++) {
        for (int j = 0; j < shade_count; j++) {
          powers[i][j][0] = 0.0;
        }
      }
    }
    noise_level = 0.0;
  }
  void addPoint(float height_fraction, color c, float amt) {
    float hu = hue(c) / 255.;
    float sa = saturation(c) / 255.;
    float br = brightness(c) / 255.;
    float shade = br - sa;
    int overtone;
    if (shade < -0.85) {
      overtone = -1;
    } else if (shade < -0.49) {
      overtone = 0;
    } else if (shade < -0.13) {
      overtone = 1;
    } else if (shade <= 0.23) {
      overtone = 2;
    } else if (shade <= 0.59) {
      overtone = 3;
    } else if (shade <= 0.95) {
      overtone = 4;
    } else {
      overtone = -1;
    }
    if (overtone >= 0) {
      int left_hue_i = -1, right_hue_i = -1;
      float left_hue_amt = 0.0, right_hue_amt = 0.0;
      for (int i = hue_count - 1; i >= 0; i--) {
        if (hu >= hue_set[i]) {
          left_hue_i = i;
          if (i == hue_count - 1) {
            right_hue_i = 0;
            right_hue_amt = (hu - hue_set[i]) / (1.0 - hue_set[i]);
          } else {
            right_hue_i = i + 1;
            right_hue_amt = (hu - hue_set[i]) / (hue_set[i + 1] - hue_set[i]);
          }
          left_hue_amt = 1.0 - right_hue_amt;
          break;
        }
      }
      if (complex_wave) {
        float regions_y = height_fraction * (waveform_count - 1);
        int lower_wave_i = int(regions_y);
        int upper_wave_i = lower_wave_i + 1;
        float upper_wave_amt = regions_y % 1;
        float lower_wave_amt = 1.0 - upper_wave_amt;
        powers[left_hue_i][overtone][lower_wave_i] += (sa + br) * left_hue_amt * lower_wave_amt * amt;
        powers[right_hue_i][overtone][upper_wave_i] += (sa + br) * right_hue_amt * upper_wave_amt * amt;
      } else {
        powers[left_hue_i][overtone][0] += (sa + br) * left_hue_amt * amt;
        powers[right_hue_i][overtone][0] += (sa + br) * right_hue_amt * amt;
      }
    }
    noise_level += br;
  }
  void endFrame() {
    for (int i = 0; i < hue_count; i++) {
      for (int j = 0; j < shade_count; j++) {
        for (int k = 0; k < waveform_count; k++) {
          powers[i][j][k] /= pixel_count;
          if (!complex_wave) {
            break;
          }
        }
        synth_units[i][j].setVols(powers[i][j]);
      }
    }
    noise_level /= pixel_count;
    noise_level /= 2; // Max noise level of 0.5
  }
  void write() {
    silence.generate(stream);
    pink_noise.volume = (noise_level + 3 * last_noise_level) / 4;
    pink_noise.generate(stream, Ess.ADD);
    for (int i = 0; i < hue_count; i++) {
      for (int j = 0; j < shade_count; j++) {
        synth_units[i][j].writeToStream(stream);
      }
    }
  }
}

class SynthUnit {
  SineWave sine;
  TriangleWave tri;
  SquareWave square;
  SawtoothWave saw;
  SynthUnit(float pitch) {
    this.sine = new SineWave(pitch, 0.0);
    this.tri = new TriangleWave(pitch, 0.0);
    this.square = new SquareWave(pitch, 0.0);
    this.saw = new SawtoothWave(pitch, 0.0);
  }
  void setVols(float [] vol) {
    sine.volume = vol[0];
    if (complex_wave) {
      // tri.volume = vol[1];
      square.volume = vol[1] * 0.4;
      // saw.volume = vol[3];
    }
  }
  void writeToStream(AudioStream stream) {
    sine.generate(stream, Ess.ADD);
    tri.generate(stream, Ess.ADD);
    square.generate(stream, Ess.ADD);
    saw.generate(stream, Ess.ADD);
    // Adjust phase
    sine.phase += stream.size;
    sine.phase %= stream.sampleRate;
    tri.phase = sine.phase;
    square.phase = sine.phase;
    saw.phase = sine.phase;
  }
}
