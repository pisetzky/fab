cmake_minimum_required(VERSION 3.22)
project(ChordPilot VERSION 1.0.0)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# JUCE: pass -DJUCE_DIR=/path/to/JUCE to use a local copy, otherwise it is downloaded.
if(DEFINED JUCE_DIR)
    add_subdirectory(${JUCE_DIR} JUCE)
else()
    include(FetchContent)
    FetchContent_Declare(JUCE GIT_REPOSITORY https://github.com/juce-framework/JUCE.git GIT_TAG 8.0.4 GIT_SHALLOW ON)
    FetchContent_MakeAvailable(JUCE)
endif()

set(CP_FORMATS VST3 Standalone)
if(APPLE)
    list(APPEND CP_FORMATS AU)
endif()

juce_add_plugin(ChordPilot
    COMPANY_NAME "Fab Audio"
    PLUGIN_MANUFACTURER_CODE FabA
    PLUGIN_CODE Chpd
    FORMATS ${CP_FORMATS}
    PRODUCT_NAME "ChordPilot"
    IS_SYNTH TRUE
    NEEDS_MIDI_INPUT TRUE
    NEEDS_MIDI_OUTPUT TRUE
    IS_MIDI_EFFECT FALSE
    EDITOR_WANTS_KEYBOARD_FOCUS TRUE
    COPY_PLUGIN_AFTER_BUILD FALSE
    VST3_CATEGORIES Instrument Synth
    AU_MAIN_TYPE kAudioUnitType_MusicDevice
    MICROPHONE_PERMISSION_ENABLED FALSE
    BUNDLE_ID com.fabaudio.chordpilot.desktop)

juce_generate_juce_header(ChordPilot)

target_sources(ChordPilot PRIVATE
    Source/Engine.cpp
    Source/PluginProcessor.cpp
    Source/PluginEditor.cpp)

target_compile_definitions(ChordPilot PUBLIC
    JUCE_WEB_BROWSER=0
    JUCE_USE_CURL=0
    JUCE_VST3_CAN_REPLACE_VST2=0
    JUCE_DISPLAY_SPLASH_SCREEN=0)

target_link_libraries(ChordPilot
    PRIVATE juce::juce_audio_utils juce::juce_audio_devices
    PUBLIC juce::juce_recommended_config_flags juce::juce_recommended_lto_flags juce::juce_recommended_warning_flags)

# Engine unit tests (plain C++)
add_executable(ChordPilotEngineTests Tests/EngineTests.cpp Source/Engine.cpp)
target_include_directories(ChordPilotEngineTests PRIVATE Source)
