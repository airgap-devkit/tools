// Minimal gRPC server built against the PREBUILT gRPC package.
// Nothing here depends on how gRPC was built -- you just include the headers
// and link the gRPC::grpc++ target (CMake handles the ~200 transitive libs).

#include <iostream>
#include <memory>
#include <string>

#include <grpcpp/grpcpp.h>

#include "echo.grpc.pb.h" // generated from proto/echo.proto at build time

class EchoServiceImpl final : public echo::Echo::Service {
  grpc::Status Say(grpc::ServerContext * /*context*/,
                   const echo::EchoRequest *request,
                   echo::EchoReply *reply) override {
    reply->set_message("You said: " + request->message());
    return grpc::Status::OK;
  }
};

int main() {
  const std::string address("0.0.0.0:50051");
  EchoServiceImpl service;

  grpc::ServerBuilder builder;
  builder.AddListeningPort(address, grpc::InsecureServerCredentials());
  builder.RegisterService(&service);

  std::unique_ptr<grpc::Server> server(builder.BuildAndStart());
  std::cout << "Echo server listening on " << address << std::endl;
  server->Wait();
  return 0;
}
