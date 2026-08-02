import os
import wave
import struct
import math
import random

# Create audio output directory if it doesn't exist
os.makedirs("audio", exist_ok=True)

SAMPLE_RATE = 44100

def save_wav(filename, data, sample_rate=44100):
    filepath = os.path.join("audio", filename)
    with wave.open(filepath, 'wb') as wav_file:
        wav_file.setparams((1, 2, sample_rate, len(data), 'NONE', 'not compressed'))
        for sample in data:
            # Clamp value
            val = int(max(-32768, min(32767, sample * 32767)))
            wav_file.writeframes(struct.pack('<h', val))
    print(f"Generated {filepath} with {len(data)} samples (~{len(data)/sample_rate:.2f} seconds)")

def adsr_envelope(t, duration, attack=0.01, decay=0.05, sustain=0.7, release=0.1):
    if t < attack:
        return t / attack
    elif t < attack + decay:
        t_decay = (t - attack) / decay
        return 1.0 - (1.0 - sustain) * t_decay
    elif t < duration:
        return sustain
    elif t < duration + release:
        t_release = (t - duration) / release
        return sustain * (1.0 - t_release)
    else:
        return 0.0

def get_phase(t, freq, sample_rate, vibrato_freq=6.0, vibrato_depth=0.0):
    w = 2.0 * math.pi * vibrato_freq
    if vibrato_depth > 0.0:
        val = freq * (t - (vibrato_depth / w) * math.cos(w * t))
    else:
        val = freq * t
    return 2.0 * math.pi * val

def generate_wave(waveform, phase, duty_cycle=0.5):
    p = phase % (2.0 * math.pi)
    if waveform == 'sine':
        return math.sin(p)
    elif waveform == 'square':
        return 1.0 if p < (2.0 * math.pi * duty_cycle) else -1.0
    elif waveform == 'triangle':
        norm_p = p / (2.0 * math.pi)
        if norm_p < 0.25:
            return norm_p * 4.0
        elif norm_p < 0.75:
            return 2.0 - norm_p * 4.0
        else:
            return norm_p * 4.0 - 4.0
    elif waveform == 'sawtooth':
        norm_p = p / (2.0 * math.pi)
        return 2.0 * norm_p - 1.0
    elif waveform == 'noise':
        return random.uniform(-1.0, 1.0)
    return 0.0

# ==========================================
# MODERN SYNTHESIS UTILITIES
# ==========================================

def apply_delay_reverb(samples, delay_seconds=0.22, decay=0.35, sample_rate=44100):
    """Simulates space reverb using a feedback delay line."""
    delay_samples = int(delay_seconds * sample_rate)
    out = list(samples)
    for i in range(delay_samples, len(samples)):
        out[i] += out[i - delay_samples] * decay
    return out

def generate_supersaw(freq, duration, sample_rate, detuning=0.006, volume=1.0):
    """Sum of multiple detuned sawtooth waves to create a wide modern lead sound."""
    num_samples = int(duration * sample_rate)
    samples = [0.0] * num_samples
    detunes = [-2.0, -1.0, 0.0, 1.0, 2.0]
    for d in detunes:
        f = freq * (1.0 + d * detuning)
        for i in range(num_samples):
            t = i / sample_rate
            phase = (2.0 * math.pi * f * t) % (2.0 * math.pi)
            samples[i] += ((phase / math.pi) - 1.0)
    
    # Normalize and scale
    for i in range(num_samples):
        samples[i] = (samples[i] / 5.0) * volume
    return samples

def generate_pad_chord(midi_notes, duration, sample_rate=44100, volume=1.0):
    """Warm chord pad using detuned oscillators with slow attack and release."""
    num_samples = int(duration * sample_rate)
    chord_samples = [0.0] * num_samples
    for note in midi_notes:
        freq = midi_to_freq(note)
        samples = generate_supersaw(freq, duration, sample_rate, detuning=0.003, volume=volume / len(midi_notes))
        for i in range(num_samples):
            t = i / sample_rate
            # Smooth pad envelope
            env = adsr_envelope(t, duration - 0.4, attack=0.3, decay=0.4, sustain=0.8, release=0.3)
            chord_samples[i] += samples[i] * env
    return chord_samples

def generate_bass_note(freq, duration, sample_rate=44100, volume=1.0):
    """Synthwave bass note combining a deep sub sine and warm triangle."""
    num_samples = int(duration * sample_rate)
    samples = []
    for i in range(num_samples):
        t = i / sample_rate
        phase = (2.0 * math.pi * freq * t) % (2.0 * math.pi)
        
        # Sub-bass sine + warm triangle harmonics
        val_sine = math.sin(phase)
        norm_p = phase / (2.0 * math.pi)
        if norm_p < 0.25:
            val_tri = norm_p * 4.0
        elif norm_p < 0.75:
            val_tri = 2.0 - norm_p * 4.0
        else:
            val_tri = norm_p * 4.0 - 4.0
            
        val = 0.75 * val_sine + 0.25 * val_tri
        env = adsr_envelope(t, duration - 0.02, attack=0.01, decay=0.08, sustain=0.8, release=0.05)
        samples.append(val * env * volume)
    return samples

def generate_lead_note(freq, duration, sample_rate=44100, volume=1.0):
    """Supersaw lead note with vibrato and ADSR."""
    num_samples = int(duration * sample_rate)
    samples = generate_supersaw(freq, duration, sample_rate, detuning=0.005, volume=volume)
    for i in range(num_samples):
        t = i / sample_rate
        # Add a bit of natural vibrato over time
        vibrato = 1.0 + 0.006 * math.sin(2.0 * math.pi * 6.0 * t)
        env = adsr_envelope(t, duration - 0.03, attack=0.015, decay=0.08, sustain=0.6, release=0.08)
        samples[i] *= env * vibrato
    return samples

def mix_samples_wrap(buffer, sample_index, note_samples):
    buffer_len = len(buffer)
    for i in range(len(note_samples)):
        idx = (sample_index + i) % buffer_len
        buffer[idx] += note_samples[i]

def midi_to_freq(note):
    if note == 0:
        return 0.0
    return 440.0 * 2.0 ** ((note - 69.0) / 12.0)

# ==========================================
# MODERN DRUM SYNTHESIS
# ==========================================

def generate_modern_kick(sample_rate=44100):
    """Punchy modern electronic kick with a transient click and deep sub-sweep."""
    duration = 0.15
    num_samples = int(duration * sample_rate)
    samples = []
    for i in range(num_samples):
        t = i / sample_rate
        # Exponential frequency sweep: start at 250Hz, sweep down to 45Hz
        freq = 45.0 + (250.0 - 45.0) * math.exp(-t * 60.0)
        phase = 2.0 * math.pi * (45.0 * t + (250.0 - 45.0) / 60.0 * (1.0 - math.exp(-t * 60.0)))
        sine = math.sin(phase)
        
        # High frequency noise transient click for impact definition
        click_env = math.exp(-t * 400.0)
        click = random.uniform(-1.0, 1.0) * click_env
        
        # Exponential decay volume envelope
        env = math.exp(-t * 12.0)
        val = 0.85 * sine + 0.15 * click
        samples.append(val * env * 0.8)
    return samples

def generate_modern_snare(sample_rate=44100):
    """Big electronic snare: sweeping sine body mixed with gated white noise and reverb."""
    duration = 0.22
    num_samples = int(duration * sample_rate)
    samples = []
    for i in range(num_samples):
        t = i / sample_rate
        # Snare body (180 Hz sweeping to 100 Hz)
        freq_body = 100.0 + 80.0 * math.exp(-t * 45.0)
        phase_body = 2.0 * math.pi * (100.0 * t + 80.0 / 45.0 * (1.0 - math.exp(-t * 45.0)))
        body = math.sin(phase_body) * math.exp(-t * 25.0)
        
        # Noise component (snare wires rattle)
        noise = random.uniform(-1.0, 1.0) * math.exp(-t * 9.0)
        
        val = 0.35 * body + 0.65 * noise
        env = 1.0 - (t / duration)
        samples.append(val * env * 0.45)
    # Apply early reflections delay to widen the snare
    return apply_delay_reverb(samples, delay_seconds=0.06, decay=0.25, sample_rate=sample_rate)

def generate_modern_hihat(sample_rate=44100):
    """Crisp modern open hi-hat: high-pass filtered white noise with fast decay."""
    duration = 0.08
    num_samples = int(duration * sample_rate)
    samples = []
    prev = 0.0
    for i in range(num_samples):
        t = i / sample_rate
        noise = random.uniform(-1.0, 1.0)
        # Simple differential high-pass filter
        val = noise - prev
        prev = noise
        env = math.exp(-t * 40.0)
        samples.append(val * env * 0.15)
    return samples

# ==========================================
# 1. GENERATE MODERN BGM THEME
# ==========================================
print("Generating Modern BGM Theme...")
BPM = 110
step_dur = 60.0 / BPM / 4.0 # 16th note step = 0.136 seconds
total_steps = 128
song_dur = total_steps * step_dur # ~17.45 seconds
num_samples = int(song_dur * SAMPLE_RATE)
bgm_buffer = [0.0] * num_samples

# Compose Chord Progression Pads (Am, F, C, G)
pad_progression = [
    # Bar 1 & 2 (Am)
    (0, [45, 48, 52, 57], 32),
    # Bar 3 & 4 (F)
    (32, [41, 45, 48, 53], 32),
    # Bar 5 & 6 (C)
    (64, [36, 40, 43, 48], 32),
    # Bar 7 & 8 (G)
    (96, [43, 47, 50, 55], 32)
]

# Compose Rolling Bass (galop pattern: octave bounces on 8th notes)
bass_progression = [
    # Am
    (45, 57), (45, 57),
    # F
    (41, 53), (41, 53),
    # C
    (36, 48), (36, 48),
    # G
    (43, 55), (43, 55)
]
bass_data = []
for bar in range(8):
    root, octave = bass_progression[bar // 1] # 1 bar each
    start_step = bar * 16
    for step in range(0, 16, 2): # 8th notes
        note = root if (step % 4 == 0) else octave
        bass_data.append((start_step + step, note, 2))

# Compose Soaring Melody Hook
melody_data = [
    # Bar 1 (Am)
    (0, 69, 4),  # A4
    (4, 71, 4),  # B4
    (8, 72, 8),  # C5
    # Bar 2 (Am)
    (16, 76, 4), # E5
    (20, 74, 4), # D5
    (24, 72, 4), # C5
    (28, 71, 4), # B4
    # Bar 3 (F)
    (32, 65, 4), # F4
    (36, 67, 4), # G4
    (40, 69, 8), # A4
    # Bar 4 (F)
    (48, 72, 4), # C5
    (52, 71, 4), # B4
    (56, 69, 4), # A4
    (60, 67, 4), # G4
    # Bar 5 (C)
    (64, 72, 4), # C5
    (68, 74, 4), # D5
    (72, 76, 8), # E5
    # Bar 6 (C)
    (80, 81, 4), # A5
    (84, 79, 4), # G5
    (88, 76, 4), # E5
    (92, 74, 4), # D5
    # Bar 7 (G)
    (96, 74, 4),  # D5
    (100, 76, 4), # E5
    (104, 74, 8), # D5
    # Bar 8 (G)
    (112, 71, 4), # B4
    (116, 67, 4), # G4
    (120, 69, 8)  # A4
]

# 1. Mix Pad Chords
for step, notes, dur_steps in pad_progression:
    chord_samples = generate_pad_chord(notes, dur_steps * step_dur, SAMPLE_RATE, volume=0.25)
    mix_samples_wrap(bgm_buffer, int(step * step_dur * SAMPLE_RATE), chord_samples)

# 2. Mix Rolling Bass
for step, note, dur_steps in bass_data:
    freq = midi_to_freq(note)
    bass_samples = generate_bass_note(freq, dur_steps * step_dur, SAMPLE_RATE, volume=0.35)
    mix_samples_wrap(bgm_buffer, int(step * step_dur * SAMPLE_RATE), bass_samples)

# 3. Mix Lead Melody
lead_buffer = [0.0] * num_samples
for step, note, dur_steps in melody_data:
    freq = midi_to_freq(note)
    # articulate gate
    gate = dur_steps * step_dur - 0.03
    lead_samples = generate_lead_note(freq, gate, SAMPLE_RATE, volume=0.3)
    mix_samples_wrap(lead_buffer, int(step * step_dur * SAMPLE_RATE), lead_samples)

# Apply spacious delay reverb to the lead melody
lead_reverbed = apply_delay_reverb(lead_buffer, delay_seconds=0.27, decay=0.38, sample_rate=SAMPLE_RATE)
for i in range(num_samples):
    bgm_buffer[i] += lead_reverbed[i]

# 4. Mix Modern Drums (Four-on-the-floor driving beat)
kick_samples = generate_modern_kick(SAMPLE_RATE)
snare_samples = generate_modern_snare(SAMPLE_RATE)
hihat_samples = generate_modern_hihat(SAMPLE_RATE)

for step in range(total_steps):
    sample_idx = int(step * step_dur * SAMPLE_RATE)
    # Kick on every beat (steps 0, 4, 8, 12...)
    if step % 4 == 0:
        mix_samples_wrap(bgm_buffer, sample_idx, kick_samples)
    # Snare on beats 2 and 4 (steps 4, 12, 20...)
    if step % 8 == 4:
        mix_samples_wrap(bgm_buffer, sample_idx, snare_samples)
    # Hi-hat on offbeats (steps 2, 6, 10, 14...)
    if step % 4 == 2:
        mix_samples_wrap(bgm_buffer, sample_idx, hihat_samples)

# Normalize BGM to avoid clipping
max_val = max(abs(x) for x in bgm_buffer)
if max_val > 0.99:
    bgm_buffer = [x / max_val * 0.95 for x in bgm_buffer]

save_wav("music_theme.wav", bgm_buffer, SAMPLE_RATE)

# ==========================================
# 1B. GENERATE CONVOY MUSIC THEME (Intense Action Theme)
# ==========================================
print("Generating Convoy Music Theme...")
convoy_BPM = 130
convoy_step_dur = 60.0 / convoy_BPM / 4.0 # 0.11538 seconds
convoy_total_steps = 128
convoy_song_dur = convoy_total_steps * convoy_step_dur # ~14.77 seconds
convoy_num_samples = int(convoy_song_dur * SAMPLE_RATE)
convoy_buffer = [0.0] * convoy_num_samples

# Compose Chord Progression Pads (Em, C, D, Bm)
convoy_pad_progression = [
    (0, [40, 43, 47, 52], 32),   # Em
    (32, [36, 40, 43, 48], 32),  # C
    (64, [38, 42, 45, 50], 32),  # D
    (96, [35, 38, 42, 47], 32)   # Bm (35, 38, 42, 47)
]

# Rolling Bass progression
convoy_bass_progression = [
    (40, 52), # Em
    (36, 48), # C
    (38, 50), # D
    (35, 47)  # Bm
]
convoy_bass_data = []
for bar in range(8):
    root, octave = convoy_bass_progression[(bar // 1) % 4]
    start_step = bar * 16
    for step in range(0, 16, 2): # 8th notes
        note = root if (step % 4 == 0) else octave
        convoy_bass_data.append((start_step + step, note, 2))

# Melody Pluck Arpeggio
convoy_chords_arp = [
    [52, 55, 59, 64], # Em
    [48, 52, 55, 60], # C
    [50, 54, 57, 62], # D
    [47, 50, 54, 59]  # Bm
]
convoy_arp_data = []
for bar in range(8):
    chord_notes = convoy_chords_arp[(bar // 1) % 4]
    for step in range(16):
        s = bar * 16 + step
        note = chord_notes[step % 4]
        convoy_arp_data.append((s, note, 1))

# Mix Pad Chords
for step, notes, dur_steps in convoy_pad_progression:
    chord_samples = generate_pad_chord(notes, dur_steps * convoy_step_dur, SAMPLE_RATE, volume=0.22)
    mix_samples_wrap(convoy_buffer, int(step * convoy_step_dur * SAMPLE_RATE), chord_samples)

# Mix Rolling Bass
for step, note, dur_steps in convoy_bass_data:
    freq = midi_to_freq(note)
    bass_samples = generate_bass_note(freq, dur_steps * convoy_step_dur, SAMPLE_RATE, volume=0.38)
    mix_samples_wrap(convoy_buffer, int(step * convoy_step_dur * SAMPLE_RATE), bass_samples)

# Mix Arpeggio Pluck Lead
convoy_lead_buffer = [0.0] * convoy_num_samples
for step, note, dur_steps in convoy_arp_data:
    freq = midi_to_freq(note)
    n_samples = generate_supersaw(freq, dur_steps * convoy_step_dur, SAMPLE_RATE, detuning=0.005, volume=0.28)
    for i in range(len(n_samples)):
        t = i / SAMPLE_RATE
        env = math.exp(-t * 22.0)
        n_samples[i] *= env
    mix_samples_wrap(convoy_lead_buffer, int(step * convoy_step_dur * SAMPLE_RATE), n_samples)

convoy_lead_reverbed = apply_delay_reverb(convoy_lead_buffer, delay_seconds=0.18, decay=0.3, sample_rate=SAMPLE_RATE)
for i in range(convoy_num_samples):
    convoy_buffer[i] += convoy_lead_reverbed[i]

# Mix Drums
ck_samples = generate_modern_kick(SAMPLE_RATE)
sn_samples = generate_modern_snare(SAMPLE_RATE)
hh_samples = generate_modern_hihat(SAMPLE_RATE)

for step in range(convoy_total_steps):
    sample_idx = int(step * convoy_step_dur * SAMPLE_RATE)
    if step % 4 == 0:
        mix_samples_wrap(convoy_buffer, sample_idx, ck_samples)
    if step % 8 == 4:
        mix_samples_wrap(convoy_buffer, sample_idx, sn_samples)
    if step % 2 == 1:
        mix_samples_wrap(convoy_buffer, sample_idx, hh_samples)

# Normalize
c_max = max(abs(x) for x in convoy_buffer)
if c_max > 0.99:
    convoy_buffer = [x / c_max * 0.95 for x in convoy_buffer]

save_wav("music_convoy.wav", convoy_buffer, SAMPLE_RATE)

# ==========================================
# 2. GENERATE MODERN COIN SFX (Clean Retro Ping)
# ==========================================
print("Generating modern coin SFX...")
# Note 1: E5 (659.25 Hz) for 0.05 seconds
n1 = []
for i in range(int(0.05 * SAMPLE_RATE)):
    t = i / SAMPLE_RATE
    phase = 2.0 * math.pi * 659.25 * t
    norm_p = (phase % (2.0 * math.pi)) / (2.0 * math.pi)
    tri = norm_p * 4.0 if norm_p < 0.25 else (2.0 - norm_p * 4.0 if norm_p < 0.75 else norm_p * 4.0 - 4.0)
    sine = math.sin(phase)
    n1.append((0.6 * tri + 0.4 * sine) * math.exp(-t * 20.0) * 0.45)

# Note 2: B5 (987.77 Hz) for 0.22 seconds
n2 = []
for i in range(int(0.22 * SAMPLE_RATE)):
    t = i / SAMPLE_RATE
    phase = 2.0 * math.pi * 987.77 * t
    norm_p = (phase % (2.0 * math.pi)) / (2.0 * math.pi)
    tri = norm_p * 4.0 if norm_p < 0.25 else (2.0 - norm_p * 4.0 if norm_p < 0.75 else norm_p * 4.0 - 4.0)
    sine = math.sin(phase)
    n2.append((0.6 * tri + 0.4 * sine) * math.exp(-t * 20.0) * 0.45)

combined = n1 + n2
# Apply moving average filter to soften the waveforms (removes raw aliasing buzz)
filtered = []
for i in range(len(combined)):
    val = 0.0
    count = 0
    for w in range(5):
        idx = i - w
        if idx >= 0:
            val += combined[idx]
            count += 1
    filtered.append(val / count if count > 0 else 0.0)

filtered = apply_delay_reverb(filtered, delay_seconds=0.06, decay=0.25, sample_rate=SAMPLE_RATE)
save_wav("sfx_coin.wav", filtered, SAMPLE_RATE)

# ==========================================
# 3. GENERATE MODERN CLICK SFX
# ==========================================
print("Generating modern click SFX...")
click_dur = 0.03
click_samples = []
for i in range(int(click_dur * SAMPLE_RATE)):
    t = i / SAMPLE_RATE
    # High frequency organic sine click + small noise transient
    freq = 2500.0 * math.exp(-t * 120.0)
    sine = math.sin(2.0 * math.pi * freq * t)
    noise = random.uniform(-1.0, 1.0) * math.exp(-t * 300.0)
    val = 0.8 * sine + 0.2 * noise
    env = math.exp(-t * 90.0)
    click_samples.append(val * env * 0.3)
save_wav("sfx_click.wav", click_samples, SAMPLE_RATE)

# ==========================================
# 4. GENERATE MODERN JUMP SFX (Whoosh Sweep)
# ==========================================
print("Generating modern jump SFX...")
jump_dur = 0.22
jump_samples = [0.0] * int(jump_dur * SAMPLE_RATE)
for i in range(len(jump_samples)):
    t = i / jump_dur
    # Whoosh sweep: sine sweep 180Hz to 600Hz + noise sweep
    freq = 180.0 + 420.0 * t
    phase = 2.0 * math.pi * (180.0 * (i/SAMPLE_RATE) + 0.5 * 420.0 * ((i/SAMPLE_RATE)**2 / jump_dur))
    sine = math.sin(phase)
    noise = random.uniform(-1.0, 1.0)
    val = 0.55 * sine + 0.45 * noise
    env = math.sin(t * math.pi) * (1.0 - t) # bell curve
    jump_samples[i] = val * env * 0.4

jump_samples = apply_delay_reverb(jump_samples, delay_seconds=0.07, decay=0.3, sample_rate=SAMPLE_RATE)
save_wav("sfx_jump.wav", jump_samples, SAMPLE_RATE)

# ==========================================
# 5. GENERATE MODERN CRASH SFX (Sub Blast)
# ==========================================
print("Generating modern crash SFX...")
crash_dur = 0.6
crash_samples = [0.0] * int(crash_dur * SAMPLE_RATE)
for i in range(len(crash_samples)):
    t = i / SAMPLE_RATE
    # 1. Deep sub sweep: 180 Hz down to 30 Hz
    freq_sub = 30.0 + 150.0 * math.exp(-t * 25.0)
    phase_sub = 2.0 * math.pi * (30.0 * t + 150.0 / 25.0 * (1.0 - math.exp(-t * 25.0)))
    sub = math.sin(phase_sub) * math.exp(-t * 12.0)
    
    # 2. Crash impact noise
    noise = random.uniform(-1.0, 1.0) * math.exp(-t * 18.0)
    
    val = 0.4 * sub + 0.6 * noise
    env = math.exp(-t * 6.0)
    crash_samples[i] = val * env * 0.65

crash_samples = apply_delay_reverb(crash_samples, delay_seconds=0.12, decay=0.3, sample_rate=SAMPLE_RATE)
save_wav("sfx_crash.wav", crash_samples, SAMPLE_RATE)

# ==========================================
# 6. GENERATE MODERN GLASS SHATTER SFX
# ==========================================
print("Generating modern glass shatter SFX...")
glass_dur = 0.5
glass_samples = [0.0] * int(glass_dur * SAMPLE_RATE)
for i in range(len(glass_samples)):
    t = i / SAMPLE_RATE
    noise = random.uniform(-1.0, 1.0) * math.exp(-t * 15.0)
    
    # Multiple fluttering high-pitch glassy frequencies
    sine1 = math.sin(2.0 * math.pi * 3600.0 * t)
    sine2 = math.sin(2.0 * math.pi * 4800.0 * t)
    sine3 = math.sin(2.0 * math.pi * 6500.0 * t)
    sine4 = math.sin(2.0 * math.pi * 8000.0 * t)
    
    # Amplitude modulation to simulate crackling pieces bouncing
    flutter = 1.0 + 0.4 * math.sin(2.0 * math.pi * 35.0 * t)
    val = 0.4 * noise + 0.25 * sine1 + 0.15 * sine2 + 0.1 * sine3 + 0.1 * sine4
    env = math.exp(-t * 8.5) * flutter
    glass_samples[i] = val * env * 0.45

glass_samples = apply_delay_reverb(glass_samples, delay_seconds=0.09, decay=0.35, sample_rate=SAMPLE_RATE)
save_wav("sfx_glass.wav", glass_samples, SAMPLE_RATE)

# ==========================================
# 7. GENERATE MODERN VICTORY SFX (EDM Fanfare)
# ==========================================
print("Generating modern victory SFX...")
vic_dur = 1.2
vic_samples = [0.0] * int(vic_dur * SAMPLE_RATE)

# A triumphant synth chord sequence (Amin -> Fmaj -> Cmaj -> Gmaj)
vic_chords = [
    (0.0, 0.25, [57, 60, 64, 69]), # Amin
    (0.25, 0.5, [53, 57, 60, 65]), # Fmaj
    (0.5, 0.75, [48, 52, 55, 60]), # Cmaj
    (0.75, 1.1, [55, 59, 62, 67])  # Gmaj
]

for start_t, end_t, notes in vic_chords:
    chord_len = end_t - start_t
    c_samples = generate_pad_chord(notes, chord_len, SAMPLE_RATE, volume=0.35)
    start_idx = int(start_t * SAMPLE_RATE)
    for i in range(len(c_samples)):
        idx = start_idx + i
        if idx < len(vic_samples):
            vic_samples[idx] += c_samples[i]

vic_samples = apply_delay_reverb(vic_samples, delay_seconds=0.18, decay=0.35, sample_rate=SAMPLE_RATE)
save_wav("sfx_victory.wav", vic_samples, SAMPLE_RATE)

# ==========================================
# 8. GENERATE MODERN HORN SFX
# ==========================================
print("Generating modern horn SFX...")
horn_dur = 0.45
horn_samples = []
for i in range(int(horn_dur * SAMPLE_RATE)):
    t = i / SAMPLE_RATE
    # Standard dual-tone vehicle horn frequencies: 435 Hz and 580 Hz
    phase1 = 2.0 * math.pi * 435.0 * t
    phase2 = 2.0 * math.pi * 580.0 * t
    
    # Layer and add soft clipping saturation for a rich analog tone
    val = 0.5 * math.sin(phase1) + 0.5 * math.sin(phase2)
    # Warm saturation formula
    val_saturated = math.tanh(val * 1.5)
    
    env = adsr_envelope(t, horn_dur - 0.05, attack=0.015, decay=0.05, sustain=0.9, release=0.04)
    horn_samples.append(val_saturated * env * 0.35)
save_wav("sfx_horn.wav", horn_samples, SAMPLE_RATE)

# ==========================================
# 9. GENERATE MODERN ENGINE SFX LOOP
# ==========================================
print("Generating modern engine loop...")
eng_dur = 1.0
eng_samples = [0.0] * int(eng_dur * SAMPLE_RATE)

# Looping noise base
eng_noise = [random.uniform(-1.0, 1.0) for _ in range(int(eng_dur * SAMPLE_RATE))]
eng_fade = int(0.12 * SAMPLE_RATE)
for i in range(eng_fade):
    t = i / eng_fade
    blend = eng_noise[i] * t + eng_noise[len(eng_noise) - eng_fade + i] * (1.0 - t)
    eng_noise[i] = blend
    eng_noise[len(eng_noise) - eng_fade + i] = blend

for i in range(len(eng_samples)):
    t = i / SAMPLE_RATE
    # Base deep rumble (55Hz sub) + low-mid warm harmonic (110Hz triangle)
    sub = math.sin(2.0 * math.pi * 55.0 * t)
    
    # triangle 110Hz
    phase_tri = (2.0 * math.pi * 110.0 * t) % (2.0 * math.pi)
    norm_tri = phase_tri / (2.0 * math.pi)
    if norm_tri < 0.25:
        tri = norm_tri * 4.0
    elif norm_tri < 0.75:
        tri = 2.0 - norm_tri * 4.0
    else:
        tri = norm_tri * 4.0 - 4.0
        
    # low pass filtered engine noise rumble
    noise_rumble = eng_noise[i] * 0.18
    
    val = 0.5 * sub + 0.35 * tri + 0.15 * noise_rumble
    # soft analog clip saturation
    eng_samples[i] = math.tanh(val * 1.2) * 0.45

save_wav("sfx_engine.wav", eng_samples, SAMPLE_RATE)

print("All modern day audio assets generated successfully!")
