import os
import json
import boto3

sfn = boto3.client('stepfunctions', end_url=os.environ.get('AWS_ENDPOINT_URL'))
STATE_MACHINE_ARN = os.environ['STATE_MACHINE_ARN']

def handler(event, context):
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']

        execution_input = {
            "bucket_in": bucket,
            "key_in": key,
        }

        response = sfn.start_execution(
            stateMachineArn=STATE_MACHINE_ARN,
            input=json.dumps(execution_input)
        )

        print(f"Started execution: {response['executionArn']}")

    return {"status": "triggered"} 