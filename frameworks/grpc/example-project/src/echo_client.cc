// Minimal gRPC client built against the PREBUILT gRPC package.
//   Usage: echo_client.exe ["your message"]

#include <iostream>
#include <memory>
#include <string>

#include <grpcpp/grpcpp.h>

#include "echo.grpc.pb.h"  // generated from proto/echo.proto at build time

int main(int argc, char** argv) {
  const std::string target("localhost:50051");
  auto channel =
      grpc::CreateChannel(target, grpc::InsecureChannelCredentials());
  std::unique_ptr<echo::Echo::Stub> stub = echo::Echo::NewStub(channel);

  echo::EchoRequest request;
  request.set_message(argc > 1 ? argv[1] : "hello from client");

  echo::EchoReply reply;
  grpc::ClientContext context;
  grpc::Status status = stub->Say(&context, request, &reply);

  if (status.ok()) {
    std::cout << "Server replied: " << reply.message() << std::endl;
    return 0;
  }
  std::cout << "RPC failed: " << status.error_code() << ": "
            << status.error_message() << std::endl;
  return 1;
}
