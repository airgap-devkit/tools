// SPDX-License-Identifier: Apache-2.0
// Minimal gRPC client built against the PREBUILT gRPC package.
//   Usage: echo_client.exe ["your message"]

#include <cstdlib>
#include <fstream>
#include <iostream>
#include <memory>
#include <sstream>
#include <string>

#include <grpcpp/grpcpp.h>

#include "echo.grpc.pb.h" // generated from proto/echo.proto at build time

// Use TLS when a PEM root-certificate file is supplied via GRPC_TLS_ROOT_CERT;
// fall back to an insecure channel for the local loopback demo.
static std::shared_ptr<grpc::ChannelCredentials> MakeChannelCredentials() {
  if (const char *ca_path = std::getenv("GRPC_TLS_ROOT_CERT")) {
    std::ifstream ca_file(ca_path);
    std::stringstream ca_buf;
    ca_buf << ca_file.rdbuf();
    grpc::SslCredentialsOptions ssl_opts;
    ssl_opts.pem_root_certs = ca_buf.str();
    return grpc::SslCredentials(ssl_opts);
  }
  return grpc::InsecureChannelCredentials();
}

int main(int argc, char **argv) {
  const std::string target("localhost:50051");
  auto channel = grpc::CreateChannel(target, MakeChannelCredentials());
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
