#!/bin/bash

# Exit on error
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Generating gRPC code...${NC}"

# Activate virtual environment if it exists
if [ -f "venv/bin/activate" ]; then
    source venv/bin/activate
    echo "Activated virtual environment"
fi

# Install required tools if not installed
if ! command -v protoc &> /dev/null; then
    echo -e "${YELLOW}Installing protobuf compiler...${NC}"
    apt update
    apt install -y protobuf-compiler
fi

# Install required Python packages in venv
pip install grpcio-tools

# Generate Python gRPC code from proto file
python -m grpc_tools.protoc \
    --python_out=. \
    --grpc_python_out=. \
    --proto_path=. \
    xray_api.proto

echo "gRPC code generated successfully!"
echo "Generated files:"
echo "- xray_api_pb2.py"
echo "- xray_api_pb2_grpc.py"

# Fix imports in generated files
for file in xray_api_pb2*.py; do
    if [ -f "$file" ]; then
        # Fix relative imports to absolute imports
        sed -i 's/from \. import grpc/import grpc/' "$file"
        sed -i 's/from \. import xray_api_pb2/import xray_api_pb2/' "$file"
        echo "Fixed imports in $file"
    fi
done

echo -e "${GREEN}Successfully generated gRPC code!${NC}"

# Fix indentation in db.py
echo -e "${YELLOW}Fixing indentation in db.py...${NC}"
sed -i 's/^                logger.error/            logger.error/' db.py

echo -e "${GREEN}All done!${NC}"
