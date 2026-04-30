import os
import boto3

sns = boto3.client('sns', endpoint_url=os.environ.get('AWS_ENDPOINT_URL'))
TOPIC_ARN = os.environ['SNS_TOPIC_ARN']

def handler(event, context):
    video_id = event.get('video_id', 'unknown')

    message = (
        f"Processing successful!\n\n"
        f"Video ID: {video_id} processed successfully.\n"
        f"Metadata registered successfully in DynamoDB.\n"
        f"Final status: Success"
    )

    sns.publish(
        TopicArn=TOPIC_ARN,
        Subject='Video Pipeline Alert',
        Message=message
    )

    print(f"Notification sent for video ID: {video_id}")

    return { "status": "notified" }