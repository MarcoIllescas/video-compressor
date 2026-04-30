import os
import json
import boto3

sfn = boto3.client('stepfunctions', end_url=os.environ.get('AWS_ENDPOINT_URL'))
STATE_MACHINE_ARN = os.environ['STATE_MACHINE_ARN']

def handler(event, context):
    for record in event['Records']:
        sqs_body = json.loads(record['body'])

        sns_message = json.loads(sqs_body['Message'])

        for s3_record in sns_message['Records']:
            bucket = s3_record['s3']['bucket']['name']
            key = s3_record['s3']['object']['key']

            execution_input = {
                "bucket_in": bucket,
                "key_in": key
            }

            sfn.start_execution(
                stateMachineArn=STATE_MACHINE_ARN,
                input=json.dumps(execution_input)
            )
            print(f"Pipeline execution started for: {key}")

    return { "status": "triggered_from_sqs" }