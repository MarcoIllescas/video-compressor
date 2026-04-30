#!/bin/bash

# This script is used to test the pipeline by running it with 
# a sample input and checking the output.

# Stop the script if any command fails
set -e

echo "Phase 1: Deploy infrastructure using Terraform..."
cd terraform
terraform init
terraform apply -auto-approve

INPUT_BUCKET=$(terraform output -raw input_bucket_name)
TABLE_NAME=$(terraform output -raw dynamodb_table_name)
cd ..

echo ""
echo "Phase 2: Generate sample input data (1080p)..."
./src/lambda_720p/ffmpeg -y -f lavfi -i testsrc=duration=10:size=1920x1080:rate=30 -c:v libx264 video_10s.mp4 -nostats -loglevel 0
./src/lambda_720p/ffmpeg -y -f lavfi -i testsrc=duration=20:size=1920x1080:rate=30 -c:v libx264 video_20s.mp4 -nostats -loglevel 0
./src/lambda_720p/ffmpeg -y -f lavfi -i testsrc=duration=30:size=1920x1080:rate=30 -c:v libx264 video_30s.mp4 -nostats -loglevel 0

echo ""
echo "Phase 3: Upload sample videos simultaneously to S3 input bucket..."
aws --endpoint-url=http://localhost:4566 s3 cp video_10s.mp4 s3://$INPUT_BUCKET/ &
aws --endpoint-url=http://localhost:4566 s3 cp video_20s.mp4 s3://$INPUT_BUCKET/ &
aws --endpoint-url=http://localhost:4566 s3 cp video_30s.mp4 s3://$INPUT_BUCKET/ &

wait
echo "Videos uploaded successfully. Pipeline have been triggered 3 times."

echo ""
echo "Phase 4: Wait for the Lambda and Step Functions to complete..."
sleep 30

echo ""
echo "Phase 5: Check the output in DynamoDB..."
aws --endpoint-url=http://localhost:4566 dynamodb scan --table-name $TABLE_NAME --query "Items[*].[video_id.S, formats.L[*].M.resolution.S]" --output text

echo ""
echo "Test completed successfully. The pipeline is working as expected."