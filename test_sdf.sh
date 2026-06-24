#!/bin/bash
set -e

# Path to built binary
BINARY=".build/debug/SDForensics"

echo "=================================================="
echo "      SD FORENSICS SAFE VIRTUAL VERIFICATION      "
echo "=================================================="

# Step 1: Create a 10MB mock image file
echo -e "\n1. Spawning 10MB zero-filled mock device file..."
$BINARY mock-create sd_mock.img

# Step 2: Initialize and mark the virtual image
echo -e "\n2. Formatting and writing custom metadata block..."
$BINARY initialize sd_mock.img --name CAM_A_CARD_04 --owner RED_TEAM_PROD --cycles 12

# Step 3: Run forensic audit against the initialized image
echo -e "\n3. Performing forensic sector-level audit..."
$BINARY analyze sd_mock.img

# Step 4: Run diagnostic benchmarking
echo -e "\n4. Running speed throughput diagnostic..."
$BINARY benchmark sd_mock.img

echo -e "\n=================================================="
echo "          SAFE MOCK VERIFICATION SUCCESS          "
echo "=================================================="
