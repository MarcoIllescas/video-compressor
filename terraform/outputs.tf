output "input_bucket_name" {
    description = "Bucket name where input videos are stored."
    value       = aws_s3_bucket.input_videos_1080p.bucket
}

output "dynamodb_table_name" {
    description = "Name of the DynamoDB table for video metadata."
    value       = aws_dynamodb_table.video_metadata.name
}