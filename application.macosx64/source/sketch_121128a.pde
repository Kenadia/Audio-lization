// Ignore y-value. Hue corresponds to pitch, brightness and saturation to overtones, lowpass, noise.

import processing.video.*;
import krister.Ess.*;

// Image input from camera
Capture cam;
final int cam_w = 400;
final int cam_h = 300;

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
final int voice_count = 5;
final int pitch_count = 8;
Synth synth;

// Audio output
final int SAMPLE_RATE = 44100;
AudioStream [] output_streams;

void setup() {
  size(400, 300);
  frameRate(30);
  
  // Initialize camera
  // cam = new Capture(this, "name=FaceTime HD Camera (Built-in),size=1280x720,fps=30");
  // cam = new Capture(this, "name=Logitech Camera,size=400x300,fps=30");
  cam = new Capture(this, "name=FaceTime HD Camera (Built-in),size=400x300,fps=30");
  if (cam == null) {
    cam = new Capture(this, "name=FaceTime Camera (Built-in),size=400x300,fps=30");
  }
  if (cam == null) {
    cam = new Capture(this, "name=iSight Camera (Built-in),size=400x300,fps=30");
  }
  cam.start();
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
  println("stop");
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
    color [] cropped = crop(pix, cam.width, 160, 120, 80, 60);
    synth.playImage(cropped, 80);
    noFill();
    stroke(255, 180);
    rect(160 - 1, 120 - 1, 80 + 1, 60 + 1);
    stroke(127, 180);
    rect(160 - 2, 120 - 2, 80 + 3, 60 + 3);
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
      int x = image_w - (i % image_w) - 1; // FLIP
      int y = i / image_w;
      int voice_id = voice_count * x / image_w;
      color c = pix[i];
      voices[voice_id].addPoint(y, c);
    }
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
  SynthUnit [] [] synth_units;
  float [] [] powers;
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
    this.powers = new float[hue_count][shade_count];
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
    for (int i = 0; i < hue_count; i++) {
      for (int j = 0; j < shade_count; j++) {
        powers[i][j] = 0.0;
      }
    }
    noise_level = 0.0;
  }
  void addPoint(int y, color c) {
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
      powers[left_hue_i][overtone] += (sa + br) * left_hue_amt;
      powers[right_hue_i][overtone] += (sa + br) * right_hue_amt;
    }
    noise_level += br;
  }
  void endFrame() {
    for (int i = 0; i < hue_count; i++) {
      for (int j = 0; j < shade_count; j++) {
        powers[i][j] /= pixel_count;
        synth_units[i][j].setVol(powers[i][j]);
      }
    }
    noise_level /= pixel_count;
    noise_level /= 2;
    /* Print
    println("Noise: " + noise_level);
    String [] colors = {"red", "orange", "yellow", "green", "cyan", "blue", "purple", "magenta"}; 
    for (int i = 0; i < 8; i++) {
      print(colors[i] + '\t');
      for (int j = 0; j < 5; j++) {
        float p = round(powers[i][j] * 10000) / 10000.;
        print(p + "\t\t");
      }
      println();
    }
    println();*/
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
  //TriangleWave tri;
  //SquareWave square;
  //SawtoothWave saw;
  SynthUnit(float pitch) {
    this.sine = new SineWave(pitch, 0.0);
    //this.tri = new TriangleWave(pitch, 0.0);
    //this.square = new SquareWave(pitch, 0.0);
    //this.saw = new SawtoothWave(pitch, 0.0);
  }
  void setVol(float vol) {
    sine.volume = vol;
  }
  void play(int r, int g, int b) {
    color c = color(r, g, b);
    float hu = hue(c) / 255.;
    float sa = saturation(c) / 255.;
    float br = brightness(c) / 255.;
    colorMode(HSB, 1.0);
    color hue_color = color(hu, 1.0, 1.0);
    colorMode(RGB, 255);
    float hue_r = red(hue_color) / 255.;
    float hue_g = green(hue_color) / 255.;
    float hue_b = blue(hue_color) / 255.;
    float tone_vol;
    if (br >= 0.5) {
      tone_vol = sa;
    } else {
      tone_vol = sa * br * 2;
    }
    tone_vol *= 0.1;
    //saw.volume = hue_r * tone_vol;
    //square.volume = hue_g * tone_vol;
    //sine.volume = hue_b * tone_vol;
  }
  void writeToStream(AudioStream stream) {
    sine.generate(stream, Ess.ADD);
    //tri.generate(stream, Ess.ADD);
    //square.generate(stream, Ess.ADD);
    //saw.generate(stream, Ess.ADD);
    // Adjust phase
    sine.phase += stream.size;
    sine.phase %= stream.sampleRate;
    //tri.phase = sine.phase;
    //square.phase = sine.phase;
    //saw.phase = sine.phase;
  }
}

class VoiceOne {
  AudioStream stream;
  float [] pitch_set;
  int pitch_count;
  SynthUnit [] synth_units;
  float phase;
  Silence silence;
  float last_noise_level;
  PinkNoise pink_noise;
  VoiceOne(AudioStream stream, float [] pitch_set) {
    this.stream = stream;
    this.pitch_set = pitch_set;
    this.pitch_count = pitch_set.length;
    this.synth_units = new SynthUnit[pitch_count];
    for (int i = 0; i < pitch_count; i++) {
      this.synth_units[i] = new SynthUnit(pitch_set[i]);
    }
    this.phase = 0;
    this.silence = new Silence();
    this.last_noise_level = 0.0;
    this.pink_noise = new PinkNoise(0.0);
  }
  void play(int region_y, int r, int g, int b) {
    // Reverse region_y since high pitches are at the top (low y-value)
    synth_units[pitch_count - region_y - 1].play(r, g, b);
  }
  void write() {
    silence.generate(stream);
    float noise_sum = 0.0;
    for (int i = 0; i < pitch_count; i++) {
      synth_units[i].writeToStream(stream);
      //noise_sum += synth_units[i].getNoiseLevel();
    }
    float avg_noise = noise_sum / pitch_count;
    pink_noise.volume = (avg_noise + 2 * last_noise_level) / 3;
    pink_noise.generate(stream, Ess.ADD);
  }
}

class SynthUnitOne {
  SineWave sine;
  TriangleWave tri;
  SquareWave square;
  SawtoothWave saw;
  PinkNoise pink_noise;
  SynthUnitOne(float pitch) {
    this.sine = new SineWave(pitch, 0.0);
    this.tri = new TriangleWave(pitch, 0.0);
    this.square = new SquareWave(pitch, 0.0);
    this.saw = new SawtoothWave(pitch, 0.0);
    this.sine = new SineWave(pitch, 0.0);
    this.pink_noise = new PinkNoise(0.0);
    this.sine.frequency = pitch;
    this.tri.frequency = pitch;
    this.square.frequency = pitch;
    this.saw.frequency = pitch;
  }
  void play(int r, int g, int b) {
    color c = color(r, g, b);
    float hu = hue(c) / 255.;
    float sa = saturation(c) / 255.;
    float br = brightness(c) / 255.;
    colorMode(HSB, 1.0);
    color hue_color = color(hu, 1.0, 1.0);
    colorMode(RGB, 255);
    float hue_r = red(hue_color) / 255.;
    float hue_g = green(hue_color) / 255.;
    float hue_b = blue(hue_color) / 255.;
    float tone_vol;
    if (br >= 0.5) {
      pink_noise.volume = (br - 0.5) * (1.0 - sa) * 2;
      tone_vol = sa;
    } else {
      pink_noise.volume = 0.0;
      tone_vol = sa * br * 2;
    }
    tone_vol *= 0.1;
    saw.volume = hue_r * tone_vol;
    square.volume = hue_g * tone_vol;
    sine.volume = hue_b * tone_vol;
  }
  void writeToStream(AudioStream stream) {
    //pink_noise.generate(stream, Ess.ADD);
    sine.generate(stream, Ess.ADD);
    tri.generate(stream, Ess.ADD);
    square.generate(stream, Ess.ADD);
    saw.generate(stream, Ess.ADD);
    sine.phase += stream.size;
    sine.phase %= stream.sampleRate;
    tri.phase = sine.phase;
    square.phase = sine.phase;
    saw.phase = sine.phase;
  }
  float getNoiseLevel() {
    return pink_noise.volume;
  }
}
