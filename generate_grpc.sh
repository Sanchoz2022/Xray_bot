#!/bin/bash

# Exit on error
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Generating gRPC code...${NC}"

# Install required tools if not installed
if ! command -v protoc &> /dev/null; then
    echo -e "${YELLOW}Installing protobuf compiler...${NC}"
    apt update
    apt install -y protobuf-compiler
fi

# Install Python gRPC tools
pip install grpcio-tools

# Generate Python gRPC code
echo -e "${GREEN}Generating Python gRPC code...${NC}"
python -m grpc_tools.protoc -I. --python_out=. --grpc_python_out=. xray_api.proto

# Fix imports in generated files
for file in xray_api_pb2*.py; do
    sed -i 's/^import /from . import /' "$file"
done

echo -e "${GREEN}Successfully generated gRPC code!${NC}"

# Fix indentation in db.py
echo -e "${YELLOW}Fixing indentation in db.py...${NC}"
sed -i 's/^                logger.error/            logger.error/' db.py

echo -e "${GREEN}All done!${NC}"
