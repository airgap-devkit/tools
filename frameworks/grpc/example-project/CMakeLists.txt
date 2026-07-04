# Starter gRPC project. Copy this whole folder anywhere and make it your own.
# It consumes the PREBUILT gRPC package via find_package -- it does not build gRPC.
#
# Configure with a preset (recommended, works in VS Code + Visual Studio):
#   cmake --preset vs2026-v143
#   cmake --build --preset vs2026-v143-release
# ...or manually -- see README.md.
cmake_minimum_required(VERSION 3.16)
project(grpc_example_project CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(MSVC)
  add_definitions(-D_WIN32_WINNT=0x600)
  # The prebuilt libs use the static CRT (/MT). The shipped grpc-toolchain.cmake
  # sets this; we repeat it so a plain configure (no toolchain file) still matches.
  if(NOT CMAKE_MSVC_RUNTIME_LIBRARY)
    set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
  endif()
endif()

# Locate the prebuilt package (found via CMAKE_PREFIX_PATH = your GRPC_ROOT).
find_package(Protobuf CONFIG REQUIRED)
find_package(gRPC CONFIG REQUIRED)
message(STATUS "Using protobuf ${Protobuf_VERSION} / gRPC ${gRPC_VERSION}")

# --- Generate C++ from proto/echo.proto at build time ------------------------
get_filename_component(echo_proto "proto/echo.proto" ABSOLUTE)
get_filename_component(echo_proto_dir "${echo_proto}" PATH)

set(gen "${CMAKE_CURRENT_BINARY_DIR}")
set(echo_srcs "${gen}/echo.pb.cc" "${gen}/echo.grpc.pb.cc")
set(echo_hdrs "${gen}/echo.pb.h" "${gen}/echo.grpc.pb.h")

add_custom_command(
  OUTPUT ${echo_srcs} ${echo_hdrs}
  COMMAND protobuf::protoc
  ARGS --grpc_out "${gen}"
       --cpp_out "${gen}"
       -I "${echo_proto_dir}"
       --plugin=protoc-gen-grpc="$<TARGET_FILE:gRPC::grpc_cpp_plugin>"
       "${echo_proto}"
  DEPENDS "${echo_proto}")

add_library(echo_proto ${echo_srcs} ${echo_hdrs})
target_include_directories(echo_proto PUBLIC "${gen}")
target_link_libraries(echo_proto PUBLIC gRPC::grpc++ protobuf::libprotobuf)

# --- The two executables -----------------------------------------------------
add_executable(echo_server src/echo_server.cc)
target_link_libraries(echo_server PRIVATE echo_proto)

add_executable(echo_client src/echo_client.cc)
target_link_libraries(echo_client PRIVATE echo_proto)
