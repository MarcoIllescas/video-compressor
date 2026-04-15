import os
import boto3
from datetime import datetime

dynamodb = boto3.resource('dynamodb', endpoint_url=os.environ.get('AWS_ENDPOINT_URL'))
s3 = boto3.client('s3', endpoint_url=os.environ.get('AWS_ENDPOINT_URL'))

def handler(event, context):
    table = dynamodb.Table('VideoMetadata')
    video_id = event[0]['key']

    metadata = {
        'video_id': video_id,
        'timestamp': datetime.now().isoformat(),
        'formats': []
    }

    for result in event:
        response = s3.head_object(Bucket=result['bucket'], Key=result['key'])
        metadata['formats'].append({
            'resolution': result['resolution'],
            'size_bytes': response['ContentLength'],
            's3_path': f"s3://{result['bucket']}/{result['key']}"
        })

    table.put_item(Item=metadata)

    return {'status': 'metadata_saved', 'video_id': video_id}