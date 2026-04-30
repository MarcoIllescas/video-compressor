provider "aws" {
    access_key = var.use_localstack ? "test" : var.aws_access_key
    secret_key = var.use_localstack ? "test" : var.aws_secret_key
    region     = "us-east-1"

    s3_use_path_style           = true
    skip_credentials_validation = var.use_localstack
    skip_metadata_api_check     = var.use_localstack
    skip_requesting_account_id  = var.use_localstack

    endpoints {
        s3              = var.use_localstack ? "http://localhost:4566" : null
        dynamodb        = var.use_localstack ? "http://localhost:4566" : null
        lambda          = var.use_localstack ? "http://localhost:4566" : null
        stepfunctions   = var.use_localstack ? "http://localhost:4566" : null
        iam             = var.use_localstack ? "http://localhost:4566" : null
        sns             = var.use_localstack ? "http://localhost:4566" : null
        sqs             = var.use_localstack ? "http://localhost:4566" : null
    }
}

# ------------------------------------------------------ #
#                        S3 Buckets                      #
# ------------------------------------------------------ #
resource "aws_s3_bucket" "input_videos_1080p" {
    bucket = "video-compressor-1080p"
}

resource "aws_s3_bucket" "output_videos_720p" {
    bucket = "video-compressor-720p"
}

resource "aws_s3_bucket" "output_videos_480p" {
    bucket = "video-compressor-480p"
}

# ------------------------------------------------------ #
#                         DynamoDB                       #
# ------------------------------------------------------ #
resource "aws_dynamodb_table" "video_metadata" {
    name           = "video_metadata"
    billing_mode   = "PAY_PER_REQUEST"
    hash_key       = "video_id"

    attribute {
        name = "video_id"
        type = "S"
    }
}

# ------------------------------------------------------ #
#               SNS & SQS for notifications              #
# ------------------------------------------------------ #
resource "aws_sns_topic" "video_ingest_fanout" {
    name = "video-ingest-fanout"
}

resource "aws_sns_topic_policy" "allow_s3_to_sns" {
    arn    = aws_sns_topic.video_ingest_fanout.arn

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Effect = "Allow"
            Principal = { Service = "s3.amazonaws.com" }
            Action = "SNS:Publish"
            Resource = aws_sns_topic.video_ingest_fanout.arn
            Condition = {
                ArnLike = {
                    "aws:SourceArn" = aws_s3_bucket.input_videos_1080p.arn
                }
            }
        }]
    })
}

resource "aws_s3_bucket_notification" "bucket_notification" {
    bucket = aws_s3_bucket.input_videos_1080p.id

    topic {
        topic_arn = aws_sns_topic.video_ingest_fanout.arn
        events    = ["s3:ObjectCreated:*"]
    }

    depends_on = [ aws_sns_topic_policy.allow_s3_to_sns ]
}

resource "aws_sqs_queue" "ffmpeg_processing_dlq" {
    name = "ffmpeg-processing-dlq"  
}

resource "aws_sqs_queue" "ffmpeg_processing_queue" {
    name = "ffmpeg-processing-queue"

    redrive_policy = jsonencode({
        deadLetterTargetArn = aws_sqs_queue.ffmpeg_processing_dlq.arn
        maxReceiveCount     = 3
    })
}

resource "aws_sqs_queue_policy" "allow_sns_to_sqs" {
    queue_url = aws_sqs_queue.ffmpeg_processing_queue.id

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Effect = "Allow"
            Principal = "*"
            Action = "SQS:SendMessage"
            Resource = aws_sqs_queue.ffmpeg_processing_queue.arn
            Condition = {
                ArnEquals = {
                    "aws:SourceArn" = aws_sns_topic.video_ingest_fanout.arn
                }
            }
        }]
    })
}

resource "aws_sns_topic_subscription" "ingest_to_sqs" {
    topic_arn = aws_sns_topic.video_ingest_fanout.arn
    protocol  = "sqs"
    endpoint  = aws_sqs_queue.ffmpeg_processing_queue.arn
}

resource "aws_sns_topic" "video_pipeline_alerts" {
    name = "video-pipeline-alerts"
}

resource "aws_lambda_event_source_mapping" "sqs_to_lambda" {
    event_source_arn  = aws_sqs_queue.ffmpeg_processing_queue.arn
    function_name     = aws_lambda_function.lambda_trigger.arn
    batch_size        = 1
}

# ------------------------------------------------------ #
#                         IAM Roles                      #
# ------------------------------------------------------ #
data "aws_iam_policy_document" "lambda_assume_role_policy" {
    statement {
        effect  = "Allow"
        actions = ["sts:AssumeRole"]
        principals {
            type        = "Service"
            identifiers = ["lambda.amazonaws.com"]
        }
    }
}

data "aws_iam_policy_document" "step_function_assume_role_policy" {
    statement {
        effect  = "Allow"
        actions = ["sts:AssumeRole"]
        principals {
            type        = "Service"
            identifiers = ["states.amazonaws.com"]
        }
    }
}

#             Lambda role for 720p processing            #
resource "aws_iam_role" "lambda_role_720p" {
    name                = "lambda-role-720p"
    assume_role_policy  = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_role_policy" "policy_lambda_720p" {
    name   = "lambda-policy-720p"
    role   = aws_iam_role.lambda_role_720p.id
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = ["s3:GetObject"]
                Effect = "Allow"
                Resource = "${aws_s3_bucket.input_videos_1080p.arn}/*"
            },
            {
                Action = ["s3:PutObject"]
                Effect = "Allow"
                Resource = "${aws_s3_bucket.output_videos_720p.arn}/*"
            },
        ]
    })
}

#             Lambda role for 480p processing            #
resource "aws_iam_role" "lambda_role_480p" {
    name                = "lambda-role-480p"
    assume_role_policy  = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_role_policy" "policy_lambda_480p" {
    name   = "lambda-policy-480p"
    role   = aws_iam_role.lambda_role_480p.id
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = ["s3:GetObject"]
                Effect = "Allow"
                Resource = "${aws_s3_bucket.input_videos_1080p.arn}/*"
            },
            {
                Action = ["s3:PutObject"]
                Effect = "Allow"
                Resource = "${aws_s3_bucket.output_videos_480p.arn}/*"
            },
        ]
    })
}

#                      Metadata role                     #
resource "aws_iam_role" "metadata_role" {
    name                = "metadata-role"
    assume_role_policy  = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_role_policy" "policy_metadata" {
    name   = "metadata-policy"
    role   = aws_iam_role.metadata_role.id
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = ["s3:GetObject", "s3:HeadObject"]
                Effect = "Allow"
                Resource = [
                    "${aws_s3_bucket.input_videos_1080p.arn}/*",
                    "${aws_s3_bucket.output_videos_720p.arn}/*",
                    "${aws_s3_bucket.output_videos_480p.arn}/*"
                ]
            },
            {
                Action = ["dynamodb:PutItem"]
                Effect = "Allow"
                Resource = "${aws_dynamodb_table.video_metadata.arn}"
            },
        ]
    })
}

#                   Step Function role                   #
resource "aws_iam_role" "step_function_role" {
    name                = "step-function-role"
    assume_role_policy  = data.aws_iam_policy_document.step_function_assume_role_policy.json
}

resource "aws_iam_role_policy" "step_function_policy" {
    name = "step-function-lambda-invoke-policy"
    role = aws_iam_role.step_function_role.id
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = ["lambda:InvokeFunction"]
                Effect = "Allow"
                Resource = [
                    aws_lambda_function.lambda_720p.arn,
                    aws_lambda_function.lambda_480p.arn,
                    aws_lambda_function.lambda_metadata.arn,
                    aws_lambda_function.lambda_notification.arn
                ]
            }
        ]
    })
}

#                       Trigger role                     #
resource "aws_iam_role" "trigger_role" {
    name                = "trigger-role"
    assume_role_policy  = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_role_policy" "policy_trigger" {
    name   = "trigger-policy"
    role   = aws_iam_role.trigger_role.id
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Action = ["states:StartExecution"]
                Effect = "Allow"
                Resource = aws_sfn_state_machine.video_pipeline_sfn.arn
            }
        ]
    })
}

resource "aws_iam_role_policy" "policy_trigger_sqs" {
    name   = "trigger-sqs-policy"
    role   = aws_iam_role.trigger_role.id

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Action = [
                "sqs:ReceiveMessage", 
                "sqs:DeleteMessage", 
                "sqs:GetQueueAttributes"
            ]
            Effect = "Allow"
            Resource = aws_sqs_queue.ffmpeg_processing_queue.arn
        }]
    })
}

#                    Notification role                   #
resource "aws_iam_role" "role_notification" {
    name               = "role-lambda-notification"
    assume_role_policy = data.aws_iam_policy_document.lambda_assume_role_policy.json
}

resource "aws_iam_role_policy" "policy_notification" {
    name = "policy-notification-sns"
    role = aws_iam_role.role_notification.id
    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Action   = "sns:Publish"
            Effect   = "Allow"
            Resource = aws_sns_topic.video_pipeline_alerts.arn
        }]
    })
}

# ------------------------------------------------------ #
#                 Packing Lambda functions               #
# ------------------------------------------------------ #
data "archive_file" "zip_lambda_720p" {
    type        = "zip"
    source_dir  = "../src/lambda_720p"
    output_path = "lambda_720p.zip"
}

data "archive_file" "zip_lambda_480p" {
    type        = "zip"
    source_dir  = "../src/lambda_480p"
    output_path = "lambda_480p.zip"
}

data "archive_file" "zip_lambda_metadata" {
    type        = "zip"
    source_dir  = "../src/lambda_metadata"
    output_path = "lambda_metadata.zip"
}

data "archive_file" "zip_lambda_trigger" {
    type        = "zip"
    source_dir  = "../src/lambda_trigger"
    output_path = "lambda_trigger.zip"
}

data "archive_file" "zip_notification" {
    type        = "zip"
    source_dir  = "../src/lambda_notification"
    output_path = "lambda_notification.zip"
}

# ------------------------------------------------------ #
#                 Creating Lambda functions              #
# ------------------------------------------------------ #
resource "aws_lambda_function" "lambda_720p" {
    filename         = data.archive_file.zip_lambda_720p.output_path
    source_code_hash = data.archive_file.zip_lambda_720p.output_base64sha256
    function_name    = "video-convert-720p"
    role             = aws_iam_role.lambda_role_720p.arn
    handler          = "app.handler"
    runtime          = "python3.9"
    timeout          = 60
    memory_size      = 512

    environment {
        variables = {
            BUCKET_OUT       = aws_s3_bucket.output_videos_720p.bucket
            RESOLUTION       = "1280x720"
        }
    }
}

resource "aws_lambda_function" "lambda_480p" {
    filename         = data.archive_file.zip_lambda_480p.output_path
    source_code_hash = data.archive_file.zip_lambda_480p.output_base64sha256
    function_name    = "video-convert-480p"
    role             = aws_iam_role.lambda_role_480p.arn
    handler          = "app.handler"
    runtime          = "python3.9"
    timeout          = 60
    memory_size      = 512

    environment {
        variables = {
            BUCKET_OUT       = aws_s3_bucket.output_videos_480p.bucket
            RESOLUTION       = "854x480"
        }
    }
}

resource "aws_lambda_function" "lambda_metadata" {
    filename         = data.archive_file.zip_lambda_metadata.output_path
    source_code_hash = data.archive_file.zip_lambda_metadata.output_base64sha256
    function_name    = "save-video-metadata"
    role             = aws_iam_role.metadata_role.arn
    handler          = "app.handler"
    runtime          = "python3.9"
    timeout          = 10
    memory_size      = 128
}

resource "aws_lambda_function" "lambda_trigger" {
    filename         = data.archive_file.zip_lambda_trigger.output_path
    source_code_hash = data.archive_file.zip_lambda_trigger.output_base64sha256
    function_name    = "trigger-pipeline"
    role             = aws_iam_role.trigger_role.arn
    handler          = "app.handler"
    runtime          = "python3.9"

    environment {
        variables = {
            STATE_MACHINE_ARN = aws_sfn_state_machine.video_pipeline_sfn.arn
        }
    }
}

resource "aws_lambda_function" "lambda_notification" {
    filename         = data.archive_file.zip_notification.output_path
    source_code_hash = data.archive_file.zip_notification.output_base64sha256
    function_name    = "send-notification"
    role             = aws_iam_role.role_notification.arn
    handler          = "app.handler"
    runtime          = "python3.9"
    
    environment {
        variables = {
            SNS_TOPIC_ARN    = aws_sns_topic.video_pipeline_alerts.arn
        }
    }
}

# ------------------------------------------------------ #
#                 Creating State Machine                 #
# ------------------------------------------------------ #
resource "aws_sfn_state_machine" "video_pipeline_sfn" {
    name     = "video-processing-pipeline"
    role_arn = aws_iam_role.step_function_role.arn

    definition = jsonencode({
        StartAt = "ParallelProcessing"
        States = {
            "ParallelProcessing" = {
                Type     = "Parallel"
                Next     = "SaveMetadata"
                Branches = [
                    {
                        StartAt = "ConvertTo720p"
                        States = {
                            "ConvertTo720p" = {
                                Type     = "Task"
                                Resource = aws_lambda_function.lambda_720p.arn
                                End      = true
                            }
                        }
                    },
                    {
                        StartAt = "ConvertTo480p"
                        States = {
                            "ConvertTo480p" = {
                                Type     = "Task"
                                Resource = aws_lambda_function.lambda_480p.arn
                                End      = true
                            }
                        }
                    }
                ]
            },
            "SaveMetadata" = {
                Type     = "Task"
                Resource = aws_lambda_function.lambda_metadata.arn
                Next     = "SendNotification"
            },
            "SendNotification" = {
                Type     = "Task"
                Resource = aws_lambda_function.lambda_notification.arn
                End      = true
            }
        }
    })
}

# ------------------------------------------------------ #
#                      SIMULATED EMAIL                   #
# ------------------------------------------------------ #
resource "aws_sns_topic_subscription" "email_subscription" {
    topic_arn = aws_sns_topic.video_pipeline_alerts.arn
    protocol = "email"
    endpoint = "illescasnav@gmail.com"
}