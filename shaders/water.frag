#version 460 core
#include <flutter/runtime_effect.glsl>

// Agua en perspectiva: ondas, reflejo del cielo, brillo del sol, estela y niebla.
// Las coordenadas se invierten con la misma cámara que usa SceneCamera.

uniform vec2 uSize;
uniform float uHorizonY;
uniform float uFocal;
uniform float uCamHeight;
uniform float uDistance;
uniform float uTime;
uniform float uWaveAmp;
uniform float uWaveScale;
uniform float uSunX;
uniform float uLight;        // fuerza del brillo (0–1)
uniform vec3 uWaterNear;
uniform vec3 uWaterFar;
uniform vec3 uSkyHorizon;
uniform vec3 uSunColor;
uniform vec3 uFog;
uniform float uWakeStrength;
uniform float uSternZ;       // z de la popa: donde nace la estela

out vec4 fragColor;

float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
  // Acotar la celda: con z grande el seno del hash pierde precisión
  vec2 i = mod(floor(p), 289.0);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Dos octavas de ruido cuya frecuencia crece cerca de la cámara (z chico),
// así el agua cercana tiene detalle fino en vez de bloques gigantes.
float waveH(float x, float zw, float z) {
  float s = uWaveScale;
  float d = clamp(6.0 / z, 1.0, 6.0);
  float n = (vnoise(vec2(x, zw) * (0.8 * d) + uTime * 0.15) - 0.5) * 0.6
          + (vnoise(vec2(x, zw) * (2.6 * d) - uTime * 0.25) - 0.5) * 0.3;
  return sin(zw / s + uTime * 0.6) * 0.6
       + sin((zw * 0.7 + x * 1.3) / s + uTime * 0.9) * 0.4
       + n;
}

void main() {
  vec2 px = FlutterFragCoord().xy;
  if (px.y <= uHorizonY + 0.5) {
    fragColor = vec4(0.0);
    return;
  }
  float z = uFocal * uCamHeight / (px.y - uHorizonY);
  float x = (px.x - uSize.x * 0.5) * z / uFocal;
  float zw = z + uDistance;

  float h = waveH(x, zw, z);

  vec3 col = mix(uWaterNear, uWaterFar, smoothstep(2.0, 120.0, z));
  col *= 1.0 + h * uWaveAmp * 0.25;

  // Fresnel: más espejo cuanto más rasante la mirada (lejos)
  float fres = pow(1.0 - clamp(uCamHeight / length(vec2(z, uCamHeight)), 0.0, 1.0), 3.0);
  col = mix(col, uSkyHorizon, fres * 0.6);

  // Brillo del sol/luna: columna bajo el astro, solo en las crestas
  float colW = 25.0 + z * 4.0;
  float dxs = (px.x - uSunX) / colW;
  float column = exp(-dxs * dxs) * 0.4;
  float crest = smoothstep(0.3, 0.9, h * 0.5 + 0.5);
  // Destellos suaves (sin celdas visibles), más finos cerca de la cámara
  float sparkle = smoothstep(0.45, 0.95, vnoise(vec2(x, zw) * (3.0 + 12.0 / z) + uTime * 0.8));
  float glitter = column * crest * (0.25 + 0.75 * sparkle) * uLight;
  col += uSunColor * glitter * 0.9;

  // Estela: dos líneas de espuma en V y turbulencia en el centro
  if (z < uSternZ) {
    float back = uSternZ - z;
    float wv = 0.3 + back * 0.35;
    float edge = 1.0 - smoothstep(0.0, 0.35, abs(abs(x) - wv));
    float center = (1.0 - smoothstep(0.0, 0.5, abs(x))) * 0.6;
    float fade = 1.0 - smoothstep(0.0, uSternZ, back);
    float n = 0.6 + 0.4 * vnoise(vec2(x * 3.0, zw * 2.0) + uTime);
    float foam = (edge + center) * fade * uWakeStrength * n;
    col = mix(col, vec3(1.0), clamp(foam, 0.0, 1.0) * 0.35);
  }

  col = mix(col, uFog, smoothstep(80.0, 400.0, z));
  fragColor = vec4(col, 1.0);
}
