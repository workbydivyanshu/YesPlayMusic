cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Force libgcc_s.so.1 to precede libflutter_linux_gtk.so in DT_NEEDED so that
# LuaJIT inside system libmpv (loaded by media_kit) resolves _Unwind_* symbols
# from libgcc_s instead of Flutter's bundled LLVM unwinder, preventing SIGSEGV
# on track switches (qier222/YesPlayMusic#2532).
include(CheckCXXSourceCompiles)
set(CMAKE_REQUIRED_FLAGS "-Wl,--push-state,--no-as-needed,-lgcc_s,--pop-state")
check_cxx_source_compiles("int main() { return 0; }" HAVE_LIBGCC_S)
unset(CMAKE_REQUIRED_FLAGS)
if(HAVE_LIBGCC_S)
  target_link_options(${BINARY_NAME} PRIVATE
    "LINKER:--push-state,--no-as-needed,-lgcc_s,--pop-state"
  )
endif()

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
