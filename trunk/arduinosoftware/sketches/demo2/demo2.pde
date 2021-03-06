// 4-chan TC w/ mcp3424 and mcp9800 using only standard Aurdino libraries
// Bill Welch 2010 http://github.com/bvwelch/arduino
// MIT license: http://opensource.org/licenses/mit-license.php
// Note: this small example is for K-type thermocouples only.
// FIXME: use Jim Gallt's library for a full-featured logger.
//       http://code.google.com/p/tc4-shield/ 

char *banner = "a_logger15";

#include <Wire.h>

#define A_ADC 0x68
#define A_AMB 0x48

#define MICROVOLT_TO_C 40.69 // K-type only, linear approx.

#define CFG 0x1B     // continuous, 16-bit, gain=8
//#define CFG 0x8B     // one-shot, 16-bit, gain=8

#define AMB_INIT B01100000

void start_conversion(int chan);
void get_samples16(int chan);
void get_ambient();
void blinker();
void logger();

int ledPin = 13;
char msg[80];

float samples[4];
float temps[4];
float ambient = 0;
float amb_f = 0;
float timestamp = 0;

void loop()
{
  float idletime;
  
  // limit sample rate to once per second
  while ( (millis() % 1000) != 0 ) ;  
  timestamp = float(millis()) / 1000.;

  get_ambient();
  delay(10);

  for (int chan=0; chan<4; chan++) {
    start_conversion(chan);
    delay(100);
    get_samples16(chan);
    delay(10);
  }

  logger();
  blinker();

  idletime = float(millis()) / 1000.;
  idletime = 1.0 - (idletime - timestamp);
  if (idletime < 0.100) {
    Serial.print("# idle: ");
    Serial.println(idletime);
  }
}

void logger()
{
  Serial.print(timestamp);
  Serial.print(",");
  Serial.print(amb_f);
  Serial.print(",");
  for (int i=0; i<4; i++) {
    Serial.print(temps[i]);
    if (i < 3) Serial.print(",");
  }
  Serial.println();
}

void start_conversion(int chan)
{
  // try a workaround to improve reliability.
  // set chip to default settings
  Wire.beginTransmission(A_ADC);
  Wire.send(0x90);
  Wire.endTransmission();

  // set chip to actual desired settings
  Wire.beginTransmission(A_ADC);
  Wire.send(CFG | (chan << 5) );
  Wire.endTransmission();
}

void get_samples16(int expect)
{
  int stat1, stat2;
  int a, b, rdy1, rdy2, gain, chan, mode, ss;
  int32_t v;
  float f;

  // in continous mode, we should see RDY change in the 2nd
  // status byte since we have just read the data
  Wire.requestFrom(A_ADC, 4);
  if (Wire.available() != 4) {
    Serial.println("# ADC available != 4 ???");
    return; // an old/stale value is better than incorrect value
  }
  
  a = Wire.receive();
  b = Wire.receive();
  stat1 = Wire.receive();
  stat2 = Wire.receive();

  rdy1 = (stat1 >> 7) & 1;
  chan = (stat1 >> 5) & 3;
  mode = (stat1 >> 4) & 1;
  ss = (stat1 >> 2) & 3;
  gain = stat1 & 3;
  rdy2 = (stat2 >> 7) & 1;
  
  if (rdy1 != 0) {
    Serial.print("# rdy1 != 0? ");
    Serial.print(a); Serial.print(" ");
    Serial.print(b); Serial.print(" ");
    Serial.print(stat1); Serial.print(" ");
    Serial.println(stat2);
    return; // an old/stale value is better than incorrect value
  }

  if (rdy2 == 0) {
    Serial.print("# rdy2 == 0? ");
    Serial.print(a); Serial.print(" ");
    Serial.print(b); Serial.print(" ");
    Serial.print(stat1); Serial.print(" ");
    Serial.println(stat2);
    return; // an old/stale value is better than incorrect value
  }

  if (chan != expect) {
    Serial.print("# chan != expect: ");
    Serial.print(a); Serial.print(" ");
    Serial.print(b); Serial.print(" ");
    Serial.print(stat1); Serial.print(" ");
    Serial.println(stat2);
    return; // an old/stale value is better than incorrect value
  }

  if ( (stat1 & 0x1F) != (CFG & 0x1F) ) {
    Serial.print("# bad CFG: ");
    Serial.print(a); Serial.print(" ");
    Serial.print(b); Serial.print(" ");
    Serial.print(stat1); Serial.print(" ");
    Serial.println(stat2);
    return; // an old/stale value is better than incorrect value
  }

  if ( (stat1 & 0x7F) != (stat2 & 0x7F) ) {
    Serial.print("# stats mismatch: ");
    Serial.print(a); Serial.print(" ");
    Serial.print(b); Serial.print(" ");
    Serial.print(stat1); Serial.print(" ");
    Serial.println(stat2);
    return; // an old/stale value is better than incorrect value
  }

  v = a;
  v <<= 24;
  v >>= 16;
  v |= b;
  
  // convert to microvolts
  // divide by gain
  f = (float)v * 62.5;
  f /= (float) (1 << (CFG & 3) );
  samples[chan] = f;  // units = microvolts

  // temp in Celcius
  f /= MICROVOLT_TO_C;
  f += ambient;

  // convert to F
  f = (f * 1.8) + 32.;
  temps[chan] = f;
}

// FIXME: test temps below freezing.
void get_ambient()
{
  byte a, b;
  int32_t v;

  // Wire.beginTransmission(A_AMB);
  // Wire.send(0); // point to temperature reg.
  // Wire.endTransmission();

  Wire.requestFrom(A_AMB, 2);
  if (Wire.available() != 2) {
    Serial.println("# AMB available != 2 ???");
    return; // an old/stale value is better than incorrect value
  }
  a = Wire.receive();
  b = Wire.receive();

  v = a;
  
  // handle sign-bit
  v <<= 24;
  v >>= 24;

  ambient = v;
  ambient += (float)b / 256. ;

  // convert to F
  amb_f = (ambient * 1.8) + 32. ;

}

void blinker()
{
  static char on = 0;
  if (on) {
    digitalWrite(ledPin, HIGH);
//  digitalWrite(ledPin, LOW);
  } else {
      digitalWrite(ledPin, LOW);
//    digitalWrite(ledPin, HIGH);
  }
  on ^= 1;
}

void setup()
{
  byte a;
  pinMode(ledPin, OUTPUT);     
  Serial.begin(57600);

  while ( millis() < 3000) {
    blinker();
    delay(500);
  }

  sprintf(msg, "\n# %s: 4-chan TC", banner);
  Serial.println(msg);
  Serial.println("# time,ambient,T0,T1,T2,T3");
 
  while ( millis() < 6000) {
    blinker();
    delay(500);
  }

  Wire.begin();

  // configure mcp3424
  Wire.beginTransmission(A_ADC);
  Wire.send(CFG);
  Wire.endTransmission();

  // configure mcp9800.
  Wire.beginTransmission(A_AMB);
  Wire.send(1); // point to config reg
  Wire.send(AMB_INIT);
  Wire.endTransmission();

  // see if we can read it back.
  Wire.beginTransmission(A_AMB);
  Wire.send(1); // point to config reg
  Wire.endTransmission();
  Wire.requestFrom(A_AMB, 1);
  a = 0xff;
  if (Wire.available()) {
    a = Wire.receive();
  }
  if (a != AMB_INIT) {
    Serial.println("# Error configuring mcp9800");
  } else {
    Serial.println("# mcp9800 Config reg OK");
  }
  
  // set pointer to temperature register and
  // leave it there for all future readings.
  Wire.beginTransmission(A_AMB);
  Wire.send(0);
  Wire.endTransmission();
}

