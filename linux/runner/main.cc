#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <string>

#include "my_application.h"

// Force the Skia rendering backend on Linux.
//
// The engine's Linux default is Impeller (it logs "Using the Impeller
// rendering backend (OpenGLESSDF)"), and on the NVIDIA proprietary driver
// that path segfaults in the rasterizer thread (`io.flutter.rast`) a few
// seconds into video playback — reproducible on an RTX 3070 / driver 610.57,
// with the crash inside libflutter_linux_gtk.so and no Dart frames on the
// stack. Skia does not crash, and it is also what lets media_kit run its
// hardware video output here (see `enableHardwareAcceleration` in
// `lib/features/watch/watch_screen.dart`); under Impeller that had to fall
// back to software rendering, which is what made playback stutter.
//
// The engine reads its switches from the environment as
// FLUTTER_ENGINE_SWITCHES (a count) plus FLUTTER_ENGINE_SWITCH_<N>, indexed
// from 1 — the same channel `flutter run` uses to pass `--no-enable-impeller`
// (see `_computeEnvironment` in flutter_tools' `desktop_device.dart`). So
// this appends one more switch to whatever is already there rather than
// replacing the set, which would drop the tool's own flags (dart profiling,
// the VM Service port) and break `flutter run`.
//
// An explicit choice always wins: if any switch already mentions
// enable-impeller, this leaves the environment untouched, so
// `flutter run --enable-impeller` can still be used to retest the Impeller
// path once the driver bug is fixed.
static void DisableImpellerByDefault() {
  const char* count_str = getenv("FLUTTER_ENGINE_SWITCHES");
  int count = count_str != nullptr ? atoi(count_str) : 0;
  if (count < 0) {
    count = 0;
  }

  for (int i = 1; i <= count; i++) {
    std::string name = "FLUTTER_ENGINE_SWITCH_" + std::to_string(i);
    const char* value = getenv(name.c_str());
    if (value != nullptr && strstr(value, "enable-impeller") != nullptr) {
      return;  // caller asked for a specific backend; respect it
    }
  }

  std::string name = "FLUTTER_ENGINE_SWITCH_" + std::to_string(count + 1);
  setenv(name.c_str(), "enable-impeller=false", 1);
  setenv("FLUTTER_ENGINE_SWITCHES", std::to_string(count + 1).c_str(), 1);
}

int main(int argc, char** argv) {
  DisableImpellerByDefault();

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
